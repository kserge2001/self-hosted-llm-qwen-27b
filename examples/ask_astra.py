# An app team's code: call Astra with the OpenAI SDK and the team's own key.
# Needs:  pip install openai python-dotenv
# And a .env file next to this script (see examples/.env.example).
from dotenv import load_dotenv
from openai import OpenAI

load_dotenv()

# The SDK reads OPENAI_BASE_URL (the gateway) and OPENAI_API_KEY (the team key) from .env
client = OpenAI()

response = client.chat.completions.create(
    model="astra",
    messages=[
        {"role": "system", "content": "You are Astra, the company assistant. Answer in two sentences."},
        {"role": "user", "content": "What should a new employee prepare for their first day?"},
    ],
)

print(response.choices[0].message.content)
print(response.usage)
