/*
 * Ellie's Postgres Cookbook
 * Setting a server-side statement timeout, using node-postgres.
 *
 * Copyright (c) 2026, pgEdge, Inc.
 * This code is released under the PostgreSQL License.
 */

// --8<-- [start:imports]
import pg from "pg";
// --8<-- [end:imports]

// --8<-- [start:config]
// The SQLSTATE code that the server reports when it cancels a statement,
// whether because of a timeout or because a client asked for the cancel.
const QUERY_CANCELED = "57014";

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
// BEGIN, so a cancelled statement does not leave the session in a failed
// transaction.
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

// --8<-- [start:timeout]
// Sets the statement timeout for the rest of the session.
async function setStatementTimeout(
  client: pg.Client,
  timeout: string,
): Promise<void> {
  // SET cannot take a parameter, but set_config() is an ordinary
  // function, so the value can be sent safely. The final argument, false,
  // makes the setting last for the session rather than for the current
  // transaction.
  await client.query("SELECT set_config('statement_timeout', $1, false)", [
    timeout,
  ]);
}

// Runs a statement that outlasts the timeout, and returns true if the
// server cancelled it.
async function sleepExceedsTimeout(client: pg.Client): Promise<boolean> {
  try {
    await client.query("SELECT pg_sleep(5)");
  } catch (err) {
    // Only a cancelled statement is expected here; any other error is a
    // real failure, so it is thrown again.
    if ((err as pg.DatabaseError).code !== QUERY_CANCELED) {
      throw err;
    }
    return true;
  }
  return false;
}

// Returns true if the session can still run a statement.
async function isUsable(client: pg.Client): Promise<boolean> {
  const result = await client.query<{ one: number }>("SELECT 1 AS one");
  return result.rows[0].one === 1;
}
// --8<-- [end:timeout]

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
    await setStatementTimeout(client, "100ms");
    if (await sleepExceedsTimeout(client)) {
      console.log("Query cancelled after exceeding the statement timeout");
    }
    console.log(`Connection still usable: ${await isUsable(client)}`);
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
