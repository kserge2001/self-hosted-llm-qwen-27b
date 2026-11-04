"""Builds the chat messages promptfoo sends to the gateway.

It reuses the app's real system prompt. When a test gives `tool_result`, the messages also hold
the tool calls and their results, as if the app had already asked the cluster. So the test checks
the model and the prompt, without a cluster.
"""

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from app.prompt import SYSTEM_PROMPT  # noqa: E402 - needs the path above


def build(context: dict) -> str:
    v = context["vars"]
    messages = [{"role": "system", "content": SYSTEM_PROMPT}, {"role": "user", "content": v["question"]}]
    # tool_result is the list_pods answer; events_result and deployment_result (optional) are the
    # answers of recent_events and describe_deployment.
    results = [
        ("list_pods", v.get("tool_result")),
        ("recent_events", v.get("events_result")),
        ("describe_deployment", v.get("deployment_result")),
    ]
    calls = [(f"call_{i}", name, out) for i, (name, out) in enumerate(results, 1) if out]
    if calls:
        arguments = json.dumps({"namespace": v["namespace"]})
        tool_calls = [
            {"id": cid, "type": "function", "function": {"name": name, "arguments": arguments}}
            for cid, name, _ in calls
        ]
        messages.append({"role": "assistant", "content": None, "tool_calls": tool_calls})
        for cid, _, out in calls:
            messages.append({"role": "tool", "tool_call_id": cid, "content": out})
    return json.dumps(messages)  # promptfoo reads a JSON list of messages as a chat prompt
