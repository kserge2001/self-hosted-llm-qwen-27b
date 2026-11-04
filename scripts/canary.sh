#!/usr/bin/env bash
# Canary release of a new model version. A second vLLM release, "vllm-canary", runs the new
# revision on its own GPU node. The gateway (LiteLLM) sends it a share of the traffic. You raise the
# share step by step while you compare it with the main release, then promote it or roll it back.
#
# Every step changes files and makes a Git commit. You push it; Argo CD applies what Git says.
# (In a company, each push is a pull request that someone reviews.)
#
#   1. load the new revision into S3 first:   change revision in model/qwen3.8-27b.yaml, run the Job in model/
#   bash scripts/canary.sh start <revision>   2. canary release with the new revision, no traffic yet
#   bash scripts/canary.sh weight 10          3. gateway: main 90, canary 10   (later: 25, 50 ...)
#   bash scripts/load.sh 200                  4. send test traffic; compare the two in Grafana and MLflow
#   bash scripts/canary.sh promote            5a. the main release rolls to the new revision; canary removed
#   bash scripts/canary.sh rollback           5b. the main release stays as it is; canary removed
#
# Needs git and yq v4 (https://github.com/mikefarah/yq, v4.54.1 checked 2026-10-28).
# Run from the repository's main folder.
set -euo pipefail

MAIN_VALUES=serving/values/qwen3.8-27b.yaml
CANARY_VALUES=serving/values/qwen3.8-27b-canary.yaml
MAIN_APP=argocd/apps/serving.yaml
CANARY_APP=argocd/apps/serving-canary.yaml
GATEWAY_VALUES=gateway/litellm/values.yaml               # LiteLLM config is under proxy_config
CANARY_ID=astra-canary                                   # LiteLLM deployment id that marks the canary entry
CANARY_API_BASE=http://vllm-canary.serving.svc:8000/v1   # the chart names the Service after the release

command -v yq >/dev/null || { echo "yq v4 is needed: https://github.com/mikefarah/yq"; exit 1; }
[ -f "$MAIN_VALUES" ] || { echo "Run from the repository's main folder."; exit 1; }

# A clean tree, so each commit holds only this step.
clean_tree() {
  if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "Commit or stash your changes first."; exit 1
  fi
}

done_msg() {
  echo
  echo "Committed. Push it, and Argo CD applies it:  git push"
  echo "$1"
}

