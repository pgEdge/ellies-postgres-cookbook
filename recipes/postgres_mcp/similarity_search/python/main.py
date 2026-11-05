"""
Ellie's Postgres Cookbook
Searching by meaning through the pgEdge Postgres MCP Server, using httpx.

These examples are for pgEdge Postgres MCP Server 1.1.0.

Copyright (c) 2026, pgEdge, Inc.
This code is released under the PostgreSQL License.
"""

# --8<-- [start:imports]
import os
import re
import sys

import httpx
# --8<-- [end:imports]


# --8<-- [start:config]
# The or operator treats an empty variable as unset.
BASE_URL = (os.environ.get("MCP_URL") or "http://localhost:8080").rstrip("/")
TOKEN = os.environ.get("MCP_TOKEN") or ""

# The server turns the query into an embedding before it searches, which
# can take a while if the embedding model has to load first, so the
# timeout is longer than in the other recipes.
TIMEOUT_SECONDS = 90

QUERY = "a gift for an amateur astronomer"


class McpError(Exception):
    """Raised when the MCP Server rejects a request or replies oddly."""


def call_tool(client: httpx.Client, name: str, arguments: dict) -> str:
    """Calls a tool with tools/call and returns the text of its reply.

    The server answers a JSON-RPC error with HTTP status 200, and a tool
    that fails returns a normal result with isError set, so the function
    checks for both as well as the HTTP status.
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
    text = result["content"][0]["text"]
    if result.get("isError"):
        raise McpError(f"{name} failed: {text}")
    return text
# --8<-- [end:config]


# --8<-- [start:search]
def search(client: httpx.Client) -> None:
    """Searches the product descriptions for the query, and prints the
    number of results and the name of the product that matches it most
    closely.

    similarity_search finds the closest rows by vector distance, and then
    reorders them, mixing in a keyword score and favouring variety, so the
    first result in the reply is not always the closest. Each result has a
    line such as "Source: cookbook_mcp.products.description (vector search
    rank: #1, chunk: 1)"; the function picks the result ranked first by
    the vector search, whose text follows the first blank line after it.
    Every description starts with the product's name and a colon.
    """
    text = call_tool(client, "similarity_search", {
        "table_name": "cookbook_mcp.products",
        "query_text": QUERY,
        "top_n": 3,
    })
    print(f"Query: {QUERY}")
    lines = text.split("\n")
    count = sum(1 for line in lines if re.fullmatch(r"Result \d+/\d+", line))
    print(f"Results: {count}")

    source = next((i for i, line in enumerate(lines)
                   if line.startswith("Source: ") and
                   line.endswith("(vector search rank: #1, chunk: 1)")), None)
    blank = None if source is None else next(
        (i for i in range(source + 1, len(lines)) if lines[i] == ""), None)
    if blank is None or blank + 1 >= len(lines) or ": " not in lines[blank + 1]:
        raise McpError(f"The reply had no closest match: {text[:200]}")
    print(f"Best match: {lines[blank + 1].split(': ')[0]}")
# --8<-- [end:search]


# --8<-- [start:main]
def main() -> int:
    if not TOKEN:
        print("MCP_TOKEN must be set", file=sys.stderr)
        return 1
    try:
        with httpx.Client(base_url=BASE_URL, timeout=TIMEOUT_SECONDS) as client:
            search(client)
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
