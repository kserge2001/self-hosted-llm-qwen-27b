# Versions checked on the Terraform Registry on 2026-10-28.
terraform {
  required_version = ">= 1.10" # use_lockfile (S3 native locking) needs 1.10+

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.70" # 6.70.0, 2026-10-22
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.9" # 2.9.1, 2026-09-10
    }
  }

  # No backend here: this stack creates the state bucket, so its own (tiny) state stays local.
  # Keep terraform.tfstate from this folder, or import the bucket again if you lose it.
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = var.name
      Stage     = "bootstrap"
      ManagedBy = "terraform"
    }
  }
}
