# Checking the Node Number

This recipe shows what happens when the `snowflake.node` setting is not
set. Every Snowflake ID carries the number of the node that made it, so the
extension refuses to make IDs on a server whose node is 0, and the error
tells you that the node is not set.

These examples are for Snowflake 2.6.0.

The example reads the setting, sets it to 0 for one transaction to cause the
error, and then shows that the setting is back to its original value. The
output looks like this on a server whose node is 1:

```text
Node: 1
Node inside the transaction: 0
nextval() says: value for snowflake.node is not set
Node after the rollback: 1
nextval() says: ok
```

## Preparing the Ingredients

The example needs the same setup as the
[Generating Snowflake IDs](generate_ids.md) recipe. Changing
`snowflake.node` needs a superuser, or a role that has been granted `SET`
on the parameter with `GRANT SET ON PARAMETER snowflake.node TO
role_name` (PostgreSQL 15 and later), because the setting has the context
`superuser`.

## Reading the Setting

The `current_setting()` function reads the node number. The following
statement prints it:

```sql
--8<-- "recipes/snowflake/node_setting/sql/main.sql:show"
```

## Catching the Error

The `snowflake.nextval()` function raises an error when the node is 0. The
following statement creates a helper function in the temporary schema that
catches the error and returns its message, so that the program can print the
message and carry on:

```sql
--8<-- "recipes/snowflake/node_setting/sql/main.sql:helper"
```

## Unsetting the Node for One Transaction

The `SET LOCAL` command changes the setting only until the end of the
transaction, so the server keeps its real node number. The following
statements set the node to 0, call the helper, and roll back:

```sql
--8<-- "recipes/snowflake/node_setting/sql/main.sql:unset"
```

## Checking That the Setting Is Back

After the rollback, the node has its original value and `nextval()` works
again. The following statements confirm both:

```sql
--8<-- "recipes/snowflake/node_setting/sql/main.sql:after"
```

## Setting the Node on a Server

Each server in a cluster needs a different node number, from 1 to 1023. A
managed pgEdge deployment assigns `snowflake.node` for you, and the value
comes from each node's place in the cluster:

- The Control Plane sets `snowflake.node` from the node ordinal.
- The pgEdge Helm charts derive `snowflake.node` from each node name.
- The pgEdge Ansible playbooks set `snowflake.node` from the node zone.

When you deploy with one of these methods, no further action is needed.
For a self-managed server, set the value in `postgresql.conf`, or run
`ALTER SYSTEM SET snowflake.node = 2` and then `SELECT pg_reload_conf()`.
A value given on the `postgres` command line takes precedence over both.

## Running the Example

The complete program is available in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/snowflake/node_setting).
Set the `PG*` environment variables for your server, and then run the
following command from the `sql` directory:

```bash
psql -X -q -v ON_ERROR_STOP=1 -f main.sql
```

## Viewing the Complete Program

The following block shows the complete program:

```sql
--8<-- "recipes/snowflake/node_setting/sql/main.sql"
```

## Next Steps

The following resources provide more information about the topics in this
recipe:

- The [Generating Snowflake IDs](generate_ids.md) recipe shows the IDs
  that a server makes once its node is set.
- The PostgreSQL documentation for
  [ALTER SYSTEM](https://www.postgresql.org/docs/current/sql-altersystem.html)
  describes how to persist a setting.
- The [Snowflake repository](https://github.com/pgEdge/snowflake) holds the
  source and documentation for the extension.
