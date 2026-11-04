# MLflow on Amazon SageMaker AI: a serverless MLflow App, named `astra`, in your own AWS account.
# The gateway (LiteLLM) sends one trace per request to it: the request, the answer and what LiteLLM
# adds, plus a tag team:<name> (gateway/sync_teams.py sets it). The traces never leave your account. The same App can also be the
# model registry of a company pipeline (05-model-pipeline explains it).
# AWS runs the server and its metadata database. We own only the artifact bucket and one role.
#
# Clients use the app ARN as MLFLOW_TRACKING_URI. The sagemaker-mlflow plugin (in the gateway image,
# gateway/litellm/image) signs every call with the caller's own AWS credentials, so access is plain IAM:
# sagemaker:CallMlflowAppApi on this ARN (pod-identity.tf gives it to the gateway).

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
  # No copy of each model version in the SageMaker Model Registry.
  model_registration_mode = "AutoModelRegistrationDisabled"

  # The app must be able to use its role and bucket from the first minute.
  depends_on = [aws_iam_role_policy.mlflow_app]
}
