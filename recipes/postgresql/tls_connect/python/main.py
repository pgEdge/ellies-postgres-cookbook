"""
Ellie's Postgres Cookbook
Connecting to PostgreSQL over TLS with full verification, using psycopg 3.

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
    a password of None is simply not sent. PGSSLROOTCERT has no default,
    because verification is meaningless without the certificate of the
    authority that signed the server certificate.
    """
    root_cert = os.environ.get("PGSSLROOTCERT")
    if not root_cert:
        raise RuntimeError("PGSSLROOTCERT must name the root certificate")

    return {
        "host": os.environ.get("PGHOST") or "localhost",
        "port": os.environ.get("PGPORT") or "5432",
        "dbname": os.environ.get("PGDATABASE") or "postgres",
        "user": os.environ.get("PGUSER") or "postgres",
        "password": os.environ.get("PGPASSWORD") or None,
        # verify-full checks that the certificate chains to the root
        # certificate and that it matches the host name. Weaker modes,
        # such as require, encrypt the connection without proving who is
        # on the other end.
        "sslmode": "verify-full",
        "sslrootcert": root_cert,
    }
# --8<-- [end:config]


# --8<-- [start:connect]
def connect() -> psycopg.Connection:
    """Opens a verified TLS connection with the settings from the
    environment. The connection fails if verification fails."""
    return psycopg.connect(**connection_settings())
# --8<-- [end:connect]


# --8<-- [start:query]
def connection_is_encrypted(conn: psycopg.Connection) -> bool:
    """Asks the server whether this connection uses TLS."""
    # pg_stat_ssl has one row for each connection; pg_backend_pid()
    # identifies the one that belongs to this session. The version column
    # holds the protocol version, such as TLSv1.3.
    row = conn.execute(
        "SELECT ssl, version FROM pg_catalog.pg_stat_ssl "
        "WHERE pid = pg_backend_pid()"
    ).fetchone()
    return row[0]
# --8<-- [end:query]


# --8<-- [start:main]
def main() -> int:
    try:
        # The with block closes the connection when it exits, whether or
        # not an error occurred.
        with connect() as conn:
            encrypted = connection_is_encrypted(conn)
            print(f"Connection is encrypted: {str(encrypted).lower()}")
            # Reaching this line means that verify-full succeeded; a
            # certificate or host name mismatch raises an error instead.
            print("Server certificate verified: true")
    # psycopg.Error is the base class for every error the driver raises,
    # including connection and certificate verification failures.
    except (psycopg.Error, RuntimeError) as e:
        print(f"Database error: {e}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
# --8<-- [end:main]
