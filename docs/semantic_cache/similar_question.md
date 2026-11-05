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

The script needs the same server as the [Caching a Query
Result](cache_result.md) recipe: pg_semantic_cache with a vector dimension
of 768, and the pgEdge Vectorizer creating embeddings with
`nomic-embed-text` through Ollama. That recipe describes how to configure
both extensions.

## Setting Up the Script

The script stops at the first error, and prints plain lines rather than
tables. psql variables hold the three questions and the similarity
threshold, which is the lowest cosine similarity that the script treats as
the same question. The following block shows the start of the script:

```sql
--8<-- "recipes/semantic_cache/similar_question/sql/main.sql:setup"
```

## Getting the Embeddings

The script gets the embedding of every question before it changes the
cache, so that a failure to reach the model leaves nothing in the cache.
The following block gets the three embeddings in one query, and stores
them in psql variables:

```sql
--8<-- "recipes/semantic_cache/similar_question/sql/main.sql:embed"
```

## Searching Every List of the Index

pg_semantic_cache indexes the embeddings with a pgvector IVFFlat index,
which divides the vectors into lists, and by default searches only the list
nearest to the query. A lookup can therefore miss a similar entry that lies
in another list; when the script was tested without the setting below, a
question with a similarity of 0.757 missed an entry with a threshold of
0.75. The `ivfflat.probes` setting sets the number of lists to search, and
a value at least as large as the number of lists makes the search exact.
pg_semantic_cache creates 100 lists in a new cache, and `rebuild_index()`
creates between 10 and 1,000 lists, depending on the number of entries.
The following block sets the number of lists for the session:

```sql
--8<-- "recipes/semantic_cache/similar_question/sql/main.sql:probes"
```

Searching more lists makes each lookup slower, which matters little for a
small cache; a large cache might use a smaller value, and accept that a
lookup occasionally misses.

## Caching the Answer

The `semantic_cache.cache_query()` function stores the original question,
its embedding, and the answer, which the script tags with `cookbook` and
`cookbook-similar-question`. The following block caches the answer for an
hour:

```sql
--8<-- "recipes/semantic_cache/similar_question/sql/main.sql:cache"
```

## Looking Up the Other Questions

The `semantic_cache.get_cached_result()` function returns the closest
unexpired entry whose similarity is at least the threshold. The `found`
column is `true` for a hit; for a miss, the `similarity_score` column still
reports the similarity of the closest entry, which helps when choosing a
threshold. The following block looks up the rewording and the unrelated
question, and prints whether each one hits:

```sql
--8<-- "recipes/semantic_cache/similar_question/sql/main.sql:lookup"
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
--8<-- "recipes/semantic_cache/similar_question/sql/main.sql:cleanup"
```

The script runs the steps that change the cache between `BEGIN` and
`COMMIT`, so a failed run leaves no entry behind.

## Running the Example

The complete script is available in the [cookbook
repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/semantic_cache/similar_question).
psql reads its connection settings from the standard `PG*` environment
variables. Set the variables for your server, and then run the following
command from the `sql` directory of the recipe:

```bash
psql -X -q -v ON_ERROR_STOP=1 -f main.sql
```

## Viewing the Complete Program

The following block shows the complete script:

```sql
--8<-- "recipes/semantic_cache/similar_question/sql/main.sql"
```

## Next Steps

The following resources provide more information about the topics in this
recipe:

- The [pg_semantic_cache function
  reference](https://github.com/pgEdge/pg_semantic_cache/tree/f946dff6183984dd0eebc962031eb66d6668c014/docs/functions)
  describes every function in version 0.1.0-beta4.
- The pgvector documentation on [IVFFlat
  indexes](https://github.com/pgvector/pgvector#ivfflat) explains lists and
  probes.
- The [Measuring the Cache Hit Rate](cache_statistics.md) recipe shows how
  to read the hits and misses that each lookup records.
