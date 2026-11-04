/*
 * Ellie's Postgres Cookbook
 * Connecting to PostgreSQL and running a scalar query, using node-postgres.
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

async function main(): Promise<number> {
  // --8<-- [start:connect]
  const client = new pg.Client(config);

  try {
    await client.connect();
    // --8<-- [end:connect]

    // --8<-- [start:query]
    // Always pass values as parameters rather than building them into
    // the SQL string; node-postgres sends them separately, which
    // prevents SQL injection.
    const result = await client.query<{ count: string }>(
      "SELECT count(*) FROM pg_catalog.pg_type WHERE typname = $1",
      ["int4"],
    );

    // count(*) returns a bigint, which node-postgres returns as a string
    // because it may not fit in a JavaScript number.
    const count = BigInt(result.rows[0].count);

    console.log(`Number of types named 'int4': ${count}`);
    // --8<-- [end:query]
    return 0;
    // --8<-- [start:errors]
  } catch (err) {
    // Connection failures and errors reported by the server both arrive
    // here as rejected promises.
    const message = err instanceof Error ? err.message : String(err);
    console.error(`Database error: ${message}`);
    return 1;
    // --8<-- [end:errors]
    // --8<-- [start:cleanup]
  } finally {
    // The finally block runs whether or not an error occurred.
    await client.end();
  }
  // --8<-- [end:cleanup]
}

process.exitCode = await main();
