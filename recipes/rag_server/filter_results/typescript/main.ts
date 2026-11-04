/*
 * Ellie's Postgres Cookbook
 * Filtering the documents that the pgEdge RAG Server retrieves, using the
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

const question = "How long does the Acme Widget take to charge?";

// The product to search, and the versions to ask about in turn. The
// question names no version, so only the filter tells the pipeline which
// documents to use.
const product = "Acme Widget";
const versions = ["1.0", "2.0"];

// The server waits for the language model before it replies, and a small
// model on a modest machine can take a while, so allow plenty of time.
const timeoutMs = 300_000;
// --8<-- [end:config]

// --8<-- [start:filter]
interface Condition {
  column: string;
  operator: string;
  value: string;
}

interface Filter {
  logic: "AND" | "OR";
  conditions: Condition[];
}

// Returns the filter for a product and a version. The conditions are
// joined with AND, which is the default, and each one compares a column of
// the pipeline's table with a value. The server passes the values to
// PostgreSQL as parameters, so they need no escaping.
function buildFilter(product: string, version: string): Filter {
  return {
    logic: "AND",
    conditions: [
      { column: "product", operator: "=", value: product },
      { column: "version", operator: "=", value: version },
    ],
  };
}
// --8<-- [end:filter]

// --8<-- [start:ask]
interface Source {
  id?: string;
  content?: string;
  score?: number;
}

interface QueryResponse {
  answer: string;
  sources?: Source[];
}

// Describes an error response, which carries a JSON body of the form
// {"error": {"code": "...", "message": "..."}}.
async function errorText(response: Response): Promise<string> {
  const text = await response.text();
  try {
    const { error } = JSON.parse(text);
    return `${error.code}: ${error.message}`;
  } catch {
    return text.slice(0, 200) || response.statusText;
  }
}

// Sends the question and the filter to the pipeline, and asks for the
// documents that the answer came from. Returns the decoded reply.
async function ask(question: string, filter: Filter): Promise<QueryResponse> {
  const response = await fetch(
    `${baseUrl}/v1/pipelines/${encodeURIComponent(pipeline)}`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ query: question, filter, include_sources: true }),
      signal: AbortSignal.timeout(timeoutMs),
    },
  );

  // fetch only rejects when it cannot reach the server; an error status
  // is a normal response, so check it explicitly.
  if (!response.ok) {
    throw new Error(`HTTP ${response.status}, ${await errorText(response)}`);
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
    for (const version of versions) {
      const body = await ask(question, buildFilter(product, version));
      console.log();
      console.log(`Filter: product = ${product}, version = ${version}`);
      show(body);
    }
    return 0;
  } catch (err) {
    console.error(`RAG Server error: ${describe(err)}`);
    return 1;
  }
}

process.exitCode = await main();
// --8<-- [end:main]
