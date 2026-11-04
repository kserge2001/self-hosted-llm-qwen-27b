# Private image registries. You build each image on your laptop and push it here:
#   astra/k8s-assistant  the example app (apps/k8s-assistant/README.md)
#   astra/litellm        the gateway: the official LiteLLM image plus the MLflow client (gateway/litellm/image)
# The nodes pull with their own role: the Karpenter node role has AmazonEC2ContainerRegistryPullOnly.

resource "aws_ecr_repository" "app" {
  name                 = "${var.name}/k8s-assistant"
  image_tag_mutability = "IMMUTABLE" # a tag always means the same image
  force_delete         = true        # lab only: lets terraform destroy delete it with its images

  image_scanning_configuration {
    scan_on_push = true # basic scan for known vulnerabilities in each pushed image
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

# Keep the last 10 images, so old ones do not pile up.
resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "keep the last 10 images"
      selection    = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = 10 }
      action       = { type = "expire" }
    }]
  })
}

resource "aws_ecr_repository" "gateway" {
  name                 = "${var.name}/litellm"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true # lab only

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

resource "aws_ecr_lifecycle_policy" "gateway" {
  repository = aws_ecr_repository.gateway.name
  policy     = aws_ecr_lifecycle_policy.app.policy # the same rule: keep the last 10 images
}
