/*
 * Ellie's Postgres Cookbook
 * Listing the regions, sizes, and PostgreSQL versions that the pgEdge
 * Starfleet Managed API offers, using the built-in fetch function.
 *
 * Copyright (c) 2026, pgEdge, Inc.
 * This code is released under the PostgreSQL License.
 */

// --8<-- [start:imports]
// Node.js provides fetch as a global function, so the only import is the
// process object, which holds the environment and the exit status.
import process from "node:process";
// --8<-- [end:imports]

// --8<-- [start:config]
// Read the API settings from the environment. The || operator, unlike ??,
// also treats an empty variable as unset.
const baseUrl = (
  process.env.STARFLEET_API_URL || "https://api.pgedge.com"
).replace(/\/+$/, "");
const clientId = process.env.STARFLEET_CLIENT_ID || "";
const clientSecret = process.env.STARFLEET_CLIENT_SECRET || "";
// --8<-- [end:config]

// --8<-- [start:token]
// Exchanges the client ID and secret for an access token, which the
// Managed API accepts as a bearer token for the next 24 hours.
async function getToken(): Promise<string> {
  if (!clientId || !clientSecret) {
    throw new Error(
      "STARFLEET_CLIENT_ID and STARFLEET_CLIENT_SECRET must be set",
    );
  }

  const response = await fetch(`${baseUrl}/account/v1/oauth/token`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      grant_type: "client_credentials",
      client_id: clientId,
      client_secret: clientSecret,
    }),
    signal: AbortSignal.timeout(30_000),
  });

  // fetch only rejects on network failures, so check the status here.
  if (!response.ok) {
    throw new Error(
      `token request failed: ${response.status} ${await response.text()}`,
    );
  }
  const body = (await response.json()) as { access_token: string };
  return body.access_token;
}
// --8<-- [end:token]

// --8<-- [start:api]
// Sends an authenticated GET request to the Managed API and returns the
// decoded JSON reply.
async function apiGet<T>(
  token: string,
  path: string,
  query = "",
): Promise<T> {
  const response = await fetch(`${baseUrl}/managed/v1${path}${query}`, {
    headers: { Authorization: `Bearer ${token}` },
    signal: AbortSignal.timeout(30_000),
  });
  if (!response.ok) {
    throw new Error(
      `GET ${path} failed: ${response.status} ${await response.text()}`,
    );
  }
  return (await response.json()) as T;
}
// --8<-- [end:api]

// --8<-- [start:regions]
// Returns the identifiers of the regions that can host a database.
async function listRegions(token: string): Promise<string[]> {
  const regions = await apiGet<{ region: string }[]>(token, "/regions");
  return regions.map((r) => r.region);
}
// --8<-- [end:regions]

// --8<-- [start:sizes]
interface Size {
  name: string;
  connections: number;
  storage_size: string;
  pricing?: {
    price_amount: number;
    currency: string;
    billing_interval: string;
  };
}

// Returns a description of each size, smallest first.
async function listSizes(token: string): Promise<string[]> {
  // The pricing option asks the API to include each size's price, which
  // takes a little longer because the API looks it up from billing.
  const sizes = await apiGet<Size[]>(token, "/sizes", "?include=pricing");

  return sizes.map((size) => {
    let line = `${size.name}: ${size.connections} connections, ${size.storage_size} storage`;
    // A size with no configured price omits the pricing field. The
    // amount is in the smallest unit of the currency, such as cents.
    if (size.pricing) {
      const amount = (size.pricing.price_amount / 100).toFixed(2);
      line += `, ${amount} ${size.pricing.currency} per ${size.pricing.billing_interval}`;
    }
    return line;
  });
}
// --8<-- [end:sizes]

// --8<-- [start:versions]
// Returns the PostgreSQL major versions, newest first, marking the one
// that a new database gets by default.
async function listVersions(token: string): Promise<string[]> {
  const versions = await apiGet<{ version: string; default: boolean }[]>(
    token,
    "/pg-versions",
  );
  return versions.map((v) => v.version + (v.default ? " (default)" : ""));
}
// --8<-- [end:versions]

// --8<-- [start:main]
// Returns a readable description of an error. A failure to connect
// arrives as a TypeError whose cause holds the details, and Node reports
// a failure to reach several addresses as an AggregateError.
function describe(err: unknown): string {
  if (err instanceof AggregateError) {
    return err.errors.map(describe).join("; ");
  }
  if (err instanceof Error && err.cause) {
    return `${err.message}: ${describe(err.cause)}`;
  }
  return err instanceof Error ? err.message : String(err);
}

async function main(): Promise<number> {
  try {
    const token = await getToken();

    console.log("Regions:");
    for (const region of await listRegions(token)) {
      console.log(`  ${region}`);
    }

    console.log("Sizes (smallest first):");
    for (const size of await listSizes(token)) {
      console.log(`  ${size}`);
    }

    console.log("PostgreSQL versions:");
    for (const version of await listVersions(token)) {
      console.log(`  ${version}`);
    }
    return 0;
  } catch (err) {
    console.error(`Error: ${describe(err)}`);
    return 1;
  }
}

process.exitCode = await main();
// --8<-- [end:main]
