"""
Ellie's Postgres Cookbook
Using transactions to move money between accounts, using psycopg 3.

Copyright (c) 2026, pgEdge, Inc.
This code is released under the PostgreSQL License.
"""

# --8<-- [start:imports]
import os
import sys

import psycopg
from psycopg import errors
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
    """Opens a connection with the settings from the environment.

    By default psycopg opens a transaction before the first statement and
    keeps it open until the program commits. Autocommit mode turns that
    off, so that each statement commits by itself and the program decides
    exactly where each transaction begins and ends.
    """
    return psycopg.connect(**connection_settings(), autocommit=True)
# --8<-- [end:connect]


# --8<-- [start:setup]
def create_accounts(conn: psycopg.Connection) -> None:
    """Creates a temporary table of two accounts. The CHECK constraint
    stops any balance from going below zero."""
    conn.execute(
        "CREATE TEMPORARY TABLE accounts ("
        "id int PRIMARY KEY, "
        "balance int NOT NULL CHECK (balance >= 0))"
    )
    conn.execute("INSERT INTO accounts VALUES (1, 100), (2, 50)")
# --8<-- [end:setup]


# --8<-- [start:transfer]
def transfer(conn: psycopg.Connection, source: int, target: int,
             amount: int) -> None:
    """Moves money between two accounts in a single transaction."""
    # The with block begins a transaction, commits it when the block ends
    # normally, and rolls it back if an exception leaves the block.
    with conn.transaction():
        # Credit the target first, so that a failure of the debit shows
        # that the rollback undoes the credit as well.
        conn.execute(
            "UPDATE accounts SET balance = balance + %s WHERE id = %s",
            (amount, target),
        )
        conn.execute(
            "UPDATE accounts SET balance = balance - %s WHERE id = %s",
            (amount, source),
        )
# --8<-- [end:transfer]


# --8<-- [start:balance]
def get_balance(conn: psycopg.Connection, account: int) -> int:
    """Returns the balance of the given account."""
    row = conn.execute(
        "SELECT balance FROM accounts WHERE id = %s", (account,)
    ).fetchone()
    return row[0]
# --8<-- [end:balance]


# --8<-- [start:main]
def main() -> int:
    try:
        # The with block closes the connection when it exits, whether or
        # not an error occurred.
        with connect() as conn:
            create_accounts(conn)

            transfer(conn, 1, 2, 30)
            print("Transferred 30 from account 1 to account 2")

            try:
                transfer(conn, 1, 2, 500)
                print("Transferred 500 from account 1 to account 2")
            # CheckViolation is SQLSTATE 23514. The transaction has already
            # been rolled back, so this is an expected outcome; any other
            # error is not, and reaches the handler below.
            except errors.CheckViolation:
                print("Transfer of 500 from account 1 to account 2 "
                      "failed and was rolled back")

            for account in (1, 2):
                print(f"Account {account} balance: "
                      f"{get_balance(conn, account)}")
    # psycopg.Error is the base class for every error the driver raises,
    # including connection failures and errors reported by the server.
    except psycopg.Error as e:
        print(f"Database error: {e}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
# --8<-- [end:main]
