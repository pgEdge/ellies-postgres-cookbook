/*
 * Ellie's Postgres Cookbook
 * Asking the pgEdge RAG Server a question, using the built-in fetch.
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
interface QueryResponse {
  answer: string;
  tokens_used: number;
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

// Sends the question to the pipeline, and returns the answer with the
// number of tokens the request used.
async function ask(question: string): Promise<QueryResponse> {
  // encodeURIComponent escapes any character in the pipeline name that is
  // not safe in a URL path.
  const response = await fetch(
    `${baseUrl}/v1/pipelines/${encodeURIComponent(pipeline)}`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ query: question }),
      signal: AbortSignal.timeout(timeoutMs),
    },
  );

  // fetch only rejects when it cannot reach the server; an error status
  // is a normal response, so check it explicitly.
  if (!response.ok) {
    throw new Error(`HTTP ${response.status}, ${await errorText(response)}`);
  }

  const body = (await response.json()) as Partial<QueryResponse>;
  if (typeof body.answer !== "string" || typeof body.tokens_used !== "number") {
    throw new Error(`Unexpected response: ${JSON.stringify(body).slice(0, 200)}`);
  }
  return { answer: body.answer, tokens_used: body.tokens_used };
}
// --8<-- [end:ask]

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
    const { answer, tokens_used } = await ask(question);
    console.log(`Question: ${question}`);
    console.log(`Answer:\n${answer}`);
    console.log(`Tokens used: ${tokens_used}`);
    return 0;
  } catch (err) {
    console.error(`RAG Server error: ${describe(err)}`);
    return 1;
  }
}

process.exitCode = await main();
// --8<-- [end:main]
