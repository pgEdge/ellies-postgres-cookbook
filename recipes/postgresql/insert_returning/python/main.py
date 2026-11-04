"""
Ellie's Postgres Cookbook
Inserting rows and reading generated keys, using psycopg 3.

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


# --8<-- [start:setup]
def create_people(conn: psycopg.Connection) -> None:
    """Creates a temporary table whose id column the server fills in.

    GENERATED ALWAYS AS IDENTITY makes the server assign each id from a
    sequence, and refuses any attempt to supply one.
    """
    conn.execute(
        "CREATE TEMPORARY TABLE people ("
        "id int GENERATED ALWAYS AS IDENTITY PRIMARY KEY, "
        "name text NOT NULL)"
    )
# --8<-- [end:setup]


# --8<-- [start:add_person]
def add_person(conn: psycopg.Connection, name: str) -> int:
    """Inserts a row and returns the id that the server generated."""
    # RETURNING makes the INSERT produce a result row, like a SELECT, so
    # the program learns the new id without a second query. The name is a
    # parameter, which psycopg sends separately from the SQL text.
    row = conn.execute(
        "INSERT INTO people (name) VALUES (%s) RETURNING id",
        (name,),
    ).fetchone()
    return row[0]
# --8<-- [end:add_person]


# --8<-- [start:main]
def main() -> int:
    try:
        # The with block commits the transaction and closes the connection
        # when it exits normally, and rolls back if an error occurred.
        with connect() as conn:
            create_people(conn)
            for name in ("Jane Doe", "John Smith", "Alex Example"):
                person_id = add_person(conn, name)
                print(f"Inserted '{name}' with id {person_id}")
    # psycopg.Error is the base class for every error the driver raises,
    # including connection failures and errors reported by the server.
    except psycopg.Error as e:
        print(f"Database error: {e}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
# --8<-- [end:main]
