# Stage 6: k8s-assistant, an app that uses Astra

In a company, an app team owns this folder. It has its own CI and its own team key.

The app answers questions about the cluster. It calls Astra through the gateway with the OpenAI SDK. The model asks for cluster data with tool calls. The app runs three read-only functions:

| Tool | What it returns |
|---|---|
| `list_pods` | pods in a namespace: phase, ready, restarts, waiting reason |
| `describe_deployment` | replicas, ready replicas, images, conditions |
| `recent_events` | the newest events in a namespace |

The app cannot change the cluster. Its ClusterRole allows only `get` and `list` on pods, events, namespaces and deployments. It cannot read Secrets or ConfigMaps.

## Before you start

The team `k8s-assistant` must exist in `5-gateway/teams/teams.yaml` (name, `budget_usd`, `rpm`, `tpm`). Stage 5 owns that file, so ask the AI platform team to add it. The teams workflow then writes the key to `astra/teams/k8s-assistant` in Secrets Manager. This app reads it from there.

## Files

| Path | What it is |
|---|---|
| `app/` | the FastAPI app: `POST /ask`, `GET /health` |
| `tests/test_app.py` | unit tests, no cluster and no gateway |
| `tests/promptfooconfig.yaml` | promptfoo tests against the real gateway |
| `Dockerfile` | slim image, runs as user 10001 |
| `deploy/` | namespace, read-only RBAC, ExternalSecret for the key, Deployment, Service |
| `argocd/k8s-assistant.yaml` | the Argo CD ApplicationSet (one Application, like stages 4 and 5) |
| `../../.github/workflows/app-ci.yml` | lint, unit tests, image to GHCR, promptfoo on `arc-runner` |

## Run it

1. The image in `deploy/kustomization.yaml` is `ghcr.io/kserge2001/k8s-assistant`. If you use a fork, put your GitHub user or organisation (lower case) there. Argo CD fills in the domain and the repository by itself.
2. Set the repository variable `ASTRA_DOMAIN` in GitHub (Settings, Variables). The promptfoo job uses it.
3. Push. CI builds the image `ghcr.io/<owner>/k8s-assistant:sha-<commit>`. Put that tag in `deploy/kustomization.yaml`.
4. Make the GHCR package `k8s-assistant` public (GitHub > Packages > Package settings > Change visibility). The cluster pulls the image without a login, so a private package fails with `ImagePullBackOff`. To keep it private, add an image pull secret to the deployment instead.
5. Add the app to Argo CD: `kubectl apply -f 6-app/k8s-assistant/argocd/k8s-assistant.yaml`

## The check that ends this stage

```bash
kubectl -n k8s-assistant port-forward svc/k8s-assistant 8080:80
curl -s localhost:8080/ask -H 'Content-Type: application/json' \
  -d '{"question": "Are all pods in the serving namespace ready?", "user": "maria.lopez@example.com"}'
```

The answer names the vLLM pods, and `tools_used` shows `list_pods`. The `user` value appears with its spend in the gateway. The promptfoo job in CI is green.
