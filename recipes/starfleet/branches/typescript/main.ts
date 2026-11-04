/*
 * Ellie's Postgres Cookbook
 * Creating a branch of a pgEdge Starfleet database for a test run, and
 * connecting to it, using the built-in fetch function and node-postgres.
 *
 * The program creates a database of its own to branch. The Starfleet
 * service bills for every database and every branch from the moment that
 * it becomes connectable, so the program deletes the branch and then the
 * database on every path: after a success, after a failure, and after
 * Ctrl-C.
 *
 * Copyright (c) 2026, pgEdge, Inc.
 * This code is released under the PostgreSQL License.
 */

// --8<-- [start:imports]
import { randomBytes } from "node:crypto";
import pg from "pg";
import process from "node:process";
import { setTimeout as sleep } from "node:timers/promises";
// --8<-- [end:imports]

// --8<-- [start:config]
// How long to wait for a database to become available, or to disappear
// after a delete, and how often to check.
const TIMEOUT_MS = 900_000;
const POLL_MS = 10_000;

// How many times to look for a database whose create reply was lost.
const LOOKUP_ATTEMPTS = 3;

// How many times to try connecting to the database before giving up.
const CONNECT_ATTEMPTS = 6;

// Read the API settings from the environment. The || operator, unlike ??,
// also treats an empty variable as unset.
const baseUrl = (
  process.env.STARFLEET_API_URL || "https://api.pgedge.com"
).replace(/\/+$/, "");
const clientId = process.env.STARFLEET_CLIENT_ID || "";
const clientSecret = process.env.STARFLEET_CLIENT_SECRET || "";

// Ctrl-C and SIGTERM abort the signal below instead of ending the
// process, which lets the program delete its database before it exits.
// The handlers stay in place, so a further Ctrl-C does not end the process
// during the cleanup either.
const interrupt = new AbortController();
for (const signalName of ["SIGINT", "SIGTERM"] as const) {
  process.on(signalName, () => interrupt.abort());
}
// --8<-- [end:config]

// --8<-- [start:token]
// Exchanges the client ID and secret for an access token, which the
// Managed API accepts as a bearer token until it expires.
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

// Returns this machine's public IP address as the API sees it.
async function clientIp(token: string): Promise<string> {
  // A new database is closed to everyone until an allowlist rule admits
  // an address. The API reports the address it sees this request come
  // from, which is the one to admit; a bare address means a single host.
  const reply = await api<{ ip_address: string }>(token, "GET", "/client-ip");
  return reply!.ip_address;
}

