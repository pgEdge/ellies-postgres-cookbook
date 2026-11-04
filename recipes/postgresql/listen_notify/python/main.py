"""
Ellie's Postgres Cookbook
Listening for notifications with LISTEN and NOTIFY, using psycopg 3.

Copyright (c) 2026, pgEdge, Inc.
This code is released under the PostgreSQL License.
"""

# --8<-- [start:imports]
import os
import sys

import psycopg
# --8<-- [end:imports]


# --8<-- [start:config]
CHANNEL = "cookbook_listen_notify"
TIMEOUT_SECONDS = 5


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

    Autocommit mode matters here: without it, psycopg would open a
    transaction around LISTEN, and the subscription would not take effect
    until that transaction committed. A transaction around NOTIFY would
    likewise hold the notification back until the commit.
    """
    return psycopg.connect(**connection_settings(), autocommit=True)
# --8<-- [end:connect]


# --8<-- [start:listen]
def listen(conn: psycopg.Connection, channel: str) -> None:
    """Subscribes the connection to a channel."""
    # LISTEN takes an identifier rather than a value, so it cannot use a
    # parameter; psycopg.sql.Identifier quotes the name safely.
    conn.execute(psycopg.sql.SQL("LISTEN {}").format(
        psycopg.sql.Identifier(channel)))
# --8<-- [end:listen]


# --8<-- [start:notify]
def notify(conn: psycopg.Connection, channel: str, payload: str) -> None:
    """Sends a notification to every connection listening on a channel."""
    # pg_notify() takes the channel and payload as ordinary parameters,
    # unlike the NOTIFY command.
    conn.execute("SELECT pg_notify(%s, %s)", (channel, payload))
# --8<-- [end:notify]


# --8<-- [start:wait]
def wait_for_notification(conn: psycopg.Connection, timeout: float):
    """Waits for one notification, and returns it, or None on timeout."""
    # notifies() yields notifications as they arrive, and ends when the
    # timeout passes without one. stop_after ends it after the first.
    for notification in conn.notifies(timeout=timeout, stop_after=1):
        return notification
    return None
# --8<-- [end:wait]


# --8<-- [start:main]
def main() -> int:
    try:
        # Each with block closes its connection when it exits, whether or
        # not an error occurred.
        with connect() as listener, connect() as sender:
            listen(listener, CHANNEL)
            print(f"Listening on channel '{CHANNEL}'")

            notify(sender, CHANNEL, "Hello from connection B")

            notification = wait_for_notification(listener, TIMEOUT_SECONDS)
            if notification is None:
                print(f"No notification within {TIMEOUT_SECONDS} seconds",
                      file=sys.stderr)
                return 1
            print(f"Received notification on '{notification.channel}': "
                  f"{notification.payload}")
    # psycopg.Error is the base class for every error the driver raises,
    # including connection failures and errors reported by the server.
    except psycopg.Error as e:
        print(f"Database error: {e}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
# --8<-- [end:main]
