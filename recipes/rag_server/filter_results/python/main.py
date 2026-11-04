"""
Ellie's Postgres Cookbook
Filtering the documents that the pgEdge RAG Server retrieves, using httpx.

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

QUESTION = "How long does the Acme Widget take to charge?"

# The product to search, and the versions to ask about in turn. The
# question names no version, so only the filter tells the pipeline which
# documents to use.
PRODUCT = "Acme Widget"
VERSIONS = ["1.0", "2.0"]

# The server waits for the language model before it replies, and a small
# model on a modest machine can take a while, so allow plenty of time.
TIMEOUT_SECONDS = 300.0
# --8<-- [end:config]


# --8<-- [start:filter]
def build_filter(product: str, version: str) -> dict:
    """Returns the filter for a product and a version. The conditions are
    joined with AND, which is the default, and each one compares a column
    of the pipeline's table with a value. The server passes the values to
    PostgreSQL as parameters, so they need no escaping."""
    return {
        "logic": "AND",
        "conditions": [
            {"column": "product", "operator": "=", "value": product},
            {"column": "version", "operator": "=", "value": version},
        ],
    }
# --8<-- [end:filter]


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


def ask(client: httpx.Client, question: str, filter_: dict) -> dict:
    """Sends the question and the filter to the pipeline, and asks for the
    documents that the answer came from. Returns the decoded reply."""
    response = client.post(
        f"/v1/pipelines/{quote(PIPELINE, safe='')}",
        json={"query": question, "filter": filter_, "include_sources": True},
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


# --8<-- [start:show]
def show(body: dict) -> None:
    """Prints the answer in a reply, and then the IDs of its sources."""
    ids = [str(source.get("id", "(no id)")) for source in body.get("sources") or []]
    print(f"Answer:\n{body['answer']}")
    print(f"Sources: {', '.join(ids)}")
# --8<-- [end:show]


# --8<-- [start:main]
def main() -> int:
    try:
        with httpx.Client(base_url=BASE_URL, timeout=TIMEOUT_SECONDS) as client:
            print(f"Question: {QUESTION}")
            for version in VERSIONS:
                body = ask(client, QUESTION, build_filter(PRODUCT, version))
                print()
                print(f"Filter: product = {PRODUCT}, version = {version}")
                show(body)
    # httpx.HTTPError is the base class for failures to reach the server,
    # such as a refused connection or a timeout.
    except (httpx.HTTPError, RagError) as e:
        print(f"RAG Server error: {e}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
# --8<-- [end:main]
