# 3-model-pipeline: promote a model version

This stage moves one model version from Hugging Face to "ready to serve".
It does not deploy. At the end it opens a pull request on `4-serving`. Merging that pull request is the deployment.

The workflow is `.github/workflows/model-promote.yml`. It runs on the ARC runners inside the cluster.
They get AWS access from EKS Pod Identity, so there are no AWS keys in GitHub.

The model registry is MLflow on Amazon SageMaker AI: the serverless MLflow App `astra`, made by `1-foundations/terraform`.
The tracking URI is the app ARN, not a URL. The `sagemaker-mlflow` package (in `requirements.txt`) reads the ARN and signs each call with your AWS credentials.
The scripts find the ARN by the app name, so you copy nothing into GitHub.

## The steps

| Job | Script | What it does |
|---|---|---|
| intake | `download.py` | Downloads the pinned `revision` from Hugging Face. Only the `allow_patterns` files. Stops if a weight file is not `.safetensors`. |
| intake | `scan.py` | Checks each safetensors header, runs ModelScan, and checks that the license on Hugging Face is the license in the spec. |
| intake | `upload.py` | Copies the files to `s3://astra-models-<account>/<name>/<revision>/`. Writes `SHA256SUMS` last. |
| register | `register.py` | Creates an MLflow run and a model version. The version source is the S3 folder. Tags: `hf_repo`, `revision`, `scan=passed`. |
| evaluate | `k8s/eval-job.yaml` | A Job on a GPU node. vLLM streams the weights from S3 (Run:ai Model Streamer). lm-evaluation-harness runs the eval tasks. Results go to `s3://astra-mlflow-<account>/eval/<name>/<revision>/results.json`. |
| gate | `gate.py` | Compares the scores with the thresholds in the spec. Logs them to MLflow. Pass: alias `candidate`. Fail: the workflow stops. |
| approve | (none) | Waits for a person to approve in GitHub (environment `model-approval`). |
| promote | `promote.py` | Rollout `direct`: sets alias `champion` and writes `model.uri` and `model.revision` in `4-serving/values/qwen3.8-27b.yaml`. Rollout `canary`: sets alias `approved` and writes them in `4-serving/values/qwen3.8-27b-canary.yaml`. Then opens a pull request. |

The spec file is `models/qwen3.8-27b.yaml`. The eval threshold in it is a starting value. Tune it after the first run.

## Start a promotion

- Change `revision` in the spec and merge the change to `main`, or
- GitHub, Actions, model-promote, Run workflow, choose the spec file.

Choose the rollout when you run the workflow by hand:

- `direct` (the default, and always used by a push): merging the pull request serves the new version to all traffic.
- `canary`: merging the pull request serves nothing yet. The new version first gets 10% of the traffic with `7-operate/scripts/canary.sh`. See `7-operate/runbooks/model-upgrade.md`. `canary.sh promote` sets the alias `champion` later.

## One-time setup

1. Put your Hugging Face token in Secrets Manager:

   ```bash
   aws secretsmanager put-secret-value --secret-id astra/hf-token --secret-string 'hf_...'
   ```

2. In GitHub, Settings, Environments, create the environment `model-approval`.
   Turn on **Required reviewers** and add the people who approve models.

3. The promote job opens its pull request with a token of the ARC GitHub App (secret `astra/arc/github-app`), not with `GITHUB_TOKEN`.
   Why: a pull request opened with `GITHUB_TOKEN` does not start other workflows, so CI would not check it.
   In GitHub, open the app's settings, **Permissions**, **Repository permissions**, and add:
   - **Contents**: Read and write (push the branch)
   - **Pull requests**: Read and write (open the pull request)

   Save. Then accept the new permissions on the app's installation (Settings, GitHub Apps, Configure).

4. Nothing to do for MLflow. Terraform made the app, and the runner role may use it (`sagemaker:CallMlflowAppApi`).
   To open the MLflow UI, get a short-lived link and open it in your browser:

   ```bash
   aws sagemaker create-presigned-mlflow-app-url --query AuthorizedUrl --output text \
     --arn "$(terraform -chdir=1-foundations/terraform output -raw mlflow_tracking_arn)"
   ```

## Run a script by hand

Your AWS login needs `sagemaker:ListMlflowApps` and `sagemaker:CallMlflowAppApi` (an admin login has both).

```bash
cd 3-model-pipeline/scripts
pip install -r requirements.txt     # Python 3.12
python spec.py ../models/qwen3.8-27b.yaml
```

The scripts find the app by name. To use another app, set its ARN first:
`export MLFLOW_TRACKING_URI=$(terraform -chdir=../../1-foundations/terraform output -raw mlflow_tracking_arn)`.
