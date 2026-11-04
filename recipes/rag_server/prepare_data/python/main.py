"""
Ellie's Postgres Cookbook
Preparing documents for the pgEdge RAG Server: embedding them with Ollama
and storing them in a pgvector table, using httpx and psycopg 3.

These examples are for pgEdge RAG Server 2.0.0.

Copyright (c) 2026, pgEdge, Inc.
This code is released under the PostgreSQL License.
"""

# --8<-- [start:imports]
import os
import sys

import httpx
import psycopg
# --8<-- [end:imports]


# --8<-- [start:config]
# The or operator treats an empty variable as unset, as libpq does.
OLLAMA_URL = (os.environ.get("OLLAMA_URL") or "http://localhost:11434").rstrip("/")
EMBED_MODEL = os.environ.get("EMBED_MODEL") or "nomic-embed-text"

# This recipe uses its own table, so that it never disturbs the table that
# a running pipeline reads.
TABLE = "cookbook_prepare_data"

# The documents to store; in a real application they come from your own
# data. The text is fictional.
DOCUMENTS = [
    (1, "Charging the Acme Gadget",
     "The Acme Gadget charges through its USB-C port. A full charge takes "
     "two hours, and a fully charged Acme Gadget runs for ten hours."),
    (2, "Resetting the Acme Gadget",
     "To reset the Acme Gadget to its factory settings, hold down the "
     "power button for eight seconds until the status light flashes red."),
    (3, "Warranty for the Acme Gadget",
     "The Acme Gadget comes with a two-year warranty that covers "
     "manufacturing defects but not accidental damage."),
]


def connection_settings() -> dict:
    """Reads the connection settings from the standard libpq environment
    variables, with defaults suitable for a local development server."""
    return {
        "host": os.environ.get("PGHOST") or "localhost",
        "port": os.environ.get("PGPORT") or "5432",
        "dbname": os.environ.get("PGDATABASE") or "postgres",
        "user": os.environ.get("PGUSER") or "postgres",
        "password": os.environ.get("PGPASSWORD") or None,
    }
# --8<-- [end:config]


# --8<-- [start:embed]
def embed(texts: list[str]) -> list[list[float]]:
    """Asks Ollama for the embedding of each text, in the same order."""
    # The embed endpoint accepts a list of texts, so one request embeds
    # every document.
    response = httpx.post(
        f"{OLLAMA_URL}/api/embed",
        json={"model": EMBED_MODEL, "input": texts},
        timeout=300.0,
    )
    response.raise_for_status()

    embeddings = response.json()["embeddings"]
    if len(embeddings) != len(texts):
        raise ValueError(
            f"Expected {len(texts)} embeddings, got {len(embeddings)}")
    return embeddings
# --8<-- [end:embed]


# --8<-- [start:table]
def create_table(conn: psycopg.Connection, dimensions: int) -> None:
    """Creates the table, replacing any earlier copy. The vector column
    must have the same number of dimensions as the embedding model."""
    conn.execute("CREATE EXTENSION IF NOT EXISTS vector")
    conn.execute(f"DROP TABLE IF EXISTS {TABLE}")
    # The table name is a constant and the dimensions are an integer, so
    # building them into the statement is safe; a statement cannot take
    # either as a parameter.
    conn.execute(
        f"""
        CREATE TABLE {TABLE} (
            id        integer PRIMARY KEY,
            title     text NOT NULL,
            content   text NOT NULL,
            embedding vector({int(dimensions)}) NOT NULL
        )
        """
    )
# --8<-- [end:table]


# --8<-- [start:insert]
def insert_documents(conn: psycopg.Connection,
                     embeddings: list[list[float]]) -> None:
    """Stores each document with its embedding."""
    rows = []
    for (doc_id, title, content), embedding in zip(DOCUMENTS, embeddings):
        # pgvector reads a vector from text such as '[0.1,0.2,0.3]', and
        # the cast tells the server how to interpret the parameter.
        vector = "[" + ",".join(str(value) for value in embedding) + "]"
        rows.append((doc_id, title, content, vector))

    with conn.cursor() as cur:
        cur.executemany(
            f"INSERT INTO {TABLE} (id, title, content, embedding) "
            "VALUES (%s, %s, %s, %s::vector)",
            rows,
        )
# --8<-- [end:insert]


# --8<-- [start:verify]
def describe_table(conn: psycopg.Connection) -> tuple[int, int]:
    """Returns the number of rows, and the number of dimensions of their
    embeddings."""
    row = conn.execute(
        f"SELECT count(*), max(vector_dims(embedding)) FROM {TABLE}"
    ).fetchone()
    return row[0], row[1]
# --8<-- [end:verify]


# --8<-- [start:cleanup]
def drop_table(conn: psycopg.Connection) -> None:
    """Removes the table. A real application keeps it, so that the RAG
    Server can read it."""
    conn.execute(f"DROP TABLE IF EXISTS {TABLE}")
# --8<-- [end:cleanup]


# --8<-- [start:main]
def main() -> int:
    try:
        embeddings = embed([content for _, _, content in DOCUMENTS])
        print(f"Embedded {len(embeddings)} documents with {EMBED_MODEL}")

        # Autocommit makes each statement take effect at once, so that the
        # transaction block below is the only place that groups them.
        with psycopg.connect(**connection_settings(), autocommit=True) as conn:
            try:
                with conn.transaction():
                    create_table(conn, len(embeddings[0]))
                    insert_documents(conn, embeddings)

                rows, dimensions = describe_table(conn)
                print(f"Stored {rows} rows with {dimensions}-dimension "
                      f"embeddings in {TABLE}")
            finally:
                # Remove the table whether or not a step failed.
                drop_table(conn)
    # httpx.HTTPError covers a failure to reach Ollama or an error status,
    # and psycopg.Error covers every error from the database driver.
    except (httpx.HTTPError, psycopg.Error, KeyError, ValueError) as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
# --8<-- [end:main]
