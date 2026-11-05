"""
Ellie's Postgres Cookbook
Reading resources and prompts from the pgEdge Postgres MCP Server, using
httpx.

These examples are for pgEdge Postgres MCP Server 1.1.0.

Copyright (c) 2026, pgEdge, Inc.
This code is released under the PostgreSQL License.
"""

# --8<-- [start:imports]
import json
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


def rpc(client: httpx.Client, method: str, params: dict):
    """Sends a JSON-RPC request and returns its result.

    The server answers a JSON-RPC error with HTTP status 200, so the
    function checks the reply for an error member as well as the HTTP
    status.
    """
    response = client.post(
        "/mcp/v1",
        headers={"Authorization": f"Bearer {TOKEN}"},
        json={"jsonrpc": "2.0", "id": 1, "method": method, "params": params},
    )
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


# --8<-- [start:resources]
def read_system_info(client: httpx.Client) -> None:
    """Lists the resources that the server offers, and then reads
    pg://system_info, which describes the PostgreSQL server.

    The contents of a resource are text, which for this one holds a JSON
    object, so the function parses the text a second time. version_number
    is a string such as "180006", from which integer division by 10000
    gives the major version.
    """
    result = rpc(client, "resources/list", {})
    print("Resources: " + ", ".join(r["uri"] for r in result["resources"]))

    result = rpc(client, "resources/read", {"uri": "pg://system_info"})
    try:
        info = json.loads(result["contents"][0]["text"])
    except ValueError:
        raise McpError(f"Unexpected result: {str(result)[:200]}") from None
    print(f"PostgreSQL major version: {int(info['version_number']) // 10000}")
    print(f"Writes allowed: {str(info['allow_writes']).lower()}")
# --8<-- [end:resources]


# --8<-- [start:prompts]
def read_prompts(client: httpx.Client) -> None:
    """Lists the prompts that the server offers, and then fetches
    explore-database, which takes no arguments. A prompt is a set of
    messages, ready to hand to a language model, that guide it through a
    task with the server's tools."""
    result = rpc(client, "prompts/list", {})
    print("Prompts: " + ", ".join(p["name"] for p in result["prompts"]))

    result = rpc(client, "prompts/get",
                 {"name": "explore-database", "arguments": {}})
    print(f"explore-database: {result['description']}")
    print(f"First message role: {result['messages'][0]['role']}")
# --8<-- [end:prompts]


# --8<-- [start:main]
def main() -> int:
    if not TOKEN:
        print("MCP_TOKEN must be set", file=sys.stderr)
        return 1
    try:
        with httpx.Client(base_url=BASE_URL, timeout=TIMEOUT_SECONDS) as client:
            read_system_info(client)
            read_prompts(client)
    # httpx.HTTPError is the base class for failures to reach the server,
    # such as a refused connection or a timeout. KeyError, IndexError and
    # TypeError cover a reply that lacks the members the program reads.
    except (httpx.HTTPError, McpError, KeyError, IndexError, TypeError) as e:
        print(f"MCP Server error: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
# --8<-- [end:main]
