"""
Ellie's Postgres Cookbook
Finding the task that created a pgEdge Control Plane database, and
following its log until the task finishes, using httpx.

These examples are for the Control Plane v0.11.0.

Copyright (c) 2026, pgEdge, Inc.
This code is released under the PostgreSQL License.
"""

# --8<-- [start:imports]
import os
import sys
import time

import httpx
# --8<-- [end:imports]


# --8<-- [start:config]
# The or operator treats an empty variable as unset.
BASE_URL = (os.environ.get("CONTROL_PLANE_URL") or "http://localhost:3000").rstrip("/")
DATABASE_ID = os.environ.get("CONTROL_PLANE_DATABASE_ID") or "cookbook"

TIMEOUT_SECONDS = 30.0

# How long to follow a task that is still running, and how often to check.
FOLLOW_SECONDS = 600
POLL_SECONDS = 5

# The statuses after which a task does not change again.
FINAL_STATUSES = {"completed", "failed", "canceled"}


class ControlPlaneError(Exception):
    """Raised when the Control Plane rejects a request or replies oddly."""


def get(client: httpx.Client, path: str, params: dict | None = None) -> dict:
    """Fetches a path from the server, and returns the decoded reply."""
    response = client.get(path, params=params)
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


# --8<-- [start:list]
def find_create_task(client: httpx.Client) -> str:
    """Returns the ID of the task that created the database. Every create,
    update and delete runs as a task. The IDs sort by creation time, and
    sort_order=asc lists the oldest task first."""
    reply = get(client, f"/v1/databases/{DATABASE_ID}/tasks",
                {"sort_order": "asc"})
    for task in reply.get("tasks") or []:
        if task.get("type") == "create":
            return task["task_id"]
    raise ControlPlaneError(f"no create task for {DATABASE_ID}")
# --8<-- [end:list]


# --8<-- [start:follow]
def follow_task(client: httpx.Client, task_id: str) -> str:
    """Prints the log of a task as it grows, until the task finishes, and
    returns its final status. Each log reply carries last_entry_id, and
    passing that back as after_entry_id fetches only the newer entries.
    The status is read before the log, so that once it is final, the log
    that follows it is complete."""
    path = f"/v1/databases/{DATABASE_ID}/tasks/{task_id}"
    deadline = time.monotonic() + FOLLOW_SECONDS
    after = None
    while True:
        status = get(client, path).get("status")

        log = get(client, f"{path}/log",
                  {"after_entry_id": after} if after else None)
        for entry in log.get("entries") or []:
            print(f"Log: {entry.get('message')}")
        after = log.get("last_entry_id") or after

        if status in FINAL_STATUSES:
            return status
        if time.monotonic() >= deadline:
            raise ControlPlaneError(
                f"task {task_id} was still {status} after {FOLLOW_SECONDS} seconds")
        time.sleep(POLL_SECONDS)
# --8<-- [end:follow]


# --8<-- [start:main]
def main() -> int:
    try:
        with httpx.Client(base_url=BASE_URL, timeout=TIMEOUT_SECONDS) as client:
            task_id = find_create_task(client)
            print("Task: create")
            status = follow_task(client, task_id)
    # httpx.HTTPError is the base class for failures to reach the server,
    # such as a refused connection or a timeout.
    except (httpx.HTTPError, ControlPlaneError) as e:
        print(f"Control Plane error: {e}", file=sys.stderr)
        return 1

    print(f"Status: {status}")
    return 0 if status == "completed" else 1


if __name__ == "__main__":
    sys.exit(main())
# --8<-- [end:main]
