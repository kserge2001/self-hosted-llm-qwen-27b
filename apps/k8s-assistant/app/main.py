"""HTTP API: POST /ask with a question, GET /health for the kubelet probes."""

from fastapi import FastAPI, HTTPException
from openai import APIError
from pydantic import BaseModel, Field

from app import agent, kube

app = FastAPI(title="k8s-assistant")
_client = None


def get_client():
    # Created on first use, so /health and the tests work without a gateway key.
    global _client
    if _client is None:
        kube.load_kube_config()
        _client = agent.make_client()
    return _client


class Question(BaseModel):
    question: str = Field(min_length=1, max_length=2000)
    # The person who asked. Sent to the gateway as the OpenAI `user` field for per-person spend.
    user: str = Field(default="anonymous", max_length=200)


@app.get("/health")
def health() -> dict:
    # No gateway call here: a gateway outage must not make Kubernetes restart this pod.
    return {"status": "ok"}


@app.post("/ask")
def ask(q: Question) -> dict:
    try:
        return agent.ask(q.question, q.user, get_client())
    except APIError as exc:
        # Pass the gateway's status on. LiteLLM answers 429 both for a team rate limit and for a used-up
        # team budget (first build, measured), so tell them apart by the error `type`, not by the status.
        status = getattr(exc, "status_code", None) or 502
        if exc.type == "budget_exceeded":
            raise HTTPException(status_code=status, detail="team budget used up: ask the platform team") from exc
        raise HTTPException(status_code=status, detail=f"gateway error: {exc.message}") from exc
