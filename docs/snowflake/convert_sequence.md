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
-- An ordinary identity column, with one row that has the ID 1. The table is
-- temporary, so nothing is left behind.
CREATE TEMPORARY TABLE cookbook_orders (
    id   bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    item text NOT NULL
);

INSERT INTO cookbook_orders (item) VALUES ('before');
```

## Converting the Column

The function takes the `regclass` of the sequence behind the column, which
`pg_get_serial_sequence()` finds. It clears the identity property and sets
the default of the column to `snowflake.nextval()`; the sequence stays, and
the function changes it to `bigint` with `NO CYCLE` and a `MAXVALUE` of
9223372036854775807, so that Snowflake IDs stay within its bounds. The
function raises `NOTICE` messages that describe each change, so the program
sets `client_min_messages` to `warning` at the start to keep the output
stable.
The following statement converts the column:

```sql
-- The function drops the identity property and sets the default to
-- snowflake.nextval() on the same sequence. It edits pg_attribute, so it
-- needs a superuser. The \gset command keeps the function's return value
-- out of the output.
SELECT snowflake.convert_sequence_to_snowflake(
           pg_get_serial_sequence('cookbook_orders', 'id')::regclass)
       AS converted \gset
```

## Verifying the Result

A second insert gets a Snowflake ID, whilst the first row keeps the ID 1.
The following statements insert the row and compare the two IDs:

```sql
-- Existing rows keep their IDs; new rows get Snowflake IDs.
INSERT INTO cookbook_orders (item) VALUES ('after');

SELECT 'Old ID: ' || id
FROM cookbook_orders WHERE item = 'before';

SELECT format('New ID is on node %s and larger than the old one: %s',
              snowflake.get_node(n.id), (n.id > o.id)::text)
FROM cookbook_orders AS n, cookbook_orders AS o
WHERE n.item = 'after' AND o.item = 'before';
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
-- Ellie's Postgres Cookbook
-- Moving an identity column from a sequence to Snowflake IDs.
--
-- Copyright (c) 2026, pgEdge, Inc.
-- This code is released under the PostgreSQL License.

\pset format unaligned
\pset tuples_only on

-- The conversion raises NOTICE messages that describe each change; hiding
-- them keeps the output stable.
SET client_min_messages = warning;

-- An ordinary identity column, with one row that has the ID 1. The table is
-- temporary, so nothing is left behind.
CREATE TEMPORARY TABLE cookbook_orders (
    id   bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    item text NOT NULL
);

INSERT INTO cookbook_orders (item) VALUES ('before');

-- The function drops the identity property and sets the default to
-- snowflake.nextval() on the same sequence. It edits pg_attribute, so it
-- needs a superuser. The \gset command keeps the function's return value
-- out of the output.
SELECT snowflake.convert_sequence_to_snowflake(
           pg_get_serial_sequence('cookbook_orders', 'id')::regclass)
       AS converted \gset

-- Existing rows keep their IDs; new rows get Snowflake IDs.
INSERT INTO cookbook_orders (item) VALUES ('after');

SELECT 'Old ID: ' || id
FROM cookbook_orders WHERE item = 'before';

SELECT format('New ID is on node %s and larger than the old one: %s',
              snowflake.get_node(n.id), (n.id > o.id)::text)
FROM cookbook_orders AS n, cookbook_orders AS o
WHERE n.item = 'after' AND o.item = 'before';

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
