#!/usr/bin/env bash
#
# Ellie's Postgres Cookbook
# Running read-only queries through the pgEdge Postgres MCP Server, using
# curl and jq.
#
# These examples are for pgEdge Postgres MCP Server 1.1.0.
#
# Copyright (c) 2026, pgEdge, Inc.
# This code is released under the PostgreSQL License.

# --8<-- [start:imports]
# Stop at the first failed command or unset variable, and treat a failure
# anywhere in a pipeline as a failure of the whole pipeline.
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
MCP_URL="${MCP_URL:-http://localhost:8080}"
MCP_URL="${MCP_URL%/}"
: "${MCP_TOKEN:?MCP_TOKEN must be set}"

TIMEOUT_SECONDS=30

# Calls a tool with tools/call and prints its result, which holds the text
# of the reply in content[0].text and, if the tool failed, isError set to
# true: call_tool NAME ARGUMENTS_JSON. The server answers a JSON-RPC error
# with HTTP status 200, so the function checks the reply for an error
# member as well as the HTTP status. The token goes to curl in a header
# file that bash supplies through a pipe, so that it never appears in the
# arguments of the curl process, which other users can read in the process
# list.
call_tool() {
    local name="$1" request reply status body
    request=$(jq -nc --arg name "$name" --argjson arguments "$2" \
        '{jsonrpc: "2.0", id: 1, method: "tools/call",
          params: {name: $name, arguments: $arguments}}')
    reply=$(curl --silent --show-error \
        --connect-timeout 10 --max-time "$TIMEOUT_SECONDS" \
        --header @<(printf 'Authorization: Bearer %s\n' "$MCP_TOKEN") \
        --header 'Content-Type: application/json' \
        --write-out '\n%{http_code}' --data-binary "$request" \
        "$MCP_URL/mcp/v1") || return 1
    # --write-out puts the HTTP status on a line of its own at the end.
    status="${reply##*$'\n'}"
    body="${reply%$'\n'*}"
    if [[ "$status" != 200 ]]; then
        echo "$name failed with HTTP $status: ${body:0:200}" >&2
        return 1
    fi
    if ! jq -e '.result.content[0].text or has("error")' >/dev/null 2>&1 \
        <<<"$body"; then
        echo "$name failed: unexpected response: ${body:0:200}" >&2
        return 1
    fi
    if jq -e 'has("error")' >/dev/null <<<"$body"; then
        echo "$name failed: $(jq -r '.error.message' <<<"$body")" >&2
        return 1
    fi
    jq -c '.result' <<<"$body"
}
# --8<-- [end:config]

# --8<-- [start:select]
# Runs a SELECT with query_database, and prints the column names and each
# row. The reply repeats the query, with the LIMIT that the server adds,
# and then has a line such as "Results (3 rows):", a header line, and one
# line for each row, with the values separated by tabs. The server writes
# a tab or a newline inside a value as \t or \n, and a NULL as an empty
# string.
select_cheap_products() {
    local query result
    query="SELECT name, price FROM cookbook_mcp.products
           WHERE price < 100 ORDER BY price"
    result=$(call_tool query_database \
        "$(jq -nc --arg query "$query" '{query: $query}')") || return 1
    if jq -e '.isError == true' >/dev/null <<<"$result"; then
        echo "query_database failed: $(jq -r '.content[0].text' <<<"$result")" >&2
        return 1
    fi
    jq -r '
        .content[0].text | split("\n") as $lines
        | ($lines | map(startswith("Results ")) | index(true)) as $start
        | if $start == null or $start + 1 >= ($lines | length)
          then error("The reply had no results") else . end
        | "Columns: \($lines[$start + 1] | split("\t") | join(", "))",
          ($lines[$start + 2:][] | select(. != "")
           | "Row: \(split("\t") | join(", "))")' <<<"$result" || {
        echo "Unexpected reply: $(jq -r '.content[0].text' <<<"$result" | head -c 200)" >&2
        return 1
    }
}
# --8<-- [end:select]

# --8<-- [start:insert]
# Tries to add a row. query_database runs every query in a read-only
# transaction, so PostgreSQL itself refuses the INSERT, and the tool
# returns the error with isError set to true. The script fails if the
# server accepts the write.
try_insert() {
    local query result
    query="INSERT INTO cookbook_mcp.products
               (name, category, price, in_stock, description)
           VALUES ('Acme Test Widget', 'Testing', 1.00, true,
                   'A made-up product that is never saved')"
    result=$(call_tool query_database \
        "$(jq -nc --arg query "$query" '{query: $query}')") || return 1
    if ! jq -e '.isError == true' >/dev/null <<<"$result"; then
        echo "The server accepted a write" >&2
        return 1
    fi
    echo "INSERT rejected: $(jq -r '.content[0].text' <<<"$result")"
}
# --8<-- [end:insert]

# --8<-- [start:main]
main() {
    select_cheap_products
    try_insert
}

main
# --8<-- [end:main]
