-- Ellie's Postgres Cookbook
-- Expiring cached results with pg_semantic_cache.
--
-- Copyright (c) 2026, pgEdge, Inc.
-- This code is released under the PostgreSQL License.

-- --8<-- [start:setup]
-- Stop at the first error, and print plain lines rather than tables.
\set ON_ERROR_STOP on
\pset format unaligned
\pset tuples_only on

-- The question whose result the program caches.
\set question 'What was the total value of refunds issued last week?'
-- --8<-- [end:setup]

-- --8<-- [start:embed]
-- Get the embedding of the question from the pgEdge Vectorizer.
SELECT pgedge_vectorizer.generate_embedding(:'question')::text AS embedding
\gset
-- --8<-- [end:embed]

-- --8<-- [start:sweep]
-- Remove any entry that an earlier, interrupted run of this program left
-- behind, so that the new entry starts with a fresh expiry time.
SELECT semantic_cache.invalidate_cache(tag => 'cookbook-expire-entries')
       AS leftovers
\gset
-- --8<-- [end:sweep]

-- --8<-- [start:cache]
-- Cache the result for one second only. Each statement commits on its
-- own, because the expiry time depends on the clock moving on.
SELECT semantic_cache.cache_query(
           query_text      => :'question',
           query_embedding => :'embedding',
           result_data     => '{"refunds_total": 99.50}',
           ttl_seconds     => 1,
           tags            => ARRAY['cookbook', 'cookbook-expire-entries']
       ) AS cache_id
\gset
\echo Cached the result for 1 second

SELECT format('Lookup straight away: %s',
              CASE WHEN found THEN 'hit' ELSE 'miss' END)
  FROM semantic_cache.get_cached_result(:'embedding', 0.95);
-- --8<-- [end:cache]

-- --8<-- [start:wait]
-- Wait until the entry has expired. A lookup ignores an expired entry,
-- although the entry stays in the table until it is evicted.
SELECT FROM pg_sleep(2);

SELECT format('Lookup after 2 seconds: %s',
              CASE WHEN found THEN 'hit' ELSE 'miss' END)
  FROM semantic_cache.get_cached_result(:'embedding', 0.95);

SELECT format('Entries still stored: %s', count(*))
  FROM semantic_cache.cache_entries
 WHERE tags @> ARRAY['cookbook-expire-entries'];
-- --8<-- [end:wait]

-- --8<-- [start:evict]
-- Delete every expired entry in the cache. The count that evict_expired()
-- returns includes expired entries from other applications, so the
-- program prints how many of its own entries remain instead.
SELECT semantic_cache.evict_expired() AS evicted
\gset

SELECT format('Entries stored after evict_expired(): %s', count(*))
  FROM semantic_cache.cache_entries
 WHERE tags @> ARRAY['cookbook-expire-entries'];
-- --8<-- [end:evict]
