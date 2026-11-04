#!/usr/bin/env bash
# Checks that nothing from this build is left in your AWS account: everything Terraform made, and
# everything the controllers in the cluster made (nodes, disks, load balancers, DNS records).
# scripts/teardown.sh runs it at the end. Run it yourself any time:
#
#   bash scripts/check-clean.sh <region> <domain> [name]      for example: us-east-1 lab.example.com astra
#
# Prints one line per kind of resource. Exit code 0: nothing left. 1: something is left (it is listed).
# It looks only for this build's names and tags, so it lists nothing else in your account.
set -uo pipefail

REGION=${1:?usage: check-clean.sh <region> <domain> [name]}
DOMAIN=${2:?usage: check-clean.sh <region> <domain> [name]}
NAME=${3:-astra}
export AWS_DEFAULT_REGION=$REGION
left=0

# check <what> <aws cli command...>: the command prints what is left, or nothing.
check() {
  local what=$1; shift
  local out
  out=$("$@" 2>/dev/null | tr '\t' '\n' | sed '/^None$/d;/^$/d')
  if [ -n "$out" ]; then
    printf '%-36s LEFT: %s\n' "$what" "$(echo "$out" | tr '\n' ' ')"
    left=1
  else
    printf '%-36s ok\n' "$what"
  fi
}

echo "== Made by the controllers in the cluster (Terraform does not know these)"
check "EC2 instances (all nodes)"          aws ec2 describe-instances --output text \
  --filters "Name=tag-key,Values=kubernetes.io/cluster/$NAME" "Name=instance-state-name,Values=pending,running,stopping,stopped,shutting-down" \
  --query 'Reservations[].Instances[].InstanceId'
check "Karpenter launch templates"         aws ec2 describe-launch-templates --output text \
  --filters "Name=tag:karpenter.k8s.aws/cluster,Values=$NAME" --query 'LaunchTemplates[].LaunchTemplateName'
check "Karpenter instance profiles"        aws iam list-instance-profiles --output text \
  --query "InstanceProfiles[?starts_with(InstanceProfileName, '${NAME}_')].InstanceProfileName"
check "EBS volumes of this cluster"        aws ec2 describe-volumes --output text \
  --filters "Name=tag-key,Values=kubernetes.io/cluster/$NAME" --query 'Volumes[].VolumeId'
check "EBS volumes from PVCs, unattached"  aws ec2 describe-volumes --output text \
  --filters "Name=tag:ebs.csi.aws.com/cluster,Values=true" "Name=status,Values=available" --query 'Volumes[].VolumeId'
check "Load balancers and target groups"   aws resourcegroupstaggingapi get-resources --output text \
  --tag-filters "Key=elbv2.k8s.aws/cluster,Values=$NAME" \
  --resource-type-filters elasticloadbalancing:loadbalancer elasticloadbalancing:targetgroup \
  --query 'ResourceTagMappingList[].ResourceARN'
ZONE=$(aws route53 list-hosted-zones-by-name --dns-name "$DOMAIN" --query "HostedZones[?Name=='$DOMAIN.'].Id | [0]" --output text 2>/dev/null)
check "Route 53 records (ExternalDNS, ACM)" aws route53 list-resource-record-sets --hosted-zone-id "$ZONE" --output text \
  --query "ResourceRecordSets[?contains(Name, 'astra.$DOMAIN') || contains(Name, 'argocd.$DOMAIN') || contains(Name, 'grafana.$DOMAIN')].[Type,Name]"

echo "== Made by Terraform"
check "EKS cluster"                        aws eks list-clusters --query "clusters[?@=='$NAME']" --output text
VPC=$(aws ec2 describe-vpcs --filters "Name=tag:Project,Values=$NAME" --query 'Vpcs[].VpcId' --output text 2>/dev/null)
check "VPC"                                echo "${VPC/None/}"
for v in ${VPC/None/}; do
  check "  network interfaces in $v"       aws ec2 describe-network-interfaces --output text \
    --filters "Name=vpc-id,Values=$v" --query 'NetworkInterfaces[].NetworkInterfaceId'
  check "  security groups in $v"          aws ec2 describe-security-groups --output text \
    --filters "Name=vpc-id,Values=$v" --query "SecurityGroups[?GroupName!='default'].GroupId"
done
check "NAT gateways"                       aws ec2 describe-nat-gateways --output text \
  --filter "Name=tag:Project,Values=$NAME" "Name=state,Values=pending,available,deleting" --query 'NatGateways[].NatGatewayId'
check "Elastic IPs"                        aws ec2 describe-addresses --output text \
  --filters "Name=tag:Project,Values=$NAME" --query 'Addresses[].PublicIp'
check "RDS instance"                       aws rds describe-db-instances --output text \
  --query "DBInstances[?DBInstanceIdentifier=='$NAME'].DBInstanceIdentifier"
check "RDS snapshots"                      aws rds describe-db-snapshots --db-instance-identifier "$NAME" --output text \
  --query 'DBSnapshots[].DBSnapshotIdentifier'
check "S3 buckets"                         aws s3api list-buckets --output text \
  --query "Buckets[?starts_with(Name, '$NAME-')].Name"
check "ECR repositories"                   aws ecr describe-repositories --output text \
  --query "repositories[?starts_with(repositoryName, '$NAME/')].repositoryName"
check "Secrets (also scheduled deletion)"  aws secretsmanager list-secrets --include-planned-deletion --output text \
  --filters "Key=name,Values=$NAME/" --query 'SecretList[].Name'
check "ACM certificate"                    aws acm list-certificates --output text \
  --query "CertificateSummaryList[?DomainName=='astra.$DOMAIN'].CertificateArn"
check "IAM roles"                          aws iam list-roles --output text \
  --query "Roles[?starts_with(RoleName, '$NAME-') || starts_with(RoleName, 'KarpenterController') || starts_with(RoleName, 'system-eks-node-group')].RoleName"
check "SQS queue (Karpenter)"              aws sqs list-queues --queue-name-prefix "Karpenter-$NAME" --output text --query 'QueueUrls[]'
check "EventBridge rules (Karpenter)"      aws events list-rules --output text \
  --query "Rules[?starts_with(Name, 'Karpenter')].Name"
check "CloudWatch log groups"              aws logs describe-log-groups --log-group-name-prefix "/aws/eks/$NAME" --output text \
  --query 'logGroups[].logGroupName'
check "MLflow App (SageMaker AI)"          aws sagemaker list-mlflow-apps --output text \
  --query "Summaries[?Name=='$NAME' && Status!='Deleted'].Arn"
check "Bedrock guardrail"                  aws bedrock list-guardrails --output text \
  --query "guardrails[?name=='$NAME-guardrail'].id"

echo "== Anything else with the tag Project=$NAME (a last sweep; may lag a few minutes after a delete)"
check "Tagged resources"                   aws resourcegroupstaggingapi get-resources --output text \
  --tag-filters "Key=Project,Values=$NAME" --query 'ResourceTagMappingList[].ResourceARN'

echo
if [ "$left" = 0 ]; then
  echo "Nothing from this build is left in $REGION."
else
  echo "Something is left (see LEFT above). Delete it in the console or with the AWS CLI, then run this again."
  echo "Right after teardown, a few items can still be deleting: wait 5 minutes and run it again."
fi
exit "$left"
