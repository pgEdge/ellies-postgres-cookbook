-- Ellie's Postgres Cookbook
-- Keeping embeddings up to date with pgEdge Vectorizer, whose trigger
-- chunks and queues a row again when its text changes.
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

-- --8<-- [start:wait]
-- The script waits twice, so it keeps the waiting loop in a function. A
-- function in pg_temp lasts only as long as the session, and needs no
-- cleanup. The function waits until the background worker has embedded
-- every queued chunk of the table, and fails if an item fails or the
-- wait takes over five minutes. A cold embedding model can take a while
-- to answer its first request.
CREATE FUNCTION pg_temp.wait_for_embeddings(p_chunk_table text)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
    deadline timestamptz := clock_timestamp() + interval '300 seconds';
    failure text;
BEGIN
    LOOP
        SELECT error_message INTO failure
        FROM pgedge_vectorizer.failed_items
        WHERE chunk_table = p_chunk_table
        LIMIT 1;
        IF FOUND THEN
            RAISE EXCEPTION 'embedding failed: %', failure;
        END IF;

        EXIT WHEN NOT EXISTS (
            SELECT 1
            FROM pgedge_vectorizer.queue_status
            WHERE chunk_table = p_chunk_table
              AND status IN ('pending', 'processing'));

        IF clock_timestamp() > deadline THEN
            RAISE EXCEPTION 'timed out waiting for the embeddings';
        END IF;
        PERFORM pg_sleep(1);
    END LOOP;
END
$$;
-- --8<-- [end:wait]

-- --8<-- [start:setup]
-- Vectorize three rows, and wait for their embeddings.
CREATE TABLE cookbook_update_source (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    content text NOT NULL
);

INSERT INTO cookbook_update_source (content) VALUES
    ('Knead the bread dough for ten minutes, then leave it to rise in a warm kitchen.'),
    ('Jupiter is the largest planet in the solar system, with dozens of moons.'),
    ('PostgreSQL stores data in tables and answers questions written in SQL.');

-- Both functions return void, so the queries select no columns, which
-- prints nothing.
SELECT FROM pgedge_vectorizer.enable_vectorization(
    'cookbook_update_source', 'content');
SELECT FROM pg_temp.wait_for_embeddings(
    'cookbook_update_source_content_chunks');

SELECT 'Before the update: ' || content
FROM cookbook_update_source_content_chunks
WHERE source_id = 2;
-- --8<-- [end:setup]

-- --8<-- [start:update]
-- The trigger sees that the text has changed, replaces the row's chunks
-- with chunks of the new text, and queues them for embedding. An update
-- that leaves the text as it was queues nothing.
UPDATE cookbook_update_source
SET content = 'Saturn is famous for its bright rings of ice and rock.'
WHERE id = 2;

SELECT FROM pg_temp.wait_for_embeddings(
    'cookbook_update_source_content_chunks');
-- --8<-- [end:update]

-- --8<-- [start:check]
-- The chunk now holds the new text, with a new embedding.
SELECT 'After the update: ' || content
FROM cookbook_update_source_content_chunks
WHERE source_id = 2;

SELECT 'Chunks for row 2 with embeddings: ' || count(embedding)
FROM cookbook_update_source_content_chunks
WHERE source_id = 2;

-- A search by meaning finds the new text.
\set question 'Which planet has rings?'
\echo Question: :question
SELECT 'Top match (row ' || c.source_id || '): ' || c.content
FROM cookbook_update_source_content_chunks AS c
ORDER BY c.embedding <=> (
    SELECT pgedge_vectorizer.generate_embedding(:'question'))
LIMIT 1;
-- --8<-- [end:check]

-- --8<-- [start:cleanup]
-- Stop at the first error from here on, so that a failed cleanup fails
-- the script.
\set ON_ERROR_STOP on

-- Drop the triggers and the chunk table, and then remove the table's
-- completed queue items, which disable_vectorization() leaves behind.
SELECT FROM pgedge_vectorizer.disable_vectorization(
    'cookbook_update_source', 'content', drop_chunk_table => true);
DELETE FROM pgedge_vectorizer.queue
WHERE chunk_table = 'cookbook_update_source_content_chunks';
DROP TABLE cookbook_update_source;

-- Fail the script if any earlier step failed; psql keeps the SQLSTATE of
-- the most recent error, or 00000 if there was none.
SELECT :'LAST_ERROR_SQLSTATE' <> '00000' AS failed \gset
\if :failed
DO $$ BEGIN RAISE EXCEPTION 'a step of the recipe failed'; END $$;
\endif
-- --8<-- [end:cleanup]
