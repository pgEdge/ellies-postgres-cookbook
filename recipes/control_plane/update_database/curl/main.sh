#!/usr/bin/env bash
#
# Ellie's Postgres Cookbook
# Changing a Postgres setting of a pgEdge Control Plane database, checking
# it from a connection, and putting the original settings back, using
# curl, jq and psql.
#
# These examples are for the Control Plane v0.11.0.
#
# The script restores the original settings on every path: after a
# success, after a failure, and after Ctrl-C.
#
# Copyright (c) 2026, pgEdge, Inc.
# This code is released under the PostgreSQL License.

# --8<-- [start:imports]
# Stop at the first failed command or unset variable, and make a failure
# anywhere in a pipeline fail the whole pipeline.
set -euo pipefail

# The script needs curl to call the API, jq to read and build the JSON,
# and psql to connect to the database.
for tool in curl jq psql; do
    command -v "$tool" >/dev/null || { echo "Control Plane error: $tool is required" >&2; exit 1; }
done
# --8<-- [end:imports]

# --8<-- [start:config]
# The :- expansion treats an empty variable as unset. The password has no
# default; the Control Plane never returns it, so it comes from whoever
# created the database user.
base_url="${CONTROL_PLANE_URL:-http://localhost:3000}"
base_url="${base_url%/}"
database_id="${CONTROL_PLANE_DATABASE_ID:-cookbook}"
database_user="${CONTROL_PLANE_DATABASE_USER:-cookbook}"
database_password="${CONTROL_PLANE_DATABASE_PASSWORD:-}"

timeout_seconds=30

# The setting to change, and its new value.
setting=work_mem
value=16MB

# How long to wait for an update to finish, and how often to check.
wait_seconds=600
poll_seconds=5

# Sends a request and prints the reply, followed by the HTTP status on a
# line of its own; the status is 000 if no reply arrived. Any further
# arguments go to curl, such as --data @- to send standard input as the
# body.
request() {
    local method="$1" path="$2"
    shift 2
    curl --silent --show-error --max-time "$timeout_seconds" --request "$method" \
        --write-out '\n%{http_code}' "$@" "$base_url$path" || true
}

# Fetches a path from the server and prints the reply, or reports the
# error and fails.
get() {
    local reply status
    reply="$(request GET "$1")"
    status="${reply##*$'\n'}"
    if [[ "$status" != 200 ]]; then
        echo "Control Plane error: HTTP $status, ${reply%$'\n'*}" >&2
        return 1
    fi
    printf '%s\n' "${reply%$'\n'*}"
}
# --8<-- [end:config]

# --8<-- [start:update]
# Sends a whole database spec as an update, and prints the reply followed
# by the HTTP status, as request() does. The Control Plane compares the
# spec with the current one and changes only what differs; the work
# happens in a task after the reply.
update_database() {
    jq '{spec: .}' <<<"$1" |
        request POST "/v1/databases/$database_id" \
            --header "Content-Type: application/json" --data @-
}

# Prints the spec with the setting changed. postgresql_conf holds the
# Postgres settings that the Control Plane manages, and may be missing.
changed_spec() {
    jq --arg name "$setting" --arg value "$value" \
        '.postgresql_conf = ((.postgresql_conf // {}) + {($name): $value})' <<<"$1"
}
# --8<-- [end:update]

# --8<-- [start:wait]
# Polls a task until it finishes, and fails unless it completed.
wait_for_task() {
    local task_id="$1" deadline=$((SECONDS + wait_seconds)) status
    while ((SECONDS < deadline)); do
        status="$(get "/v1/databases/$database_id/tasks/$task_id" | jq -er '.status')"
        case "$status" in
            completed) return 0 ;;
            failed|canceled)
                echo "Control Plane error: the task finished with the status $status" >&2
                return 1 ;;
        esac
        sleep "$poll_seconds"
    done
    echo "Control Plane error: the task was still running after $wait_seconds seconds" >&2
    return 1
}
# --8<-- [end:wait]

