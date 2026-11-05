# k8s-assistant: an app that uses Astra

In a company, an app team owns this folder, with its own team key.

The app answers questions about the cluster. It calls Astra through the gateway with the OpenAI SDK. The model asks for cluster data with tool calls. The app runs three read-only functions:

| Tool | What it returns |
|---|---|
| `list_pods` | pods in a namespace: phase, ready, restarts, waiting reason |
| `describe_deployment` | replicas, ready replicas, images, conditions |
| `recent_events` | the newest events in a namespace |

The app cannot change the cluster. Its ClusterRole allows only `get` and `list` on pods, events, namespaces and deployments. It cannot read Secrets or ConfigMaps.

## Files

| Path | What it is |
|---|---|
| `app/` | the FastAPI app: `POST /ask`, `GET /health` |
| `tests/test_app.py` | unit tests, no cluster and no gateway |
| `tests/promptfooconfig.yaml` | promptfoo tests against the real gateway |
| `Dockerfile` | small Alpine image without pip, runs as user 10001 |
| `deploy/` | namespace, read-only RBAC, ExternalSecret for the key, Deployment, Service |
| `../../argocd/apps/k8s-assistant.yaml` | the Argo CD ApplicationSet |

## Before you start

The team `k8s-assistant` must be in `gateway/teams.yaml`, and `gateway/sync_teams.py` must have run. It writes the key to `astra/teams/k8s-assistant` in Secrets Manager. The app reads it from there.

## Build, test, deploy

Run from the repository's main folder.

1. Unit tests:

```bash
cd apps/k8s-assistant
pip install -r requirements-dev.txt
pytest -q
ruff check .
cd ../..
```

2. Build the image and push it to ECR. Pick a new tag for every build: the ECR repository does not allow a tag to be reused.

```bash
REPO=$(terraform -chdir=terraform/foundations output -raw app_image_repo)
REGION=$(terraform -chdir=terraform/foundations output -raw region)
TAG=0.1.0
aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "${REPO%%/*}"
docker build --platform linux/amd64 --provenance=false -t "$REPO:$TAG" apps/k8s-assistant
docker push "$REPO:$TAG"
```

`--provenance=false` pushes one plain image. Without it, Docker pushes an image index with a provenance
attestation, and ECR basic scanning cannot scan an index (it reports `UnsupportedImageTypeException`).

3. Put the tag in `argocd/apps/k8s-assistant.yaml` (under `kustomize.images`), commit and push. Argo CD deploys it.

4. promptfoo, against the real gateway (in a second terminal: `kubectl -n gateway port-forward svc/litellm 4000:4000`):

```bash
export OPENAI_BASE_URL=http://localhost:4000/v1
export OPENAI_API_KEY=$(aws secretsmanager get-secret-value --secret-id astra/teams/k8s-assistant --query SecretString --output text | jq -r .api_key)
cd apps/k8s-assistant && npx promptfoo@0.125.1 eval -c tests/promptfooconfig.yaml --no-cache
```

## Check it

```bash
kubectl -n k8s-assistant port-forward svc/k8s-assistant 8081:80   # 8080 is the Argo CD tunnel
curl -s localhost:8081/ask -H 'Content-Type: application/json' \
  -d '{"question": "Are all pods in the serving namespace ready?", "user": "maria.lopez@example.com"}'
```

The answer names the vLLM pods, and `tools_used` shows `list_pods`. The `user` value appears with its spend in the gateway.
