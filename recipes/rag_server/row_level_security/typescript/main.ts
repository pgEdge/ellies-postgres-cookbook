/*
 * Ellie's Postgres Cookbook
 * Limiting the answers of the pgEdge RAG Server to each caller's own rows,
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
const pipeline = process.env.RAG_PIPELINE || "cookbook_private";

const question = "What is the status of my warranty claim?";

// The callers to ask for. The fictional documents in the pipeline's table
// belong to these two people.
const callers = ["jane.doe@example.com", "john.smith@example.com"];

// The header in which the server expects a trusted proxy to put the claims
// of the caller. This is the server's default; the identity.claims_header
// setting changes it.
const claimsHeader = "X-Forwarded-Claims";

// The server waits for the language model before it replies, and a small
// model on a modest machine can take a while, so allow plenty of time.
const timeoutMs = 300_000;
// --8<-- [end:config]

// --8<-- [start:ask]
interface Source {
  id?: string;
}

interface QueryResponse {
  answer: string;
  sources?: Source[];
}

// ApiError is thrown when the RAG Server replies with an error. The reply
// has an HTTP status and a JSON body of the form
// {"error": {"code": "...", "message": "..."}}.
class ApiError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message: string,
  ) {
    super(message);
  }
}

// Sends the question to the pipeline on behalf of a caller, and asks for
// the documents that the answer came from. Returns the decoded reply. A
// subject of undefined sends no identity at all.
async function ask(subject?: string): Promise<QueryResponse> {
  // The claims are a JSON object, which JSON.stringify builds, so that the
  // subject needs no escaping.
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (subject !== undefined) {
    headers[claimsHeader] = JSON.stringify({ sub: subject });
  }

  const response = await fetch(
    `${baseUrl}/v1/pipelines/${encodeURIComponent(pipeline)}`,
    {
      method: "POST",
      headers,
      body: JSON.stringify({ query: question, include_sources: true }),
      signal: AbortSignal.timeout(timeoutMs),
    },
  );

  // fetch only rejects when it cannot reach the server; an error status
  // is a normal response, so check it explicitly.
  if (!response.ok) {
    const text = await response.text();
    let error: { code?: unknown; message?: unknown } | undefined;
    try {
      error = JSON.parse(text).error;
    } catch {
      // Fall through to the generic error below.
    }
    if (typeof error?.code === "string" && typeof error.message === "string") {
      throw new ApiError(response.status, error.code, error.message);
    }
    throw new Error(`HTTP ${response.status}, ${text.slice(0, 200)}`);
  }

  const body = (await response.json()) as Partial<QueryResponse>;
  if (typeof body.answer !== "string") {
    throw new Error(`Unexpected response: ${JSON.stringify(body).slice(0, 200)}`);
  }
  return body as QueryResponse;
}
// --8<-- [end:ask]

// --8<-- [start:show]
// Prints the answer in a reply, and then the IDs of its sources.
function show(body: QueryResponse): void {
  const ids = (body.sources ?? []).map((source) => source.id ?? "(no id)");
  console.log(`Answer:\n${body.answer}`);
  console.log(`Sources: ${ids.join(", ")}`);
}
// --8<-- [end:show]

// --8<-- [start:main]
// Asks the question without an identity. The server must refuse with
// IDENTITY_REQUIRED, because it never falls back to the pipeline's own
// database role; any other outcome is a failure.
async function askAnonymously(): Promise<void> {
  console.log();
  console.log("Caller: (no identity)");
  try {
    await ask();
  } catch (err) {
    if (!(err instanceof ApiError)) {
      throw err;
    }
    console.log(`${err.code} (HTTP ${err.status})`);
    if (err.code !== "IDENTITY_REQUIRED") {
      throw new Error(`expected IDENTITY_REQUIRED, got ${err.code}: ${err.message}`);
    }
    return;
  }
  throw new Error("the server answered without an identity; is identity.enabled set?");
}

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
    console.log(`Question: ${question}`);
    for (const caller of callers) {
      const body = await ask(caller);
      console.log();
      console.log(`Caller: ${caller}`);
      show(body);
    }
    await askAnonymously();
    return 0;
  } catch (err) {
    console.error(`RAG Server error: ${describe(err)}`);
    return 1;
  }
}

process.exitCode = await main();
// --8<-- [end:main]
