"""
Ellie's Postgres Cookbook
Handling errors from the pgEdge RAG Server by error code, using httpx.

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

# A pipeline name that no server has, to cause PIPELINE_NOT_FOUND.
MISSING_PIPELINE = "no-such-pipeline"

# The server rejects both requests before it calls a language model, so
# they answer quickly.
TIMEOUT_SECONDS = 30.0
# --8<-- [end:config]


# --8<-- [start:request]
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
        self.message = message


def send_query(client: httpx.Client, pipeline: str, query: str) -> dict:
    """Sends a query to a pipeline, and returns the decoded reply. Raises
    ApiError when the server replies with an error."""
    response = client.post(
        f"/v1/pipelines/{quote(pipeline, safe='')}", json={"query": query}
    )
    if response.is_error:
        try:
            error = response.json()["error"]
            raise ApiError(response.status_code, error["code"], error["message"])
        except (ValueError, KeyError, TypeError):
            raise RagError(
                f"HTTP {response.status_code}, {response.text[:200]}"
            ) from None
    return response.json()
# --8<-- [end:request]


# --8<-- [start:advise]
def advise(err: ApiError) -> str:
    """Returns advice for an error, chosen by the error code. Branch on the
    code rather than on the message, which is meant for people and may
    change; branch on the HTTP status only for the temporary failures that
    have no code worth handling individually."""
    if err.code == "PIPELINE_NOT_FOUND":
        return "Check the pipeline name; GET /v1/pipelines lists the pipelines."
    if err.code == "INVALID_REQUEST":
        return "Fix the request; the body must be JSON with a non-empty query."
    if err.status in (503, 504):
        return "The failure may be temporary, so retry the request later."
    return f"This program does not handle {err.code}."
# --8<-- [end:advise]


# --8<-- [start:main]
def demonstrate(
    client: httpx.Client, title: str, pipeline: str, query: str, expected: str
) -> None:
    """Sends one query that the server must refuse with the expected error
    code, and prints how the program handles the refusal. Any other outcome
    is a failure."""
    print(title)
    try:
        send_query(client, pipeline, query)
    except ApiError as e:
        print(f"  {e.code} (HTTP {e.status}): {e.message}")
        print(f"  {advise(e)}")
        if e.code != expected:
            raise RagError(f"expected {expected}, got {e.code}") from None
        return
    raise RagError("the request unexpectedly succeeded")


def main() -> int:
    try:
        with httpx.Client(base_url=BASE_URL, timeout=TIMEOUT_SECONDS) as client:
            demonstrate(client, "Asking a pipeline that does not exist",
                        MISSING_PIPELINE, "Hello", "PIPELINE_NOT_FOUND")
            demonstrate(client, "Asking an empty question",
                        PIPELINE, "", "INVALID_REQUEST")
    # httpx.HTTPError is the base class for failures to reach the server,
    # such as a refused connection or a timeout.
    except (httpx.HTTPError, RagError) as e:
        print(f"RAG Server error: {e}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
# --8<-- [end:main]
