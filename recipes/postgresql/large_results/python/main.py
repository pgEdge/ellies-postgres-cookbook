"""
Ellie's Postgres Cookbook
Reading a large result in batches, using psycopg 3.

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


# --8<-- [start:read_batches]
BATCH_SIZE = 1000


def read_in_batches(conn: psycopg.Connection) -> tuple[int, int]:
    """Reads every row of a large result, one batch at a time, and
    returns the number of rows and the sum of their values."""
    rows_read = 0
    total = 0

    # Giving the cursor a name makes it a server-side cursor: the server
    # keeps the result and sends rows only as the program asks for them.
    # An ordinary cursor would transfer all 100,000 rows to the client
    # before the first fetch. The cursor lives inside the transaction
    # that psycopg opens for us, and the with block closes it.
    with conn.cursor(name="large_results") as cur:
        cur.execute("SELECT g FROM generate_series(1, 100000) AS g")

        while True:
            # fetchmany() asks the server for the next batch, and returns
            # an empty list once the result is exhausted.
            batch = cur.fetchmany(BATCH_SIZE)
            if not batch:
                break

            for (value,) in batch:
                rows_read += 1
                total += value

    return rows_read, total
# --8<-- [end:read_batches]


# --8<-- [start:main]
def main() -> int:
    try:
        # The with block closes the connection when it exits, whether or
        # not an error occurred.
        with connect() as conn:
            rows_read, total = read_in_batches(conn)
            print(f"Rows read: {rows_read}")
            print(f"Sum of values: {total}")
    # psycopg.Error is the base class for every error the driver raises,
    # including connection failures and errors reported by the server.
    except psycopg.Error as e:
        print(f"Database error: {e}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
# --8<-- [end:main]
