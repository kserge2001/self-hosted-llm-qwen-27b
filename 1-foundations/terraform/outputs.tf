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
  description = "S3 buckets: model weights, MLflow artifacts, Langfuse events."
  value       = { for k, b in aws_s3_bucket.this : k => b.bucket }
}

output "mlflow_tracking_arn" {
  description = "ARN of the SageMaker MLflow App. With the sagemaker-mlflow plugin it is the MLFLOW_TRACKING_URI."
  value       = aws_sagemaker_mlflow_app.this.arn
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
  description = "IAM role of the Karpenter nodes. The EC2NodeClass in 2-platform names it."
  value       = module.karpenter.node_iam_role_name
}

output "secrets_generated" {
  description = "Secrets Terraform filled in. Nothing to do."
  value       = sort([for s in aws_secretsmanager_secret.generated : s.name])
}

output "secrets_to_fill" {
  description = "Secrets that exist but are empty. Set them before stage 2 needs them."
  value       = sort([for s in aws_secretsmanager_secret.student : s.name])
}

output "fill_hf_token" {
  description = "Hugging Face read token (huggingface.co > Settings > Access Tokens). Used by the model download job."
  value       = "aws secretsmanager put-secret-value --region ${var.region} --secret-id ${aws_secretsmanager_secret.student["hf-token"].name} --secret-string 'hf_xxx'"
}

output "fill_arc_github_app" {
  description = "GitHub App for the in-cluster runners (ARC). Create the App on your repo, install it, download its private key, then run this."
  value       = <<-EOT
    aws secretsmanager put-secret-value --region ${var.region} \
      --secret-id ${aws_secretsmanager_secret.student["arc/github-app"].name} \
      --secret-string "$(jq -n --arg id 'APP_ID' --arg inst 'INSTALLATION_ID' --rawfile key app.private-key.pem \
        '{github_app_id: $id, github_app_installation_id: $inst, github_app_private_key: $key}')"
  EOT
}

output "argocd_admin_password" {
  description = "First Argo CD login is user admin with this password."
  value       = "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
}
