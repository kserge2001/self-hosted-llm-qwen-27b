# Stage 8: what a company changes before go-live

The lab takes shortcuts, so it is cheap and quick to build. A company changes these before real users depend on Astra. Each line says what changes and why.

| Lab | Production | Why |
|---|---|---|
| `kubectl port-forward` and SSM to reach internal services | VPN or zero-trust access (for example AWS Verified Access) with company sign-in | every person is checked and logged, and no laptop needs cluster credentials |
| Argo CD installed by Terraform with Helm | managed Argo CD (EKS Capabilities) | AWS runs, upgrades and secures Argo CD, so the platform team does not |
| Prometheus and Grafana in the cluster | Amazon Managed Service for Prometheus and Amazon Managed Grafana | metrics survive the cluster, and nobody has to size or back up Prometheus |
| images pinned by tag, pulled from public registries | images pinned by digest, pulled from a private ECR mirror (pull-through cache) | a tag can be moved to other code; a digest cannot, and a public registry outage cannot stop a deploy |
| model files scanned by ModelScan in the pipeline | also a model registry proxy with scanning: JFrog Artifactory or Hugging Face's built-in scans | one approved place for all models, with the scan result kept with the file |
| on-demand GPUs, taken when free | reserved GPU capacity: On-Demand Capacity Reservations for g6e (EC2 Capacity Blocks do not list g6e; checked 2026-10-28, the AWS page lists only P and Trn types) | us-east-1 runs out of L40S GPUs, and a model server that cannot start means no Astra |
| one RDS instance in one zone | RDS Multi-AZ | the gateway keeps its keys and budgets when one zone fails |
| MLflow as the SageMaker MLflow App (managed by AWS) | keep it. Self-host MLflow on Kubernetes only for data residency rules, an air-gapped network, or when a platform team owns and runs it | a managed registry has no server, database or upgrade to look after |
| Langfuse with ClickHouse in the cluster | Langfuse on a managed ClickHouse (ClickHouse Cloud) | trace data grows fast and needs backups and scaling the cluster should not carry |
| model files checked by hash only | models signed with OpenSSF Model Signing, signature checked before serving | proves who built the model files and that nobody changed them on the way |
