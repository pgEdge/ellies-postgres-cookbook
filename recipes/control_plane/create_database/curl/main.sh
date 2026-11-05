#!/usr/bin/env bash
#
# Ellie's Postgres Cookbook
# Creating a pgEdge Control Plane database on one host, waiting until it is
# available, and deleting it again, using curl and jq.
#
# These examples are for the Control Plane v0.11.0.
#
# The database runs in containers on the host until it is deleted, so this
# script deletes the database it creates on every path: after a success,
# after a failure, and after Ctrl-C.
#
# Copyright (c) 2026, pgEdge, Inc.
# This code is released under the PostgreSQL License.

# --8<-- [start:imports]
# Stop at the first failed command or unset variable, and make a failure
# anywhere in a pipeline fail the whole pipeline.
set -euo pipefail

# The script needs curl to call the API and jq to read the JSON replies.
for tool in curl jq; do
    command -v "$tool" >/dev/null || { echo "Control Plane error: $tool is required" >&2; exit 1; }
done
# --8<-- [end:imports]

# --8<-- [start:config]
# The :- expansion treats an empty variable as unset. The new database
# listens on the given port on its host, so choose one that is free.
base_url="${CONTROL_PLANE_URL:-http://localhost:3000}"
base_url="${base_url%/}"
port="${CONTROL_PLANE_RECIPE_PORT:-6433}"

# How long to wait for a database to become available, or to disappear
# after a delete, and how often to check.
wait_seconds=600
poll_seconds=5

# Sends a request and prints the reply, followed by the HTTP status on a
# line of its own; the status is 000 if no reply arrived. Any further
# arguments go to curl, such as --data @- to send standard input as the
# body.
request() {
    local method="$1" path="$2"
    shift 2
    curl --silent --show-error --max-time 30 --request "$method" \
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

# --8<-- [start:host]
# Prints the ID of the first host in the cluster. A database places each of
# its nodes on one or more hosts, which run the Postgres containers.
first_host() {
    get /v1/hosts | jq -er '.hosts[0].id'
}
# --8<-- [end:host]

# --8<-- [start:create]
# Asks the Control Plane to create a database with one node, and prints the
# reply followed by the HTTP status, as request() does. The reply holds the
# database and the task that creates it; the work happens in the
# background after the reply.
create_database() {
    local id="$1" host="$2"
    jq -n --arg id "$id" --arg host "$host" --argjson port "$port" \
        '{id: $id,
          spec: {database_name: "recipe",
                 port: $port,
                 nodes: [{name: "n1", host_ids: [$host]}]}}' |
        request POST /v1/databases \
            --header "Content-Type: application/json" --data @-
}
# --8<-- [end:create]

# --8<-- [start:wait]
# Polls the database, printing its state each time it changes, until the
# state is available, and then sets available_port to the port of its
# first instance. Each instance runs one node, and its connection_info
# holds the address and port that clients use. A failed state ends the
# wait at once.
wait_until_available() {
    local id="$1" deadline=$((SECONDS + wait_seconds)) database state last=""
    while ((SECONDS < deadline)); do
        database="$(get "/v1/databases/$id")"
        state="$(jq -er '.state' <<<"$database")"
        if [[ "$state" != "$last" ]]; then
            echo "Database state: $state"
            last="$state"
        fi
        if [[ "$state" == "available" ]]; then
            available_port="$(jq -er '.instances[0].connection_info.port' <<<"$database")" || {
                echo "Control Plane error: the database is available but has no instances" >&2
                return 1
            }
            return 0
        fi
        if [[ "$state" == "failed" ]]; then
            echo "Control Plane error: the database has the state failed" >&2
            return 1
        fi
        sleep "$poll_seconds"
    done
    echo "Control Plane error: the database was not available after $wait_seconds seconds" >&2
    return 1
}
# --8<-- [end:wait]

