# Invalidating Cached Results by Tag

This recipe demonstrates how an application removes cached results from
[pg_semantic_cache](https://github.com/pgEdge/pg_semantic_cache) when the
data behind them changes. Each entry carries a list of tags, such as the
names of the tables that the result was read from, and one call removes
every entry with a given tag. The example is a psql script, because the
extension is used entirely through SQL functions.

These examples are for pg_semantic_cache 0.1.0-beta4.

The script caches one result about orders and one about customers, then
invalidates the results tagged with the orders table, and looks up both
questions again. The script prints the following output:

```text
Cached 2 results
Invalidated 1 entry tagged cookbook-orders
Orders question -> miss
Customers question -> hit
Removed 1 remaining cached entry
```

## Preparing the Ingredients

The script needs the same server as the
[Caching a Query Result](cache_result.md) recipe: pg_semantic_cache with a
vector dimension of 768, and the pgEdge Vectorizer creating embeddings with
`nomic-embed-text` through Ollama. That recipe describes how to configure both
extensions.

## Setting Up the Script

The script stops at the first error, and prints plain lines rather than
tables. psql variables hold the two questions that the script caches. The
following block shows the start of the script:

```sql
--8<-- "recipes/semantic_cache/invalidate_by_tag/sql/main.sql:setup"
```

## Getting the Embeddings

The script gets the embedding of each question before it changes the
cache, so that a failure to reach the model leaves nothing in the cache.
The following block gets both embeddings in one query:

```sql
--8<-- "recipes/semantic_cache/invalidate_by_tag/sql/main.sql:embed"
```

## Caching Tagged Results

The `tags` argument of `semantic_cache.cache_query()` takes an array of
text labels. The script tags each result with the table that it describes,
`cookbook-orders` or `cookbook-customers`, and with the `cookbook` and
`cookbook-invalidate-by-tag` tags that identify the entries that the script
created. The following block caches both results:

```sql
--8<-- "recipes/semantic_cache/invalidate_by_tag/sql/main.sql:cache"
```

## Invalidating the Orders Results

The `semantic_cache.invalidate_cache()` function takes a `tag` argument,
deletes every entry whose tags include that tag, and returns the number of
entries that it deleted. The function also takes a `pattern` argument,
which deletes every entry whose question text matches a `LIKE` pattern;
with both arguments, the function deletes the entries that match either
one. The following block invalidates the results tagged with the orders
table:

```sql
--8<-- "recipes/semantic_cache/invalidate_by_tag/sql/main.sql:invalidate"
```

An application can make the same call from a trigger on the orders table,
or after a batch job that loads new orders, so that the cache never returns
a result that is out of date.

## Looking Up Both Questions

The script looks up each question with its own embedding, and a threshold
of 0.95. The orders question now misses, because its entry is gone, and
the customers question still hits. The orders question cannot match the
customers entry instead, because the two questions are far apart: with the
`nomic-embed-text` model in Ollama (digest `0a109f422b47`), their
similarity is about 0.61. The similarity depends on the embedding model,
but a threshold of 0.95 leaves a wide margin. The following block looks up
both questions:

```sql
--8<-- "recipes/semantic_cache/invalidate_by_tag/sql/main.sql:lookup"
```

## Removing the Entries

The script removes the entry that remains with the
`cookbook-invalidate-by-tag` tag. The following block removes the entry:

```sql
--8<-- "recipes/semantic_cache/invalidate_by_tag/sql/main.sql:cleanup"
```

The script runs the steps that change the cache between `BEGIN` and
`COMMIT`. If any step fails, psql stops, and PostgreSQL rolls back the
transaction, so a failed run leaves no entry behind. Each lookup updates
the hit and miss counters in the single row of the
`semantic_cache.cache_metadata` table, so a lookup in an open transaction
makes other sessions' lookups wait until the transaction ends; keep such
transactions short.

## Running the Example

The complete script is available in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/semantic_cache/invalidate_by_tag).
psql reads its connection settings from the standard `PG*` environment
variables. Set the variables for your server, and then run the following
command from the `sql` directory of the recipe:

```bash
psql -X -q -v ON_ERROR_STOP=1 -f main.sql
```

## Viewing the Complete Program

The following block shows the complete script:

```sql
--8<-- "recipes/semantic_cache/invalidate_by_tag/sql/main.sql"
```

## Next Steps

The following resources provide more information about the topics in this
recipe:

- The
  [pg_semantic_cache function reference](https://github.com/pgEdge/pg_semantic_cache/tree/f946dff6183984dd0eebc962031eb66d6668c014/docs/functions)
  describes `invalidate_cache()` and the other functions that remove
  entries.
- The [Expiring Cached Results](expire_entries.md) recipe removes results
  after a fixed time instead.
- The PostgreSQL documentation on
  [triggers](https://www.postgresql.org/docs/current/plpgsql-trigger.html)
  explains how to run a function when a table changes.
