#!/usr/bin/env bash
#
# Ellie's Postgres Cookbook
# Handling errors from the pgEdge RAG Server by error code, using curl and
# jq.
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
RAG_PIPELINE="${RAG_PIPELINE:-cookbook}"

# A pipeline name that no server has, to cause PIPELINE_NOT_FOUND.
MISSING_PIPELINE="no-such-pipeline"

# The server rejects both requests before it calls a language model, so
# they answer quickly.
TIMEOUT_SECONDS=30

# Escapes a value for use in a URL path, as the other languages do.
escape() { jq -rn --arg value "$1" '$value | @uri'; }
# --8<-- [end:config]

# --8<-- [start:request]
# Sends a query to a pipeline. On success, the function prints the JSON
# reply. On an error reply, it sets the variables STATUS, CODE, and MESSAGE
# from the HTTP status and the "error" object in the body, and returns 1.
# With --fail-with-body, curl exits non-zero on an HTTP error status but
# still prints the body; --write-out adds the HTTP status after it. When
# the server cannot be reached at all, curl prints status 000 and the
# function exits the program, since there is no reply to branch on. The
# script leaves out --show-error, because it reports each failure itself.
STATUS="" CODE="" MESSAGE=""
send_query() {
    local pipeline="$1" query="$2" output rc=0
    output="$(jq -n --arg query "$query" '{query: $query}' |
        curl --silent --fail-with-body \
            --max-time "$TIMEOUT_SECONDS" \
            --header 'Content-Type: application/json' \
            --data-binary @- \
            --write-out '\n%{http_code}' \
            "$RAG_SERVER_URL/v1/pipelines/$(escape "$pipeline")")" || rc=$?

    STATUS="${output##*$'\n'}"
    local body="${output%$'\n'*}"
    if [[ "$STATUS" == 000 ]]; then
        echo "RAG Server error: could not reach $RAG_SERVER_URL" >&2
        exit 1
    fi
    [[ $rc -eq 0 ]] && { printf '%s\n' "$body"; return 0; }

    # An error reply has the form {"error": {"code": "...", "message": "..."}}.
    CODE="$(jq -r '.error.code // empty' <<<"$body" 2>/dev/null || true)"
    MESSAGE="$(jq -r '.error.message // empty' <<<"$body" 2>/dev/null || true)"
    if [[ -z "$CODE" ]]; then
        echo "RAG Server error: HTTP $STATUS, ${body:0:200}" >&2
        exit 1
    fi
    return 1
}
# --8<-- [end:request]

# --8<-- [start:advise]
# Returns advice for an error, chosen by the error code. Branch on the
# code rather than on the message, which is meant for people and may
# change; branch on the HTTP status only for the temporary failures that
# have no code worth handling individually.
advise() {
    case "$CODE" in
        PIPELINE_NOT_FOUND)
            echo "Check the pipeline name; GET /v1/pipelines lists the pipelines." ;;
        INVALID_REQUEST)
            echo "Fix the request; the body must be JSON with a non-empty query." ;;
        *)
            case "$STATUS" in
                503|504) echo "The failure may be temporary, so retry the request later." ;;
                *)       echo "This program does not handle $CODE." ;;
            esac ;;
    esac
}
# --8<-- [end:advise]

# --8<-- [start:main]
# Sends one query that the server must refuse with the expected error
# code, and prints how the program handles the refusal. A reply with any
# other outcome is a failure.
demonstrate() {
    local title="$1" pipeline="$2" query="$3" expected="$4"

    echo "$title"
    if send_query "$pipeline" "$query" >/dev/null; then
        echo "RAG Server error: the request unexpectedly succeeded" >&2
        return 1
    fi
    echo "  $CODE (HTTP $STATUS): $MESSAGE"
    echo "  $(advise)"
    if [[ "$CODE" != "$expected" ]]; then
        echo "RAG Server error: expected $expected, got $CODE" >&2
        return 1
    fi
}

main() {
    demonstrate "Asking a pipeline that does not exist" \
        "$MISSING_PIPELINE" "Hello" PIPELINE_NOT_FOUND
    demonstrate "Asking an empty question" \
        "$RAG_PIPELINE" "" INVALID_REQUEST
}

main
# --8<-- [end:main]
