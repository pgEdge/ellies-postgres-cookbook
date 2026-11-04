"""
Ellie's Postgres Cookbook
Limiting the answers of the pgEdge RAG Server to each caller's own rows,
using httpx.

These examples are for pgEdge RAG Server 2.0.0.

Copyright (c) 2026, pgEdge, Inc.
This code is released under the PostgreSQL License.
"""

# --8<-- [start:imports]
import json
import os
import sys
from urllib.parse import quote

import httpx
# --8<-- [end:imports]


# --8<-- [start:config]
# The or operator treats an empty variable as unset.
BASE_URL = (os.environ.get("RAG_SERVER_URL") or "http://localhost:8080").rstrip("/")
PIPELINE = os.environ.get("RAG_PIPELINE") or "cookbook_private"

QUESTION = "What is the status of my warranty claim?"

# The callers to ask for. The fictional documents in the pipeline's table
# belong to these two people.
CALLERS = ["jane.doe@example.com", "john.smith@example.com"]

# The header in which the server expects a trusted proxy to put the claims
# of the caller. This is the server's default; the identity.claims_header
# setting changes it.
CLAIMS_HEADER = "X-Forwarded-Claims"

# The server waits for the language model before it replies, and a small
# model on a modest machine can take a while, so allow plenty of time.
TIMEOUT_SECONDS = 300.0
# --8<-- [end:config]


# --8<-- [start:ask]
class RagError(Exception):
    """Raised when a reply is not one that the program can interpret."""


class ApiError(Exception):
    """Raised when the RAG Server replies with an error. The reply has an
    HTTP status and a JSON body of the form
    {"error": {"code": "...", "message": "..."}}."""

    def __init__(self, status: int, code: str, message: str):
        super().__init__(f"{code}: {message}")
        self.status = status
        self.code = code


def ask(client: httpx.Client, subject: str | None) -> dict:
    """Sends the question to the pipeline on behalf of a caller, and asks
    for the documents that the answer came from. Returns the decoded reply.
    A subject of None sends no identity at all."""
    # The claims are a JSON object, which json.dumps builds, so that the
    # subject needs no escaping.
    headers = {}
    if subject is not None:
        headers[CLAIMS_HEADER] = json.dumps({"sub": subject})

    response = client.post(
        f"/v1/pipelines/{quote(PIPELINE, safe='')}",
        json={"query": QUESTION, "include_sources": True},
        headers=headers,
    )
    if response.is_error:
        try:
            error = response.json()["error"]
            raise ApiError(response.status_code, error["code"], error["message"])
        except (ValueError, KeyError, TypeError):
            raise RagError(
                f"HTTP {response.status_code}, {response.text[:200]}"
            ) from None

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
def ask_anonymously(client: httpx.Client) -> None:
    """Asks the question without an identity. The server must refuse with
    IDENTITY_REQUIRED, because it never falls back to the pipeline's own
    database role; any other outcome is a failure."""
    print()
    print("Caller: (no identity)")
    try:
        ask(client, None)
    except ApiError as e:
        print(f"{e.code} (HTTP {e.status})")
        if e.code != "IDENTITY_REQUIRED":
            raise RagError(f"expected IDENTITY_REQUIRED, got {e}") from None
        return
    raise RagError("the server answered without an identity; "
                   "is identity.enabled set?")


def main() -> int:
    try:
        with httpx.Client(base_url=BASE_URL, timeout=TIMEOUT_SECONDS) as client:
            print(f"Question: {QUESTION}")
            for caller in CALLERS:
                body = ask(client, caller)
                print()
                print(f"Caller: {caller}")
                show(body)
            ask_anonymously(client)
    # httpx.HTTPError is the base class for failures to reach the server,
    # such as a refused connection or a timeout.
    except (httpx.HTTPError, ApiError, RagError) as e:
        print(f"RAG Server error: {e}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
# --8<-- [end:main]
