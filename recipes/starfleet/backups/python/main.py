"""
Ellie's Postgres Cookbook
Taking an on-demand backup of a pgEdge Starfleet database, and tracking it
until it completes, using httpx.

The program creates a database of its own to back up. The Starfleet service
bills for every database from the moment that it becomes connectable, so
the program deletes the database on every path: after a success, after a
failure, and after Ctrl-C.

Copyright (c) 2026, pgEdge, Inc.
This code is released under the PostgreSQL License.
"""

# --8<-- [start:imports]
import os
import secrets
import signal
import sys
import time

import httpx
# --8<-- [end:imports]


# --8<-- [start:config]
# How long to wait for a database to become available, or to disappear
# after a delete, and how often to check.
TIMEOUT_SECONDS = 900
POLL_SECONDS = 10

# How many times to look for a database whose create reply was lost.
LOOKUP_ATTEMPTS = 3


def settings() -> dict:
    """Reads the API settings from the environment.

    The or operator treats an empty variable as unset. The client ID and
    secret have no defaults, so a missing value becomes None, and the
    token request reports it.
    """
    return {
        "base_url": (
            os.environ.get("STARFLEET_API_URL") or "https://api.pgedge.com"
        ).rstrip("/"),
        "client_id": os.environ.get("STARFLEET_CLIENT_ID") or None,
        "client_secret": os.environ.get("STARFLEET_CLIENT_SECRET") or None,
    }
# --8<-- [end:config]


# --8<-- [start:token]
def get_token(config: dict) -> str:
    """Exchanges the client ID and secret for an access token, which the
    Managed API accepts as a bearer token until it expires."""
    if not config["client_id"] or not config["client_secret"]:
        raise RuntimeError(
            "STARFLEET_CLIENT_ID and STARFLEET_CLIENT_SECRET must be set"
        )

    response = httpx.post(
        f"{config['base_url']}/account/v1/oauth/token",
        json={
            "grant_type": "client_credentials",
            "client_id": config["client_id"],
            "client_secret": config["client_secret"],
        },
        timeout=30,
    )
    # Turn any 4xx or 5xx status into an httpx.HTTPStatusError.
    response.raise_for_status()
    return response.json()["access_token"]
# --8<-- [end:token]


# --8<-- [start:api]
def api(config: dict, token: str, method: str, path: str, body=None):
    """Sends an authenticated request to the Managed API and returns the
    decoded JSON reply, or None if the reply has no body."""
    response = httpx.request(
        method,
        f"{config['base_url']}/managed/v1{path}",
        headers={"Authorization": f"Bearer {token}"},
        json=body,
        timeout=30,
    )
    response.raise_for_status()
    return response.json() if response.content else None
# --8<-- [end:api]


# --8<-- [start:placement]
def choose_placement(config: dict, token: str) -> tuple[str, str]:
    """Returns the region and size for the new database.

    The API lists sizes smallest first, so the first one is the cheapest.
    The API does not price regions, so the example takes the first one.
    """
    regions = api(config, token, "GET", "/regions")
    sizes = api(config, token, "GET", "/sizes")
    if not regions or not sizes:
        raise RuntimeError("the API offers no region or size")
    return regions[0]["region"], sizes[0]["name"]
# --8<-- [end:placement]


# --8<-- [start:create]
def client_ip(config: dict, token: str) -> str:
    """Returns the address that the API sees requests come from."""
    # A new database is closed to everyone until an allowlist rule admits
    # an address. The API reports the address it sees this request come
    # from, which is the one to admit; a bare address means a single host.
    return api(config, token, "GET", "/client-ip")["ip_address"]


def create_database(
    config: dict, token: str, name: str, display_name: str, region: str,
    size: str, ip: str,
) -> dict:
    """Creates a database that only this machine can reach, and returns
    the API's description of it, which includes its ID."""
    return api(config, token, "POST", "/databases", {
        # The name becomes the Postgres database name, so it holds only
        # letters and digits, and the readable cookbook- prefix goes in
        # the display name. The program also uses the name to find the
        # database again if the reply to this request is lost.
        "name": name,
        "display_name": display_name,
        "region": region,
        "size": size,
        "ip_allowlist": {"rules": [{"cidr": ip, "label": "cookbook"}]},
    })
# --8<-- [end:create]


# --8<-- [start:wait]
# The API does not document its status values; the example treats these
# two as failures, which end the wait at once instead of leaving it to run
# until the time limit.
FAILED_STATUSES = {"degraded", "failed"}


