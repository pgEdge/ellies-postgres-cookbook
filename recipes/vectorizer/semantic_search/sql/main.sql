-- Ellie's Postgres Cookbook
-- Searching vectorized text by meaning with pgEdge Vectorizer, by ordering
-- the chunks by their distance from the embedding of a question.
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
-- --8<-- [end:setup]

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
            RAISE EXCEPTION 'timed out waiting for the embeddings';
        END IF;
        PERFORM pg_sleep(1);
    END LOOP;
END
$$;
-- --8<-- [end:wait]

-- --8<-- [start:search]
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
-- --8<-- [end:search]

-- --8<-- [start:cleanup]
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
-- --8<-- [end:cleanup]
