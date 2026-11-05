/*
 * Ellie's Postgres Cookbook
 * Creating a pgEdge Control Plane database on one host, waiting until it
 * is available, and deleting it again, using the built-in fetch.
 *
 * These examples are for the Control Plane v0.11.0.
 *
 * The database runs in containers on the host until it is deleted, so
 * this program deletes the database it creates on every path: after a
 * success, after a failure, and after Ctrl-C.
 *
 * Copyright (c) 2026, pgEdge, Inc.
 * This code is released under the PostgreSQL License.
 */

// --8<-- [start:imports]
// Node.js provides fetch and AbortSignal as globals; setTimeout from
// timers/promises returns a promise, which suits a polling loop.
import { randomBytes } from "node:crypto";
import { setTimeout as sleep } from "node:timers/promises";
// --8<-- [end:imports]

// --8<-- [start:config]
// The || operator, unlike ??, also treats an empty variable as unset. The
// new database listens on the given port on its host, so choose one that
// is free.
const baseUrl = (process.env.CONTROL_PLANE_URL || "http://localhost:3000").replace(/\/+$/, "");
const port = Number(process.env.CONTROL_PLANE_RECIPE_PORT || "6433");

const timeoutMs = 30_000;

// How long to wait for a database to become available, or to disappear
// after a delete, and how often to check.
const waitMs = 600_000;
const pollMs = 5_000;

// Ctrl-C and SIGTERM abort the signal below instead of ending the process,
// which lets the program delete its database before it exits. The
// handlers stay in place, so a further Ctrl-C does not end the process
// during the cleanup either.
const interrupt = new AbortController();
for (const signalName of ["SIGINT", "SIGTERM"] as const) {
  process.on(signalName, () => interrupt.abort());
}

// An error reply from the Control Plane, with its HTTP status.
class ControlPlaneError extends Error {
  constructor(
    message: string,
    readonly status?: number,
  ) {
    super(message);
  }
}

// Sends a request to the server, and returns the decoded reply. The
// request stops when the user presses Ctrl-C, unless the caller passes a
// different signal, as the cleanup does.
async function call<T>(
  method: string,
  path: string,
  body?: unknown,
  signal: AbortSignal = interrupt.signal,
): Promise<T> {
  const response = await fetch(`${baseUrl}${path}`, {
    method,
    headers: body === undefined ? {} : { "Content-Type": "application/json" },
    body: body === undefined ? undefined : JSON.stringify(body),
    signal: AbortSignal.any([signal, AbortSignal.timeout(timeoutMs)]),
  });

  // fetch only rejects when it cannot reach the server; an error status
  // is a normal response, so check it explicitly.
  const text = await response.text();
  if (!response.ok) {
    throw new ControlPlaneError(
      `HTTP ${response.status}, ${text.slice(0, 200) || response.statusText}`,
      response.status,
    );
  }
  try {
    return JSON.parse(text) as T;
  } catch {
    throw new ControlPlaneError(`Unexpected response: ${text.slice(0, 200)}`);
  }
}
// --8<-- [end:config]

// --8<-- [start:host]
// Returns the ID of the first host in the cluster. A database places each
// of its nodes on one or more hosts, which run the Postgres containers.
async function firstHost(): Promise<string> {
  const reply = await call<{ hosts?: { id: string }[] }>("GET", "/v1/hosts");
  const host = reply.hosts?.[0];
  if (!host) {
    throw new ControlPlaneError("the cluster has no hosts");
  }
  return host.id;
}
// --8<-- [end:host]

// --8<-- [start:create]
// Asks the Control Plane to create a database with one node. The reply
// holds the database and the task that creates it; the work happens in the
// background after the reply.
async function createDatabase(databaseId: string, host: string): Promise<void> {
  await call("POST", "/v1/databases", {
    id: databaseId,
    spec: {
      database_name: "recipe",
      port,
      nodes: [{ name: "n1", host_ids: [host] }],
    },
  });
}
// --8<-- [end:create]

// --8<-- [start:wait]
interface Database {
  state?: string;
  instances?: { connection_info?: { port?: number } }[];
}

