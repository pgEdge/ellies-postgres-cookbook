/*
 * Ellie's Postgres Cookbook
 * Loading rows in bulk with COPY, using node-postgres and pg-copy-streams.
 *
 * Copyright (c) 2026, pgEdge, Inc.
 * This code is released under the PostgreSQL License.
 */

// --8<-- [start:imports]
import { Readable } from "node:stream";
import { pipeline } from "node:stream/promises";

import pg from "pg";
import { from as copyFrom } from "pg-copy-streams";
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

// --8<-- [start:create_table]
// Creates a temporary table, which only this session can see and which
// PostgreSQL drops when the session ends.
async function createTable(client: pg.Client): Promise<void> {
  await client.query(
    "CREATE TEMPORARY TABLE items (id int PRIMARY KEY, name text NOT NULL)",
  );
}
// --8<-- [end:create_table]

// --8<-- [start:generate_rows]
// Escapes a value for the COPY text format, in which a backslash, a tab,
// a newline, and a carriage return all have a special meaning.
function escapeText(value: string): string {
  return value
    .replaceAll("\\", "\\\\")
    .replaceAll("\t", "\\t")
    .replaceAll("\n", "\\n")
    .replaceAll("\r", "\\r");
}

// Yields one line of COPY text for each row to load: the columns are
// separated by tabs, and each row ends with a newline. A generator
// produces the rows one at a time, so the program never holds them all.
function* generateRows(count: number): Generator<string> {
  for (let id = 1; id <= count; id++) {
    yield `${id}\t${escapeText(`item ${id}`)}\n`;
  }
}
// --8<-- [end:generate_rows]

// --8<-- [start:copy_rows]
// Loads the rows with COPY ... FROM STDIN and returns how many rows the
// server stored.
async function copyRows(
  client: pg.Client,
  rows: Iterable<string>,
): Promise<number> {
  // copyFrom() builds a query that the client runs like any other, and
  // that behaves as a writable stream: the data goes to the server as it
  // is written, which is much faster than one INSERT for each row.
  const stream = client.query(
    copyFrom("COPY items (id, name) FROM STDIN"),
  );

  // pipeline() copies the rows into the stream, applies back-pressure if
  // the server is slow, and rejects if either side fails.
  await pipeline(Readable.from(rows), stream);

  // The stream reports the row count once the server has finished.
  return stream.rowCount;
}
// --8<-- [end:copy_rows]

// --8<-- [start:summarise]
// Returns the number of rows in the table and the sum of their ids.
async function summarise(
  client: pg.Client,
): Promise<{ count: string; total: string }> {
  // count and sum of an int both return a bigint, which node-postgres
  // returns as strings because they may not fit in a JavaScript number.
  const result = await client.query<{ count: string; total: string }>(
    "SELECT count(*) AS count, sum(id) AS total FROM items",
  );
  return result.rows[0];
}
// --8<-- [end:summarise]

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
    await createTable(client);

    const copied = await copyRows(client, generateRows(1000));
    console.log(`Copied ${copied} rows`);

    const { count, total } = await summarise(client);
    console.log(`Rows in table: ${count}`);
    console.log(`Sum of ids: ${total}`);
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
