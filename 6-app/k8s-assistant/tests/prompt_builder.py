"""Builds the chat messages promptfoo sends to the gateway.

It reuses the app's real system prompt. When a test gives `tool_result`, the messages also hold
a list_pods call and its result, as if the app had already asked the cluster. So the test checks
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
    if v.get("tool_result"):
        arguments = json.dumps({"namespace": v["namespace"]})
        call = {"id": "call_1", "type": "function", "function": {"name": "list_pods", "arguments": arguments}}
        messages.append({"role": "assistant", "content": None, "tool_calls": [call]})
        messages.append({"role": "tool", "tool_call_id": "call_1", "content": v["tool_result"]})
    return json.dumps(messages)  # promptfoo reads a JSON list of messages as a chat prompt
