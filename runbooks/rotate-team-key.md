# Runbook: rotate a team key

**When:** a key leaked (in a log, a chat, a Git commit), a person left the team, or on the regular schedule.

`gateway/sync_teams.py` owns the keys. Each team has one key with the alias `<team>-key`, saved in `astra/teams/<team>` in Secrets Manager. Apps read it from there with an ExternalSecret, so a rotation needs no change in the app's code.

The script makes a new key only when the saved key no longer works. So you rotate by deleting the old key first.

1. Delete the old key at the gateway. The admin API is not on the Ingress, so use a port-forward:
   ```bash
   kubectl -n gateway port-forward svc/litellm 4000:4000 &
   MASTER=$(kubectl -n gateway get secret litellm-env -o jsonpath='{.data.LITELLM_MASTER_KEY}' | base64 -d)
   curl -sf localhost:4000/key/delete -H "Authorization: Bearer $MASTER" \
     -H 'Content-Type: application/json' -d '{"key_aliases": ["<team>-key"]}'
   ```
   From now on the team's app gets HTTP 401 until step 3 is done. Pick a quiet time, unless the key leaked.
2. Run `python gateway/sync_teams.py --gateway http://localhost:4000` (the port-forward from step 1 is still open). It sees the dead key, makes a new one and saves it in `astra/teams/<team>`.
3. Make the app pick it up now, not at the next refresh. Environment variables are read only when a pod starts, so restart it:
   ```bash
   kubectl -n <app namespace> annotate externalsecret <name> force-sync=$(date +%s) --overwrite
   kubectl -n <app namespace> rollout restart deployment <app>
   ```
   For `k8s-assistant`: namespace `k8s-assistant`, ExternalSecret `k8s-assistant-gateway-key`, deployment `k8s-assistant`.
4. Check that the app works (for `k8s-assistant`: the check in its README).
5. If the key leaked: look in MLflow (experiment `astra-gateway`) for traces with the tag `team:<name>` from before step 1 that you cannot explain.

**Why delete first:** a leaked key must stop working at once. A short outage for one team is better than a stranger using its budget.
