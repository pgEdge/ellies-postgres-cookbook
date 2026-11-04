#!/usr/bin/env bash
#
# Ellie's Postgres Cookbook
# Limiting the answers of the pgEdge RAG Server to each caller's own rows,
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
RAG_PIPELINE="${RAG_PIPELINE:-cookbook_private}"

QUESTION="What is the status of my warranty claim?"

# The callers to ask for. The fictional documents in the pipeline's table
# belong to these two people.
CALLERS=("jane.doe@example.com" "john.smith@example.com")

# The header in which the server expects a trusted proxy to put the claims
# of the caller. This is the server's default; the identity.claims_header
# setting changes it.
CLAIMS_HEADER="X-Forwarded-Claims"

# The server waits for the language model before it replies, and a small
# model on a modest machine can take a while, so allow plenty of time.
TIMEOUT_SECONDS=300

# Escapes a value for use in a URL path, as the other languages do.
escape() { jq -rn --arg value "$1" '$value | @uri'; }
# --8<-- [end:config]

# --8<-- [start:ask]
# Sends the question to the pipeline on behalf of a caller, and asks for
# the documents that the answer came from. The argument is the caller's
# subject, or an empty string to send no identity. The function sets
# STATUS to the HTTP status and BODY to the reply, and returns 1 when the
# status is an error. The claims are a JSON object, which jq builds, so
# that the subject needs no escaping. With --fail-with-body, curl exits
# non-zero on an HTTP error status but still prints the body; --write-out
# adds the HTTP status after it. The script leaves out --show-error,
# because it reports each failure itself.
STATUS="" BODY=""
ask() {
    local subject="$1" output rc=0 headers=()
    if [[ -n "$subject" ]]; then
        headers=(--header "$CLAIMS_HEADER: $(jq -cn --arg sub "$subject" '{sub: $sub}')")
    fi

    output="$(jq -n --arg query "$QUESTION" '{query: $query, include_sources: true}' |
        curl --silent --fail-with-body \
            --max-time "$TIMEOUT_SECONDS" \
            --header 'Content-Type: application/json' \
            ${headers[@]+"${headers[@]}"} \
            --data-binary @- \
            --write-out '\n%{http_code}' \
            "$RAG_SERVER_URL/v1/pipelines/$(escape "$RAG_PIPELINE")")" || rc=$?

    STATUS="${output##*$'\n'}"
    BODY="${output%$'\n'*}"
    if [[ "$STATUS" == 000 ]]; then
        echo "RAG Server error: could not reach $RAG_SERVER_URL" >&2
        exit 1
    fi
    return "$rc"
}
# --8<-- [end:ask]

# --8<-- [start:show]
# Prints the answer in the reply, and then the IDs of its sources. The
# error call makes jq fail when the answer is missing or is not a string,
# since interpolating null would print the word "null".
show() {
    jq -er 'if (.answer | type) == "string"
            then "Answer:\n\(.answer)"
            else error("missing answer") end,
            "Sources: \((.sources // []) | map(.id // "(no id)") | join(", "))"'
}
# --8<-- [end:show]

# --8<-- [start:main]
# Asks the question as a caller who has an identity, and prints what that
# caller may see.
ask_as() {
    echo
    echo "Caller: $1"
    if ! ask "$1"; then
        echo "RAG Server error: HTTP $STATUS, ${BODY:0:200}" >&2
        return 1
    fi
    show <<<"$BODY" || {
        echo "Unexpected response: ${BODY:0:200}" >&2
        return 1
    }
}

# Asks the question without an identity. The server must refuse with
# IDENTITY_REQUIRED, because it never falls back to the pipeline's own
# database role; any other outcome is a failure.
ask_anonymously() {
    local code

    echo
    echo "Caller: (no identity)"
    if ask ""; then
        echo "RAG Server error: the server answered without an identity;" \
             "is identity.enabled set?" >&2
        return 1
    fi
    code="$(jq -r '.error.code // empty' <<<"$BODY" 2>/dev/null || true)"
    echo "$code (HTTP $STATUS)"
    if [[ "$code" != IDENTITY_REQUIRED ]]; then
        echo "RAG Server error: expected IDENTITY_REQUIRED, got HTTP $STATUS:" \
             "${BODY:0:200}" >&2
        return 1
    fi
}

main() {
    local caller

    echo "Question: $QUESTION"
    for caller in "${CALLERS[@]}"; do
        ask_as "$caller"
    done
    ask_anonymously
}

main
# --8<-- [end:main]
