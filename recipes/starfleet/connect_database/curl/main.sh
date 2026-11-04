#!/usr/bin/env bash
#
# Ellie's Postgres Cookbook
# Connecting to a pgEdge Starfleet database and running a query, using
# curl, jq, and psql.
#
# The script creates a database of its own to connect to. The Starfleet
# service bills for every database from the moment that it becomes
# connectable, so the script deletes the database on every path: after a
# success, after a failure, and after Ctrl-C.
#
# Copyright (c) 2026, pgEdge, Inc.
# This code is released under the PostgreSQL License.

# --8<-- [start:imports]
# Stop at the first failed command or unset variable, and make a failure
# anywhere in a pipeline fail the whole pipeline.
set -euo pipefail

# The script needs curl to call the API, jq to read the JSON replies, and
# psql to connect to the database.
for tool in curl jq psql; do
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
# Managed API accepts as a bearer token for the next 24 hours, and prints
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
    local region="$1" size="$2" ip suffix
    # A new database is closed to everyone until an allowlist rule admits
    # an address. The API reports the address it sees this request come
    # from, which is the one to admit; a bare address means a single host.
    ip="$(api GET /client-ip | jq -er '.ip_address')"

    suffix="$(od -An -N3 -tx1 /dev/urandom | tr -d ' \n')"
    # The name becomes the Postgres database name, which allows only
    # letters and digits, so the readable cookbook- prefix goes in the
    # display name.
    jq -n --arg suffix "$suffix" --arg region "$region" --arg size "$size" \
        --arg ip "$ip" \
        '{name: "cookbook\($suffix)", display_name: "cookbook-\($suffix)",
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
        sleep "$poll_seconds"
    done
    echo "Error: the database was not available after $timeout_seconds seconds" >&2
    return 1
}
# --8<-- [end:wait]

# --8<-- [start:connection]
# Reads the connection details of an available database from its
# description, and prints them as the environment variables that psql
# reads. The details, including the password of the application user,
# come with the description of the database, and are present only once
# the database is available.
connection_environment() {
    api GET "/databases/$1" | jq -er '.connection |
        "PGHOST=\(.host | @sh)",
        "PGPORT=\(.port | @sh)",
        "PGDATABASE=\(.database | @sh)",
        "PGUSER=\(.username | @sh)",
        "PGPASSWORD=\(.password | @sh)"'
}
# --8<-- [end:connection]

# --8<-- [start:query]
# Connects to the database with psql and prints the server's version
# string. The connection details reach psql through its environment, so
# the password never appears in the process list.
server_version() {
    local settings
    settings="$(connection_environment "$1")"

    # The sslmode=require setting encrypts the connection without
    # verifying the server certificate, which a public authority has not
    # signed.
    (
        eval "export $(tr '\n' ' ' <<<"$settings")"
        export PGSSLMODE=require PGCONNECT_TIMEOUT=15

        # A database can refuse connections for a short while after the
        # API reports it as available, so try a few times.
        local attempt
        for attempt in 1 2 3 4 5 6; do
            psql --no-psqlrc --tuples-only --no-align \
                --command 'SELECT version()' && return 0
            sleep "$poll_seconds"
        done
        return 1
    )
}
# --8<-- [end:query]

# --8<-- [start:delete]
# Deletes the database and waits until the API no longer lists it.
delete_database() {
    local id="$1" deadline=$((SECONDS + timeout_seconds)) status

    while true; do
        status="$(api_status DELETE "/databases/$id")"
        case "$status" in
            204) break ;;
            # The API refuses with 409 while the database is busy with
            # another operation, such as being created, so try again.
            409) ;;
            *) echo "Error: deleting the database returned HTTP status $status" >&2
               return 1 ;;
        esac
        if ((SECONDS >= deadline)); then
            echo "Error: the database stayed busy for $timeout_seconds seconds" >&2
            return 1
        fi
        sleep "$poll_seconds"
    done

    # The delete starts the teardown; a 404 shows that it has finished.
    while true; do
        status="$(api_status GET "/databases/$id")"
        case "$status" in
            404) return 0 ;;
            200) ;;
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
    if [[ -n "${database_id:-}" ]]; then
        if delete_database "$database_id"; then
            echo "Deleted database"
        else
            echo "Error: could not delete database $database_id" >&2
            status=1
        fi
    fi
    exit "$status"
}

main() {
    database_id=""
    trap cleanup EXIT
    # Turn Ctrl-C and SIGTERM into a normal exit, so that cleanup runs.
    trap 'exit 130' INT
    trap 'exit 143' TERM

    token="$(get_token)"

    local placement region size database
    placement="$(choose_placement)"
    region="${placement% *}"
    size="${placement#* }"
    echo "Region: $region"
    echo "Size: $size"

    database="$(create_database "$region" "$size")"
    database_id="$(jq -er '.id' <<<"$database")"
    echo "Created database $(jq -er '.display_name' <<<"$database")"

    wait_until_available "$database_id"
    echo "Database is available"

    echo "Server version: $(server_version "$database_id")"
}

main
# --8<-- [end:main]
