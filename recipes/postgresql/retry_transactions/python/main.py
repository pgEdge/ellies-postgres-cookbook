"""
Ellie's Postgres Cookbook
Retrying a transaction after a serialisation failure, using psycopg 3.

Copyright (c) 2026, pgEdge, Inc.
This code is released under the PostgreSQL License.
"""

# --8<-- [start:imports]
import os
import sys
import time

import psycopg
# --8<-- [end:imports]


# --8<-- [start:config]
# The SQLSTATE codes that mean "run the transaction again": 40001 is a
# serialisation failure and 40P01 is a deadlock.
RETRYABLE = {"40001", "40P01"}
MAX_ATTEMPTS = 5


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

    Autocommit mode means that the program, rather than the driver,
    decides where each transaction begins and ends.
    """
    return psycopg.connect(**connection_settings(), autocommit=True)
# --8<-- [end:connect]


# --8<-- [start:setup]
def create_table(conn: psycopg.Connection) -> None:
    """Creates the shared counter table, with a single row set to zero.

    The table must be visible to a second connection, so it cannot be
    temporary; the name is specific to this recipe, and any earlier copy
    is dropped first.
    """
    drop_table(conn)
    conn.execute(
        "CREATE TABLE cookbook_retry_transactions "
        "(id int PRIMARY KEY, value int NOT NULL)"
    )
    conn.execute(
        "INSERT INTO cookbook_retry_transactions (id, value) VALUES (%s, %s)",
        (1, 0),
    )


def drop_table(conn: psycopg.Connection) -> None:
    """Drops the shared counter table if it exists."""
    conn.execute("DROP TABLE IF EXISTS cookbook_retry_transactions")
# --8<-- [end:setup]


# --8<-- [start:work]
def increment_counter(conn: psycopg.Connection, attempt: int) -> None:
    """Reads the counter and writes back the value plus one."""
    value = conn.execute(
        "SELECT value FROM cookbook_retry_transactions WHERE id = %s",
        (1,),
    ).fetchone()[0]

    # Simulate another client by updating the row from a second
    # connection, after this transaction has read the row but before it
    # writes. This happens on the first attempt only.
    if attempt == 1:
        with connect() as other:
            other.execute(
                "UPDATE cookbook_retry_transactions "
                "SET value = value + 1 WHERE id = %s",
                (1,),
            )

    # Under REPEATABLE READ, updating a row that another transaction
    # changed and committed since this transaction's snapshot was taken
    # fails with SQLSTATE 40001.
    conn.execute(
        "UPDATE cookbook_retry_transactions SET value = %s WHERE id = %s",
        (value + 1, 1),
    )


def read_counter(conn: psycopg.Connection) -> int:
    """Returns the current value of the counter."""
    row = conn.execute(
        "SELECT value FROM cookbook_retry_transactions WHERE id = %s",
        (1,),
    ).fetchone()
    return row[0]
# --8<-- [end:work]


# --8<-- [start:retry]
def run_with_retry(conn: psycopg.Connection, work) -> None:
    """Runs work(conn, attempt) in a REPEATABLE READ transaction, and runs
    it again if the server reports a serialisation failure or a deadlock.
    """
    conn.isolation_level = psycopg.IsolationLevel.REPEATABLE_READ

    for attempt in range(1, MAX_ATTEMPTS + 1):
        try:
            # The transaction block commits when it exits normally, and
            # rolls back if an exception escapes it.
            with conn.transaction():
                work(conn, attempt)
        except psycopg.Error as e:
            # Any other error, or running out of attempts, is a real
            # failure that the caller must handle.
            if e.sqlstate not in RETRYABLE or attempt == MAX_ATTEMPTS:
                raise
            print(f"Attempt {attempt}: serialisation failure, retrying")
            # A short, growing pause gives the competing transaction time
            # to finish.
            time.sleep(0.05 * attempt)
        else:
            print(f"Attempt {attempt}: committed")
            return
# --8<-- [end:retry]


# --8<-- [start:main]
def main() -> int:
    try:
        # The with block closes the connection when it exits, whether or
        # not an error occurred.
        with connect() as conn:
            try:
                create_table(conn)
                run_with_retry(conn, increment_counter)
                print(f"Counter value: {read_counter(conn)}")
            finally:
                # Drop the shared table even if the work failed.
                drop_table(conn)
    # psycopg.Error is the base class for every error the driver raises,
    # including connection failures and errors reported by the server.
    except psycopg.Error as e:
        print(f"Database error: {e}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
# --8<-- [end:main]
