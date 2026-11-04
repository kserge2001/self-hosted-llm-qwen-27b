module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.29" # 21.29.0, 2026-10-07

  name               = local.name
  kubernetes_version = var.kubernetes_version

  # The Kubernetes API is reachable from the internet only from admin_cidrs, and privately inside the VPC.
  endpoint_public_access       = true
  endpoint_public_access_cidrs = var.admin_cidrs
  endpoint_private_access      = true

  # Whoever runs `terraform apply` becomes cluster admin through an EKS access entry.
  # Terraform needs this itself, to install Karpenter and Argo CD below.
  enable_cluster_creator_admin_permissions = true

  # More admins (an instructor, a CI role) are access entries too. No aws-auth ConfigMap.
  access_entries = {
    for i, arn in var.admin_principal_arns : "admin-${i}" => {
      principal_arn = arn
      policy_associations = {
        admin = {
          policy_arn   = "arn:${local.partition}:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = { type = "cluster" }
        }
      }
    }
  }

  # EKS-managed add-ons. vpc-cni and the Pod Identity agent must run before any node joins,
  # or the first pods start without networking or AWS credentials.
  addons = {
    coredns    = {}
    kube-proxy = {}
    vpc-cni = {
      before_compute = true
    }
    eks-pod-identity-agent = {
      before_compute = true
    }
    # Persistent volumes (Prometheus, Langfuse ClickHouse) need the EBS CSI driver.
    aws-ebs-csi-driver = {
      pod_identity_association = [{
        role_arn        = module.ebs_csi_pod_identity.iam_role_arn
        service_account = "ebs-csi-controller-sa"
      }]
    }
  }

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # A small fixed node group for the system pods: Karpenter cannot run on nodes it creates itself.
  # Every other node (CPU and GPU) is created by Karpenter from the NodePools in 2-platform.
  eks_managed_node_groups = {
    system = {
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = var.system_instance_types

      min_size     = 2
      max_size     = 3
      desired_size = 2

      labels = {
        # Karpenter and Argo CD use this label to stay on nodes Karpenter does not manage.
        "karpenter.sh/controller" = "true"
      }
    }
  }

  # Karpenter nodes join this security group (the EC2NodeClass selects it by tag).
  # Only one security group in the account should carry this tag for the cluster.
  node_security_group_tags = {
    "karpenter.sh/discovery" = local.name
  }
}
