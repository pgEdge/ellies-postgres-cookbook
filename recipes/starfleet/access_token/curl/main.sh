#!/usr/bin/env bash
#
# Ellie's Postgres Cookbook
# Exchanging a client ID and secret for a pgEdge Starfleet access token,
# using curl and jq.
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
# The :- expansion treats an empty variable as unset.
base_url="${STARFLEET_API_URL:-https://api.pgedge.com}"
base_url="${base_url%/}"
client_id="${STARFLEET_CLIENT_ID:-}"
client_secret="${STARFLEET_CLIENT_SECRET:-}"
# --8<-- [end:config]

# --8<-- [start:token]
# Exchanges the client ID and secret for an access token, and prints the
# JSON reply. The token endpoint belongs to the account API, and accepts
# the OAuth 2.0 client credentials grant as a JSON body.
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
            "$base_url/account/v1/oauth/token"
}
# --8<-- [end:token]

# --8<-- [start:main]
main() {
    local reply
    reply="$(get_token)" || return 1

    # Never print the token itself; it grants access to the account. The
    # strings and numbers filters produce nothing for a missing or null
    # field, and -e then makes jq exit non-zero instead of printing null.
    jq -er '"Token type: \(.token_type | strings)",
            "Token length: \(.access_token | strings | length) characters",
            "Expires in: \(.expires_in | numbers) seconds"' <<<"$reply"
}

main
# --8<-- [end:main]
