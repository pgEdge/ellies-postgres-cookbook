/*
 * Ellie's Postgres Cookbook
 * Reading a large result in batches, using node-postgres and pg-cursor.
 *
 * Copyright (c) 2026, pgEdge, Inc.
 * This code is released under the PostgreSQL License.
 */

// --8<-- [start:imports]
import pg from "pg";
import Cursor from "pg-cursor";
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

// --8<-- [start:read_batches]
const BATCH_SIZE = 1000;

// Reads every row of a large result, one batch at a time, and returns the
// number of rows and the sum of their values.
async function readInBatches(
  client: pg.Client,
): Promise<{ rowsRead: number; total: number }> {
  let rowsRead = 0;
  let total = 0;

  // A Cursor is a query that the client runs like any other, but that
  // fetches rows only when the program calls read(). The driver declares
  // a portal on the server, so the client never holds the whole result.
  const cursor = client.query(
    new Cursor<{ g: number }>(
      "SELECT g FROM generate_series(1, 100000) AS g",
    ),
  );

  try {
    while (true) {
      // read() resolves with up to BATCH_SIZE rows, and with an empty
      // array once the result is exhausted.
      const batch = await cursor.read(BATCH_SIZE);
      if (batch.length === 0) {
        break;
      }

      for (const row of batch) {
        rowsRead += 1;
        total += row.g;
      }
    }
  } finally {
    // Closing the cursor releases the portal, even after an error.
    await cursor.close();
  }

  return { rowsRead, total };
}
// --8<-- [end:read_batches]

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
    const { rowsRead, total } = await readInBatches(client);
    console.log(`Rows read: ${rowsRead}`);
    console.log(`Sum of values: ${total}`);
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
