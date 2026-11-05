"""
Ellie's Postgres Cookbook
Running read-only queries through the pgEdge Postgres MCP Server, using
httpx.

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


def call_tool(client: httpx.Client, name: str,
              arguments: dict) -> tuple[str, bool]:
    """Calls a tool with tools/call and returns the text of its reply and
    whether the tool failed, which it reports by setting isError.

    The server answers a JSON-RPC error with HTTP status 200, so the
    function checks the reply for an error member as well as the HTTP
    status.
    """
    response = client.post(
        "/mcp/v1",
        headers={"Authorization": f"Bearer {TOKEN}"},
        json={"jsonrpc": "2.0", "id": 1, "method": "tools/call",
              "params": {"name": name, "arguments": arguments}},
    )
    if response.status_code != 200:
        raise McpError(f"{name} failed with HTTP {response.status_code}: "
                       f"{response.text[:200]}")
    try:
        reply = response.json()
    except ValueError:
        reply = None
    if not isinstance(reply, dict) or not ("result" in reply or "error" in reply):
        raise McpError(f"{name} failed: unexpected response: "
                       f"{response.text[:200]}")
    if "error" in reply:
        raise McpError(f"{name} failed: {reply['error'].get('message')}")
    result = reply["result"]
    return result["content"][0]["text"], bool(result.get("isError"))
# --8<-- [end:config]


# --8<-- [start:select]
def select_cheap_products(client: httpx.Client) -> None:
    """Runs a SELECT with query_database, and prints the column names and
    each row.

    The reply repeats the query, with the LIMIT that the server adds, and
    then has a line such as "Results (3 rows):", a header line, and one
    line for each row, with the values separated by tabs. The server
    writes a tab or a newline inside a value as \\t or \\n, and a NULL as
    an empty string.
    """
    text, failed = call_tool(client, "query_database", {
        "query": "SELECT name, price FROM cookbook_mcp.products "
                 "WHERE price < 100 ORDER BY price",
    })
    if failed:
        raise McpError(f"query_database failed: {text}")
    lines = text.split("\n")
    start = next((i for i, line in enumerate(lines)
                  if line.startswith("Results ")), None)
    if start is None or start + 1 >= len(lines):
        raise McpError(f"Unexpected reply: {text[:200]}")
    print("Columns: " + ", ".join(lines[start + 1].split("\t")))
    for line in lines[start + 2:]:
        if line:
            print("Row: " + ", ".join(line.split("\t")))
# --8<-- [end:select]


# --8<-- [start:insert]
def try_insert(client: httpx.Client) -> None:
    """Tries to add a row. query_database runs every query in a read-only
    transaction, so PostgreSQL itself refuses the INSERT with SQLSTATE
    25006, and the tool returns the error with isError set to true. The
    INSERT leaves out id, which the table requires, so that even a server
    that allows writes would refuse it rather than save a row. That is
    why the function checks for the read-only error itself rather than
    for any error, and fails if the write succeeds or fails for another
    reason. It prints only the last line of the error, which holds
    PostgreSQL's message, because some errors start with the query."""
    text, failed = call_tool(client, "query_database", {
        "query": "INSERT INTO cookbook_mcp.products "
                 "(name, category, price, in_stock, description) "
                 "VALUES ('Acme Test Widget', 'Testing', 1.00, true, "
                 "'A made-up product that is never saved')",
    })
    error_line = text.strip().split("\n")[-1]
    if not failed:
        raise McpError("The server accepted a write")
    if "SQLSTATE 25006" not in text:
        raise McpError(f"The INSERT failed for another reason: {error_line}")
    print(f"INSERT rejected: {error_line}")
# --8<-- [end:insert]


# --8<-- [start:main]
def main() -> int:
    if not TOKEN:
        print("MCP_TOKEN must be set", file=sys.stderr)
        return 1
    try:
        with httpx.Client(base_url=BASE_URL, timeout=TIMEOUT_SECONDS) as client:
            select_cheap_products(client)
            try_insert(client)
    # httpx.HTTPError is the base class for failures to reach the server,
    # such as a refused connection or a timeout. KeyError, IndexError,
    # TypeError, AttributeError and ValueError cover a reply that lacks the
    # members the program reads, or holds one of the wrong type or form.
    except (httpx.HTTPError, McpError, KeyError, IndexError, TypeError,
            AttributeError, ValueError) as e:
        print(f"MCP Server error: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
# --8<-- [end:main]
