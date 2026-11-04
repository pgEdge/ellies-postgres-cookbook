"""
Ellie's Postgres Cookbook
Exchanging a client ID and secret for a pgEdge Starfleet access token,
using httpx.

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
def get_token(config: dict) -> dict:
    """Exchanges the client ID and secret for an access token.

    The token endpoint belongs to the account API, and accepts the OAuth
    2.0 client credentials grant as a JSON body.
    """
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
    return response.json()
# --8<-- [end:token]


# --8<-- [start:main]
def main() -> int:
    try:
        token = get_token(settings())
        # Never print the token itself; it grants access to the account.
        print(f"Token type: {token['token_type']}")
        print(f"Token length: {len(token['access_token'])} characters")
        print(f"Expires in: {token['expires_in']} seconds")
    # httpx.HTTPError covers connection failures and, through
    # raise_for_status(), error responses from the API.
    except httpx.HTTPError as e:
        print(f"API error: {e}", file=sys.stderr)
        return 1
    except RuntimeError as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
# --8<-- [end:main]
