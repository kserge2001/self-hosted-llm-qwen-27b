# Stage 7: operate Astra

In a company, the platform team and the people on call own this folder.

| Path | What it does |
|---|---|
| `scripts/spend-report.sh` | what each team spent against its budget, from the gateway admin API |
| `scripts/canary.sh` | a new model version gets 10% of the traffic, then is promoted or rolled back. Every step is a Git commit and a pull request |
| `scripts/teardown.sh` | deletes everything in the right order, so nothing is left that costs money |
| `runbooks/` | short steps for the usual problems: model upgrade, no GPU capacity, budget used up, node failure, rotate a team key |

The admin API of the gateway is not on its Ingress (only `/v1` and `/health` are). So `spend-report.sh` opens a port-forward to the gateway Service while it runs.

`canary.sh` needs `git`, `yq` v4 and `kubectl`. Its `promote` also sets the MLflow alias `champion`, so it needs Python with `3-model-pipeline/scripts/requirements.txt` and your AWS login (MLflow is the SageMaker MLflow App, no port-forward). The canary values file comes from the model pipeline (rollout `canary`). `canary.sh` edits `4-serving/values/`, `4-serving/argocd/` and `5-gateway/litellm/values.yaml`, and commits on a new branch. Nothing changes in the cluster until you merge.

## The check that ends this stage

- A canary was promoted or rolled back, and `canary.sh cleanup` removed it.
- After `teardown.sh`, the EC2 console shows no instances, volumes or load balancers named `astra`.
