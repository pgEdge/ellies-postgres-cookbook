#!/usr/bin/env bash
#
# Ellie's Postgres Cookbook
# Finding the task that created a pgEdge Control Plane database, and
# following its log until the task finishes, using curl and jq.
#
# These examples are for the Control Plane v0.11.0.
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
CONTROL_PLANE_URL="${CONTROL_PLANE_URL:-http://localhost:3000}"
CONTROL_PLANE_URL="${CONTROL_PLANE_URL%/}"
DATABASE_ID="${CONTROL_PLANE_DATABASE_ID:-cookbook}"

TIMEOUT_SECONDS=30

# How long to follow a task that is still running, and how often to check.
FOLLOW_SECONDS=600
POLL_SECONDS=5

# Fetches a path from the server and prints the JSON reply. With
# --fail-with-body, curl exits non-zero on an HTTP error status but still
# prints the body, which carries the server's explanation.
get() {
    curl --silent --show-error --fail-with-body \
        --max-time "$TIMEOUT_SECONDS" "$CONTROL_PLANE_URL$1"
}
# --8<-- [end:config]

# --8<-- [start:list]
# Prints the ID of the task that created the database. Every create,
# update and delete runs as a task. The IDs sort by creation time, and
# sort_order=asc lists the oldest task first.
find_create_task() {
    local response
    response="$(get "/v1/databases/$DATABASE_ID/tasks?sort_order=asc")" || {
        echo "Control Plane error: $response" >&2
        return 1
    }
    jq -er 'first(.tasks[] | select(.type == "create")) | .task_id' \
        <<<"$response" || {
        echo "Control Plane error: no create task for $DATABASE_ID" >&2
        return 1
    }
}
# --8<-- [end:list]

# --8<-- [start:follow]
# Prints the log of a task as it grows, until the task finishes, and then
# prints its final status. Each log reply carries last_entry_id, and
# passing that back as after_entry_id fetches only the newer entries. The
# status is read before the log, so that once it is final, the log that
# follows it is complete.
follow_task() {
    local task_id="$1" path="/v1/databases/$DATABASE_ID/tasks/$1"
    local deadline=$((SECONDS + FOLLOW_SECONDS)) after="" task status log

    while true; do
        task="$(get "$path")" || {
            echo "Control Plane error: $task" >&2
            return 1
        }
        status="$(jq -er '.status' <<<"$task")"

        log="$(get "$path/log${after:+?after_entry_id=$after}")" || {
            echo "Control Plane error: $log" >&2
            return 1
        }
        jq -r '.entries[] | "Log: \(.message)"' <<<"$log"
        after="$(jq -r '.last_entry_id // empty' <<<"$log")"

        case "$status" in
            completed|failed|canceled) break ;;
        esac
        if ((SECONDS >= deadline)); then
            echo "Error: task $task_id was still $status after $FOLLOW_SECONDS seconds" >&2
            return 1
        fi
        sleep "$POLL_SECONDS"
    done

    echo "Status: $status"
    [[ "$status" == "completed" ]]
}
# --8<-- [end:follow]

# --8<-- [start:main]
main() {
    local task_id
    task_id="$(find_create_task)" || exit 1
    echo "Task: create"
    follow_task "$task_id" || exit 1
}

main
# --8<-- [end:main]
