# Converting a Sequence to Snowflake

This recipe shows how to move an existing identity column to Snowflake IDs.
The `snowflake.convert_sequence_to_snowflake()` function changes the column
in place, so rows that already exist keep their IDs and every new row gets a
Snowflake ID.

These examples are for Snowflake 2.6.0.

The example prints the old ID, and compares it with a new one. The output
looks like this:

```text
Old ID: 1
New ID is on node 1 and larger than the old one: true
```

## Preparing the Ingredients

The example needs the same setup as the
[Generating Snowflake IDs](generate_ids.md) recipe. The conversion edits the
`pg_attribute` system catalog, so the user that runs it must be a
superuser.

## Creating a Table with an Identity Column

The example starts with an ordinary identity column, and one row that gets
the ID 1. The table is temporary, so it disappears when the session ends.
The following statements create the table and insert the row:

```sql
--8<-- "recipes/snowflake/convert_sequence/sql/main.sql:table"
```

## Converting the Column

The function takes the `regclass` of the sequence behind the column, which
`pg_get_serial_sequence()` finds. It drops the identity property and sets
the default of the column to `snowflake.nextval()`. The function raises
`NOTICE` messages that describe each change, so the program sets
`client_min_messages` to `warning` at the start to keep the output stable.
The following statement converts the column:

```sql
--8<-- "recipes/snowflake/convert_sequence/sql/main.sql:convert"
```

## Verifying the Result

A second insert gets a Snowflake ID, whilst the first row keeps the ID 1.
The following statements insert the row and compare the two IDs:

```sql
--8<-- "recipes/snowflake/convert_sequence/sql/main.sql:verify"
```

## Running the Example

The complete program is available in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/snowflake/convert_sequence).
Set the `PG*` environment variables for your server, and then run the
following command from the `sql` directory:

```bash
psql -X -q -v ON_ERROR_STOP=1 -f main.sql
```

## Viewing the Complete Program

The following block shows the complete program:

```sql
--8<-- "recipes/snowflake/convert_sequence/sql/main.sql"
```

## Next Steps

The following resources provide more information about the topics in this
recipe:

- The [Generating Snowflake IDs](generate_ids.md) recipe shows a new table
  that uses Snowflake IDs from the start.
- The [Decoding a Snowflake ID](decode_id.md) recipe shows how to read an
  ID.
- The PostgreSQL documentation for
  [CREATE TABLE](https://www.postgresql.org/docs/current/sql-createtable.html)
  describes identity columns.
