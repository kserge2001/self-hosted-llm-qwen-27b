data "aws_caller_identity" "current" {}

locals {
  # Bucket names are global, so the account id makes the name unique.
  state_bucket = "${var.name}-tfstate-${data.aws_caller_identity.current.account_id}"
}

# --- State bucket: one per account, shared by every Terraform stack of the course -------------------

resource "aws_s3_bucket" "state" {
  bucket = local.state_bucket

  # The state is the only record of what Terraform built. Never delete it by accident.
  lifecycle {
    prevent_destroy = true
  }
}

# Every apply writes a new object version, so a broken state can be rolled back.
resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

# State holds secrets (generated passwords), so it is encrypted at rest.
resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Old state versions pile up with each apply. Keep the last 90 days.
resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    id     = "expire-old-versions"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

# Refuse any request that is not HTTPS.
data "aws_iam_policy_document" "tls_only" {
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.state.arn,
      "${aws_s3_bucket.state.arn}/*",
    ]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "state" {
  bucket = aws_s3_bucket.state.id
  policy = data.aws_iam_policy_document.tls_only.json

  # The public access block must exist first, or the policy call can race with it.
  depends_on = [aws_s3_bucket_public_access_block.state]
}

# --- Backend settings for the main stack ------------------------------------------------------------
# `terraform init -backend-config=backend.hcl` in ../foundations reads this file.
# use_lockfile = S3 native locking (a .tflock object). No DynamoDB table needed any more.

resource "local_file" "backend" {
  filename        = "${path.module}/../foundations/backend.hcl"
  file_permission = "0644"
  content         = <<-EOT
    bucket       = "${aws_s3_bucket.state.bucket}"
    key          = "foundations/terraform.tfstate"
    region       = "${var.region}"
    encrypt      = true
    use_lockfile = true
  EOT
}
