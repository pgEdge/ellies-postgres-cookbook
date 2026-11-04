/*
 * Ellie's Postgres Cookbook
 * Creating a pgEdge Starfleet database, waiting until it is available,
 * and deleting it again, using the built-in fetch function.
 *
 * The Starfleet service bills for every database from the moment that it
 * becomes connectable, so this program deletes the database it creates on
 * every path: after a success, after a failure, and after Ctrl-C.
 *
 * Copyright (c) 2026, pgEdge, Inc.
 * This code is released under the PostgreSQL License.
 */

// --8<-- [start:imports]
import { randomBytes } from "node:crypto";
import process from "node:process";
import { setTimeout as sleep } from "node:timers/promises";
// --8<-- [end:imports]

// --8<-- [start:config]
// How long to wait for a database to become available, or to disappear
// after a delete, and how often to check.
const TIMEOUT_MS = 900_000;
const POLL_MS = 10_000;

// Read the API settings from the environment. The || operator, unlike ??,
// also treats an empty variable as unset.
const baseUrl = (
  process.env.STARFLEET_API_URL || "https://api.pgedge.com"
).replace(/\/+$/, "");
const clientId = process.env.STARFLEET_CLIENT_ID || "";
const clientSecret = process.env.STARFLEET_CLIENT_SECRET || "";

// Ctrl-C and SIGTERM abort the signal below instead of ending the
// process, which lets the program delete its database before it exits.
const interrupt = new AbortController();
for (const name of ["SIGINT", "SIGTERM"] as const) {
  process.once(name, () => interrupt.abort());
}
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
// An error reply from the Managed API, with its HTTP status.
class ApiError extends Error {
  constructor(
    readonly status: number,
    message: string,
  ) {
    super(message);
  }
}

// Sends an authenticated request to the Managed API and returns the
// decoded JSON reply, or undefined if the reply has no body. The request
// stops when the user presses Ctrl-C, unless the caller passes a
// different signal, as the cleanup does.
async function api<T>(
  token: string,
  method: string,
  path: string,
  body?: unknown,
  signal: AbortSignal = interrupt.signal,
): Promise<T | undefined> {
  const response = await fetch(`${baseUrl}/managed/v1${path}`, {
    method,
    headers: {
      Authorization: `Bearer ${token}`,
      ...(body === undefined ? {} : { "Content-Type": "application/json" }),
    },
    body: body === undefined ? undefined : JSON.stringify(body),
    signal: AbortSignal.any([signal, AbortSignal.timeout(30_000)]),
  });
  if (!response.ok) {
    throw new ApiError(
      response.status,
      `${method} ${path} failed: ${response.status} ${await response.text()}`,
    );
  }
  const text = await response.text();
  return text ? (JSON.parse(text) as T) : undefined;
}
// --8<-- [end:api]

// --8<-- [start:placement]
// Returns the region and size for the new database. The API lists sizes
// smallest first, so the first one is the cheapest. The API does not
// price regions, so the example takes the first one.
async function choosePlacement(
  token: string,
): Promise<{ region: string; size: string }> {
  const regions = await api<{ region: string }[]>(token, "GET", "/regions");
  const sizes = await api<{ name: string }[]>(token, "GET", "/sizes");
  if (!regions?.length || !sizes?.length) {
    throw new Error("the API offers no region or size");
  }
  return { region: regions[0].region, size: sizes[0].name };
}
// --8<-- [end:placement]

// --8<-- [start:create]
interface Database {
  id: string;
  display_name: string;
  status: string;
}

// Creates a database that only this machine can reach, and returns the
// API's description of it, which includes its ID.
async function createDatabase(
  token: string,
  region: string,
  size: string,
): Promise<Database> {
  // A new database is closed to everyone until an allowlist rule admits
  // an address. The API reports the address it sees this request come
  // from, which is the one to admit; a bare address means a single host.
  const ip = await api<{ ip_address: string }>(token, "GET", "/client-ip");

  const suffix = randomBytes(3).toString("hex");
  const database = await api<Database>(token, "POST", "/databases", {
    // The name becomes the Postgres database name, which allows only
    // letters and digits, so the readable cookbook- prefix goes in the
    // display name.
    name: `cookbook${suffix}`,
    display_name: `cookbook-${suffix}`,
    region,
    size,
    ip_allowlist: { rules: [{ cidr: ip!.ip_address, label: "cookbook" }] },
  });
  return database!;
}
// --8<-- [end:create]

