#!/usr/bin/env bash
#
# Ellie's Postgres Cookbook
# Querying metrics and top queries with the AI DBA Workbench API, using curl
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
: "${WORKBENCH_TOKEN:?WORKBENCH_TOKEN must be set}"
: "${WORKBENCH_CONNECTION_ID:?WORKBENCH_CONNECTION_ID must be set}"
# --8<-- [end:config]

# --8<-- [start:request]
# Sends an authenticated GET request and prints the JSON reply:
# api PATH [curl options]. With --fail-with-body, a request that the server
# rejects leaves the server's error message in the reply, and the function
# prints it to standard error.
api() {
    local path="$1"
    shift
    local response
    response=$(curl --silent --show-error --fail-with-body --get \
        --header "Authorization: Bearer $WORKBENCH_TOKEN" \
        "$@" "$WORKBENCH_URL/api/v1$path") || {
        echo "GET $path failed: $response" >&2
        return 1
    }
    printf '%s' "$response"
}
# --8<-- [end:request]

# --8<-- [start:query_metrics]
# Prints one line for each series that the pg_stat_database probe collected
# over the last hour, in six buckets: the metric, the number of points, and
# the latest value. The --data-urlencode options build the query string.
query_metrics() {
    local series
    series=$(api /metrics/query \
        --data-urlencode "connection_id=$WORKBENCH_CONNECTION_ID" \
        --data-urlencode "probe_name=pg_stat_database" \
        --data-urlencode "time_range=1h" \
        --data-urlencode "buckets=6" \
        --data-urlencode "metrics=numbackends,xact_commit")

    if [[ "$(jq length <<<"$series")" -eq 0 ]]; then
        echo "The Workbench returned no series; has the collector run yet?" >&2
        return 1
    fi
    jq -r <<<"$series" '.[] | if .data == [] then "\(.name): no data"
                     else "\(.name): \(.data | length) points, latest \(.data | last | .value)"
                     end'
}
# --8<-- [end:query_metrics]

# --8<-- [start:top_queries]
# Prints the queries that have used the most execution time, as the
# pg_stat_statements extension on the monitored server recorded them.
# The query text is cut to 50 characters on one line.
top_queries() {
    local queries
    queries=$(api /metrics/top-queries \
        --data-urlencode "connection_id=$WORKBENCH_CONNECTION_ID" \
        --data-urlencode "limit=5" \
        --data-urlencode "order_by=total_exec_time" \
        --data-urlencode "exclude_collector=true")

    if [[ "$(jq length <<<"$queries")" -eq 0 ]]; then
        echo "No statements recorded (is pg_stat_statements installed?)"
        return
    fi
    echo "Top queries by total execution time:"
    jq -r 'to_entries[] | "\(.key + 1). \(.value.calls) calls, \(.value.mean_exec_time * 100 | round / 100) ms mean: \(.value.query | gsub("\\s+"; " ") | .[0:50])"' \
        <<<"$queries"
}
# --8<-- [end:top_queries]

# --8<-- [start:main]
main() {
    query_metrics
    top_queries
}

main
# --8<-- [end:main]