# --8<-- [start:delete]
# Deletes the database and waits until the API no longer has it. The
# Control Plane answers 409 whilst another task, such as the create, is
# still running on the database, so the script repeats the request, as it
# does when no reply arrived or the server failed. A 404 means that the
# database is already gone.
delete_database() {
    local id="$1" deadline=$((SECONDS + wait_seconds)) reply status
    local task_id task_status

    while true; do
        reply="$(request DELETE "/v1/databases/$id")"
        status="${reply##*$'\n'}"
        case "$status" in
            200) task_id="$(jq -er '.task.task_id' <<<"${reply%$'\n'*}")" || {
                     echo "Control Plane error: Unexpected response: ${reply%$'\n'*}" >&2
                     return 1
                 }
                 break ;;
            404) return 0 ;;
            000|409|5??) ;;
            *) echo "Control Plane error: HTTP $status, ${reply%$'\n'*}" >&2
               return 1 ;;
        esac
        if ((SECONDS >= deadline)); then
            echo "Control Plane error: the delete was still failing after $wait_seconds seconds" >&2
            return 1
        fi
        sleep "$poll_seconds"
    done

    # The delete starts a task that removes the database; a 404 shows that
    # it has finished. Whilst the database is still there, the status of
    # the task shows whether the delete failed.
    while true; do
        reply="$(request GET "/v1/databases/$id")"
        status="${reply##*$'\n'}"
        case "$status" in
            404) return 0 ;;
            200) reply="$(request GET "/v1/databases/$id/tasks/$task_id")"
                 if [[ "${reply##*$'\n'}" == 200 ]]; then
                     task_status="$(jq -r '.status // empty' <<<"${reply%$'\n'*}")"
                     if [[ "$task_status" == failed || "$task_status" == canceled ]]; then
                         echo "Control Plane error: the delete task finished with the status $task_status" >&2
                         return 1
                     fi
                 fi ;;
            000|5??) ;;
            *) echo "Control Plane error: HTTP $status, ${reply%$'\n'*}" >&2
               return 1 ;;
        esac
        if ((SECONDS >= deadline)); then
            echo "Control Plane error: the database was still present after $wait_seconds seconds" >&2
            return 1
        fi
        sleep "$poll_seconds"
    done
}
# --8<-- [end:delete]

# --8<-- [start:main]
# Deletes the database, if the script may have created one. The EXIT trap
# runs this function when the script finishes, whether the example
# succeeded, failed, or was interrupted.
cleanup() {
    local status=$?
    # Ignore further interrupts, so that they cannot cut the cleanup short.
    trap '' INT TERM
    if [[ "$created" == 1 ]]; then
        if delete_database "$database_id"; then
            echo "Deleted database"
        else
            echo "Delete the database $database_id by hand" >&2
            status=1
        fi
    fi
    exit "$status"
}

main() {
    database_id="" created=0 available_port=""
    if ! [[ "$port" =~ ^[1-9][0-9]{0,4}$ ]] || ((port > 65535)); then
        echo "CONTROL_PLANE_RECIPE_PORT must be a port number from 1 to 65535" >&2
        exit 1
    fi

    trap cleanup EXIT
    # Turn Ctrl-C and SIGTERM into a normal exit, so that cleanup runs.
    trap 'echo "Interrupted" >&2; exit 130' INT TERM

    local host reply status
    host="$(first_host)"
    echo "Host: $host"

    # The client chooses the ID of a new database, so the script knows it
    # before the request, and can delete the database even if the reply
    # never arrives. The random suffix keeps the ID unique.
    database_id="cookbook-recipe-$(od -An -N3 -tx1 /dev/urandom | tr -d ' \n')"

    # Clean up unless the server refused the request with a 4xx status,
    # which means it created nothing; a 409, for example, means that a
    # database with this ID already exists, and is not this script's to
    # delete.
    created=1
    reply="$(create_database "$database_id" "$host")"
    status="${reply##*$'\n'}"
    if [[ "$status" != 200 ]]; then
        [[ "$status" =~ ^4[0-9][0-9]$ ]] && created=0
        echo "Control Plane error: HTTP $status, ${reply%$'\n'*}" >&2
        return 1
    fi
    echo "Created database $database_id"

    wait_until_available "$database_id"
    echo "Database is available on port $available_port"
}

main
# --8<-- [end:main]
