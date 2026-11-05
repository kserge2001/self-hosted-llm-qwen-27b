#!/usr/bin/env bash
# Deletes the whole lab, so the hourly bill stops. The order matters:
#   1. Stop the root app's auto-sync, then delete the apps in argocd/apps (model server, gateway,
#      the app), while the controllers that clean up after them still run.
#   2. Pause Argo CD, then remove load balancers, DNS records, disks and the Karpenter NodePools.
#      Terraform never created these, so it cannot delete them, and they would block it.
#   3. The astra/teams/* secrets (sync_teams.py made them, not Terraform), then terraform destroy
#      of terraform/foundations (cluster, network, database, buckets, ECR, secrets).
#   4. The bootstrap state bucket. Last, because step 3 keeps its state there.
#   5. scripts/check-clean.sh lists anything that is still there (exit code 1 if something is).
#
# Run from the repository's main folder:  bash scripts/teardown.sh
# It asks twice: "yes" for terraform destroy, then the state bucket's name. To run it without
# questions (for example from another script), set both answers in advance:
#   AUTO_APPROVE=1 CONFIRM_BUCKET=<state bucket name> bash scripts/teardown.sh
# (Piping the answers in does not work with Terraform on Windows: it waits at its prompt.)
set -euo pipefail

[ -d terraform/foundations ] || { echo "Run from the repository's main folder."; exit 1; }
TF=terraform/foundations
REGION=$(terraform -chdir=$TF output -raw region)
ZONE_ID=$(terraform -chdir=$TF output -raw route53_zone_id)
DOMAIN=$(terraform -chdir=$TF output -raw domain)

echo "== 1. Argo CD apps"
# The root app "platform" applies everything under argocd/. Stop its auto-sync first, or it would
# put back each ApplicationSet we delete.
kubectl -n argocd patch application platform --type merge -p '{"spec":{"syncPolicy":{"automated":null}}}'
# The apps' Applications carry the Argo CD resources finalizer, so deleting the ApplicationSet also
# deletes the pods, Services and Ingresses they made.
for appset in serving-canary k8s-assistant gateway serving; do
  kubectl -n argocd delete applicationset "$appset" --ignore-not-found --wait=true
done
for app in serving-canary k8s-assistant gateway serving; do
  kubectl -n argocd wait --for=delete "application/$app" --timeout=15m 2>/dev/null || true
done

echo "== 2. Pause Argo CD, so it does not recreate what we delete next"
# The add-ons (load balancer controller, ExternalDNS, Karpenter, EBS CSI driver) keep running and do the cleanup.
kubectl -n argocd scale statefulset -l app.kubernetes.io/component=application-controller --replicas=0
kubectl -n argocd scale deployment -l app.kubernetes.io/component=applicationset-controller --replicas=0

echo "== 2a. Ingresses: the load balancer controller deletes the shared ALB"
kubectl delete ingress --all --all-namespaces --wait=true --timeout=10m
kubectl get svc -A -o jsonpath='{range .items[?(@.spec.type=="LoadBalancer")]}{.metadata.namespace}{" "}{.metadata.name}{"\n"}{end}' \
  | while read -r ns name; do kubectl -n "$ns" delete svc "$name" --wait=true; done

echo "== 2b. DNS: wait until ExternalDNS has deleted its records in $DOMAIN"
# ExternalDNS (policy sync) deletes a record after its Ingress is gone. It checks about once a minute.
# Terraform deletes the cluster next, and with it ExternalDNS, so wait here. Up to 10 minutes.
records() {
  aws route53 list-resource-record-sets --hosted-zone-id "$ZONE_ID" --output text \
    --query "ResourceRecordSets[?Type=='A' || Type=='AAAA' || Type=='CNAME'].Name" \
    | tr '\t' '\n' | grep -E "^(astra|argocd|grafana)\.${DOMAIN//./\\.}\.?$" || true
}
for _ in $(seq 60); do
  left=$(records)
  [ -z "$left" ] && break
  echo "   still there: $(echo "$left" | tr '\n' ' ')"
  sleep 10
