#!/usr/bin/env bash
#
# Ellie's Postgres Cookbook
# Holding a conversation with the pgEdge RAG Server, using curl and jq.
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

# The second question makes sense only with the first in front of it,
# because "it" and "then" refer to the first question and its answer.
QUESTIONS=(
    "How long does the Acme Widget 2.0 take to charge?"
    "And how many hours will it then run for?"
)

# The server waits for the language model before it replies, and a small
# model on a modest machine can take a while, so allow plenty of time.
TIMEOUT_SECONDS=300

# Escapes a value for use in a URL path, as the other languages do.
escape() { jq -rn --arg value "$1" '$value | @uri'; }
# --8<-- [end:config]

# --8<-- [start:ask]
# Sends a question and the conversation so far to the pipeline, and prints
# the JSON reply. The server keeps no conversation between requests, so
# the second argument is a JSON array of the earlier messages, each with a
# role of user or assistant, in order. With --fail-with-body, curl exits
# non-zero on an HTTP error status but still prints the body, which
# carries the server's explanation.
ask() {
    jq -n --arg query "$1" --argjson messages "$2" \
        '{query: $query, messages: $messages}' |
        curl --silent --show-error --fail-with-body \
            --max-time "$TIMEOUT_SECONDS" \
            --header 'Content-Type: application/json' \
            --data-binary @- \
            "$RAG_SERVER_URL/v1/pipelines/$(escape "$RAG_PIPELINE")"
}
# --8<-- [end:ask]

# --8<-- [start:converse]
# Asks each question in turn, printing both sides of the conversation. After
# each answer, the question and the answer join the history that the next
# request carries.
converse() {
    local history='[]' question response answer

    for question in "${QUESTIONS[@]}"; do
        if ! response="$(ask "$question" "$history")"; then
            echo "RAG Server error: $response" >&2
            return 1
        fi

        # The error call makes jq fail when the answer is missing or is not
        # a string, since interpolating null would print the word "null".
        if ! answer="$(jq -er 'if (.answer | type) == "string"
                               then .answer
                               else error("missing answer") end' \
                          <<<"$response")"; then
            echo "Unexpected response: $response" >&2
            return 1
        fi

        echo "You: $question"
        echo "Assistant: $answer"

        history="$(jq -c --arg question "$question" --arg answer "$answer" \
            '. + [{role: "user", content: $question},
                  {role: "assistant", content: $answer}]' <<<"$history")"
    done
}
# --8<-- [end:converse]

# --8<-- [start:main]
main() {
    converse
}

main
# --8<-- [end:main]
