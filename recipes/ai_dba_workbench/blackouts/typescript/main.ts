/*
 * Ellie's Postgres Cookbook
 * Scheduling a maintenance blackout with the AI DBA Workbench API, using the
 * built-in fetch.
 *
 * Copyright (c) 2026, pgEdge, Inc.
 * This code is released under the PostgreSQL License.
 */

// --8<-- [start:imports]
// The program needs no imports: fetch and process are built in to Node.js.
// --8<-- [end:imports]

// --8<-- [start:config]
interface Settings {
  baseUrl: string;
  token: string;
  connectionId: number;
}

// Read the settings from the environment. The || operator, unlike ??, also
// treats an empty variable as unset.
function settings(): Settings {
  const token = process.env.WORKBENCH_TOKEN || "";
  const connectionId = process.env.WORKBENCH_CONNECTION_ID || "";
  if (!token || !connectionId) {
    throw new Error("WORKBENCH_TOKEN and WORKBENCH_CONNECTION_ID must be set");
  }
  if (!/^\d+$/.test(connectionId)) {
    throw new Error("WORKBENCH_CONNECTION_ID must be a number");
  }
  const baseUrl = process.env.WORKBENCH_URL || "http://localhost:8080";
  return {
    baseUrl: baseUrl.replace(/\/+$/, ""),
    token,
    connectionId: Number(connectionId),
  };
}
// --8<-- [end:config]

// --8<-- [start:request]
interface Blackout {
  id: number;
  is_active: boolean;
}

// Aborts the request in progress, and every later one that can be
// interrupted, when the program receives SIGINT or SIGTERM. The handlers also
// stop Node.js from exiting on those signals, which lets the cleanup run, and
// a second signal during the cleanup does nothing.
const interrupted = new AbortController();
for (const name of ["SIGINT", "SIGTERM"] as const) {
  process.on(name, () => interrupted.abort(new Error(`Interrupted by ${name}`)));
}

// Sends a request to the API and returns the response. A request that the
// server rejects throws an error that includes the message from the server.
// The cleanup passes interruptible as false, so that a signal cannot cancel
// it.
async function api(
  s: Settings,
  method: string,
  path: string,
  body?: unknown,
  interruptible = true,
): Promise<Response> {
  const headers: Record<string, string> = {
    Authorization: `Bearer ${s.token}`,
  };
  if (body !== undefined) headers["Content-Type"] = "application/json";

  const response = await fetch(`${s.baseUrl}/api/v1${path}`, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
    signal: interruptible
      ? AbortSignal.any([AbortSignal.timeout(30_000), interrupted.signal])
      : AbortSignal.timeout(30_000),
  });
  if (!response.ok) {
    const text = (await response.text()).trim();
    throw new Error(
      `${method} ${path} failed with status ${response.status}: ${text}`,
    );
  }
  return response;
}
// --8<-- [end:request]

// --8<-- [start:create]
// Creates a blackout for one monitored server and returns it. The blackout
// starts a minute ago, so that a small difference between the clocks of this
// machine and the server cannot leave it inactive, and it ends in one hour.
// The toISOString method writes the times in RFC 3339 format.
async function createBlackout(s: Settings): Promise<Blackout> {
  const now = Date.now();
  // A signal cannot interrupt this request either, because the program
  // would not know the ID of a blackout that the server created after the
  // interruption. The next request notices the signal instead.
  const response = await api(
    s,
    "POST",
    "/blackouts",
    {
      scope: "server",
      connection_id: s.connectionId,
      reason: "Cookbook maintenance window",
      start_time: new Date(now - 60_000).toISOString(),
      end_time: new Date(now + 3_600_000).toISOString(),
    },
    false,
  );
  return (await response.json()) as Blackout;
}
// --8<-- [end:create]

// --8<-- [start:read]
// Returns the blackout with the given ID.
async function getBlackout(s: Settings, id: number): Promise<Blackout> {
  const response = await api(s, "GET", `/blackouts/${id}`);
  return (await response.json()) as Blackout;
}
// --8<-- [end:read]

// --8<-- [start:stop]
// Stops a blackout that is in progress, which sets its end time to now, and
// returns the stopped blackout.
async function stopBlackout(s: Settings, id: number): Promise<Blackout> {
  const response = await api(s, "POST", `/blackouts/${id}/stop`);
  return (await response.json()) as Blackout;
}
// --8<-- [end:stop]

// --8<-- [start:delete]
// Deletes a blackout by its ID. A signal cannot interrupt this request,
// because it is the cleanup.
async function deleteBlackout(s: Settings, id: number): Promise<void> {
  await api(s, "DELETE", `/blackouts/${id}`, undefined, false);
}
// --8<-- [end:delete]

// --8<-- [start:main]
async function main(): Promise<number> {
  let exitCode = 0;
  let cleanup: (() => Promise<void>) | undefined;
  try {
    const s = settings();

    const created = await createBlackout(s);
    // Delete the blackout whether or not a later step fails, so that a
    // failed run does not leave alerts suppressed.
    cleanup = () => deleteBlackout(s, created.id);
    console.log(
      `Created a blackout for the server (active: ${created.is_active})`,
    );

    const blackout = await getBlackout(s, created.id);
    console.log(`Read the blackout back (active: ${blackout.is_active})`);

    const stopped = await stopBlackout(s, created.id);
    console.log(`Stopped the blackout (active: ${stopped.is_active})`);
    if (stopped.is_active) throw new Error("The blackout is still active");

    await cleanup();
    cleanup = undefined;
    console.log("Deleted the blackout");
  } catch (err) {
    console.error(`Error: ${err instanceof Error ? err.message : err}`);
    exitCode = 1;
  }

  if (cleanup) {
    try {
      await cleanup();
    } catch (err) {
      console.error(
        `Error: could not delete the blackout: ${
          err instanceof Error ? err.message : err
        }`,
      );
      exitCode = 1;
    }
  }
  return exitCode;
}

process.exitCode = await main();
// --8<-- [end:main]