// Creates a database that only this machine can reach, and returns the
// API's description of it, which includes its ID.
async function createDatabase(
  token: string,
  name: string,
  displayName: string,
  region: string,
  size: string,
  ip: string,
): Promise<Database> {
  const database = await api<Database>(token, "POST", "/databases", {
    // The name becomes the Postgres database name, so it holds only
    // letters and digits, and the readable cookbook- prefix goes in the
    // display name. The program also uses the name to find the database
    // again if the reply to this request is lost.
    name,
    display_name: displayName,
    region,
    size,
    ip_allowlist: { rules: [{ cidr: ip, label: "cookbook" }] },
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
    // The API does not document its status values; the example treats
    // these two as failures, which end the wait at once instead of leaving
    // it to run until the time limit.
    if (database!.status === "degraded" || database!.status === "failed") {
      throw new Error(`the database has the status ${database!.status}`);
    }
    await sleep(POLL_MS, undefined, { signal: interrupt.signal });
  }
  throw new Error(`the database was not available after ${TIMEOUT_MS / 1000} seconds`);
}
// --8<-- [end:wait]

// --8<-- [start:branch]
interface Branch {
  id: string;
  display_name?: string;
  status: string;
}

// Creates a copy-on-write branch of the database, and returns the API's
// description of it, which includes its ID.
async function createBranch(
  token: string,
  databaseId: string,
  displayName: string,
): Promise<Branch> {
  // The API assigns the name of a branch, so the program gives the branch
  // a display name and uses that to find it again if the reply to this
  // request is lost. The request sets no allowlist, so the branch copies
  // the rules of the database, which admit this machine. The branch also
  // copies the size, the region, and the Postgres version.
  const branch = await api<Branch>(
    token,
    "POST",
    `/databases/${databaseId}/branches`,
    { display_name: displayName },
  );
  return branch!;
}

// Polls the branch until its status is available.
async function waitUntilBranchAvailable(
  token: string,
  branchPath: string,
): Promise<void> {
  const deadline = Date.now() + TIMEOUT_MS;
  let last = "";
  while (Date.now() < deadline) {
    const branch = await api<Branch>(token, "GET", branchPath);
    if (branch!.status !== last) {
      console.log(`Branch status: ${branch!.status}`);
      last = branch!.status;
    }
    if (branch!.status === "available") {
      return;
    }
    if (branch!.status === "degraded" || branch!.status === "failed") {
      throw new Error(`the branch has the status ${branch!.status}`);
    }
    await sleep(POLL_MS, undefined, { signal: interrupt.signal });
  }
  throw new Error(`the branch was not available after ${TIMEOUT_MS / 1000} seconds`);
}
// --8<-- [end:branch]

// --8<-- [start:connection]
// Reads the connection details of an available branch, and returns them
// as a node-postgres configuration.
async function connectionConfig(
  token: string,
  branchPath: string,
): Promise<pg.ClientConfig> {
  // The connection details, including the password of the branch's own
  // application user, come with the description of the branch. They are
  // present only while the branch is available. The API does not require
  // the host, so fall back to the external IP address if it is missing.
  const database = await api<{
    connection?: {
      host?: string;
      external_ip_address?: string;
      port?: number;
      database?: string;
      username?: string;
      password?: string;
    };
  }>(token, "GET", branchPath);
  const connection = database?.connection;
  const host = connection?.host || connection?.external_ip_address;
  if (
    !host ||
    !connection?.port ||
    !connection.database ||
    !connection.username ||
    !connection.password
  ) {
    throw new Error("the database description has incomplete connection details");
  }

  return {
    host,
    port: connection.port,
    database: connection.database,
    user: connection.username,
    password: connection.password,
    // Encrypt the connection. The certificate of a Starfleet database is
    // not signed by a public authority, so the example does not verify it.
    ssl: { rejectUnauthorized: false },
    connectionTimeoutMillis: 15_000,
  };
}
// --8<-- [end:connection]

// --8<-- [start:query]
// Connects to the database and returns the server's version string.
async function serverVersion(config: pg.ClientConfig): Promise<string> {
  // A database can refuse connections for a short while after the API
  // reports it as available, so try a few times before giving up. An
  // error from the server itself, such as a failed login, will not change
  // on a second attempt. A failed client cannot be reused, so each attempt
  // makes a new one.
  let client = new pg.Client(config);
  for (let attempt = 1; ; attempt++) {
    try {
      await client.connect();
      break;
    } catch (err) {
      if (err instanceof pg.DatabaseError || attempt === CONNECT_ATTEMPTS) {
        throw err;
      }
      await sleep(POLL_MS, undefined, { signal: interrupt.signal });
      client = new pg.Client(config);
    }
  }
  try {
    const result = await client.query<{ version: string }>("SELECT version()");
    return result.rows[0].version;
  } finally {
    // The finally block closes the connection whether or not the query
    // failed.
    await client.end();
  }
}
// --8<-- [end:query]

// --8<-- [start:delete]
// Reports whether a failed request is worth repeating: no reply arrived
// (fetch rejects, and the error is not an ApiError), the service is
// overloaded or failing, or it answered 409, which the API does whilst a
// database is still being created.
function isTransient(err: unknown): boolean {
  if (!(err instanceof ApiError)) {
    return true;
  }
  return err.status === 409 || err.status === 429 || err.status >= 500;
}

// Looks for the database a few times, because the service may not have
// recorded a request whose reply was lost until a little later. Returns
// undefined if the database never appears.
async function findCreatedDatabase(
  token: string,
  name: string,
  signal: AbortSignal,
): Promise<string | undefined> {
  for (let attempt = 1; ; attempt++) {
    const id = await findDatabase(token, name, signal);
    if (id || attempt === LOOKUP_ATTEMPTS) {
      return id;
    }
    await sleep(POLL_MS);
  }
}

// Reports whether a failed create request might still have created the
// database: no reply arrived, the reply could not be decoded, or the
// service failed with a 5xx status. A 4xx reply is a definite refusal.
function outcomeUnknown(err: unknown): boolean {
  return !(err instanceof ApiError) || err.status >= 500;
}

// Returns the ID of the database with the given name, or undefined. The
// program uses this when it cannot tell whether a create request worked.
// It repeats the request, as the delete does, because the fault that lost
// the reply to the create request may still be there. The request asks for
// the newest databases first, but the API does not say which property it
// sorts on.
async function findDatabase(
  token: string,
  name: string,
  signal: AbortSignal,
): Promise<string | undefined> {
  const deadline = Date.now() + TIMEOUT_MS;
  for (;;) {
    try {
      const databases = await api<{ id: string; name: string }[]>(
        token,
        "GET",
        "/databases?limit=100&descending=true",
        undefined,
        signal,
      );
      return databases?.find((database) => database.name === name)?.id;
    } catch (err) {
      if (!isTransient(err) || Date.now() > deadline) {
        throw err;
      }
      await sleep(POLL_MS);
    }
  }
}

// Returns the branches of the database that have not been deleted, newest
// first. The request repeats, as the deletes do, and a 404 means that the
// database has gone, and so have its branches.
async function listBranches(token: string, databaseId: string): Promise<Branch[]> {
  const never = new AbortController().signal;
  const deadline = Date.now() + TIMEOUT_MS;
  for (;;) {
    try {
      const branches = await api<Branch[]>(
        token,
        "GET",
        `/databases/${databaseId}/branches?limit=100&descending=true`,
        undefined,
        never,
      );
      return branches ?? [];
    } catch (err) {
      if (err instanceof ApiError && err.status === 404) {
        return [];
      }
      if (!isTransient(err) || Date.now() > deadline) {
        throw err;
      }
      await sleep(POLL_MS);
    }
  }
}

// Looks for the branch with the given display name a few times, because
// the service may not have recorded a request whose reply was lost until a
// little later. Returns undefined if the branch never appears.
async function findCreatedBranch(
  token: string,
  databaseId: string,
  displayName: string,
): Promise<string | undefined> {
  for (let attempt = 1; ; attempt++) {
    const branches = await listBranches(token, databaseId);
    const id = branches.find((branch) => branch.display_name === displayName)?.id;
    if (id || attempt === LOOKUP_ATTEMPTS) {
      return id;
    }
    await sleep(POLL_MS);
  }
}

// Deletes the branch and waits until the API no longer lists it. The
// requests ignore Ctrl-C, so that a second interrupt cannot leave the
// branch behind.
async function deleteBranch(
  token: string,
  databaseId: string,
  branchId: string,
): Promise<void> {
  const never = new AbortController().signal;
  const deadline = Date.now() + TIMEOUT_MS;

  for (;;) {
    try {
      await api(
        token,
        "DELETE",
        `/databases/${databaseId}/branches/${branchId}`,
        undefined,
        never,
      );
      break;
    } catch (err) {
      if (err instanceof ApiError && err.status === 404) {
        return;
      }
      if (!isTransient(err) || Date.now() > deadline) {
        throw err;
      }
      await sleep(POLL_MS);
    }
  }

  // The API takes a branch out of the list as soon as it accepts the
  // delete, even though the teardown carries on afterwards.
  while (Date.now() < deadline) {
    const branches = await listBranches(token, databaseId);
    if (branches.every((branch) => branch.id !== branchId)) {
      return;
    }
    await sleep(POLL_MS);
  }
  throw new Error(`the branch was still listed after ${TIMEOUT_MS / 1000} seconds`);
}

// Deletes the database and waits until the API no longer lists it. The
// requests ignore Ctrl-C, so that a second interrupt cannot leave the
// database behind.
async function deleteDatabase(token: string, databaseId: string): Promise<void> {
  const never = new AbortController().signal;
  const deadline = Date.now() + TIMEOUT_MS;

  for (;;) {
    try {
      // The API refuses to delete a database that has branches, with a 409
      // reply, unless force=true, which deletes every branch first. The
      // program has deleted its branch by now, so this is a safety net for
      // a branch that the program could not find.
      await api(
        token,
        "DELETE",
        `/databases/${databaseId}?force=true`,
        undefined,
        never,
      );
      break;
    } catch (err) {
      if (err instanceof ApiError && err.status === 404) {
        return;
      }
      if (!isTransient(err) || Date.now() > deadline) {
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
      if (!isTransient(err)) {
        throw err;
      }
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
  let name: string | undefined;
  let databaseId: string | undefined;
  let branchId: string | undefined;
  let branchName: string | undefined;
  let branchLookup = false;
  let lookup = false;
  try {
    token = await getToken();

    const { region, size } = await choosePlacement(token);
    console.log(`Region: ${region}`);
    console.log(`Size: ${size}`);

    // Choose the name before the request, so that the program can find
    // the database even if the reply to the request never arrives.
    const suffix = randomBytes(3).toString("hex");
    name = `cookbook${suffix}`;
    // Look the database up by name afterwards only if the outcome of the
    // request is unknown, so that a refusal cannot lead the cleanup to
    // delete another database that has the same name.
    const ip = await clientIp(token);
    lookup = true;
    let database;
    try {
      database = await createDatabase(
        token,
        name,
        `cookbook-${suffix}`,
        region,
        size,
        ip,
      );
    } catch (err) {
      lookup = outcomeUnknown(err);
      throw err;
    }
    databaseId = database.id;
    console.log(`Created database ${database.display_name}`);

    await waitUntilAvailable(token, databaseId);
    console.log("Database is available");

    // The program names the branch before the request, as it does the
    // database, and looks it up afterwards only if the outcome is unknown.
    branchName = `cookbook-${suffix}-branch`;
    branchLookup = true;
    let branch;
    try {
      branch = await createBranch(token, databaseId, branchName);
    } catch (err) {
      branchLookup = outcomeUnknown(err);
      throw err;
    }
    branchId = branch.id;
    console.log(`Created branch ${branch.display_name}`);

    const branchPath = `/databases/${databaseId}/branches/${branchId}`;
    await waitUntilBranchAvailable(token, branchPath);
    console.log("Branch is available");

    const config = await connectionConfig(token, branchPath);
    console.log(`Branch server version: ${await serverVersion(config)}`);
  } catch (err) {
    if (interrupt.signal.aborted) {
      console.error("Interrupted");
      exitCode = 130;
    } else {
      console.error(`Error: ${describe(err)}`);
      exitCode = 1;
    }
  } finally {
    // Delete the database whether the example succeeded, failed, or was
    // interrupted, because the service bills for it until then.
    if (token && name) {
      try {
        if (!databaseId && lookup) {
          databaseId = await findCreatedDatabase(
            token,
            name,
            new AbortController().signal,
          );
          if (!databaseId) {
            console.error(
              `Error: the database ${name} was not found; check your account for it by hand`,
            );
            exitCode = 1;
          }
        }
        if (databaseId) {
          // Delete the branch before the database. A failure here must not
          // stop the database delete, which uses force=true as a safety
          // net.
          try {
            if (!branchId && branchLookup && branchName) {
              branchId = await findCreatedBranch(token, databaseId, branchName);
              if (!branchId) {
                console.error(
                  `Error: the branch ${branchName} was not found; check your account for it by hand`,
                );
                exitCode = 1;
              }
            }
            if (branchId) {
              await deleteBranch(token, databaseId, branchId);
              console.log("Deleted branch");
            }
          } catch (err) {
            console.error(`Error: ${describe(err)}`);
            console.error(
              "The forced delete of the database that follows also deletes the branch",
            );
            exitCode = 1;
          }
          await deleteDatabase(token, databaseId);
          console.log("Deleted database");
        }
      } catch (err) {
        console.error(`Error: ${describe(err)}`);
        console.error(
          `Delete the database ${databaseId ?? name} and any branches by hand, because they may still be billing`,
        );
        exitCode = 1;
      }
    }
  }
  return exitCode;
}

process.exitCode = await main();
// --8<-- [end:main]
