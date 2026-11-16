# Vectorizing a Table

This recipe shows how to keep embeddings for a text column up to date
without writing any application code. The script creates a table with three
rows, and calls `pgedge_vectorizer.enable_vectorization()` for its text
column. The extension splits each row into chunks, stores the chunks in a
table of its own, and queues them; a background worker then asks the
embedding model for an embedding of each chunk. The script waits for the
worker, reports what the extension created, and then removes everything
again.

These examples are for pgEdge Vectorizer 1.1.

The script prints the following output:

```text
Chunk table: cookbook_enable_vectorization_content_chunks
Chunks: 3
Chunks with embeddings: 3
Embedding dimensions: 768
```

## Preparing the Ingredients

The script needs a PostgreSQL server with the `vector` (pgvector) and
`pgedge_vectorizer` extensions installed in the database, and an embedding
model that the server can reach. Creating the `pgedge_vectorizer` extension
requires a superuser, and the server must load the extension's library at
start-up. The examples use Ollama with the `nomic-embed-text` model, which
returns embeddings with 768 dimensions.

The following table lists the server settings that the examples use:

| Setting                            | Value                         |
|------------------------------------|-------------------------------|
| `shared_preload_libraries`         | `pgedge_vectorizer`           |
| `pgedge_vectorizer.provider`       | `ollama`                      |
| `pgedge_vectorizer.api_url`        | `http://localhost:11434`      |
| `pgedge_vectorizer.model`          | `nomic-embed-text`            |
| `pgedge_vectorizer.databases`      | `postgres`                    |

The background worker only processes the queue in the databases that
`pgedge_vectorizer.databases` lists, so the list must include the database
that the script connects to. Change `pgedge_vectorizer.api_url` to the
address at which the server can reach Ollama. The following commands
create the extensions once the server is running with these settings:

```sql
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS pgedge_vectorizer;
```

## Configuring psql

The script prints plain lines, so that its output is easy to read and to
compare, and it hides the `NOTICE` messages that the Vectorizer functions
raise. A failed step must not stop the script before the cleanup at the
end, so the script turns off `ON_ERROR_STOP` until the cleanup starts. The
following code shows the settings:

```sql
-- Print plain lines, and hide the NOTICE messages that the Vectorizer
-- functions raise as they work.
\pset format unaligned
\pset tuples_only on
SET client_min_messages = warning;

-- Keep going after a failed step, so that the cleanup at the end of the
-- script always runs; the script fails at the end instead.
\set ON_ERROR_STOP off
```

## Creating the Table

The background worker reads the chunks in a session of its own, so the
table must be an ordinary table that every session can see, rather than a
temporary table. The table also needs a primary key, which the extension
uses to link each chunk back to its row. The following code creates the
table and inserts three rows:

```sql
-- The background worker reads the rows in its own session, so the table
-- must be an ordinary table rather than a temporary one.
CREATE TABLE cookbook_enable_vectorization (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    content text NOT NULL
);

INSERT INTO cookbook_enable_vectorization (content) VALUES
    ('Knead the bread dough for ten minutes, then leave it to rise in a warm kitchen.'),
    ('Jupiter is the largest planet in the solar system, with dozens of moons.'),
    ('PostgreSQL stores data in tables and answers questions written in SQL.');
```

## Enabling Vectorization

The `enable_vectorization()` function takes the table and the name of the
text column. The function creates a chunk table named after the table and
the column, with an HNSW index for cosine distance. The function also adds
triggers that chunk and queue each row that an `INSERT` or `UPDATE`
changes, and that remove the chunks of deleted rows, and it chunks and
queues the rows that the table already holds. Optional
arguments choose the chunking strategy, the chunk size and the overlap;
without them, the extension uses the server's default settings. The
following code enables vectorization for the `content` column:

```sql
-- Create the chunk table, its indexes and the triggers, and queue the
-- existing rows for embedding. The extension asks the embedding model for
-- its dimension when the call does not give one. The function returns
-- void, so the query selects no columns, which prints nothing.
SELECT FROM pgedge_vectorizer.enable_vectorization(
    'cookbook_enable_vectorization', 'content');
```

## Waiting for the Embeddings

The background worker embeds the queued chunks in batches, so the
embeddings appear shortly after the rows rather than at once. The script
waits in a `DO` block that checks the queue once a second, through the
`pgedge_vectorizer.queue_status` and `pgedge_vectorizer.failed_items`
views. The block stops when no item for the chunk table is pending or in
progress, and raises an error if an item fails or the wait passes five
minutes. A model that is not yet in memory can take some time to answer its
first request, particularly on a server without a GPU. The following code
waits for the worker:

