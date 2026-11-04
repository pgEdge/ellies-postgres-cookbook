/*
 * Ellie's Postgres Cookbook
 * Passing a list of values as a single array parameter, using
 * node-postgres.
 *
 * Copyright (c) 2026, pgEdge, Inc.
 * This code is released under the PostgreSQL License.
 */

// --8<-- [start:imports]
import pg from "pg";
// --8<-- [end:imports]

// --8<-- [start:config]
// Read the connection settings from the standard libpq environment
// variables, with defaults suitable for a local development server.
// The || operator, unlike ??, also treats an empty variable as unset, as
// libpq does.
const config: pg.ClientConfig = {
  host: process.env.PGHOST || "localhost",
  port: Number(process.env.PGPORT || "5432"),
  database: process.env.PGDATABASE || "postgres",
  user: process.env.PGUSER || "postgres",
  password: process.env.PGPASSWORD || undefined,
};
// --8<-- [end:config]

// --8<-- [start:connect]
// Opens a connection with the settings from the environment.
async function connect(): Promise<pg.Client> {
  const client = new pg.Client(config);
  try {
    await client.connect();
  } catch (err) {
    // Release the client before passing the failure to the caller.
    await client.end();
    throw err;
  }
  return client;
}
// --8<-- [end:connect]

// --8<-- [start:query]
// Returns the names from the list that exist as data types.
async function findTypes(client: pg.Client, names: string[]): Promise<string[]> {
  // The whole list travels as one array parameter, so the SQL text is the
  // same however many values the list holds. node-postgres converts a
  // JavaScript array into a PostgreSQL array.
  const result = await client.query<{ typname: string }>(
    "SELECT typname FROM pg_catalog.pg_type " +
      "WHERE typname = ANY($1) ORDER BY typname",
    [names],
  );
  return result.rows.map((row) => row.typname);
}
// --8<-- [end:query]

// --8<-- [start:main]
// Returns a readable description of an error. When a host name resolves
// to several addresses, Node reports a failure to reach all of them as an
// AggregateError, whose own message is empty.
function describe(err: unknown): string {
  if (err instanceof AggregateError) {
    return err.errors.map(describe).join("; ");
  }
  return err instanceof Error ? err.message : String(err);
}

async function main(): Promise<number> {
  const wanted = ["int4", "text", "bool", "no_such_type"];
  let client: pg.Client | undefined;
  try {
    client = await connect();
    const found = await findTypes(client, wanted);
    console.log(
      `Found ${found.length} of ${wanted.length} types: ${found.join(", ")}`,
    );
    return 0;
  } catch (err) {
    // Connection failures and errors reported by the server both arrive
    // here as rejected promises.
    console.error(`Database error: ${describe(err)}`);
    return 1;
  } finally {
    // The finally block runs whether or not an error occurred; client is
    // undefined if the connection attempt failed.
    await client?.end();
  }
}

process.exitCode = await main();
// --8<-- [end:main]
