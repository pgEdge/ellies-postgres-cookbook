#!/usr/bin/env bash
#
# Ellie's Postgres Cookbook
# Chatting with the LLM through the AI DBA Workbench API, using curl and jq.
#
# Copyright (c) 2026, pgEdge, Inc.
# This code is released under the PostgreSQL License.

# --8<-- [start:imports]
# Stop at the first failing command, treat an unset variable as an error,
# and fail a pipeline when any command in it fails.
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
WORKBENCH_URL="${WORKBENCH_URL:-http://localhost:8080}"
WORKBENCH_URL="${WORKBENCH_URL%/}"
: "${WORKBENCH_TOKEN:?WORKBENCH_TOKEN must be set}"
# --8<-- [end:config]

# --8<-- [start:request]
# Sends an authenticated request and prints the JSON reply:
# api METHOD PATH [curl options]. With --fail-with-body, a request that the
# server rejects leaves the server's error message in the reply, and the
# function prints it to standard error.
# The token goes to curl in a header file that bash supplies through a pipe,
# so that it never appears in the arguments of the curl process, which other
# users can read in the process list.
api() {
    local method="$1" path="$2"
    shift 2
    local response
    response=$(curl --silent --show-error --fail-with-body \
        --connect-timeout 10 --max-time 300 \
        --request "$method" \
        --header @<(printf 'Authorization: Bearer %s\n' "$WORKBENCH_TOKEN") \
        "$@" "$WORKBENCH_URL/api/v1$path") || {
        echo "$method $path failed: $response" >&2
        return 1
    }
    printf '%s' "$response"
}
# --8<-- [end:request]

# --8<-- [start:providers]
# Prints the default provider and model, which the chat endpoint uses when a
# request names neither.
show_provider() {
    local providers
    providers=$(api GET /llm/providers)
    jq -r '"Provider: \(.providers[] | select(.isDefault) | .name) " +
           "(model \(.defaultModel))"' <<<"$providers"
}
# --8<-- [end:providers]

# --8<-- [start:chat]
# Sends a conversation to the model and prints the reply as JSON. The
# argument is the conversation so far, as a JSON array of messages.
chat() {
    local messages="$1"
    jq -n --argjson messages "$messages" '{messages: $messages}' |
        api POST /llm/chat \
            --header 'Content-Type: application/json' --data @-
}

# Prints the text of a reply on a single line. A small model may spread its
# answer over several lines, so the function joins the text blocks and
# collapses the white space, and it fails when the reply holds no text.
reply_text() {
    local text
    text=$(jq -r '[.content[] | select(.type == "text") | .text] | join(" ")' \
        <<<"$1" | tr -s '[:space:]' ' ' | sed 's/^ //; s/ $//')
    if [[ -z "$text" ]]; then
        echo "The model returned no text" >&2
        return 1
    fi
    printf '%s\n' "$text"
}
# --8<-- [end:chat]

# --8<-- [start:main]
main() {
    local first second question text

    show_provider

    # The first message starts the conversation.
    question="Name one type of PostgreSQL index, in one sentence."
    first=$(chat "$(jq -nc --arg q "$question" \
        '[{role: "user", content: $q}]')")
    text=$(reply_text "$first")
    echo "Reply: $text"

    # The server keeps no conversation, so the follow-up repeats the earlier
    # messages, including the model's reply, and adds the new question.
    second=$(chat "$(jq -nc --arg q "$question" --arg a "$text" \
        '[{role: "user", content: $q},
          {role: "assistant", content: $a},
          {role: "user", content: "Summarise your answer in five words."}]')")
    text=$(reply_text "$second")
    echo "Follow-up reply: $text"
    echo "Stop reason: $(jq -r '.stop_reason' <<<"$second")"
}

main
# --8<-- [end:main]
