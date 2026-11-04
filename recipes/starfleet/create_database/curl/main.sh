#!/usr/bin/env bash
#
# Ellie's Postgres Cookbook
# Creating a pgEdge Starfleet database, waiting until it is available, and
# deleting it again, using curl and jq.
#
# The Starfleet service bills for every database from the moment that it
# becomes connectable, so this script deletes the database it creates on
# every path: after a success, after a failure, and after Ctrl-C.
#
# Copyright (c) 2026, pgEdge, Inc.
# This code is released under the PostgreSQL License.

# --8<-- [start:imports]
# Stop at the first failed command or unset variable, and make a failure
# anywhere in a pipeline fail the whole pipeline.
set -euo pipefail

# The script needs curl to call the API and jq to read the JSON replies.
for tool in curl jq; do
    command -v "$tool" >/dev/null || { echo "Error: $tool is required" >&2; exit 1; }
done
# --8<-- [end:imports]

# --8<-- [start:config]
# How long to wait for a database to become available, or to disappear
# after a delete, and how often to check.
timeout_seconds=900
poll_seconds=10

# The :- expansion treats an empty variable as unset.
base_url="${STARFLEET_API_URL:-https://api.pgedge.com}"
base_url="${base_url%/}"
client_id="${STARFLEET_CLIENT_ID:-}"
client_secret="${STARFLEET_CLIENT_SECRET:-}"
# --8<-- [end:config]

# --8<-- [start:token]
# Exchanges the client ID and secret for an access token, which the
# Managed API accepts as a bearer token until it expires, and prints
# the token.
get_token() {
    if [[ -z "$client_id" || -z "$client_secret" ]]; then
        echo "Error: STARFLEET_CLIENT_ID and STARFLEET_CLIENT_SECRET must be set" >&2
        return 1
    fi

    # jq builds the body from the environment, and curl reads it from
    # standard input with --data @-, so the secret never appears in the
    # process list. --fail-with-body makes curl exit non-zero on an HTTP
    # error status whilst still printing the API's error message.
    jq -n '{grant_type: "client_credentials",
            client_id: env.STARFLEET_CLIENT_ID,
            client_secret: env.STARFLEET_CLIENT_SECRET}' |
        curl --silent --show-error --fail-with-body --max-time 30 \
            --header "Content-Type: application/json" \
            --data @- \
            "$base_url/account/v1/oauth/token" |
        jq -er '.access_token'
}
# --8<-- [end:token]

# --8<-- [start:api]
# Sends an authenticated request to the Managed API and prints the JSON
# reply. The first argument is the method, the second is the path, and any
# others go to curl, such as --data @- to send standard input as the body.
# The --config option reads the Authorization header from a file that
# bash creates from the printf command, so the token never appears in the
# process list; that leaves standard input free for the body.
api() {
    local method="$1" path="$2"
    shift 2
    curl --silent --show-error --fail-with-body --max-time 30 \
        --request "$method" \
        --config <(printf 'header = "Authorization: Bearer %s"\n' "$token") \
        "$@" "$base_url/managed/v1$path"
}

# Sends a request and prints only the HTTP status, for the calls that
# react to a particular status. A status of 000 means no reply arrived.
api_status() {
    curl --silent --output /dev/null --write-out '%{http_code}' --max-time 30 \
        --request "$1" \
        --config <(printf 'header = "Authorization: Bearer %s"\n' "$token") \
        "$base_url/managed/v1$2" || true
}
# --8<-- [end:api]

# --8<-- [start:placement]
# Prints the region and size for the new database, separated by a space.
# The API lists sizes smallest first, so the first one is the cheapest.
# The API does not price regions, so the example takes the first one.
choose_placement() {
    local region size
    region="$(api GET /regions | jq -er '.[0].region')"
    size="$(api GET /sizes | jq -er '.[0].name')"
    echo "$region $size"
}
# --8<-- [end:placement]

# --8<-- [start:create]
# Creates a database that only this machine can reach, and prints the
# API's description of it, which includes its ID.
create_database() {
    local name="$1" display_name="$2" region="$3" size="$4" ip
    # A new database is closed to everyone until an allowlist rule admits
    # an address. The API reports the address it sees this request come
    # from, which is the one to admit; a bare address means a single host.
    ip="$(api GET /client-ip | jq -er '.ip_address')"

    # The name becomes the Postgres database name, so it holds only letters
    # and digits, and the readable cookbook- prefix goes in the display
    # name. The script also uses the name to find the database again if the
    # reply to this request is lost.
    jq -n --arg name "$name" --arg display_name "$display_name" \
        --arg region "$region" --arg size "$size" --arg ip "$ip" \
        '{name: $name, display_name: $display_name,
          region: $region, size: $size,
          ip_allowlist: {rules: [{cidr: $ip, label: "cookbook"}]}}' |
        api POST /databases --header "Content-Type: application/json" --data @-
}
# --8<-- [end:create]

