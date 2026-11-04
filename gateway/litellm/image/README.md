# The gateway image

The official LiteLLM image plus `mlflow-skinny` (the MLflow client) and `sagemaker-mlflow` (signs each call to the
SageMaker MLflow App with the pod's AWS role). Build it once per LiteLLM version and push it to ECR.

Run from the repository's main folder:

```bash
REPO=$(terraform -chdir=terraform/foundations output -raw gateway_image_repo)
REGION=$(terraform -chdir=terraform/foundations output -raw region)
TAG=v1.106.5-mlflow1          # the LiteLLM version, then our own build number
aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "${REPO%%/*}"
docker build --platform linux/amd64 --provenance=false -t "$REPO:$TAG" gateway/litellm/image
docker push "$REPO:$TAG"
```

`--provenance=false` pushes one plain image. Without it, Docker pushes an image index with a provenance
attestation, and ECR basic scanning cannot scan an index (it reports `UnsupportedImageTypeException`).

If you use another tag, change `image.tag` in `gateway/litellm/values.yaml`, commit and push.
Argo CD sets `image.repository` to this ECR repository (argocd/apps/gateway.yaml).
