"""
Ellie's Postgres Cookbook
Changing a Postgres setting of a pgEdge Control Plane database, checking
it from a connection, and putting the original settings back, using httpx
and psycopg.

These examples are for the Control Plane v0.11.0.

The program restores the original settings on every path: after a
success, after a failure, and after Ctrl-C.

Copyright (c) 2026, pgEdge, Inc.
This code is released under the PostgreSQL License.
"""

# --8<-- [start:imports]
import copy
import os
import signal
import sys
import time

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

# The setting to change, and its new value.
SETTING = "work_mem"
VALUE = "16MB"

# How long to wait for an update to finish, and how often to check.
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


# --8<-- [start:update]
def update_database(client: httpx.Client, spec: dict) -> str:
    """Sends a whole database spec as an update, and returns the ID of the
    task that applies it. The Control Plane compares the spec with the
    current one and changes only what differs; the work happens in the
    task after the reply."""
    reply = call(client, "POST", f"/v1/databases/{DATABASE_ID}", {"spec": spec})
    return reply["task"]["task_id"]


def changed_spec(spec: dict) -> dict:
    """Returns a copy of the spec with the setting changed.
    postgresql_conf holds the Postgres settings that the Control Plane
    manages, and may be missing."""
    changed = copy.deepcopy(spec)
    changed.setdefault("postgresql_conf", {})[SETTING] = VALUE
    return changed
# --8<-- [end:update]


# --8<-- [start:wait]
def wait_for_task(client: httpx.Client, task_id: str) -> None:
    """Polls a task until it finishes, and raises an error unless it
    completed."""
    deadline = time.monotonic() + WAIT_SECONDS
    while time.monotonic() < deadline:
        task = call(client, "GET", f"/v1/databases/{DATABASE_ID}/tasks/{task_id}")
        status = task.get("status")
        if status == "completed":
            return
        if status in ("failed", "canceled"):
            raise ControlPlaneError(f"the task finished with the status {status}")
        time.sleep(POLL_SECONDS)
    raise ControlPlaneError(f"the task was still running after {WAIT_SECONDS} seconds")
# --8<-- [end:wait]


# --8<-- [start:connect]
def show_setting(client: httpx.Client) -> str:
    """Connects to the first available instance and returns the current
    value of the setting. Each instance runs one node, and its
    connection_info holds the address and port that clients use."""
    database = call(client, "GET", f"/v1/databases/{DATABASE_ID}")
    for instance in database.get("instances") or []:
        info = instance.get("connection_info") or {}
        if instance.get("state") == "available" and info.get("addresses"):
            break
    else:
        raise ControlPlaneError(f"no available instance of {DATABASE_ID}")

    # The with block closes the connection when it exits, whether or not
    # an error occurred.
    with psycopg.connect(
        host=info["addresses"][0],
        port=info["port"],
        dbname=database["spec"]["database_name"],
        user=DATABASE_USER,
        password=DATABASE_PASSWORD,
        connect_timeout=TIMEOUT_SECONDS,
    ) as conn:
        return conn.execute("SELECT current_setting(%s)", (SETTING,)).fetchone()[0]
# --8<-- [end:connect]


# --8<-- [start:restore]
def restore(client: httpx.Client, spec: dict) -> None:
    """Sends the original spec back and waits for the task. The Control
    Plane answers 409 whilst another task, such as the update, is still
    running on the database, so the program repeats the request, as it
    does when no reply arrived or the server failed."""
    deadline = time.monotonic() + WAIT_SECONDS
    while True:
        try:
            task_id = update_database(client, spec)
            break
        except (httpx.TransportError, ControlPlaneError) as e:
            status = getattr(e, "status", None)
            transient = isinstance(e, httpx.TransportError) or (
                status is not None and (status == 409 or status >= 500))
            if not transient or time.monotonic() >= deadline:
                raise
            time.sleep(POLL_SECONDS)
    wait_for_task(client, task_id)
# --8<-- [end:restore]


# --8<-- [start:main]
def stop(*_) -> None:
    """Handles SIGTERM like Ctrl-C, by raising KeyboardInterrupt."""
    raise KeyboardInterrupt


def main() -> int:
    if not DATABASE_PASSWORD:
        print("CONTROL_PLANE_DATABASE_PASSWORD must be set", file=sys.stderr)
        return 1

    # Turn SIGTERM into a KeyboardInterrupt, so that the finally block
    # runs, as it does for Ctrl-C.
    signal.signal(signal.SIGTERM, stop)

    exit_code = 0
    changed = False
    original = None
    with httpx.Client(base_url=BASE_URL, timeout=TIMEOUT_SECONDS) as client:
        try:
            # The spec that the API returns leaves out the passwords of the
            # database users, and an update may leave them out too, which
            # keeps them unchanged.
            original = call(client, "GET", f"/v1/databases/{DATABASE_ID}")["spec"]

            # Restore unless the server refused the request with a 4xx
            # status, which means that it changed nothing.
            print(f"Setting {SETTING} to {VALUE}")
            changed = True
            try:
                task_id = update_database(client, changed_spec(original))
            except ControlPlaneError as e:
                if e.status is not None and 400 <= e.status < 500:
                    changed = False
                raise
            wait_for_task(client, task_id)
            print("Update completed")

            print(f"{SETTING} is now {show_setting(client)}")
        # httpx.HTTPError is the base class for failures to reach the
        # server, such as a refused connection or a timeout.
        except (httpx.HTTPError, ControlPlaneError, KeyError) as e:
            print(f"Control Plane error: {e}", file=sys.stderr)
            exit_code = 1
        # psycopg.Error is the base class for the driver's errors, including
        # a failure to connect.
        except psycopg.Error as e:
            print(f"Database error: {e}", file=sys.stderr)
            exit_code = 1
        except KeyboardInterrupt:
            print("Interrupted", file=sys.stderr)
            exit_code = 130
        finally:
            # Restore the original settings whether the example succeeded,
            # failed, or was interrupted. Ignore further interrupts, so
            # that they cannot cut the cleanup short.
            signal.signal(signal.SIGINT, signal.SIG_IGN)
            signal.signal(signal.SIGTERM, signal.SIG_IGN)
            if changed:
                try:
                    restore(client, original)
                    print("Restored the original settings")
                except (httpx.HTTPError, ControlPlaneError, KeyError) as e:
                    print(f"Control Plane error: {e}", file=sys.stderr)
                    print(f"Restore the settings of the database {DATABASE_ID} by hand",
                          file=sys.stderr)
                    exit_code = 1

    return exit_code


if __name__ == "__main__":
    sys.exit(main())
# --8<-- [end:main]
