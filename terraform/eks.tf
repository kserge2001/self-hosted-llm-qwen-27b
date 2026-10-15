module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.29"

  name               = local.name
  kubernetes_version = var.kubernetes_version

  # The Kubernetes API is reachable from the internet only from admin_cidrs, and privately inside the VPC.
  endpoint_public_access       = true
  endpoint_public_access_cidrs = var.admin_cidrs
  endpoint_private_access      = true

  # Whoever runs `terraform apply` becomes cluster admin through an EKS access entry.
  enable_cluster_creator_admin_permissions = true

  # EKS Auto Mode: AWS runs node provisioning (Karpenter), networking, storage, load balancers,
  # Pod Identity and the NVIDIA GPU drivers. The two built-in pools run the CPU workloads.
  # The GPU pool is added from k8s/10-gpu-nodepool.yaml.
  compute_config = {
    enabled    = true
    node_pools = ["general-purpose", "system"]
  }

  # The control plane lives in 3 zones, fixed when the cluster is created.
  # Nodes may use every private subnet: the GPU NodeClass finds them by tag, in up to 4 zones.
  vpc_id                   = module.vpc.vpc_id
  control_plane_subnet_ids = slice(module.vpc.private_subnets, 0, 3)
  subnet_ids               = module.vpc.private_subnets
}
