#!/usr/bin/env bash
#
# Ellie's Postgres Cookbook
# Checking the health of the pgEdge RAG Server and listing its pipelines,
# using curl and jq.
#
# These examples are for pgEdge RAG Server 2.0.0.
#
# Copyright (c) 2026, pgEdge, Inc.
# This code is released under the PostgreSQL License.

# --8<-- [start:imports]
# Stop at the first failed command or unset variable, and treat a failure
# anywhere in a pipeline as a failure of the whole pipeline.
set -euo pipefail

for tool in curl jq; do
    command -v "$tool" >/dev/null || { echo "$tool is required" >&2; exit 1; }
done
# --8<-- [end:imports]

# --8<-- [start:config]
# The :- operator treats an empty variable as unset.
RAG_SERVER_URL="${RAG_SERVER_URL:-http://localhost:8080}"
RAG_SERVER_URL="${RAG_SERVER_URL%/}"

# None of these endpoints calls a language model, but the health check
# contacts each provider, so allow it some time.
TIMEOUT_SECONDS=30

# Fetches a path from the server and prints the JSON reply. With
# --fail-with-body, curl exits non-zero on an HTTP error status but still
# prints the body, which carries the server's explanation.
get() {
    curl --silent --show-error --fail-with-body \
        --max-time "$TIMEOUT_SECONDS" "$RAG_SERVER_URL$1"
}
# --8<-- [end:config]

# --8<-- [start:live]
# Checks that the server process is running. The /v1/live endpoint is
# cheap and calls nothing else, so it suits a frequent liveness probe. The
# error call makes jq fail unless the status is the string "ok".
check_live() {
    local response
    response="$(get /v1/live)" || {
        echo "RAG Server error: $response" >&2
        return 1
    }
    jq -er 'if .status == "ok" then "Live: ok"
            else error("status is not ok") end' <<<"$response" || {
        echo "Unexpected response: $response" >&2
        return 1
    }
}
# --8<-- [end:live]

# --8<-- [start:health]
# Checks whether each pipeline can reach its language model providers.
# The /v1/health endpoint answers with HTTP 200 even when a provider is
# down, so curl succeeds either way; the status field is "healthy" or
# "degraded". This function prints the report, returns 1 when a request
# or reply fails, and returns 2 when the status is anything but "healthy".
check_health() {
    local response
    response="$(get /v1/health)" || {
        echo "RAG Server error: $response" >&2
        return 1
    }
    jq -er '
        def provider:
            if .reachable then "reachable"
            else "unreachable (\(.error // "unknown"))" end;

        if (.status | type) != "string" then error("missing status") else
            "Health: \(.status)",
            ((.pipelines // [])[]
             | "- \(.name): embedding \(.embedding | provider), "
               + "completion \(.completion | provider)")
        end' <<<"$response" || {
        echo "Unexpected response: $response" >&2
        return 1
    }
    [[ "$(jq -r '.status' <<<"$response")" == "healthy" ]] || {
        echo "RAG Server is not healthy" >&2
        return 2
    }
}
# --8<-- [end:health]

# --8<-- [start:pipelines]
# Lists the pipelines that the server offers, with their descriptions.
list_pipelines() {
    local response
    response="$(get /v1/pipelines)" || {
        echo "RAG Server error: $response" >&2
        return 1
    }
    jq -er '
        if (.pipelines | type) != "array" then error("missing pipelines") else
            "Pipelines (\(.pipelines | length)):",
            (.pipelines[] | "- \(.name): \(.description // "(no description)")")
        end' <<<"$response" || {
        echo "Unexpected response: $response" >&2
        return 1
    }
}
# --8<-- [end:pipelines]

# --8<-- [start:main]
main() {
    local status=0 result=0

    # Stop at the first request that fails, as the other examples do. A
    # degraded server still answers every request, so carry on and list the
    # pipelines, and then exit non-zero.
    check_live || exit 1
    check_health || result=$?
    if [[ "$result" -eq 2 ]]; then
        status=1
    elif [[ "$result" -ne 0 ]]; then
        exit 1
    fi
    list_pipelines || exit 1
    exit "$status"
}

main
# --8<-- [end:main]
