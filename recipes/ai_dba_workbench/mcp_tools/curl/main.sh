#!/usr/bin/env bash
#
# Ellie's Postgres Cookbook
# Calling AI DBA Workbench MCP tools with curl and jq.
#
# Copyright (c) 2026, pgEdge, Inc.
# This code is released under the PostgreSQL License.

# --8<-- [start:imports]
# Stop at the first failing command, treat an unset variable as an error,
# and fail a pipeline when any command in it fails.
set -euo pipefail

# The script needs curl to make the requests and jq to build the requests
# and read the replies.
for tool in curl jq; do
    command -v "$tool" >/dev/null || { echo "$tool is required" >&2; exit 1; }
done
# --8<-- [end:imports]

# --8<-- [start:config]
# Read the settings from the environment. The :- and :? forms, unlike - and
# ?, treat an empty variable as unset.
WORKBENCH_URL="${WORKBENCH_URL:-http://localhost:8080}"
WORKBENCH_URL="${WORKBENCH_URL%/}"
: "${WORKBENCH_TOKEN:?WORKBENCH_TOKEN must be set}"
: "${WORKBENCH_CONNECTION_ID:?WORKBENCH_CONNECTION_ID must be set}"
# --8<-- [end:config]

# --8<-- [start:rpc]
# Sends a JSON-RPC request to the MCP endpoint and prints the result:
# rpc METHOD PARAMS_JSON. The server answers a JSON-RPC error with HTTP
# status 200, so the function checks the reply for an error member as well as
# for an HTTP failure.
# The token goes to curl in a header file that bash supplies through a pipe,
# so that it never appears in the arguments of the curl process, which other
# users can read in the process list.
rpc() {
    local method="$1" params="$2"
    local response
    response=$(jq -n --arg method "$method" --argjson params "$params" \
        '{jsonrpc: "2.0", id: 1, method: $method, params: $params}' |
        curl --silent --show-error --fail-with-body \
            --header @<(printf 'Authorization: Bearer %s\n' "$WORKBENCH_TOKEN") \
            --header 'Content-Type: application/json' \
            --data @- "$WORKBENCH_URL/mcp/v1") || {
        echo "$method failed: $response" >&2
        return 1
    }
    if jq -e '.error' >/dev/null 2>&1 <<<"$response"; then
        echo "$method failed: $(jq -r '.error.message' <<<"$response")" >&2
        return 1
    fi
    jq -c '.result' <<<"$response"
}
# --8<-- [end:rpc]

# --8<-- [start:initialize]
# Introduces the client to the server and prints the server's name and
# version. The Workbench keeps no session, so a client can skip this step.
initialize() {
    local result
    result=$(rpc initialize '{
        "protocolVersion": "2024-11-05",
        "capabilities": {},
        "clientInfo": {"name": "cookbook", "version": "1.0.0"}
    }') || return 1
    jq -r '"Server: \(.serverInfo.name) \(.serverInfo.version)"' <<<"$result"
}
# --8<-- [end:initialize]

# --8<-- [start:list_tools]
# Lists the tools, checks that the two that the script calls are present, and
# prints the arguments that each one requires.
list_tools() {
    local result
    result=$(rpc tools/list '{}') || return 1
    # The server lists its tools in no fixed order, so the filter looks up the
    # two tools by name, in the order that it names them.
    jq -r '.tools as $tools | ("query_database", "execute_explain") as $name |
           $tools[] | select(.name == $name) |
           "\(.name) requires: \(.inputSchema.required | join(", "))"' \
        <<<"$result"
    if [[ "$(jq '[.tools[].name | select(. == "query_database" or
                  . == "execute_explain")] | length' <<<"$result")" -ne 2 ]]; then
        echo "The server does not offer both tools" >&2
        return 1
    fi
}
# --8<-- [end:list_tools]

# --8<-- [start:call_tool]
# Calls a tool and prints the text of its reply: call_tool NAME ARGUMENTS_JSON.
# A tool that fails returns a normal result with isError set, so the function
# checks that flag too.
call_tool() {
    local name="$1" arguments="$2"
    local result
    result=$(rpc tools/call \
        "$(jq -nc --arg name "$name" --argjson arguments "$arguments" \
            '{name: $name, arguments: $arguments}')") || return 1
    if [[ "$(jq -r '.isError // false' <<<"$result")" == "true" ]]; then
        echo "$name failed: $(jq -r '.content[0].text' <<<"$result")" >&2
        return 1
    fi
    jq -r '.content[0].text' <<<"$result"
}
# --8<-- [end:call_tool]

# --8<-- [start:query_database]
# Runs a harmless read-only query with query_database and prints the column
# names and the rows. The reply is text that starts with the connection and
# the query, and then has a "Results" line followed by the rows in
# tab-separated form, so the function prints only what follows that line.
query_database() {
    local text query rows
    query="SELECT 'Hello from the Workbench' AS greeting, 6 * 7 AS answer"
    text=$(call_tool query_database "$(jq -nc \
        --argjson connection_id "$WORKBENCH_CONNECTION_ID" \
        --arg query "$query" \
        '{connection_id: $connection_id, query: $query}')")
    # Drop everything up to the Results line, then turn the tabs into commas.
    rows=$(sed -n '/^Results (/,$p' <<<"$text" | tail -n +2 |
        awk -F'\t' 'BEGIN { OFS = ", " }
                    { $1 = $1; print (NR == 1 ? "Columns: " : "Row: ") $0 }')
    if [[ -z "$rows" ]]; then
        echo "The reply had no results" >&2
        return 1
    fi
    echo "$rows"
}
# --8<-- [end:query_database]

# --8<-- [start:execute_explain]
# Plans a query with execute_explain, without running it, and prints the type
# of the first node of the plan. Setting analyze to true would run the query.
execute_explain() {
    local text
    text=$(call_tool execute_explain "$(jq -nc \
        --argjson connection_id "$WORKBENCH_CONNECTION_ID" \
        '{connection_id: $connection_id, query: "SELECT 1 + 1",
          analyze: false}')")
    # The plan follows a line of equals signs.
    local node
    node=$(sed -n '/^=\{10,\}$/{n;p;q;}' <<<"$text" | awk '{ print $1 }')
    if [[ -z "$node" ]]; then
        echo "The reply had no execution plan" >&2
        return 1
    fi
    echo "Plan starts with: $node"
}
# --8<-- [end:execute_explain]

# --8<-- [start:main]
main() {
    initialize
    list_tools
    query_database
    execute_explain
}

main
# --8<-- [end:main]
