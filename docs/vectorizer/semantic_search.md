# Searching Vectorized Text

This recipe shows how to find the text closest in meaning to a question,
even when the question and the text share no words. The script vectorizes
a table of three rows about unrelated subjects, waits for the embeddings,
and then orders the chunks by their distance from an embedding of the
question. The question asks how to bake a loaf, and the closest chunk is
the row about kneading bread dough.

These examples are for pgEdge Vectorizer 1.1.

The script prints the following output:

```text
Question: How do I bake a loaf?
Top match (row 1): Knead the bread dough for ten minutes, then leave it to rise in a warm kitchen.
```

The distances, and so the order of the results, depend on the embedding
model and on the build of the model. The rows in this example cover
subjects far enough apart that the top match should not change, but the
order of the other rows can. The output above came from Ollama's
`nomic-embed-text` model with the digest `0a109f422b47`.

## Preparing the Ingredients

The script needs a PostgreSQL server with the `vector` and
`pgedge_vectorizer` extensions, and an embedding model that the server can
reach. The [Vectorizing a Table](enable_vectorization.md) recipe lists the
server settings that the examples use; the background worker must process
the queue in the database that the script connects to.

## Configuring psql

The script prints plain lines, and it hides the `NOTICE` messages that the
Vectorizer functions raise. A failed step must not stop the script before
the cleanup at the end, so the script turns off `ON_ERROR_STOP` until the
cleanup starts. The following code shows the settings:

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

## Vectorizing the Rows

The script creates a table with a primary key, inserts three rows, and
calls `enable_vectorization()` for the text column. The function creates
the `cookbook_semantic_search_content_chunks` table, and queues each chunk
for the background worker to embed. The following code creates and
vectorizes the table:

```sql
-- Three rows about unrelated subjects, so that the right answer is clear
-- whichever build of the embedding model is in use.
CREATE TABLE cookbook_semantic_search (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    content text NOT NULL
);

INSERT INTO cookbook_semantic_search (content) VALUES
    ('Knead the bread dough for ten minutes, then leave it to rise in a warm kitchen.'),
    ('Jupiter is the largest planet in the solar system, with dozens of moons.'),
    ('PostgreSQL stores data in tables and answers questions written in SQL.');

-- The function returns void, so the query selects no columns, which
-- prints nothing.
SELECT FROM pgedge_vectorizer.enable_vectorization(
    'cookbook_semantic_search', 'content');
```

## Waiting for the Embeddings

The background worker embeds the chunks shortly after they are queued, so
the script waits in a `DO` block that checks the queue once a second. The
block stops when no item for the chunk table is pending or in progress,
and raises an error if an item fails or the wait passes five minutes; a
model that is not yet in memory can take some time to answer its first
request. The following code waits for the worker:

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
        WHERE chunk_table = 'cookbook_semantic_search_content_chunks'
        LIMIT 1;
        IF FOUND THEN
            RAISE EXCEPTION 'embedding failed: %', failure;
        END IF;

        EXIT WHEN NOT EXISTS (
            SELECT 1
            FROM pgedge_vectorizer.queue_status
            WHERE chunk_table = 'cookbook_semantic_search_content_chunks'
              AND status IN ('pending', 'processing'));

        IF clock_timestamp() > deadline THEN
            -- Report the latest error that the worker recorded for the
            -- table; a request that hangs records none.
            SELECT error_message INTO failure
            FROM pgedge_vectorizer.queue
            WHERE chunk_table = 'cookbook_semantic_search_content_chunks'
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

## Searching by Meaning

The `pgedge_vectorizer.generate_embedding()` function asks the configured
model for an embedding of the question, in the same session and without
the queue. The `<=>` operator from pgvector returns the cosine distance
between two embeddings, so ordering the chunks by that distance puts the
chunk closest in meaning first. The chunk table has an HNSW index for
cosine distance, which lets a larger table answer the query without
comparing every chunk.

The script keeps the question in a psql variable, and psql writes the value
into the query as a quoted string literal, escaping any quotes inside it.
The scalar subquery asks the model for the embedding once, rather than once
for each chunk. The following code runs the search:

```sql
-- psql quotes the variable as a string literal where :'question' appears,
-- escaping any quotes inside it.
\set question 'How do I bake a loaf?'
\echo Question: :question

-- The <=> operator gives the cosine distance, which is smallest for the
-- chunk closest in meaning to the question. The scalar subquery embeds
-- the question once, rather than once for each chunk that it compares.
SELECT 'Top match (row ' || c.source_id || '): ' || c.content
FROM cookbook_semantic_search_content_chunks AS c
ORDER BY c.embedding <=> (
    SELECT pgedge_vectorizer.generate_embedding(:'question'))
LIMIT 1;
```

## Cleaning Up

