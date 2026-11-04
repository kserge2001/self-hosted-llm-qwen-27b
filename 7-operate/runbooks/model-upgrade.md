# Runbook: upgrade the model

**When:** a new revision of the model, or a new model, should serve as `astra`.

1. Run the model pipeline (stage 3) for the new revision: GitHub, Actions, model-promote, Run workflow, rollout `canary`. It downloads, scans, uploads to S3, registers in MLflow and runs the eval gate. After the approval it sets the alias `approved` (not `champion`) and opens a pull request that adds `4-serving/values/qwen3.8-27b-canary.yaml`. Merge it. Nothing serves the new version yet.
2. Start the canary: `bash 7-operate/scripts/canary.sh start`. It adds `4-serving/argocd/serving-canary.yaml`. Push, open the pull request, merge. The GPU NodePool allows 4 GPUs, so the main release can still grow to 3 replicas while the canary runs.
3. `kubectl apply -f 4-serving/argocd/serving-canary.yaml`. Wait until the canary pod is Ready (about 10 minutes for the weights).
4. Send it 10% of the traffic: `bash 7-operate/scripts/canary.sh route`. Merge the pull request.
5. Watch for at least one busy hour: error rate and latency in Grafana, answer quality and user feedback in Langfuse. Compare the canary with the main release.
6. Good: `bash 7-operate/scripts/canary.sh promote`. It also sets the MLflow alias `champion` on the canary's version (it needs Python with `3-model-pipeline/scripts/requirements.txt` and your AWS login). Bad: `bash 7-operate/scripts/canary.sh rollback`. The alias `champion` stays on the old version. Merge the pull request.
7. Right after the merge: `bash 7-operate/scripts/canary.sh cleanup`. The main release's rolling update needs the canary's GPU.

**Why a canary:** the eval gate tests a fixed set of questions. Real traffic finds what the tests missed, and 10% limits the harm.

**Note:** the canary needs one more GPU node while it runs. Check for free GPU capacity first (see `gpu-capacity-shortage.md`).
