output "region" {
  value = var.region
}

output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_security_group_id" {
  value = module.eks.cluster_primary_security_group_id
}

output "node_role_name" {
  description = "IAM role of the Auto Mode nodes. The GPU NodeClass reuses it."
  value       = module.eks.node_iam_role_name
}

output "model_bucket" {
  value = aws_s3_bucket.models.bucket
}

output "secret_id" {
  description = "Secrets Manager secret holding the gateway, model server and Grafana secrets."
  value       = aws_secretsmanager_secret.platform.id
}

output "configure_kubectl" {
  value = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}
