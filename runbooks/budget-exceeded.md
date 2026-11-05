# Runbook: a team's budget is used up

**Signs:** the team's app gets an error from the gateway with `"type": "budget_exceeded"` in the body. The team asks why Astra stopped working.

The status code depends on the LiteLLM version: 422 in v1.106.5, 429 in older versions. A rate limit gives 429 too. So look at the `type` field, not at the status code, to know it is the budget. The k8s-assistant app turns it into 429 for its own callers.

1. See the spend of every team: `bash scripts/spend-report.sh`
2. Find out what used the budget. In MLflow (open it with `bash scripts/mlflow-ui.sh`, then the workspace `default`, the experiment `astra-gateway` and its Traces), search the traces with `tags.team = '<name>'` and look at `response_cost` in each trace. The `user` field shows which person or job sent the requests.
3. Decide with the team:
   - **A mistake** (a loop, a test against the real gateway): the team fixes its code. The budget resets on the date in the report.
   - **Real need**: raise `budget_usd` for the team in `gateway/teams.yaml` and run `python gateway/sync_teams.py --gateway http://localhost:4000` with the gateway port-forwarded. The team's manager approves the change first, because the money comes from their budget.
4. Do not give the team another team's key. Spend must stay with the team that caused it.

**Why budgets:** the GPUs cost the same every hour. A budget stops one team from using the capacity that the other teams pay for.
