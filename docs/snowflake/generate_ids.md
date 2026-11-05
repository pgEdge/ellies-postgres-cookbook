# Generating Snowflake IDs

This recipe shows how to give a table cluster-unique `bigint` keys with the
Snowflake extension. Each server in a cluster has its own node number, and
the extension builds every ID from a timestamp, a counter and that node
number, so two servers never make the same ID and no server needs to ask
another before it inserts a row.

These examples are for Snowflake 2.6.0.

The IDs differ on every run, because each one holds the time at which it
was made, so the example prints facts about the IDs instead of the IDs
themselves. The output looks like this:

```text
Inserted 3 rows on node 1
IDs increase: true
```

## Preparing the Ingredients

The example needs a PostgreSQL server with the `snowflake` extension in
`shared_preload_libraries`, a `snowflake.node` setting that is not 0, and
the extension created in the database with `CREATE EXTENSION snowflake`.
Connect as a superuser, using the `PG*` environment variables that `psql`
reads.

## Creating a Table with a Snowflake Default

The table uses `snowflake.nextval()` as the default of its `id` column. The
function returns a `bigint`, so the column needs no other type. The table is
temporary, so it disappears when the session ends. The following statement
creates the table:

```sql
--8<-- "recipes/snowflake/generate_ids/sql/main.sql:table"
```

## Inserting Rows

The insert statement leaves out the `id` column, so the default supplies
each value. The statement uses `RETURNING` to read the generated IDs, and
reports the number of rows and the node that made them with
`snowflake.get_node()`, which extracts the node number from an ID. The
following statement runs the insert:

```sql
--8<-- "recipes/snowflake/generate_ids/sql/main.sql:insert"
```

## Checking the Order

IDs begin with the timestamp, so an ID made later is always larger than one
made earlier on the same node. The following query compares each ID with the
one before it:

```sql
--8<-- "recipes/snowflake/generate_ids/sql/main.sql:order"
```

## Running the Example

The complete program is available in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/snowflake/generate_ids).
Set the `PG*` environment variables for your server, and then run the
following command from the `sql` directory:

```bash
psql -X -q -v ON_ERROR_STOP=1 -f main.sql
```

## Viewing the Complete Program

The following block shows the complete program:

```sql
--8<-- "recipes/snowflake/generate_ids/sql/main.sql"
```

## Next Steps

The following resources provide more information about the topics in this
recipe:

- The [Decoding a Snowflake ID](decode_id.md) recipe shows how to read the
  node and time back out of an ID.
- The [Converting a Sequence to Snowflake](convert_sequence.md) recipe
  moves an existing table to Snowflake IDs.
- The [Checking the Node Number](node_setting.md) recipe explains the
  `snowflake.node` setting.
