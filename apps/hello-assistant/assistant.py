"""A very small chat assistant that calls Astra, the company's own model, through the gateway.

It is the shortest real app: the OpenAI SDK, a base URL, a team API key and the model name "astra".
The model itself runs on your GPU nodes; the gateway checks the key and the budget, masks personal
data and writes one trace per request to MLflow.

    export OPENAI_BASE_URL=http://localhost:4000/v1    # the gateway, through kubectl port-forward
    export OPENAI_API_KEY=<the hello-assistant team key>
    python assistant.py                                  # chat; an empty line or Ctrl+C ends it
    python assistant.py "What is a Kubernetes pod?"      # one question, one answer
"""

import os
import sys

from openai import OpenAI

MODEL = "astra"  # the only model name teams may call; the gateway knows which model is behind it
SYSTEM = "You are a helpful assistant for the engineers of our company. Answer briefly and plainly."
USER_ID = os.environ.get("ASSISTANT_USER", "hello-assistant-cli")  # an internal id, never a name or an email


def ask(client, history):
    """Send the whole conversation, print the answer as it arrives, and return it."""
    stream = client.chat.completions.create(model=MODEL, messages=history, user=USER_ID, stream=True)
    parts = []
    for chunk in stream:
        if chunk.choices and chunk.choices[0].delta.content:
            text = chunk.choices[0].delta.content
            parts.append(text)
            print(text, end="", flush=True)
    print()
    return "".join(parts)


def main():
    if not os.environ.get("OPENAI_BASE_URL") or not os.environ.get("OPENAI_API_KEY"):
        sys.exit("Set OPENAI_BASE_URL and OPENAI_API_KEY first (see the top of this file).")
    client = OpenAI()  # reads OPENAI_BASE_URL and OPENAI_API_KEY
    history = [{"role": "system", "content": SYSTEM}]

    if len(sys.argv) > 1:  # one question from the command line
        history.append({"role": "user", "content": " ".join(sys.argv[1:])})
        ask(client, history)
        return

    print(f"Chat with {MODEL}. An empty line ends it.")
    try:
        while True:
            question = input("you> ").strip()
            if not question:
                break
            history.append({"role": "user", "content": question})
            print("astra> ", end="", flush=True)
            history.append({"role": "assistant", "content": ask(client, history)})
    except (KeyboardInterrupt, EOFError):
        print()


if __name__ == "__main__":
    main()