// Polls the database, printing its state each time it changes, until the
// state is available, and returns the port of its first instance. Each
// instance runs one node, and its connection_info holds the address and
// port that clients use. A failed state ends the wait at once.
async function waitUntilAvailable(databaseId: string): Promise<number | undefined> {
  const deadline = Date.now() + waitMs;
  let last: string | undefined;
  while (Date.now() < deadline) {
    const database = await call<Database>("GET", `/v1/databases/${databaseId}`);
    if (database.state !== last) {
      console.log(`Database state: ${database.state}`);
      last = database.state;
    }
    if (database.state === "available") {
      return database.instances?.[0]?.connection_info?.port;
    }
    if (database.state === "failed") {
      throw new ControlPlaneError("the database has the state failed");
    }
    await sleep(pollMs, undefined, { signal: interrupt.signal });
  }
  throw new ControlPlaneError(`the database was not available after ${waitMs / 1000} seconds`);
}
// --8<-- [end:wait]

// --8<-- [start:delete]
// Reports whether a failed request is worth repeating: no reply arrived,
// the server failed, or it answered 409, which the Control Plane does
// whilst another task, such as the create, is still running on the
// database.
function isTransient(err: unknown): boolean {
  if (!(err instanceof ControlPlaneError)) {
    return true;
  }
  return err.status !== undefined && (err.status === 409 || err.status >= 500);
}

function isGone(err: unknown): boolean {
  return err instanceof ControlPlaneError && err.status === 404;
}

// Deletes the database and waits until the API no longer has it. A 404
// means that the database is already gone. The cleanup runs after Ctrl-C,
// so its requests and waits use a signal that never aborts.
async function deleteDatabase(databaseId: string): Promise<void> {
  const never = new AbortController().signal;
  const path = `/v1/databases/${databaseId}`;
  const deadline = Date.now() + waitMs;
  for (;;) {
    try {
      await call("DELETE", path, undefined, never);
      break;
    } catch (err) {
      if (isGone(err)) {
        return;
      }
      if (!isTransient(err) || Date.now() >= deadline) {
        throw err;
      }
      await sleep(pollMs);
    }
  }

  // The delete starts a task that removes the database; a 404 shows that
  // it has finished.
  while (Date.now() < deadline) {
    try {
      await call("GET", path, undefined, never);
    } catch (err) {
      if (isGone(err)) {
        return;
      }
      if (!isTransient(err)) {
        throw err;
      }
    }
    await sleep(pollMs);
  }
  throw new ControlPlaneError(`the database was still present after ${waitMs / 1000} seconds`);
}
// --8<-- [end:delete]

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
  let exitCode = 0;
  let created = false;
  // The client chooses the ID of a new database, so the program knows it
  // before the request, and can delete the database even if the reply
  // never arrives. The random suffix keeps the ID unique.
  const databaseId = `cookbook-recipe-${randomBytes(3).toString("hex")}`;
  try {
    const host = await firstHost();
    console.log(`Host: ${host}`);

    // Clean up unless the server refused the request with a 4xx status,
    // which means it created nothing; a 409, for example, means that a
    // database with this ID already exists, and is not this program's to
    // delete.
    created = true;
    try {
      await createDatabase(databaseId, host);
    } catch (err) {
      if (err instanceof ControlPlaneError && err.status && err.status < 500) {
        created = false;
      }
      throw err;
    }
    console.log(`Created database ${databaseId}`);

    const instancePort = await waitUntilAvailable(databaseId);
    console.log(`Database is available on port ${instancePort}`);
  } catch (err) {
    if (interrupt.signal.aborted) {
      console.error("Interrupted");
      exitCode = 130;
    } else {
      console.error(`Control Plane error: ${describe(err)}`);
      exitCode = 1;
    }
  } finally {
    // Delete the database whether the example succeeded, failed, or was
    // interrupted.
    if (created) {
      try {
        await deleteDatabase(databaseId);
        console.log("Deleted database");
      } catch (err) {
        console.error(`Control Plane error: ${describe(err)}`);
        console.error(`Delete the database ${databaseId} by hand`);
        exitCode = 1;
      }
    }
  }
  return exitCode;
}

process.exitCode = await main();
// --8<-- [end:main]
