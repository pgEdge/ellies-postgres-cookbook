-- Ellie's Postgres Cookbook
-- Monitoring pgEdge Vectorizer's embedding queue with the queue_status,
-- pending_count and failed_items views.
--
-- Copyright (c) 2026, pgEdge, Inc.
-- This code is released under the PostgreSQL License.

-- --8<-- [start:settings]
-- Print plain lines, and hide the NOTICE messages that the Vectorizer
-- functions raise as they work.
\pset format unaligned
\pset tuples_only on
SET client_min_messages = warning;

-- Keep going after a failed step, so that the cleanup at the end of the
-- script always runs; the script fails at the end instead.
\set ON_ERROR_STOP off
-- --8<-- [end:settings]

-- --8<-- [start:setup]
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
-- --8<-- [end:setup]

-- --8<-- [start:queue]
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
-- --8<-- [end:queue]

-- --8<-- [start:wait]
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
-- --8<-- [end:wait]

-- --8<-- [start:status]
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
-- --8<-- [end:status]

-- --8<-- [start:cleanup]
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
-- --8<-- [end:cleanup]
