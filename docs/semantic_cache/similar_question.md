# Finding an Answer to a Reworded Question

This recipe demonstrates the main purpose of
[pg_semantic_cache](https://github.com/pgEdge/pg_semantic_cache): returning
a cached answer when a user asks the same question in different words. The
cache compares the embeddings of the two questions, and returns the cached
answer when their similarity reaches a threshold that the application
chooses. The example is a psql script, because the extension is used
entirely through SQL functions.

These examples are for pg_semantic_cache 0.1.0-beta4.

The script caches the answer to one question, and then looks up a
rewording of that question and an unrelated question. The script prints
the following output:

```text
Cached the answer to: Which customers placed the most orders this year?
Who are our top customers by number of orders this year? -> hit
How do I reset my password? -> miss
Removed 1 cached entry
```

!!! note

    Whether a lookup hits depends on the embedding model. The script was
    tested with the `nomic-embed-text` model in Ollama (digest
    `0a109f422b47`), which gives the rewording a similarity of about 0.90
    and the unrelated question a similarity of about 0.43. A different
    model, or a different build of the same model, gives different
    similarities, and may need a different threshold.

## Preparing the Ingredients

The script needs the same server as the
[Caching a Query Result](cache_result.md) recipe: pg_semantic_cache with a
vector dimension of 768, and the pgEdge Vectorizer creating embeddings with
`nomic-embed-text` through Ollama. That recipe describes how to configure both
extensions.

## Setting Up the Script

The script stops at the first error, and prints plain lines rather than
tables. psql variables hold the three questions and the similarity
threshold, which is the lowest cosine similarity that the script treats as
the same question. The following block shows the start of the script:

```sql
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
```

## Getting the Embeddings

The script gets the embedding of every question before it changes the
cache, so that a failure to reach the model leaves nothing in the cache.
The following block gets the three embeddings in one query, and stores
them in psql variables:

```sql
-- Get the embedding of each question from the pgEdge Vectorizer before
-- changing the cache, so that a failure here leaves nothing behind.
SELECT pgedge_vectorizer.generate_embedding(:'question')::text
           AS question_embedding,
       pgedge_vectorizer.generate_embedding(:'reworded')::text
           AS reworded_embedding,
       pgedge_vectorizer.generate_embedding(:'unrelated')::text
           AS unrelated_embedding
\gset
```

## Searching Every List of the Index

pg_semantic_cache indexes the embeddings with a pgvector IVFFlat index,
which divides the vectors into lists around a set of centres, and by
default searches only the list whose centre is nearest to the query.
pgvector chooses the centres from the rows in the table when it builds the
index, but pg_semantic_cache always builds the index on an empty table:
`init_schema()` creates the table and the index together, and
`rebuild_index()` empties the table before it creates the index. With no
rows to learn from, pgvector picks random centres, so similar embeddings
often fall into different lists, however large the cache grows. When the
script was tested without the setting below, a question with a similarity
of 0.757 missed an entry with a threshold of 0.75.

The number of lists also depends on how the index was built. A new cache has
100 lists. The `rebuild_index()` function chooses 10, 100, 200, or 1,000 lists
from the number of entries in the cache, counted before it deletes them; after
the setup in the [Caching a Query Result](cache_result.md) recipe, which
rebuilds an empty cache, the index has 10 lists. The following query shows the
definition of the index, including its `lists` setting:

```sql
SELECT indexdef
  FROM pg_indexes
 WHERE schemaname = 'semantic_cache'
   AND indexname = 'idx_cache_embedding';
```

There are two ways to make lookups find every similar entry:

- Set `ivfflat.probes`, the number of lists to search, to at least the
  number of lists in the index, which makes the search exact; the script
  sets it to 100 for the session.
- Call `semantic_cache.set_index_type('hnsw')` before
  `rebuild_index()`, so that the cache uses an HNSW index, which needs no
  rows to build a good index.

Calling `rebuild_index()` again once the cache holds data does not help,
because the function deletes every entry before it creates the index, so
pgvector picks random centres again; only the number of lists changes.

The following block sets the number of lists to search for the session:

```sql
-- The cache table has an IVFFlat index, which by default searches only
-- the one list of vectors nearest to the query, and so can miss a close
-- entry in another list. Searching 100 lists makes the search exact for
-- an index of up to 100 lists; the lists setting in the indexdef column
-- of pg_indexes, for semantic_cache.idx_cache_embedding, shows how many
-- lists the index has.
SET ivfflat.probes = 100;
```

Searching more lists makes each lookup slower, which matters little for a
small cache; for a large cache, an HNSW index avoids the problem without
searching every list.

## Caching the Answer

The `semantic_cache.cache_query()` function stores the original question,
its embedding, and the answer, which the script tags with `cookbook` and
`cookbook-similar-question`. The following block caches the answer for an
hour:

```sql
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
```

## Looking Up the Other Questions

The `semantic_cache.get_cached_result()` function returns the closest
unexpired entry whose similarity is at least the threshold. The `found`
column is `true` for a hit; for a miss, the `similarity_score` column still
reports the similarity of the closest entry, which helps when choosing a
threshold. The following block looks up the rewording and the unrelated
question, and prints whether each one hits:

```sql
-- Look up each of the other questions. A miss still reports the
-- similarity of the closest entry, which is below the threshold.
SELECT format('%s -> %s', :'reworded',
              CASE WHEN found THEN 'hit' ELSE 'miss' END)
  FROM semantic_cache.get_cached_result(:'reworded_embedding', :threshold);

SELECT format('%s -> %s', :'unrelated',
              CASE WHEN found THEN 'hit' ELSE 'miss' END)
  FROM semantic_cache.get_cached_result(:'unrelated_embedding', :threshold);
```

A threshold that is too low returns the answer to a different question,
such as one about customer sign-ups rather than orders; with
`nomic-embed-text`, the question "How many customers signed up last
month?" has a similarity of about 0.73 to "How many orders did we ship
last month?". Choose the threshold by testing questions that should and
should not match.

## Removing the Entries

The `semantic_cache.invalidate_cache()` function removes the entry by its
`cookbook-similar-question` tag. The following block removes the entry:

```sql
-- Remove the entries that this program created.
SELECT semantic_cache.invalidate_cache(tag => 'cookbook-similar-question')
       AS removed
\gset
\echo Removed :removed cached entry
```

The script runs the steps that change the cache between `BEGIN` and
`COMMIT`, so a failed run leaves no entry behind. Each lookup updates the
hit and miss counters in the single row of the
`semantic_cache.cache_metadata` table, so a lookup in an open transaction
makes other sessions' lookups wait until the transaction ends; keep such
transactions short.

## Running the Example

The complete script is available in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/semantic_cache/similar_question).
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
-- Finding a cached answer to a reworded question with pg_semantic_cache.
--
-- Copyright (c) 2026, pgEdge, Inc.
-- This code is released under the PostgreSQL License.

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

