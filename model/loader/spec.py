"""Shared helpers: read the model spec and build the S3 names from it."""

import os
import sys

import boto3
import yaml

# Weight formats that can run code when loaded (pickle and friends). Only safetensors is allowed.
UNSAFE_WEIGHT_SUFFIXES = (
    ".bin", ".pt", ".pth", ".ckpt", ".pkl", ".pickle",
    ".h5", ".keras", ".pb", ".msgpack", ".npy", ".npz", ".gguf", ".onnx",
)


def load(path):
    with open(path, encoding="utf-8") as f:
        spec = yaml.safe_load(f)
    for key in ("name", "hf_repo", "revision", "license", "allow_patterns"):
        if key not in spec:
            sys.exit(f"{path}: missing key '{key}'")
    # A branch name like "main" can move; only a full commit hash is a real pin.
    if len(str(spec["revision"])) != 40:
        sys.exit(f"{path}: revision must be a full 40-character commit hash")
    return spec


def account_id():
    return boto3.client("sts").get_caller_identity()["Account"]


def models_bucket():
    return os.environ.get("MODELS_BUCKET") or f"astra-models-{account_id()}"


def model_prefix(spec):
    return f"{spec['name']}/{spec['revision']}/"


def model_uri(spec):
    return f"s3://{models_bucket()}/{model_prefix(spec)}"
