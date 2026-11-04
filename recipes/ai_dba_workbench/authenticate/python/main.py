"""
Ellie's Postgres Cookbook
Authenticating with the AI DBA Workbench API, using httpx.

Copyright (c) 2026, pgEdge, Inc.
This code is released under the PostgreSQL License.
"""

# --8<-- [start:imports]
import os
import sys

import httpx
# --8<-- [end:imports]


# --8<-- [start:config]
def settings() -> dict:
    """Reads the settings from the environment.

    The or operator treats an empty variable as unset.
    """
    username = os.environ.get("WORKBENCH_USERNAME") or ""
    password = os.environ.get("WORKBENCH_PASSWORD") or ""
    if not username or not password:
        raise RuntimeError(
            "WORKBENCH_USERNAME and WORKBENCH_PASSWORD must be set"
        )
    return {
        "base_url": (
            os.environ.get("WORKBENCH_URL") or "http://localhost:8080"
        ).rstrip("/"),
        "username": username,
        "password": password,
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


# --8<-- [start:user_info]
def user_info(base_url: str, token: str) -> str:
    """Returns the user that a token belongs to, with its superuser flag."""
    info = api("GET", base_url, "/user/info", token).json()
    superuser = str(info["is_superuser"]).lower()
    return f"{info['username']} (superuser: {superuser})"
# --8<-- [end:user_info]


# --8<-- [start:create_token]
def create_token(base_url: str, session: str, owner: str,
                 annotation: str) -> tuple[int, str]:
    """Creates an API token for a user and returns its ID and its value.

    The server shows the value only once. The token expires after an hour.
    """
    created = api("POST", base_url, "/rbac/tokens", session, json={
        "owner_username": owner,
        "annotation": annotation,
        "expires_in": "1h",
    }).json()
    return created["id"], created["token"]
# --8<-- [end:create_token]


# --8<-- [start:delete_token]
def delete_token(base_url: str, session: str, token_id: int) -> None:
    """Deletes an API token by its ID."""
    api("DELETE", base_url, f"/rbac/tokens/{token_id}", session)
# --8<-- [end:delete_token]


# --8<-- [start:main]
def main() -> int:
    token_id = None
    try:
        config = settings()
        base_url = config["base_url"]

        session = login(base_url, config["username"], config["password"])
        print("Logged in with a session token")
        print(f"Session token belongs to {user_info(base_url, session)}")

        token_id, api_token = create_token(
            base_url, session, config["username"], "cookbook-authenticate"
        )
        print("Created the API token 'cookbook-authenticate'")
        print(f"API token belongs to {user_info(base_url, api_token)}")
    # httpx.HTTPError covers failures to connect, and RuntimeError covers
    # replies that the server rejected or that lacked what we need.
    except (httpx.HTTPError, RuntimeError) as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1
    finally:
        # Delete the token whether or not a later step failed, so that a
        # failed run does not leave a token behind.
        if token_id is not None:
            try:
                delete_token(base_url, session, token_id)
                print("Deleted the API token")
            except (httpx.HTTPError, RuntimeError) as e:
                print(f"Error: could not delete the token: {e}",
                      file=sys.stderr)
                return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
# --8<-- [end:main]
