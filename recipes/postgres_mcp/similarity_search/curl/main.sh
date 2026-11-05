#!/usr/bin/env bash
#
# Ellie's Postgres Cookbook
# Searching by meaning through the pgEdge Postgres MCP Server, using curl
# and jq.
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

# The server turns the query into an embedding before it searches, which
# can take a while if the embedding model has to load first, so the
# timeout is longer than in the other recipes.
TIMEOUT_SECONDS=90

QUERY="a gift for an amateur astronomer"

# Calls a tool with tools/call and prints the text of its reply:
# call_tool NAME ARGUMENTS_JSON. The server answers a JSON-RPC error with
# HTTP status 200, and a tool that fails returns a normal result with
# isError set, so the function checks for both as well as the HTTP status.
# The token goes to curl in a header file that bash supplies through a
# pipe, so that it never appears in the arguments of the curl process,
# which other users can read in the process list.
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
    if ! jq -e 'has("result") or has("error")' >/dev/null 2>&1 <<<"$body"; then
        echo "$name failed: unexpected response: ${body:0:200}" >&2
        return 1
    fi
    if jq -e 'has("error")' >/dev/null <<<"$body"; then
        echo "$name failed: $(jq -r '.error.message' <<<"$body")" >&2
        return 1
    fi
    if jq -e '.result.isError == true' >/dev/null <<<"$body"; then
        echo "$name failed: $(jq -r '.result.content[0].text' <<<"$body")" >&2
        return 1
    fi
    jq -r '.result.content[0].text' <<<"$body"
}
# --8<-- [end:config]

# --8<-- [start:search]
# Searches the product descriptions for the query, and prints the number
# of results and the name of the product that matches it most closely.
# similarity_search finds the closest rows by vector distance, and then
# reorders them, mixing in a keyword score and favouring variety, so the
# first result in the reply is not always the closest. Each result has a
# line such as "Source: cookbook_mcp.products.description (vector search
# rank: #1, chunk: 1)"; the script picks the result ranked first by the
# vector search, whose text follows the first blank line after it. Every
# description starts with the product's name and a colon.
search() {
    local text best
    text=$(call_tool similarity_search "$(jq -nc --arg query "$QUERY" '{
        table_name: "cookbook_mcp.products",
        query_text: $query,
        top_n: 3
    }')") || return 1
    echo "Query: $QUERY"
    echo "Results: $(grep -cE '^Result [0-9]+/[0-9]+$' <<<"$text" || true)"
    best=$(awk '
        /^Source: .*\(vector search rank: #1, chunk: 1\)$/ { found = 1; next }
        found && $0 == "" { blank = 1; next }
        found && blank { print; exit }' <<<"$text")
    if [[ "$best" != *": "* ]]; then
        echo "The reply had no closest match: ${text:0:200}" >&2
        return 1
    fi
    echo "Best match: ${best%%: *}"
}
# --8<-- [end:search]

# --8<-- [start:main]
main() {
    search
}

main
# --8<-- [end:main]
