#!/usr/bin/env bash
# Creates the teams that use Astra, each with a monthly budget and a rate limit, and one key per team.
# Needs the gateway port-forward running in another terminal:
#   kubectl -n gateway port-forward svc/litellm 4000:4000
# Run from the project's main folder:  bash scripts/create-teams.sh
set -euo pipefail

PY=python3; python3 -c "" 2>/dev/null || PY=python
GW=http://localhost:4000
MASTER=$(kubectl -n gateway get secret litellm-env -o jsonpath='{.data.LITELLM_MASTER_KEY}' | base64 -d)

field() { $PY -c "import json,sys; print(json.load(sys.stdin)['$1'])"; }

# new_team  name  budget_usd_per_30_days  requests_per_minute  tokens_per_minute
new_team() {
  curl -sf "$GW/team/new" -H "Authorization: Bearer $MASTER" -H "Content-Type: application/json" \
    -d "{\"team_alias\":\"$1\",\"models\":[\"astra\"],\"max_budget\":$2,\"budget_duration\":\"30d\",\"rpm_limit\":$3,\"tpm_limit\":$4}" \
    | field team_id
}

# new_key  team_id  key_name
new_key() {
  curl -sf "$GW/key/generate" -H "Authorization: Bearer $MASTER" -H "Content-Type: application/json" \
    -d "{\"team_id\":\"$1\",\"key_alias\":\"$2\",\"models\":[\"astra\"]}" \
    | field key
}

#                       team               budget  req/min  tokens/min
HR=$(new_team          hr-assistant        50      60       200000)
SUPPORT=$(new_team     support-bot         150     300      1000000)
LOADTEST=$(new_team    platform-loadtest   50      10000    50000000)
SANDBOX=$(new_team     intern-sandbox      0.01    5        20000)

mkdir -p build
{
  echo "HR_KEY=$(new_key "$HR" hr-assistant-app)"
  echo "SUPPORT_KEY=$(new_key "$SUPPORT" support-bot-app)"
  echo "LOADTEST_KEY=$(new_key "$LOADTEST" loadtest)"
  echo "SANDBOX_KEY=$(new_key "$SANDBOX" intern-notebook)"
} > build/keys.env

echo "Teams created. Keys saved in build/keys.env (git-ignored)."
