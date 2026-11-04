"""
Ellie's Postgres Cookbook
Registering a server to monitor with the AI DBA Workbench API, using httpx.

Copyright (c) 2026, pgEdge, Inc.
This code is released under the PostgreSQL License.
"""

# --8<-- [start:imports]
import os
import sys

import httpx
# --8<-- [end:imports]


# --8<-- [start:config]
SERVER_NAME = "cookbook-register-server"


def settings() -> dict:
    """Reads the settings from the environment.

    The or operator treats an empty variable as unset.
    """
    username = os.environ.get("WORKBENCH_USERNAME") or ""
    password = os.environ.get("WORKBENCH_PASSWORD") or ""
    connection_id = os.environ.get("WORKBENCH_CONNECTION_ID") or ""
    if not (username and password and connection_id):
        raise RuntimeError(
            "WORKBENCH_USERNAME, WORKBENCH_PASSWORD, and "
            "WORKBENCH_CONNECTION_ID must be set"
        )
    return {
        "base_url": (
            os.environ.get("WORKBENCH_URL") or "http://localhost:8080"
        ).rstrip("/"),
        "username": username,
        "password": password,
        "connection_id": connection_id,
        # The Workbench refuses to register a server without a password,
        # even one that uses trust authentication, so fall back to a
        # placeholder.
        "server_password": (
            os.environ.get("PGPASSWORD") or "unused-with-trust-authentication"
        ),
    }
# --8<-- [end:config]


# --8<-- [start:request]
def api(method: str, base_url: str, path: str, token: str | None = None,
        **kwargs) -> httpx.Response:
    """Sends a request to the API and returns the response.

    A request that the server rejects raises an error that includes the
    message from the server, which raise_for_status alone would leave out.
    """
    headers = {"Authorization": f"Bearer {token}"} if token else {}
    response = httpx.request(
        method, f"{base_url}/api/v1{path}", headers=headers, timeout=30,
        **kwargs,
    )
    if response.is_error:
        raise RuntimeError(
            f"{method} {path} failed with status {response.status_code}: "
            f"{response.text.strip()}"
        )
    return response
# --8<-- [end:request]


# --8<-- [start:login]
def login(base_url: str, username: str, password: str) -> str:
    """Logs in and returns the session token.

    The server returns the token in a session_token cookie, not in the
    body of the reply.
    """
    response = api("POST", base_url, "/auth/login",
                   json={"username": username, "password": password})
    token = response.cookies.get("session_token")
    if not token:
        raise RuntimeError("The login reply had no session_token cookie")
    return token
# --8<-- [end:login]


# --8<-- [start:lookup]
def get_connection(base_url: str, session: str, connection_id: str) -> dict:
    """Returns the details of an existing connection, which the program
    uses as the address of the server to register."""
    return api("GET", base_url, f"/connections/{connection_id}",
               session).json()
# --8<-- [end:lookup]


# --8<-- [start:register]
def register_server(base_url: str, session: str, name: str, template: dict,
                    password: str) -> int:
    """Registers a server and returns the ID of the new connection.

    The address comes from an existing connection. The request must
    include a password, and a description, which the server needs in
    version 1.0.0.
    """
    created = api("POST", base_url, "/connections", session, json={
        "name": name,
        "description": "Registered by the cookbook",
        "host": template["host"],
        "port": template["port"],
        "database_name": template["database_name"],
        "username": template["username"],
        "ssl_mode": template.get("ssl_mode"),
        "password": password,
        "is_monitored": True,
        "is_shared": False,
    }).json()
    return created["id"]
# --8<-- [end:register]


# --8<-- [start:list]
def find_connection(base_url: str, session: str, name: str) -> dict | None:
    """Returns the named connection from the list, or None if the list has
    no such connection."""
    connections = api("GET", base_url, "/connections", session).json()
    return next((c for c in connections if c["name"] == name), None)
# --8<-- [end:list]


# --8<-- [start:delete]
def delete_connection(base_url: str, session: str,
                      connection_id: int) -> None:
    """Deletes a connection by its ID."""
    api("DELETE", base_url, f"/connections/{connection_id}", session)
# --8<-- [end:delete]


# --8<-- [start:main]
def main() -> int:
    new_id = None
    try:
        config = settings()
        base_url = config["base_url"]

        session = login(base_url, config["username"], config["password"])
        template = get_connection(base_url, session, config["connection_id"])

        new_id = register_server(base_url, session, SERVER_NAME, template,
                                 config["server_password"])
        print(f"Registered the server '{SERVER_NAME}'")

        found = find_connection(base_url, session, SERVER_NAME)
        if found is None:
            raise RuntimeError("The new connection is missing from the list")
        monitored = str(found["is_monitored"]).lower()
        print(f"Found '{SERVER_NAME}' in the list (monitored: {monitored})")

        delete_connection(base_url, session, new_id)
        new_id = None
        print("Deleted the connection")

        if find_connection(base_url, session, SERVER_NAME) is not None:
            raise RuntimeError("The connection is still in the list")
        print("The connection is no longer in the list")
    # httpx.HTTPError covers failures to connect, and RuntimeError covers
    # replies that the server rejected or that lacked what we need.
    except (httpx.HTTPError, RuntimeError) as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1
    finally:
        # Delete the connection whether or not a later step failed, so
        # that a failed run does not leave a server registered.
        if new_id is not None:
            try:
                delete_connection(base_url, session, new_id)
            except (httpx.HTTPError, RuntimeError) as e:
                print(f"Error: could not delete the connection: {e}",
                      file=sys.stderr)
                return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
# --8<-- [end:main]
