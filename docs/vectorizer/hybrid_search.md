# Combining Keyword and Vector Search

This recipe shows how to rank text by its keywords and by its meaning at
the same time. A search by meaning alone can miss an exact term, such as a
product name or an error code, that a keyword search finds at once; hybrid
search runs both and merges the two rankings. The script vectorizes a
table of three rows, waits for the background worker, and then calls
`pgedge_vectorizer.hybrid_search_simple()` with a question.

These examples are for pgEdge Vectorizer 1.1.

The script prints the following output:

```text
Chunks with keyword vectors: 3
Question: Which database stores tables?
Top match (row 3): PostgreSQL stores data in tables and answers questions written in SQL.
```

The vector half of the ranking depends on the embedding model and on the
build of the model. The rows in this example cover subjects far enough
apart, and share enough keywords with the question, that the top match
should not change, but the order of the other rows can. The output above
came from Ollama's `nomic-embed-text` model with the digest
`0a109f422b47`.

## Preparing the Ingredients

The script needs a PostgreSQL server with the `vector` and
`pgedge_vectorizer` extensions, and an embedding model that the server can
reach. The [Vectorizing a Table](enable_vectorization.md) recipe lists the
server settings that the examples use. Hybrid search also needs the
following setting, which tells the background worker to compute a sparse
BM25 vector for each chunk alongside its embedding:

```ini
pgedge_vectorizer.enable_hybrid = on
```

The setting must apply to the background worker as well as to the session
that searches, so set it in `postgresql.conf` and reload the
configuration, or set it on the server's command line, rather than in the
session alone.
Chunks that the worker embedded before the setting took effect have no
sparse vector until `pgedge_vectorizer.reprocess_chunks()` queues them
again.

## Configuring psql

The script prints plain lines, and it hides the `NOTICE` messages that the
Vectorizer functions raise. A failed step must not stop the script before
the cleanup at the end, so the script turns off `ON_ERROR_STOP` until the
cleanup starts. The following code shows the settings:

```sql
--8<-- "recipes/vectorizer/hybrid_search/sql/main.sql:settings"
```

## Vectorizing the Rows

The script creates a table with a primary key, inserts three rows, and
calls `enable_vectorization()` for the text column, which creates the
`cookbook_hybrid_search_content_chunks` table and queues each chunk for the
background worker. The following code creates and vectorizes the table:

```sql
--8<-- "recipes/vectorizer/hybrid_search/sql/main.sql:setup"
```

## Waiting for the Embeddings

The script waits in a `DO` block that checks the queue once a second. The
block stops when no item for the chunk table is pending or in progress,
and raises an error if an item fails or the wait passes five minutes; a
model that is not yet in memory can take some time to answer its first
request. The worker computes each chunk's embedding and sparse vector
together, so one wait covers both. The following code waits for the
worker:

```sql
--8<-- "recipes/vectorizer/hybrid_search/sql/main.sql:wait"
```

## Checking the Keyword Vectors

The worker stores the sparse BM25 vector of each chunk in the
`sparse_embedding` column of the chunk table, and leaves the column empty
when `enable_hybrid` is off. The following code counts the chunks that
have a sparse vector:

```sql
--8<-- "recipes/vectorizer/hybrid_search/sql/main.sql:check"
```

## Searching by Keyword and Meaning

The `hybrid_search_simple()` function takes the source table rather than
the chunk table, and looks up the chunk table in the extension's registry.
The function ranks the chunks by the cosine distance of their embeddings
from the question's embedding, and separately by their BM25 keyword score,
and then merges the two lists with Reciprocal Rank Fusion (RRF). Each
result carries the source row's primary key as text, the chunk, and the
`rrf_score`, which is highest for the best match. The
`pgedge_vectorizer.hybrid_search()` function takes the same arguments with
two more, for the weight of the vector ranking and the RRF constant, and
also returns each chunk's rank in both lists.

The script keeps the question in a psql variable, and psql writes the value
into the query as a quoted string literal, escaping any quotes inside it.
The following code runs the search:

```sql
--8<-- "recipes/vectorizer/hybrid_search/sql/main.sql:search"
```

## Cleaning Up

The `disable_vectorization()` function drops the triggers and, with
`drop_chunk_table`, the chunk table and its table of keyword statistics,
and it removes the table's pending items from the queue. Completed items
stay in the queue; the `clear_completed(0)` function would remove them at
once, but for every vectorized table in the database, so the script
deletes only the items for its own chunk table. The script then checks
psql's `LAST_ERROR_SQLSTATE` variable, and raises an error if an earlier
step failed, so that psql exits with a non-zero status. The following code
removes everything that the script created:

```sql
--8<-- "recipes/vectorizer/hybrid_search/sql/main.sql:cleanup"
```

## Running the Example

The script is available in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/vectorizer/hybrid_search).
Set the `PG*` environment variables for your server, and then run the
following command from the recipe's `sql` directory:

```bash
psql -X -q -v ON_ERROR_STOP=1 -f main.sql
```

## Viewing the Complete Program

The following code shows the complete script:

```sql
--8<-- "recipes/vectorizer/hybrid_search/sql/main.sql"
```

## Next Steps

The following resources provide more information about the topics in this
recipe:

- The [Searching Vectorized Text](semantic_search.md) recipe searches by
  meaning alone, with the pgvector distance operator.
- The [Splitting Text into Chunks](chunk_text.md) recipe shows how the
  extension divides a document before it embeds the chunks.
- The [pgEdge Vectorizer documentation](https://docs.pgedge.com/pgedge-vectorizer/)
  describes the hybrid search functions and their settings.