def wait_until_available(config: dict, token: str, database_id: str) -> None:
    """Polls the database until its status is available."""
    deadline = time.monotonic() + TIMEOUT_SECONDS
    last = None
    while time.monotonic() < deadline:
        status = api(config, token, "GET", f"/databases/{database_id}")["status"]
        if status != last:
            print(f"Database status: {status}")
            last = status
        if status == "available":
            return
        if status in FAILED_STATUSES:
            raise RuntimeError(f"the database has the status {status}")
        time.sleep(POLL_SECONDS)
    raise TimeoutError(f"the database was not available after {TIMEOUT_SECONDS} seconds")
# --8<-- [end:wait]


# --8<-- [start:backup]
# The API does not document its backup status values beyond "completed",
# which marks a usable backup; the example treats "failed" as a failure,
# which ends the wait at once instead of leaving it to run until the time
# limit.
FAILED_BACKUP_STATUSES = {"failed"}


def take_backup(config: dict, token: str, database_id: str) -> dict:
    """Starts an on-demand backup and returns the pending backup."""
    # The hot kind is a fast local snapshot. The durable kind streams a
    # base backup to object storage, and needs the durable tier to be
    # enabled for the database. The API answers 202 at once and runs the
    # backup in the background.
    return api(
        config, token, "POST", f"/databases/{database_id}/backup",
        {"kind": "hot"},
    )


def wait_for_backup(config: dict, token: str, backup_id: str) -> None:
    """Polls the backup until its status is completed."""
    deadline = time.monotonic() + TIMEOUT_SECONDS
    last = None
    while time.monotonic() < deadline:
        status = api(config, token, "GET", f"/backups/{backup_id}")["status"]
        if status != last:
            print(f"Backup status: {status}")
            last = status
        if status == "completed":
            return
        if status in FAILED_BACKUP_STATUSES:
            raise RuntimeError(f"the backup has the status {status}")
        time.sleep(POLL_SECONDS)
    raise TimeoutError(f"the backup was not completed after {TIMEOUT_SECONDS} seconds")


def print_tasks(config: dict, token: str, database_id: str) -> None:
    """Prints the name and status of each task recorded for the database."""
    # Managed database operations record their progress as tasks, with the
    # kind "database" and the database ID as the subject.
    tasks = api(
        config, token, "GET",
        f"/tasks?subject_kind=database&subject_id={database_id}",
    )
    for task in tasks or []:
        print(f"Task: {task['name']} ({task['status']})")


def backup_after_delete(config: dict, token: str, backup_id: str) -> str:
    """Reports whether the API still lists a backup once its database has
    been deleted. The API specification gives no rule for this, so the
    example only observes it."""
    prefix = "Backup after the database was deleted:"
    try:
        api(config, token, "GET", f"/backups/{backup_id}")
        return f"{prefix} still listed"
    except httpx.HTTPStatusError as e:
        return f"{prefix} {'gone' if e.response.status_code == 404 else 'unknown'}"
    except httpx.TransportError:
        return f"{prefix} unknown"
# --8<-- [end:backup]


# --8<-- [start:delete]
def is_transient(error: Exception) -> bool:
    """Reports whether a failed request is worth repeating: no reply
    arrived, the service is overloaded or failing, or it answered 409,
    which the API does whilst a database is still being created."""
    if isinstance(error, httpx.TransportError):
        return True
    if isinstance(error, httpx.HTTPStatusError):
        status = error.response.status_code
        return status in (409, 429) or status >= 500
    return False


def is_gone(error: Exception) -> bool:
    """Reports whether an error is a 404 reply, which means that the
    database does not exist."""
    return (
        isinstance(error, httpx.HTTPStatusError)
        and error.response.status_code == 404
    )


def find_database(config: dict, token: str, name: str):
    """Returns the ID of the database with the given name, or None. The
    program uses this when it cannot tell whether a create request worked.
    It repeats the request, as the delete does, because the fault that
    lost the reply to the create request may still be there. The request
    asks for the newest databases first, but the API does not say which
    property it sorts on."""
    deadline = time.monotonic() + TIMEOUT_SECONDS
    while True:
        try:
            databases = api(
                config, token, "GET", "/databases?limit=100&descending=true"
            )
            break
        except httpx.HTTPError as e:
            if not is_transient(e) or time.monotonic() > deadline:
                raise
            time.sleep(POLL_SECONDS)
    for database in databases or []:
        if database["name"] == name:
            return database["id"]
    return None


