#!/usr/bin/env bash
#
# Ellie's Postgres Cookbook
# Authenticating with the AI DBA Workbench API, using curl and jq.
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
    # jq reads the credentials from its environment, and curl reads the
    # request from standard input, so that neither the password nor the
    # request body appears in a process list.
    response=$(jq -n '{username: env.WORKBENCH_USERNAME,
                       password: env.WORKBENCH_PASSWORD}' |
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

# --8<-- [start:user_info]
# Prints the user that a token belongs to, as "name (superuser: flag)".
user_info() {
    local token="$1"
    api GET /user/info "$token" |
        jq -r '"\(.username) (superuser: \(.is_superuser))"'
}
# --8<-- [end:user_info]

# --8<-- [start:create_token]
# Creates an API token for a user and prints its ID and its value, which
# the server shows only once. The token expires after an hour.
create_token() {
    local session="$1" owner="$2" annotation="$3"
    jq -n --arg owner "$owner" --arg annotation "$annotation" \
          '{owner_username: $owner, annotation: $annotation,
            expires_in: "1h"}' |
        api POST /rbac/tokens "$session" \
            --header 'Content-Type: application/json' --data @- |
        jq -r '"\(.id) \(.token)"'
}
# --8<-- [end:create_token]

# --8<-- [start:delete_token]
# Deletes an API token by its ID.
delete_token() {
    local session="$1" token_id="$2"
    api DELETE "/rbac/tokens/$token_id" "$session" >/dev/null
}
# --8<-- [end:delete_token]

# --8<-- [start:main]
# These variables are global, because the EXIT trap runs after main returns.
session=""
token_id=""

cleanup() {
    local status=$?
    # Delete the token when the script ends, even if a later step failed,
    # so that a failed run does not leave a token behind. Report a delete
    # that fails, and make the exit status non-zero.
    if [[ -n "$token_id" ]]; then
        delete_token "$session" "$token_id" || {
            echo "Error: could not delete the API token" >&2
            status=1
        }
    fi
    exit "$status"
}

main() {
    local who created api_token
    session=$(login)
    echo "Logged in with a session token"
    # Assign the result first: a failure inside a command substitution that
    # is an argument of echo would not stop the script.
    who=$(user_info "$session")
    echo "Session token belongs to $who"

    created=$(create_token "$session" "$WORKBENCH_USERNAME" \
                           "cookbook-authenticate")
    token_id="${created%% *}"
    api_token="${created#* }"
    echo "Created the API token 'cookbook-authenticate'"
    who=$(user_info "$api_token")
    echo "API token belongs to $who"

    delete_token "$session" "$token_id"
    token_id=""
    echo "Deleted the API token"
}

trap cleanup EXIT
main
# --8<-- [end:main]
