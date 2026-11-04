# Runbook: upgrade the model

**When:** a new revision of the model should serve as `astra`.

1. Load the new revision into S3. Change `revision` in `model/qwen3.8-27b.yaml`, then run the loader Job again (`model/README.md`). The Job downloads, scans and uploads. If the scan fails, nothing is uploaded.
2. Start the canary: `bash scripts/canary.sh start <revision>`, then `git push`. Argo CD starts `vllm-canary` with the new revision on its own GPU node. It gets no traffic yet. Wait until its pod is Ready.
3. Send it 10% of the traffic: `bash scripts/canary.sh weight 10`, then `git push`.
4. Send test traffic and compare: `bash scripts/load.sh 200`. In Grafana, compare error rate and latency of `vllm` and `vllm-canary`. In MLflow (experiment `astra-gateway`), compare the answers of the two releases for the same questions. In a company, watch real traffic for at least one busy hour.
5. Raise the share if it looks good: `canary.sh weight 25`, then `50`, each with a push and a check.
6. Good: `bash scripts/canary.sh promote`, then `git push`. The main release rolls to the new revision one pod at a time, and the canary is removed. Bad: `bash scripts/canary.sh rollback`, then `git push`. Only the canary is removed.

**Why a canary:** an evaluation uses a fixed set of questions. Real traffic finds what the tests missed, and a small share limits the harm.

**Note:** the canary needs one more GPU node while it runs. Check for free GPU capacity first (see `gpu-capacity-shortage.md`).
