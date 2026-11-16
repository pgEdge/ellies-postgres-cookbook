# Monitoring the Embedding Queue

This recipe shows how to watch pgEdge Vectorizer's queue of chunks waiting
for embeddings. The triggers that the extension adds to a vectorized table
queue an item for each new chunk, and a background worker takes the items
from the queue and embeds them. The extension provides three views of the
queue: `queue_status` counts the items by chunk table and status,
`pending_count` counts the pending items across the database, and
`failed_items` lists the items that have failed. The script reads the views
before and after the worker has embedded three rows.

These examples are for pgEdge Vectorizer 1.1.

The script prints the following output:

```text
Before the commit:
pending: 3
After the worker has finished:
completed: 3
Pending items in the queue: 0
Failed items for the table: 0
```

The `pending_count` view covers every vectorized table in the database, so
on a server where other tables are being vectorized it can report more
items than the script queues.

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

## Vectorizing an Empty Table

The script vectorizes the table before it holds any rows, so that the
trigger queues each row as the script inserts it. The following code
creates the table, and calls `enable_vectorization()` for its text column:

```sql
-- Vectorize an empty table, so that the trigger queues each row as the
-- next step inserts it.
CREATE TABLE cookbook_queue_status (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    content text NOT NULL
);

-- The function returns void, so the query selects no columns, which
-- prints nothing.
SELECT FROM pgedge_vectorizer.enable_vectorization(
    'cookbook_queue_status', 'content');
```

## Queueing the Rows

The trigger chunks each row as the `INSERT` adds it, and queues an item
for each chunk, in the same transaction as the `INSERT`. The background
worker cannot see the items until the transaction commits, so a query in
the same transaction sees all three items as pending, whatever the worker
is doing. Once the transaction commits, the worker can take the items at
any moment, so a count read after the commit varies from run to run. The
following code inserts the rows and reads the `queue_status` view before
the commit:

```sql
-- The trigger chunks each new row and adds a queue item for each chunk.
-- The background worker cannot see the items until the transaction
-- commits, so the queue holds exactly three pending items for the table
-- when the transaction reads it.
BEGIN;

INSERT INTO cookbook_queue_status (content) VALUES
    ('Knead the bread dough for ten minutes, then leave it to rise in a warm kitchen.'),
    ('Jupiter is the largest planet in the solar system, with dozens of moons.'),
    ('PostgreSQL stores data in tables and answers questions written in SQL.');

\echo Before the commit:
SELECT status || ': ' || count
FROM pgedge_vectorizer.queue_status
WHERE chunk_table = 'cookbook_queue_status_content_chunks';

COMMIT;
```

## Waiting for the Embeddings

The script waits in a `DO` block that checks the queue once a second. The
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
        WHERE chunk_table = 'cookbook_queue_status_content_chunks'
        LIMIT 1;
        IF FOUND THEN
            RAISE EXCEPTION 'embedding failed: %', failure;
        END IF;

        EXIT WHEN NOT EXISTS (
            SELECT 1
            FROM pgedge_vectorizer.queue_status
            WHERE chunk_table = 'cookbook_queue_status_content_chunks'
              AND status IN ('pending', 'processing'));

        IF clock_timestamp() > deadline THEN
            -- Report the latest error that the worker recorded for the
            -- table; a request that hangs records none.
            SELECT error_message INTO failure
            FROM pgedge_vectorizer.queue
            WHERE chunk_table = 'cookbook_queue_status_content_chunks'
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

## Reading the Queue Views

An item moves from `pending` to `processing` while the worker embeds its
chunk, and to `completed` once the embedding is stored. When the worker
cannot embed a chunk, it sets the item back to `pending` with a delay that
doubles with each attempt, and marks the item `failed` once the item has
used up its attempts; the `pgedge_vectorizer.max_retries` setting sets the
number of attempts for new items. The `failed_items` view shows the error
from the last attempt. The `queue_status` view also reports the oldest and
newest item, and the average processing time, for each table and status.
The following code reads the three views after the wait:

```sql
-- queue_status counts the items of each chunk table by status; the
-- worker has now marked all three items as completed.
\echo After the worker has finished:
SELECT status || ': ' || count
FROM pgedge_vectorizer.queue_status
WHERE chunk_table = 'cookbook_queue_status_content_chunks';

-- pending_count covers the whole queue, for every vectorized table in
-- the database.
SELECT 'Pending items in the queue: ' || pending_items
FROM pgedge_vectorizer.pending_count;

-- failed_items lists the items that have used up their retries, with the
-- error from the last attempt.
SELECT 'Failed items for the table: ' || count(*)
FROM pgedge_vectorizer.failed_items
WHERE chunk_table = 'cookbook_queue_status_content_chunks';
```

## Cleaning Up

The `disable_vectorization()` function drops the triggers and, with
`drop_chunk_table`, the chunk table, and it removes the table's pending
items from the queue. The completed items stay in the queue until they are
older than the `pgedge_vectorizer.auto_cleanup_hours` setting (24 hours by
default) allows, and the `clear_completed()` function likewise deletes
completed items only once they are older than 24 hours by default. Calling
`clear_completed(0)`
removes them at once, but for every vectorized table in the database, so
the script deletes only the items for its own chunk table instead. The
script then checks psql's `LAST_ERROR_SQLSTATE` variable, and raises an
error if an earlier step failed, so that psql exits with a non-zero status.
The following code removes everything that the script created:

