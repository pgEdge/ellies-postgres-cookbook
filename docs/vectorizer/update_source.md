# Keeping Embeddings Up to Date

This recipe shows how pgEdge Vectorizer keeps a table's embeddings in step
with its text. The trigger that `enable_vectorization()` adds to the table
notices when an `UPDATE` changes a row's text, replaces the row's chunks
with chunks of the new text, and queues them for the background worker. The
script vectorizes three rows, changes the text of one of them, waits for
the new embedding, and then finds the new text with a search by meaning.

These examples are for pgEdge Vectorizer 1.1.

The script prints the following output:

```text
Before the update: Jupiter is the largest planet in the solar system, with dozens of moons.
After the update: Saturn is famous for its bright rings of ice and rock.
Chunks for row 2 with embeddings: 1
Question: Which planet has rings?
Top match (row 2): Saturn is famous for its bright rings of ice and rock.
```

The distances, and so the order of the search results, depend on the
embedding model and on the build of the model. The rows in this example
cover subjects far enough apart that the top match should not change, but
the order of the other rows can. The output above came from Ollama's
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
--8<-- "recipes/vectorizer/update_source/sql/main.sql:settings"
```

## Waiting for the Embeddings

The script waits for the background worker twice, once after vectorizing
the table and once after the update, so it keeps the waiting loop in a
function rather than repeating a `DO` block. A function created in the
`pg_temp` schema belongs to the session, and PostgreSQL drops it when the
session ends, so it needs no cleanup. The function checks the queue once a
second, stops when no item for the chunk table is pending or in progress,
and raises an error if an item fails or the wait passes five minutes; a
model that is not yet in memory can take some time to answer its first
request. The following code creates the function:

```sql
--8<-- "recipes/vectorizer/update_source/sql/main.sql:wait"
```

## Vectorizing the Rows

The script creates a table with a primary key, inserts three rows, and
calls `enable_vectorization()` for the text column. The function returns
`void`, as does the waiting function, so the script selects no columns
from either, and psql prints nothing for them. Once the worker has embedded
the chunks, the script prints the chunk for the second row. The following
code vectorizes the table:

```sql
--8<-- "recipes/vectorizer/update_source/sql/main.sql:setup"
```

## Updating a Row

The trigger runs for each row that an `UPDATE` touches, and compares the
new text with the old. When the text has changed, the trigger deletes the
row's chunks, chunks the new text, and queues the new chunks; when the text
is the same once leading and trailing spaces are ignored, the trigger
does nothing, so an update to another column does not cost a call to the
model. Until the worker embeds the new chunks, a search does not find the
row by its new text. The following code changes the text of the second row
and waits for the worker:

```sql
--8<-- "recipes/vectorizer/update_source/sql/main.sql:update"
```

## Checking the New Embedding

The chunk table now holds the new text for the second row, with an
embedding of that text. A search for a question about rings finds the
updated row, which the old text about Jupiter would not have matched. The
following code shows the new chunk and runs the search:

```sql
--8<-- "recipes/vectorizer/update_source/sql/main.sql:check"
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
--8<-- "recipes/vectorizer/update_source/sql/main.sql:cleanup"
```

## Running the Example

The script is available in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/vectorizer/update_source).
Set the `PG*` environment variables for your server, and then run the
following command from the recipe's `sql` directory:

```bash
psql -X -q -v ON_ERROR_STOP=1 -f main.sql
```

## Viewing the Complete Program

The following code shows the complete script:

```sql
--8<-- "recipes/vectorizer/update_source/sql/main.sql"
```

## Next Steps

The following resources provide more information about the topics in this
recipe:

- The [Monitoring the Embedding Queue](queue_status.md) recipe reads the
  views that report on the queue.
- The [Searching Vectorized Text](semantic_search.md) recipe explains the
  search by meaning.
- The [pgEdge Vectorizer documentation](https://docs.pgedge.com/pgedge-vectorizer/)
  describes the triggers and the queue.
