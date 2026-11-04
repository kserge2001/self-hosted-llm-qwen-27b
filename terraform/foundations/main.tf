data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

# Only use Availability Zones that sell the GPU instance. GPU capacity is not in every zone.
data "aws_ec2_instance_type_offerings" "gpu" {
  location_type = "availability-zone"

  filter {
    name   = "instance-type"
    values = [local.gpu_zone_probe]
  }
}

# The zone that the certificate and external-dns use.
data "aws_route53_zone" "this" {
  name         = var.domain
  private_zone = false
}

locals {
  name       = var.name # cluster name `astra`
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition

  # g6e.xlarge is the smallest GPU the model runs on. Zones that sell it usually sell the bigger g6e too.
  gpu_zone_probe = "g6e.xlarge"
  azs            = slice(sort(data.aws_ec2_instance_type_offerings.gpu.locations), 0, min(3, length(data.aws_ec2_instance_type_offerings.gpu.locations)))
  vpc_cidr       = "10.0.0.0/16"

  # Host names behind the one internal ALB. All three go on one ACM certificate.
  hosts = {
    gateway = "astra.${var.domain}"
    argocd  = "argocd.${var.domain}"
    grafana = "grafana.${var.domain}"
  }

  # Secrets Manager ARN prefix. Real ARNs end with a random 6-character suffix, hence the wildcard.
  secret_arn_prefix = "arn:${local.partition}:secretsmanager:${var.region}:${local.account_id}:secret:${var.name}"
}

check "enough_gpu_zones" {
  assert {
    condition     = length(local.azs) == 3
    error_message = "${local.gpu_zone_probe} is sold in fewer than 3 Availability Zones in ${var.region}. Pick another region."
  }
}
