/*
 * Ellie's Postgres Cookbook
 * Showing the sources of an answer from the pgEdge RAG Server, using the
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

const question = "How long does the Acme Widget 2.0 take to charge?";

// The server waits for the language model before it replies, and a small
// model on a modest machine can take a while, so allow plenty of time.
const timeoutMs = 300_000;
// --8<-- [end:config]

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

// Sends the question to the pipeline, and asks for the documents that the
// answer came from. Returns the decoded reply.
async function ask(question: string): Promise<QueryResponse> {
  const response = await fetch(
    `${baseUrl}/v1/pipelines/${encodeURIComponent(pipeline)}`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ query: question, include_sources: true }),
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

// --8<-- [start:sources]
// Returns one line for a source: its ID and the start of its text.
function describeSource(source: Source): string {
  // Collapse any line breaks, and shorten long text for display.
  let content = (source.content ?? "").split(/\s+/).filter(Boolean).join(" ");
  if (content.length > 60) {
    content = content.slice(0, 57) + "...";
  }
  return `- ${source.id ?? "(no id)"}: ${content}`;
}

// Prints the sources in a reply, in the order that the server returns them.
function printSources(body: QueryResponse): void {
  // The server leaves out the sources array, without an error, when the
  // pipeline does not set allow_include_sources.
  const sources = body.sources ?? [];
  if (sources.length === 0) {
    console.log("No sources were returned. Does the pipeline set allow_include_sources?");
    return;
  }

  console.log(`Sources (${sources.length}):`);
  for (const source of sources) {
    console.log(describeSource(source));
  }
}
// --8<-- [end:sources]

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
    const body = await ask(question);
    console.log(`Question: ${question}`);
    console.log(`Answer:\n${body.answer}`);
    printSources(body);
    return 0;
  } catch (err) {
    console.error(`RAG Server error: ${describe(err)}`);
    return 1;
  }
}

process.exitCode = await main();
// --8<-- [end:main]
