"""
Ellie's Postgres Cookbook
Using a connection pool, with psycopg 3 and psycopg_pool.

Copyright (c) 2026, pgEdge, Inc.
This code is released under the PostgreSQL License.
"""

# --8<-- [start:imports]
import os
import sys
from concurrent.futures import ThreadPoolExecutor

import psycopg
from psycopg_pool import ConnectionPool
# --8<-- [end:imports]


# --8<-- [start:config]
# The most connections that the pool opens at any one time.
POOL_SIZE = 2


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


# --8<-- [start:pool]
def create_pool() -> ConnectionPool:
    """Creates a pool that holds at most POOL_SIZE connections."""
    # The pool opens its connections in background threads. A request for
    # a connection waits for up to timeout seconds when both connections
    # are busy, and then raises an error rather than waiting forever.
    pool = ConnectionPool(
        kwargs=connection_settings(),
        min_size=1,
        max_size=POOL_SIZE,
        timeout=5,
        open=True,
    )

    # wait() blocks until the pool has opened its first connection, and
    # raises an error if that takes longer than the timeout, for example
    # because the server is unreachable. Close the pool before re-raising,
    # so that its background threads stop.
    try:
        pool.wait(timeout=5)
    except psycopg.Error:
        pool.close()
        raise
    return pool
# --8<-- [end:pool]


# --8<-- [start:query]
def run_query(pool: ConnectionPool, number: int) -> int:
    """Borrows a connection from the pool, and returns the number back."""
    # The with block borrows a connection and returns it to the pool when
    # it exits, whether or not an error occurred; it does not close it.
    with pool.connection() as conn:
        # Pass values as parameters rather than formatting them into the
        # SQL string. The cast gives the parameter a type, which the
        # server cannot infer from SELECT $1 alone.
        row = conn.execute("SELECT %s::int", (number,)).fetchone()
        return row[0]
# --8<-- [end:query]


# --8<-- [start:main]
def main() -> int:
    try:
        # The with block closes the pool, and every connection in it,
        # when it exits.
        with create_pool() as pool:
            # Five threads ask for a connection at once, but the pool has
            # only two, so the other threads wait their turn.
            with ThreadPoolExecutor(max_workers=5) as executor:
                results = list(
                    executor.map(lambda n: run_query(pool, n), range(1, 6))
                )
        print(f"Ran {len(results)} queries through a pool of at most "
              f"{POOL_SIZE} connections")
        print(f"Sum of results: {sum(results)}")
    # psycopg.Error is the base class for every error the driver raises,
    # including connection failures and errors reported by the server. The
    # pool raises PoolTimeout, a subclass, when it cannot supply a
    # connection in time.
    except psycopg.Error as e:
        print(f"Database error: {e}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
# --8<-- [end:main]
