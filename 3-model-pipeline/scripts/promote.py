"""Step 8 (after a human approved): promote the candidate.

Two ways to roll out (the workflow input `rollout`):
- direct: alias `champion`, and the new uri and revision go into the serving values file.
  Merging the pull request is the deployment.
- canary: alias `approved` (not champion yet), and the new uri and revision go into the canary
  values file. 7-operate/scripts/canary.sh runs the canary; its `promote` sets `champion`.
  So `champion` always means "serves all traffic".
"""

import argparse
import re
import sys

from mlflow import MlflowClient

import spec as specs

ALIAS = {"direct": "champion", "canary": "approved"}

CANARY_HEADER = """\
# Canary of a model upgrade, written by the model pipeline (rollout: canary).
# A copy of the main values file with the new model.uri and model.revision.
# 7-operate/scripts/canary.sh runs it; its promote or rollback removes this file.
"""


def set_model_values(text, path, uri, revision):
    """Change model.uri and model.revision in the text, keeping the comments in the file."""
    block = re.search(r"^model:[ \t]*\n((?:[ \t]+.*\n|[ \t]*\n)*)", text, re.MULTILINE)
    if not block:
        sys.exit(f"{path}: no top-level 'model:' block")
    body = block.group(1)
    for key, value in (("uri", uri), ("revision", revision)):
        body, n = re.subn(rf"^([ \t]+{key}:[ \t]*)[^\s#]+", rf"\g<1>{value}", body, count=1, flags=re.MULTILINE)
        if n != 1:
            sys.exit(f"{path}: no model.{key} line")
    return text[: block.start(1)] + body + text[block.end(1):]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--spec", required=True)
    ap.add_argument("--version", required=True, help="the version a human approved")
    ap.add_argument("--values", help="main serving values file, e.g. 4-serving/values/qwen3.8-27b.yaml")
    ap.add_argument("--rollout", choices=sorted(ALIAS), default="direct")
    args = ap.parse_args()

    s = specs.load(args.spec)
    specs.use_mlflow()
    client = MlflowClient()
    cand = client.get_model_version_by_alias(s["name"], "candidate")
    # Promote only what was approved: the alias must still point at this run's version.
    if str(cand.version) != str(args.version):
        sys.exit(f"candidate is version {cand.version}, the approval was for {args.version}")

    alias = ALIAS[args.rollout]
    client.set_registered_model_alias(s["name"], alias, cand.version)
    uri, rev = cand.source, cand.tags["revision"]
    print(f"{s['name']} version {cand.version} is now '{alias}'\n  uri: {uri}\n  revision: {rev}")

    out = {"uri": uri, "revision": rev, "version": cand.version, "alias": alias}
    if args.values:
        with open(args.values, encoding="utf-8") as f:
            text = f.read()
        target = args.values
        if args.rollout == "canary":
            # The canary keeps every setting of the main release; only the weights change.
            # The name is the one canary.sh expects: <main values>-canary.yaml.
            target = re.sub(r"\.yaml$", "-canary.yaml", args.values)
            text = CANARY_HEADER + "\n" + re.sub(r"\A(?:#.*\n)+\n?", "", text)
        with open(target, "w", encoding="utf-8") as f:
            f.write(set_model_values(text, args.values, uri, rev))
        print(f"wrote {target}")
        out["values_file"] = target
    specs.write_outputs(out)


if __name__ == "__main__":
    main()
