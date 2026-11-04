# Build contract (internal: shared names for every stage)

Every stage folder builds against these names. Do not invent new names; add them here first.

## Tool choices (decided by job-description frequency, market share and production reference designs, 2026-10-28)

Terraform · GitHub Actions · Argo CD (Helm, GitOps Bridge) · Karpenter · vLLM (own Helm chart) · S3 + Run:ai Model Streamer · MLflow registry: SageMaker AI MLflow App (serverless, S3 artifacts) · ModelScan + safetensors-only · lm-evaluation-harness (model gate) · promptfoo (app tests) · LiteLLM gateway · KEDA · kube-prometheus-stack + NVIDIA DCGM exporter · Langfuse (self-hosted) · LiteLLM guardrails: Presidio (PII) + Bedrock ApplyGuardrail · External Secrets + AWS Secrets Manager · Kyverno · GitHub Actions Runner Controller (ARC) runners inside the cluster · EKS Pod Identity.

## Repository layout

```
.github/workflows/      ci.yml, model-promote.yml, gateway-teams.yml, app-ci.yml, arc-smoke.yml
1-foundations/          Terraform: bootstrap/ (state bucket) and terraform/ (VPC, EKS, Karpenter, IAM, S3, RDS, Secrets Manager, ACM, Bedrock guardrail, SageMaker MLflow App, Argo CD + GitOps Bridge)
2-platform/             Argo CD ApplicationSets for the add-ons, Karpenter NodePools, Kyverno policies, ARC, db-init
3-model-pipeline/       models/<model>.yaml spec, scripts/ (download, scan, upload, register, gate, promote), k8s/eval-job.yaml
4-serving/              charts/vllm/ (own chart), values/qwen3.8-27b.yaml (the version that serves), argocd/serving.yaml
5-gateway/              litellm/ values + config, langfuse/ values, presidio/, teams/teams.yaml, scripts/sync_teams.py, argocd/gateway.yaml
6-app/k8s-assistant/    app code, Dockerfile, promptfoo tests, deploy/ (Kubernetes manifests), argocd/k8s-assistant.yaml
7-operate/              scripts/ (spend-report, canary, teardown) and runbooks/
8-production/           README only: what a company changes before go-live
```

## AWS (all created by `1-foundations/terraform`)

