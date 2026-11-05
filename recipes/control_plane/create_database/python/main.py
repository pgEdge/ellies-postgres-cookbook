"""
Ellie's Postgres Cookbook
Creating a pgEdge Control Plane database on one host, waiting until it is
available, and deleting it again, using httpx.

These examples are for the Control Plane v0.11.0.

The database runs in containers on the host until it is deleted, so this
program deletes the database it creates on every path: after a success,
after a failure, and after Ctrl-C.

Copyright (c) 2026, pgEdge, Inc.
This code is released under the PostgreSQL License.
"""

# --8<-- [start:imports]
import os
import re
import secrets
import signal
import sys
import time

import httpx
# --8<-- [end:imports]


# --8<-- [start:config]
# The or operator treats an empty variable as unset. The new database
# listens on the given port on its host, so choose one that is free.
BASE_URL = (os.environ.get("CONTROL_PLANE_URL") or "http://localhost:3000").rstrip("/")
PORT_TEXT = os.environ.get("CONTROL_PLANE_RECIPE_PORT") or "6433"

TIMEOUT_SECONDS = 30.0

# How long to wait for a database to become available, or to disappear
# after a delete, and how often to check.
WAIT_SECONDS = 600
POLL_SECONDS = 5


class ControlPlaneError(Exception):
    """Raised when the Control Plane rejects a request or replies oddly.
    The status is the HTTP status of the reply, if there was one."""

    def __init__(self, message: str, status: int | None = None):
        super().__init__(message)
        self.status = status


def call(client: httpx.Client, method: str, path: str, body: dict | None = None) -> dict:
    """Sends a request to the server, and returns the decoded reply."""
    response = client.request(method, path, json=body)
    if response.is_error:
        raise ControlPlaneError(
            f"HTTP {response.status_code}, {response.text[:200]}",
            response.status_code)
    try:
        reply = response.json()
        if isinstance(reply, dict):
            return reply
    except ValueError:
        pass
    raise ControlPlaneError(f"Unexpected response: {response.text[:200]}")
# --8<-- [end:config]


# --8<-- [start:host]
def first_host(client: httpx.Client) -> str:
    """Returns the ID of the first host in the cluster. A database places
    each of its nodes on one or more hosts, which run the Postgres
    containers."""
    hosts = call(client, "GET", "/v1/hosts").get("hosts") or []
    if not hosts:
        raise ControlPlaneError("the cluster has no hosts")
    return hosts[0]["id"]
# --8<-- [end:host]


# --8<-- [start:create]
def create_database(client: httpx.Client, database_id: str, host: str) -> None:
    """Asks the Control Plane to create a database with one node. The reply
    holds the database and the task that creates it; the work happens in
    the background after the reply."""
    call(client, "POST", "/v1/databases", {
        "id": database_id,
        "spec": {
            "database_name": "recipe",
            "port": int(PORT_TEXT),
            "nodes": [{"name": "n1", "host_ids": [host]}],
        },
    })
# --8<-- [end:create]


# --8<-- [start:wait]
def wait_until_available(client: httpx.Client, database_id: str) -> int:
    """Polls the database, printing its state each time it changes, until
    the state is available, and returns the port of its first instance.
    Each instance runs one node, and its connection_info holds the address
    and port that clients use. A failed state ends the wait at once."""
    deadline = time.monotonic() + WAIT_SECONDS
    last = None
    while time.monotonic() < deadline:
        database = call(client, "GET", f"/v1/databases/{database_id}")
        state = database.get("state")
        if state != last:
            print(f"Database state: {state}")
            last = state
        if state == "available":
            instances = database.get("instances") or []
            if not instances:
                raise ControlPlaneError("the database is available but has no instances")
            return instances[0]["connection_info"]["port"]
        if state == "failed":
            raise ControlPlaneError("the database has the state failed")
        time.sleep(POLL_SECONDS)
    raise ControlPlaneError(
        f"the database was not available after {WAIT_SECONDS} seconds")
# --8<-- [end:wait]


# --8<-- [start:delete]
def is_transient(error: Exception) -> bool:
    """Reports whether a failed request is worth repeating: no reply
    arrived, the server failed, or it answered 409, which the Control
    Plane does whilst another task, such as the create, is still running
    on the database."""
    if isinstance(error, httpx.TransportError):
        return True
    status = getattr(error, "status", None)
    return status is not None and (status == 409 or status >= 500)


