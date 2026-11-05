-- Ellie's Postgres Cookbook
-- Caching a query result with pg_semantic_cache, and reading it back.
--
-- Copyright (c) 2026, pgEdge, Inc.
-- This code is released under the PostgreSQL License.

-- --8<-- [start:setup]
-- Stop at the first error, and print plain lines rather than tables.
\set ON_ERROR_STOP on
\pset format unaligned
\pset tuples_only on

-- The question whose result the program caches.
\set question 'How many orders did the shop ship in May?'
-- --8<-- [end:setup]

-- --8<-- [start:embed]
-- Ask the pgEdge Vectorizer for the embedding of the question, and keep
-- its text form, such as [0.12,-0.48,...], in the psql variable embedding.
SELECT pgedge_vectorizer.generate_embedding(:'question')::text AS embedding
\gset
-- --8<-- [end:embed]

-- Run every step that changes the cache in one transaction, so that
-- PostgreSQL rolls the new entry back if any step fails.
BEGIN;

-- --8<-- [start:cache]
-- Store the result for an hour, tagged so that the program can remove
-- exactly the entries that it created. cache_query() returns the new id.
SELECT semantic_cache.cache_query(
           query_text      => :'question',
           query_embedding => :'embedding',
           result_data     => '{"orders_shipped": 1234}'::jsonb,
           ttl_seconds     => 3600,
           tags            => ARRAY['cookbook', 'cookbook-cache-result']
       ) AS cache_id
\gset

SELECT format('Cached the result for %s seconds with tags %s',
              ttl_seconds, tags)
  FROM semantic_cache.cache_entries
 WHERE id = :cache_id;
-- --8<-- [end:cache]

-- --8<-- [start:lookup]
-- Look the result up with the same embedding; only an entry at least 95%
-- similar to the embedding counts as a match.
SELECT found::text AS found,
       round(similarity_score::numeric, 2) AS similarity,
       result_data AS result
  FROM semantic_cache.get_cached_result(
           query_embedding      => :'embedding',
           similarity_threshold => 0.95)
\gset

\echo Found: :found
\echo Similarity: :similarity
\echo Result: :result
-- --8<-- [end:lookup]

-- --8<-- [start:cleanup]
-- Remove the entries that this program created.
SELECT semantic_cache.invalidate_cache(tag => 'cookbook-cache-result')
       AS removed
\gset
\echo Removed :removed cached entry
-- --8<-- [end:cleanup]

COMMIT;
