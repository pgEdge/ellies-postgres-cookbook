/*
 * Ellie's Postgres Cookbook
 * Checking the health of the pgEdge RAG Server and listing its pipelines,
 * using the built-in fetch.
 *
 * These examples are for pgEdge RAG Server 2.0.0.
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
const baseUrl = (process.env.RAG_SERVER_URL || "http://localhost:8080").replace(/\/+$/, "");

// None of these endpoints calls a language model, but the health check
// contacts each provider, so allow it some time.
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

// --8<-- [start:live]
// Checks that the server process is running. The /v1/live endpoint is
// cheap and calls nothing else, so it suits a frequent liveness probe.
async function checkLive(): Promise<void> {
  const body = await get<{ status?: string }>("/v1/live");
  if (body.status !== "ok") {
    throw new Error(`Unexpected response: ${JSON.stringify(body)}`);
  }
  console.log("Live: ok");
}
// --8<-- [end:live]

// --8<-- [start:health]
interface Provider {
  reachable?: boolean;
  error?: string;
}

interface PipelineHealth {
  name?: string;
  embedding?: Provider;
  completion?: Provider;
}

// Describes whether a language model provider answered the check.
function describeProvider(provider: Provider = {}): string {
  return provider.reachable ? "reachable" : `unreachable (${provider.error ?? "unknown"})`;
}

// Checks whether each pipeline can reach its language model providers.
// The /v1/health endpoint answers with HTTP 200 even when a provider is
// down, so the status field is the thing to check: it is "healthy" or
// "degraded". Prints the report, and returns whether the server is
// healthy.
async function checkHealth(): Promise<boolean> {
  const body = await get<{ status?: unknown; pipelines?: PipelineHealth[] }>("/v1/health");
  if (typeof body.status !== "string") {
    throw new Error(`Unexpected response: ${JSON.stringify(body)}`);
  }

  console.log(`Health: ${body.status}`);
  for (const pipeline of body.pipelines ?? []) {
    console.log(
      `- ${pipeline.name}: embedding ${describeProvider(pipeline.embedding)}, ` +
        `completion ${describeProvider(pipeline.completion)}`,
    );
  }
  return body.status === "healthy";
}
// --8<-- [end:health]

// --8<-- [start:pipelines]
// Lists the pipelines that the server offers, with their descriptions.
async function listPipelines(): Promise<void> {
  const body = await get<{ pipelines?: { name?: string; description?: string }[] }>(
    "/v1/pipelines",
  );
  if (!Array.isArray(body.pipelines)) {
    throw new Error("Unexpected response: missing pipelines");
  }

  console.log(`Pipelines (${body.pipelines.length}):`);
  for (const pipeline of body.pipelines) {
    console.log(`- ${pipeline.name}: ${pipeline.description || "(no description)"}`);
  }
}
// --8<-- [end:pipelines]

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
    await checkLive();
    const healthy = await checkHealth();
    await listPipelines();

    // A degraded server still answers with HTTP 200, so report it with the
    // exit status.
    if (!healthy) {
      console.error("RAG Server is not healthy");
      return 1;
    }
    return 0;
  } catch (err) {
    console.error(`RAG Server error: ${describe(err)}`);
    return 1;
  }
}

process.exitCode = await main();
// --8<-- [end:main]
