/*
 * Ellie's Postgres Cookbook
 * Changing a Postgres setting of a pgEdge Control Plane database, checking
 * it from a connection, and putting the original settings back, using the
 * built-in fetch and node-postgres.
 *
 * These examples are for the Control Plane v0.11.0.
 *
 * The program restores the original settings on every path: after a
 * success, after a failure, and after Ctrl-C.
 *
 * Copyright (c) 2026, pgEdge, Inc.
 * This code is released under the PostgreSQL License.
 */

// --8<-- [start:imports]
// Node.js provides fetch and AbortSignal as globals; setTimeout from
// timers/promises returns a promise, which suits a polling loop. pg is
// node-postgres.
import { setTimeout as sleep } from "node:timers/promises";
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

// The setting to change, and its new value.
const setting = "work_mem";
const value = "16MB";

// How long to wait for an update to finish, and how often to check.
const waitMs = 600_000;
const pollMs = 5_000;

// Ctrl-C and SIGTERM abort the signal below instead of ending the process,
// which lets the program restore the settings before it exits. The
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

// An error from the database connection or its query.
class DatabaseError extends Error {}

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

// --8<-- [start:update]
// The spec is kept as plain JSON, so that the update sends back every
// field that the server returned, including any that this program does
// not know about.
type Spec = Record<string, unknown> & { postgresql_conf?: Record<string, unknown> };

// Sends a whole database spec as an update, and returns the ID of the
// task that applies it. The Control Plane compares the spec with the
// current one and changes only what differs; the work happens in the task
// after the reply.
async function updateDatabase(spec: Spec, signal?: AbortSignal): Promise<string> {
  const reply = await call<{ task: { task_id: string } }>(
    "POST",
    `/v1/databases/${databaseId}`,
    { spec },
    signal,
  );
  return reply.task.task_id;
}

// Returns a copy of the spec with the setting changed. postgresql_conf
// holds the Postgres settings that the Control Plane manages, and may be
// missing.
function changedSpec(spec: Spec): Spec {
  return { ...spec, postgresql_conf: { ...spec.postgresql_conf, [setting]: value } };
}
// --8<-- [end:update]

// --8<-- [start:wait]
// Reports whether a failed request is worth repeating: no reply arrived,
// the server failed, or it answered 409, which the Control Plane does
// whilst another task, such as the update, is still running on the
// database.
function isTransient(err: unknown): boolean {
  if (!(err instanceof ControlPlaneError)) {
    return true;
  }
  return err.status !== undefined && (err.status === 409 || err.status >= 500);
}

// Polls a task until it finishes, and throws an error unless it
// completed. A failed poll is repeated if it is worth repeating. The
// cleanup passes a signal that never aborts.
async function waitForTask(taskId: string, signal: AbortSignal = interrupt.signal): Promise<void> {
  const deadline = Date.now() + waitMs;
  while (Date.now() < deadline) {
    let task: { status?: string } = {};
    try {
      task = await call<{ status?: string }>(
        "GET",
        `/v1/databases/${databaseId}/tasks/${taskId}`,
        undefined,
        signal,
      );
    } catch (err) {
      if (signal.aborted || !isTransient(err)) {
        throw err;
      }
    }
    if (task.status === "completed") {
      return;
    }
    if (task.status === "failed" || task.status === "canceled") {
      throw new ControlPlaneError(`the task finished with the status ${task.status}`);
    }
    await sleep(pollMs, undefined, { signal });
  }
  throw new ControlPlaneError(`the task was still running after ${waitMs / 1000} seconds`);
}
// --8<-- [end:wait]

// --8<-- [start:connect]
interface Database {
  spec: { database_name: string };
  instances?: {
    state?: string;
    connection_info?: { addresses?: string[]; port?: number };
  }[];
}

// Connects to the first available instance and returns the current value
// of the setting. Each instance runs one node, and its connection_info
// holds the address and port that clients use.
async function showSetting(): Promise<string> {
  const database = await call<Database>("GET", `/v1/databases/${databaseId}`);
  const info = database.instances?.find(
    (i) => i.state === "available" && i.connection_info?.addresses?.length,
  )?.connection_info;
  if (!info) {
    throw new ControlPlaneError(`no available instance of ${databaseId}`);
  }

  const client = new pg.Client({
    host: info.addresses![0],
    port: info.port,
    database: database.spec.database_name,
    user: databaseUser,
    password: databasePassword,
    connectionTimeoutMillis: timeoutMs,
  });
  try {
    await client.connect();
  } catch (err) {
    throw new DatabaseError(describe(err));
  }
  try {
    const result = await client.query<{ current_setting: string }>(
      "SELECT current_setting($1)",
      [setting],
    );
    return result.rows[0].current_setting;
  } catch (err) {
    throw new DatabaseError(describe(err));
  } finally {
    // Close the connection whether or not the query failed.
    await client.end();
  }
}
// --8<-- [end:connect]

// --8<-- [start:restore]
// Sends the original spec back and waits for the task. The Control Plane
// answers 409 whilst another task, such as the update, is still running on
// the database, so the program repeats the request, as it does when no
// reply arrived or the server failed. The cleanup runs after Ctrl-C, so
// its requests and waits use a signal that never aborts.
async function restore(spec: Spec): Promise<void> {
  const never = new AbortController().signal;
  const deadline = Date.now() + waitMs;
  let taskId: string;
  for (;;) {
    try {
      taskId = await updateDatabase(spec, never);
      break;
    } catch (err) {
      if (!isTransient(err) || Date.now() >= deadline) {
        throw err;
      }
      await sleep(pollMs);
    }
  }
  await waitForTask(taskId, never);
}
// --8<-- [end:restore]

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

  let exitCode = 0;
  let changed = false;
  let original: Spec | undefined;
  try {
    // The spec that the API returns leaves out the passwords of the
    // database users, and an update may leave them out too, which keeps
    // them unchanged.
    original = (await call<{ spec: Spec }>("GET", `/v1/databases/${databaseId}`)).spec;

    // Restore unless the server refused the request with a 4xx status,
    // which means that it changed nothing.
    console.log(`Setting ${setting} to ${value}`);
    changed = true;
    let taskId: string;
    try {
      taskId = await updateDatabase(changedSpec(original));
    } catch (err) {
      if (err instanceof ControlPlaneError && err.status && err.status < 500) {
        changed = false;
      }
      throw err;
    }
    await waitForTask(taskId);
    console.log("Update completed");

    console.log(`${setting} is now ${await showSetting()}`);
    // The database connection does not stop for Ctrl-C, so check whether
    // a signal arrived whilst it was open.
    if (interrupt.signal.aborted) {
      throw new Error("Interrupted");
    }
  } catch (err) {
    if (interrupt.signal.aborted) {
      console.error("Interrupted");
      exitCode = 130;
    } else if (err instanceof DatabaseError) {
      console.error(`Database error: ${err.message}`);
      exitCode = 1;
    } else {
      console.error(`Control Plane error: ${describe(err)}`);
      exitCode = 1;
    }
  } finally {
    // Restore the original settings whether the example succeeded,
    // failed, or was interrupted.
    if (changed && original) {
      try {
        await restore(original);
        console.log("Restored the original settings");
      } catch (err) {
        console.error(`Control Plane error: ${describe(err)}`);
        console.error(`Restore the settings of the database ${databaseId} by hand`);
        exitCode = 1;
      }
    }
  }
  return exitCode;
}

process.exitCode = await main();
// --8<-- [end:main]
