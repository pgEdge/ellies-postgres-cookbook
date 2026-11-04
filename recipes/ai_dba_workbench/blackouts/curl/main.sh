#!/usr/bin/env bash
#
# Ellie's Postgres Cookbook
# Scheduling a maintenance blackout with the AI DBA Workbench API, using curl
# and jq.
#
# Copyright (c) 2026, pgEdge, Inc.
# This code is released under the PostgreSQL License.

# --8<-- [start:imports]
# Stop at the first failing command, treat an unset variable as an error,
# and fail a pipeline when any command in it fails.
set -euo pipefail

# The script needs curl to make the requests and jq to build the request and
# read the replies.
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
: "${WORKBENCH_CONNECTION_ID:?WORKBENCH_CONNECTION_ID must be set}"
# --8<-- [end:config]

# --8<-- [start:request]
# Sends an authenticated request and prints the JSON reply:
# api METHOD PATH [curl options]. With --fail-with-body, a request that the
# server rejects leaves the server's error message in the reply, and the
# function prints it to standard error. A caller can set allow_status to an
# HTTP status that the function should treat as success.
# The token goes to curl in a header file that bash supplies through a pipe,
# so that it never appears in the arguments of the curl process, which other
# users can read in the process list.
api() {
    local method="$1" path="$2"
    shift 2
    local output status response
    # With allow_status, curl stays quiet about the status that is allowed.
    local show_error=--show-error
    [[ -z "${allow_status:-}" ]] || show_error=--silent
    # The --write-out option appends the HTTP status on a line of its own.
    output=$(curl --silent "$show_error" --fail-with-body \
        --connect-timeout 10 --max-time 30 \
        --write-out '\n%{http_code}' \
        --request "$method" \
        --header @<(printf 'Authorization: Bearer %s\n' "$WORKBENCH_TOKEN") \
        "$@" "$WORKBENCH_URL/api/v1$path") && status=0 || status=$?
    response="${output%$'\n'*}"
    if [[ "$status" -ne 0 ]]; then
        if [[ -n "${allow_status:-}" && "${output##*$'\n'}" == "$allow_status" ]]
        then
            return 0
        fi
        echo "$method $path failed: ${response:-no reply (curl $status)}" >&2
        return 1
    fi
    printf '%s' "$response"
}
# --8<-- [end:request]

# --8<-- [start:create]
# Creates a blackout for one monitored server and prints the reply. The
# reason ends with the unique marker, so that the cleanup can find the
# blackout even if this script never sees the reply. The blackout starts a
# minute ago, so that a small difference between the clocks of this machine and
# the server cannot leave it inactive, and it ends in one hour. The times are
# in RFC 3339 format, which jq builds from the current time.
create_blackout() {
    local connection_id="$1" marker="$2"
    jq -n --argjson connection_id "$connection_id" --arg marker "$marker" \
        '{scope: "server", connection_id: $connection_id,
          reason: ("Cookbook maintenance window " + $marker),
          start_time: (now - 60 | todate),
          end_time: (now + 3600 | todate)}' |
        api POST /blackouts \
            --header 'Content-Type: application/json' --data @-
}
# --8<-- [end:create]

# --8<-- [start:read]
# Prints the blackout with the given ID.
get_blackout() {
    api GET "/blackouts/$1"
}
# --8<-- [end:read]

# --8<-- [start:stop]
# Stops a blackout that is in progress, which sets its end time to now, and
# prints the stopped blackout.
stop_blackout() {
    api POST "/blackouts/$1/stop"
}
# --8<-- [end:stop]

# --8<-- [start:delete]
# Deletes a blackout by its ID. A 404 status means that the blackout is
# already gone, which is what the caller wanted, so it counts as success.
delete_blackout() {
    allow_status=404 api DELETE "/blackouts/$1" >/dev/null
}
# --8<-- [end:delete]

# --8<-- [start:main]
# Prints the IDs of the blackouts whose reason contains the marker.
find_blackouts() {
    api GET /blackouts |
        jq -r --arg marker "$1" \
            '.blackouts[] | select(.reason | contains($marker)) | .id'
}

# These variables are global, because the EXIT trap runs after main returns.
# The marker is set before the create call and cleared once the blackout is
# deleted, so a non-empty marker means that the outcome of the create call is
# unknown, or that its blackout still exists. The created variable holds the
# reply to the create call, which bash assigns before it runs a signal
# handler, whereas it would not yet have extracted the ID from the reply.
marker=""
created=""

cleanup() {
    local status=$?
    # Ignore further signals, so that a second one cannot abort the delete.
    trap '' INT TERM
    # Delete the blackout when the script ends, even if a later step failed,
    # so that a failed run does not leave alerts suppressed. Report a delete
    # that fails, and make the exit status non-zero.
    local id ids=""
    if [[ -n "$created" ]]; then
        ids=$(jq -er '.id' <<<"$created") || ids=""
    fi
    if [[ -z "$ids" && -n "$marker" ]]; then
        # Ctrl+C in a terminal sends SIGINT to every process in the
        # foreground group, which includes curl, so the create call can end
        # without a reply even though the server created the blackout. Look
        # for the blackout by its marker. The server may still be handling
        # the request, so look up to three times, a second apart.
        local attempt
        for attempt in 1 2 3; do
            ids=$(find_blackouts "$marker") || {
                echo "Error: could not look up the blackout" >&2
                status=1
                break
            }
            if [[ -n "$ids" ]]; then
                break
            fi
            if [[ "$attempt" -lt 3 ]]; then
                sleep 1
            fi
        done
    fi
    for id in $ids; do
        delete_blackout "$id" || {
            echo "Error: could not delete the blackout $id" >&2
            status=1
        }
    done
    exit "$status"
}

main() {
    local blackout_id blackout stopped active
    marker="cookbook-$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')"
    created=$(create_blackout "$WORKBENCH_CONNECTION_ID" "$marker")
    blackout_id=$(jq -er '.id' <<<"$created")
    active=$(jq -r '.is_active' <<<"$created")
    echo "Created a blackout for the server (active: $active)"

    blackout=$(get_blackout "$blackout_id")
    active=$(jq -r '.is_active' <<<"$blackout")
    echo "Read the blackout back (active: $active)"

    stopped=$(stop_blackout "$blackout_id")
    active=$(jq -r '.is_active' <<<"$stopped")
    echo "Stopped the blackout (active: $active)"
    if [[ "$active" != "false" ]]; then
        echo "The blackout is still active" >&2
        return 1
    fi

    delete_blackout "$blackout_id"
    created=""
    marker=""
    echo "Deleted the blackout"
}

# Without handlers for the signals, a second signal that arrives before bash
# has run the EXIT trap would end the script before the delete. The handlers
# exit with the usual status for a signal (128 plus the signal number), which
# runs the EXIT trap.
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
main
# --8<-- [end:main]
