#!/usr/bin/env bash
#
# Ellie's Postgres Cookbook
# Streaming an answer from the pgEdge RAG Server, using curl and jq.
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

# The server may wait for the language model before the first chunk
# arrives, and a small model on a modest machine can take a while, so
# allow plenty of time for the whole stream.
TIMEOUT_SECONDS=300
# --8<-- [end:config]

# --8<-- [start:request]
# Sends the question with streaming switched on, and prints the Server-Sent
# Events as they arrive. --no-buffer stops curl from holding the output
# back, and --fail-with-body makes curl exit non-zero on an HTTP error
# status while still printing the body, which carries the explanation.
request_stream() {
    jq -n --arg query "$1" '{query: $query, stream: true}' |
        curl --silent --show-error --fail-with-body --no-buffer \
            --max-time "$TIMEOUT_SECONDS" \
            --header 'Content-Type: application/json' \
            --data-binary @- \
            "$RAG_SERVER_URL/v1/pipelines/$RAG_PIPELINE"
}
# --8<-- [end:request]

# --8<-- [start:events]
# Reads Server-Sent Events from standard input, prints the content of each
# chunk event as it arrives, and returns non-zero if the stream reports an
# error or ends without a done event. Each event is a "data:" line holding
# a JSON object. The read loop also handles a final line that has no
# newline.
read_events() {
    local line data kind chunks=0 error="" other="" done=false

    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        if [[ "$line" != data:* ]]; then
            # Blank lines separate events, and comment lines start with a
            # colon. Anything else is not an event, such as the JSON body
            # of an HTTP error, so keep it for the error message.
            [[ -z "$line" || "$line" == :* ]] || other+="$line"
            continue
        fi

        data="${line#data:}"
        data="${data# }"
        kind="$(jq -r '.type' <<<"$data")"
        case "$kind" in
            chunk)
                # The last chunk has no content. The -j option prints
                # without a trailing newline.
                if [[ "$(jq -r '.content // ""' <<<"$data")" != "" ]]; then
                    jq -j '.content' <<<"$data"
                    chunks=$((chunks + 1))
                fi
                ;;
            error) error="$(jq -r '.error // "unknown error"' <<<"$data")" ;;
            done)  done=true ;;
        esac
    done
    echo

    # The server sends a done event after an error event, so keep reading
    # until the stream ends before reporting the error.
    if [[ -n "$error" ]]; then
        echo "The stream reported an error: $error" >&2
        return 1
    fi
    if [[ "$done" != true ]]; then
        echo "The stream ended before the done event${other:+: $other}" >&2
        return 1
    fi
    echo "Chunks received: $chunks"
}
# --8<-- [end:events]

# --8<-- [start:main]
main() {
    echo "Question: $QUESTION"
    echo "Answer:"
    # With pipefail, the pipeline fails if curl fails or the stream
    # reports an error.
    request_stream "$QUESTION" | read_events || {
        echo "RAG Server error: the request failed" >&2
        exit 1
    }
}

main
# --8<-- [end:main]
