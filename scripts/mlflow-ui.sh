#!/usr/bin/env bash
# Opens the MLflow UI of the SageMaker AI MLflow App (the gateway's traces).
# AWS hosts the UI, so no port-forward is needed. The command makes a sign-in link with your own AWS
# login: the link works once, within 5 minutes; the browser session it opens lasts 12 hours.
# In the UI: the workspace "default", then the experiment "astra-gateway", then Traces.
#
# Run from the repository's main folder:  bash scripts/mlflow-ui.sh
set -euo pipefail

[ -d terraform/foundations ] || { echo "Run from the repository's main folder."; exit 1; }
ARN=$(terraform -chdir=terraform/foundations output -raw mlflow_tracking_arn)
URL=$(aws sagemaker create-presigned-mlflow-app-url --arn "$ARN" \
        --expires-in-seconds 300 --session-expiration-duration-in-seconds 43200 \
        --query AuthorizedUrl --output text)

echo "MLflow App: $ARN"
echo "Sign-in link (one use, valid 5 minutes):"
echo "$URL"

# Open it in the default browser when the system has a way to (Windows Git Bash, macOS, Linux desktop).
if command -v cmd.exe >/dev/null 2>&1; then cmd.exe /c start "" "$URL" >/dev/null 2>&1 || true
elif command -v open >/dev/null 2>&1; then open "$URL" || true
elif command -v xdg-open >/dev/null 2>&1; then xdg-open "$URL" >/dev/null 2>&1 || true
fi
