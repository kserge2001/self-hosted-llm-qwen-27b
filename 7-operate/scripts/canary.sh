#!/usr/bin/env bash
# Canary release of a new model version: a second vLLM release (vllm-canary, one replica) gets 10%
# of the gateway traffic. Then you promote it (it becomes the main version) or roll it back.
#
# Every step is a Git commit on a new branch. You push it, open a pull request, and merging it is
# the change: Argo CD applies what Git says. So every step is reviewed and can be reverted.
#
#   (model-promote with rollout "canary")      0. pull request with the canary values; MLflow alias "approved"
#   bash 7-operate/scripts/canary.sh start     1. canary ApplicationSet, no traffic yet
#   kubectl apply -f 4-serving/argocd/serving-canary.yaml   (after merging step 1; wait until Ready)
#   bash 7-operate/scripts/canary.sh route     2. gateway: main weight 90, canary weight 10
#   (compare errors, latency and answers in Grafana and Langfuse)
#   bash 7-operate/scripts/canary.sh promote   3a. the main release takes the canary's version; MLflow alias "champion"
#   bash 7-operate/scripts/canary.sh rollback  3b. the main release stays as it is; "champion" does not change
#   bash 7-operate/scripts/canary.sh cleanup   4. right after merging 3a or 3b: delete the canary
#
# Needs git, yq v4 (https://github.com/mikefarah/yq, v4.54.1 checked 2026-10-28), kubectl for cleanup, and for
# promote Python with 3-model-pipeline/scripts/requirements.txt and your AWS login. Run from the repository's main folder.
set -euo pipefail

MAIN_VALUES=4-serving/values/qwen3.8-27b.yaml
CANARY_VALUES=4-serving/values/qwen3.8-27b-canary.yaml
MAIN_APP=4-serving/argocd/serving.yaml
CANARY_APP=4-serving/argocd/serving-canary.yaml
GATEWAY_VALUES=5-gateway/litellm/values.yaml             # LiteLLM config is under proxy_config
CANARY_ID=astra-canary                                   # LiteLLM deployment id that marks the canary entry
CANARY_API_BASE=http://vllm-canary.serving.svc:8000/v1   # the chart names the Service after the release
MODEL_NAME=qwen3.8-27b                                   # MLflow registered model name
PYTHON=${PYTHON:-python3}                                # with mlflow-skinny and sagemaker-mlflow installed

command -v yq >/dev/null || { echo "yq v4 is needed: https://github.com/mikefarah/yq"; exit 1; }
[ -f "$MAIN_VALUES" ] || { echo "Run from the repository's main folder."; exit 1; }

# A clean tree, so the commit holds only this change.
new_branch() {
  if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "Commit or stash your changes first."; exit 1
  fi
  git switch -c "$1"
}

next() {
  echo
  echo "Committed on branch $(git branch --show-current). Next:"
  echo "  git push -u origin HEAD   then open a pull request. Merging it is the change."
  echo "$1"
}

short_rev() { yq '.model.revision' "$CANARY_VALUES" | cut -c1-12; }

start() {
  # The model pipeline (rollout: canary) wrote the values file, so start only adds the ApplicationSet.
  [ -f "$CANARY_VALUES" ] || { echo "No $CANARY_VALUES. Run model-promote with rollout canary and merge its pull request."; exit 1; }
  [ ! -f "$CANARY_APP" ] || { echo "A canary already exists: $CANARY_APP"; exit 1; }
  new_branch "canary/start-$(short_rev)"

  # The canary ApplicationSet is a copy of the main one, as 4-serving/argocd/serving.yaml describes.
  # canary: true makes the chart run one replica and skip what the main release already owns.
  yq '
    .metadata.name = "serving-canary"
    | .spec.template.metadata.name = "serving-canary"
    | .spec.template.spec.source.helm.releaseName = "vllm-canary"
    | .spec.template.spec.source.helm.valueFiles = ["../../values/qwen3.8-27b-canary.yaml"]
    | .spec.template.spec.source.helm.valuesObject.canary = true
    | . head_comment = "Canary of a model upgrade, made by 7-operate/scripts/canary.sh. Removed by promote or rollback."
  ' "$MAIN_APP" > "$CANARY_APP"

  # No cap on the main release: the GPU NodePool allows 4 GPUs, so the main release at its
  # KEDA maximum (3) plus the canary (1) still fit.

  git add "$CANARY_APP"
  git commit -m "canary: vLLM release for revision $(yq '.model.revision' "$CANARY_VALUES") (no traffic yet)"
  next "After the merge:  kubectl apply -f $CANARY_APP
Wait until the vllm-canary pod is Ready (the weights load in about 10 minutes):
  kubectl -n serving get pods -w
Then run:  bash 7-operate/scripts/canary.sh route"
}

