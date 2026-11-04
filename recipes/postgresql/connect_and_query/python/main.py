"""
Ellie's Postgres Cookbook
Connecting to PostgreSQL and running a scalar query, using psycopg 3.

Copyright (c) 2026, pgEdge, Inc.
This code is released under the PostgreSQL License.
"""

# --8<-- [start:imports]
import os
import sys

import psycopg
# --8<-- [end:imports]


def main() -> int:
    # --8<-- [start:config]
    # Read the connection settings from the standard libpq environment
    # variables, with defaults suitable for a local development server.
    # A password of None is simply not sent.
    conninfo = {
        "host": os.environ.get("PGHOST", "localhost"),
        "port": os.environ.get("PGPORT", "5432"),
        "dbname": os.environ.get("PGDATABASE", "postgres"),
        "user": os.environ.get("PGUSER", "postgres"),
        "password": os.environ.get("PGPASSWORD"),
    }
    # --8<-- [end:config]

    # --8<-- [start:connect]
    try:
        # The with block closes the connection when it exits, whether
        # or not an error occurred.
        with psycopg.connect(**conninfo) as conn:
            # --8<-- [end:connect]
            # --8<-- [start:query]
            # Always pass values as parameters rather than formatting
            # them into the SQL string; psycopg sends them separately,
            # which prevents SQL injection.
            row = conn.execute(
                "SELECT count(*) FROM pg_catalog.pg_type WHERE typname = %s",
                ("int4",),
            ).fetchone()
            count = row[0]

            print(f"Number of types named 'int4': {count}")
            # --8<-- [end:query]
    # --8<-- [start:errors]
    # psycopg.Error is the base class for every error the driver raises,
    # including connection failures and errors reported by the server.
    except psycopg.Error as e:
        print(f"Database error: {e}", file=sys.stderr)
        return 1
    # --8<-- [end:errors]

    return 0


if __name__ == "__main__":
    sys.exit(main())
