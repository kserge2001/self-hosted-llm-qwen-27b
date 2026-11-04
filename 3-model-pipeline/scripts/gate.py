"""Step 6: compare the lm-eval scores with the spec thresholds.

Pass: the version gets the alias `candidate`. Fail: the workflow stops here.
"""

import argparse
import json
import sys
from urllib.parse import urlparse

import boto3
from mlflow import MlflowClient

import spec as specs


def read_results(uri):
    if uri.startswith("s3://"):
        u = urlparse(uri)
        body = boto3.client("s3").get_object(Bucket=u.netloc, Key=u.path.lstrip("/"))["Body"]
        return json.load(body)
    with open(uri, encoding="utf-8") as f:
        return json.load(f)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--spec", required=True)
    ap.add_argument("--version", required=True, help="MLflow model version from register.py")
    ap.add_argument("--results", help="results.json, s3:// or local (default: the contract location)")
    args = ap.parse_args()

    s = specs.load(args.spec)
    results = read_results(args.results or specs.results_uri(s))["results"]
    specs.use_mlflow()
    client = MlflowClient()
    mv = client.get_model_version(s["name"], args.version)

    passed = True
    for task in s["eval"]["tasks"]:
        score = results[task["name"]][task["metric"]]
        ok = score >= task["min"]
        passed = passed and ok
        key = f"eval_{task['name']}"
        client.log_metric(mv.run_id, key, score)
        client.set_model_version_tag(s["name"], mv.version, key, f"{score:.4f}")
        print(f"{task['name']}: {score:.4f} (min {task['min']}) {'PASS' if ok else 'FAIL'}")

    if not passed:
        sys.exit("gate failed: this version is not promoted")
    client.set_registered_model_alias(s["name"], "candidate", mv.version)
    print(f"{s['name']} version {mv.version} is now 'candidate'")


if __name__ == "__main__":
    main()
