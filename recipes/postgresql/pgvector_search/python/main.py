"""
Ellie's Postgres Cookbook
Storing and searching vectors with pgvector, using psycopg 3.

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


# --8<-- [start:schema]
def create_schema(conn: psycopg.Connection) -> None:
    """Enables pgvector and creates a temporary table of colours."""
    conn.execute("CREATE EXTENSION IF NOT EXISTS vector")

    # vector(3) fixes the number of dimensions, one for each of the red,
    # green, and blue components. The temporary table disappears when the
    # session ends, so the program can run repeatedly.
    conn.execute(
        "CREATE TEMPORARY TABLE colours ("
        "name text PRIMARY KEY, rgb vector(3) NOT NULL)"
    )

    # An HNSW index speeds up nearest-neighbour searches; vector_l2_ops
    # matches the <-> (Euclidean distance) operator used by the search.
    conn.execute("CREATE INDEX ON colours USING hnsw (rgb vector_l2_ops)")
# --8<-- [end:schema]


# --8<-- [start:insert]
def insert_colours(conn: psycopg.Connection) -> None:
    """Stores five colours, each as a vector of its RGB components."""
    colours = [
        ("red", "[1,0,0]"),
        ("green", "[0,1,0]"),
        ("blue", "[0,0,1]"),
        ("yellow", "[1,1,0]"),
        ("white", "[1,1,1]"),
    ]
    with conn.cursor() as cur:
        # A vector travels as text in pgvector's [x,y,z] format, and the
        # ::vector cast converts it on the server, so the driver needs no
        # vector-specific support.
        cur.executemany(
            "INSERT INTO colours (name, rgb) VALUES (%s, %s::vector)",
            colours,
        )
# --8<-- [end:insert]


# --8<-- [start:search]
def nearest_colours(conn: psycopg.Connection, target: str,
                    count: int) -> list[str]:
    """Returns the names of the colours nearest to the target vector."""
    # <-> is the Euclidean (L2) distance operator, so ordering by it puts
    # the nearest colour first.
    rows = conn.execute(
        "SELECT name FROM colours ORDER BY rgb <-> %s::vector LIMIT %s",
        (target, count),
    ).fetchall()
    return [row[0] for row in rows]
# --8<-- [end:search]


# --8<-- [start:main]
def main() -> int:
    target = "[0.9,0.7,0.2]"
    try:
        # The with block closes the connection when it exits, whether or
        # not an error occurred.
        with connect() as conn:
            create_schema(conn)
            insert_colours(conn)
            print(f"Colours nearest to {target}:")
            for rank, name in enumerate(nearest_colours(conn, target, 3), 1):
                print(f"{rank}. {name}")
    # psycopg.Error is the base class for every error the driver raises,
    # including connection failures and errors reported by the server.
    except psycopg.Error as e:
        print(f"Database error: {e}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
# --8<-- [end:main]
