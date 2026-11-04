/*
 * Ellie's Postgres Cookbook
 * Handling errors from the pgEdge RAG Server by error code, using the
 * built-in fetch.
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
const pipeline = process.env.RAG_PIPELINE || "cookbook";

// A pipeline name that no server has, to cause PIPELINE_NOT_FOUND.
const missingPipeline = "no-such-pipeline";

// The server rejects both requests before it calls a language model, so
// they answer quickly.
const timeoutMs = 30_000;
// --8<-- [end:config]

// --8<-- [start:request]
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

// Sends a query to a pipeline, and returns the decoded reply. Throws an
// ApiError when the server replies with an error.
async function sendQuery(name: string, query: string): Promise<unknown> {
  const response = await fetch(
    `${baseUrl}/v1/pipelines/${encodeURIComponent(name)}`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ query }),
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
  return response.json();
}
// --8<-- [end:request]

// --8<-- [start:advise]
// Returns advice for an error, chosen by the error code. Branch on the
// code rather than on the message, which is meant for people and may
// change; branch on the HTTP status only for the temporary failures that
// have no code worth handling individually.
function advise(err: ApiError): string {
  switch (err.code) {
    case "PIPELINE_NOT_FOUND":
      return "Check the pipeline name; GET /v1/pipelines lists the pipelines.";
    case "INVALID_REQUEST":
      return "Fix the request; the body must be JSON with a non-empty query.";
    default:
      if (err.status === 503 || err.status === 504) {
        return "The failure may be temporary, so retry the request later.";
      }
      return `This program does not handle ${err.code}.`;
  }
}
// --8<-- [end:advise]

// --8<-- [start:main]
// Sends one query that the server must refuse with the expected error
// code, and prints how the program handles the refusal. Any other outcome
// is a failure.
async function demonstrate(
  title: string,
  name: string,
  query: string,
  expected: string,
): Promise<void> {
  console.log(title);
  try {
    await sendQuery(name, query);
  } catch (err) {
    if (!(err instanceof ApiError)) {
      throw err;
    }
    console.log(`  ${err.code} (HTTP ${err.status}): ${err.message}`);
    console.log(`  ${advise(err)}`);
    if (err.code !== expected) {
      throw new Error(`expected ${expected}, got ${err.code}`);
    }
    return;
  }
  throw new Error("the request unexpectedly succeeded");
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
    await demonstrate(
      "Asking a pipeline that does not exist",
      missingPipeline,
      "Hello",
      "PIPELINE_NOT_FOUND",
    );
    await demonstrate("Asking an empty question", pipeline, "", "INVALID_REQUEST");
    return 0;
  } catch (err) {
    console.error(`RAG Server error: ${describe(err)}`);
    return 1;
  }
}

process.exitCode = await main();
// --8<-- [end:main]
