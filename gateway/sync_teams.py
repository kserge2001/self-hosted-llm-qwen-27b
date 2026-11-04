#!/usr/bin/env python3
"""Make LiteLLM match gateway/teams.yaml.

For each team: create it or update its budget and limits, then make sure it has one working key.
A new key is saved in AWS Secrets Manager as astra/teams/<team>. Keys are never printed.
Safe to run again and again: a team that already matches, with a working key, is left as it is.

Run it from your laptop after every change to teams.yaml, with the gateway port-forwarded:
    kubectl -n gateway port-forward svc/litellm 4000:4000
    python gateway/sync_teams.py --gateway http://localhost:4000 [--dry-run]
Needs your AWS login: it reads astra/litellm/master-key and reads/writes astra/teams/*.
"""
import argparse
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

import boto3
import yaml

MODELS = ["astra"]              # the only model name teams may call
BUDGET_DURATION = "30d"         # budgets reset every 30 days
MASTER_KEY_SECRET = "astra/litellm/master-key"
TEAM_SECRET_PREFIX = "astra/teams/"


class Gateway:
    """Small client for the LiteLLM admin API."""

    def __init__(self, base_url, master_key):
        self.base_url = base_url.rstrip("/")
        self.master_key = master_key

    def call(self, method, path, body=None, query=None):
        url = self.base_url + path
        if query:
            url += "?" + urllib.parse.urlencode(query)
        data = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(url, data=data, method=method)
        req.add_header("Authorization", "Bearer " + self.master_key)
        req.add_header("Content-Type", "application/json")
        try:
            with urllib.request.urlopen(req, timeout=60) as resp:
                return resp.status, json.loads(resp.read() or b"{}")
        except urllib.error.HTTPError as err:
            # Show the status and path only: an error body can echo a key back.
            return err.code, None


def load_teams(path):
    with open(path, encoding="utf-8") as f:
        teams = yaml.safe_load(f)["teams"]
    names = [t["name"] for t in teams]
    if len(names) != len(set(names)):
        sys.exit("teams.yaml: a team name appears twice")
    return teams


def team_body(team):
    return {
        "team_alias": team["name"],
        "models": MODELS,
        "max_budget": float(team["budget_usd"]),
        "budget_duration": BUDGET_DURATION,
        "rpm_limit": int(team["rpm"]),
        "tpm_limit": int(team["tpm"]),
        # LiteLLM adds a team's metadata tags to every request of that team, so each MLflow trace
        # carries the tag team:<name>. That is how you find one team's traces in MLflow.
        "metadata": {"tags": [f"team:{team['name']}"]},
    }


def existing_teams(gw):
    status, data = gw.call("GET", "/team/list")
    if status != 200:
        sys.exit(f"GET /team/list failed with HTTP {status}")
    teams = data if isinstance(data, list) else data.get("teams", [])
    return {t["team_alias"]: t for t in teams if t.get("team_alias")}


def needs_update(current, wanted):
    for k, v in wanted.items():
        if k == "team_alias":
            continue
        if k == "metadata":  # LiteLLM keeps more keys in metadata; compare only the tags we set
            if (current.get("metadata") or {}).get("tags") != v["tags"]:
                return True
        elif current.get(k) != v:
            return True
    return False


def read_team_key(sm, team_name):
    """The key saved for this team, or None."""
    try:
        value = sm.get_secret_value(SecretId=TEAM_SECRET_PREFIX + team_name)["SecretString"]
        return json.loads(value).get("api_key")
    except sm.exceptions.ResourceNotFoundException:
        return None


def save_team_key(sm, team_name, team_id, key_alias, key):
    name = TEAM_SECRET_PREFIX + team_name
    value = json.dumps({"api_key": key, "team_id": team_id, "key_alias": key_alias})
    try:
        sm.put_secret_value(SecretId=name, SecretString=value)
    except sm.exceptions.ResourceNotFoundException:
        sm.create_secret(Name=name, SecretString=value,
                         Description=f"LiteLLM key for team {team_name} (written by sync_teams.py)")


def key_works(gw, key, team_id):
    status, data = gw.call("GET", "/key/info", query={"key": key})
    return status == 200 and (data or {}).get("info", {}).get("team_id") == team_id


def ensure_key(gw, sm, team_name, team_id, dry_run):
    key_alias = f"{team_name}-key"
    saved = read_team_key(sm, team_name)
    if saved and key_works(gw, saved, team_id):
        print(f"  key: ok ({key_alias})")
        return
    if dry_run:
        print(f"  key: would create {key_alias} and save it in {TEAM_SECRET_PREFIX}{team_name}")
        return
    # The saved key is missing or no longer valid: replace any old key with this alias.
    gw.call("POST", "/key/delete", {"key_aliases": [key_alias]})
    status, data = gw.call("POST", "/key/generate",
                           {"team_id": team_id, "key_alias": key_alias, "models": MODELS})
    if status != 200 or not data or "key" not in data:
        sys.exit(f"POST /key/generate for {team_name} failed with HTTP {status}")
    save_team_key(sm, team_name, team_id, key_alias, data["key"])
    print(f"  key: created {key_alias}, saved in {TEAM_SECRET_PREFIX}{team_name}")


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--teams", default=os.path.join(here, "teams.yaml"))
    parser.add_argument("--gateway", default=os.environ.get("LITELLM_URL", "http://litellm.gateway.svc:4000"))
    parser.add_argument("--region", default=os.environ.get("AWS_REGION", "us-east-1"))
    parser.add_argument("--dry-run", action="store_true", help="show what would change, change nothing")
    args = parser.parse_args()

    sm = boto3.client("secretsmanager", region_name=args.region)
    master_key = sm.get_secret_value(SecretId=MASTER_KEY_SECRET)["SecretString"]
    gw = Gateway(args.gateway, master_key)

    current = existing_teams(gw)
    for team in load_teams(args.teams):
        name, wanted = team["name"], team_body(team)
        print(f"team {name}:")
        if name not in current:
            if args.dry_run:
                print("  would create")
                print(f"  key: would create {name}-key")
                continue
            status, data = gw.call("POST", "/team/new", wanted)
            if status != 200:
                sys.exit(f"POST /team/new for {name} failed with HTTP {status}")
            team_id = data["team_id"]
            print("  created")
        else:
            team_id = current[name]["team_id"]
            if needs_update(current[name], wanted):
                if args.dry_run:
                    print("  would update budget/limits")
                else:
                    status, _ = gw.call("POST", "/team/update", {"team_id": team_id, **wanted})
                    if status != 200:
                        sys.exit(f"POST /team/update for {name} failed with HTTP {status}")
                    print("  updated budget/limits")
            else:
                print("  up to date")
        ensure_key(gw, sm, name, team_id, args.dry_run)

    unknown = sorted(set(current) - {t["name"] for t in load_teams(args.teams)})
    if unknown:
        print("In LiteLLM but not in teams.yaml (left as they are): " + ", ".join(unknown))


if __name__ == "__main__":
    main()