```sql
-- Wait until the background worker has embedded every queued chunk of the
-- table, and fail if an item fails or the wait takes over five minutes. A
-- cold embedding model can take a while to answer its first request.
DO $$
DECLARE
    deadline timestamptz := clock_timestamp() + interval '300 seconds';
    failure text;
BEGIN
    LOOP
        SELECT error_message INTO failure
        FROM pgedge_vectorizer.failed_items
        WHERE chunk_table = 'cookbook_enable_vectorization_content_chunks'
        LIMIT 1;
        IF FOUND THEN
            RAISE EXCEPTION 'embedding failed: %', failure;
        END IF;

        EXIT WHEN NOT EXISTS (
            SELECT 1
            FROM pgedge_vectorizer.queue_status
            WHERE chunk_table = 'cookbook_enable_vectorization_content_chunks'
              AND status IN ('pending', 'processing'));

        IF clock_timestamp() > deadline THEN
            -- Report the latest error that the worker recorded for the
            -- table; a request that hangs records none.
            SELECT error_message INTO failure
            FROM pgedge_vectorizer.queue
            WHERE chunk_table = 'cookbook_enable_vectorization_content_chunks'
              AND error_message IS NOT NULL
            ORDER BY next_retry_at DESC NULLS LAST, id DESC
            LIMIT 1;
            RAISE EXCEPTION 'timed out waiting for the embeddings: %',
                coalesce(failure, 'no error recorded; check that '
                    || 'pgedge_vectorizer.databases lists this database '
                    || 'and that pgedge_vectorizer.api_url reaches the '
                    || 'embedding provider');
        END IF;
        PERFORM pg_sleep(1);
    END LOOP;
END
$$;
```

## Inspecting the Chunks

The `pgedge_vectorizer.vectorizers` table records the chunk table for each
vectorized column. Each chunk row holds the chunk's text, the primary key
of its source row in `source_id`, and the embedding. The rows in this
example are short, so each fits in a single chunk. The following code
reports the chunk table, the number of chunks, and the dimensions of an
embedding:

```sql
-- The registry records the chunk table that the extension created.
SELECT 'Chunk table: ' || chunk_table
FROM pgedge_vectorizer.vectorizers
WHERE source_table = 'cookbook_enable_vectorization';

-- Each short row fits in a single chunk, and each chunk now has an
-- embedding with one value for each dimension of the model.
SELECT 'Chunks: ' || count(*)
FROM cookbook_enable_vectorization_content_chunks;
SELECT 'Chunks with embeddings: ' || count(embedding)
FROM cookbook_enable_vectorization_content_chunks;
SELECT 'Embedding dimensions: ' || vector_dims(embedding)
FROM cookbook_enable_vectorization_content_chunks
LIMIT 1;
```

## Cleaning Up

The `disable_vectorization()` function drops the triggers, removes the
table's pending items from the queue, and with `drop_chunk_table` drops the
chunk table too. The function leaves the table's completed items in the
queue, and the extension's `clear_completed()` function deletes completed
items only once they are older than 24 hours by default. Calling
`clear_completed(0)` removes them at once, but for every vectorized table
in the database, so the script deletes only the items for its own chunk
table instead.

The cleanup turns `ON_ERROR_STOP` back on, so that a failure during the
cleanup stops the script with an error. Finally, the script checks the
`LAST_ERROR_SQLSTATE` variable, in which psql keeps the SQLSTATE code of the
most recent error, and raises an error if an earlier step failed; psql then
exits with a non-zero status. The following code removes everything that
the script created:

```sql
-- Stop at the first error from here on, so that a failed cleanup fails
-- the script.
\set ON_ERROR_STOP on

-- Drop the triggers and the chunk table, and then remove the table's
-- completed queue items, which disable_vectorization() leaves behind.
SELECT FROM pgedge_vectorizer.disable_vectorization(
    'cookbook_enable_vectorization', 'content', drop_chunk_table => true);
DELETE FROM pgedge_vectorizer.queue
WHERE chunk_table = 'cookbook_enable_vectorization_content_chunks';
DROP TABLE cookbook_enable_vectorization;

-- Fail the script if any earlier step failed; psql keeps the SQLSTATE of
-- the most recent error, or 00000 if there was none.
SELECT :'LAST_ERROR_SQLSTATE' <> '00000' AS failed \gset
\if :failed
DO $$ BEGIN RAISE EXCEPTION 'a step of the recipe failed'; END $$;
\endif
```

## Running the Example

The script is available in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/vectorizer/enable_vectorization).
Set the `PG*` environment variables for your server, and then run the
following command from the recipe's `sql` directory:

```bash
psql -X -q -v ON_ERROR_STOP=1 -f main.sql
```

## Viewing the Complete Program

The following code shows the complete script:

