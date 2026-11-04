# Versions checked on the Terraform Registry on 2026-10-28.
terraform {
  required_version = ">= 1.10" # use_lockfile (S3 native locking) needs 1.10+

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.70" # 6.70.0, 2026-10-22
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.3" # 3.3.0, 2026-09-02
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.4" # 3.4.0, 2026-10-19
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.9" # 3.9.1, 2026-09-11
    }
  }

  # State lives in the bucket made by ../bootstrap. It wrote backend.hcl next to this file:
  #   terraform init -backend-config=backend.hcl
  backend "s3" {}
}

provider "aws" {
  region = var.region

  # Every resource carries these tags, so Cost Explorer can show what Astra costs.
  default_tags {
    tags = {
      Project   = var.name
      Stage     = "foundations"
      ManagedBy = "terraform"
    }
  }
}

# Helm and Kubernetes talk to the new cluster with a short-lived token from the AWS CLI.
# The machine running Terraform must reach the API, so its IP must be in admin_cidrs.
provider "helm" {
  kubernetes = {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.region]
    }
  }
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.region]
  }
}
