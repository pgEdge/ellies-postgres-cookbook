"""
Ellie's Postgres Cookbook
Exploring a schema through the pgEdge Postgres MCP Server, using httpx.

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

TIMEOUT_SECONDS = 30

# The schema and table that scripts/start_postgres_mcp.sh creates.
SCHEMA = "cookbook_mcp"
TABLE = "products"


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


# --8<-- [start:parse_tsv]
def parse_tsv(text: str) -> list[dict]:
    """Reads the table in a tool's reply into a list of rows, each a
    dictionary keyed by column name.

    The reply starts with a line or two about the database, and then has
    a header line and one line for each row, with the values separated by
    tabs. The server writes a tab or a newline inside a value as \\t or
    \\n, so splitting on them is safe. The header is the first line that
    starts with "schema", the first column of every table that
    get_schema_info returns.
    """
    lines = text.split("\n")
    start = next((i for i, line in enumerate(lines)
                  if line.startswith("schema\t")), None)
    if start is None:
        raise McpError(f"The reply had no table: {text[:200]}")
    header = lines[start].split("\t")
    return [dict(zip(header, line.split("\t")))
            for line in lines[start + 1:] if line]
# --8<-- [end:parse_tsv]


# --8<-- [start:list_tables]
def list_tables(client: httpx.Client) -> None:
    """Lists the tables in the schema with their comments. With compact set
    to true, get_schema_info returns one line for each table, without its
    columns, which suits a first look at a large database."""
    text = call_tool(client, "get_schema_info",
                     {"schema_name": SCHEMA, "compact": True})
    print(f"Tables in {SCHEMA}:")
    for row in parse_tsv(text):
        print(f"- {row['table']}: {row.get('table_desc') or '(no comment)'}")
# --8<-- [end:list_tables]


# --8<-- [start:describe_table]
def describe_table(client: httpx.Client) -> None:
    """Lists the columns of one table with their types. Given a table_name,
    get_schema_info returns one line for each column, which also carries
    the table's details."""
    text = call_tool(client, "get_schema_info",
                     {"schema_name": SCHEMA, "table_name": TABLE})
    rows = parse_tsv(text)
    if not rows:
        raise McpError(f"{SCHEMA}.{TABLE} has no columns")
    print(f"Columns of {SCHEMA}.{TABLE}:")
    for row in rows:
        key = " (primary key)" if row.get("is_pk") == "true" else ""
        print(f"- {row['column']}: {row['data_type']}{key}")
# --8<-- [end:describe_table]


# --8<-- [start:count_rows]
def count_in_stock(client: httpx.Client) -> None:
    """Counts the products in stock with count_rows. The where argument is
    a condition without the WHERE keyword; the server rejects one that
    contains a subquery."""
    text = call_tool(client, "count_rows",
                     {"schema": SCHEMA, "table": TABLE, "where": "in_stock"})
    # The reply ends with a line such as "Count: 4".
    match = re.search(r"^Count: (\d+)$", text, re.MULTILINE)
    if not match:
        raise McpError(f"The reply had no count: {text[:200]}")
    print(f"Products in stock: {match.group(1)}")
# --8<-- [end:count_rows]


# --8<-- [start:main]
def main() -> int:
    if not TOKEN:
        print("MCP_TOKEN must be set", file=sys.stderr)
        return 1
    try:
        with httpx.Client(base_url=BASE_URL, timeout=TIMEOUT_SECONDS) as client:
            list_tables(client)
            describe_table(client)
            count_in_stock(client)
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
