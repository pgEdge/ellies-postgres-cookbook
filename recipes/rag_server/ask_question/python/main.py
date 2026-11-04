"""
Ellie's Postgres Cookbook
Asking the pgEdge RAG Server a question, using httpx.

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

QUESTION = "How long does the Acme Widget 2.0 take to charge?"

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


def ask(client: httpx.Client, question: str) -> tuple[str, int]:
    """Sends the question to the pipeline, and returns the answer with the
    number of tokens the request used."""
    # quote() escapes any character in the pipeline name that is not safe
    # in a URL path.
    response = client.post(
        f"/v1/pipelines/{quote(PIPELINE, safe='')}",
        json={"query": question},
    )
    if response.is_error:
        raise RagError(f"HTTP {response.status_code}, {error_text(response)}")

    try:
        body = response.json()
        return body["answer"], body["tokens_used"]
    except (ValueError, KeyError, TypeError):
        raise RagError(f"Unexpected response: {response.text[:200]}")
# --8<-- [end:ask]


# --8<-- [start:main]
def main() -> int:
    try:
        # The with block closes the client's connections when it exits,
        # whether or not an error occurred.
        with httpx.Client(base_url=BASE_URL, timeout=TIMEOUT_SECONDS) as client:
            answer, tokens_used = ask(client, QUESTION)
    # httpx.HTTPError is the base class for failures to reach the server,
    # such as a refused connection or a timeout.
    except (httpx.HTTPError, RagError) as e:
        print(f"RAG Server error: {e}", file=sys.stderr)
        return 1

    print(f"Question: {QUESTION}")
    print(f"Answer:\n{answer}")
    print(f"Tokens used: {tokens_used}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
# --8<-- [end:main]
