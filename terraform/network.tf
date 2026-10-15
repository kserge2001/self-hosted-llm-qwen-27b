data "aws_caller_identity" "current" {}

# Only use Availability Zones that sell the GPU instance. GPU capacity is not in every zone.
data "aws_ec2_instance_type_offerings" "gpu" {
  location_type = "availability-zone"

  filter {
    name   = "instance-type"
    values = [var.gpu_instance_type]
  }
}

locals {
  name       = "${var.name}-${var.environment}"
  account_id = data.aws_caller_identity.current.account_id
  azs        = slice(sort(data.aws_ec2_instance_type_offerings.gpu.locations), 0, min(4, length(data.aws_ec2_instance_type_offerings.gpu.locations)))
  vpc_cidr   = "10.0.0.0/16"
}

check "enough_gpu_zones" {
  assert {
    condition     = length(local.azs) >= 2
    error_message = "${var.gpu_instance_type} is sold in fewer than 2 Availability Zones in ${var.region}. Pick another region."
  }
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.7"

  name = local.name
  cidr = local.vpc_cidr
  azs  = local.azs

  # Private subnets hold the nodes, pods and database: 10.0.0.0/20, 10.0.16.0/20, ... (4,091 IPs each).
  # Public subnets only hold the NAT gateway: 10.0.240.0/24, 10.0.241.0/24, ... at the top of the range.
  private_subnets = [for i, az in local.azs : cidrsubnet(local.vpc_cidr, 4, i)]
  public_subnets  = [for i, az in local.azs : cidrsubnet(local.vpc_cidr, 8, i + 240)]

  # One NAT gateway for the lab. Production uses one per zone, so one zone failing does not cut the others off.
  enable_nat_gateway = true
  single_nat_gateway = true

  enable_dns_hostnames = true
  enable_dns_support   = true

  public_subnet_tags  = { "kubernetes.io/role/elb" = 1 }
  private_subnet_tags = { "kubernetes.io/role/internal-elb" = 1, "astra/cluster" = local.name }
}

# Model weights (about 31 GB per node start) come from S3 over the AWS network:
# free, fast, and not billed per GB through the NAT gateway.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = module.vpc.vpc_id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = module.vpc.private_route_table_ids
  tags              = { Name = "${local.name}-s3" }
}
