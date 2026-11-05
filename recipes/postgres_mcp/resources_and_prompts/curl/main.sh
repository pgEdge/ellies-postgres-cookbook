#!/usr/bin/env bash
#
# Ellie's Postgres Cookbook
# Reading resources and prompts from the pgEdge Postgres MCP Server, using
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

# Sends a JSON-RPC request and prints its result: rpc METHOD PARAMS_JSON.
# The server answers a JSON-RPC error with HTTP status 200, so the function
# checks the reply for an error member as well as the HTTP status. The
# token goes to curl in a header file that bash supplies through a pipe,
# so that it never appears in the arguments of the curl process, which
# other users can read in the process list.
rpc() {
    local method="$1" request reply status body
    request=$(jq -nc --arg method "$method" --argjson params "$2" \
        '{jsonrpc: "2.0", id: 1, method: $method, params: $params}')
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
        echo "$method failed with HTTP $status: ${body:0:200}" >&2
        return 1
    fi
    if ! jq -e 'has("result") or has("error")' >/dev/null 2>&1 <<<"$body"; then
        echo "$method failed: unexpected response: ${body:0:200}" >&2
        return 1
    fi
    if jq -e 'has("error")' >/dev/null <<<"$body"; then
        echo "$method failed: $(jq -r '.error.message' <<<"$body")" >&2
        return 1
    fi
    jq -c '.result' <<<"$body"
}
# --8<-- [end:config]

# --8<-- [start:resources]
# Lists the resources that the server offers, and then reads
# pg://system_info, which describes the PostgreSQL server. The contents of
# a resource are text, which for this one holds a JSON object, so the
# script parses the text a second time. version_number is a string such as
# "180006", from which integer division by 10000 gives the major version.
read_system_info() {
    local result
    result=$(rpc resources/list '{}') || return 1
    echo "Resources: $(jq -r '[.resources[].uri] | join(", ")' <<<"$result")"

    result=$(rpc resources/read '{"uri": "pg://system_info"}') || return 1
    jq -r '.contents[0].text | fromjson
           | "PostgreSQL major version: \(.version_number | tonumber / 10000 | floor)",
             "Writes allowed: \(.allow_writes)"' <<<"$result" 2>/dev/null || {
        echo "Unexpected result: ${result:0:200}" >&2
        return 1
    }
}
# --8<-- [end:resources]

# --8<-- [start:prompts]
# Lists the prompts that the server offers, and then fetches
# explore-database, which takes no arguments. A prompt is a set of
# messages, ready to hand to a language model, that guide it through a
# task with the server's tools.
read_prompts() {
    local result
    result=$(rpc prompts/list '{}') || return 1
    echo "Prompts: $(jq -r '[.prompts[].name] | join(", ")' <<<"$result")"

    result=$(rpc prompts/get '{"name": "explore-database", "arguments": {}}') \
        || return 1
    jq -r '"explore-database: \(.description)",
           "First message role: \(.messages[0].role)"' <<<"$result"
}
# --8<-- [end:prompts]

# --8<-- [start:main]
main() {
    read_system_info
    read_prompts
}

main
# --8<-- [end:main]
