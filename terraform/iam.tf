# Workload identity with EKS Pod Identity: each Kubernetes service account gets its own IAM role.
# No access keys anywhere, and each component can do one job.
#
#   namespace / service account   can do
#   llm / model-loader            write model weights to the model bucket
#   llm / vllm                    read model weights from the model bucket

data "aws_iam_policy_document" "pod_identity_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

locals {
  workloads = {
    model-loader = { actions = ["s3:GetObject", "s3:PutObject", "s3:AbortMultipartUpload"] }
    vllm         = { actions = ["s3:GetObject"] }
  }
}

resource "aws_iam_role" "workload" {
  for_each           = local.workloads
  name               = "${local.name}-${each.key}"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust.json
}

data "aws_iam_policy_document" "workload" {
  for_each = local.workloads

  statement {
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.models.arn]
  }
  statement {
    actions   = each.value.actions
    resources = ["${aws_s3_bucket.models.arn}/*"]
  }
}

resource "aws_iam_role_policy" "workload" {
  for_each = local.workloads
  name     = "models-bucket"
  role     = aws_iam_role.workload[each.key].id
  policy   = data.aws_iam_policy_document.workload[each.key].json
}

resource "aws_eks_pod_identity_association" "workload" {
  for_each        = local.workloads
  cluster_name    = module.eks.cluster_name
  namespace       = "llm"
  service_account = each.key
  role_arn        = aws_iam_role.workload[each.key].arn
}
