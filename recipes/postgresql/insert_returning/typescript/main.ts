/*
 * Ellie's Postgres Cookbook
 * Inserting rows and reading generated keys, using node-postgres.
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

// --8<-- [start:setup]
// Creates a temporary table whose id column the server fills in.
// GENERATED ALWAYS AS IDENTITY makes the server assign each id from a
// sequence, and refuses any attempt to supply one.
async function createPeople(client: pg.Client): Promise<void> {
  await client.query(
    "CREATE TEMPORARY TABLE people (" +
      "id int GENERATED ALWAYS AS IDENTITY PRIMARY KEY, " +
      "name text NOT NULL)",
  );
}
// --8<-- [end:setup]

// --8<-- [start:add_person]
// Inserts a row and returns the id that the server generated.
async function addPerson(client: pg.Client, name: string): Promise<number> {
  // RETURNING makes the INSERT produce a result row, like a SELECT, so the
  // program learns the new id without a second query. The name is a
  // parameter, which node-postgres sends separately from the SQL text.
  const result = await client.query<{ id: number }>(
    "INSERT INTO people (name) VALUES ($1) RETURNING id",
    [name],
  );

  // An int column arrives as a JavaScript number.
  return result.rows[0].id;
}
// --8<-- [end:add_person]

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
  let client: pg.Client | undefined;
  try {
    client = await connect();
    await createPeople(client);
    for (const name of ["Jane Doe", "John Smith", "Alex Example"]) {
      const id = await addPerson(client, name);
      console.log(`Inserted '${name}' with id ${id}`);
    }
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
