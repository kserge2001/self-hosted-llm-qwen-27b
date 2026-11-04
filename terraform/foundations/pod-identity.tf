# Workload identity with EKS Pod Identity: each Kubernetes service account gets its own IAM role.
# No access keys anywhere, and each component can do one job.
# The roles exist before the apps: Argo CD installs the apps later, and the pods pick up the role
# as soon as their service account appears.

locals {
  bucket_arn = { for k, b in aws_s3_bucket.this : k => b.arn }

  # S3 permission sets, reused below.
  s3_read = {
    list   = ["s3:ListBucket", "s3:GetBucketLocation"]
    object = ["s3:GetObject"]
  }
  s3_write = {
    list   = ["s3:ListBucket", "s3:GetBucketLocation", "s3:ListBucketMultipartUploads"]
    object = ["s3:GetObject", "s3:PutObject", "s3:AbortMultipartUpload", "s3:ListMultipartUploadParts"]
  }
  s3_read_write = {
    list   = local.s3_write.list
    object = concat(local.s3_write.object, ["s3:DeleteObject"])
  }

  # namespace / service account => S3 access per bucket, plus any extra statements.
  workloads = {
    model-loader = {
      # The Job in model/ that copies the model from Hugging Face to the models bucket.
      namespace = "models"
      s3        = { models = local.s3_write }
      extra = [
        {
          sid       = "ReadHfToken"
          actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
          resources = [aws_secretsmanager_secret.student["hf-token"].arn]
        },
      ]
    }
    vllm = {
      namespace = "serving"
      s3        = { models = local.s3_read }
      extra     = []
    }
    litellm = {
      namespace = "gateway"
      # The MLflow client writes each trace's body (traces.json) straight to the MLflow bucket with
      # this role; the App API call only registers the trace. Without it: AccessDenied, no traces.
      s3 = { mlflow = local.s3_write }
      extra = [
        {
          sid       = "ApplyGuardrail"
          actions   = ["bedrock:ApplyGuardrail"]
          resources = [aws_bedrock_guardrail.this.guardrail_arn]
        },
        {
          # Optional fallback model on Bedrock. Model access must also be enabled in the console.
          sid       = "InvokeFallbackModel"
          actions   = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"]
          resources = ["arn:${local.partition}:bedrock:*::foundation-model/*", "arn:${local.partition}:bedrock:*:${local.account_id}:inference-profile/*"]
        },
        {
          # One trace per request to the MLflow App (the sagemaker-mlflow plugin signs with this role).
          sid       = "WriteTraces"
          actions   = ["sagemaker:CallMlflowAppApi"]
          resources = [aws_sagemaker_mlflow_app.this.arn]
        },
      ]
    }
  }
}

# Workloads with a custom policy (one role each).
module "workload_pod_identity" {
  source   = "terraform-aws-modules/eks-pod-identity/aws"
  version  = "~> 2.10" # 2.10.0, 2026-10-17
  for_each = local.workloads

  name            = "${local.name}-${each.key}"
  use_name_prefix = false

  attach_custom_policy = true
  policy_statements = concat(
    flatten([
      for bucket, perms in each.value.s3 : [
        { sid = "${title(bucket)}Bucket", actions = perms.list, resources = [local.bucket_arn[bucket]] },
        { sid = "${title(bucket)}Objects", actions = perms.object, resources = ["${local.bucket_arn[bucket]}/*"] },
      ]
    ]),
    each.value.extra,
  )

  associations = {
    this = {
      cluster_name    = module.eks.cluster_name
      namespace       = each.value.namespace
      service_account = each.key
    }
  }
}

# Add-on controllers use the policies built into the module (the same JSON the projects publish).
module "aws_lb_controller_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 2.10"

  name                            = "${local.name}-aws-load-balancer-controller"
  use_name_prefix                 = false
  attach_aws_lb_controller_policy = true

  associations = {
    this = {
      cluster_name    = module.eks.cluster_name
      namespace       = "kube-system"
      service_account = "aws-load-balancer-controller"
    }
  }
}

module "external_dns_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 2.10"

  name                          = "${local.name}-external-dns"
  use_name_prefix               = false
  attach_external_dns_policy    = true
  external_dns_hosted_zone_arns = [data.aws_route53_zone.this.arn] # only the one zone

  associations = {
    this = {
      cluster_name    = module.eks.cluster_name
      namespace       = "external-dns"
      service_account = "external-dns"
    }
  }
}

module "external_secrets_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 2.10"

  name                                  = "${local.name}-external-secrets"
  use_name_prefix                       = false
  attach_external_secrets_policy        = true
  external_secrets_secrets_manager_arns = ["${local.secret_arn_prefix}/*"] # read only, astra/* only
  external_secrets_create_permission    = false

  associations = {
    this = {
      cluster_name    = module.eks.cluster_name
      namespace       = "external-secrets"
      service_account = "external-secrets"
    }
  }
}

# EBS CSI driver (EKS add-on). The eks module creates its association, see eks.tf.
module "ebs_csi_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 2.10"

  name                      = "${local.name}-ebs-csi"
  use_name_prefix           = false
  attach_aws_ebs_csi_policy = true
}
