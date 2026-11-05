/*
 * Ellie's Postgres Cookbook
 * Finding the address of a pgEdge Control Plane database and connecting
 * to it, using the built-in fetch and node-postgres.
 *
 * These examples are for the Control Plane v0.11.0.
 *
 * Copyright (c) 2026, pgEdge, Inc.
 * This code is released under the PostgreSQL License.
 */

// --8<-- [start:imports]
// Node.js provides fetch and AbortSignal as globals; pg is node-postgres.
import pg from "pg";
// --8<-- [end:imports]

// --8<-- [start:config]
// The || operator, unlike ??, also treats an empty variable as unset. The
// password has no default; the Control Plane never returns it, so it
// comes from whoever created the database user.
const baseUrl = (process.env.CONTROL_PLANE_URL || "http://localhost:3000").replace(/\/+$/, "");
const databaseId = process.env.CONTROL_PLANE_DATABASE_ID || "cookbook";
const databaseUser = process.env.CONTROL_PLANE_DATABASE_USER || "cookbook";
const databasePassword = process.env.CONTROL_PLANE_DATABASE_PASSWORD || undefined;

const timeoutMs = 30_000;

// Fetches a path from the server, and returns the decoded reply.
async function get<T>(path: string): Promise<T> {
  const response = await fetch(`${baseUrl}${path}`, {
    signal: AbortSignal.timeout(timeoutMs),
  });

  // fetch only rejects when it cannot reach the server; an error status
  // is a normal response, so check it explicitly.
  if (!response.ok) {
    const text = await response.text();
    throw new Error(`HTTP ${response.status}, ${text.slice(0, 200) || response.statusText}`);
  }
  return (await response.json()) as T;
}
// --8<-- [end:config]

// --8<-- [start:find]
interface Database {
  spec?: { database_name?: string };
  instances?: {
    node_name?: string;
    state?: string;
    connection_info?: { addresses?: string[]; port?: number };
  }[];
}

interface Instance {
  node?: string;
  host: string;
  port?: number;
  database?: string;
}

// Returns the connection settings for the first instance of the database
// that is available. Each instance runs one node of the database, and its
// connection_info holds the addresses and port that clients use.
async function findInstance(): Promise<Instance> {
  const database = await get<Database>(`/v1/databases/${databaseId}`);
  for (const instance of database.instances ?? []) {
    const info = instance.connection_info;
    if (instance.state === "available" && info?.addresses?.length) {
      return {
        node: instance.node_name,
        host: info.addresses[0],
        port: info.port,
        database: database.spec?.database_name,
      };
    }
  }
  throw new Error(`no available instance of ${databaseId}`);
}
// --8<-- [end:find]

// --8<-- [start:connect]
// Connects to the instance, and returns the name of the database and the
// version of the Spock extension.
async function query(instance: Instance): Promise<[string, string]> {
  const client = new pg.Client({
    host: instance.host,
    port: instance.port,
    database: instance.database,
    user: databaseUser,
    password: databasePassword,
    connectionTimeoutMillis: timeoutMs,
  });
  await client.connect();
  try {
    const database = await client.query<{ current_database: string }>(
      "SELECT current_database()",
    );
    const spock = await client.query<{ extversion: string }>(
      "SELECT extversion FROM pg_extension WHERE extname = 'spock'",
    );
    return [database.rows[0].current_database, spock.rows[0]?.extversion ?? "not installed"];
  } finally {
    // Close the connection whether or not a query failed.
    await client.end();
  }
}
// --8<-- [end:connect]

// --8<-- [start:main]
// Returns a readable description of an error. fetch reports a connection
// failure as a TypeError with the cause (often an AggregateError, whose
// own message is empty) attached.
function describe(err: unknown): string {
  if (err instanceof AggregateError) {
    return err.errors.map(describe).join("; ");
  }
  if (err instanceof Error) {
    return err.cause ? `${err.message}: ${describe(err.cause)}` : err.message;
  }
  return String(err);
}

async function main(): Promise<number> {
  if (databasePassword === undefined) {
    console.error("CONTROL_PLANE_DATABASE_PASSWORD must be set");
    return 1;
  }

  let instance: Instance;
  try {
    instance = await findInstance();
  } catch (err) {
    console.error(`Control Plane error: ${describe(err)}`);
    return 1;
  }
  console.log(`Connecting to node ${instance.node}`);

  try {
    const [database, spock] = await query(instance);
    console.log(`Connected to database ${database}`);
    console.log(`Spock: ${spock}`);
    return 0;
  } catch (err) {
    console.error(`Database error: ${describe(err)}`);
    return 1;
  }
}

process.exitCode = await main();
// --8<-- [end:main]
