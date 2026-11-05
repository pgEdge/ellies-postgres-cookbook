# Measuring the Cache Hit Rate

This recipe demonstrates how to read the statistics that
[pg_semantic_cache](https://github.com/pgEdge/pg_semantic_cache) keeps
about lookups, and how to work out the hit rate of a cache. The hit rate is
the share of lookups that the cache answers, and shows whether the cache
saves enough work to justify its space. The example is a psql script,
because the extension is used entirely through SQL functions.

These examples are for pg_semantic_cache 0.1.0-beta4.

The script reads the statistics, caches one result, looks it up twice,
looks up an unrelated question once, and then reads the statistics again.
The statistics cover every application that uses the cache on the server,
so the script prints how much they changed rather than their totals. The
script prints the following output:

```text
First lookup -> hit
Second lookup -> hit
Unrelated lookup -> miss
Entries added: 1
Hits: 2
Misses: 1
Hit rate for this run: 66.7%
Removed 1 cached entry
```

The differences are exact only when no other session uses the cache while
the script runs, because the counters include every session's lookups.

## Preparing the Ingredients

The script needs the same server as the
[Caching a Query Result](cache_result.md) recipe: pg_semantic_cache with a
vector dimension of 768, and the pgEdge Vectorizer creating embeddings with
`nomic-embed-text` through Ollama. That recipe describes how to configure both
extensions.

## Setting Up the Script

The script stops at the first error, and prints plain lines rather than
tables. psql variables hold the question that the script caches and an
unrelated question that it does not. The following block shows the start
of the script:

```sql
-- Stop at the first error, and print plain lines rather than tables.
\set ON_ERROR_STOP on
\pset format unaligned
\pset tuples_only on

-- A question that the program caches, and one that it never caches.
\set question 'What is the average value of an order this month?'
\set unrelated 'Recommend a good recipe for apple pie.'
```

## Getting the Embeddings

The script gets the embedding of each question before it changes the
cache, so that a failure to reach the model leaves nothing in the cache.
The following block gets both embeddings in one query:

```sql
-- Get the embedding of each question from the pgEdge Vectorizer before
-- changing the cache, so that a failure here leaves nothing behind.
SELECT pgedge_vectorizer.generate_embedding(:'question')::text
           AS question_embedding,
       pgedge_vectorizer.generate_embedding(:'unrelated')::text
           AS unrelated_embedding
\gset
```

## Reading the Statistics

The `semantic_cache.cache_stats()` function returns one row. The following
table describes the columns of the row:

| Column             | Type     | Description                                    |
|--------------------|----------|------------------------------------------------|
| `total_entries`    | `bigint` | The number of entries, expired or not.         |
| `total_hits`       | `bigint` | The number of lookups that found a result.     |
| `total_misses`     | `bigint` | The number of lookups that found no result.    |
| `hit_rate_percent` | `real`   | The hits as a percentage of all lookups.       |

The counters start when the extension is created, and pg_semantic_cache
0.1.0-beta4 has no function that resets them. The following block stores
the values before the script starts in psql variables:

```sql
-- The statistics cover every application that uses the cache, so record
-- them before the program starts.
SELECT total_entries AS entries_before,
       total_hits AS hits_before,
       total_misses AS misses_before
  FROM semantic_cache.cache_stats()
\gset
```

## Making Some Lookups

The `semantic_cache.get_cached_result()` function adds one to the hits or
the misses each time it runs, so an application needs no extra call to
keep the statistics. The script caches one result, looks it up twice with
the same embedding, and looks up the unrelated question once. With the
`nomic-embed-text` model in Ollama (digest `0a109f422b47`), the two
questions have a similarity of about 0.47, far below the threshold of
0.95; the similarity depends on the embedding model. The following block
makes the lookups:

```sql
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
```

## Printing the Changes

The script reads the statistics again, subtracts the values from before
the run, and works out the hit rate of the run from the differences. The
`semantic_cache.cache_hit_rate()` function returns the `hit_rate_percent`
value on its own, which covers every lookup since the extension was
created. The following block prints the changes:

```sql
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
```

pg_semantic_cache also has a `log_cache_access()` function, which records
one lookup with its cost in the `semantic_cache.cache_access_log` table, for
the cost reports that `get_cost_savings()` returns. That function does not
change the hit and miss counters, which only `get_cached_result()` updates.

## Removing the Entries

The script removes its entry with the `cookbook-cache-statistics` tag. The
following block removes the entry:

```sql
-- Remove the entries that this program created.
SELECT semantic_cache.invalidate_cache(tag => 'cookbook-cache-statistics')
       AS removed
\gset
\echo Removed :removed cached entry
```

The script runs the steps that change the cache between `BEGIN` and
`COMMIT`. If any step fails, psql stops, and PostgreSQL rolls back the
transaction, which removes the entry and also undoes the changes to the
counters. The first lookup locks the row of the
`semantic_cache.cache_metadata` table that holds the counters, so other
sessions' lookups wait until the transaction ends; keep such transactions
short.

## Running the Example

The complete script is available in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/semantic_cache/cache_statistics).
psql reads its connection settings from the standard `PG*` environment
variables. Set the variables for your server, and then run the following
command from the `sql` directory of the recipe:

```bash
psql -X -q -v ON_ERROR_STOP=1 -f main.sql
```

## Viewing the Complete Program

The following block shows the complete script:

```sql
-- Ellie's Postgres Cookbook
-- Measuring the hit rate of a pg_semantic_cache cache.
--
-- Copyright (c) 2026, pgEdge, Inc.
-- This code is released under the PostgreSQL License.

-- Stop at the first error, and print plain lines rather than tables.
\set ON_ERROR_STOP on
\pset format unaligned
\pset tuples_only on

-- A question that the program caches, and one that it never caches.
\set question 'What is the average value of an order this month?'
\set unrelated 'Recommend a good recipe for apple pie.'

-- Get the embedding of each question from the pgEdge Vectorizer before
-- changing the cache, so that a failure here leaves nothing behind.
SELECT pgedge_vectorizer.generate_embedding(:'question')::text
           AS question_embedding,
       pgedge_vectorizer.generate_embedding(:'unrelated')::text
           AS unrelated_embedding
\gset

-- Run every step that changes the cache in one transaction, so that
-- PostgreSQL rolls the new entry back if any step fails.
BEGIN;

-- The statistics cover every application that uses the cache, so record
-- them before the program starts.
SELECT total_entries AS entries_before,
       total_hits AS hits_before,
       total_misses AS misses_before
  FROM semantic_cache.cache_stats()
\gset

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

-- Remove the entries that this program created.
SELECT semantic_cache.invalidate_cache(tag => 'cookbook-cache-statistics')
       AS removed
\gset
\echo Removed :removed cached entry

COMMIT;

```

## Next Steps

The following resources provide more information about the topics in this
recipe:

- The
  [pg_semantic_cache function reference](https://github.com/pgEdge/pg_semantic_cache/tree/f946dff6183984dd0eebc962031eb66d6668c014/docs/functions)
  describes `cache_stats()`, `cache_hit_rate()`, and the cost reporting
  functions.
- The [Finding an Answer to a Reworded Question](similar_question.md)
  recipe shows how the similarity threshold decides between a hit and a
  miss.
