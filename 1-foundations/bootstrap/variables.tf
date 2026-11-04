variable "region" {
  description = "AWS region for the state bucket. Use the same region as the cluster."
  type        = string
  default     = "us-east-1"
}

variable "name" {
  description = "Name prefix for every resource."
  type        = string
  default     = "astra"
}