// --8<-- [start:wait]
// Polls the database until its status is available.
async function waitUntilAvailable(
  token: string,
  databaseId: string,
): Promise<void> {
  const deadline = Date.now() + TIMEOUT_MS;
  let last = "";
  while (Date.now() < deadline) {
    const database = await api<Database>(token, "GET", `/databases/${databaseId}`);
    if (database!.status !== last) {
      console.log(`Database status: ${database!.status}`);
      last = database!.status;
    }
    if (database!.status === "available") {
      return;
    }
    await sleep(POLL_MS, undefined, { signal: interrupt.signal });
  }
  throw new Error(`the database was not available after ${TIMEOUT_MS / 1000} seconds`);
}
// --8<-- [end:wait]

// --8<-- [start:delete]
// Deletes the database and waits until the API no longer lists it. The
// requests ignore Ctrl-C, so that a second interrupt cannot leave the
// database behind.
async function deleteDatabase(token: string, databaseId: string): Promise<void> {
  const never = new AbortController().signal;
  const deadline = Date.now() + TIMEOUT_MS;

  for (;;) {
    try {
      await api(token, "DELETE", `/databases/${databaseId}`, undefined, never);
      break;
    } catch (err) {
      // The API refuses with 409 while the database is busy with another
      // operation, such as being created, so try again.
      if (!(err instanceof ApiError && err.status === 409) || Date.now() > deadline) {
        throw err;
      }
      await sleep(POLL_MS);
    }
  }

  // The delete starts the teardown; a 404 shows that it has finished.
  while (Date.now() < deadline) {
    try {
      await api(token, "GET", `/databases/${databaseId}`, undefined, never);
    } catch (err) {
      if (err instanceof ApiError && err.status === 404) {
        return;
      }
      throw err;
    }
    await sleep(POLL_MS);
  }
  throw new Error(`the database was still present after ${TIMEOUT_MS / 1000} seconds`);
}
// --8<-- [end:delete]

// --8<-- [start:main]
// Returns a readable description of an error. A failure to connect
// arrives as a TypeError whose cause holds the details, and Node reports
// a failure to reach several addresses as an AggregateError.
function describe(err: unknown): string {
  if (interrupt.signal.aborted) {
    return "interrupted";
  }
  if (err instanceof AggregateError) {
    return err.errors.map(describe).join("; ");
  }
  if (err instanceof Error && err.cause) {
    return `${err.message}: ${describe(err.cause)}`;
  }
  return err instanceof Error ? err.message : String(err);
}

async function main(): Promise<number> {
  let exitCode = 0;
  let token: string | undefined;
  let databaseId: string | undefined;
  try {
    token = await getToken();

    const { region, size } = await choosePlacement(token);
    console.log(`Region: ${region}`);
    console.log(`Size: ${size}`);

    const database = await createDatabase(token, region, size);
    databaseId = database.id;
    console.log(`Created database ${database.display_name}`);

    await waitUntilAvailable(token, databaseId);
    console.log("Database is available");
  } catch (err) {
    console.error(`Error: ${describe(err)}`);
    exitCode = 1;
  } finally {
    // Delete the database whether the example succeeded, failed, or was
    // interrupted, because the service bills for it until then.
    if (token && databaseId) {
      try {
        await deleteDatabase(token, databaseId);
        console.log("Deleted database");
      } catch (err) {
        console.error(`Error deleting database ${databaseId}: ${describe(err)}`);
        exitCode = 1;
      }
    }
  }
  return exitCode;
}

process.exitCode = await main();
// --8<-- [end:main]
