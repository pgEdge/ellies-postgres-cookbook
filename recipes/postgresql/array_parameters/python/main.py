"""
Ellie's Postgres Cookbook
Passing a list of values as a single array parameter, using psycopg 3.

Copyright (c) 2026, pgEdge, Inc.
This code is released under the PostgreSQL License.
"""

# --8<-- [start:imports]
import os
import sys

import psycopg
# --8<-- [end:imports]


# --8<-- [start:config]
def connection_settings() -> dict:
    """Reads the connection settings from the standard libpq environment
    variables, with defaults suitable for a local development server.

    The or operator treats an empty variable as unset, as libpq does, and
    a password of None is simply not sent.
    """
    return {
        "host": os.environ.get("PGHOST") or "localhost",
        "port": os.environ.get("PGPORT") or "5432",
        "dbname": os.environ.get("PGDATABASE") or "postgres",
        "user": os.environ.get("PGUSER") or "postgres",
        "password": os.environ.get("PGPASSWORD") or None,
    }
# --8<-- [end:config]


# --8<-- [start:connect]
def connect() -> psycopg.Connection:
    """Opens a connection with the settings from the environment."""
    return psycopg.connect(**connection_settings())
# --8<-- [end:connect]


# --8<-- [start:query]
def find_types(conn: psycopg.Connection, names: list[str]) -> list[str]:
    """Returns the names from the list that exist as data types."""
    # The whole list travels as one array parameter, so the SQL text is
    # the same however many values the list holds. psycopg converts a
    # Python list into a PostgreSQL array.
    rows = conn.execute(
        "SELECT typname FROM pg_catalog.pg_type "
        "WHERE typname = ANY(%s) ORDER BY typname",
        (names,),
    ).fetchall()
    return [row[0] for row in rows]
# --8<-- [end:query]


# --8<-- [start:main]
def main() -> int:
    wanted = ["int4", "text", "bool", "no_such_type"]
    try:
        # The with block closes the connection when it exits, whether or
        # not an error occurred.
        with connect() as conn:
            found = find_types(conn, wanted)
            print(f"Found {len(found)} of {len(wanted)} types: "
                  f"{', '.join(found)}")
    # psycopg.Error is the base class for every error the driver raises,
    # including connection failures and errors reported by the server.
    except psycopg.Error as e:
        print(f"Database error: {e}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
# --8<-- [end:main]
