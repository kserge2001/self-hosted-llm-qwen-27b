"""Step 3: copy the scanned files to s3://astra-models-<account>/<name>/<revision>/.

SHA256SUMS is written last. Its presence means the upload is complete,
and it lets anyone check later that the weights in S3 are the weights we scanned.
"""

import argparse
import hashlib
import pathlib
import sys

import boto3
from boto3.s3.transfer import TransferConfig

import spec as specs

CONFIG = TransferConfig(multipart_chunksize=64 * 1024 * 1024, max_concurrency=16)


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(8 * 1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--spec", required=True)
    ap.add_argument("--dir", help="folder written by download.py")
    ap.add_argument("--report", help="modelscan report to keep next to the weights")
    ap.add_argument("--check", action="store_true", help="only check: exit 0 if this revision is complete in S3")
    args = ap.parse_args()

    s = specs.load(args.spec)
    bucket, prefix = specs.models_bucket(), specs.model_prefix(s)
    s3 = boto3.client("s3")

    # SHA256SUMS is written last, so if it is there, this revision is already complete in S3.
    complete = bool(s3.list_objects_v2(Bucket=bucket, Prefix=prefix + "SHA256SUMS").get("KeyCount"))
    if args.check:
        print(f"already complete: s3://{bucket}/{prefix}" if complete else f"not in S3 yet: s3://{bucket}/{prefix}")
        sys.exit(0 if complete else 1)
    if complete:
        print(f"already complete: s3://{bucket}/{prefix}")
        return
    if not args.dir:
        sys.exit("--dir is required")
    root = pathlib.Path(args.dir)

    sums = []
    for p in sorted(root.rglob("*")):
        if not p.is_file() or ".cache" in p.parts:   # .cache is Hugging Face bookkeeping
            continue
        rel = p.relative_to(root).as_posix()
        sums.append(f"{sha256(p)}  {rel}\n")
        s3.upload_file(str(p), bucket, prefix + rel, Config=CONFIG)
        print(f"uploaded {rel}")

    # The scan report stays next to the weights: the record of what was checked. Not in SHA256SUMS.
    if args.report and pathlib.Path(args.report).is_file():
        s3.upload_file(args.report, bucket, prefix + "modelscan-report.json")
        print("uploaded modelscan-report.json")

    s3.put_object(Bucket=bucket, Key=prefix + "SHA256SUMS", Body="".join(sums).encode())
    print(f"done: s3://{bucket}/{prefix} ({len(sums)} files)")


if __name__ == "__main__":
    main()