- Region `us-east-1` (variable `region`). Name prefix `astra` (variable `name`). Cluster name: `astra`.
- Domain: variable `domain` (a public Route 53 hosted zone). Host names: `astra.<domain>` (gateway), `argocd.<domain>`, `grafana.<domain>`, `langfuse.<domain>`. One ACM certificate with these four names as SANs, validated by DNS in the zone.
- One internal ALB shared by all Ingresses: IngressClass `alb`, group name `astra-internal`, scheme `internal`.
- S3 buckets (versioned, encrypted, block public): `astra-models-<account>` (model weights, prefix `<model>/<revision>/`), `astra-mlflow-<account>` (artifact store of the MLflow App, and the eval results under `eval/`), `astra-langfuse-<account>` (Langfuse events/media).
- RDS PostgreSQL (one instance, private): database `litellm` with its own user. Created by Terraform (the `postgresql` database created by a Kubernetes Job `db-init` in 2-platform, reading the master secret).
- MLflow: SageMaker AI MLflow App `astra` (serverless; AWS keeps the metadata), artifact store `s3://astra-mlflow-<account>/`, service role `astra-mlflow-app` (S3 on that bucket only), automatic SageMaker Model Registry copy off. The app ARN is the tracking URI (with the `sagemaker-mlflow` plugin, SigV4 with the caller's AWS credentials); Terraform output and cluster-secret annotation `mlflow_tracking_arn`. Clients need `sagemaker:CallMlflowAppApi` on the app ARN, plus `sagemaker:ListMlflowApps` to find it by name.
- Secrets Manager names: `astra/rds/master`, `astra/rds/litellm` (JSON: host, port, dbname, username, password), `astra/litellm/master-key`, `astra/litellm/salt-key`, `astra/vllm/api-key`, `astra/langfuse/init` (JSON with the Langfuse keys and passwords), `astra/hf-token` (value set by the student), `astra/arc/github-app` (JSON: github_app_id, github_app_installation_id, github_app_private_key — set by the student), `astra/teams/<team>` (written by the teams workflow; JSON: `api_key`, `team_id`, `key_alias`).
- Bedrock guardrail `astra-guardrail` (PII anonymize + denied topics minimal), id exported.

## Kubernetes namespaces and service accounts with EKS Pod Identity

| Namespace | Service account | AWS access |
|---|---|---|
| kube-system | `karpenter` | Karpenter controller (from the terraform-aws-modules/eks karpenter submodule). Terraform installs the controller (Helm); 2-platform only adds NodePools |
| kube-system | `aws-load-balancer-controller` | LB controller policy |
| external-dns | `external-dns` | Route 53 change on the one zone |
| external-secrets | `external-secrets` | Secrets Manager read `astra/*`, write `astra/teams/*` is NOT here |
| arc-runners | `arc-runner` | S3 read/write models bucket, S3 read `astra-mlflow-<account>/eval/*` (gate job), Secrets Manager read `astra/hf-token`, create/write/read `astra/teams/*`, read `astra/litellm/master-key`, read `astra/arc/github-app` (promote pull request token), `sagemaker:CallMlflowAppApi` on the MLflow App, `sagemaker:ListMlflowApps` |
| model-pipeline | `model-eval` | S3 read models bucket, write mlflow bucket (no MLflow API: the eval Job only writes `results.json`) |
| serving | `vllm` | S3 read models bucket |
| gateway | `litellm` | `bedrock:ApplyGuardrail` on the guardrail; `bedrock:InvokeModel` for an optional fallback model |
| langfuse | `langfuse` | S3 read/write langfuse bucket |

## GitOps Bridge (Terraform → Argo CD)

Terraform installs Argo CD (Helm) and creates the in-cluster cluster Secret with labels `enable_<addon>: "true"` and these annotations, read by ApplicationSets with a cluster generator (`{{metadata.annotations.<key>}}`):

`aws_region`, `aws_account_id`, `aws_cluster_name`, `aws_vpc_id`, `domain`, `acm_certificate_arn`, `models_bucket`, `mlflow_bucket`, `mlflow_tracking_arn`, `langfuse_bucket`, `rds_host`, `bedrock_guardrail_id`, `bedrock_guardrail_version`, `karpenter_node_role`, `karpenter_queue`, `repo_url`, `repo_revision`.

Terraform also creates one root Application `platform` → path `2-platform/addons` (ApplicationSets). Stages 4, 5 and 6 are added later by the student with `kubectl apply -f <stage>/argocd/<app>.yaml` (in a company: a pull request to the GitOps repo). Every stage file (`2-platform/addons/*.yaml`, `4-serving/argocd/serving.yaml`, `5-gateway/argocd/*.yaml`, `6-app/k8s-assistant/argocd/k8s-assistant.yaml`) is an ApplicationSet with the cluster generator, not an Application.

## Model contract

- Spec file `3-model-pipeline/models/qwen3.8-27b.yaml`: `name: qwen3.8-27b`, `hf_repo: Qwen/Qwen3.8-27B-FP8`, `revision: 017b9c7af6b5689d5dd426a76e0bc077eb5ca20a`, `license`, `allow_patterns`, eval tasks and thresholds.
- Weights land in `s3://astra-models-<account>/qwen3.8-27b/<revision>/`.
- MLflow registered model name: `qwen3.8-27b`. Each version: source = that S3 URI, tags `hf_repo`, `revision`, `scan=passed`, `eval_<task>`. Aliases: `candidate` (after gate passes), `champion` (after human approval, rollout `direct`; or after `canary.sh promote`), `approved` (after human approval, rollout `canary`).
- After approval the pipeline opens a pull request (GitHub App token, so CI runs) that sets `model.uri` and `model.revision` in `4-serving/values/qwen3.8-27b.yaml` (rollout `direct`) or `4-serving/values/qwen3.8-27b-canary.yaml` (rollout `canary`). Merging it is the deployment.
- vLLM served model name: `astra`. Service `vllm.serving.svc:8000`. vLLM API key from `astra/vllm/api-key`.
- Gateway: `https://astra.<domain>/v1`, model name `astra`. LiteLLM master key from `astra/litellm/master-key`. The Ingress opens only `/v1` and `/health`; the admin API (teams, keys, spend) is reached by `kubectl -n gateway port-forward svc/litellm 4000:4000`, or from the ARC runner at `http://litellm.gateway.svc:4000`.

## Versions

Pin every chart, image and provider to the latest stable release on the day of writing, checked online (GitHub releases, Artifact Hub, PyPI). Write the date checked in a comment next to the pin. Images by tag (digest pinning is a production note in 8-production).

## Proven settings from the first build (reuse)

vLLM `v0.31.0` worked with: `--max-model-len 32768 --gpu-memory-utilization 0.92 --max-num-seqs 128 --language-model-only --reasoning-parser qwen3 --enable-auto-tool-choice --tool-call-parser qwen3_coder --default-chat-template-kwargs '{"enable_thinking": false}'`, `enableServiceLinks: false` (VLLM_PORT clash), `/dev/shm` emptyDir, startup probe up to 20 min, GPU g6e.xlarge/2xlarge/4xlarge allowed (capacity runs out in us-east-1), requests cpu 3 / memory 24Gi, limit memory 28Gi.

## Added after stage 1 was built

- The 12 add-on labels on the cluster secret `in-cluster` (value `"true"`, from the Terraform variable `addons`): `enable_aws_load_balancer_controller`, `enable_external_dns`, `enable_external_secrets`, `enable_karpenter_nodepools`, `enable_kyverno`, `enable_keda`, `enable_kube_prometheus_stack`, `enable_dcgm_exporter`, `enable_arc`, `enable_db_init`, `enable_cert_manager`, `enable_clickhouse_operator`. Also label `cluster_name` (selects `cluster-base`, which is not optional).
- State bucket `astra-tfstate-<account>`, key `1-foundations/terraform.tfstate`.
- IAM role names `astra-<service-account>`; Karpenter node role `astra-karpenter-node`; system node group label `karpenter.sh/controller=true`.
- EBS CSI driver (EKS add-on, Pod Identity on `kube-system/ebs-csi-controller-sa`) for Prometheus and ClickHouse volumes.
- RDS master user `postgres`. The user and database `litellm` are created by the stage 2 `db-init` Job (label `enable_db_init`).
- Langfuse uses its chart's own PostgreSQL in the lab; `astra/langfuse/init` keys (exactly what `5-gateway/langfuse/manifests/externalsecrets.yaml` reads): `salt`, `encryption_key` (64 hex), `nextauth_secret`, `public_key` (`pk-lf-…`), `secret_key` (`sk-lf-…`), `admin_email`, `admin_password`, `postgres_password`, `clickhouse_password`, `redis_password`.
- `domain` and `admin_cidrs` have no default (a wrong domain fails the zone lookup; an open CIDR would expose the Kubernetes API).

## Final names (integration pass, 2026-10-28)

Platform (2-platform):
- ClusterSecretStore `aws-secrets-manager` (every ExternalSecret uses it).
- Namespaces: `arc-systems` (ARC controller, service account `arc-controller`), `arc-runners` (runner pods), `platform-jobs` (db-init Job), `kyverno`, `keda`, `monitoring` (kube-prometheus-stack, DCGM exporter), `cert-manager`, `clickhouse-operator`, `external-secrets`, `external-dns`. `model-pipeline` and `gateway` are made by `2-platform/cluster-base` (stages 3 and 5 do not declare them; Argo CD uses `CreateNamespace=true` at most).
- Sync waves: -2 OCI Helm repos, -1 cluster-base, 0 External Secrets + Karpenter NodePools, 1 ClusterSecretStore + LB controller, 2 ExternalDNS, Kyverno, KEDA, monitoring-config, cert-manager, 3 Kyverno policies, kube-prometheus-stack, ClickHouse operator, 4 db-init, DCGM exporter, 5 ARC controller, 6 ARC runner set.
- StorageClass `gp3` (default, from cluster-base). The ARC runner work dir `/home/runner/_work` is a 100Gi gp3 generic ephemeral volume per runner pod.
- GPU NodePool `gpu`: limit `nvidia.com/gpu: 4` (2 serving replicas + 1 surge in a rolling update + 1 canary or eval Job). KEDA `maxReplicas: 3`. NodePool `general` for everything else.
- Kubernetes Secrets: `arc-github-app` (namespace `arc-runners`, from `astra/arc/github-app`), `grafana-admin` (namespace `monitoring`, random password made by an ESO generator), `vllm-api-key` (namespace `serving`, from `astra/vllm/api-key`).
- Prometheus: `http://kube-prometheus-stack-prometheus.monitoring.svc:9090`.
- MLflow: no in-cluster server. `3-model-pipeline/scripts/spec.py` (`use_mlflow()`) sets `MLFLOW_TRACKING_URI` to the ARN of the MLflow App named `astra` (found with `ListMlflowApps`), unless `MLFLOW_TRACKING_URI` is already set. `model-promote.yml` and `7-operate/scripts/canary.sh` use it; no GitHub variable is needed.

CI (GitHub):
- Self-hosted jobs use `runs-on: arc-runner` (the ARC runner scale set name).
- MLflow experiment name = model name (`qwen3.8-27b`); run name `<name>-<revision[:8]>`.
- GitHub environment `model-approval` (required reviewers) holds the approve job of `model-promote.yml`.
- GitHub repository variable `ASTRA_DOMAIN` (the `domain`), read by `app-ci.yml` (promptfoo against `https://astra.<domain>/v1`).
- App image `ghcr.io/kserge2001/k8s-assistant` (owner from `repo_url`); the GHCR package must be public or the deployment needs a pull secret.

Canary (7-operate/scripts/canary.sh):
- ApplicationSet and Application `serving-canary` (file `4-serving/argocd/serving-canary.yaml`), Helm release `vllm-canary` (Service `vllm-canary.serving.svc:8000`), values `4-serving/values/qwen3.8-27b-canary.yaml`, LiteLLM `model_info.id` `astra-canary` (weight 10, main 90). The main release keeps `maxReplicas: 3` while a canary runs (3 + 1 = the GPU limit).

Placeholders left on purpose:
- `__ACCOUNT_ID__` in `4-serving/values/qwen3.8-27b.yaml` `model.uri`, until the first promote pull request.
