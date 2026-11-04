"""Step 2: scan the downloaded files. Fail on any finding or a license change."""

import argparse
import json
import pathlib
import struct
import subprocess
import sys

from huggingface_hub import HfApi

import spec as specs
from download import check_weights


def check_safetensors_headers(folder):
    """A real safetensors file starts with an 8-byte length and a JSON header.
    This catches a pickle file that was only renamed to .safetensors."""
    for p in sorted(pathlib.Path(folder).glob("*.safetensors")):
        with open(p, "rb") as f:
            (size,) = struct.unpack("<Q", f.read(8))
            if size > 100_000_000:
                sys.exit(f"{p.name}: not a safetensors file (header size {size})")
            json.loads(f.read(size))
    print("safetensors headers are valid")


def run_modelscan(folder):
    # Exit codes: 0 clean, 1 issues found, 2 scan error, 3 no file type it scans.
    # 3 is the normal result for a safetensors-only folder: nothing in it can run code.
    rc = subprocess.run(
        ["modelscan", "scan", "-p", folder, "--show-skipped",
         "-r", "json", "-o", "modelscan-report.json"],
        check=False,
    ).returncode
    if rc not in (0, 3):
        sys.exit(f"modelscan failed with exit code {rc}, see modelscan-report.json")
    print(f"modelscan passed (exit code {rc})")


def check_license(s):
    info = HfApi().model_info(s["hf_repo"], revision=s["revision"])
    found = (info.card_data or {}).get("license")
    if found != s["license"]:
        sys.exit(f"license is '{found}' on Hugging Face, spec says '{s['license']}': review it first")
    print(f"license {found} matches the spec")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--spec", required=True)
    ap.add_argument("--dir", required=True, help="folder written by download.py")
    args = ap.parse_args()

    s = specs.load(args.spec)
    check_weights(args.dir)
    check_safetensors_headers(args.dir)
    run_modelscan(args.dir)
    check_license(s)


if __name__ == "__main__":
    main()
