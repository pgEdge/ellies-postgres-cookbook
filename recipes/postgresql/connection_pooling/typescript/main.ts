/*
 * Ellie's Postgres Cookbook
 * Using a connection pool, with node-postgres.
 *
 * Copyright (c) 2026, pgEdge, Inc.
 * This code is released under the PostgreSQL License.
 */

// --8<-- [start:imports]
import pg from "pg";
// --8<-- [end:imports]

// --8<-- [start:config]
// The most connections that the pool opens at any one time.
const POOL_SIZE = 2;

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

// --8<-- [start:pool]
// Creates a pool that holds at most POOL_SIZE connections.
function createPool(): pg.Pool {
  const pool = new pg.Pool({
    ...config,
    max: POOL_SIZE,
    // A request fails after this many milliseconds if the pool can
    // neither lend an idle connection nor open a new one.
    connectionTimeoutMillis: 5000,
  });

  // An idle connection can fail while it waits in the pool, for example
  // if the server restarts. The pool emits an error event for it, and
  // Node terminates the process if nothing handles the event.
  pool.on("error", (err) => {
    console.error(`Idle connection error: ${err.message}`);
  });
  return pool;
}
// --8<-- [end:pool]

// --8<-- [start:query]
// Borrows a connection from the pool, and returns the number back.
async function runQuery(pool: pg.Pool, n: number): Promise<number> {
  // pool.query borrows a connection, runs the statement, and returns the
  // connection to the pool, whether or not an error occurred. Pass values
  // as parameters rather than building them into the SQL string. The cast
  // gives the parameter a type, which the server cannot infer from
  // SELECT $1 alone.
  const result = await pool.query<{ n: number }>("SELECT $1::int AS n", [n]);
  return result.rows[0].n;
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
  const pool = createPool();
  try {
    // All five queries start at once, but the pool has only two
    // connections, so the others wait their turn.
    const results = await Promise.all(
      [1, 2, 3, 4, 5].map((n) => runQuery(pool, n)),
    );
    const sum = results.reduce((total, n) => total + n, 0);

    console.log(
      `Ran ${results.length} queries through a pool of at most ` +
        `${POOL_SIZE} connections`,
    );
    console.log(`Sum of results: ${sum}`);
    return 0;
  } catch (err) {
    // Connection failures and errors reported by the server both arrive
    // here as rejected promises.
    console.error(`Database error: ${describe(err)}`);
    return 1;
  } finally {
    // The finally block runs whether or not an error occurred; end()
    // closes every connection in the pool.
    await pool.end();
  }
}

process.exitCode = await main();
// --8<-- [end:main]
