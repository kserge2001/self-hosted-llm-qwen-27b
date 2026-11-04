output "region" {
  value = var.region
}

output "cluster_name" {
  value = module.eks.cluster_name
}

output "configure_kubectl" {
  description = "Run this to point kubectl at the new cluster."
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "buckets" {
  description = "S3 buckets: model weights, MLflow artifacts."
  value       = { for k, b in aws_s3_bucket.this : k => b.bucket }
}

output "rds_host" {
  value = aws_db_instance.this.address
}

output "acm_certificate_arn" {
  value = aws_acm_certificate_validation.this.certificate_arn
}

output "bedrock_guardrail_id" {
  value = aws_bedrock_guardrail.this.guardrail_id
}

output "bedrock_guardrail_version" {
  value = aws_bedrock_guardrail_version.this.version
}

output "karpenter_node_role" {
  description = "IAM role of the Karpenter nodes. The EC2NodeClass in platform/karpenter names it."
  value       = module.karpenter.node_iam_role_name
}

output "secrets_generated" {
  description = "Secrets Terraform filled in. Nothing to do."
  value       = sort([for s in aws_secretsmanager_secret.generated : s.name])
}

output "secrets_to_fill" {
  description = "Secrets that exist but are empty. Set them before the model loader runs."
  value       = sort([for s in aws_secretsmanager_secret.student : s.name])
}

output "fill_hf_token" {
  description = "Hugging Face read token (huggingface.co > Settings > Access Tokens). Used by the model loader Job."
  value       = "aws secretsmanager put-secret-value --region ${var.region} --secret-id ${aws_secretsmanager_secret.student["hf-token"].name} --secret-string 'hf_xxx'"
}

output "gateway_image_repo" {
  description = "ECR repository for the gateway image (gateway/litellm/image). docker push goes here."
  value       = aws_ecr_repository.gateway.repository_url
}

output "mlflow_tracking_arn" {
  description = "ARN of the SageMaker MLflow App. With the sagemaker-mlflow plugin it is the MLFLOW_TRACKING_URI."
  value       = aws_sagemaker_mlflow_app.this.arn
}

output "app_image_repo" {
  description = "ECR repository for the k8s-assistant image. docker push goes here."
  value       = aws_ecr_repository.app.repository_url
}

output "route53_zone_id" {
  description = "The hosted zone of var.domain. scripts/teardown.sh checks it for leftover records."
  value       = data.aws_route53_zone.this.zone_id
}

output "domain" {
  value = var.domain
}

output "argocd_admin_password" {
  description = "First Argo CD login is user admin with this password."
  value       = "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
}