# --8<-- [start:connect]
# Connects to the first available instance with psql and prints the
# current value of the setting. Each instance runs one node, and its
# connection_info holds the address and port that clients use. PGPASSWORD
# passes the password through the environment, so it never appears in the
# process list.
show_setting() {
    local database name address port
    database="$(get "/v1/databases/$database_id")"
    read -r name address port < <(jq -er '
        .spec.database_name as $name
        | first(.instances[]?
                | select(.state == "available"
                         and (.connection_info.addresses | length) > 0))
        | "\($name) \(.connection_info.addresses[0]) \(.connection_info.port)"
        ' <<<"$database") || {
        echo "Control Plane error: no available instance of $database_id" >&2
        return 1
    }
    PGPASSWORD="$database_password" PGCONNECT_TIMEOUT="$timeout_seconds" \
        psql -X -A -t -v ON_ERROR_STOP=1 \
        --host "$address" --port "$port" \
        --username "$database_user" --dbname "$name" \
        -c "SHOW $setting" || {
        echo "Database error: could not query $name" >&2
        return 1
    }
}
# --8<-- [end:connect]

# --8<-- [start:restore]
# Sends the original spec back and waits for the task. The Control Plane
# answers 409 whilst another task, such as the update, is still running on
# the database, so the script repeats the request, as it does when no
# reply arrived or the server failed.
restore() {
    local deadline=$((SECONDS + wait_seconds)) reply status
    while true; do
        reply="$(update_database "$original")"
        status="${reply##*$'\n'}"
        case "$status" in
            200) break ;;
            000|409|5??) ;;
            *) echo "Control Plane error: HTTP $status, ${reply%$'\n'*}" >&2
               return 1 ;;
        esac
        if ((SECONDS >= deadline)); then
            echo "Control Plane error: the restore was still failing after $wait_seconds seconds" >&2
            return 1
        fi
        sleep "$poll_seconds"
    done
    wait_for_task "$(jq -er '.task.task_id' <<<"${reply%$'\n'*}")"
}
# --8<-- [end:restore]

# --8<-- [start:main]
# Restores the original settings, if the script may have changed them. The
# EXIT trap runs this function when the script finishes, whether the
# example succeeded, failed, or was interrupted.
cleanup() {
    local status=$?
    # Ignore further interrupts, so that they cannot cut the cleanup short.
    trap '' INT TERM
    if [[ "$changed" == 1 ]]; then
        if restore; then
            echo "Restored the original settings"
        else
            echo "Restore the settings of the database $database_id by hand" >&2
            status=1
        fi
    fi
    exit "$status"
}

main() {
    original="" changed=0
    trap cleanup EXIT
    # Turn Ctrl-C and SIGTERM into a normal exit, so that cleanup runs.
    trap 'exit 130' INT
    trap 'exit 143' TERM

    if [[ -z "$database_password" ]]; then
        echo "CONTROL_PLANE_DATABASE_PASSWORD must be set" >&2
        return 1
    fi

    # The spec that the API returns leaves out the passwords of the
    # database users, and an update may leave them out too, which keeps
    # them unchanged.
    local reply status current
    original="$(get "/v1/databases/$database_id" | jq -e '.spec')"

    # Restore unless the server refused the request with a 4xx status,
    # which means that it changed nothing.
    echo "Setting $setting to $value"
    changed=1
    reply="$(update_database "$(changed_spec "$original")")"
    status="${reply##*$'\n'}"
    if [[ "$status" != 200 ]]; then
        [[ "$status" =~ ^4[0-9][0-9]$ ]] && changed=0
        echo "Control Plane error: HTTP $status, ${reply%$'\n'*}" >&2
        return 1
    fi
    wait_for_task "$(jq -er '.task.task_id' <<<"${reply%$'\n'*}")"
    echo "Update completed"

    current="$(show_setting)"
    echo "$setting is now $current"
}

main
# --8<-- [end:main]
