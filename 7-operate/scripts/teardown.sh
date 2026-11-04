#!/usr/bin/env bash
# Deletes the whole lab, so the hourly bill stops. The order matters:
#   1. Argo CD apps of stages 6, 5 and 4, while the controllers that clean up after them still run.
#   2. Pause Argo CD, remove load balancers and disks, then the Karpenter NodePools: Karpenter drains
#      and terminates its nodes. Terraform never created these, so it cannot delete them.
#   3. The astra/teams/* secrets (the teams workflow made them, not Terraform), then terraform destroy
#      of 1-foundations/terraform (cluster, network, databases, buckets, secrets).
#   4. The bootstrap state bucket. Last, because step 3 keeps its state there.
#
# Run from the repository's main folder:  bash 7-operate/scripts/teardown.sh
set -euo pipefail

[ -d 1-foundations ] || { echo "Run from the repository's main folder."; exit 1; }

echo "== 1. Argo CD apps, newest stage first"
# Stages 4 and 5 are ApplicationSets. Their Applications carry the Argo CD resources finalizer,
# so deleting them also deletes the pods, Services and Ingresses they made.
kubectl -n argocd delete applicationset serving-canary --ignore-not-found --wait=true
for f in 6-app/k8s-assistant/argocd/k8s-assistant.yaml 5-gateway/argocd/langfuse.yaml \
         5-gateway/argocd/gateway.yaml 4-serving/argocd/serving.yaml; do
  kubectl delete -f "$f" --ignore-not-found --wait=true
done
for app in serving-canary k8s-assistant langfuse gateway serving; do
  kubectl -n argocd wait --for=delete "application/$app" --timeout=15m 2>/dev/null || true
done

echo "== 2. Pause Argo CD, so it does not recreate what we delete next"
# The add-ons (load balancer controller, Karpenter, EBS CSI driver) keep running and do the cleanup.
kubectl -n argocd scale statefulset -l app.kubernetes.io/component=application-controller --replicas=0
kubectl -n argocd scale deployment -l app.kubernetes.io/component=applicationset-controller --replicas=0

echo "== 2a. Ingresses: the load balancer controller deletes the shared ALB"
kubectl delete ingress --all --all-namespaces --wait=true --timeout=10m
kubectl get svc -A -o jsonpath='{range .items[?(@.spec.type=="LoadBalancer")]}{.metadata.namespace}{" "}{.metadata.name}{"\n"}{end}' \
  | while read -r ns name; do kubectl -n "$ns" delete svc "$name" --wait=true; done

echo "== 2b. Disks: the EBS CSI driver deletes the volumes behind the PVCs"
# A PVC is only deleted when no pod uses it, so first stop the StatefulSets that hold them.
for ns in $(kubectl get pvc -A -o jsonpath='{.items[*].metadata.namespace}' | tr ' ' '\n' | sort -u); do
  kubectl -n "$ns" delete statefulset --all --wait=true
done
kubectl delete pvc --all --all-namespaces --wait=true --timeout=10m

echo "== 2c. Karpenter NodePools: Karpenter drains and terminates its nodes"
kubectl delete nodepools --all --wait=true --timeout=15m
until [ -z "$(kubectl get nodeclaims -o name 2>/dev/null)" ]; do
  echo "   waiting for Karpenter nodes to go:"; kubectl get nodeclaims --no-headers 2>/dev/null || true
  sleep 20
done
# EC2NodeClasses last: Karpenter then deletes the instance profiles it made.
# A left-over instance profile stops Terraform from deleting the node IAM role.
kubectl delete ec2nodeclasses --all --wait=true --timeout=5m

echo "== 3a. Team key secrets: the teams workflow created them, so Terraform does not know them"
# Without --force-delete-without-recovery a deleted secret waits 7-30 days, and its name stays taken.
REGION=$(terraform -chdir=1-foundations/terraform output -raw region)
for id in $(aws secretsmanager list-secrets --region "$REGION" \
              --filters Key=name,Values=astra/teams/ --query 'SecretList[].Name' --output text); do
  echo "   deleting $id"
  aws secretsmanager delete-secret --region "$REGION" --secret-id "$id" --force-delete-without-recovery >/dev/null
done

echo "== 3b. terraform destroy: foundations (prints a plan and asks for yes)"
terraform -chdir=1-foundations/terraform destroy

echo "== 4. The bootstrap state bucket"
# The bucket has prevent_destroy, so a plain terraform destroy refuses. That guard is on purpose:
# it holds the only record of what Terraform built. Delete it by hand, and only now.
BUCKET=$(terraform -chdir=1-foundations/bootstrap output -raw state_bucket)
read -r -p "Type the bucket name to delete it and every old state version ($BUCKET): " answer
[ "$answer" = "$BUCKET" ] || { echo "Not deleted."; exit 1; }
VERSIONS=$(mktemp)
# shellcheck disable=SC2016  # the backticks are a JMESPath literal for the AWS CLI, not a shell command
aws s3api list-object-versions --bucket "$BUCKET" --output json \
  --query '{Objects: [Versions, DeleteMarkers][][].{Key: Key, VersionId: VersionId}, Quiet: `true`}' > "$VERSIONS"
grep -q '"Key"' "$VERSIONS" && aws s3api delete-objects --bucket "$BUCKET" --delete "file://$VERSIONS"
rm -f "$VERSIONS"
aws s3api delete-bucket --bucket "$BUCKET"
# Terraform now sees the bucket is gone and removes the rest (bucket settings, backend.hcl).
terraform -chdir=1-foundations/bootstrap destroy

echo "Done. Check the EC2 console for running instances or EBS volumes named astra; there should be none."
