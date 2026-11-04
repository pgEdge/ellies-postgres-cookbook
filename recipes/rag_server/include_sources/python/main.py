"""
Ellie's Postgres Cookbook
Showing the sources of an answer from the pgEdge RAG Server, using httpx.

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


def ask(client: httpx.Client, question: str) -> dict:
    """Sends the question to the pipeline, and asks for the documents that
    the answer came from. Returns the decoded reply."""
    response = client.post(
        f"/v1/pipelines/{quote(PIPELINE, safe='')}",
        json={"query": question, "include_sources": True},
    )
    if response.is_error:
        raise RagError(f"HTTP {response.status_code}, {error_text(response)}")

    try:
        body = response.json()
        if isinstance(body["answer"], str):
            return body
    except (ValueError, KeyError, TypeError):
        pass
    raise RagError(f"Unexpected response: {response.text[:200]}")
# --8<-- [end:ask]


# --8<-- [start:sources]
def describe_source(source: dict) -> str:
    """Returns one line for a source: its ID and the start of its text."""
    # Collapse any line breaks, and shorten long text for display.
    content = " ".join(source.get("content", "").split())
    if len(content) > 60:
        content = content[:57] + "..."
    return f"- {source.get('id', '(no id)')}: {content}"


def print_sources(body: dict) -> None:
    """Prints the sources in a reply, in the order the server returns."""
    # The server leaves out the sources array, without an error, when the
    # pipeline does not set allow_include_sources.
    sources = body.get("sources")
    if not sources:
        print("No sources were returned. Does the pipeline set "
              "allow_include_sources?")
        return

    print(f"Sources ({len(sources)}):")
    for source in sources:
        print(describe_source(source))
# --8<-- [end:sources]


# --8<-- [start:main]
def main() -> int:
    try:
        with httpx.Client(base_url=BASE_URL, timeout=TIMEOUT_SECONDS) as client:
            body = ask(client, QUESTION)
        print(f"Question: {QUESTION}")
        print(f"Answer:\n{body['answer']}")
        print_sources(body)
    # httpx.HTTPError is the base class for failures to reach the server,
    # such as a refused connection or a timeout.
    except (httpx.HTTPError, RagError) as e:
        print(f"RAG Server error: {e}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
# --8<-- [end:main]