start() {
  local rev=${1:-}
  [ ${#rev} = 40 ] || { echo "Usage: canary.sh start <40-character revision>"; exit 1; }
  [ ! -f "$CANARY_APP" ] || { echo "A canary already exists: $CANARY_APP"; exit 1; }
  local cur
  cur=$(yq '.model.revision' "$MAIN_VALUES")
  [ "$rev" != "$cur" ] || { echo "The main release already serves $rev."; exit 1; }
  clean_tree

  # The new revision must be in S3 (the loader writes SHA256SUMS last), and it must hold other files.
  # Two Hugging Face commits can have the same weights (a commit that only changes the README);
  # a canary of identical files costs a GPU node and tests nothing. FORCE=1 skips this check.
  local base new old
  base="s3://astra-models-$(aws sts get-caller-identity --query Account --output text)/$(yq '.model.name' "$MAIN_VALUES")"
  new=$(aws s3 cp --quiet "$base/$rev/SHA256SUMS" - 2>/dev/null) || { echo "$rev is not in S3 yet: run the loader Job first (model/)."; exit 1; }
  old=$(aws s3 cp --quiet "$base/$cur/SHA256SUMS" - 2>/dev/null) || old=""
  if [ "$new" = "$old" ] && [ "${FORCE:-0}" != 1 ]; then
    echo "$rev has the same files as the serving revision $cur (SHA256SUMS match)."
    echo "Nothing to test. To run the canary anyway (for practice): FORCE=1 bash scripts/canary.sh start $rev"
    exit 1
  fi

  # The canary values: the main values with the new revision.
  REV=$rev yq '.model.revision = strenv(REV)' "$MAIN_VALUES" > "$CANARY_VALUES"
  # The canary ApplicationSet: a copy of the main one. canary: true makes the chart run one replica
  # and skip what the main release already owns (service account, API key Secret, autoscaler).
  yq '
    .metadata.name = "serving-canary"
    | .spec.template.metadata.name = "serving-canary"
    | .spec.template.spec.source.helm.releaseName = "vllm-canary"
    | .spec.template.spec.source.helm.releaseName line_comment = "Service \"vllm-canary\" -> vllm-canary.serving.svc:8000"
    | .spec.template.spec.source.helm.valueFiles = ["../values/qwen3.8-27b-canary.yaml"]
    | .spec.template.spec.source.helm.valuesObject.canary = true
    | . head_comment = "Canary of a model upgrade, made by scripts/canary.sh start. Removed by promote or rollback."
  ' "$MAIN_APP" > "$CANARY_APP"

  git add "$CANARY_VALUES" "$CANARY_APP"
  git commit -q -m "canary: vllm-canary with revision $rev (no traffic yet)"
  done_msg "Wait until the vllm-canary pod is Ready (a GPU node starts, then the weights load):
  kubectl -n serving get pods -L astra/role,astra/model-revision -w
Then send it traffic:  bash scripts/canary.sh weight 10"
}

weight() {
  local w=${1:-}
  [[ "$w" =~ ^[0-9]+$ ]] && [ "$w" -ge 1 ] && [ "$w" -le 99 ] || { echo "Usage: canary.sh weight <1-99>"; exit 1; }
  [ -f "$CANARY_VALUES" ] || { echo "No canary. Run start first."; exit 1; }
  clean_tree
  local routed
  routed=$(ID=$CANARY_ID yq '[.proxy_config.model_list[] | select(.model_info.id == strenv(ID))] | length' "$GATEWAY_VALUES")
  if [ "$routed" = 0 ]; then
    # Add the canary entry: a copy of the main entry with the canary's address.
    # Key, timeout and price stay the same, so apps and budgets see no difference.
    ID=$CANARY_ID BASE=$CANARY_API_BASE yq -i '
      .proxy_config.model_list += [
        .proxy_config.model_list[] | select(.model_name == "astra")
        | .litellm_params.api_base = strenv(BASE)
        | .model_info.id = strenv(ID)
      ]' "$GATEWAY_VALUES"
  fi
  # LiteLLM's simple-shuffle routing picks an entry at random for each request, by weight.
  # env() reads the variable as a YAML value, so the weights are written as numbers.
  ID=$CANARY_ID MAIN_W=$((100 - w)) CANARY_W=$w yq -i '
    (.proxy_config.model_list[] | select(.model_name == "astra" and .model_info.id != strenv(ID)) | .litellm_params.weight) = env(MAIN_W)
    | (.proxy_config.model_list[] | select(.model_info.id == strenv(ID)) | .litellm_params.weight) = env(CANARY_W)
  ' "$GATEWAY_VALUES"
  git add "$GATEWAY_VALUES"
  git commit -q -m "canary: $w% of astra traffic to the canary"
  done_msg "Argo CD rolls the gateway pods with the new weights. Then compare the two releases:
  bash scripts/load.sh 200
Next step: a higher weight (canary.sh weight 25, then 50), or promote, or rollback."
}

# Takes the canary out of the gateway and its files out of Git. Argo CD then deletes the
# ApplicationSet, and its Application's finalizer deletes the canary pod: the GPU node is freed.
unroute() {
  ID=$CANARY_ID yq -i '
    del(.proxy_config.model_list[] | select(.model_info.id == strenv(ID)))
    | del(.proxy_config.model_list[] | select(.model_name == "astra") | .litellm_params.weight)' "$GATEWAY_VALUES"
  git rm -q "$CANARY_VALUES" "$CANARY_APP"
  git add "$GATEWAY_VALUES" "$MAIN_VALUES"
}

promote() {
  [ -f "$CANARY_VALUES" ] || { echo "No canary to promote."; exit 1; }
  clean_tree
  local rev
  rev=$(yq '.model.revision' "$CANARY_VALUES")
  # The main release now loads the canary's revision, one replica at a time (maxSurge 1, maxUnavailable 0).
  REV=$rev yq -i '.model.revision = strenv(REV)' "$MAIN_VALUES"
  unroute
  git commit -q -m "canary: promote revision $rev to the main release"
  done_msg "Argo CD rolls the main release to $rev and removes the canary. Watch:
  kubectl -n serving get pods -L astra/role,astra/model-revision -w"
}

rollback() {
  [ -f "$CANARY_VALUES" ] || { echo "No canary to roll back."; exit 1; }
  clean_tree
  # The main release keeps its version. It served the rest of the traffic the whole time.
  unroute
  git commit -q -m "canary: roll back, all traffic to the main release"
  done_msg "Argo CD removes the canary. All traffic goes to the main release again."
}

case "${1:-}" in
  start) start "${2:-}" ;;
  weight) weight "${2:-}" ;;
  promote) promote ;;
  rollback) rollback ;;
  *) sed -n '2,16p' "$0"; exit 1 ;;
esac
