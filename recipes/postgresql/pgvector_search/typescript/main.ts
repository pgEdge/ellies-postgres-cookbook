/*
 * Ellie's Postgres Cookbook
 * Storing and searching vectors with pgvector, using node-postgres.
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

// --8<-- [start:schema]
// Enables pgvector and creates a temporary table of colours.
async function createSchema(client: pg.Client): Promise<void> {
  await client.query("CREATE EXTENSION IF NOT EXISTS vector");

  // vector(3) fixes the number of dimensions, one for each of the red,
  // green, and blue components. The temporary table disappears when the
  // session ends, so the program can run repeatedly.
  await client.query(
    "CREATE TEMPORARY TABLE colours (" +
      "name text PRIMARY KEY, rgb vector(3) NOT NULL)",
  );

  // An HNSW index speeds up nearest-neighbour searches; vector_l2_ops
  // matches the <-> (Euclidean distance) operator used by the search.
  await client.query("CREATE INDEX ON colours USING hnsw (rgb vector_l2_ops)");
}
// --8<-- [end:schema]

// --8<-- [start:insert]
// Stores five colours, each as a vector of its RGB components.
async function insertColours(client: pg.Client): Promise<void> {
  const colours: [string, string][] = [
    ["red", "[1,0,0]"],
    ["green", "[0,1,0]"],
    ["blue", "[0,0,1]"],
    ["yellow", "[1,1,0]"],
    ["white", "[1,1,1]"],
  ];
  for (const [name, rgb] of colours) {
    // A vector travels as text in pgvector's [x,y,z] format, and the
    // ::vector cast converts it on the server, so the driver needs no
    // vector-specific support.
    await client.query(
      "INSERT INTO colours (name, rgb) VALUES ($1, $2::vector)",
      [name, rgb],
    );
  }
}
// --8<-- [end:insert]

// --8<-- [start:search]
// Returns the names of the colours nearest to the target vector.
async function nearestColours(
  client: pg.Client,
  target: string,
  count: number,
): Promise<string[]> {
  // <-> is the Euclidean (L2) distance operator, so ordering by it puts
  // the nearest colour first.
  const result = await client.query<{ name: string }>(
    "SELECT name FROM colours ORDER BY rgb <-> $1::vector LIMIT $2",
    [target, count],
  );
  return result.rows.map((row) => row.name);
}
// --8<-- [end:search]

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
  const target = "[0.9,0.7,0.2]";
  let client: pg.Client | undefined;
  try {
    client = await connect();
    await createSchema(client);
    await insertColours(client);

    console.log(`Colours nearest to ${target}:`);
    const names = await nearestColours(client, target, 3);
    names.forEach((name, i) => console.log(`${i + 1}. ${name}`));
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
