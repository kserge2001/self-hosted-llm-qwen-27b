# The gateway image: the official LiteLLM image plus the MLflow client and AWS's sagemaker-mlflow plugin,
# so LiteLLM can send its traces to the SageMaker MLflow App. The official image has no MLflow client.
# Build and push it (gateway/litellm/image/README.md). Pinned versions: latest on PyPI, checked 2026-11-04.
FROM ghcr.io/berriai/litellm:v1.106.5

RUN pip install --no-cache-dir mlflow-skinny==3.18.0 sagemaker-mlflow==0.5.0
