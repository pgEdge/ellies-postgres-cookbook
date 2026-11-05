#!/usr/bin/env bash
#
# Ellie's Postgres Cookbook
# Connecting to the pgEdge Postgres MCP Server, using curl and jq.
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

# Posts a JSON-RPC message to the MCP endpoint with a token, and prints the
# reply followed by the HTTP status on a line of its own: post TOKEN BODY.
# The token goes to curl in a header file that bash supplies through a
# pipe, so that it never appears in the arguments of the curl process, which
# other users can read in the process list.
post() {
    curl --silent --show-error \
        --connect-timeout 10 --max-time "$TIMEOUT_SECONDS" \
        --header @<(printf 'Authorization: Bearer %s\n' "$1") \
        --header 'Content-Type: application/json' \
        --write-out '\n%{http_code}' --data-binary "$2" "$MCP_URL/mcp/v1"
}

# Sends a JSON-RPC request and prints its result: rpc METHOD PARAMS_JSON.
# The server answers a JSON-RPC error with HTTP status 200, so the function
# checks the reply for an error member as well as the HTTP status.
rpc() {
    local method="$1" request reply status body
    request=$(jq -nc --arg method "$method" --argjson params "$2" \
        '{jsonrpc: "2.0", id: 1, method: $method, params: $params}')
    reply=$(post "$MCP_TOKEN" "$request") || return 1
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

# --8<-- [start:health]
# Checks that the server is running. The /health endpoint needs no token.
check_health() {
    local body
    body=$(curl --silent --show-error --fail-with-body \
        --connect-timeout 10 --max-time "$TIMEOUT_SECONDS" \
        "$MCP_URL/health") || {
        echo "Health check failed: $body" >&2
        return 1
    }
    jq -er 'if .status == "ok" then "Health: ok"
            else error("status is not ok") end' <<<"$body" 2>/dev/null || {
        echo "Unexpected response: ${body:0:200}" >&2
        return 1
    }
}
# --8<-- [end:health]

# --8<-- [start:initialize]
# Introduces the client to the server, and prints the server's name and
# version and the protocol revision that the server chose. The server
# accepts 2024-11-05, 2025-03-26, 2025-06-18 and 2025-11-25, and answers a
# revision it does not know with one that it does, so the client checks
# the answer. The notifications/initialized message then completes the
# handshake; it is a notification, with no id, so the server replies with
# HTTP 202 and no body.
initialize() {
    local result protocol reply
    result=$(rpc initialize '{
        "protocolVersion": "2025-06-18",
        "capabilities": {},
        "clientInfo": {"name": "cookbook", "version": "1.0.0"}
    }') || return 1
    jq -r '"Server: \(.serverInfo.name) \(.serverInfo.version)"' <<<"$result"
    protocol=$(jq -r '.protocolVersion' <<<"$result")
    if [[ "$protocol" != "2025-06-18" ]]; then
        echo "The server chose protocol version $protocol" >&2
        return 1
    fi
    echo "Protocol version: $protocol"

    reply=$(post "$MCP_TOKEN" \
        '{"jsonrpc": "2.0", "method": "notifications/initialized"}') || return 1
    if [[ "${reply##*$'\n'}" != 202 ]]; then
        echo "notifications/initialized failed: ${reply:0:200}" >&2
        return 1
    fi
}
# --8<-- [end:initialize]

# --8<-- [start:wrong_token]
# Sends a request with a token that the server does not know, and prints
# the HTTP status and the server's message, which is a JSON object with an
# error member rather than a JSON-RPC reply.
wrong_token() {
    local reply status body
    reply=$(post "not-a-real-token" \
        '{"jsonrpc": "2.0", "id": 1, "method": "tools/list", "params": {}}') \
        || return 1
    status="${reply##*$'\n'}"
    body="${reply%$'\n'*}"
    if [[ "$status" != 401 ]]; then
        echo "Expected HTTP 401 for a wrong token, but got $status" >&2
        return 1
    fi
    echo "Wrong token: HTTP $status, $(jq -r '.error // "no message"' <<<"$body")"
}
# --8<-- [end:wrong_token]

# --8<-- [start:main]
main() {
    check_health
    initialize
    wrong_token
}

main
# --8<-- [end:main]
