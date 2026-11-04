module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.29" # 21.29.0, 2026-10-07

  name               = local.name
  kubernetes_version = var.kubernetes_version

  # The Kubernetes API is reachable from the internet only from admin_cidrs, and privately inside the VPC.
  endpoint_public_access       = true
  endpoint_public_access_cidrs = var.admin_cidrs
  endpoint_private_access      = true

  # Pods get AWS roles through EKS Pod Identity (pod-identity.tf), so no IAM OIDC provider for IRSA.
  enable_irsa = false

  # EKS already encrypts all Kubernetes API data (Secrets included) with an AWS owned key, at no cost
  # (Kubernetes 1.28 and later). So no customer managed KMS key: nothing to pay for, and nothing that
  # waits 7-30 days to be deleted after terraform destroy. A company that must hold its own key sets one.
  create_kms_key    = false
  encryption_config = null

  # Control-plane logs in CloudWatch: only the audit log (who did what in the cluster), kept 7 days.
  # Lab setting. Production keeps api, audit and authenticator, for as long as the company's rules say.
  enabled_log_types                      = ["audit"]
  cloudwatch_log_group_retention_in_days = 7

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
      # Without this, EKS stores NetworkPolicy objects but nothing enforces them
      # (the vLLM policy in serving/ would allow every namespace).
      configuration_values = jsonencode({ enableNetworkPolicy = "true" })
    }
    eks-pod-identity-agent = {
      before_compute = true
    }
    # Persistent volumes (Prometheus, the model loader's work disk) need the EBS CSI driver.
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
  # Every other node (CPU and GPU) is created by Karpenter from the NodePools in platform/karpenter.
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
