"""
Ellie's Postgres Cookbook
Holding a conversation with the pgEdge RAG Server, using httpx.

These examples are for pgEdge RAG Server 2.0.0.

Copyright (c) 2026, pgEdge, Inc.
This code is released under the PostgreSQL License.
"""

# --8<-- [start:imports]
import os
import sys
from urllib.parse import quote

import httpx
# --8<-- [end:imports]


# --8<-- [start:config]
# The or operator treats an empty variable as unset.
BASE_URL = (os.environ.get("RAG_SERVER_URL") or "http://localhost:8080").rstrip("/")
PIPELINE = os.environ.get("RAG_PIPELINE") or "cookbook"

# The second question does not say which version of the Acme Widget it
# means, so only the first question and its answer, which the model
# receives as history, settle that. The search uses only the current
# question, which is why this one still names the product.
QUESTIONS = [
    "How long does the Acme Widget 2.0 take to charge?",
    "And how many hours does the Acme Widget run for once it is charged?",
]

# The server waits for the language model before it replies, and a small
# model on a modest machine can take a while, so allow plenty of time.
TIMEOUT_SECONDS = 300.0
# --8<-- [end:config]


# --8<-- [start:ask]
class RagError(Exception):
    """Raised when the RAG Server rejects a request or replies oddly."""


def error_text(response: httpx.Response) -> str:
    """Describes an error response, which carries a JSON body of the form
    {"error": {"code": "...", "message": "..."}}."""
    try:
        error = response.json()["error"]
        return f"{error['code']}: {error['message']}"
    except (ValueError, KeyError, TypeError):
        return response.text[:200] or response.reason_phrase


def ask(client: httpx.Client, question: str, history: list[dict]) -> str:
    """Sends a question and the conversation so far to the pipeline, and
    returns the answer. The server keeps no conversation between requests,
    so history lists the earlier messages, each with a role of user or
    assistant, in order."""
    response = client.post(
        f"/v1/pipelines/{quote(PIPELINE, safe='')}",
        json={"query": question, "messages": history},
    )
    if response.is_error:
        raise RagError(f"HTTP {response.status_code}, {error_text(response)}")

    try:
        answer = response.json()["answer"]
        if isinstance(answer, str):
            return answer
    except (ValueError, KeyError, TypeError):
        pass
    raise RagError(f"Unexpected response: {response.text[:200]}")
# --8<-- [end:ask]


# --8<-- [start:converse]
def converse(client: httpx.Client) -> None:
    """Asks each question in turn, printing both sides of the conversation.
    After each answer, the question and the answer join the history that
    the next request carries."""
    history: list[dict] = []
    for question in QUESTIONS:
        answer = ask(client, question, history)
        print(f"You: {question}")
        print(f"Assistant: {answer}")
        history += [
            {"role": "user", "content": question},
            {"role": "assistant", "content": answer},
        ]
# --8<-- [end:converse]


# --8<-- [start:main]
def main() -> int:
    try:
        with httpx.Client(base_url=BASE_URL, timeout=TIMEOUT_SECONDS) as client:
            converse(client)
    # httpx.HTTPError is the base class for failures to reach the server,
    # such as a refused connection or a timeout.
    except (httpx.HTTPError, RagError) as e:
        print(f"RAG Server error: {e}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
# --8<-- [end:main]
