# Astra: an internal inference API on Amazon EKS (reference solution)

Astra is a company's own AI model API. Apps call it like OpenAI, with a base URL, a team key and the model name `astra`, but the model (Qwen3.8-27B) runs on the company's own GPUs in its own AWS account.

This repository is the **finished build**. The guide on kodelumi walks you through creating each of these files yourself, in a near-empty repository made from the starter. Use this one to compare, or to copy a long file the guide points to.

## Who does what

| Who | What it does here |
|---|---|
| You, with `terraform` | `terraform/bootstrap` (the state bucket), then `terraform/foundations`: VPC, EKS, Karpenter, IAM, S3, ECR, RDS, secrets, the certificate, the Bedrock guardrail, Argo CD and its one root app |
| Argo CD | applies every file under `argocd/` from your repository, and keeps the cluster equal to Git. You never run `helm install`. |
| You, with `kubectl` | start the model loader Job (`model/`), look at things, port-forward to the UIs |
| You, with scripts | `gateway/sync_teams.py` (team keys), `scripts/canary.sh`, `scripts/load.sh`, `scripts/spend-report.sh`, `scripts/teardown.sh` |
| You, with `docker` | build the app image and push it to ECR |

There is no CI in this build. Every step is a command you run, so you see each one happen. The guide explains what a company automates and how.

## Folders

| Folder | What it holds | Read by |
|---|---|---|
| `terraform/bootstrap/` | the S3 bucket for Terraform state | you (`terraform apply`) |
| `terraform/foundations/` | the AWS account side of the platform | you (`terraform apply`) |
| `argocd/addons/` | one ApplicationSet per shared tool: External Secrets, LB controller, ExternalDNS, Karpenter NodePools, Kyverno, KEDA, monitoring, cert-manager, ClickHouse operator, db-init | Argo CD |
| `argocd/apps/` | one ApplicationSet per app: `serving`, `gateway`, `langfuse`, `k8s-assistant` (and `serving-canary` during a canary) | Argo CD |
| `platform/` | small charts the add-ons use: cluster basics, NodePools, policies, dashboards, the database Job | Argo CD |
| `model/` | the model spec and the loader Job: download, scan, upload to S3 | you (`kubectl apply -k`) |
| `serving/` | our vLLM Helm chart and the values of the version that serves | Argo CD |
| `gateway/` | LiteLLM, Langfuse and Presidio settings, `teams.yaml`, `sync_teams.py` | Argo CD, and you for the teams |
| `apps/k8s-assistant/` | an app that uses Astra: code, tests, Dockerfile, Kubernetes manifests | you (docker), Argo CD (deploy) |
| `scripts/` | canary, test traffic, spend report, teardown | you |
| `runbooks/` | what to do when something goes wrong | you |

## Cost

The GPU nodes cost the most: a g6e.xlarge costs $1.861 an hour (us-east-1, on-demand, October 2026). Two of them run all the time, plus one more during a canary. With the cluster, the NAT gateway, the database and the small nodes, the build costs a few dollars an hour while it runs. Run `scripts/teardown.sh` when you stop.

GPU instances need a quota ("Running On-Demand G and VT instances") and free capacity in the region. Check both before you start.
