#!/usr/bin/env bash
#
# Ellie's Postgres Cookbook
# Filtering the documents that the pgEdge RAG Server retrieves, using curl
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

QUESTION="How long does the Acme Widget take to charge?"

# The product to search, and the versions to ask about in turn. The
# question names no version, so only the filter tells the pipeline which
# documents to use.
PRODUCT="Acme Widget"
VERSIONS=("1.0" "2.0")

# The server waits for the language model before it replies, and a small
# model on a modest machine can take a while, so allow plenty of time.
TIMEOUT_SECONDS=300

# Escapes a value for use in a URL path, as the other languages do.
escape() { jq -rn --arg value "$1" '$value | @uri'; }
# --8<-- [end:config]

# --8<-- [start:filter]
# Prints the filter for a product and a version as JSON. The conditions
# are joined with AND, which is the default, and each one compares a
# column of the pipeline's table with a value. The server passes the
# values to PostgreSQL as parameters, so they need no escaping.
build_filter() {
    jq -n --arg product "$1" --arg version "$2" '{
        logic: "AND",
        conditions: [
            {column: "product", operator: "=", value: $product},
            {column: "version", operator: "=", value: $version}
        ]}'
}
# --8<-- [end:filter]

# --8<-- [start:ask]
# Sends the question and the filter to the pipeline, asks for the documents
# that the answer came from, and prints the JSON reply. With
# --fail-with-body, curl exits non-zero on an HTTP error status but still
# prints the body, which carries the server's explanation.
ask() {
    jq -n --arg query "$QUESTION" --argjson filter "$1" \
        '{query: $query, filter: $filter, include_sources: true}' |
        curl --silent --show-error --fail-with-body \
            --max-time "$TIMEOUT_SECONDS" \
            --header 'Content-Type: application/json' \
            --data-binary @- \
            "$RAG_SERVER_URL/v1/pipelines/$(escape "$RAG_PIPELINE")"
}
# --8<-- [end:ask]

# --8<-- [start:show]
# Prints the answer in a reply, and then the IDs of its sources. The error
# call makes jq fail when the answer is missing or is not a string, since
# interpolating null would print the word "null".
show() {
    jq -er 'if (.answer | type) == "string"
            then "Answer:\n\(.answer)"
            else error("missing answer") end,
            "Sources: \((.sources // []) | map(.id // "(no id)") | join(", "))"'
}
# --8<-- [end:show]

# --8<-- [start:main]
main() {
    local version response

    echo "Question: $QUESTION"
    for version in "${VERSIONS[@]}"; do
        echo
        echo "Filter: product = $PRODUCT, version = $version"
        if ! response="$(ask "$(build_filter "$PRODUCT" "$version")")"; then
            echo "RAG Server error: $response" >&2
            exit 1
        fi
        show <<<"$response" || {
            echo "Unexpected response: $response" >&2
            exit 1
        }
    done
}

main
# --8<-- [end:main]
