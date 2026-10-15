#!/usr/bin/env bash
# Prints what each team spent this budget period at the internal price, against its budget.
# Needs the gateway port-forward:  kubectl -n gateway port-forward svc/litellm 4000:4000
# Run from the project's main folder:  bash scripts/spend-report.sh
set -euo pipefail

PY=python3; python3 -c "" 2>/dev/null || PY=python
MASTER=$(kubectl -n gateway get secret litellm-env -o jsonpath='{.data.LITELLM_MASTER_KEY}' | base64 -d)

curl -sf http://localhost:4000/team/list -H "Authorization: Bearer $MASTER" | $PY -c "
import json, sys
teams = json.load(sys.stdin)
teams.sort(key=lambda t: t['spend'], reverse=True)   # biggest spender first
print(f\"{'team':<20}{'spent':>12}{'budget':>10}{'used':>8}  resets\")
for t in teams:
    used = 100 * t['spend'] / t['max_budget']
    print(f\"{t['team_alias']:<20}{t['spend']:>12.6f}{t['max_budget']:>10.2f}{used:>7.1f}%  {(t['budget_reset_at'] or '')[:10]}\")
"
