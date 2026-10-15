# Astra: an internal inference API on Amazon EKS

Astra is the company's internal inference API. The company's AI engineers call it from their applications exactly as they would call OpenAI: a base URL, a team key and the model name `astra`.

Behind the name runs **Qwen3.8-27B**, a model anyone can download and run (an open-weight model). The company downloaded it once and runs it on its own GPUs, the chips that do the model's arithmetic. No request leaves the company's AWS account, and no provider bills per token (a token is a piece of a word).

The GPUs still cost money every hour, so every team pays its share. Each team gets a key, a monthly budget and limits on requests and tokens per minute. The gateway, the front door every request goes through, prices every token at an internal rate and charges it to the team's budget. A dashboard shows what each team used.

Start with [docs/deployment-guide.md](docs/deployment-guide.md). It explains every idea in plain words, every decision and its options, and every build step. Step 9 is the API as an AI engineer uses it. The glossary defines every term used here.

## Calling Astra

```python
from openai import OpenAI

client = OpenAI(base_url="http://localhost:4000/v1", api_key="<your team key>")
response = client.chat.completions.create(model="astra", messages=[{"role": "user", "content": "Hello"}])
print(response.choices[0].message.content)
```

Streaming, tool calling, structured JSON output and per-user spend tracking all work through the same API (guide, step 9).

## What runs where

```
 applications built by AI engineers         EKS cluster (Auto Mode, private subnets, up to 4 Availability Zones)
 ──────────────────────────────────         ──────────────────────────────────────────────────────────────────
 HR assistant      ─┐
 Support bot       ─┤  team key   ┌──────────────┐  vLLM key  ┌──────────────────────────┐
 Data notebooks    ─┼───────────▶ │ LiteLLM x2   │──────────▶ │ vLLM replica 1  (zone A) │  1 x L40S GPU
 Any team's code   ─┘             │ gateway:     │            │ vLLM replica 2  (zone B) │  1 x L40S GPU
                                  │ keys,        │            └──────────────────────────┘
                                  │ budgets,     │                        ▲ weights copied at start
                                  │ rate limits, │                 S3 model bucket
                                  │ spend log    │
                                  └──────┬───────┘
                                         ▼
                               RDS PostgreSQL (teams, keys, spend)       Prometheus + Grafana
```

## Layout

| Path | What it holds | Applied with |
|---|---|---|
| `terraform/` | VPC, EKS Auto Mode cluster, S3 model bucket, RDS PostgreSQL, Secrets Manager, Pod Identity roles | `terraform apply` |
| `k8s/00-platform.yaml` | namespaces, default StorageClass, network policy switch | `kubectl apply` |
| `k8s/10-gpu-nodepool.yaml` | which GPU machines the cluster may start, and the GPU limit | `kubectl apply` |
| `k8s/20-model-loader.yaml` | one-off Job: Hugging Face to the S3 model bucket | `kubectl create` |
| `k8s/30-vllm.yaml` | the model servers, network lock, metrics, alerts | `kubectl apply` |
| `k8s/40-gateway.yaml` | LiteLLM gateway and Redis | `kubectl apply` |
| `k8s/60-monitoring-values.yaml` | Prometheus and Grafana | `helm install` |
| `k8s/70-dashboard.yaml` | the Grafana dashboard: GPU serving and spend by team | `kubectl apply` |
| `scripts/render.sh` | writes Terraform outputs into the manifests (output in `build/`) | `bash` |
| `scripts/create-secrets.sh` | copies secrets from Secrets Manager into the cluster | `bash` |
| `scripts/create-teams.sh` | creates teams, budgets, rate limits and keys | `bash` |
| `scripts/spend-report.sh` | what each team spent against its budget | `bash` |
| `examples/ask_astra.py` | how an AI engineer's app calls Astra | `python` |

## Cost

This runs two GPU machines. It costs about **$4.45 an hour** while it is up (see the Cost section of the guide). Tear it down when you finish (step 14 of the guide).
