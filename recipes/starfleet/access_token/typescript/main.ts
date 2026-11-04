/*
 * Ellie's Postgres Cookbook
 * Exchanging a client ID and secret for a pgEdge Starfleet access token,
 * using the built-in fetch function.
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
interface AccessToken {
  access_token: string;
  token_type: string;
  expires_in: number;
}

// Exchanges the client ID and secret for an access token. The token
// endpoint belongs to the account API, and accepts the OAuth 2.0 client
// credentials grant as a JSON body.
async function getToken(): Promise<AccessToken> {
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
  const token = (await response.json()) as AccessToken;
  if (!token.access_token) {
    throw new Error("the token response has no access token");
  }
  return token;
}
// --8<-- [end:token]

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
    // Never print the token itself; it grants access to the account.
    console.log(`Token type: ${token.token_type}`);
    console.log(`Token length: ${token.access_token.length} characters`);
    console.log(`Expires in: ${token.expires_in} seconds`);
    return 0;
  } catch (err) {
    console.error(`Error: ${describe(err)}`);
    return 1;
  }
}

process.exitCode = await main();
// --8<-- [end:main]
