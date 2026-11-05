"""
Ellie's Postgres Cookbook
Finding the address of a pgEdge Control Plane database and connecting to
it, using httpx and psycopg.

These examples are for the Control Plane v0.11.0.

Copyright (c) 2026, pgEdge, Inc.
This code is released under the PostgreSQL License.
"""

# --8<-- [start:imports]
import os
import sys

import httpx
import psycopg
# --8<-- [end:imports]


# --8<-- [start:config]
# The or operator treats an empty variable as unset. The password has no
# default; the Control Plane never returns it, so it comes from whoever
# created the database user.
BASE_URL = (os.environ.get("CONTROL_PLANE_URL") or "http://localhost:3000").rstrip("/")
DATABASE_ID = os.environ.get("CONTROL_PLANE_DATABASE_ID") or "cookbook"
DATABASE_USER = os.environ.get("CONTROL_PLANE_DATABASE_USER") or "cookbook"
DATABASE_PASSWORD = os.environ.get("CONTROL_PLANE_DATABASE_PASSWORD") or None

TIMEOUT_SECONDS = 30


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


# --8<-- [start:find]
def find_instance(client: httpx.Client) -> dict:
    """Returns the connection settings for the first instance of the
    database that is available. Each instance runs one node of the
    database, and its connection_info holds the addresses and port that
    clients use."""
    database = get(client, f"/v1/databases/{DATABASE_ID}")
    for instance in database.get("instances") or []:
        info = instance.get("connection_info") or {}
        if instance.get("state") == "available" and info.get("addresses"):
            return {
                "node": instance.get("node_name"),
                "host": info["addresses"][0],
                "port": info.get("port"),
                "dbname": (database.get("spec") or {}).get("database_name"),
            }
    raise ControlPlaneError(f"no available instance of {DATABASE_ID}")
# --8<-- [end:find]


# --8<-- [start:connect]
def query(instance: dict) -> tuple[str, str]:
    """Connects to the instance, and returns the name of the database and
    the version of the Spock extension."""
    # The with block closes the connection when it exits, whether or not
    # an error occurred.
    with psycopg.connect(
        host=instance["host"],
        port=instance["port"],
        dbname=instance["dbname"],
        user=DATABASE_USER,
        password=DATABASE_PASSWORD,
        connect_timeout=TIMEOUT_SECONDS,
    ) as conn:
        database = conn.execute("SELECT current_database()").fetchone()[0]
        row = conn.execute(
            "SELECT extversion FROM pg_extension WHERE extname = 'spock'"
        ).fetchone()
    return database, row[0] if row else "not installed"
# --8<-- [end:connect]


# --8<-- [start:main]
def main() -> int:
    if DATABASE_PASSWORD is None:
        print("CONTROL_PLANE_DATABASE_PASSWORD must be set", file=sys.stderr)
        return 1

    try:
        with httpx.Client(base_url=BASE_URL, timeout=TIMEOUT_SECONDS) as client:
            instance = find_instance(client)
    # httpx.HTTPError is the base class for failures to reach the server,
    # such as a refused connection or a timeout.
    except (httpx.HTTPError, ControlPlaneError) as e:
        print(f"Control Plane error: {e}", file=sys.stderr)
        return 1
    print(f"Connecting to node {instance['node']}")

    try:
        database, spock = query(instance)
    # psycopg.Error is the base class for the driver's errors, including
    # connection failures and errors reported by the server.
    except psycopg.Error as e:
        print(f"Database error: {e}", file=sys.stderr)
        return 1
    print(f"Connected to database {database}")
    print(f"Spock: {spock}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
# --8<-- [end:main]
