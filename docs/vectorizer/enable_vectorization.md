# Vectorizing a Table

This recipe shows how to keep embeddings for a text column up to date
without writing any application code. The script creates a table with three
rows, and calls `pgedge_vectorizer.enable_vectorization()` for its text
column. The extension splits each row into chunks, stores the chunks in a
table of its own, and queues them; a background worker then asks the
embedding model for an embedding of each chunk. The script waits for the
worker, reports what the extension created, and then removes everything
again.

These examples are for pgEdge Vectorizer 1.1.

The script prints the following output:

```text
Chunk table: cookbook_enable_vectorization_content_chunks
Chunks: 3
Chunks with embeddings: 3
Embedding dimensions: 768
```

## Preparing the Ingredients

The script needs a PostgreSQL server with the `vector` (pgvector) and
`pgedge_vectorizer` extensions installed in the database, and an embedding
model that the server can reach. Creating the `pgedge_vectorizer` extension
requires a superuser, and the server must load the extension's library at
start-up. The examples use Ollama with the `nomic-embed-text` model, which
returns embeddings with 768 dimensions.

The following table lists the server settings that the examples use:

| Setting                            | Value                         |
|------------------------------------|-------------------------------|
| `shared_preload_libraries`         | `pgedge_vectorizer`           |
| `pgedge_vectorizer.provider`       | `ollama`                      |
| `pgedge_vectorizer.api_url`        | `http://localhost:11434`      |
| `pgedge_vectorizer.model`          | `nomic-embed-text`            |
| `pgedge_vectorizer.databases`      | `postgres`                    |

The background worker only processes the queue in the databases that
`pgedge_vectorizer.databases` lists, so the list must include the database
that the script connects to. Change `pgedge_vectorizer.api_url` to the
address at which the server can reach Ollama. The following commands
create the extensions once the server is running with these settings:

```sql
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS pgedge_vectorizer;
```

## Configuring psql

The script prints plain lines, so that its output is easy to read and to
compare, and it hides the `NOTICE` messages that the Vectorizer functions
raise. A failed step must not stop the script before the cleanup at the
end, so the script turns off `ON_ERROR_STOP` until the cleanup starts. The
following code shows the settings:

```sql
--8<-- "recipes/vectorizer/enable_vectorization/sql/main.sql:settings"
```

## Creating the Table

The background worker reads the chunks in a session of its own, so the
table must be an ordinary table that every session can see, rather than a
temporary table. The table also needs a primary key, which the extension
uses to link each chunk back to its row. The following code creates the
table and inserts three rows:

```sql
--8<-- "recipes/vectorizer/enable_vectorization/sql/main.sql:setup"
```

## Enabling Vectorization

The `enable_vectorization()` function takes the table and the name of the
text column. The function creates a chunk table named after the table and
the column, with an HNSW index for cosine distance. The function also adds
triggers that chunk and queue each row that an `INSERT` or `UPDATE`
changes, and that remove the chunks of deleted rows, and it chunks and
queues the rows that the table already holds. Optional
arguments choose the chunking strategy, the chunk size and the overlap;
without them, the extension uses the server's default settings. The
following code enables vectorization for the `content` column:

```sql
--8<-- "recipes/vectorizer/enable_vectorization/sql/main.sql:vectorize"
```

## Waiting for the Embeddings

The background worker embeds the queued chunks in batches, so the
embeddings appear shortly after the rows rather than at once. The script
waits in a `DO` block that checks the queue once a second, through the
`pgedge_vectorizer.queue_status` and `pgedge_vectorizer.failed_items`
views. The block stops when no item for the chunk table is pending or in
progress, and raises an error if an item fails or the wait passes five
minutes. A model that is not yet in memory can take some time to answer its
first request, particularly on a server without a GPU. The following code
waits for the worker:

```sql
--8<-- "recipes/vectorizer/enable_vectorization/sql/main.sql:wait"
```

## Inspecting the Chunks

The `pgedge_vectorizer.vectorizers` table records the chunk table for each
vectorized column. Each chunk row holds the chunk's text, the primary key
of its source row in `source_id`, and the embedding. The rows in this
example are short, so each fits in a single chunk. The following code
reports the chunk table, the number of chunks, and the dimensions of an
embedding:

```sql
--8<-- "recipes/vectorizer/enable_vectorization/sql/main.sql:inspect"
```

## Cleaning Up

The `disable_vectorization()` function drops the triggers, removes the
table's pending items from the queue, and with `drop_chunk_table` drops the
chunk table too. The function leaves the table's completed items in the
queue, and the extension's `clear_completed()` function deletes completed
items only once they are older than 24 hours by default. Calling
`clear_completed(0)` removes them at once, but for every vectorized table
in the database, so the script deletes only the items for its own chunk
table instead.

The cleanup turns `ON_ERROR_STOP` back on, so that a failure during the
cleanup stops the script with an error. Finally, the script checks the
`LAST_ERROR_SQLSTATE` variable, in which psql keeps the SQLSTATE code of the
most recent error, and raises an error if an earlier step failed; psql then
exits with a non-zero status. The following code removes everything that
the script created:

```sql
--8<-- "recipes/vectorizer/enable_vectorization/sql/main.sql:cleanup"
```

## Running the Example

The script is available in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/vectorizer/enable_vectorization).
Set the `PG*` environment variables for your server, and then run the
following command from the recipe's `sql` directory:

```bash
psql -X -q -v ON_ERROR_STOP=1 -f main.sql
```

## Viewing the Complete Program

The following code shows the complete script:

```sql
--8<-- "recipes/vectorizer/enable_vectorization/sql/main.sql"
```

## Next Steps

The following resources provide more information about the topics in this
recipe:

- The [Searching Vectorized Text](semantic_search.md) recipe uses the
  embeddings to find the row closest in meaning to a question.
- The [Monitoring the Embedding Queue](queue_status.md) recipe reads the
  views that report on the queue.
- The [pgEdge Vectorizer documentation](https://docs.pgedge.com/pgedge-vectorizer/)
  describes every function and setting of the extension.
