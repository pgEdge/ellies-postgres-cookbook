/*
 * Ellie's Postgres Cookbook
 * Checking the version of the pgEdge Control Plane, its cluster, and the
 * state of each host, using the built-in fetch.
 *
 * These examples are for the Control Plane v0.11.0.
 *
 * Copyright (c) 2026, pgEdge, Inc.
 * This code is released under the PostgreSQL License.
 */

// --8<-- [start:imports]
// Node.js provides fetch and AbortSignal as globals, so this program
// imports nothing.
// --8<-- [end:imports]

// --8<-- [start:config]
// The || operator, unlike ??, also treats an empty variable as unset.
const baseUrl = (process.env.CONTROL_PLANE_URL || "http://localhost:3000").replace(/\/+$/, "");

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

// --8<-- [start:version]
// Prints the version of the Control Plane server.
async function showVersion(): Promise<void> {
  const body = await get<{ version?: unknown }>("/v1/version");
  if (typeof body.version !== "string") {
    throw new Error("Unexpected response: missing version");
  }
  console.log(`Version: ${body.version}`);
}
// --8<-- [end:version]

// --8<-- [start:cluster]
// Prints the state of the cluster. A server answers this request only
// once its cluster has been initialised, and it then reports "available";
// the health of the cluster shows in the state of each host.
async function showCluster(): Promise<void> {
  const body = await get<{ status?: { state?: unknown } }>("/v1/cluster");
  if (typeof body.status?.state !== "string") {
    throw new Error("Unexpected response: missing state");
  }
  console.log(`Cluster: ${body.status.state}`);
}
// --8<-- [end:cluster]

// --8<-- [start:hosts]
interface Host {
  id?: string;
  status?: { state?: string };
}

// Lists the hosts in the cluster with their states, and returns whether
// every host is "healthy". The other states are "degraded", "unreachable"
// and "unknown".
async function showHosts(): Promise<boolean> {
  const body = await get<{ hosts?: Host[] }>("/v1/hosts");
  if (!Array.isArray(body.hosts)) {
    throw new Error("Unexpected response: missing hosts");
  }

  console.log(`Hosts (${body.hosts.length}):`);
  let healthy = true;
  for (const host of body.hosts) {
    const state = host.status?.state ?? "unknown";
    console.log(`- ${host.id}: ${state}`);
    healthy &&= state === "healthy";
  }
  return healthy;
}
// --8<-- [end:hosts]

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
  try {
    await showVersion();
    await showCluster();
    const healthy = await showHosts();

    // Report an unhealthy host with the exit status.
    if (!healthy) {
      console.error("A host is not healthy");
      return 1;
    }
    return 0;
  } catch (err) {
    console.error(`Control Plane error: ${describe(err)}`);
    return 1;
  }
}

process.exitCode = await main();
// --8<-- [end:main]
