"""
Ellie's Postgres Cookbook
Connecting to the pgEdge Postgres MCP Server, using httpx.

These examples are for pgEdge Postgres MCP Server 1.1.0.

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
BASE_URL = (os.environ.get("MCP_URL") or "http://localhost:8080").rstrip("/")
TOKEN = os.environ.get("MCP_TOKEN") or ""

TIMEOUT_SECONDS = 30


class McpError(Exception):
    """Raised when the MCP Server rejects a request or replies oddly."""


def post(client: httpx.Client, token: str, message: dict) -> httpx.Response:
    """Posts a JSON-RPC message to the MCP endpoint with a token."""
    return client.post(
        "/mcp/v1", json=message,
        headers={"Authorization": f"Bearer {token}"},
    )


def rpc(client: httpx.Client, method: str, params: dict) -> dict:
    """Sends a JSON-RPC request and returns its result.

    The server answers a JSON-RPC error with HTTP status 200, so the
    function checks the reply for an error member as well as the HTTP
    status.
    """
    response = post(client, TOKEN, {
        "jsonrpc": "2.0", "id": 1, "method": method, "params": params,
    })
    if response.status_code != 200:
        raise McpError(f"{method} failed with HTTP {response.status_code}: "
                       f"{response.text[:200]}")
    try:
        reply = response.json()
    except ValueError:
        reply = None
    if not isinstance(reply, dict) or not ("result" in reply or "error" in reply):
        raise McpError(f"{method} failed: unexpected response: "
                       f"{response.text[:200]}")
    if "error" in reply:
        raise McpError(f"{method} failed: {reply['error'].get('message')}")
    return reply["result"]
# --8<-- [end:config]


# --8<-- [start:health]
def check_health(client: httpx.Client) -> None:
    """Checks that the server is running. The /health endpoint needs no
    token."""
    response = client.get("/health")
    if response.status_code != 200:
        raise McpError(f"Health check failed with HTTP "
                       f"{response.status_code}: {response.text[:200]}")
    try:
        status = response.json().get("status")
    except (ValueError, AttributeError):
        status = None
    if status != "ok":
        raise McpError(f"Unexpected response: {response.text[:200]}")
    print("Health: ok")
# --8<-- [end:health]


# --8<-- [start:initialize]
def initialize(client: httpx.Client) -> None:
    """Introduces the client to the server, and prints the server's name and
    version and the protocol revision that the server chose.

    The server accepts 2024-11-05, 2025-03-26, 2025-06-18 and 2025-11-25,
    and answers a revision it does not know with one that it does, so the
    client checks the answer. The notifications/initialized message then
    completes the handshake; it is a notification, with no id, so the
    server replies with HTTP 202 and no body.
    """
    result = rpc(client, "initialize", {
        "protocolVersion": "2025-06-18",
        "capabilities": {},
        "clientInfo": {"name": "cookbook", "version": "1.0.0"},
    })
    info = result["serverInfo"]
    print(f"Server: {info['name']} {info['version']}")
    protocol = result.get("protocolVersion")
    if protocol != "2025-06-18":
        raise McpError(f"The server chose protocol version {protocol}")
    print(f"Protocol version: {protocol}")

    response = post(client, TOKEN, {
        "jsonrpc": "2.0", "method": "notifications/initialized",
    })
    if response.status_code != 202:
        raise McpError(f"notifications/initialized failed with HTTP "
                       f"{response.status_code}: {response.text[:200]}")
# --8<-- [end:initialize]


# --8<-- [start:wrong_token]
def wrong_token(client: httpx.Client) -> None:
    """Sends a request with a token that the server does not know, and
    prints the HTTP status and the server's message, which is a JSON object
    with an error member rather than a JSON-RPC reply."""
    response = post(client, "not-a-real-token", {
        "jsonrpc": "2.0", "id": 1, "method": "tools/list", "params": {},
    })
    if response.status_code != 401:
        raise McpError(f"Expected HTTP 401 for a wrong token, but got "
                       f"{response.status_code}")
    try:
        message = response.json().get("error") or "no message"
    except (ValueError, AttributeError):
        message = "no message"
    print(f"Wrong token: HTTP {response.status_code}, {message}")
# --8<-- [end:wrong_token]


# --8<-- [start:main]
def main() -> int:
    if not TOKEN:
        print("MCP_TOKEN must be set", file=sys.stderr)
        return 1
    try:
        with httpx.Client(base_url=BASE_URL, timeout=TIMEOUT_SECONDS) as client:
            check_health(client)
            initialize(client)
            wrong_token(client)
    # httpx.HTTPError is the base class for failures to reach the server,
    # such as a refused connection or a timeout. KeyError and TypeError
    # cover a result that lacks the members the program reads.
    except (httpx.HTTPError, McpError, KeyError, TypeError) as e:
        print(f"MCP Server error: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
# --8<-- [end:main]