The `disable_vectorization()` function drops the triggers and, with
`drop_chunk_table`, the chunk table, and it removes the table's pending
items from the queue. Completed items stay in the queue; the
`clear_completed(0)` function would remove them at once, but for every
vectorized table in the database, so the script deletes only the items for
its own chunk table. The script then checks psql's `LAST_ERROR_SQLSTATE`
variable, and raises an error if an earlier step failed, so that psql exits
with a non-zero status. The following code removes everything that the
script created:

```sql
-- Stop at the first error from here on, so that a failed cleanup fails
-- the script.
\set ON_ERROR_STOP on

-- Drop the triggers and the chunk table, and then remove the table's
-- completed queue items, which disable_vectorization() leaves behind.
SELECT FROM pgedge_vectorizer.disable_vectorization(
    'cookbook_semantic_search', 'content', drop_chunk_table => true);
DELETE FROM pgedge_vectorizer.queue
WHERE chunk_table = 'cookbook_semantic_search_content_chunks';
DROP TABLE cookbook_semantic_search;

-- Fail the script if any earlier step failed; psql keeps the SQLSTATE of
-- the most recent error, or 00000 if there was none.
SELECT :'LAST_ERROR_SQLSTATE' <> '00000' AS failed \gset
\if :failed
DO $$ BEGIN RAISE EXCEPTION 'a step of the recipe failed'; END $$;
\endif
```

## Running the Example

The script is available in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/vectorizer/semantic_search).
Set the `PG*` environment variables for your server, and then run the
following command from the recipe's `sql` directory:

```bash
psql -X -q -v ON_ERROR_STOP=1 -f main.sql
```

## Viewing the Complete Program

The following code shows the complete script:

```sql
-- Ellie's Postgres Cookbook
-- Searching vectorized text by meaning with pgEdge Vectorizer, by ordering
-- the chunks by their distance from the embedding of a question.
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

-- Three rows about unrelated subjects, so that the right answer is clear
-- whichever build of the embedding model is in use.
CREATE TABLE cookbook_semantic_search (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    content text NOT NULL
);

INSERT INTO cookbook_semantic_search (content) VALUES
    ('Knead the bread dough for ten minutes, then leave it to rise in a warm kitchen.'),
    ('Jupiter is the largest planet in the solar system, with dozens of moons.'),
    ('PostgreSQL stores data in tables and answers questions written in SQL.');

-- The function returns void, so the query selects no columns, which
-- prints nothing.
SELECT FROM pgedge_vectorizer.enable_vectorization(
    'cookbook_semantic_search', 'content');

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
        WHERE chunk_table = 'cookbook_semantic_search_content_chunks'
        LIMIT 1;
        IF FOUND THEN
            RAISE EXCEPTION 'embedding failed: %', failure;
        END IF;

        EXIT WHEN NOT EXISTS (
            SELECT 1
            FROM pgedge_vectorizer.queue_status
            WHERE chunk_table = 'cookbook_semantic_search_content_chunks'
              AND status IN ('pending', 'processing'));

        IF clock_timestamp() > deadline THEN
            -- Report the latest error that the worker recorded for the
            -- table; a request that hangs records none.
            SELECT error_message INTO failure
            FROM pgedge_vectorizer.queue
            WHERE chunk_table = 'cookbook_semantic_search_content_chunks'
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

-- psql quotes the variable as a string literal where :'question' appears,
-- escaping any quotes inside it.
\set question 'How do I bake a loaf?'
\echo Question: :question

-- The <=> operator gives the cosine distance, which is smallest for the
-- chunk closest in meaning to the question. The scalar subquery embeds
-- the question once, rather than once for each chunk that it compares.
SELECT 'Top match (row ' || c.source_id || '): ' || c.content
FROM cookbook_semantic_search_content_chunks AS c
ORDER BY c.embedding <=> (
    SELECT pgedge_vectorizer.generate_embedding(:'question'))
LIMIT 1;

-- Stop at the first error from here on, so that a failed cleanup fails
-- the script.
\set ON_ERROR_STOP on

-- Drop the triggers and the chunk table, and then remove the table's
-- completed queue items, which disable_vectorization() leaves behind.
SELECT FROM pgedge_vectorizer.disable_vectorization(
    'cookbook_semantic_search', 'content', drop_chunk_table => true);
DELETE FROM pgedge_vectorizer.queue
WHERE chunk_table = 'cookbook_semantic_search_content_chunks';
DROP TABLE cookbook_semantic_search;

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

- The [Combining Keyword and Vector Search](hybrid_search.md) recipe adds
  a keyword ranking to the search by meaning.
- The [Vectorizing a Table](enable_vectorization.md) recipe describes what
  `enable_vectorization()` creates.
- The [pgvector documentation](https://github.com/pgvector/pgvector)
  describes the distance operators and the HNSW index.
