"""
Ellie's Postgres Cookbook
Checking the health of the pgEdge RAG Server and listing its pipelines,
using httpx.

These examples are for pgEdge RAG Server 2.0.0.

Copyright (c) 2026, pgEdge, Inc.
This code is released under the PostgreSQL License.
"""

# --8<-- [start:imports]
import os
import sys

import httpx
# --8<-- [end:imports]


# --8<-- [start:config]
# The or operator treats an empty variable as unset.
BASE_URL = (os.environ.get("RAG_SERVER_URL") or "http://localhost:8080").rstrip("/")

# None of these endpoints calls a language model, but the health check
# contacts each provider, so allow it some time.
TIMEOUT_SECONDS = 30.0


class RagError(Exception):
    """Raised when the RAG Server rejects a request or replies oddly."""


def get(client: httpx.Client, path: str) -> dict:
    """Fetches a path from the server, and returns the decoded reply."""
    response = client.get(path)
    if response.is_error:
        raise RagError(f"HTTP {response.status_code}, {response.text[:200]}")
    try:
        body = response.json()
        if isinstance(body, dict):
            return body
    except ValueError:
        pass
    raise RagError(f"Unexpected response: {response.text[:200]}")
# --8<-- [end:config]


# --8<-- [start:live]
def check_live(client: httpx.Client) -> None:
    """Checks that the server process is running. The /v1/live endpoint is
    cheap and calls nothing else, so it suits a frequent liveness probe."""
    body = get(client, "/v1/live")
    if body.get("status") != "ok":
        raise RagError(f"Unexpected response: {body}")
    print("Live: ok")
# --8<-- [end:live]


# --8<-- [start:health]
def describe_provider(provider: dict) -> str:
    """Describes whether a language model provider answered the check."""
    if provider.get("reachable"):
        return "reachable"
    return f"unreachable ({provider.get('error', 'unknown')})"


def check_health(client: httpx.Client) -> bool:
    """Checks whether each pipeline can reach its language model providers.
    The /v1/health endpoint answers with HTTP 200 even when a provider is
    down, so the status field is the thing to check: it is "healthy" or
    "degraded". Prints the report, and returns whether the server is
    healthy."""
    body = get(client, "/v1/health")
    status = body.get("status")
    if not isinstance(status, str):
        raise RagError(f"Unexpected response: {body}")

    print(f"Health: {status}")
    for pipeline in body.get("pipelines") or []:
        embedding = describe_provider(pipeline.get("embedding", {}))
        completion = describe_provider(pipeline.get("completion", {}))
        print(f"- {pipeline.get('name')}: embedding {embedding}, "
              f"completion {completion}")
    return status == "healthy"
# --8<-- [end:health]


# --8<-- [start:pipelines]
def list_pipelines(client: httpx.Client) -> None:
    """Lists the pipelines that the server offers, with their
    descriptions."""
    pipelines = get(client, "/v1/pipelines").get("pipelines")
    if not isinstance(pipelines, list):
        raise RagError("Unexpected response: missing pipelines")

    print(f"Pipelines ({len(pipelines)}):")
    for pipeline in pipelines:
        description = pipeline.get("description") or "(no description)"
        print(f"- {pipeline.get('name')}: {description}")
# --8<-- [end:pipelines]


# --8<-- [start:main]
def main() -> int:
    try:
        with httpx.Client(base_url=BASE_URL, timeout=TIMEOUT_SECONDS) as client:
            check_live(client)
            healthy = check_health(client)
            list_pipelines(client)
    # httpx.HTTPError is the base class for failures to reach the server,
    # such as a refused connection or a timeout.
    except (httpx.HTTPError, RagError) as e:
        print(f"RAG Server error: {e}", file=sys.stderr)
        return 1

    # A degraded server still answers with HTTP 200, so report it with the
    # exit status.
    if not healthy:
        print("RAG Server is not healthy", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
# --8<-- [end:main]
