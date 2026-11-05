"""
Ellie's Postgres Cookbook
Checking the version of the pgEdge Control Plane, its cluster, and the
state of each host, using httpx.

These examples are for the Control Plane v0.11.0.

Copyright (c) 2026, pgEdge, Inc.
This code is released under the PostgreSQL License.
"""

# --8<-- [start:imports]
import os
import sys

import httpx
# --8<-- [end:imports]


# --8<-- [start:config]
# The or operator treats an empty variable as unset.
BASE_URL = (os.environ.get("CONTROL_PLANE_URL") or "http://localhost:3000").rstrip("/")

TIMEOUT_SECONDS = 30.0


class ControlPlaneError(Exception):
    """Raised when the Control Plane rejects a request or replies oddly."""


def get(client: httpx.Client, path: str) -> dict:
    """Fetches a path from the server, and returns the decoded reply."""
    response = client.get(path)
    if response.is_error:
        raise ControlPlaneError(f"HTTP {response.status_code}, {response.text[:200]}")
    try:
        body = response.json()
        if isinstance(body, dict):
            return body
    except ValueError:
        pass
    raise ControlPlaneError(f"Unexpected response: {response.text[:200]}")
# --8<-- [end:config]


# --8<-- [start:version]
def show_version(client: httpx.Client) -> None:
    """Prints the version of the Control Plane server."""
    version = get(client, "/v1/version").get("version")
    if not isinstance(version, str):
        raise ControlPlaneError("Unexpected response: missing version")
    print(f"Version: {version}")
# --8<-- [end:version]


# --8<-- [start:cluster]
def show_cluster(client: httpx.Client) -> None:
    """Prints the state of the cluster. A server answers this request only
    once its cluster has been initialised, and it then reports
    "available"; the health of the cluster shows in the state of each
    host."""
    state = (get(client, "/v1/cluster").get("status") or {}).get("state")
    if not isinstance(state, str):
        raise ControlPlaneError("Unexpected response: missing state")
    print(f"Cluster: {state}")
# --8<-- [end:cluster]


# --8<-- [start:hosts]
def show_hosts(client: httpx.Client) -> bool:
    """Lists the hosts in the cluster with their states, and returns
    whether every host is "healthy". The other states are "degraded",
    "unreachable" and "unknown"."""
    hosts = get(client, "/v1/hosts").get("hosts")
    if not isinstance(hosts, list):
        raise ControlPlaneError("Unexpected response: missing hosts")

    print(f"Hosts ({len(hosts)}):")
    healthy = True
    for host in hosts:
        state = (host.get("status") or {}).get("state", "unknown")
        print(f"- {host.get('id')}: {state}")
        healthy = healthy and state == "healthy"
    return healthy
# --8<-- [end:hosts]


# --8<-- [start:main]
def main() -> int:
    try:
        with httpx.Client(base_url=BASE_URL, timeout=TIMEOUT_SECONDS) as client:
            show_version(client)
            show_cluster(client)
            healthy = show_hosts(client)
    # httpx.HTTPError is the base class for failures to reach the server,
    # such as a refused connection or a timeout.
    except (httpx.HTTPError, ControlPlaneError) as e:
        print(f"Control Plane error: {e}", file=sys.stderr)
        return 1

    # Report an unhealthy host with the exit status.
    if not healthy:
        print("A host is not healthy", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
# --8<-- [end:main]
