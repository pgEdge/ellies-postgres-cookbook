# Caching a Query Result

This recipe demonstrates how an application stores the result of an
expensive query in [pg_semantic_cache](https://github.com/pgEdge/pg_semantic_cache),
and then reads the result back. The cache finds a result by the meaning of
the question rather than by its exact text: each entry holds an embedding
of the question, and a lookup returns the entry whose embedding is most
similar to the embedding of the new question. The example is a psql
script, because the extension is used entirely through SQL functions.

These examples are for pg_semantic_cache 0.1.0-beta4.

The script caches the answer to a question about shipped orders, looks the
answer up with the same embedding, and then removes the entry. The script
prints the following output:

```text
Cached the result for 3600 seconds with tags {cookbook,cookbook-cache-result}
Found: true
Similarity: 1.00
Result: {"orders_shipped": 1234}
Removed 1 cached entry
```

## Preparing the Ingredients

pg_semantic_cache stores embeddings but does not create them, so the
script asks the [pgEdge Vectorizer](https://github.com/pgEdge/pgedge-vectorizer)
for each embedding with its `pgedge_vectorizer.generate_embedding()`
function. The examples need a server with the following components:

- pg_semantic_cache 0.1.0-beta4 and pgvector, which the cache uses to store
  and compare the embeddings.
- The pgEdge Vectorizer, configured to create embeddings with the
  `nomic-embed-text` model through [Ollama](https://ollama.com/).
- A cache whose vector dimension matches the model; `nomic-embed-text`
  creates embeddings with 768 dimensions, whereas pg_semantic_cache expects
  1536 by default.

The `generate_embedding()` function calls the model from the session that
runs it, so it does not need the Vectorizer's background workers. The
following settings in `postgresql.conf` configure the Vectorizer to use
Ollama on the local machine:

```ini
pgedge_vectorizer.provider = 'ollama'
pgedge_vectorizer.api_url = 'http://localhost:11434'
pgedge_vectorizer.model = 'nomic-embed-text'
```

The following statements create the extensions and set the dimension of
the cache. The `rebuild_index()` function recreates the cache table with
the new dimension, and deletes every entry in the cache, so run it only on
a new cache:

```sql
CREATE EXTENSION IF NOT EXISTS pgedge_vectorizer;
CREATE EXTENSION IF NOT EXISTS pg_semantic_cache;
SELECT semantic_cache.set_vector_dimension(768);
SELECT semantic_cache.rebuild_index();
```

## Setting Up the Script

The script stops at the first error, and prints plain lines rather than
tables, so that its output is easy to read. A psql variable holds the
question that the script caches. The following block shows the start of
the script:

```sql
--8<-- "recipes/semantic_cache/cache_result/sql/main.sql:setup"
```

## Getting the Embedding

The `generate_embedding()` function sends the question to the model, and
returns the embedding as a pgvector `vector` value. pg_semantic_cache
accepts embeddings as text, so the script casts the value to `text`, and
the psql `\gset` command stores the result in a variable named after the
column. The following block shows how the script gets the embedding:

```sql
--8<-- "recipes/semantic_cache/cache_result/sql/main.sql:embed"
```

## Caching the Result

The `semantic_cache.cache_query()` function stores the question, its
embedding, and the result as a `jsonb` value, and returns the id of the
new entry. The following table describes the arguments of the function:

| Argument          | Type      | Description                                   |
|-------------------|-----------|-----------------------------------------------|
| `query_text`      | `text`    | The question; one entry per distinct text.    |
| `query_embedding` | `text`    | The embedding, such as `[0.1,0.2,...]`.       |
| `result_data`     | `jsonb`   | The result to return to later lookups.        |
| `ttl_seconds`     | `integer` | The lifetime in seconds; 3600 by default.     |
| `tags`            | `text[]`  | Labels for removing entries in groups.        |

The cache identifies an entry by the MD5 hash of its question text. If an
entry for the same text already exists, `cache_query()` returns the id of
that entry and counts another access, but leaves its result, tags, and
expiry time unchanged. The script tags the entry with `cookbook` and
`cookbook-cache-result`, so that it can later remove exactly the entries
that it created. The following block caches the result, and prints the
lifetime and tags of the new entry:

```sql
--8<-- "recipes/semantic_cache/cache_result/sql/main.sql:cache"
```

## Looking Up the Result

The `semantic_cache.get_cached_result()` function takes an embedding and a
similarity threshold, and returns one row. The `found` column reports
whether an unexpired entry is at least as similar as the threshold; the
row also holds the cached result, the cosine similarity between the two
embeddings, and the age of the entry in seconds. The script looks the
result up with the embedding that it cached, so the similarity rounds to
1.00. The following block shows the lookup:

```sql
--8<-- "recipes/semantic_cache/cache_result/sql/main.sql:lookup"
```

The function also counts each lookup as a hit or a miss, by updating the
single row of the `semantic_cache.cache_metadata` table; the [Measuring
the Cache Hit Rate](cache_statistics.md) recipe shows how to read those
statistics.

## Removing the Entries

The cache is a single table that every application on the server shares,
so the script removes only its own entries. The
`semantic_cache.invalidate_cache()` function deletes every entry whose tags
include the tag that it receives, and returns the number of entries that
it deleted. The following block removes the entry:

```sql
--8<-- "recipes/semantic_cache/cache_result/sql/main.sql:cleanup"
```

The script runs the steps that change the cache between `BEGIN` and
`COMMIT`. If any step fails, psql stops, and PostgreSQL rolls back the
transaction, so a failed run leaves no entry behind. An application would
normally commit each cached result at once, so that other sessions can
find it, and would not look anything up inside a long transaction: every
lookup updates the same `cache_metadata` row, so a lookup in an open
transaction locks that row, and other sessions' lookups wait until the
transaction ends.

## Running the Example

The complete script is available in the [cookbook
repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/semantic_cache/cache_result).
psql reads its connection settings from the standard `PG*` environment
variables. Set the variables for your server, and then run the following
command from the `sql` directory of the recipe:

```bash
psql -X -q -v ON_ERROR_STOP=1 -f main.sql
```

## Viewing the Complete Program

The following block shows the complete script:

```sql
--8<-- "recipes/semantic_cache/cache_result/sql/main.sql"
```

## Next Steps

The following resources provide more information about the topics in this
recipe:

- The [pg_semantic_cache function
  reference](https://github.com/pgEdge/pg_semantic_cache/tree/f946dff6183984dd0eebc962031eb66d6668c014/docs/functions)
  describes every function in version 0.1.0-beta4.
- The [Finding an Answer to a Reworded Question](similar_question.md)
  recipe looks up a cached result with a question that uses different
  words.
- The [Expiring Cached Results](expire_entries.md) and [Invalidating Cached
  Results by Tag](invalidate_by_tag.md) recipes show two ways to remove
  results that are out of date.
