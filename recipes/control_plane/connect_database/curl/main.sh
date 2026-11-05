#!/usr/bin/env bash
#
# Ellie's Postgres Cookbook
# Finding the address of a pgEdge Control Plane database and connecting
# to it, using curl, jq and psql.
#
# These examples are for the Control Plane v0.11.0.
#
# Copyright (c) 2026, pgEdge, Inc.
# This code is released under the PostgreSQL License.

# --8<-- [start:imports]
# Stop at the first failed command or unset variable, and treat a failure
# anywhere in a pipeline as a failure of the whole pipeline.
set -euo pipefail

for tool in curl jq psql; do
    command -v "$tool" >/dev/null || { echo "Control Plane error: $tool is required" >&2; exit 1; }
done
# --8<-- [end:imports]

# --8<-- [start:config]
# The :- operator treats an empty variable as unset. The password has no
# default; the Control Plane never returns it, so it comes from whoever
# created the database user.
CONTROL_PLANE_URL="${CONTROL_PLANE_URL:-http://localhost:3000}"
CONTROL_PLANE_URL="${CONTROL_PLANE_URL%/}"
DATABASE_ID="${CONTROL_PLANE_DATABASE_ID:-cookbook}"
DATABASE_USER="${CONTROL_PLANE_DATABASE_USER:-cookbook}"
DATABASE_PASSWORD="${CONTROL_PLANE_DATABASE_PASSWORD:-}"

TIMEOUT_SECONDS=30

# Fetches a path from the server and prints the JSON reply. With
# --fail-with-body, curl exits non-zero on an HTTP error status but still
# prints the body, which carries the server's explanation.
get() {
    curl --silent --show-error --fail-with-body \
        --max-time "$TIMEOUT_SECONDS" "$CONTROL_PLANE_URL$1"
}
# --8<-- [end:config]

# --8<-- [start:find]
# Prints the database name, node name, address and port of the first
# instance of the database that is available, separated by spaces. Each
# instance runs one node of the database, and its connection_info holds
# the addresses and port that clients use.
find_instance() {
    local response
    response="$(get "/v1/databases/$DATABASE_ID")" || {
        echo "Control Plane error: $response" >&2
        return 1
    }
    jq -er '
        .spec.database_name as $name
        | first(.instances[]?
                | select(.state == "available"
                         and (.connection_info.addresses | length) > 0))
        | "\($name) \(.node_name) \(.connection_info.addresses[0]) \(.connection_info.port)"
        ' <<<"$response" || {
        echo "Control Plane error: no available instance of $DATABASE_ID" >&2
        return 1
    }
}
# --8<-- [end:find]

# --8<-- [start:connect]
# Connects with psql and runs the two queries. PGPASSWORD passes the
# password through the environment, so it never appears in the process
# list. The -X option skips any .psqlrc, -A and -t print bare values, and
# ON_ERROR_STOP makes psql exit non-zero if a query fails.
query() {
    local name="$1" address="$2" port="$3"
    PGPASSWORD="$DATABASE_PASSWORD" PGCONNECT_TIMEOUT="$TIMEOUT_SECONDS" \
        psql -X -A -t -v ON_ERROR_STOP=1 \
        --host "$address" --port "$port" \
        --username "$DATABASE_USER" --dbname "$name" \
        -c "SELECT current_database()" \
        -c "SELECT coalesce((SELECT extversion FROM pg_extension
                             WHERE extname = 'spock'), 'not installed')"
}
# --8<-- [end:connect]

# --8<-- [start:main]
main() {
    local instance name node address port result database spock

    if [[ -z "$DATABASE_PASSWORD" ]]; then
        echo "CONTROL_PLANE_DATABASE_PASSWORD must be set" >&2
        exit 1
    fi

    instance="$(find_instance)" || exit 1
    read -r name node address port <<<"$instance"
    echo "Connecting to node $node"

    result="$(query "$name" "$address" "$port")" || {
        echo "Database error: could not query $name" >&2
        exit 1
    }
    # psql prints the result of each query on a line of its own.
    { read -r database; read -r spock; } <<<"$result"
    echo "Connected to database $database"
    echo "Spock: $spock"
}

main
# --8<-- [end:main]
