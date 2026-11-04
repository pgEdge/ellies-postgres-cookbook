#!/usr/bin/env bash
#
# Ellie's Postgres Cookbook
# Listing the regions, sizes, and PostgreSQL versions that the pgEdge
# Starfleet Managed API offers, using curl and jq.
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
# Sends an authenticated GET request to the Managed API and prints the
# JSON reply. The --config option reads the Authorization header from a
# file that bash creates from the printf command, so the token never
# appears in the process list.
api_get() {
    curl --silent --show-error --fail-with-body --max-time 30 \
        --config <(printf 'header = "Authorization: Bearer %s"\n' "$token") \
        "$base_url/managed/v1$1"
}
# --8<-- [end:api]

# --8<-- [start:regions]
# Prints the identifiers of the regions that can host a database.
list_regions() {
    api_get /regions | jq -r '.[] | "  \(.region)"'
}
# --8<-- [end:regions]

# --8<-- [start:sizes]
# Prints a description of each size, smallest first. The pricing option
# asks the API to include each size's price. A size with no configured
# price omits the field, and the amount is in the smallest unit of the
# currency, such as cents.
list_sizes() {
    api_get "/sizes?include=pricing" | jq -r '.[] |
        "  \(.name): \(.connections) connections, \(.storage_size) storage" +
        (if .pricing then
            ", \(.pricing.price_amount / 100 | floor).\("0\(.pricing.price_amount % 100)"[-2:]) \(.pricing.currency) per \(.pricing.billing_interval)"
         else "" end)'
}
# --8<-- [end:sizes]

# --8<-- [start:versions]
# Prints the PostgreSQL major versions, newest first, marking the one
# that a new database gets by default.
list_versions() {
    api_get /pg-versions |
        jq -r '.[] | "  \(.version)\(if .default then " (default)" else "" end)"'
}
# --8<-- [end:versions]

# --8<-- [start:main]
main() {
    token="$(get_token)" || return 1

    echo "Regions:"
    list_regions
    echo "Sizes (smallest first):"
    list_sizes
    echo "PostgreSQL versions:"
    list_versions
}

main
# --8<-- [end:main]