```sql
-- Ellie's Postgres Cookbook
-- Vectorizing a table's text column with pgEdge Vectorizer, so that the
-- extension keeps embeddings for the text automatically.
--
-- Copyright (c) 2026, pgEdge, Inc.
-- This code is released under the PostgreSQL License.

-- Print plain lines, and hide the NOTICE messages that the Vectorizer
-- functions raise as they work.
\pset format unaligned
\pset tuples_only on
SET client_min_messages = warning;

-- Keep going after a failed step, so that the cleanup at the end of the
-- script always runs; the script fails at the end instead.
\set ON_ERROR_STOP off

-- The background worker reads the rows in its own session, so the table
-- must be an ordinary table rather than a temporary one.
CREATE TABLE cookbook_enable_vectorization (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    content text NOT NULL
);

INSERT INTO cookbook_enable_vectorization (content) VALUES
    ('Knead the bread dough for ten minutes, then leave it to rise in a warm kitchen.'),
    ('Jupiter is the largest planet in the solar system, with dozens of moons.'),
    ('PostgreSQL stores data in tables and answers questions written in SQL.');

-- Create the chunk table, its indexes and the triggers, and queue the
-- existing rows for embedding. The extension asks the embedding model for
-- its dimension when the call does not give one. The function returns
-- void, so the query selects no columns, which prints nothing.
SELECT FROM pgedge_vectorizer.enable_vectorization(
    'cookbook_enable_vectorization', 'content');

-- Wait until the background worker has embedded every queued chunk of the
-- table, and fail if an item fails or the wait takes over five minutes. A
-- cold embedding model can take a while to answer its first request.
DO $$
DECLARE
    deadline timestamptz := clock_timestamp() + interval '300 seconds';
    failure text;
BEGIN
    LOOP
        SELECT error_message INTO failure
        FROM pgedge_vectorizer.failed_items
        WHERE chunk_table = 'cookbook_enable_vectorization_content_chunks'
        LIMIT 1;
        IF FOUND THEN
            RAISE EXCEPTION 'embedding failed: %', failure;
        END IF;

        EXIT WHEN NOT EXISTS (
            SELECT 1
            FROM pgedge_vectorizer.queue_status
            WHERE chunk_table = 'cookbook_enable_vectorization_content_chunks'
              AND status IN ('pending', 'processing'));

        IF clock_timestamp() > deadline THEN
            -- Report the latest error that the worker recorded for the
            -- table; a request that hangs records none.
            SELECT error_message INTO failure
            FROM pgedge_vectorizer.queue
            WHERE chunk_table = 'cookbook_enable_vectorization_content_chunks'
              AND error_message IS NOT NULL
            ORDER BY next_retry_at DESC NULLS LAST, id DESC
            LIMIT 1;
            RAISE EXCEPTION 'timed out waiting for the embeddings: %',
                coalesce(failure, 'no error recorded; check that '
                    || 'pgedge_vectorizer.databases lists this database '
                    || 'and that pgedge_vectorizer.api_url reaches the '
                    || 'embedding provider');
        END IF;
        PERFORM pg_sleep(1);
    END LOOP;
END
$$;

-- The registry records the chunk table that the extension created.
SELECT 'Chunk table: ' || chunk_table
FROM pgedge_vectorizer.vectorizers
WHERE source_table = 'cookbook_enable_vectorization';

-- Each short row fits in a single chunk, and each chunk now has an
-- embedding with one value for each dimension of the model.
SELECT 'Chunks: ' || count(*)
FROM cookbook_enable_vectorization_content_chunks;
SELECT 'Chunks with embeddings: ' || count(embedding)
FROM cookbook_enable_vectorization_content_chunks;
SELECT 'Embedding dimensions: ' || vector_dims(embedding)
FROM cookbook_enable_vectorization_content_chunks
LIMIT 1;

-- Stop at the first error from here on, so that a failed cleanup fails
-- the script.
\set ON_ERROR_STOP on

-- Drop the triggers and the chunk table, and then remove the table's
-- completed queue items, which disable_vectorization() leaves behind.
SELECT FROM pgedge_vectorizer.disable_vectorization(
    'cookbook_enable_vectorization', 'content', drop_chunk_table => true);
DELETE FROM pgedge_vectorizer.queue
WHERE chunk_table = 'cookbook_enable_vectorization_content_chunks';
DROP TABLE cookbook_enable_vectorization;

-- Fail the script if any earlier step failed; psql keeps the SQLSTATE of
-- the most recent error, or 00000 if there was none.
SELECT :'LAST_ERROR_SQLSTATE' <> '00000' AS failed \gset
\if :failed
DO $$ BEGIN RAISE EXCEPTION 'a step of the recipe failed'; END $$;
\endif

```

## Next Steps

The following resources provide more information about the topics in this
recipe:

- The [Searching Vectorized Text](semantic_search.md) recipe uses the
  embeddings to find the row closest in meaning to a question.
- The [Monitoring the Embedding Queue](queue_status.md) recipe reads the
  views that report on the queue.
- The [pgEdge Vectorizer documentation](https://docs.pgedge.com/pgedge-vectorizer/)
  describes every function and setting of the extension.
