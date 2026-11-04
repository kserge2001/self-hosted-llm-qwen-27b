# Karpenter IAM pieces from the eks module's own submodule: the controller role (Pod Identity on
# kube-system/karpenter), the node role with its access entry, and the SQS queue for Spot interruptions.
module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 21.29" # 21.29.0, 2026-10-07

  cluster_name = module.eks.cluster_name

  # The EC2NodeClass in platform/karpenter names this role, so keep the name fixed (no random suffix).
  node_iam_role_use_name_prefix = false
  node_iam_role_name            = "${local.name}-karpenter-node"

  create_pod_identity_association = true
  namespace                       = "kube-system"
  service_account                 = "karpenter"

  # Lets you open a shell on a node with SSM Session Manager instead of SSH keys.
  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:${local.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }
}

# Chart 1.15.1 (GitHub releases, checked 2026-10-28). Karpenter 1.15.x is the line that supports Kubernetes 1.37.
resource "helm_release" "karpenter" {
  name       = "karpenter"
  namespace  = "kube-system"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  version    = "1.15.1"
  wait       = true

  values = [
    yamlencode({
      serviceAccount = { name = "karpenter" }
      nodeSelector   = { "karpenter.sh/controller" = "true" }
      # Resolve DNS from the VPC, so Karpenter works even before CoreDNS has pods.
      dnsPolicy = "Default"
      settings = {
        clusterName       = module.eks.cluster_name
        clusterEndpoint   = module.eks.cluster_endpoint
        interruptionQueue = module.karpenter.queue_name
      }
      webhook = { enabled = false }
    })
  ]

  # The Pod Identity association must exist before the pod starts, or it gets no AWS credentials.
  depends_on = [module.karpenter, module.eks]
}
