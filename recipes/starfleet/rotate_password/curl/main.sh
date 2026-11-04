#!/usr/bin/env bash
#
# Ellie's Postgres Cookbook
# Rotating the password of a role in a pgEdge Starfleet database, and
# connecting with the new password, using curl, jq and psql.
#
# The script creates a database of its own to rotate a password in. The
# Starfleet service bills for every database from the moment that it
# becomes connectable, so the script deletes the database on every path:
# after a success, after a failure, and after Ctrl-C. The script never
# prints either password.
#
# Copyright (c) 2026, pgEdge, Inc.
# This code is released under the PostgreSQL License.

# --8<-- [start:imports]
# Stop at the first failed command or unset variable, and make a failure
# anywhere in a pipeline fail the whole pipeline.
set -euo pipefail

# The script needs curl to call the API, jq to read the JSON replies and
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
# Prints the address that the API sees requests come from. A new database
# is closed to everyone until an allowlist rule admits an address, and this
# is the one to admit; a bare address means a single host.
client_ip() {
    api GET /client-ip | jq -er '.ip_address'
}

# Creates a database that only this machine can reach, and prints the
# API's description of it, which includes its ID.
create_database() {
    local name="$1" display_name="$2" region="$3" size="$4" ip="$5"
    # The name becomes the Postgres database name, so it holds only letters
    # and digits, and the readable cookbook- prefix goes in the display
    # name. The script also uses the name to find the database again if the
    # reply to this request is lost.
    jq -n --arg name "$name" --arg display_name "$display_name" \
        --arg region "$region" --arg size "$size" --arg ip "$ip" \
        '{name: $name, display_name: $display_name,
          region: $region, size: $size,
          ip_allowlist: {rules: [{cidr: $ip, label: "cookbook"}]}}' |
        api POST /databases --header "Content-Type: application/json" \
            --data @- --write-out '\n%{http_code}'
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

# --8<-- [start:connection]
# Reads the connection details of an available database from its
# description, and writes a password file for psql in the format that it
# reads. The details, including the password of the application user, come
# with the description of the database, and are present only once the
# database is available. The API does not require the host, so fall back
# to the external IP address if it is missing. Each jq call fails if its
# field is missing, and the script reads the fields one by one instead of
# passing the output to eval, so that a failure cannot print the password
# or the environment.
write_passfile() {
    local description host port database username
    description="$(api GET "/databases/$1")" || return 1
    host="$(jq -er '.connection.host // .connection.external_ip_address | strings' <<<"$description")" || return 1
    port="$(jq -er '.connection.port | numbers' <<<"$description")" || return 1
    database="$(jq -er '.connection.database | strings' <<<"$description")" || return 1
    username="$(jq -er '.connection.username | strings' <<<"$description")" || return 1
    jq -e '.connection.password | strings' <<<"$description" >/dev/null || return 1

    # Only the owner may read the file, and the password goes into it
    # without passing through the process list. In a password file a colon
    # or backslash in a field needs a backslash before it.
    umask 077
    passfile="$(mktemp)" || return 1
    jq -er '.connection | [.host // .external_ip_address, (.port | tostring),
            .database, .username, .password]
            | map(strings | gsub("\\\\"; "\\\\") | gsub(":"; "\\:"))
            | join(":")' <<<"$description" >"$passfile" || return 1

    export PGPASSFILE="$passfile" PGHOST="$host" PGPORT="$port" \
        PGDATABASE="$database" PGUSER="$username" PGCONNECT_TIMEOUT=15
    # The sslmode=require setting encrypts the connection but does not
    # check the server certificate, which a public authority has not
    # signed. Anyone who can intercept the traffic could therefore
    # impersonate the server, so treat this as suitable for an example
    # only.
    export PGSSLMODE=require
}
# --8<-- [end:connection]

# --8<-- [start:rotate]
# The built-in role that the application connects as. The API also has the
# roles admin and app_read_only.
role="app"

# Prints the password that the description of the database holds for the
# application user. It goes to a variable and not to the screen.
current_password() {
    api GET "/databases/$1" | jq -er '.connection.password | strings'
}

# Asks the API to rotate the password of the role. The API answers 204
# with no body once it has accepted the rotation and started the work.
rotate_password() {
    api POST "/databases/$1/roles/$role/rotate-password"
}

# Polls the database until it is available again with a new password. The
# first argument is the database ID and the second is the old password.
wait_for_rotation() {
    local id="$1" old="$2" deadline=$((SECONDS + timeout_seconds))
    local description status password last="available"
    # The API moves the database to the modifying status until the rotation
    # is live, and until then the previous password still authenticates and
    # the new one does not. The wait therefore ends only when the status is
    # available and the password in the description differs from the old
    # one. A rotation that fails leaves the database degraded with the
    # previous password still working, so the example treats degraded and
    # failed as failures, which end the wait at once.
    while ((SECONDS < deadline)); do
        description="$(api GET "/databases/$id")"
        status="$(jq -er '.status' <<<"$description")"
        if [[ "$status" != "$last" ]]; then
            echo "Database status: $status"
            last="$status"
        fi
        if [[ "$status" == "degraded" || "$status" == "failed" ]]; then
            echo "Error: the database has the status $status" >&2
            return 1
        fi
        password="$(jq -r '.connection.password // empty' <<<"$description")"
        if [[ "$status" == "available" && -n "$password" && "$password" != "$old" ]]; then
            return 0
        fi
        sleep "$poll_seconds"
    done
    echo "Error: the password was not rotated after $timeout_seconds seconds" >&2
    return 1
}
# --8<-- [end:rotate]

