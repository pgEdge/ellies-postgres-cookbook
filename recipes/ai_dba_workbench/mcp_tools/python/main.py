"""
Ellie's Postgres Cookbook
Calling AI DBA Workbench MCP tools, using httpx.

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
def settings() -> dict:
    """Reads the settings from the environment.

    The or operator treats an empty variable as unset.
    """
    token = os.environ.get("WORKBENCH_TOKEN") or ""
    connection_id = os.environ.get("WORKBENCH_CONNECTION_ID") or ""
    if not (token and connection_id):
        raise RuntimeError(
            "WORKBENCH_TOKEN and WORKBENCH_CONNECTION_ID must be set"
        )
    return {
        "base_url": (
            os.environ.get("WORKBENCH_URL") or "http://localhost:8080"
        ).rstrip("/"),
        "token": token,
        "connection_id": int(connection_id),
    }
# --8<-- [end:config]


# --8<-- [start:rpc]
def rpc(cfg: dict, method: str, params: dict) -> dict:
    """Sends a JSON-RPC request to the MCP endpoint and returns the result.

    The server answers a JSON-RPC error with HTTP status 200, so the
    function checks the reply for an error member as well as for an HTTP
    failure.
    """
    response = httpx.post(
        f"{cfg['base_url']}/mcp/v1", timeout=30,
        headers={"Authorization": f"Bearer {cfg['token']}"},
        json={"jsonrpc": "2.0", "id": 1, "method": method, "params": params},
    )
    if response.is_error:
        raise RuntimeError(
            f"{method} failed with status {response.status_code}: "
            f"{response.text.strip()}"
        )
    reply = response.json()
    if "error" in reply:
        raise RuntimeError(f"{method} failed: {reply['error']['message']}")
    return reply["result"]
# --8<-- [end:rpc]


# --8<-- [start:initialize]
def initialize(cfg: dict) -> None:
    """Introduces the client to the server and prints the server's name and
    version. The Workbench keeps no session, so a client can skip this
    step."""
    result = rpc(cfg, "initialize", {
        "protocolVersion": "2024-11-05",
        "capabilities": {},
        "clientInfo": {"name": "cookbook", "version": "1.0.0"},
    })
    info = result["serverInfo"]
    print(f"Server: {info['name']} {info['version']}")
# --8<-- [end:initialize]


# --8<-- [start:list_tools]
def list_tools(cfg: dict) -> None:
    """Lists the tools, checks that the two that the program calls are
    present, and prints the arguments that each one requires."""
    tools = {t["name"]: t for t in rpc(cfg, "tools/list", {})["tools"]}
    # The server lists its tools in no fixed order, so look the two tools
    # up by name.
    for name in ("query_database", "execute_explain"):
        if name not in tools:
            raise RuntimeError(f"The server does not offer {name}")
        required = ", ".join(tools[name]["inputSchema"]["required"])
        print(f"{name} requires: {required}")
# --8<-- [end:list_tools]


# --8<-- [start:call_tool]
def call_tool(cfg: dict, name: str, arguments: dict) -> str:
    """Calls a tool and returns the text of its reply.

    A tool that fails returns a normal result with isError set, so the
    function checks that flag too.
    """
    result = rpc(cfg, "tools/call", {"name": name, "arguments": arguments})
    text = result["content"][0]["text"]
    if result.get("isError"):
        raise RuntimeError(f"{name} failed: {text}")
    return text
# --8<-- [end:call_tool]


# --8<-- [start:query_database]
def query_database(cfg: dict) -> None:
    """Runs a harmless read-only query with query_database and prints the
    column names and the rows.

    The reply is text that starts with the connection and the query, and
    then has a "Results" line followed by the rows in tab-separated form,
    so the function prints only what follows that line.
    """
    text = call_tool(cfg, "query_database", {
        "connection_id": cfg["connection_id"],
        "query": "SELECT 'Hello from the Workbench' AS greeting, "
                 "6 * 7 AS answer",
    })
    _, found, results = text.partition("\nResults")
    if not found:
        raise RuntimeError("The reply had no results")
    # Skip the rest of the Results line, then turn the tabs into commas.
    lines = results.split("\n")[1:]
    for number, line in enumerate(l for l in lines if l):
        label = "Columns" if number == 0 else "Row"
        values = ", ".join(line.split("\t"))
        print(f"{label}: {values}")
# --8<-- [end:query_database]


# --8<-- [start:execute_explain]
def execute_explain(cfg: dict) -> None:
    """Plans a query with execute_explain, without running it, and prints
    the type of the first node of the plan. Setting analyze to true would
    run the query."""
    text = call_tool(cfg, "execute_explain", {
        "connection_id": cfg["connection_id"],
        "query": "SELECT 1 + 1",
        "analyze": False,
    })
    # The plan follows a line of equals signs.
    match = re.search(r"Execution Plan:\n=+\n(\S+)", text)
    if not match:
        raise RuntimeError("The reply had no execution plan")
    print(f"Plan starts with: {match.group(1)}")
# --8<-- [end:execute_explain]


# --8<-- [start:main]
def main() -> int:
    try:
        cfg = settings()
        initialize(cfg)
        list_tools(cfg)
        query_database(cfg)
        execute_explain(cfg)
    # httpx.HTTPError covers failures to connect, and RuntimeError covers
    # replies that the server rejected or that lacked what we need.
    except (httpx.HTTPError, RuntimeError) as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
# --8<-- [end:main]
