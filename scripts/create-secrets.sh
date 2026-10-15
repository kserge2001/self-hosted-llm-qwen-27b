#!/usr/bin/env bash
# Copies the platform secrets from AWS Secrets Manager into Kubernetes Secrets.
# Secrets Manager stays the source of truth. In production, the External Secrets Operator does this copy.
# Run from the project's main folder:  bash scripts/create-secrets.sh
set -euo pipefail

REGION=$(terraform -chdir=terraform output -raw region)
SECRET_ID=$(terraform -chdir=terraform output -raw secret_id)
JSON=$(aws secretsmanager get-secret-value --region "$REGION" --secret-id "$SECRET_ID" --query SecretString --output text)

PY=python3; python3 -c "" 2>/dev/null || PY=python
get() { echo "$JSON" | $PY -c "import json,sys; print(json.load(sys.stdin)['$1'])"; }

# The model servers only accept requests carrying this key. Only the gateway has it.
kubectl -n llm create secret generic vllm-api-key \
  --from-literal=api-key="$(get vllm_api_key)" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n gateway create secret generic litellm-env \
  --from-literal=LITELLM_MASTER_KEY="$(get litellm_master_key)" \
  --from-literal=LITELLM_SALT_KEY="$(get litellm_salt_key)" \
  --from-literal=DATABASE_URL="$(get database_url)" \
  --from-literal=VLLM_API_KEY="$(get vllm_api_key)" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n monitoring create secret generic grafana-admin \
  --from-literal=admin-user=admin \
  --from-literal=admin-password="$(get grafana_password)" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Secrets created in namespaces llm, gateway and monitoring."