route() {
  [ -f "$CANARY_VALUES" ] || { echo "No canary. Run start first."; exit 1; }
  local routed
  routed=$(ID=$CANARY_ID yq '[.proxy_config.model_list[] | select(.model_info.id == strenv(ID))] | length' "$GATEWAY_VALUES")
  [ "$routed" = 0 ] || { echo "The canary already gets traffic."; exit 1; }
  new_branch "canary/route-$(short_rev)"
  # LiteLLM's default routing (simple-shuffle) splits traffic by `weight`: 90 + 10 means 10% to the canary.
  # The canary entry is a copy of the main entry with another api_base, so key, timeout and price stay the same.
  ID=$CANARY_ID BASE=$CANARY_API_BASE yq -i '
    (.proxy_config.model_list[] | select(.model_name == "astra") | .litellm_params.weight) = 90
    | .proxy_config.model_list += [
        .proxy_config.model_list[] | select(.model_name == "astra")
        | .litellm_params.api_base = strenv(BASE)
        | .litellm_params.weight = 10
        | .model_info.id = strenv(ID)
      ]' "$GATEWAY_VALUES"
  git add "$GATEWAY_VALUES"
  git commit -m "canary: send 10% of astra traffic to the canary"
  next "After the merge, Argo CD rolls the gateway pods with the new config.
Compare the canary with the main release for at least one busy hour, then run promote or rollback."
}

# Takes the canary out of the gateway and its files out of Git.
unroute() {
  ID=$CANARY_ID yq -i '
    del(.proxy_config.model_list[] | select(.model_info.id == strenv(ID)))
    | del(.proxy_config.model_list[] | select(.model_name == "astra") | .litellm_params.weight)' "$GATEWAY_VALUES"
  git rm -q "$CANARY_VALUES" "$CANARY_APP"
  git add "$GATEWAY_VALUES" "$MAIN_VALUES"
}

# Moves the alias champion to the version the pipeline marked "approved", after checking that it is the
# revision the canary served. So the registry says what serves all traffic.
# MLflow is the SageMaker MLflow App, so no port-forward: spec.py (the pipeline's own helper) finds the
# app, and sagemaker-mlflow signs each call with your AWS login (needs sagemaker:CallMlflowAppApi).
set_champion() {
  REV=$1 NAME=$MODEL_NAME "$PYTHON" - <<'PY'
import os
import sys

sys.path.insert(0, "3-model-pipeline/scripts")
import spec  # noqa: E402
from mlflow import MlflowClient  # noqa: E402

name, rev = os.environ["NAME"], os.environ["REV"]
spec.use_mlflow()
client = MlflowClient()
try:
    mv = client.get_model_version_by_alias(name, "approved")
except Exception as e:
    sys.exit(f"Could not read the MLflow alias approved ({e}). Set champion by hand.")
tagged = mv.tags.get("revision")
if tagged != rev:
    sys.exit(f"MLflow alias approved is revision {tagged}, the canary is {rev}. Set champion by hand.")
try:
    client.set_registered_model_alias(name, "champion", mv.version)
except Exception as e:
    sys.exit(f"Could not set the MLflow alias champion ({e}). Set it by hand.")
print(f"MLflow: {name} version {mv.version} is now 'champion'.")
PY
}

promote() {
  [ -f "$CANARY_VALUES" ] || { echo "No canary to promote."; exit 1; }
  local rev uri
  rev=$(yq '.model.revision' "$CANARY_VALUES")
  uri=$(yq '.model.uri' "$CANARY_VALUES")
  new_branch "canary/promote-$(short_rev)"
  # The main release now loads the canary's weights, one replica at a time.
  REV=$rev URI=$uri yq -i '.model.revision = strenv(REV) | .model.uri = strenv(URI)' "$MAIN_VALUES"
  unroute
  git commit -m "canary: promote revision $rev to the main release"
  # A failed MLflow call must not hide the next steps: the Git commit is already made.
  set_champion "$rev" || echo "The commit is made; only the MLflow alias is missing."
  next "Right after the merge run:  bash 7-operate/scripts/canary.sh cleanup
The main release's rolling update may need the canary's GPU (the NodePool allows 4)."
}

rollback() {
  [ -f "$CANARY_VALUES" ] || { echo "No canary to roll back."; exit 1; }
  new_branch "canary/rollback-$(short_rev)"
  # The main release keeps its version. It served 90% of the traffic the whole time.
  # MLflow is not touched: champion stays on the version that serves.
  unroute
  git commit -m "canary: roll back, all traffic to the main release"
  next "Right after the merge run:  bash 7-operate/scripts/canary.sh cleanup"
}

cleanup() {
  # The canary ApplicationSet was added with kubectl apply, so removing its file from Git does not delete it.
  # Its Application has the Argo CD resources finalizer, so the canary pod goes too and the GPU is freed.
  kubectl -n argocd delete applicationset serving-canary --ignore-not-found --wait=true
  kubectl -n argocd wait --for=delete application/serving-canary --timeout=10m 2>/dev/null || true
  echo "Canary removed."
}

case "${1:-}" in
  start) start ;;
  route) route ;;
  promote) promote ;;
  rollback) rollback ;;
  cleanup) cleanup ;;
  *) sed -n '2,18p' "$0"; exit 1 ;;
esac
