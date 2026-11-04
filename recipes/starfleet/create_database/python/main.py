"""
Ellie's Postgres Cookbook
Creating a pgEdge Starfleet database, waiting until it is available, and
deleting it again, using httpx.

The Starfleet service bills for every database from the moment that it
becomes connectable, so this program deletes the database it creates on
every path: after a success, after a failure, and after Ctrl-C.

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
    Managed API accepts as a bearer token for the next 24 hours."""
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
def create_database(config: dict, token: str, region: str, size: str) -> dict:
    """Creates a database that only this machine can reach, and returns
    the API's description of it, which includes its ID."""
    # A new database is closed to everyone until an allowlist rule admits
    # an address. The API reports the address it sees this request come
    # from, which is the one to admit; a bare address means a single host.
    ip = api(config, token, "GET", "/client-ip")["ip_address"]

    suffix = secrets.token_hex(3)
    return api(config, token, "POST", "/databases", {
        # The name becomes the Postgres database name, which allows only
        # letters and digits, so the readable cookbook- prefix goes in the
        # display name.
        "name": f"cookbook{suffix}",
        "display_name": f"cookbook-{suffix}",
        "region": region,
        "size": size,
        "ip_allowlist": {"rules": [{"cidr": ip, "label": "cookbook"}]},
    })
# --8<-- [end:create]


# --8<-- [start:wait]
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
        time.sleep(POLL_SECONDS)
    raise TimeoutError(f"the database was not available after {TIMEOUT_SECONDS} seconds")
# --8<-- [end:wait]


# --8<-- [start:delete]
def delete_database(config: dict, token: str, database_id: str) -> None:
    """Deletes the database and waits until the API no longer lists it."""
    deadline = time.monotonic() + TIMEOUT_SECONDS
    while True:
        try:
            api(config, token, "DELETE", f"/databases/{database_id}")
            break
        except httpx.HTTPStatusError as e:
            # The API refuses with 409 while the database is busy with
            # another operation, such as being created, so try again.
            if e.response.status_code != 409 or time.monotonic() > deadline:
                raise
            time.sleep(POLL_SECONDS)

    # The delete starts the teardown; a 404 shows that it has finished.
    while time.monotonic() < deadline:
        try:
            api(config, token, "GET", f"/databases/{database_id}")
        except httpx.HTTPStatusError as e:
            if e.response.status_code == 404:
                return
            raise
        time.sleep(POLL_SECONDS)
    raise TimeoutError(f"the database was still present after {TIMEOUT_SECONDS} seconds")
# --8<-- [end:delete]


# --8<-- [start:main]
def main() -> int:
    # Turn SIGTERM into a normal exit, so that the finally block runs.
    # Ctrl-C already raises KeyboardInterrupt, which does the same.
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(1))

    exit_code = 0
    token = None
    database_id = None
    try:
        config = settings()
        token = get_token(config)

        region, size = choose_placement(config, token)
        print(f"Region: {region}")
        print(f"Size: {size}")

        database = create_database(config, token, region, size)
        database_id = database["id"]
        print(f"Created database {database['display_name']}")

        wait_until_available(config, token, database_id)
        print("Database is available")
    # httpx.HTTPError covers connection failures and, through
    # raise_for_status(), error responses from the API.
    except (httpx.HTTPError, RuntimeError, TimeoutError) as e:
        print(f"Error: {e}", file=sys.stderr)
        exit_code = 1
    except KeyboardInterrupt:
        print("Interrupted", file=sys.stderr)
        exit_code = 130
    finally:
        # Delete the database whether the example succeeded, failed, or
        # was interrupted, because the service bills for it until then.
        if database_id is not None:
            try:
                delete_database(config, token, database_id)
                print("Deleted database")
            except (httpx.HTTPError, TimeoutError) as e:
                print(f"Error deleting database {database_id}: {e}", file=sys.stderr)
                exit_code = 1

    return exit_code


if __name__ == "__main__":
    sys.exit(main())
# --8<-- [end:main]
