"""Step 1: download the pinned revision from Hugging Face into a local folder."""

import argparse
import os
import pathlib
import sys

import boto3
from huggingface_hub import snapshot_download

import spec as specs


def hf_token():
    # The token lives in Secrets Manager; the runner reads it with its Pod Identity role.
    if os.environ.get("HF_TOKEN"):
        return os.environ["HF_TOKEN"]
    secret = boto3.client("secretsmanager").get_secret_value(SecretId="astra/hf-token")
    return secret["SecretString"].strip()


def check_weights(folder):
    """Stop if any weight file is not safetensors, or if there are no weights at all."""
    files = [p for p in pathlib.Path(folder).rglob("*") if p.is_file() and ".cache" not in p.parts]
    unsafe = [p.name for p in files if p.suffix.lower() in specs.UNSAFE_WEIGHT_SUFFIXES]
    if unsafe:
        sys.exit(f"refused: non-safetensors weight files {unsafe}")
    if not any(p.suffix == ".safetensors" for p in files):
        sys.exit("refused: no .safetensors files were downloaded")
    print(f"{len(files)} files, all weights are safetensors")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--spec", required=True)
    ap.add_argument("--out", required=True, help="local folder for the model files")
    args = ap.parse_args()

    s = specs.load(args.spec)
    print(f"downloading {s['hf_repo']}@{s['revision']}")
    snapshot_download(
        repo_id=s["hf_repo"],
        revision=s["revision"],          # exact commit, never a branch
        allow_patterns=s["allow_patterns"],
        local_dir=args.out,
        token=hf_token(),
        max_workers=16,
    )
    check_weights(args.out)


if __name__ == "__main__":
    main()
