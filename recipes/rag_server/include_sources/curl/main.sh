#!/usr/bin/env bash
#
# Ellie's Postgres Cookbook
# Showing the sources of an answer from the pgEdge RAG Server, using curl
# and jq.
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

QUESTION="How long does the Acme Widget 2.0 take to charge?"

# The server waits for the language model before it replies, and a small
# model on a modest machine can take a while, so allow plenty of time.
TIMEOUT_SECONDS=300

# Escapes a value for use in a URL path, as the other languages do.
escape() { jq -rn --arg value "$1" '$value | @uri'; }
# --8<-- [end:config]

# --8<-- [start:ask]
# Sends the question to the pipeline, asks for the documents that the
# answer came from, and prints the JSON reply. jq builds the request body,
# which escapes the question correctly. With --fail-with-body, curl exits
# non-zero on an HTTP error status but still prints the body, which
# carries the server's explanation.
ask() {
    jq -n --arg query "$1" '{query: $query, include_sources: true}' |
        curl --silent --show-error --fail-with-body \
            --max-time "$TIMEOUT_SECONDS" \
            --header 'Content-Type: application/json' \
            --data-binary @- \
            "$RAG_SERVER_URL/v1/pipelines/$(escape "$RAG_PIPELINE")"
}
# --8<-- [end:ask]

# --8<-- [start:sources]
# Prints the sources in a reply, in the order that the server returns
# them, as the ID of each document and the start of its text. The server
# leaves out the sources array, without an error, when the pipeline does
# not set allow_include_sources.
print_sources() {
    jq -r '
        if .sources != null and (.sources | type) != "array" then
            error("sources is not an array")
        elif (.sources // []) | length == 0 then
            "No sources were returned. Does the pipeline set allow_include_sources?"
        else
            "Sources (\(.sources | length)):",
            (.sources[]
             | (.content // "" | gsub("\\s+"; " ")) as $text
             | "- \(.id // "(no id)"): \(if ($text | length) > 60
                                          then $text[:57] + "..."
                                          else $text end)")
        end'
}
# --8<-- [end:sources]

# --8<-- [start:main]
main() {
    local response
    if ! response="$(ask "$QUESTION")"; then
        echo "RAG Server error: $response" >&2
        exit 1
    fi

    echo "Question: $QUESTION"
    # The error call makes jq fail when the answer is missing or is not a
    # string, since interpolating null would print the word "null".
    jq -er 'if (.answer | type) == "string"
            then "Answer:\n\(.answer)"
            else error("missing answer") end' <<<"$response" || {
        echo "Unexpected response: $response" >&2
        exit 1
    }
    print_sources <<<"$response"
}

main
# --8<-- [end:main]
