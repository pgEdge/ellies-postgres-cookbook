-- Ellie's Postgres Cookbook
-- Finding a cached answer to a reworded question with pg_semantic_cache.
--
-- Copyright (c) 2026, pgEdge, Inc.
-- This code is released under the PostgreSQL License.

-- --8<-- [start:setup]
-- Stop at the first error, and print plain lines rather than tables.
\set ON_ERROR_STOP on
\pset format unaligned
\pset tuples_only on

-- The question whose answer the program caches, a rewording of it, and
-- an unrelated question.
\set question 'Which customers placed the most orders this year?'
\set reworded 'Who are our top customers by number of orders this year?'
\set unrelated 'How do I reset my password?'

-- The lowest cosine similarity that counts as the same question.
\set threshold 0.75
-- --8<-- [end:setup]

-- --8<-- [start:embed]
-- Get the embedding of each question from the pgEdge Vectorizer before
-- changing the cache, so that a failure here leaves nothing behind.
SELECT pgedge_vectorizer.generate_embedding(:'question')::text
           AS question_embedding,
       pgedge_vectorizer.generate_embedding(:'reworded')::text
           AS reworded_embedding,
       pgedge_vectorizer.generate_embedding(:'unrelated')::text
           AS unrelated_embedding
\gset
-- --8<-- [end:embed]

-- --8<-- [start:probes]
-- The cache table has an IVFFlat index, which by default searches only
-- the one list of vectors nearest to the query, and so can miss a close
-- entry in another list. Searching 100 lists makes the search exact for
-- an index of up to 100 lists; the lists setting in the indexdef column
-- of pg_indexes, for semantic_cache.idx_cache_embedding, shows how many
-- lists the index has.
SET ivfflat.probes = 100;
-- --8<-- [end:probes]

-- Run every step that changes the cache in one transaction, so that
-- PostgreSQL rolls the new entry back if any step fails.
BEGIN;

-- --8<-- [start:cache]
-- Cache the answer to the original question for an hour.
SELECT semantic_cache.cache_query(
           query_text      => :'question',
           query_embedding => :'question_embedding',
           result_data     => '{"top_customer": "Jane Doe", "orders": 42}',
           ttl_seconds     => 3600,
           tags            => ARRAY['cookbook', 'cookbook-similar-question']
       ) AS cache_id
\gset
\echo Cached the answer to: :question
-- --8<-- [end:cache]

-- --8<-- [start:lookup]
-- Look up each of the other questions. A miss still reports the
-- similarity of the closest entry, which is below the threshold.
SELECT format('%s -> %s', :'reworded',
              CASE WHEN found THEN 'hit' ELSE 'miss' END)
  FROM semantic_cache.get_cached_result(:'reworded_embedding', :threshold);

SELECT format('%s -> %s', :'unrelated',
              CASE WHEN found THEN 'hit' ELSE 'miss' END)
  FROM semantic_cache.get_cached_result(:'unrelated_embedding', :threshold);
-- --8<-- [end:lookup]

-- --8<-- [start:cleanup]
-- Remove the entries that this program created.
SELECT semantic_cache.invalidate_cache(tag => 'cookbook-similar-question')
       AS removed
\gset
\echo Removed :removed cached entry
-- --8<-- [end:cleanup]

COMMIT;
