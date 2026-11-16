# Decoding a Snowflake ID

This recipe shows how to find out which node and which moment produced a
Snowflake ID. The `snowflake.format()` function takes an ID and returns a
`jsonb` document that holds the three parts of the ID, which helps when you
are tracing a row back to the server that created it.

These examples are for Snowflake 2.6.0.

The example generates one ID, and prints facts about it that do not change
from run to run. The output looks like this:

```text
Node: 1
Made within the last minute: true
Same node from get_node(): true
```

## Preparing the Ingredients

The example needs the same setup as the
[Generating Snowflake IDs](generate_ids.md) recipe: a server that preloads
the `snowflake` library, a `snowflake.node` setting that is not 0, and the
extension created in the database.

## Generating an ID

The first statement calls `snowflake.nextval()` and uses the `\gset`
command to store the result in a `psql` variable named `id`, which later
statements read as `:id`. The following statement generates the ID:

```sql
-- Generate one ID and keep it in a psql variable named id.
SELECT snowflake.nextval() AS id \gset
```

## Decoding the ID

The `snowflake.format()` function returns a document with the keys `ts`
(the time), `count` (the counter within that millisecond) and `id`. The
`id` key holds the node number and not the ID itself, which is easy to
misread. The following statements decode the ID and print the node:

```sql
-- snowflake.format() returns a jsonb document with the keys ts, count and
-- id; the id key holds the node number, not the ID itself.
SELECT snowflake.format(:id) AS decoded \gset
SELECT 'Node: ' || (:'decoded'::jsonb ->> 'id');
```

## Checking the Time

The `ts` key is text that casts to a `timestamptz`. The following statement
casts it, compares it with `now()`, and prints whether the ID was made in
the last minute:

```sql
-- The ts key is the moment the ID was made, so it should be close to now().
SELECT 'Made within the last minute: ' ||
       (abs(extract(epoch FROM
                    now() - (:'decoded'::jsonb ->> 'ts')::timestamptz))
        < 60);
```

## Comparing with get_node

The `snowflake.get_node()` function returns only the node number. The
following statement checks that it agrees with the decoded document:

```sql
-- snowflake.get_node() agrees with the node in the decoded document.
SELECT 'Same node from get_node(): ' ||
       (snowflake.get_node(:id) = (:'decoded'::jsonb ->> 'id')::bigint);
```

## Running the Example

The complete program is available in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/snowflake/decode_id).
Set the `PG*` environment variables for your server, and then run the
following command from the `sql` directory:

```bash
psql -X -q -v ON_ERROR_STOP=1 -f main.sql
```

## Viewing the Complete Program

The following block shows the complete program:

```sql
-- Ellie's Postgres Cookbook
-- Decoding a Snowflake ID into its node, timestamp and counter.
--
-- Copyright (c) 2026, pgEdge, Inc.
-- This code is released under the PostgreSQL License.

\pset format unaligned
\pset tuples_only on

-- Generate one ID and keep it in a psql variable named id.
SELECT snowflake.nextval() AS id \gset

-- snowflake.format() returns a jsonb document with the keys ts, count and
-- id; the id key holds the node number, not the ID itself.
SELECT snowflake.format(:id) AS decoded \gset
SELECT 'Node: ' || (:'decoded'::jsonb ->> 'id');

-- The ts key is the moment the ID was made, so it should be close to now().
SELECT 'Made within the last minute: ' ||
       (abs(extract(epoch FROM
                    now() - (:'decoded'::jsonb ->> 'ts')::timestamptz))
        < 60);

-- snowflake.get_node() agrees with the node in the decoded document.
SELECT 'Same node from get_node(): ' ||
       (snowflake.get_node(:id) = (:'decoded'::jsonb ->> 'id')::bigint);

```

## Next Steps

The following resources provide more information about the topics in this
recipe:

- The [Generating Snowflake IDs](generate_ids.md) recipe shows how to make
  the IDs.
- The [Checking the Node Number](node_setting.md) recipe explains where
  the node number comes from.
