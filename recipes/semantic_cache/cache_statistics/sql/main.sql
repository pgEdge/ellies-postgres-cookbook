-- Ellie's Postgres Cookbook
-- Measuring the hit rate of a pg_semantic_cache cache.
--
-- Copyright (c) 2026, pgEdge, Inc.
-- This code is released under the PostgreSQL License.

-- --8<-- [start:setup]
-- Stop at the first error, and print plain lines rather than tables.
\set ON_ERROR_STOP on
\pset format unaligned
\pset tuples_only on

-- A question that the program caches, and one that it never caches.
\set question 'What is the average value of an order this month?'
\set unrelated 'Recommend a good recipe for apple pie.'
-- --8<-- [end:setup]

-- --8<-- [start:embed]
-- Get the embedding of each question from the pgEdge Vectorizer before
-- changing the cache, so that a failure here leaves nothing behind.
SELECT pgedge_vectorizer.generate_embedding(:'question')::text
           AS question_embedding,
       pgedge_vectorizer.generate_embedding(:'unrelated')::text
           AS unrelated_embedding
\gset
-- --8<-- [end:embed]

-- Run every step that changes the cache in one transaction, so that
-- PostgreSQL rolls the new entry back if any step fails.
BEGIN;

-- --8<-- [start:before]
-- The statistics cover every application that uses the cache, so record
-- them before the program starts.
SELECT total_entries AS entries_before,
       total_hits AS hits_before,
       total_misses AS misses_before
  FROM semantic_cache.cache_stats()
\gset
-- --8<-- [end:before]

-- --8<-- [start:traffic]
-- Cache one result, look it up twice, and then ask an unrelated question.
-- get_cached_result() counts each hit and miss itself.
SELECT semantic_cache.cache_query(
           query_text      => :'question',
           query_embedding => :'question_embedding',
           result_data     => '{"average_order_value": 42.50}',
           ttl_seconds     => 3600,
           tags            => ARRAY['cookbook', 'cookbook-cache-statistics']
       ) AS cache_id
\gset

SELECT format('First lookup -> %s',
              CASE WHEN found THEN 'hit' ELSE 'miss' END)
  FROM semantic_cache.get_cached_result(:'question_embedding', 0.95);
SELECT format('Second lookup -> %s',
              CASE WHEN found THEN 'hit' ELSE 'miss' END)
  FROM semantic_cache.get_cached_result(:'question_embedding', 0.95);
SELECT format('Unrelated lookup -> %s',
              CASE WHEN found THEN 'hit' ELSE 'miss' END)
  FROM semantic_cache.get_cached_result(:'unrelated_embedding', 0.95);
-- --8<-- [end:traffic]

-- --8<-- [start:after]
-- Read the statistics again, and print what changed during the run.
SELECT total_entries - :entries_before AS entries_added,
       total_hits - :hits_before AS hits,
       total_misses - :misses_before AS misses
  FROM semantic_cache.cache_stats()
\gset

\echo Entries added: :entries_added
\echo Hits: :hits
\echo Misses: :misses

SELECT format('Hit rate for this run: %s%%',
              round(100.0 * :hits / nullif(:hits + :misses, 0), 1));
-- --8<-- [end:after]

-- --8<-- [start:cleanup]
-- Remove the entries that this program created.
SELECT semantic_cache.invalidate_cache(tag => 'cookbook-cache-statistics')
       AS removed
\gset
\echo Removed :removed cached entry
-- --8<-- [end:cleanup]

COMMIT;