```sql
-- Stop at the first error from here on, so that a failed cleanup fails
-- the script.
\set ON_ERROR_STOP on

-- Drop the triggers and the chunk table, and then remove the table's
-- completed queue items, which disable_vectorization() leaves behind.
SELECT FROM pgedge_vectorizer.disable_vectorization(
    'cookbook_queue_status', 'content', drop_chunk_table => true);
DELETE FROM pgedge_vectorizer.queue
WHERE chunk_table = 'cookbook_queue_status_content_chunks';
DROP TABLE cookbook_queue_status;

-- Fail the script if any earlier step failed; psql keeps the SQLSTATE of
-- the most recent error, or 00000 if there was none.
SELECT :'LAST_ERROR_SQLSTATE' <> '00000' AS failed \gset
\if :failed
DO $$ BEGIN RAISE EXCEPTION 'a step of the recipe failed'; END $$;
\endif
```

## Running the Example

The script is available in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/vectorizer/queue_status).
Set the `PG*` environment variables for your server, and then run the
following command from the recipe's `sql` directory:

```bash
psql -X -q -v ON_ERROR_STOP=1 -f main.sql
```

## Viewing the Complete Program

The following code shows the complete script:

```sql
-- Ellie's Postgres Cookbook
-- Monitoring pgEdge Vectorizer's embedding queue with the queue_status,
-- pending_count and failed_items views.
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

-- Vectorize an empty table, so that the trigger queues each row as the
-- next step inserts it.
CREATE TABLE cookbook_queue_status (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    content text NOT NULL
);

-- The function returns void, so the query selects no columns, which
-- prints nothing.
SELECT FROM pgedge_vectorizer.enable_vectorization(
    'cookbook_queue_status', 'content');

-- The trigger chunks each new row and adds a queue item for each chunk.
-- The background worker cannot see the items until the transaction
-- commits, so the queue holds exactly three pending items for the table
-- when the transaction reads it.
BEGIN;

INSERT INTO cookbook_queue_status (content) VALUES
    ('Knead the bread dough for ten minutes, then leave it to rise in a warm kitchen.'),
    ('Jupiter is the largest planet in the solar system, with dozens of moons.'),
    ('PostgreSQL stores data in tables and answers questions written in SQL.');

\echo Before the commit:
SELECT status || ': ' || count
FROM pgedge_vectorizer.queue_status
WHERE chunk_table = 'cookbook_queue_status_content_chunks';

COMMIT;

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
        WHERE chunk_table = 'cookbook_queue_status_content_chunks'
        LIMIT 1;
        IF FOUND THEN
            RAISE EXCEPTION 'embedding failed: %', failure;
        END IF;

        EXIT WHEN NOT EXISTS (
            SELECT 1
            FROM pgedge_vectorizer.queue_status
            WHERE chunk_table = 'cookbook_queue_status_content_chunks'
              AND status IN ('pending', 'processing'));

        IF clock_timestamp() > deadline THEN
            -- Report the latest error that the worker recorded for the
            -- table; a request that hangs records none.
            SELECT error_message INTO failure
            FROM pgedge_vectorizer.queue
            WHERE chunk_table = 'cookbook_queue_status_content_chunks'
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

-- queue_status counts the items of each chunk table by status; the
-- worker has now marked all three items as completed.
\echo After the worker has finished:
SELECT status || ': ' || count
FROM pgedge_vectorizer.queue_status
WHERE chunk_table = 'cookbook_queue_status_content_chunks';

-- pending_count covers the whole queue, for every vectorized table in
-- the database.
SELECT 'Pending items in the queue: ' || pending_items
FROM pgedge_vectorizer.pending_count;

-- failed_items lists the items that have used up their retries, with the
-- error from the last attempt.
SELECT 'Failed items for the table: ' || count(*)
FROM pgedge_vectorizer.failed_items
WHERE chunk_table = 'cookbook_queue_status_content_chunks';

-- Stop at the first error from here on, so that a failed cleanup fails
-- the script.
\set ON_ERROR_STOP on

-- Drop the triggers and the chunk table, and then remove the table's
-- completed queue items, which disable_vectorization() leaves behind.
SELECT FROM pgedge_vectorizer.disable_vectorization(
    'cookbook_queue_status', 'content', drop_chunk_table => true);
DELETE FROM pgedge_vectorizer.queue
WHERE chunk_table = 'cookbook_queue_status_content_chunks';
DROP TABLE cookbook_queue_status;

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

- The [Vectorizing a Table](enable_vectorization.md) recipe describes what
  `enable_vectorization()` creates.
- The [Keeping Embeddings Up to Date](update_source.md) recipe shows the
  queue at work when a row's text changes.
- The [monitoring guide](https://github.com/pgEdge/pgedge-vectorizer/blob/v1.1/docs/monitoring.md)
  for pgEdge Vectorizer 1.1 describes the views and the functions that
  manage the queue.
