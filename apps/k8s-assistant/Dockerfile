# Small Alpine image, no build tools, runs as a normal user.
# python:3.15.2-alpine (Alpine 3.24) is the latest stable Python image on Docker Hub, checked 2026-11-04.
# Alpine instead of Debian slim: the slim image had 4 HIGH findings in Debian packages (glibc, zlib,
# apt) with no fix yet. Every package below has a musllinux wheel, so nothing is compiled.
FROM python:3.15.2-alpine

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /app
# Requirements first: this layer is reused while only the code changes.
COPY requirements.txt .
# Then remove pip: the running app never needs it, and pip carries its own old copies of urllib3,
# msgpack and setuptools (pip/_vendor), which scanners report as HIGH findings.
RUN pip install -r requirements.txt  && pip uninstall -y pip  && rm -rf /usr/local/lib/python3.*/ensurepip

COPY app/ app/

# A fixed numeric user, so Kubernetes runAsNonRoot can check it.
RUN adduser -D -H -u 10001 -s /sbin/nologin assistant
USER 10001

EXPOSE 8080
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080"]
