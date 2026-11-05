# Searching Vectorized Text

This recipe shows how to find the text closest in meaning to a question,
even when the question and the text share no words. The script vectorizes
a table of three rows about unrelated subjects, waits for the embeddings,
and then orders the chunks by their distance from an embedding of the
question. The question asks how to bake a loaf, and the closest chunk is
the row about kneading bread dough.

These examples are for pgEdge Vectorizer 1.1.

The script prints the following output:

```text
Question: How do I bake a loaf?
Top match (row 1): Knead the bread dough for ten minutes, then leave it to rise in a warm kitchen.
```

The distances, and so the order of the results, depend on the embedding
model and on the build of the model. The rows in this example cover
subjects far enough apart that the top match should not change, but the
order of the other rows can. The output above came from Ollama's
`nomic-embed-text` model with the digest `0a109f422b47`.

## Preparing the Ingredients

The script needs a PostgreSQL server with the `vector` and
`pgedge_vectorizer` extensions, and an embedding model that the server can
reach. The [Vectorizing a Table](enable_vectorization.md) recipe lists the
server settings that the examples use; the background worker must process
the queue in the database that the script connects to.

## Configuring psql

The script prints plain lines, and it hides the `NOTICE` messages that the
Vectorizer functions raise. A failed step must not stop the script before
the cleanup at the end, so the script turns off `ON_ERROR_STOP` until the
cleanup starts. The following code shows the settings:

```sql
--8<-- "recipes/vectorizer/semantic_search/sql/main.sql:settings"
```

## Vectorizing the Rows

The script creates a table with a primary key, inserts three rows, and
calls `enable_vectorization()` for the text column. The function creates
the `cookbook_semantic_search_content_chunks` table, and queues each chunk
for the background worker to embed. The following code creates and
vectorizes the table:

```sql
--8<-- "recipes/vectorizer/semantic_search/sql/main.sql:setup"
```

## Waiting for the Embeddings

The background worker embeds the chunks shortly after they are queued, so
the script waits in a `DO` block that checks the queue once a second. The
block stops when no item for the chunk table is pending or in progress,
and raises an error if an item fails or the wait passes five minutes; a
model that is not yet in memory can take some time to answer its first
request. The following code waits for the worker:

```sql
--8<-- "recipes/vectorizer/semantic_search/sql/main.sql:wait"
```

## Searching by Meaning

The `pgedge_vectorizer.generate_embedding()` function asks the configured
model for an embedding of the question, in the same session and without
the queue. The `<=>` operator from pgvector returns the cosine distance
between two embeddings, so ordering the chunks by that distance puts the
chunk closest in meaning first. The chunk table has an HNSW index for
cosine distance, which lets a larger table answer the query without
comparing every chunk.

The script keeps the question in a psql variable, and psql writes the value
into the query as a quoted string literal, escaping any quotes inside it.
The scalar subquery asks the model for the embedding once, rather than once
for each chunk. The following code runs the search:

```sql
--8<-- "recipes/vectorizer/semantic_search/sql/main.sql:search"
```

## Cleaning Up

The `disable_vectorization()` function drops the triggers and, with
`drop_chunk_table`, the chunk table, and it removes the table's pending
items from the queue. Completed items stay in the queue; the
`clear_completed(0)` function would remove them at once, but for every
vectorized table in the database, so the script deletes only the items for
its own chunk table. The script then checks psql's `LAST_ERROR_SQLSTATE`
variable, and raises an error if an earlier step failed, so that psql exits
with a non-zero status. The following code removes everything that the
script created:

```sql
--8<-- "recipes/vectorizer/semantic_search/sql/main.sql:cleanup"
```

## Running the Example

The script is available in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/vectorizer/semantic_search).
Set the `PG*` environment variables for your server, and then run the
following command from the recipe's `sql` directory:

```bash
psql -X -q -v ON_ERROR_STOP=1 -f main.sql
```

## Viewing the Complete Program

The following code shows the complete script:

```sql
--8<-- "recipes/vectorizer/semantic_search/sql/main.sql"
```

## Next Steps

The following resources provide more information about the topics in this
recipe:

- The [Combining Keyword and Vector Search](hybrid_search.md) recipe adds
  a keyword ranking to the search by meaning.
- The [Vectorizing a Table](enable_vectorization.md) recipe describes what
  `enable_vectorization()` creates.
- The [pgvector documentation](https://github.com/pgvector/pgvector)
  describes the distance operators and the HNSW index.
