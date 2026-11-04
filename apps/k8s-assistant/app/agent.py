"""The tool-calling loop: the model asks for cluster data, the app fetches it, the model answers."""

import json
import os

from openai import OpenAI

from app import kube
from app.prompt import SYSTEM_PROMPT

MODEL = os.environ.get("ASTRA_MODEL", "astra")  # the gateway's model name; the model behind it can change
MAX_TOOL_ROUNDS = 5  # stops a model that keeps calling tools from looping forever
MAX_RESULT_CHARS = 8000  # one tool result must not fill the context window


def make_client() -> OpenAI:
    # The SDK reads OPENAI_BASE_URL (https://astra.<domain>/v1) and OPENAI_API_KEY (the team key).
    # 60 s covers a long answer; retries cover a gateway restart.
    return OpenAI(timeout=60, max_retries=2)


def run_tool(name: str, arguments: str) -> str:
    func = kube.FUNCTIONS.get(name)
    if func is None:
        return json.dumps({"error": f"unknown tool {name}"})
    try:
        result = func(**json.loads(arguments or "{}"))
    except Exception as exc:  # noqa: BLE001 - the model gets the error and can explain it
        return json.dumps({"error": f"{type(exc).__name__}: {exc}"[:500]})
    return json.dumps(result, default=str)[:MAX_RESULT_CHARS]


def ask(question: str, user: str, client: OpenAI) -> dict:
    messages = [{"role": "system", "content": SYSTEM_PROMPT}, {"role": "user", "content": question}]
    tools_used = []
    for _ in range(MAX_TOOL_ROUNDS):
        response = client.chat.completions.create(
            model=MODEL,
            messages=messages,
            tools=kube.TOOLS,
            tool_choice="auto",
            temperature=0,  # the same question should give the same answer
            # LiteLLM records spend per end user from this field, next to the team key's spend.
            user=user,
        )
        message = response.choices[0].message
        if not message.tool_calls:
            return {"answer": message.content, "tools_used": tools_used}
        messages.append(message.model_dump(exclude_none=True))
        for call in message.tool_calls:
            tools_used.append(call.function.name)
            content = run_tool(call.function.name, call.function.arguments)
            messages.append({"role": "tool", "tool_call_id": call.id, "content": content})
    return {"answer": "I could not finish: too many tool calls. Ask a narrower question.", "tools_used": tools_used}
