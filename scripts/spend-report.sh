#!/usr/bin/env bash
# Prints what each team spent this budget period at the internal price, against its budget.
# Uses the gateway admin API (/team/list) with the LiteLLM master key.
#
# The Ingress at https://astra.<domain> only opens /v1 and /health, so the admin API is not on it.
# This script opens a port-forward to the gateway Service for the time it runs.
#
# Run from anywhere with kubectl access:  bash scripts/spend-report.sh
set -euo pipefail

PORT=${PORT:-4000}
PY=python3; python3 -c "" >/dev/null 2>&1 || PY=python   # on Windows, "python3" can be a Microsoft Store stub that does not run

# The master key is in the gateway's Secret (synced from astra/litellm/master-key).
MASTER=$(kubectl -n gateway get secret litellm-env -o jsonpath='{.data.LITELLM_MASTER_KEY}' | base64 -d)

kubectl -n gateway port-forward svc/litellm "$PORT:4000" >/dev/null &
PF=$!
trap 'kill $PF 2>/dev/null' EXIT
for _ in $(seq 30); do   # up to 30 s for the port-forward to open
  curl -s -o /dev/null "http://localhost:$PORT/health/liveliness" && break
  sleep 1
done

curl -sf "http://localhost:$PORT/team/list" -H "Authorization: Bearer $MASTER" | $PY -c "
import json, sys
teams = json.load(sys.stdin)
teams.sort(key=lambda t: t.get('spend') or 0, reverse=True)   # biggest spender first
print(f\"{'team':<20}{'spent':>12}{'budget':>10}{'used':>8}  resets\")
for t in teams:
    spend, budget = t.get('spend') or 0, t.get('max_budget')
    used = f'{100 * spend / budget:7.1f}%' if budget else '       -'   # a team without a budget has no percent
    print(f\"{t.get('team_alias') or t['team_id']:<20}{spend:>12.6f}{(budget or 0):>10.2f}{used}  {(t.get('budget_reset_at') or '')[:10]}\")
"
