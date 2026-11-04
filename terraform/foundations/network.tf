module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.7" # 6.7.3, 2026-09-18

  name = local.name
  cidr = local.vpc_cidr
  azs  = local.azs

  # Private subnets hold the nodes, pods and database: 10.0.0.0/20, 10.0.16.0/20, 10.0.32.0/20 (4,091 IPs each).
  # Public subnets only hold the NAT gateway: 10.0.240.0/24, ... at the top of the range.
  private_subnets = [for i, az in local.azs : cidrsubnet(local.vpc_cidr, 4, i)]
  public_subnets  = [for i, az in local.azs : cidrsubnet(local.vpc_cidr, 8, i + 240)]

  # One NAT gateway for the lab. Production uses one per zone, so one zone failing does not cut the others off.
  enable_nat_gateway = true
  single_nat_gateway = true

  enable_dns_hostnames = true
  enable_dns_support   = true

  public_subnet_tags = { "kubernetes.io/role/elb" = 1 }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1          # the internal ALB lands here
    "karpenter.sh/discovery"          = local.name # Karpenter EC2NodeClass finds the subnets by this tag
  }
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
