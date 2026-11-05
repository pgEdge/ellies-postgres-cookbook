#!/usr/bin/env bash
#
# Ellie's Postgres Cookbook
# Checking the version of the pgEdge Control Plane, its cluster, and the
# state of each host, using curl and jq.
#
# These examples are for the Control Plane v0.11.0.
#
# Copyright (c) 2026, pgEdge, Inc.
# This code is released under the PostgreSQL License.

# --8<-- [start:imports]
# Stop at the first failed command or unset variable, and treat a failure
# anywhere in a pipeline as a failure of the whole pipeline.
set -euo pipefail

for tool in curl jq; do
    command -v "$tool" >/dev/null || { echo "$tool is required" >&2; exit 1; }
done
# --8<-- [end:imports]

# --8<-- [start:config]
# The :- operator treats an empty variable as unset.
CONTROL_PLANE_URL="${CONTROL_PLANE_URL:-http://localhost:3000}"
CONTROL_PLANE_URL="${CONTROL_PLANE_URL%/}"

TIMEOUT_SECONDS=30

# Fetches a path from the server and prints the JSON reply. With
# --fail-with-body, curl exits non-zero on an HTTP error status but still
# prints the body, which carries the server's explanation.
get() {
    curl --silent --show-error --fail-with-body \
        --max-time "$TIMEOUT_SECONDS" "$CONTROL_PLANE_URL$1"
}
# --8<-- [end:config]

# --8<-- [start:version]
# Prints the version of the Control Plane server.
show_version() {
    local response
    response="$(get /v1/version)" || {
        echo "Control Plane error: $response" >&2
        return 1
    }
    jq -er '"Version: \(.version | strings)"' <<<"$response" || {
        echo "Unexpected response: $response" >&2
        return 1
    }
}
# --8<-- [end:version]

# --8<-- [start:cluster]
# Prints the state of the cluster. A server answers this request only once
# its cluster has been initialised, and it then reports "available"; the
# health of the cluster shows in the state of each host.
show_cluster() {
    local response
    response="$(get /v1/cluster)" || {
        echo "Control Plane error: $response" >&2
        return 1
    }
    jq -er '"Cluster: \(.status.state | strings)"' <<<"$response" || {
        echo "Unexpected response: $response" >&2
        return 1
    }
}
# --8<-- [end:cluster]

# --8<-- [start:hosts]
# Lists the hosts in the cluster with their states, and fails when a
# request or reply fails or when a host is anything but "healthy". The
# other states are "degraded", "unreachable" and "unknown".
show_hosts() {
    local response
    response="$(get /v1/hosts)" || {
        echo "Control Plane error: $response" >&2
        return 1
    }
    jq -er '
        if (.hosts | type) != "array" then error("missing hosts") else
            "Hosts (\(.hosts | length)):",
            (.hosts[] | "- \(.id): \(.status.state // "unknown")")
        end' <<<"$response" || {
        echo "Unexpected response: $response" >&2
        return 1
    }
    jq -e 'all(.hosts[]; .status.state == "healthy")' <<<"$response" >/dev/null || {
        echo "A host is not healthy" >&2
        return 1
    }
}
# --8<-- [end:hosts]

# --8<-- [start:main]
main() {
    # Any failure, including an unhealthy host, gives a non-zero exit
    # status.
    show_version || exit 1
    show_cluster || exit 1
    show_hosts || exit 1
}

main
# --8<-- [end:main]
