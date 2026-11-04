"""Step 4: record the model version in the MLflow registry.

The version points at the S3 folder; MLflow keeps the record, not a copy of the weights.
Run it again for the same revision and it reuses the version it made before.
"""

import argparse

import mlflow
from mlflow import MlflowClient

import spec as specs


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--spec", required=True)
    args = ap.parse_args()

    s = specs.load(args.spec)
    name, rev, source = s["name"], s["revision"], specs.model_uri(s)
    tags = {"hf_repo": s["hf_repo"], "revision": rev, "scan": "passed"}
    specs.use_mlflow()
    client = MlflowClient()   # server from MLFLOW_TRACKING_URI, set by use_mlflow()

    if not client.search_registered_models(filter_string=f"name = '{name}'"):
        client.create_registered_model(name)

    found = client.search_model_versions(f"name = '{name}' and tags.revision = '{rev}'")
    if found:
        mv = found[0]
        print(f"version {mv.version} already exists for revision {rev}")
    else:
        mlflow.set_experiment(name)
        with mlflow.start_run(run_name=f"{name}-{rev[:8]}") as run:
            mlflow.log_params({
                "hf_repo": s["hf_repo"],
                "revision": rev,
                "license": s["license"],
                "source": source,
                "eval_limit": s["eval"]["limit"],
                "eval_num_fewshot": s["eval"]["num_fewshot"],
            })
            mlflow.set_tags(tags)
        mv = client.create_model_version(name=name, source=source, run_id=run.info.run_id, tags=tags)
        print(f"registered {name} version {mv.version} -> {source}")

    specs.write_outputs({"version": mv.version, "run_id": mv.run_id})


if __name__ == "__main__":
    main()
