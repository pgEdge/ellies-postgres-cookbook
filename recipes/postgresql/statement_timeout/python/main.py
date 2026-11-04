"""
Ellie's Postgres Cookbook
Setting a server-side statement timeout, using psycopg 3.

Copyright (c) 2026, pgEdge, Inc.
This code is released under the PostgreSQL License.
"""

# --8<-- [start:imports]
import os
import sys

import psycopg
# --8<-- [end:imports]


# --8<-- [start:config]
# The SQLSTATE code that the server reports when it cancels a statement,
# whether because of a timeout or because a client asked for the cancel.
QUERY_CANCELED = "57014"


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
    """Opens a connection with the settings from the environment.

    Autocommit mode keeps each statement in its own transaction, so a
    cancelled statement does not leave the session in a failed
    transaction.
    """
    return psycopg.connect(**connection_settings(), autocommit=True)
# --8<-- [end:connect]


# --8<-- [start:timeout]
def set_statement_timeout(conn: psycopg.Connection, timeout: str) -> None:
    """Sets the statement timeout for the rest of the session."""
    # SET cannot take a parameter, but set_config() is an ordinary
    # function, so the value can be sent safely. The final argument,
    # false, makes the setting last for the session rather than for the
    # current transaction.
    conn.execute(
        "SELECT set_config('statement_timeout', %s, false)", (timeout,)
    )


def sleep_exceeds_timeout(conn: psycopg.Connection) -> bool:
    """Runs a statement that outlasts the timeout, and returns True if
    the server cancelled it."""
    try:
        conn.execute("SELECT pg_sleep(5)")
    except psycopg.Error as e:
        # Only a cancelled statement is expected here; any other error
        # is a real failure, so it is raised again.
        if e.sqlstate != QUERY_CANCELED:
            raise
        return True
    return False


def is_usable(conn: psycopg.Connection) -> bool:
    """Returns True if the session can still run a statement."""
    return conn.execute("SELECT 1").fetchone()[0] == 1
# --8<-- [end:timeout]


# --8<-- [start:main]
def main() -> int:
    try:
        # The with block closes the connection when it exits, whether or
        # not an error occurred.
        with connect() as conn:
            set_statement_timeout(conn, "100ms")
            if sleep_exceeds_timeout(conn):
                print("Query cancelled after exceeding the statement "
                      "timeout")
            print(f"Connection still usable: {str(is_usable(conn)).lower()}")
    # psycopg.Error is the base class for every error the driver raises,
    # including connection failures and errors reported by the server.
    except psycopg.Error as e:
        print(f"Database error: {e}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
# --8<-- [end:main]
