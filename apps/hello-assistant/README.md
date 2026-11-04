# hello-assistant: the smallest app that uses Astra

A chat program for your laptop. It calls the model through the gateway with the OpenAI SDK:
a base URL, the team API key of `hello-assistant`, and the model name `astra`. Each answer streams in
as the model writes it. Each request counts against the team's budget and shows as a trace in MLflow.

## Run it

Needs: the gateway running (`07-gateway`), and the team `hello-assistant` synced (it is in
`gateway/teams.yaml`; run `gateway/sync_teams.py` once). Run from the repository's main folder.

```bash
# 1. In a second terminal, keep a port-forward to the gateway open:
kubectl -n gateway port-forward svc/litellm 4000:4000

# 2. The team key from Secrets Manager, and the gateway address:
export OPENAI_API_KEY=$(aws secretsmanager get-secret-value --secret-id astra/teams/hello-assistant \
  --query SecretString --output text | jq -r .api_key)
export OPENAI_BASE_URL=http://localhost:4000/v1

# 3. Install the OpenAI SDK and chat:
python3 -m venv .venv-hello && . .venv-hello/bin/activate
pip install -r apps/hello-assistant/requirements.txt
python apps/hello-assistant/assistant.py "In two sentences: what is a GPU node?"
python apps/hello-assistant/assistant.py          # a chat; an empty line ends it
```

On Windows PowerShell the venv is activated with `.venv-hello\Scripts\Activate.ps1`.
