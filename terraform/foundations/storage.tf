# Two buckets, named <name>-<job>-<account> (bucket names are global).
#   models - model weights, prefix <model>/<revision>/ (written by the Job in model/)
#   mlflow - the artifact store of the MLflow App (mlflow.tf)
locals {
  buckets = {
    models = "${var.name}-models-${local.account_id}"
    mlflow = "${var.name}-mlflow-${local.account_id}"
  }
}

resource "aws_s3_bucket" "this" {
  for_each = local.buckets

  bucket        = each.value
  force_destroy = true # lab only: lets `terraform destroy` delete the buckets with their files (weights, MLflow artifacts)
}

resource "aws_s3_bucket_versioning" "this" {
  for_each = aws_s3_bucket.this

  bucket = each.value.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  for_each = aws_s3_bucket.this

  bucket = each.value.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  for_each = aws_s3_bucket.this

  bucket                  = each.value.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