def find_created_database(config: dict, token: str, name: str):
    """Looks for the database a few times, because the service may not
    have recorded a request whose reply was lost until a little later.
    Returns None if the database never appears."""
    for attempt in range(LOOKUP_ATTEMPTS):
        database_id = find_database(config, token, name)
        if database_id is not None:
            return database_id
        if attempt < LOOKUP_ATTEMPTS - 1:
            time.sleep(POLL_SECONDS)
    return None


def outcome_unknown(error: Exception) -> bool:
    """Reports whether a failed create request might still have created
    the database: no reply arrived, or the service failed with a 5xx
    status. A 4xx reply is a definite refusal."""
    if isinstance(error, httpx.HTTPStatusError):
        return error.response.status_code >= 500
    return True


def delete_database(config: dict, token: str, database_id: str) -> None:
    """Deletes the database and waits until the API no longer lists it."""
    deadline = time.monotonic() + TIMEOUT_SECONDS
    while True:
        try:
            api(config, token, "DELETE", f"/databases/{database_id}")
            break
        except httpx.HTTPError as e:
            if is_gone(e):
                return
            if not is_transient(e) or time.monotonic() > deadline:
                raise
            time.sleep(POLL_SECONDS)

    # The delete starts the teardown; a 404 shows that it has finished.
    while time.monotonic() < deadline:
        try:
            api(config, token, "GET", f"/databases/{database_id}")
        except httpx.HTTPError as e:
            if is_gone(e):
                return
            if not is_transient(e):
                raise
        time.sleep(POLL_SECONDS)
    raise TimeoutError(f"the database was still present after {TIMEOUT_SECONDS} seconds")
# --8<-- [end:delete]


# --8<-- [start:main]
def stop(*_) -> None:
    """Handles SIGTERM like Ctrl-C, by raising KeyboardInterrupt."""
    raise KeyboardInterrupt


def main() -> int:
    # Turn SIGTERM into a KeyboardInterrupt, so that the finally block
    # runs, as it does for Ctrl-C.
    signal.signal(signal.SIGTERM, stop)

    config = settings()
    exit_code = 0
    token = None
    name = None
    database_id = None
    backup_id = None
    lookup = False
    try:
        token = get_token(config)

        region, size = choose_placement(config, token)
        print(f"Region: {region}")
        print(f"Size: {size}")

        # Choose the name before the request, so that the program can find
        # the database even if the reply to the request never arrives.
        suffix = secrets.token_hex(3)
        name, display_name = f"cookbook{suffix}", f"cookbook-{suffix}"
        # Look the database up by name afterwards only if the outcome of
        # the request is unknown, so that a refusal cannot lead the
        # cleanup to delete another database that has the same name.
        ip = client_ip(config, token)
        lookup = True
        try:
            database = create_database(
                config, token, name, display_name, region, size, ip
            )
        except (httpx.HTTPError, ValueError) as e:
            lookup = outcome_unknown(e)
            raise
        database_id = database["id"]
        print(f"Created database {database['display_name']}")

        wait_until_available(config, token, database_id)
        print("Database is available")

        backup_id = take_backup(config, token, database_id)["id"]
        print("Backup started")
        wait_for_backup(config, token, backup_id)
        print_tasks(config, token, database_id)
    # httpx.HTTPError covers connection failures and, through
    # raise_for_status(), error responses from the API.
    except (httpx.HTTPError, KeyError, ValueError, RuntimeError, TimeoutError) as e:
        print(f"Error: {e}", file=sys.stderr)
        exit_code = 1
    except KeyboardInterrupt:
        print("Interrupted", file=sys.stderr)
        exit_code = 130
    finally:
        # Delete the database whether the example succeeded, failed, or
        # was interrupted, because the service bills for it until then.
        # Ignore further interrupts, so that they cannot cut it short.
        signal.signal(signal.SIGINT, signal.SIG_IGN)
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        if token is not None and name is not None:
            try:
                if database_id is None and lookup:
                    database_id = find_created_database(config, token, name)
                    if database_id is None:
                        print(
                            f"Error: the database {name} was not found; "
                            "check your account for it by hand",
                            file=sys.stderr,
                        )
                        exit_code = 1
                if database_id is not None:
                    delete_database(config, token, database_id)
                    print("Deleted database")
                    if backup_id is not None:
                        print(backup_after_delete(config, token, backup_id))
            except (httpx.HTTPError, KeyError, ValueError, TimeoutError) as e:
                print(f"Error: {e}", file=sys.stderr)
                print(
                    f"Delete the database {database_id or name} by hand, "
                    "because it may still be billing",
                    file=sys.stderr,
                )
                exit_code = 1

    return exit_code


if __name__ == "__main__":
    sys.exit(main())
# --8<-- [end:main]
