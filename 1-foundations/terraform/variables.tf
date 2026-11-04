variable "region" {
  description = "AWS region. It must sell g6e GPU instances in at least 3 Availability Zones."
  type        = string
  default     = "us-east-1"
}

variable "name" {
  description = "Name prefix for every resource. Also the EKS cluster name."
  type        = string
  default     = "astra"
}

variable "kubernetes_version" {
  description = "EKS Kubernetes version. 1.37 is the newest in EKS standard support (checked 2026-10-28)."
  type        = string
  default     = "1.37"
}

variable "domain" {
  description = "A public Route 53 hosted zone you own, for example lab.example.com. Host names are <app>.<domain>."
  type        = string
  # No default: Terraform looks the zone up, so a made-up name would fail.
}

variable "admin_cidrs" {
  description = "Public IP ranges allowed to reach the Kubernetes API, for example [\"203.0.113.7/32\"]. Include the machine that runs Terraform."
  type        = list(string)
  # No default: 0.0.0.0/0 would open the API to the whole internet.
}

variable "repo_url" {
  description = "Git repository that Argo CD reads (your fork of the course repo)."
  type        = string
  default     = "https://github.com/kserge2001/self-hosted-llm-qwen-27b.git"
}

variable "repo_revision" {
  description = "Branch, tag or commit that Argo CD follows."
  type        = string
  default     = "main"
}

variable "db_instance_class" {
  description = "RDS PostgreSQL size for the litellm database."
  type        = string
  default     = "db.t4g.small"
}

variable "system_instance_types" {
  description = "Instance types of the small managed node group for system pods (Karpenter, Argo CD, add-ons)."
  type        = list(string)
  default     = ["m7i.large"]
}

variable "admin_principal_arns" {
  description = "Extra IAM role or user ARNs that get cluster admin (for example an instructor role). The creator is always admin."
  type        = list(string)
  default     = []
}

variable "addons" {
  description = "Add-ons Argo CD installs from 2-platform. Each key becomes the label enable_<key> on the cluster Secret."
  type        = map(bool)
  default = {
    aws_load_balancer_controller = true
    external_dns                 = true
    external_secrets             = true
    karpenter_nodepools          = true
    kyverno                      = true
    keda                         = true
    kube_prometheus_stack        = true
    dcgm_exporter                = true
    arc                          = true
    db_init                      = true # the litellm database on RDS (2-platform/db-init)
    # Langfuse (stage 5) needs the ClickHouse operator, and the operator needs cert-manager.
    cert_manager        = true
    clickhouse_operator = true
  }
}
