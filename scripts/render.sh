#!/usr/bin/env bash
# Writes Terraform outputs into the Kubernetes manifests. Input: k8s/. Output: build/ (git-ignored).
# Run from the project's main folder after `terraform apply`:  bash scripts/render.sh
set -euo pipefail

tf() { terraform -chdir=terraform output -raw "$1"; }

REGION=$(tf region)
CLUSTER=$(tf cluster_name)
CLUSTER_SG=$(tf cluster_security_group_id)
NODE_ROLE=$(tf node_role_name)
BUCKET=$(tf model_bucket)

# Internal price per token for chargeback (step 11 explains where these numbers come from).
INPUT_COST=${INPUT_COST:-0.00000045}
OUTPUT_COST=${OUTPUT_COST:-0.00000227}

mkdir -p build
for f in k8s/*.yaml; do
  sed -e "s|__REGION__|$REGION|g" \
      -e "s|__CLUSTER_NAME__|$CLUSTER|g" \
      -e "s|__CLUSTER_SG__|$CLUSTER_SG|g" \
      -e "s|__NODE_ROLE__|$NODE_ROLE|g" \
      -e "s|__MODEL_BUCKET__|$BUCKET|g" \
      -e "s|__INPUT_COST__|$INPUT_COST|g" \
      -e "s|__OUTPUT_COST__|$OUTPUT_COST|g" \
      "$f" > "build/$(basename "$f")"
done

echo "Rendered into build/ for cluster $CLUSTER (bucket $BUCKET)"
grep -l "__[A-Z_]*__" build/*.yaml && { echo "Some placeholders were not replaced"; exit 1; } || true
