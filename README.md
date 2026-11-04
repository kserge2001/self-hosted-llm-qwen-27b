# Astra: an internal inference API on Amazon EKS

Astra is the company's own AI model API. Apps call it like OpenAI, with a base URL, a team key and the model name `astra`, but the model (Qwen3.8-27B) runs on the company's own GPUs in its own AWS account.

## The stages

You build Astra in eight stages, one folder each. Each stage ends with a check. Do not start the next stage before the check passes.

| Folder | What it builds | Who owns it in a company | The check that ends it |
|---|---|---|---|
| `1-foundations/` | the Terraform state bucket, then the network, EKS, Karpenter, IAM, S3, RDS, secrets, the certificate, the Bedrock guardrail, the MLflow registry (SageMaker MLflow App) and Argo CD | cloud platform team | `kubectl get nodes` works and Argo CD shows the `platform` app |
| `2-platform/` | the add-ons through Argo CD: Karpenter NodePools, Kyverno, External Secrets, monitoring, GitHub runners, the database setup Job | platform team | every add-on app in Argo CD is Synced and Healthy |
| `3-model-pipeline/` | download, scan, upload to S3, register in MLflow, eval gate, promotion pull request | ML engineers (MLOps) | the model version in MLflow has the alias `champion` |
| `4-serving/` | vLLM from our own Helm chart, serving the model as `astra` | ML platform team | `/v1/models` on `vllm.serving.svc:8000` lists `astra` |
| `5-gateway/` | the LiteLLM gateway with team keys, budgets, guardrails, and Langfuse traces | AI platform team | a call to `https://astra.<domain>/v1` with a team key answers, and the trace shows in Langfuse |
| `6-app/k8s-assistant/` | an app that answers questions about the cluster, with its own CI and promptfoo tests | an app team | `/ask` names the right pods, and the promptfoo job is green |
| `7-operate/` | spend report, canary release, teardown, runbooks | platform team and on-call | a canary was promoted or rolled back, and teardown left nothing behind |
| `8-production/` | nothing to build: what a company changes before go-live | architects and security | you can say why each change is needed |

`.github/workflows/` holds the CI of the stages: `ci.yml`, `model-promote.yml`, `gateway-teams.yml` and `app-ci.yml`.

## Cost

The GPU machines cost the most: a g6e.xlarge costs about $1.86 an hour (us-east-1, on-demand, October 2026). With the cluster, the NAT gateway, the database and the small machines, the lab costs a few dollars an hour while it runs. MLflow is the serverless SageMaker MLflow App: it has no extra charge, you pay only for its S3 bucket (checked 2026-10-28). Run `7-operate/scripts/teardown.sh` when you stop.

## The guide

The step-by-step guide is on kodelumi. It explains each stage, each decision and each command. This repository holds the code the guide builds.
