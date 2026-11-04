"""Shared helpers: read the model spec and build the contract names from it.

Run as a script to hand the names to later GitHub Actions steps:
    python spec.py ../models/qwen3.8-27b.yaml
"""

import os
import sys

import boto3
import yaml

# MLflow is the SageMaker MLflow App made by 1-foundations/terraform (mlflow.tf). Its name is fixed;
# its ARN (the tracking URI) is not, so use_mlflow() looks it up.
MLFLOW_APP_NAME = "astra"

# Weight formats that can run code when loaded (pickle and friends). Only safetensors is allowed.
UNSAFE_WEIGHT_SUFFIXES = (
    ".bin", ".pt", ".pth", ".ckpt", ".pkl", ".pickle",
    ".h5", ".keras", ".pb", ".msgpack", ".npy", ".npz", ".gguf", ".onnx",
)


def load(path):
    with open(path, encoding="utf-8") as f:
        spec = yaml.safe_load(f)
    for key in ("name", "hf_repo", "revision", "license", "allow_patterns", "eval"):
        if key not in spec:
            sys.exit(f"{path}: missing key '{key}'")
    # A branch name like "main" can move; only a full commit hash is a real pin.
    if len(str(spec["revision"])) != 40:
        sys.exit(f"{path}: revision must be a full 40-character commit hash")
    return spec


def account_id():
    return boto3.client("sts").get_caller_identity()["Account"]


def mlflow_tracking_uri():
    """The MLflow App ARN. MLFLOW_TRACKING_URI wins if set (terraform output mlflow_tracking_arn)."""
    if os.environ.get("MLFLOW_TRACKING_URI"):
        return os.environ["MLFLOW_TRACKING_URI"]
    # boto3 reads AWS_DEFAULT_REGION but not AWS_REGION (the workflow sets AWS_REGION).
    sm = boto3.client("sagemaker", region_name=os.environ.get("AWS_REGION") or os.environ.get("AWS_DEFAULT_REGION"))
    kwargs = {}
    while True:
        page = sm.list_mlflow_apps(**kwargs)
        for app in page["Summaries"]:
            if app["Name"] == MLFLOW_APP_NAME and app["Status"] not in ("Deleting", "Deleted"):
                return app["Arn"]
        if not page.get("NextToken"):
            break
        kwargs["NextToken"] = page["NextToken"]
    # Stop here: without a tracking URI, MLflow would quietly write to a local ./mlruns folder.
    sys.exit(f"no SageMaker MLflow App named '{MLFLOW_APP_NAME}' in this account and region")


def use_mlflow():
    """Point the MLflow client at the App. The sagemaker-mlflow plugin sees the ARN and signs each
    call with the caller's AWS credentials (Pod Identity on the runner, your login on a laptop)."""
    os.environ["MLFLOW_TRACKING_URI"] = mlflow_tracking_uri()


def models_bucket():
    return os.environ.get("MODELS_BUCKET") or f"astra-models-{account_id()}"


def mlflow_bucket():
    return os.environ.get("MLFLOW_BUCKET") or f"astra-mlflow-{account_id()}"


def model_prefix(spec):
    return f"{spec['name']}/{spec['revision']}/"


def model_uri(spec):
    return f"s3://{models_bucket()}/{model_prefix(spec)}"


def results_uri(spec):
    return f"s3://{mlflow_bucket()}/eval/{spec['name']}/{spec['revision']}/results.json"


def write_outputs(values):
    """Hand values to later workflow steps (GITHUB_OUTPUT), or just print them when run by hand."""
    lines = "".join(f"{k}={v}\n" for k, v in values.items())
    out = os.environ.get("GITHUB_OUTPUT")
    if out:
        with open(out, "a", encoding="utf-8") as f:
            f.write(lines)
    print(lines, end="")


if __name__ == "__main__":
    s = load(sys.argv[1])
    write_outputs({
        "name": s["name"],
        "revision": s["revision"],
        "model_uri": model_uri(s),
        "results_uri": results_uri(s),
        "mlflow_bucket": mlflow_bucket(),
        "eval_tasks": ",".join(t["name"] for t in s["eval"]["tasks"]),
        "eval_limit": s["eval"]["limit"],
        "eval_num_fewshot": s["eval"]["num_fewshot"],
    })
