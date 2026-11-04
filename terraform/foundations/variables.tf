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
  description = "Git repository that Argo CD reads: your copy (fork) of the repository. It must be public, or Argo CD needs a login for it."
  type        = string
  # No default: Argo CD must read your repository.
}

variable "repo_revision" {
  description = "Branch, tag or commit that Argo CD follows."
  type        = string
  default     = "main"
}

variable "db_instance_class" {
  description = "RDS PostgreSQL size for the litellm database. The smallest class is enough for the lab."
  type        = string
  default     = "db.t4g.micro"
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

variable "apps" {
  description = "Which apps in argocd/apps Argo CD deploys. All off at first; the guide turns each one on in its own step. Each key becomes the label enable_<key> on the cluster Secret."
  type = object({
    serving       = optional(bool, false) # vLLM (argocd/apps/serving.yaml), needs the model in S3 first
    gateway       = optional(bool, false) # LiteLLM, Redis, Presidio (argocd/apps/gateway.yaml)
    k8s_assistant = optional(bool, false) # the example app (argocd/apps/k8s-assistant.yaml)
  })
  default = {}
}

variable "addons" {
  description = "Add-ons Argo CD installs from argocd/addons. Each key becomes the label enable_<key> on the cluster Secret."
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
    db_init                      = true # the litellm database on RDS (platform/db-init)
  }
}
