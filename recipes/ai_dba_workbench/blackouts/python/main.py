"""
Ellie's Postgres Cookbook
Scheduling a maintenance blackout with the AI DBA Workbench API, using httpx.

Copyright (c) 2026, pgEdge, Inc.
This code is released under the PostgreSQL License.
"""

# --8<-- [start:imports]
import os
import signal
import sys
from datetime import datetime, timedelta, timezone

import httpx
# --8<-- [end:imports]


# --8<-- [start:config]
def settings() -> dict:
    """Reads the settings from the environment.

    The or operator treats an empty variable as unset.
    """
    token = os.environ.get("WORKBENCH_TOKEN") or ""
    connection_id = os.environ.get("WORKBENCH_CONNECTION_ID") or ""
    if not (token and connection_id):
        raise RuntimeError(
            "WORKBENCH_TOKEN and WORKBENCH_CONNECTION_ID must be set"
        )
    if not connection_id.isdigit():
        raise RuntimeError("WORKBENCH_CONNECTION_ID must be a number")
    return {
        "base_url": (
            os.environ.get("WORKBENCH_URL") or "http://localhost:8080"
        ).rstrip("/"),
        "token": token,
        "connection_id": int(connection_id),
    }
# --8<-- [end:config]


# --8<-- [start:request]
interrupted = None


def on_signal(signum, frame) -> None:
    """Records that the program received SIGINT or SIGTERM. The handler
    replaces the default action, which would end the program before it could
    delete the blackout, and a second signal does nothing more."""
    global interrupted
    interrupted = signal.Signals(signum).name


def api(cfg: dict, method: str, path: str, interruptible: bool = True,
        **kwargs) -> httpx.Response:
    """Sends a request to the API and returns the response.

    A request that the server rejects raises an error that includes the
    message from the server, which raise_for_status alone would leave out.
    After a signal, every request that is interruptible fails at once; the
    cleanup and the create call, whose result the program must not lose,
    pass False.
    """
    if interruptible and interrupted:
        raise RuntimeError(f"Interrupted by {interrupted}")
    response = httpx.request(
        method, f"{cfg['base_url']}/api/v1{path}", timeout=30,
        headers={"Authorization": f"Bearer {cfg['token']}"}, **kwargs,
    )
    if response.is_error:
        raise RuntimeError(
            f"{method} {path} failed with status {response.status_code}: "
            f"{response.text.strip()}"
        )
    return response
# --8<-- [end:request]


# --8<-- [start:create]
def create_blackout(cfg: dict) -> dict:
    """Creates a blackout for one monitored server and returns it.

    The blackout starts a minute ago, so that a small difference between
    the clocks of this machine and the server cannot leave it inactive,
    and it ends in one hour. The times are in RFC 3339 format.
    """
    now = datetime.now(timezone.utc)
    return api(cfg, "POST", "/blackouts", interruptible=False, json={
        "scope": "server",
        "connection_id": cfg["connection_id"],
        "reason": "Cookbook maintenance window",
        "start_time": (now - timedelta(minutes=1)).isoformat(),
        "end_time": (now + timedelta(hours=1)).isoformat(),
    }).json()
# --8<-- [end:create]


# --8<-- [start:read]
def get_blackout(cfg: dict, blackout_id: int) -> dict:
    """Returns the blackout with the given ID."""
    return api(cfg, "GET", f"/blackouts/{blackout_id}").json()
# --8<-- [end:read]


# --8<-- [start:stop]
def stop_blackout(cfg: dict, blackout_id: int) -> dict:
    """Stops a blackout that is in progress, which sets its end time to
    now, and returns the stopped blackout."""
    return api(cfg, "POST", f"/blackouts/{blackout_id}/stop").json()
# --8<-- [end:stop]


# --8<-- [start:delete]
def delete_blackout(cfg: dict, blackout_id: int) -> None:
    """Deletes a blackout by its ID."""
    api(cfg, "DELETE", f"/blackouts/{blackout_id}", interruptible=False)
# --8<-- [end:delete]


# --8<-- [start:main]
def main() -> int:
    cfg = None
    blackout_id = None
    status = 0
    signal.signal(signal.SIGINT, on_signal)
    signal.signal(signal.SIGTERM, on_signal)
    try:
        cfg = settings()

        created = create_blackout(cfg)
        blackout_id = created["id"]
        print("Created a blackout for the server "
              f"(active: {str(created['is_active']).lower()})")

        blackout = get_blackout(cfg, blackout_id)
        print("Read the blackout back "
              f"(active: {str(blackout['is_active']).lower()})")

        stopped = stop_blackout(cfg, blackout_id)
        print("Stopped the blackout "
              f"(active: {str(stopped['is_active']).lower()})")
        if stopped["is_active"]:
            raise RuntimeError("The blackout is still active")

        delete_blackout(cfg, blackout_id)
        blackout_id = None
        print("Deleted the blackout")
    # httpx.HTTPError covers failures to connect, and RuntimeError covers
    # replies that the server rejected or that lacked what we need.
    except (httpx.HTTPError, RuntimeError) as e:
        print(f"Error: {e}", file=sys.stderr)
        status = 1
    finally:
        # Delete the blackout whether or not a later step failed, so that
        # a failed run does not leave alerts suppressed. A return statement
        # in a finally block would hide an exception that is still in
        # flight, so this block sets the exit status instead.
        if blackout_id is not None:
            try:
                delete_blackout(cfg, blackout_id)
            except (httpx.HTTPError, RuntimeError) as e:
                print(f"Error: could not delete the blackout: {e}",
                      file=sys.stderr)
                status = 1

    return status


if __name__ == "__main__":
    sys.exit(main())
# --8<-- [end:main]
