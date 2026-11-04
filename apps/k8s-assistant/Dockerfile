# Slim image, no build tools, runs as a normal user.
# python:3.15.2-slim is the latest stable Python image on Docker Hub, checked 2026-10-28.
FROM python:3.15.2-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /app
# Requirements first: this layer is reused while only the code changes.
COPY requirements.txt .
RUN pip install -r requirements.txt

COPY app/ app/

# A fixed numeric user, so Kubernetes runAsNonRoot can check it.
RUN useradd --uid 10001 --no-create-home --shell /usr/sbin/nologin assistant
USER 10001

EXPOSE 8080
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080"]
