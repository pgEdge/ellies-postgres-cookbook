"""
Ellie's Postgres Cookbook
Loading rows in bulk with COPY, using psycopg 3.

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


# --8<-- [start:create_table]
def create_table(conn: psycopg.Connection) -> None:
    """Creates a temporary table, which only this session can see and
    which PostgreSQL drops when the session ends."""
    conn.execute(
        "CREATE TEMPORARY TABLE items ("
        "id int PRIMARY KEY, name text NOT NULL)"
    )
# --8<-- [end:create_table]


# --8<-- [start:generate_rows]
def generate_rows(count: int):
    """Yields one (id, name) tuple for each row to load. A generator
    produces the rows one at a time, so the program never needs to hold
    them all in memory."""
    for item_id in range(1, count + 1):
        yield (item_id, f"item {item_id}")
# --8<-- [end:generate_rows]


# --8<-- [start:copy_rows]
def copy_rows(conn: psycopg.Connection, rows) -> int:
    """Loads the rows with COPY ... FROM STDIN and returns how many rows
    the server stored."""
    with conn.cursor() as cur:
        # copy() streams data to the server, which is much faster than
        # sending one INSERT for each row. write_row() converts each tuple
        # to the COPY text format, escaping tabs, newlines, and
        # backslashes in the values for us.
        with cur.copy("COPY items (id, name) FROM STDIN") as copy:
            for row in rows:
                copy.write_row(row)

        # The server reports the number of rows it stored once the copy
        # block has ended.
        return cur.rowcount
# --8<-- [end:copy_rows]


# --8<-- [start:summarise]
def summarise(conn: psycopg.Connection) -> tuple[int, int]:
    """Returns the number of rows in the table and the sum of their ids."""
    row = conn.execute("SELECT count(*), sum(id) FROM items").fetchone()
    return row[0], int(row[1])
# --8<-- [end:summarise]


# --8<-- [start:main]
def main() -> int:
    try:
        # The with block closes the connection when it exits, whether or
        # not an error occurred.
        with connect() as conn:
            create_table(conn)
            copied = copy_rows(conn, generate_rows(1000))
            print(f"Copied {copied} rows")

            count, total = summarise(conn)
            print(f"Rows in table: {count}")
            print(f"Sum of ids: {total}")
    # psycopg.Error is the base class for every error the driver raises,
    # including connection failures and errors reported by the server.
    except psycopg.Error as e:
        print(f"Database error: {e}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
# --8<-- [end:main]
