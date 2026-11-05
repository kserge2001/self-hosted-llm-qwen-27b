# model/: copy one model version to S3

vLLM loads the weights from S3, not from Hugging Face. This folder copies them there.

| File | What it is |
|---|---|
| `qwen3.8-27b.yaml` | the model spec: Hugging Face repo, the exact revision (a commit hash), license, file types |
| `loader/download.py` | downloads that revision, only the allowed file types, and refuses non-safetensors weights |
| `loader/scan.py` | checks the safetensors headers, runs modelscan, checks the license |
| `loader/upload.py` | uploads to `s3://astra-models-<account>/<name>/<revision>/`, `SHA256SUMS` last |
| `job.yaml` | the Kubernetes Job that runs the three scripts inside the cluster |
| `kustomization.yaml` | puts the scripts and the spec in a ConfigMap for the Job |

## Run it

Needs: the cluster. The Hugging Face token in `astra/hf-token` (`terraform output fill_hf_token`) is optional: a public model downloads without it; a gated or private model needs it.

```bash
kubectl apply -k model/
kubectl -n models logs -f job/model-loader
```

The last log line is `done: s3://astra-models-<account>/qwen3.8-27b/<revision>/ (<n> files)`.

## A new version

1. Change `revision` in `qwen3.8-27b.yaml`.
2. Run the Job again:

```bash
kubectl -n models delete job model-loader --ignore-not-found
kubectl apply -k model/
```

3. Serve it: change `model.revision` in `serving/values/` (or start a canary: `scripts/canary.sh`).

In a company, a pipeline runs these steps, plus an evaluation on a GPU and a human approval, before any version can serve. The guide explains that pipeline; this folder is its first three steps, run by hand.
