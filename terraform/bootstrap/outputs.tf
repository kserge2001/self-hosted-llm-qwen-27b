output "state_bucket" {
  description = "S3 bucket that holds the Terraform state of every stage."
  value       = aws_s3_bucket.state.bucket
}

output "next_step" {
  value = "cd ../foundations && terraform init -backend-config=backend.hcl"
}
