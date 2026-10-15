variable "region" {
  description = "AWS region. It must sell g6e instances in at least 2 Availability Zones."
  type        = string
  default     = "us-east-1"
}

variable "name" {
  description = "Product name. Used in every resource name."
  type        = string
  default     = "astra"
}

variable "environment" {
  description = "Environment name, added to resource names and tags."
  type        = string
  default     = "lab"
}

variable "kubernetes_version" {
  description = "EKS Kubernetes version."
  type        = string
  default     = "1.36"
}

variable "admin_cidrs" {
  description = "Public IP ranges allowed to reach the Kubernetes API, for example [\"203.0.113.7/32\"]."
  type        = list(string)
}

variable "gpu_instance_type" {
  description = "GPU instance for the model servers. g6e.xlarge has one NVIDIA L40S with 48 GB."
  type        = string
  default     = "g6e.xlarge"
}

variable "db_instance_class" {
  description = "RDS PostgreSQL size for the gateway database (keys, teams, spend)."
  type        = string
  default     = "db.t4g.small"
}