-- Get the embedding of each question from the pgEdge Vectorizer before
-- changing the cache, so that a failure here leaves nothing behind.
SELECT pgedge_vectorizer.generate_embedding(:'question')::text
           AS question_embedding,
       pgedge_vectorizer.generate_embedding(:'reworded')::text
           AS reworded_embedding,
       pgedge_vectorizer.generate_embedding(:'unrelated')::text
           AS unrelated_embedding
\gset

-- The cache table has an IVFFlat index, which by default searches only
-- the one list of vectors nearest to the query, and so can miss a close
-- entry in another list. Searching 100 lists makes the search exact for
-- an index of up to 100 lists; the lists setting in the indexdef column
-- of pg_indexes, for semantic_cache.idx_cache_embedding, shows how many
-- lists the index has.
SET ivfflat.probes = 100;

-- Run every step that changes the cache in one transaction, so that
-- PostgreSQL rolls the new entry back if any step fails.
BEGIN;

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

-- Look up each of the other questions. A miss still reports the
-- similarity of the closest entry, which is below the threshold.
SELECT format('%s -> %s', :'reworded',
              CASE WHEN found THEN 'hit' ELSE 'miss' END)
  FROM semantic_cache.get_cached_result(:'reworded_embedding', :threshold);

SELECT format('%s -> %s', :'unrelated',
              CASE WHEN found THEN 'hit' ELSE 'miss' END)
  FROM semantic_cache.get_cached_result(:'unrelated_embedding', :threshold);

-- Remove the entries that this program created.
SELECT semantic_cache.invalidate_cache(tag => 'cookbook-similar-question')
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
  describes every function in version 0.1.0-beta4.
- The pgvector documentation on
  [IVFFlat indexes](https://github.com/pgvector/pgvector#ivfflat) explains
  lists and probes.
- The [Measuring the Cache Hit Rate](cache_statistics.md) recipe shows how
  to read the hits and misses that each lookup records.