# --8<-- [start:query]
# Connects to the database with psql, using the PG variables that
# write_passfile exported, and prints the name of the user that the server
# logged in.
current_user() {
    # A database can refuse connections for a short while after the API
    # reports it as available, so try a few times. psql exits with 2 for
    # every failure to connect, including a failed login, so the script
    # cannot tell a temporary failure from a permanent one and repeats
    # them all.
    local attempt
    for ((attempt = 1; attempt <= 6; attempt++)); do
        psql --no-psqlrc --tuples-only --no-align \
            --command 'SELECT current_user' && return 0
        ((attempt < 6)) && sleep "$poll_seconds"
    done
    return 1
}
# --8<-- [end:query]

# --8<-- [start:delete]
# Prints the ID of the database with the given name, or nothing. The script
# uses this when it cannot tell whether the create request worked. It
# repeats the request, as the delete does, because the fault that lost the
# reply to the create request may still be there.
find_database() {
    local deadline=$((SECONDS + timeout_seconds)) reply status
    while true; do
        # The --write-out option adds the HTTP status on a last line, and
        # prints 000 if no reply arrived. The request asks for the newest
        # databases first, but the API does not say which property it
        # sorts on.
        reply="$(api GET "/databases?limit=100&descending=true" \
            --write-out '\n%{http_code}')" || true
        status="${reply##*$'\n'}"
        case "$status" in
            200) break ;;
            000|409|429|5??) ;;
            *) echo "Error: listing the databases returned HTTP status $status" >&2
               return 1 ;;
        esac
        if ((SECONDS >= deadline)); then
            echo "Error: the list was still failing after $timeout_seconds seconds" >&2
            return 1
        fi
        sleep "$poll_seconds"
    done
    jq -r --arg name "$1" 'first(.[] | select(.name == $name) | .id) // empty' \
        <<<"${reply%$'\n'*}"
}

# Prints the ID of the database with the given name, looking up to three
# times because the service may not have recorded a request whose reply was
# lost until a little later. Prints nothing if the database never appears,
# and fails if a lookup fails.
find_created_database() {
    local attempt id
    for ((attempt = 1; attempt <= 3; attempt++)); do
        id="$(find_database "$1")" || return 1
        if [[ -n "$id" ]]; then
            echo "$id"
            return 0
        fi
        ((attempt < 3)) && sleep "$poll_seconds"
    done
    return 0
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
    [[ -n "$passfile" ]] && rm -f "$passfile"
    if [[ -n "$token" && -n "$name" ]]; then
        # If the script has no ID and cannot tell whether the create request
        # worked, look for the database by name.
        if [[ -z "$database_id" && "$lookup" == 1 ]]; then
            if ! database_id="$(find_created_database "$name")"; then
                echo "Error: could not look for database $name" >&2
                echo "Delete the database $name by hand, because it may still be billing" >&2
                database_id=""
                status=1
            elif [[ -z "$database_id" ]]; then
                echo "Error: the database $name was not found; check your account for it by hand" >&2
                status=1
            fi
        fi
        if [[ -n "$database_id" ]]; then
            if delete_database "$database_id"; then
                echo "Deleted database"
            else
                echo "Error: could not delete database $database_id" >&2
                echo "Delete the database $database_id by hand, because it may still be billing" >&2
                status=1
            fi
        fi
    fi
    exit "$status"
}

main() {
    token="" name="" database_id="" lookup=0 passfile=""
    trap cleanup EXIT
    # Turn Ctrl-C and SIGTERM into a normal exit, so that cleanup runs.
    trap 'exit 130' INT
    trap 'exit 143' TERM

    token="$(get_token)"

    local placement region size suffix database display_name reply status ip user old_password
    placement="$(choose_placement)"
    region="${placement% *}"
    size="${placement#* }"
    echo "Region: $region"
    echo "Size: $size"

    # Choose the name before the request, so that the cleanup can find the
    # database even if the reply to the request never arrives.
    suffix="$(od -An -N3 -tx1 /dev/urandom | tr -d ' \n')"
    name="cookbook$suffix"

    # Look the database up by name afterwards only if the outcome of the
    # request is unknown, so that a refusal cannot lead the cleanup to
    # delete another database that has the same name. The create_database
    # function ends its output with the HTTP status on a line of its own,
    # which is 000 if no reply arrived.
    ip="$(client_ip)"
    lookup=1
    if ! reply="$(create_database "$name" "cookbook-$suffix" "$region" "$size" "$ip")"; then
        status="${reply##*$'\n'}"
        echo "Error: creating the database failed" >&2
        echo "${reply%$'\n'*}" >&2
        [[ "$status" =~ ^4[0-9][0-9]$ ]] && lookup=0
        return 1
    fi
    database="${reply%$'\n'*}"
    database_id="$(jq -er '.id' <<<"$database")"
    display_name="$(jq -er '.display_name' <<<"$database")"
    echo "Created database $display_name"

    wait_until_available "$database_id"
    echo "Database is available"

    # Run write_passfile here and not inside $(...), so that cleanup sees
    # the path of the password file and can remove it.
    # Keep the old password only to see when the new one arrives.
    old_password="$(current_password "$database_id")"
    echo "Rotating the password of the $role role"
    rotate_password "$database_id"
    wait_for_rotation "$database_id" "$old_password"
    echo "Password rotated"

    write_passfile "$database_id"
    user="$(current_user)"
    echo "Connected as $user with the new password"
}

main
# --8<-- [end:main]
