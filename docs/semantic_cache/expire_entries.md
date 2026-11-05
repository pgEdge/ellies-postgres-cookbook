# Expiring Cached Results

This recipe demonstrates how a cached result in
[pg_semantic_cache](https://github.com/pgEdge/pg_semantic_cache) expires
after a lifetime that the application chooses, and how to delete expired
results from the cache. A lookup ignores an entry as soon as the entry
expires, but the entry stays in the cache table until a call to
`evict_expired()` deletes it. The example is a psql script, because the
extension is used entirely through SQL functions.

These examples are for pg_semantic_cache 0.1.0-beta4.

The script caches a result for one second, looks it up before and after
the second has passed, and then evicts the expired entry. The script prints
the following output:

```text
Cached the result for 1 second
Lookup straight away: hit
Lookup after 2 seconds: miss
Entries still stored: 1
Entries stored after evict_expired(): 0
```

## Preparing the Ingredients

The script needs the same server as the [Caching a Query
Result](cache_result.md) recipe: pg_semantic_cache with a vector dimension
of 768, and the pgEdge Vectorizer creating embeddings with
`nomic-embed-text` through Ollama. That recipe describes how to configure
both extensions.

## Setting Up the Script

The script stops at the first error, and prints plain lines rather than
tables. A psql variable holds the question that the script caches. The
following block shows the start of the script:

```sql
--8<-- "recipes/semantic_cache/expire_entries/sql/main.sql:setup"
```

## Getting the Embedding

The `pgedge_vectorizer.generate_embedding()` function returns the
embedding of the question, which the script stores as text in a psql
variable. The following block gets the embedding:

```sql
--8<-- "recipes/semantic_cache/expire_entries/sql/main.sql:embed"
```

## Removing Entries from an Earlier Run

The script cannot make its changes in a single transaction, which would
roll them back after a failure, because PostgreSQL fixes the value of
`now()` at the start of a
transaction, so the entry would never appear to expire. Each statement
commits on its own instead. If a run stops part-way, the entry expires a
second later, and lookups ignore it from then on; the next call to
`evict_expired()` deletes it.

The cache keeps one entry for each question text, and caching the same
question again leaves the expiry time of the existing entry unchanged. The
script therefore starts by removing any entry that an interrupted run left
behind, with the `semantic_cache.invalidate_cache()` function and the
`cookbook-expire-entries` tag. The following block removes those entries:

```sql
--8<-- "recipes/semantic_cache/expire_entries/sql/main.sql:sweep"
```

## Caching a Short-Lived Result

The `ttl_seconds` argument of `semantic_cache.cache_query()` sets the
lifetime of the entry in seconds; the default is 3600, and the maximum is
one year. The cache sets the expiry time of the entry to the current time
plus the lifetime. The following block caches the result for one second,
and looks it up at once:

```sql
--8<-- "recipes/semantic_cache/expire_entries/sql/main.sql:cache"
```

## Waiting for the Result to Expire

After two seconds, the entry has expired, and
`semantic_cache.get_cached_result()` reports a miss, because the function
considers only entries whose expiry time is still in the future. The entry
is still in the `semantic_cache.cache_entries` table, however. The
following block waits, looks the result up again, and counts the entries
that the script created:

```sql
--8<-- "recipes/semantic_cache/expire_entries/sql/main.sql:wait"
```

## Evicting Expired Entries

The `semantic_cache.evict_expired()` function deletes every expired entry
in the cache, and returns the number of entries that it deleted. The
function acts on the whole cache rather than on one application's entries,
so the count includes the expired entries of any other application on the
server; the script prints how many of its own entries remain instead. The
following block evicts the expired entries:

```sql
--8<-- "recipes/semantic_cache/expire_entries/sql/main.sql:evict"
```

Expired entries take up space in the table and its index until something
deletes them, so a scheduler such as `pg_cron` can call `evict_expired()`
at regular intervals. The `semantic_cache.auto_evict()` function also
deletes expired entries, and then applies the eviction policy in the cache
configuration.

## Running the Example

The complete script is available in the [cookbook
repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/semantic_cache/expire_entries).
psql reads its connection settings from the standard `PG*` environment
variables. Set the variables for your server, and then run the following
command from the `sql` directory of the recipe:

```bash
psql -X -q -v ON_ERROR_STOP=1 -f main.sql
```

## Viewing the Complete Program

The following block shows the complete script:

```sql
--8<-- "recipes/semantic_cache/expire_entries/sql/main.sql"
```

## Next Steps

The following resources provide more information about the topics in this
recipe:

- The [pg_semantic_cache function
  reference](https://github.com/pgEdge/pg_semantic_cache/tree/f946dff6183984dd0eebc962031eb66d6668c014/docs/functions)
  describes `evict_expired()`, `auto_evict()`, and the functions that
  evict the least recently and least frequently used entries.
- The [Invalidating Cached Results by Tag](invalidate_by_tag.md) recipe
  removes results when the data behind them changes, rather than after a
  fixed time.
