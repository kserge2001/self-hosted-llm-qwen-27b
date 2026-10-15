terraform {
  required_version = ">= 1.5.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # In a company, state lives in S3 with locking, never on a laptop.
  # Create a bucket once, then uncomment this block and run `terraform init -migrate-state`.
  # backend "s3" {
  #   bucket       = "YOUR-TFSTATE-BUCKET"
  #   key          = "astra/terraform.tfstate"
  #   region       = "us-east-1"
  #   use_lockfile = true
  #   encrypt      = true
  # }
}

provider "aws" {
  region = var.region

  # Every resource carries these tags, so Cost Explorer can show what Astra costs.
  default_tags {
    tags = {
      Project     = "astra"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}