def delete_database(client: httpx.Client, database_id: str) -> None:
    """Deletes the database and waits until the API no longer has it. A
    404 means that the database is already gone."""
    path = f"/v1/databases/{database_id}"
    deadline = time.monotonic() + WAIT_SECONDS
    while True:
        try:
            task_id = call(client, "DELETE", path)["task"]["task_id"]
            break
        except (httpx.TransportError, ControlPlaneError) as e:
            if getattr(e, "status", None) == 404:
                return
            if not is_transient(e) or time.monotonic() >= deadline:
                raise
            time.sleep(POLL_SECONDS)

    # The delete starts a task that removes the database; a 404 shows that
    # it has finished. Whilst the database is still there, the status of
    # the task shows whether the delete failed.
    while time.monotonic() < deadline:
        try:
            call(client, "GET", path)
            status = call(client, "GET", f"{path}/tasks/{task_id}").get("status")
            if status in ("failed", "canceled"):
                raise ControlPlaneError(
                    f"the delete task finished with the status {status}")
        except (httpx.TransportError, ControlPlaneError) as e:
            if getattr(e, "status", None) == 404:
                return
            if not is_transient(e):
                raise
        time.sleep(POLL_SECONDS)
    raise ControlPlaneError(
        f"the database was still present after {WAIT_SECONDS} seconds")
# --8<-- [end:delete]


# --8<-- [start:main]
def stop(*_) -> None:
    """Handles SIGTERM like Ctrl-C, by raising KeyboardInterrupt."""
    raise KeyboardInterrupt


def main() -> int:
    # The new database listens on this port, so check it before creating
    # anything.
    if not re.fullmatch(r"[1-9][0-9]{0,4}", PORT_TEXT) or int(PORT_TEXT) > 65535:
        print("CONTROL_PLANE_RECIPE_PORT must be a port number from 1 to 65535",
              file=sys.stderr)
        return 1

    # Turn SIGTERM into a KeyboardInterrupt, so that the finally block
    # runs, as it does for Ctrl-C.
    signal.signal(signal.SIGTERM, stop)

    exit_code = 0
    created = False
    # The client chooses the ID of a new database, so the program knows it
    # before the request, and can delete the database even if the reply
    # never arrives. The random suffix keeps the ID unique.
    database_id = f"cookbook-recipe-{secrets.token_hex(3)}"
    with httpx.Client(base_url=BASE_URL, timeout=TIMEOUT_SECONDS) as client:
        try:
            host = first_host(client)
            print(f"Host: {host}")

            # Clean up unless the server refused the request with a 4xx
            # status, which means it created nothing; a 409, for example,
            # means that a database with this ID already exists, and is
            # not this program's to delete.
            created = True
            try:
                create_database(client, database_id, host)
            except ControlPlaneError as e:
                if e.status is not None and 400 <= e.status < 500:
                    created = False
                raise
            print(f"Created database {database_id}")

            port = wait_until_available(client, database_id)
            print(f"Database is available on port {port}")
        # httpx.HTTPError is the base class for failures to reach the
        # server, such as a refused connection or a timeout.
        except (httpx.HTTPError, ControlPlaneError, KeyError) as e:
            print(f"Control Plane error: {e}", file=sys.stderr)
            exit_code = 1
        except KeyboardInterrupt:
            print("Interrupted", file=sys.stderr)
            exit_code = 130
        finally:
            # Delete the database whether the example succeeded, failed, or
            # was interrupted. Ignore further interrupts, so that they
            # cannot cut the cleanup short.
            signal.signal(signal.SIGINT, signal.SIG_IGN)
            signal.signal(signal.SIGTERM, signal.SIG_IGN)
            if created:
                try:
                    delete_database(client, database_id)
                    print("Deleted database")
                except (httpx.HTTPError, ControlPlaneError, KeyError) as e:
                    print(f"Control Plane error: {e}", file=sys.stderr)
                    print(f"Delete the database {database_id} by hand",
                          file=sys.stderr)
                    exit_code = 1

    return exit_code


if __name__ == "__main__":
    sys.exit(main())
# --8<-- [end:main]
