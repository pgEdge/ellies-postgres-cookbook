/*
 * Ellie's Postgres Cookbook
 * Connecting to PostgreSQL over TLS with full verification, using
 * node-postgres.
 *
 * Copyright (c) 2026, pgEdge, Inc.
 * This code is released under the PostgreSQL License.
 */

// --8<-- [start:imports]
import { readFileSync } from "node:fs";

import pg from "pg";
// --8<-- [end:imports]

// --8<-- [start:config]
// Read the connection settings from the standard libpq environment
// variables, with defaults suitable for a local development server.
// The || operator, unlike ??, also treats an empty variable as unset, as
// libpq does.
function connectionConfig(): pg.ClientConfig {
  // PGSSLROOTCERT has no default, because verification is meaningless
  // without the certificate of the authority that signed the server
  // certificate.
  const rootCert = process.env.PGSSLROOTCERT;
  if (!rootCert) {
    throw new Error("PGSSLROOTCERT must name the root certificate");
  }

  return {
    host: process.env.PGHOST || "localhost",
    port: Number(process.env.PGPORT || "5432"),
    database: process.env.PGDATABASE || "postgres",
    user: process.env.PGUSER || "postgres",
    password: process.env.PGPASSWORD || undefined,
    // Supplying the root certificate as ca makes Node trust only that
    // authority, and rejectUnauthorized makes Node reject a certificate
    // that does not chain to it or does not match the host name. Together
    // they are the equivalent of sslmode=verify-full.
    ssl: { ca: readFileSync(rootCert), rejectUnauthorized: true },
  };
}
// --8<-- [end:config]

// --8<-- [start:connect]
// Opens a verified TLS connection with the settings from the
// environment. The connection fails if verification fails.
async function connect(): Promise<pg.Client> {
  const client = new pg.Client(connectionConfig());
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
// Asks the server whether this connection uses TLS.
async function connectionIsEncrypted(client: pg.Client): Promise<boolean> {
  // pg_stat_ssl has one row for each connection; pg_backend_pid()
  // identifies the one that belongs to this session. The version column
  // holds the protocol version, such as TLSv1.3.
  const result = await client.query<{ ssl: boolean; version: string }>(
    "SELECT ssl, version FROM pg_catalog.pg_stat_ssl " +
      "WHERE pid = pg_backend_pid()",
  );
  return result.rows[0].ssl;
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
  let client: pg.Client | undefined;
  try {
    client = await connect();
    const encrypted = await connectionIsEncrypted(client);
    console.log(`Connection is encrypted: ${encrypted}`);
    // Reaching this line means that verification succeeded; a
    // certificate or host name mismatch rejects the promise instead.
    console.log("Server certificate verified: true");
    return 0;
  } catch (err) {
    // Connection, certificate, and server errors all arrive here as
    // rejected promises.
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
