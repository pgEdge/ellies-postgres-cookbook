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
# function prints it to standard error.
# The token goes to curl in a header file that bash supplies through a pipe,
# so that it never appears in the arguments of the curl process, which other
# users can read in the process list.
api() {
    local method="$1" path="$2"
    shift 2
    local response
    response=$(curl --silent --show-error --fail-with-body \
        --request "$method" \
        --header @<(printf 'Authorization: Bearer %s\n' "$WORKBENCH_TOKEN") \
        "$@" "$WORKBENCH_URL/api/v1$path") || {
        echo "$method $path failed: $response" >&2
        return 1
    }
    printf '%s' "$response"
}
# --8<-- [end:request]

# --8<-- [start:create]
# Creates a blackout for one monitored server and prints the reply. The
# blackout starts a minute ago, so that a small difference between the clocks
# of this machine and the server cannot leave it inactive, and it ends in one
# hour. The times are in RFC 3339 format, which jq builds from the current
# time.
create_blackout() {
    local connection_id="$1"
    jq -n --argjson connection_id "$connection_id" \
        '{scope: "server", connection_id: $connection_id,
          reason: "Cookbook maintenance window",
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
# Deletes a blackout by its ID.
delete_blackout() {
    api DELETE "/blackouts/$1" >/dev/null
}
# --8<-- [end:delete]

# --8<-- [start:main]
# This variable is global, because the EXIT trap runs after main returns.
blackout_id=""

cleanup() {
    local status=$?
    # Delete the blackout when the script ends, even if a later step failed,
    # so that a failed run does not leave alerts suppressed. Report a delete
    # that fails, and make the exit status non-zero.
    if [[ -n "$blackout_id" ]]; then
        delete_blackout "$blackout_id" || {
            echo "Error: could not delete the blackout $blackout_id" >&2
            status=1
        }
    fi
    exit "$status"
}

main() {
    local created blackout stopped active
    created=$(create_blackout "$WORKBENCH_CONNECTION_ID")
    blackout_id=$(jq -r '.id' <<<"$created")
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
    blackout_id=""
    echo "Deleted the blackout"
}

trap cleanup EXIT
main
# --8<-- [end:main]
