"""Unit tests. No cluster and no gateway: both are replaced by small fakes."""

import json
from pathlib import Path
from types import SimpleNamespace as NS

import pytest
from fastapi.testclient import TestClient

from app import agent, kube, main


def fake_pod(name, ready=True, restarts=0, waiting=None):
    state = NS(waiting=NS(reason=waiting) if waiting else None)
    status = NS(ready=ready, restart_count=restarts, state=state)
    return NS(
        metadata=NS(name=name),
        status=NS(phase="Running", container_statuses=[status]),
        spec=NS(node_name="node-1"),
    )


class FakeCore:
    def list_namespaced_pod(self, namespace, limit):
        return NS(items=[fake_pod("web-1"), fake_pod("web-2", ready=False, restarts=7, waiting="CrashLoopBackOff")])


def test_list_pods_shows_crashloop():
    pods = kube.list_pods("shop", core=FakeCore())
    assert pods[1] == {
        "name": "web-2",
        "phase": "Running",
        "ready": "0/1",
        "restarts": 7,
        "node": "node-1",
        "waiting": ["CrashLoopBackOff"],
    }


def test_tools_json_matches_app():
    # promptfoo reads tests/tools.json; it must be the same schema the app sends.
    saved = json.loads((Path(__file__).parent / "tools.json").read_text())
    assert saved == kube.TOOLS


def test_unknown_tool_is_an_error_not_a_crash():
    assert "unknown tool" in agent.run_tool("delete_pod", "{}")


class FakeCompletions:
    """First reply asks for list_pods, second reply answers."""

    def __init__(self):
        self.calls = []

    def create(self, **kwargs):
        self.calls.append(kwargs)
        if len(self.calls) == 1:
            call = NS(id="c1", function=NS(name="list_pods", arguments='{"namespace": "shop"}'))
            msg = NS(tool_calls=[call], content=None, model_dump=lambda **_: {"role": "assistant", "tool_calls": []})
        else:
            msg = NS(tool_calls=None, content="Pod web-2 is in CrashLoopBackOff.")
        return NS(choices=[NS(message=msg)])


def test_ask_runs_tool_and_sends_user(monkeypatch):
    monkeypatch.setitem(kube.FUNCTIONS, "list_pods", lambda namespace: [{"name": "web-2"}])
    completions = FakeCompletions()
    client = NS(chat=NS(completions=completions))
    result = agent.ask("Why is shop broken?", "maria", client)
    assert result == {"answer": "Pod web-2 is in CrashLoopBackOff.", "tools_used": ["list_pods"]}
    assert completions.calls[0]["model"] == "astra"
    assert completions.calls[0]["user"] == "maria"
    assert completions.calls[1]["messages"][-1]["content"] == '[{"name": "web-2"}]'


def test_health():
    assert TestClient(main.app).get("/health").json() == {"status": "ok"}


def test_ask_rejects_empty_question():
    assert TestClient(main.app).post("/ask", json={"question": ""}).status_code == 422


@pytest.mark.parametrize("gateway_status", [429, 422])
def test_budget_exceeded_is_429_with_a_clear_message(monkeypatch, gateway_status):
    # LiteLLM sends "type": "budget_exceeded" with HTTP 429 (older versions) or 422 (v1.106.5).
    import httpx
    from openai import APIStatusError

    request = httpx.Request("POST", "http://gateway/v1/chat/completions")
    response = httpx.Response(gateway_status, request=request)
    body = {"message": "Budget has been exceeded", "type": "budget_exceeded"}

    def over_budget(*_):
        raise APIStatusError("Budget has been exceeded", response=response, body=body)

    monkeypatch.setattr(main.agent, "ask", over_budget)
    monkeypatch.setattr(main, "get_client", lambda: None)
    reply = TestClient(main.app).post("/ask", json={"question": "Why?"})
    assert reply.status_code == 429
    assert "budget" in reply.json()["detail"]
