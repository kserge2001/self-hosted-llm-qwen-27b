# Argo CD and the GitOps Bridge.
#
# Terraform knows things Argo CD needs (bucket names, role names, the certificate ARN).
# The GitOps Bridge passes them over in one place: the in-cluster cluster Secret.
#   labels       enable_<addon> = "true"   -> which add-ons the ApplicationSets install
#   annotations  aws_vpc_id, models_bucket ... -> values the ApplicationSets template in
#                with {{metadata.annotations.<key>}}
# This is what the gitops-bridge-dev/gitops-bridge/helm module does. We write the two resources
# here because its last registry release (0.1.0, 2024-03) predates the Helm provider 3 syntax.

resource "helm_release" "argocd" {
  name             = "argo-cd"
  namespace        = "argocd"
  create_namespace = true
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "10.11.6" # Argo CD v3.5.6, chart released 2026-10-26
  wait             = true

  values = [
    yamlencode({
      global = {
        # Stay on the system node group, so Karpenter consolidation never moves Argo CD.
        nodeSelector = { "karpenter.sh/controller" = "true" }
      }
      configs = {
        params = {
          # TLS ends at the internal ALB (ACM certificate). The Ingress is made in platform/cluster-base.
          "server.insecure" = true
        }
      }
    })
  ]

  depends_on = [module.eks]
}

locals {
  # Values for Argo CD, all from this stack. The ApplicationSets read them by these exact names.
  gitops_annotations = {
    aws_region                = var.region
    aws_account_id            = local.account_id
    aws_cluster_name          = module.eks.cluster_name
    aws_vpc_id                = module.vpc.vpc_id
    domain                    = var.domain
    acm_certificate_arn       = aws_acm_certificate_validation.this.certificate_arn
    models_bucket             = aws_s3_bucket.this["models"].bucket
    rds_host                  = aws_db_instance.this.address
    bedrock_guardrail_id      = aws_bedrock_guardrail.this.guardrail_id
    bedrock_guardrail_version = aws_bedrock_guardrail_version.this.version
    karpenter_node_role       = module.karpenter.node_iam_role_name
    karpenter_queue           = module.karpenter.queue_name
    app_image_repo            = aws_ecr_repository.app.repository_url
    gateway_image_repo        = aws_ecr_repository.gateway.repository_url
    mlflow_tracking_arn       = aws_sagemaker_mlflow_app.this.arn # MLFLOW_TRACKING_URI of the gateway
    repo_url                  = var.repo_url
    repo_revision             = var.repo_revision
  }

  gitops_labels = merge(
    { for addon, on in var.addons : "enable_${addon}" => tostring(on) },
    { for app, on in var.apps : "enable_${app}" => tostring(on) },
    {
      "argocd.argoproj.io/secret-type" = "cluster" # makes Argo CD read this Secret as a cluster
      cluster_name                     = module.eks.cluster_name
    },
  )
}

# The cluster Secret for the cluster Argo CD runs in ("in-cluster").
resource "kubernetes_secret_v1" "gitops_bridge" {
  metadata {
    name        = "in-cluster"
    namespace   = "argocd"
    labels      = local.gitops_labels
    annotations = local.gitops_annotations
  }

  data = {
    name   = "in-cluster"
    server = "https://kubernetes.default.svc"
    config = jsonencode({ tlsClientConfig = { insecure = false } })
  }

  depends_on = [helm_release.argocd]
}

# The one root Application. Everything else comes from Git: it applies every file under argocd/
# in your repository (argocd/addons for the shared tools, argocd/apps for the model server, the
# gateway and the apps). Each file there is an ApplicationSet that reads the cluster Secret above.
# To add something to the cluster, you add a file under argocd/, commit and push.
# Chart argocd-apps 2.0.7, released 2026-10-16.
resource "helm_release" "argocd_root" {
  name       = "argocd-apps"
  namespace  = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argocd-apps"
  version    = "2.0.7"

  values = [
    yamlencode({
      applications = {
        platform = {
          namespace = "argocd"
          project   = "default"
          source = {
            repoURL        = var.repo_url
            targetRevision = var.repo_revision
            path           = "argocd"
            directory      = { recurse = true } # read argocd/addons and argocd/apps
          }
          destination = {
            server    = "https://kubernetes.default.svc"
            namespace = "argocd"
          }
          syncPolicy = {
            automated   = { prune = true, selfHeal = true }
            syncOptions = ["ServerSideApply=true"]
          }
        }
      }
    })
  ]

  # The ApplicationSets need the cluster Secret, and the add-ons need their Pod Identity roles.
  depends_on = [
    kubernetes_secret_v1.gitops_bridge,
    module.workload_pod_identity,
    module.aws_lb_controller_pod_identity,
    module.external_dns_pod_identity,
    module.external_secrets_pod_identity,
  ]
}
