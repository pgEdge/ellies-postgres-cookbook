/*
 * Ellie's Postgres Cookbook
 * Retrying a transaction after a serialisation failure, using
 * node-postgres.
 *
 * Copyright (c) 2026, pgEdge, Inc.
 * This code is released under the PostgreSQL License.
 */

// --8<-- [start:imports]
import { setTimeout as sleep } from "node:timers/promises";

import pg from "pg";
// --8<-- [end:imports]

// --8<-- [start:config]
// The SQLSTATE codes that mean "run the transaction again": 40001 is a
// serialisation failure and 40P01 is a deadlock.
const RETRYABLE = new Set(["40001", "40P01"]);
const MAX_ATTEMPTS = 5;

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
// Opens a connection with the settings from the environment. The driver
// runs each statement in its own transaction unless the program sends
// BEGIN, so the program decides where each transaction starts and ends.
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
// Drops the shared counter table if it exists.
async function dropTable(client: pg.Client): Promise<void> {
  await client.query("DROP TABLE IF EXISTS cookbook_retry_transactions");
}

// Creates the shared counter table, with a single row set to zero. The
// table must be visible to a second connection, so it cannot be
// temporary; the name is specific to this recipe, and any earlier copy is
// dropped first.
async function createTable(client: pg.Client): Promise<void> {
  await dropTable(client);
  await client.query(
    "CREATE TABLE cookbook_retry_transactions " +
      "(id int PRIMARY KEY, value int NOT NULL)",
  );
  await client.query(
    "INSERT INTO cookbook_retry_transactions (id, value) VALUES ($1, $2)",
    [1, 0],
  );
}
// --8<-- [end:setup]

// --8<-- [start:work]
// Reads the counter and writes back the value plus one.
async function incrementCounter(
  client: pg.Client,
  attempt: number,
): Promise<void> {
  const result = await client.query<{ value: number }>(
    "SELECT value FROM cookbook_retry_transactions WHERE id = $1",
    [1],
  );
  const value = result.rows[0].value;

  // Simulate another client by updating the row from a second
  // connection, after this transaction has read the row but before it
  // writes. This happens on the first attempt only.
  if (attempt === 1) {
    const other = await connect();
    try {
      await other.query(
        "UPDATE cookbook_retry_transactions SET value = value + 1 " +
          "WHERE id = $1",
        [1],
      );
    } finally {
      await other.end();
    }
  }

  // Under REPEATABLE READ, updating a row that another transaction
  // changed and committed since this transaction's snapshot was taken
  // fails with SQLSTATE 40001.
  await client.query(
    "UPDATE cookbook_retry_transactions SET value = $1 WHERE id = $2",
    [value + 1, 1],
  );
}

// Returns the current value of the counter.
async function readCounter(client: pg.Client): Promise<number> {
  const result = await client.query<{ value: number }>(
    "SELECT value FROM cookbook_retry_transactions WHERE id = $1",
    [1],
  );
  return result.rows[0].value;
}
// --8<-- [end:work]

// --8<-- [start:retry]
// Runs work(client, attempt) in a REPEATABLE READ transaction, and runs
// it again if the server reports a serialisation failure or a deadlock.
async function runWithRetry(
  client: pg.Client,
  work: (client: pg.Client, attempt: number) => Promise<void>,
): Promise<void> {
  for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt++) {
    try {
      await client.query("BEGIN ISOLATION LEVEL REPEATABLE READ");
      await work(client, attempt);
      await client.query("COMMIT");
      console.log(`Attempt ${attempt}: committed`);
      return;
    } catch (err) {
      // End the failed transaction so that the session can start another.
      await client.query("ROLLBACK");

      // Any other error, or running out of attempts, is a real failure
      // that the caller must handle.
      const code = (err as pg.DatabaseError).code;
      if (code === undefined || !RETRYABLE.has(code) ||
          attempt === MAX_ATTEMPTS) {
        throw err;
      }
      console.log(`Attempt ${attempt}: serialisation failure, retrying`);
      // A short, growing pause gives the competing transaction time to
      // finish.
      await sleep(50 * attempt);
    }
  }
}
// --8<-- [end:retry]

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
    try {
      await createTable(client);
      await runWithRetry(client, incrementCounter);
      console.log(`Counter value: ${await readCounter(client)}`);
    } finally {
      // Drop the shared table even if the work failed.
      await dropTable(client);
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