done
[ -z "$(records)" ] || echo "   WARNING: records are left in $DOMAIN. Delete them in Route 53 after this script."

echo "== 2c. Disks: the EBS CSI driver deletes the volumes behind the PVCs"
# A PVC is only deleted when no pod uses it, so first stop the StatefulSets and Jobs that hold them.
kubectl -n models delete job model-loader --ignore-not-found --wait=true
# The Prometheus operator would recreate its StatefulSets, so delete what it manages first.
kubectl delete prometheus,alertmanager --all --all-namespaces --ignore-not-found --wait=true
for ns in $(kubectl get pvc -A -o jsonpath='{.items[*].metadata.namespace}' | tr ' ' '\n' | sort -u); do
  kubectl -n "$ns" delete statefulset --all --wait=true
done
kubectl delete pvc --all --all-namespaces --wait=true --timeout=10m

echo "== 2d. Karpenter NodePools: Karpenter drains and terminates its nodes"
kubectl delete nodepools --all --wait=true --timeout=15m
until [ -z "$(kubectl get nodeclaims -o name 2>/dev/null)" ]; do
  echo "   waiting for Karpenter nodes to go:"; kubectl get nodeclaims --no-headers 2>/dev/null || true
  sleep 20
done
# EC2NodeClasses last: Karpenter then deletes the instance profiles it made.
# A left-over instance profile stops Terraform from deleting the node IAM role.
kubectl delete ec2nodeclasses --all --wait=true --timeout=5m

echo "== 3a. Team key secrets: sync_teams.py created them, so Terraform does not know them"
# Without --force-delete-without-recovery a deleted secret waits 7-30 days, and its name stays taken.
for id in $(aws secretsmanager list-secrets --region "$REGION" \
              --filters Key=name,Values=astra/teams/ --query 'SecretList[].Name' --output text); do
  echo "   deleting $id"
  aws secretsmanager delete-secret --region "$REGION" --secret-id "$id" --force-delete-without-recovery >/dev/null
done

echo "== 3b. terraform destroy: foundations (prints a plan and asks for yes)"
terraform -chdir=$TF destroy ${AUTO_APPROVE:+-auto-approve}

echo "== 4. The bootstrap state bucket"
# The bucket has prevent_destroy, so a plain terraform destroy refuses. That guard is on purpose:
# it holds the only record of what Terraform built. Delete it by hand, and only now.
BUCKET=$(terraform -chdir=terraform/bootstrap output -raw state_bucket)
answer=${CONFIRM_BUCKET:-}
[ -n "$answer" ] || read -r -p "Type the bucket name to delete it and every old state version ($BUCKET): " answer
[ "$answer" = "$BUCKET" ] || { echo "Not deleted."; exit 1; }
# In the current folder, not mktemp: on Windows, aws.exe cannot read a Git Bash /tmp path.
VERSIONS=.teardown-versions.json
# shellcheck disable=SC2016  # the backticks are a JMESPath literal for the AWS CLI, not a shell command
aws s3api list-object-versions --bucket "$BUCKET" --output json \
  --query '{Objects: [Versions, DeleteMarkers][][].{Key: Key, VersionId: VersionId}, Quiet: `true`}' > "$VERSIONS"
grep -q '"Key"' "$VERSIONS" && aws s3api delete-objects --bucket "$BUCKET" --delete "file://$VERSIONS"
rm -f "$VERSIONS"
aws s3api delete-bucket --bucket "$BUCKET"
# Terraform now sees the bucket is gone and removes the rest (bucket settings, backend.hcl).
terraform -chdir=terraform/bootstrap destroy ${AUTO_APPROVE:+-auto-approve}

echo "== 5. Final check: is anything from this build left in the account?"
bash scripts/check-clean.sh "$REGION" "$DOMAIN"
