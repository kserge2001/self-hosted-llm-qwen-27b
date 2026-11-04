# The gateway image: the official LiteLLM image plus the MLflow client and AWS's sagemaker-mlflow plugin,
# so LiteLLM can send its traces to the SageMaker MLflow App. The official image has no MLflow client.
# Build and push it (gateway/litellm/image/README.md). Pinned versions: latest on PyPI, checked 2026-11-04.
FROM ghcr.io/berriai/litellm:v1.106.5

# LiteLLM's Python lives in /app/.venv, which has no pip (the image is built with uv).
# So take the uv binary from its official image and install into that same environment.
COPY --from=ghcr.io/astral-sh/uv:0.13.7 /uv /usr/local/bin/uv
RUN uv pip install --python /app/.venv/bin/python --no-cache mlflow-skinny==3.18.0 sagemaker-mlflow==0.5.0
