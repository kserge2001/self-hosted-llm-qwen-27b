# MLflow model registry: a SageMaker AI MLflow App (serverless managed MLflow), named `astra`.
# AWS runs the server and its metadata database. We own only the artifact bucket and one role.
# Why an App and not a tracking server (AWS docs, checked 2026-10-28): Apps are the current managed
# MLflow offering and "should be preferred over" tracking servers. No size to pick, no hourly price,
# and AWS keeps the MLflow version up to date (3.16 today). The resource exists since AWS provider 6.35.0.
#
# Clients use the app ARN as MLFLOW_TRACKING_URI. The sagemaker-mlflow plugin signs every call with
# the caller's own AWS credentials, so access is plain IAM: sagemaker:CallMlflowAppApi on this ARN.

# The app's own role. SageMaker uses it for as long as the app exists, to read and write the artifacts.
resource "aws_iam_role" "mlflow_app" {
  name = "${local.name}-mlflow-app"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "sagemaker.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# The S3 actions the AWS docs list for the app role, but on the MLflow bucket only.
resource "aws_iam_role_policy" "mlflow_app" {
  name = "artifact-store"
  role = aws_iam_role.mlflow_app.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:Get*", "s3:Put*", "s3:List*"]
      Resource = [aws_s3_bucket.this["mlflow"].arn, "${aws_s3_bucket.this["mlflow"].arn}/*"]
    }]
  })
}

resource "aws_sagemaker_mlflow_app" "this" {
  name               = local.name
  role_arn           = aws_iam_role.mlflow_app.arn
  artifact_store_uri = "s3://${aws_s3_bucket.this["mlflow"].bucket}/"
  # MLflow is the registry. No copy of each version in the SageMaker Model Registry.
  model_registration_mode = "AutoModelRegistrationDisabled"

  # The app must be able to use its role and bucket from the first minute.
  depends_on = [aws_iam_role_policy.mlflow_app]
}
