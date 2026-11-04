"""
Ellie's Postgres Cookbook
Listing and acknowledging alerts with the AI DBA Workbench API, using httpx.

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
# The rule that the program makes fire. The metric_staleness rule alerts when
# a probe's data is out of date, and the alerter checks it every minute.
RULE_NAME = "metric_staleness"

# The longest the whole run waits for alerts, in seconds. The alerter
# evaluates its rules once a minute and clears an alert up to 30 seconds
# after it fires, so this allows for waiting out the alert from an earlier
# run, one alert that clears before the program can acknowledge it, and a
# second evaluation.
WAIT_SECONDS = 150

# How often the program polls the alerts, in seconds.
POLL_SECONDS = 0.5


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
    return {
        "base_url": (
            os.environ.get("WORKBENCH_URL") or "http://localhost:8080"
        ).rstrip("/"),
        "token": token,
        "connection_id": connection_id,
    }
# --8<-- [end:config]


# --8<-- [start:request]
def api(method: str, cfg: dict, path: str, **kwargs) -> httpx.Response:
    """Sends a request to the API and returns the response.

    A request that the server rejects raises an error that includes the
    message from the server, which raise_for_status alone would leave out.
    """
    response = httpx.request(
        method, f"{cfg['base_url']}/api/v1{path}",
        headers={"Authorization": f"Bearer {cfg['token']}"}, timeout=30,
        **kwargs,
    )
    if response.is_error:
        raise RuntimeError(
            f"{method} {path} failed with status {response.status_code}: "
            f"{response.text.strip()}"
        )
    return response
# --8<-- [end:request]


# --8<-- [start:find_rule]
def find_rule(cfg: dict, name: str) -> int:
    """Returns the ID of an alert rule, given its name."""
    for rule in api("GET", cfg, "/alert-rules").json():
        if rule["name"] == name:
            return rule["id"]
    raise RuntimeError(f"There is no alert rule named '{name}'")
# --8<-- [end:find_rule]


# --8<-- [start:set_override]
def set_override(cfg: dict, rule_id: int) -> None:
    """Overrides the threshold of a rule for one server.

    A threshold of -1 is below any value that the staleness ratio can
    take, so the rule is violated on the next evaluation.
    """
    api("PUT", cfg,
        f"/alert-overrides/server/{cfg['connection_id']}/{rule_id}",
        json={"operator": ">", "threshold": -1, "severity": "info",
              "enabled": True})
# --8<-- [end:set_override]


# --8<-- [start:wait_for_alert]
def active_alerts(cfg: dict, rule_id: int) -> list:
    """Returns the active alerts that the given rule raised for the server.

    The request filters by server, status, and type, and asks for the most
    alerts that the API returns at once, so that the result does not depend
    on the first 100 alerts of a busy Workbench.
    """
    alerts = api("GET", cfg, "/alerts", params={
        "connection_id": cfg["connection_id"], "status": "active",
        "alert_type": "threshold", "limit": 1000,
    }).json()["alerts"]
    return [alert for alert in alerts if alert["rule_id"] == rule_id]


def wait_until_quiet(cfg: dict, rule_id: int, deadline: float) -> None:
    """Waits until the rule has no active alert.

    The alerter raises no new alert for a rule while one is active, so an
    alert left by an earlier run, which clears within 30 seconds, would
    otherwise stand in for the one that this run causes.
    """
    while active_alerts(cfg, rule_id):
        if time.monotonic() >= deadline:
            raise RuntimeError("An earlier alert did not clear in time")
        time.sleep(POLL_SECONDS)


def wait_for_alert(cfg: dict, rule_id: int, deadline: float) -> dict:
    """Polls until the given rule raises an alert, and returns it.

    The alert clears itself within 30 seconds of firing, so the program
    polls twice a second.
    """
    while True:
        alerts = active_alerts(cfg, rule_id)
        if alerts:
            return alerts[0]
        if time.monotonic() >= deadline:
            raise RuntimeError(
                f"No alert was raised within {WAIT_SECONDS} seconds"
            )
        time.sleep(POLL_SECONDS)
# --8<-- [end:wait_for_alert]


# --8<-- [start:acknowledge]
def acknowledge_alert(cfg: dict, alert_id: int) -> None:
    """Acknowledges an alert, with a message that the interface shows."""
    api("POST", cfg, "/alerts/acknowledge", json={
        "alert_id": alert_id, "message": "Acknowledged by the cookbook",
    })
# --8<-- [end:acknowledge]


# --8<-- [start:check]
def acknowledged_alerts(cfg: dict) -> list:
    """Returns the acknowledged threshold alerts for the server."""
    return api("GET", cfg, "/alerts", params={
        "connection_id": cfg["connection_id"], "status": "acknowledged",
        "alert_type": "threshold", "limit": 1000,
    }).json()["alerts"]


def alert_status(cfg: dict, alert_id: int) -> str:
    """Returns the status of an alert, found by its ID in the list of
    acknowledged alerts."""
    for alert in acknowledged_alerts(cfg):
        if alert["id"] == alert_id:
            return alert["status"]
    raise RuntimeError("The alert is missing from the acknowledged alerts")
# --8<-- [end:check]


# --8<-- [start:unacknowledge]
def unacknowledge_alert(cfg: dict, alert_id: int) -> None:
    """Returns an acknowledged alert to the active state.

    The alerter clears only active alerts, so an alert that stays
    acknowledged also stops the rule from raising a new one.
    """
    api("DELETE", cfg, "/alerts/acknowledge", params={"alert_id": alert_id})
# --8<-- [end:unacknowledge]


# --8<-- [start:remove_override]
def remove_override(cfg: dict, rule_id: int) -> None:
    """Removes the override, so that the rule reverts to its default
    threshold."""
    api("DELETE", cfg,
        f"/alert-overrides/server/{cfg['connection_id']}/{rule_id}")
# --8<-- [end:remove_override]


# --8<-- [start:main]
def main() -> int:
    cfg = None
    override_rule = None
    acknowledged_alert = None
    status = 0
    try:
        cfg = settings()
        deadline = time.monotonic() + WAIT_SECONDS

        rule_id = find_rule(cfg, RULE_NAME)
        print(f"Found the rule '{RULE_NAME}'")

        # An alert from an earlier run may still be active.
        wait_until_quiet(cfg, rule_id, deadline)

        # Set the override first and remove it in the finally block, so
        # that a failed run does not leave the server raising alerts.
        override_rule = rule_id
        set_override(cfg, rule_id)
        print("Set an override that makes the rule fire")

        print("Waiting for the alerter to raise an alert")
        while True:
            alert = wait_for_alert(cfg, rule_id, deadline)

            # Record the alert before acknowledging it, so that the
            # finally block returns it to the active state even if the
            # request times out after the server has acted on it.
            acknowledged_alert = alert["id"]
            try:
                acknowledge_alert(cfg, alert["id"])
                break
            except (httpx.HTTPError, RuntimeError):
                # The alerter may have cleared the alert since the poll.
                # The override is still in place, so the rule fires again
                # at the next evaluation; any other failure is real.
                if any(a["id"] == alert["id"]
                       for a in active_alerts(cfg, rule_id)):
                    # The server did not acknowledge it, so there is
                    # nothing to undo.
                    acknowledged_alert = None
                    raise
                # If the server acted on a request that timed out, the
                # alert is acknowledged and must go back to active. When
                # that fails, the error propagates and the finally block
                # tries again, because acknowledged_alert is still set.
                if any(a["id"] == alert["id"]
                       for a in acknowledged_alerts(cfg)):
                    unacknowledge_alert(cfg, alert["id"])
                acknowledged_alert = None
                print("The alert cleared first; waiting for the next one",
                      file=sys.stderr)
        print(f"An alert is active (severity: {alert['severity']})")
        print("Acknowledged the alert")

        print(f"The alert is now {alert_status(cfg, alert['id'])}")

        unacknowledge_alert(cfg, alert["id"])
        acknowledged_alert = None
        print("Returned the alert to the active state")

        remove_override(cfg, rule_id)
        override_rule = None
        print("Removed the override")
    # httpx.HTTPError covers failures to connect, and RuntimeError covers
    # replies that the server rejected or that lacked what we need.
    except (httpx.HTTPError, RuntimeError) as e:
        print(f"Error: {e}", file=sys.stderr)
        status = 1
    finally:
        # Undo the changes whether or not a step failed, so that the server
        # does not keep raising alerts or hold an acknowledged one.
        for undo, value in ((unacknowledge_alert, acknowledged_alert),
                            (remove_override, override_rule)):
            if value is None:
                continue
            try:
                undo(cfg, value)
            except (httpx.HTTPError, RuntimeError) as e:
                print(f"Error: could not undo a change: {e}",
                      file=sys.stderr)
                status = 1

    return status


if __name__ == "__main__":
    sys.exit(main())
# --8<-- [end:main]
