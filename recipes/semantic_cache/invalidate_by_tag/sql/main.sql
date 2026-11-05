-- Ellie's Postgres Cookbook
-- Invalidating cached results by tag with pg_semantic_cache.
--
-- Copyright (c) 2026, pgEdge, Inc.
-- This code is released under the PostgreSQL License.

-- --8<-- [start:setup]
-- Stop at the first error, and print plain lines rather than tables.
\set ON_ERROR_STOP on
\pset format unaligned
\pset tuples_only on

-- One question about orders and one about customers.
\set orders_question 'How many orders are waiting to be shipped?'
\set customers_question 'How many new customers registered this week?'
-- --8<-- [end:setup]

-- --8<-- [start:embed]
-- Get the embedding of each question from the pgEdge Vectorizer before
-- changing the cache, so that a failure here leaves nothing behind.
SELECT pgedge_vectorizer.generate_embedding(:'orders_question')::text
           AS orders_embedding,
       pgedge_vectorizer.generate_embedding(:'customers_question')::text
           AS customers_embedding
\gset
-- --8<-- [end:embed]

-- Run every step that changes the cache in one transaction, so that
-- PostgreSQL rolls the new entries back if any step fails.
BEGIN;

-- --8<-- [start:cache]
-- Tag each result with the table that it was read from, as well as the
-- tags that let the program find its own entries.
SELECT semantic_cache.cache_query(
           query_text      => :'orders_question',
           query_embedding => :'orders_embedding',
           result_data     => '{"orders_waiting": 17}',
           ttl_seconds     => 3600,
           tags            => ARRAY['cookbook', 'cookbook-invalidate-by-tag',
                                    'cookbook-orders']
       ) AS orders_id,
       semantic_cache.cache_query(
           query_text      => :'customers_question',
           query_embedding => :'customers_embedding',
           result_data     => '{"new_customers": 5}',
           ttl_seconds     => 3600,
           tags            => ARRAY['cookbook', 'cookbook-invalidate-by-tag',
                                    'cookbook-customers']
       ) AS customers_id
\gset
\echo Cached 2 results
-- --8<-- [end:cache]

-- --8<-- [start:invalidate]
-- The orders table has changed, so remove every result tagged with it.
SELECT format('Invalidated %s entry tagged cookbook-orders',
              semantic_cache.invalidate_cache(tag => 'cookbook-orders'));
-- --8<-- [end:invalidate]

-- --8<-- [start:lookup]
-- Look up both questions again; only the customers result remains.
SELECT format('Orders question -> %s',
              CASE WHEN found THEN 'hit' ELSE 'miss' END)
  FROM semantic_cache.get_cached_result(:'orders_embedding', 0.95);

SELECT format('Customers question -> %s',
              CASE WHEN found THEN 'hit' ELSE 'miss' END)
  FROM semantic_cache.get_cached_result(:'customers_embedding', 0.95);
-- --8<-- [end:lookup]

-- --8<-- [start:cleanup]
-- Remove the entries that this program created.
SELECT semantic_cache.invalidate_cache(tag => 'cookbook-invalidate-by-tag')
       AS removed
\gset
\echo Removed :removed remaining cached entry
-- --8<-- [end:cleanup]

COMMIT;
