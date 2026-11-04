#!/usr/bin/env bash
# Sends test requests through the gateway and counts which backend answered each one.
# Use it during a canary: with weight 10, about 10% should come from the canary.
# It also gives Grafana and MLflow traffic to compare the two releases.
#
#   bash scripts/load.sh [requests] [team]      defaults: 100 requests, team platform-loadtest
#
# The team key comes from Secrets Manager (astra/teams/<team>), so the requests count against that
# team's budget, as real traffic would. Needs kubectl access, your AWS login, curl and python3.
set -euo pipefail

N=${1:-100}
TEAM=${2:-platform-loadtest}
PORT=${PORT:-4000}
REGION=${AWS_REGION:-us-east-1}
PY=python3; python3 -c "" >/dev/null 2>&1 || PY=python   # on Windows, "python3" can be a Microsoft Store stub that does not run

KEY=$(aws secretsmanager get-secret-value --region "$REGION" --secret-id "astra/teams/$TEAM" \
        --query SecretString --output text | $PY -c 'import json,sys; print(json.load(sys.stdin)["api_key"])')

kubectl -n gateway port-forward svc/litellm "$PORT:4000" >/dev/null &
PF=$!
for _ in $(seq 30); do   # up to 30 s for the port-forward to open
  curl -s -o /dev/null "http://localhost:$PORT/health/liveliness" && break
  sleep 1
done

# A few different questions, so the answers are worth comparing in MLflow.
QUESTIONS=(
  "In one sentence: what does a Kubernetes readiness probe do?"
  "List three reasons a pod can stay in Pending."
  "What is the difference between a Deployment and a StatefulSet? Two sentences."
  "Write a one-line bash command that counts the lines of every .log file in a folder."
  "Explain what an HTTP 429 status code means, in plain words."
)

HEADERS=$(mktemp)
trap 'kill $PF 2>/dev/null; rm -f "$HEADERS"' EXIT
main=0; canary=0; other=0; errors=0
for i in $(seq 1 "$N"); do
  q=${QUESTIONS[$(( (i - 1) % ${#QUESTIONS[@]} ))]}
  body=$($PY -c 'import json,sys; print(json.dumps({"model": "astra", "max_tokens": 120, "user": "load-test",
    "messages": [{"role": "user", "content": sys.argv[1]}]}))' "$q")
  # 000 means no answer at all (the port-forward dropped, or the 120 s limit passed).
  code=$(curl -s --max-time 120 -o /dev/null -D "$HEADERS" -w '%{http_code}' "http://localhost:$PORT/v1/chat/completions" \
           -H "Authorization: Bearer $KEY" -H 'Content-Type: application/json' -d "$body") || code=000
  if [ "$code" != 200 ]; then
    errors=$((errors + 1)); echo "request $i: HTTP $code"; continue
  fi
  # LiteLLM names the backend it used in this response header.
  base=$(tr -d '\r' < "$HEADERS" | awk -F': ' 'tolower($1)=="x-litellm-model-api-base" {print $2}')
  case "$base" in
    *vllm-canary*) canary=$((canary + 1)) ;;
    *vllm.serving*) main=$((main + 1)) ;;
    *) other=$((other + 1)) ;;   # the header was missing
  esac
done

echo
echo "requests: $N   errors: $errors"
printf '%-7s %5d  (%d%%)\n' main "$main" $((100 * main / N))
printf '%-7s %5d  (%d%%)\n' canary "$canary" $((100 * canary / N))
[ "$other" = 0 ] || printf '%-7s %5d  (no x-litellm-model-api-base header)\n' unknown "$other"
exit 0
