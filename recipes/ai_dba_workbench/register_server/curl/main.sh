#!/usr/bin/env bash
#
# Ellie's Postgres Cookbook
# Registering a server to monitor with the AI DBA Workbench API, using curl
# and jq.
#
# Copyright (c) 2026, pgEdge, Inc.
# This code is released under the PostgreSQL License.

# --8<-- [start:imports]
# Stop at the first failing command, treat an unset variable as an error,
# and fail a pipeline when any command in it fails.
set -euo pipefail

# The script needs curl to make the requests and jq to read the replies.
for tool in curl jq; do
    command -v "$tool" >/dev/null || { echo "$tool is required" >&2; exit 1; }
done
# --8<-- [end:imports]

# --8<-- [start:config]
# Read the settings from the environment. The :- and :? forms, unlike - and
# ?, treat an empty variable as unset.
WORKBENCH_URL="${WORKBENCH_URL:-http://localhost:8080}"
WORKBENCH_URL="${WORKBENCH_URL%/}"
: "${WORKBENCH_USERNAME:?WORKBENCH_USERNAME must be set}"
: "${WORKBENCH_PASSWORD:?WORKBENCH_PASSWORD must be set}"
: "${WORKBENCH_CONNECTION_ID:?WORKBENCH_CONNECTION_ID must be set}"

# The Workbench refuses to register a server without a password, even one
# that uses trust authentication, so the script falls back to a placeholder.
SERVER_PASSWORD="${PGPASSWORD:-unused-with-trust-authentication}"
SERVER_NAME="cookbook-register-server"
# --8<-- [end:config]

# --8<-- [start:request]
# Sends an authenticated request and prints the JSON reply:
# api METHOD PATH TOKEN [curl options]. With --fail-with-body, a request
# that the server rejects leaves the server's error message in the reply,
# and the function prints it to standard error.
api() {
    local method="$1" path="$2" token="$3"
    shift 3
    local response
    response=$(curl --silent --show-error --fail-with-body \
        --request "$method" \
        --header "Authorization: Bearer $token" \
        "$@" "$WORKBENCH_URL/api/v1$path") || {
        echo "$method $path failed: $response" >&2
        return 1
    }
    printf '%s' "$response"
}
# --8<-- [end:request]

# --8<-- [start:login]
# Logs in and prints the session token. The server returns the token in a
# session_token cookie, so the request includes the response headers.
login() {
    local response
    # The credentials go to curl on standard input, so that they never
    # appear in the process list.
    response=$(jq -n --arg username "$WORKBENCH_USERNAME" \
                     --arg password "$WORKBENCH_PASSWORD" \
                     '{username: $username, password: $password}' |
        curl --silent --show-error --fail-with-body --include \
             --request POST \
             --header 'Content-Type: application/json' \
             --data @- \
             "$WORKBENCH_URL/api/v1/auth/login") || {
        echo "Login failed: $response" >&2
        return 1
    }

    # Header lines end in a carriage return, which tr removes.
    local token
    token=$(printf '%s' "$response" | tr -d '\r' |
        sed -n 's/^[Ss]et-[Cc]ookie: session_token=\([^;]*\).*/\1/p')
    if [[ -z "$token" ]]; then
        echo "The login reply had no session_token cookie" >&2
        return 1
    fi
    printf '%s' "$token"
}
# --8<-- [end:login]

# --8<-- [start:lookup]
# Prints the details of an existing connection, which the script uses as
# the address of the server to register.
get_connection() {
    local session="$1" connection_id="$2"
    api GET "/connections/$connection_id" "$session"
}
# --8<-- [end:lookup]

# --8<-- [start:register]
# Registers a server and prints the ID of the new connection. The address
# comes from an existing connection, given as JSON in the third argument.
register_server() {
    local session="$1" name="$2" template="$3"
    # The template's host, port, database, and user become the new
    # connection's. The script reads the password from the environment, and
    # sends a description, which the server needs in version 1.0.0.
    jq --arg name "$name" --arg password "$SERVER_PASSWORD" \
       '{name: $name, description: "Registered by the cookbook",
         host, port, database_name, username, ssl_mode,
         password: $password, is_monitored: true, is_shared: false}' \
       <<<"$template" |
        api POST /connections "$session" \
            --header 'Content-Type: application/json' --data @- |
        jq -r '.id'
}
# --8<-- [end:register]

# --8<-- [start:list]
# Prints the monitoring state of the named connection, or nothing if the
# list has no such connection.
find_connection() {
    local session="$1" name="$2"
    api GET /connections "$session" |
        jq -r --arg name "$name" \
           '.[] | select(.name == $name) | "monitored: \(.is_monitored)"'
}
# --8<-- [end:list]

# --8<-- [start:delete]
# Deletes a connection by its ID.
delete_connection() {
    local session="$1" connection_id="$2"
    api DELETE "/connections/$connection_id" "$session" >/dev/null
}
# --8<-- [end:delete]

# --8<-- [start:main]
# These variables are global, because the EXIT trap runs after main returns.
session=""
new_id=""

cleanup() {
    # Delete the connection when the script ends, even if a later step
    # failed, so that a failed run does not leave a server registered.
    if [[ -n "$new_id" ]]; then
        delete_connection "$session" "$new_id" 2>/dev/null || true
    fi
}

main() {
    session=$(login)
    local template found
    template=$(get_connection "$session" "$WORKBENCH_CONNECTION_ID")

    new_id=$(register_server "$session" "$SERVER_NAME" "$template")
    echo "Registered the server '$SERVER_NAME'"

    found=$(find_connection "$session" "$SERVER_NAME")
    if [[ -z "$found" ]]; then
        echo "The new connection is missing from the list" >&2
        return 1
    fi
    echo "Found '$SERVER_NAME' in the list ($found)"

    delete_connection "$session" "$new_id"
    new_id=""
    echo "Deleted the connection"

    if [[ -n "$(find_connection "$session" "$SERVER_NAME")" ]]; then
        echo "The connection is still in the list" >&2
        return 1
    fi
    echo "The connection is no longer in the list"
}

trap cleanup EXIT
main
# --8<-- [end:main]
