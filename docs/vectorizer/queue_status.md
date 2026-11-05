# Monitoring the Embedding Queue

This recipe shows how to watch pgEdge Vectorizer's queue of chunks waiting
for embeddings. The triggers that the extension adds to a vectorized table
queue an item for each new chunk, and a background worker takes the items
from the queue and embeds them. The extension provides three views of the
queue: `queue_status` counts the items by chunk table and status,
`pending_count` counts the pending items across the database, and
`failed_items` lists the items that have failed. The script reads the views
before and after the worker has embedded three rows.

These examples are for pgEdge Vectorizer 1.1.

The script prints the following output:

```text
Before the commit:
pending: 3
After the worker has finished:
completed: 3
Pending items in the queue: 0
Failed items for the table: 0
```

The `pending_count` view covers every vectorized table in the database, so
on a server where other tables are being vectorized it can report more
items than the script queues.

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
--8<-- "recipes/vectorizer/queue_status/sql/main.sql:settings"
```

## Vectorizing an Empty Table

The script vectorizes the table before it holds any rows, so that the
trigger queues each row as the script inserts it. The following code
creates the table, and calls `enable_vectorization()` for its text column:

```sql
--8<-- "recipes/vectorizer/queue_status/sql/main.sql:setup"
```

## Queueing the Rows

The trigger chunks each row as the `INSERT` adds it, and queues an item
for each chunk, in the same transaction as the `INSERT`. The background
worker cannot see the items until the transaction commits, so a query in
the same transaction sees all three items as pending, whatever the worker
is doing. Once the transaction commits, the worker can take the items at
any moment, so a count read after the commit varies from run to run. The
following code inserts the rows and reads the `queue_status` view before
the commit:

```sql
--8<-- "recipes/vectorizer/queue_status/sql/main.sql:queue"
```

## Waiting for the Embeddings

The script waits in a `DO` block that checks the queue once a second. The
block stops when no item for the chunk table is pending or in progress,
and raises an error if an item fails or the wait passes five minutes; a
model that is not yet in memory can take some time to answer its first
request. The following code waits for the worker:

```sql
--8<-- "recipes/vectorizer/queue_status/sql/main.sql:wait"
```

## Reading the Queue Views

An item moves from `pending` to `processing` while the worker embeds its
chunk, and to `completed` once the embedding is stored. When the worker
cannot embed a chunk, it sets the item back to `pending` with a delay that
doubles with each attempt, and marks the item `failed` once the item has
used up its attempts; the `pgedge_vectorizer.max_retries` setting sets the
number of attempts for new items. The `failed_items` view shows the error
from the last attempt. The `queue_status` view also reports the oldest and
newest item, and the average processing time, for each table and status.
The following code reads the three views after the wait:

```sql
--8<-- "recipes/vectorizer/queue_status/sql/main.sql:status"
```

## Cleaning Up

The `disable_vectorization()` function drops the triggers and, with
`drop_chunk_table`, the chunk table, and it removes the table's pending
items from the queue. The completed items stay in the queue until they are
older than the `pgedge_vectorizer.auto_cleanup_hours` setting (24 hours by
default) allows, and the `clear_completed()` function likewise deletes
completed items only once they are older than 24 hours by default. Calling
`clear_completed(0)`
removes them at once, but for every vectorized table in the database, so
the script deletes only the items for its own chunk table instead. The
script then checks psql's `LAST_ERROR_SQLSTATE` variable, and raises an
error if an earlier step failed, so that psql exits with a non-zero status.
The following code removes everything that the script created:

```sql
--8<-- "recipes/vectorizer/queue_status/sql/main.sql:cleanup"
```

## Running the Example

The script is available in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/vectorizer/queue_status).
Set the `PG*` environment variables for your server, and then run the
following command from the recipe's `sql` directory:

```bash
psql -X -q -v ON_ERROR_STOP=1 -f main.sql
```

## Viewing the Complete Program

The following code shows the complete script:

```sql
--8<-- "recipes/vectorizer/queue_status/sql/main.sql"
```

## Next Steps

The following resources provide more information about the topics in this
recipe:

- The [Vectorizing a Table](enable_vectorization.md) recipe describes what
  `enable_vectorization()` creates.
- The [Keeping Embeddings Up to Date](update_source.md) recipe shows the
  queue at work when a row's text changes.
- The [monitoring guide](https://github.com/pgEdge/pgedge-vectorizer/blob/v1.1/docs/monitoring.md)
  for pgEdge Vectorizer 1.1 describes the views and the functions that
  manage the queue.