# --8<-- [start:wait]
# Polls the database until its status is available.
wait_until_available() {
    local id="$1" deadline=$((SECONDS + timeout_seconds)) status last=""
    while ((SECONDS < deadline)); do
        status="$(api GET "/databases/$id" | jq -er '.status')"
        if [[ "$status" != "$last" ]]; then
            echo "Database status: $status"
            last="$status"
        fi
        [[ "$status" == "available" ]] && return 0
        # The API does not document its status values; the example treats
        # these two as failures, which end the wait at once instead of
        # leaving it to run until the time limit.
        if [[ "$status" == "degraded" || "$status" == "failed" ]]; then
            echo "Error: the database has the status $status" >&2
            return 1
        fi
        sleep "$poll_seconds"
    done
    echo "Error: the database was not available after $timeout_seconds seconds" >&2
    return 1
}
# --8<-- [end:wait]

# --8<-- [start:delete]
# Prints the ID of the database with the given name, or nothing. The script
# uses this when the reply to the create request was lost.
find_database() {
    api GET "/databases?limit=100&descending=true" |
        jq -r --arg name "$1" 'first(.[] | select(.name == $name) | .id) // empty'
}

# Deletes the database and waits until the API no longer lists it. A status
# of 000 means that no reply arrived; that, 409 (which the API gives whilst a
# database is still being created), 429, and the 5xx statuses are worth
# repeating until the time limit.
delete_database() {
    local id="$1" deadline=$((SECONDS + timeout_seconds)) status

    while true; do
        status="$(api_status DELETE "/databases/$id")"
        case "$status" in
            204) break ;;
            404) return 0 ;;
            000|409|429|5??) ;;
            *) echo "Error: deleting the database returned HTTP status $status" >&2
               return 1 ;;
        esac
        if ((SECONDS >= deadline)); then
            echo "Error: the delete was still failing after $timeout_seconds seconds" >&2
            return 1
        fi
        sleep "$poll_seconds"
    done

    # The delete starts the teardown; a 404 shows that it has finished.
    while true; do
        status="$(api_status GET "/databases/$id")"
        case "$status" in
            404) return 0 ;;
            200|000|429|5??) ;;
            *) echo "Error: checking the database returned HTTP status $status" >&2
               return 1 ;;
        esac
        if ((SECONDS >= deadline)); then
            echo "Error: the database was still present after $timeout_seconds seconds" >&2
            return 1
        fi
        sleep "$poll_seconds"
    done
}
# --8<-- [end:delete]

# --8<-- [start:main]
# Deletes the database, if the script created one. The EXIT trap runs this
# function when the script finishes, whether the example succeeded, failed,
# or was interrupted, because the service bills for the database until then.
cleanup() {
    local status=$?
    # Ignore further interrupts, so that they cannot cut the cleanup short.
    trap '' INT TERM
    if [[ -n "$token" && -n "$name" ]]; then
        # If the script has no ID, the reply to the create request may have
        # been lost, so look for the database by name.
        if [[ -z "$database_id" ]]; then
            if ! database_id="$(find_database "$name")"; then
                echo "Error: could not look for database $name" >&2
                database_id=""
                status=1
            fi
        fi
        if [[ -n "$database_id" ]]; then
            if delete_database "$database_id"; then
                echo "Deleted database"
            else
                echo "Error: could not delete database $database_id" >&2
                status=1
            fi
        fi
    fi
    exit "$status"
}

main() {
    token="" name="" database_id=""
    trap cleanup EXIT
    # Turn Ctrl-C and SIGTERM into a normal exit, so that cleanup runs.
    trap 'exit 130' INT
    trap 'exit 143' TERM

    token="$(get_token)"

    local placement region size suffix database display_name
    placement="$(choose_placement)"
    region="${placement% *}"
    size="${placement#* }"
    echo "Region: $region"
    echo "Size: $size"

    # Choose the name before the request, so that the cleanup can find the
    # database even if the reply to the request never arrives.
    suffix="$(od -An -N3 -tx1 /dev/urandom | tr -d ' \n')"
    name="cookbook$suffix"
    database="$(create_database "$name" "cookbook-$suffix" "$region" "$size")"
    database_id="$(jq -er '.id' <<<"$database")"
    display_name="$(jq -er '.display_name' <<<"$database")"
    echo "Created database $display_name"

    wait_until_available "$database_id"
    echo "Database is available"
}

main
# --8<-- [end:main]
