"""
Ellie's Postgres Cookbook
Listing the regions, sizes, and PostgreSQL versions that the pgEdge
Starfleet Managed API offers, using httpx.

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
def api_get(config: dict, token: str, path: str, **params):
    """Sends an authenticated GET request to the Managed API and returns
    the decoded JSON reply."""
    response = httpx.get(
        f"{config['base_url']}/managed/v1{path}",
        headers={"Authorization": f"Bearer {token}"},
        params=params,
        timeout=30,
    )
    response.raise_for_status()
    return response.json()
# --8<-- [end:api]


# --8<-- [start:regions]
def list_regions(config: dict, token: str) -> list[str]:
    """Returns the identifiers of the regions that can host a database."""
    return [r["region"] for r in api_get(config, token, "/regions")]
# --8<-- [end:regions]


# --8<-- [start:sizes]
def list_sizes(config: dict, token: str) -> list[str]:
    """Returns a description of each size, smallest first."""
    # The pricing option asks the API to include each size's price, which
    # takes a little longer because the API looks it up from billing.
    sizes = api_get(config, token, "/sizes", include="pricing")

    lines = []
    for size in sizes:
        line = (
            f"{size['name']}: {size['connections']} connections, "
            f"{size['storage_size']} storage"
        )
        # A size with no configured price omits the pricing field. The
        # amount is in the smallest unit of the currency, such as cents.
        price = size.get("pricing")
        if price:
            line += (
                f", {price['price_amount'] / 100:.2f} "
                f"{price['currency']} per {price['billing_interval']}"
            )
        lines.append(line)
    return lines
# --8<-- [end:sizes]


# --8<-- [start:versions]
def list_versions(config: dict, token: str) -> list[str]:
    """Returns the PostgreSQL major versions, newest first, marking the
    one that a new database gets by default."""
    return [
        v["version"] + (" (default)" if v["default"] else "")
        for v in api_get(config, token, "/pg-versions")
    ]
# --8<-- [end:versions]


# --8<-- [start:main]
def main() -> int:
    try:
        config = settings()
        token = get_token(config)

        print("Regions:")
        for region in list_regions(config, token):
            print(f"  {region}")

        print("Sizes (smallest first):")
        for size in list_sizes(config, token):
            print(f"  {size}")

        print("PostgreSQL versions:")
        for version in list_versions(config, token):
            print(f"  {version}")
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
