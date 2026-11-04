/*
 * Ellie's Postgres Cookbook
 * Holding a conversation with the pgEdge RAG Server, using the built-in
 * fetch.
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

// The second question does not say which version of the Acme Widget it
// means, so only the first question and its answer, which the model
// receives as history, settle that. The search uses only the current
// question, which is why this one still names the product.
const questions = [
  "How long does the Acme Widget 2.0 take to charge?",
  "And how many hours does the Acme Widget run for once it is charged?",
];

// The server waits for the language model before it replies, and a small
// model on a modest machine can take a while, so allow plenty of time.
const timeoutMs = 300_000;
// --8<-- [end:config]

// --8<-- [start:ask]
interface Message {
  role: "user" | "assistant";
  content: string;
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

// Sends a question and the conversation so far to the pipeline, and
// returns the answer. The server keeps no conversation between requests,
// so history lists the earlier messages, each with a role of user or
// assistant, in order.
async function ask(question: string, history: Message[]): Promise<string> {
  const response = await fetch(
    `${baseUrl}/v1/pipelines/${encodeURIComponent(pipeline)}`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ query: question, messages: history }),
      signal: AbortSignal.timeout(timeoutMs),
    },
  );

  // fetch only rejects when it cannot reach the server; an error status
  // is a normal response, so check it explicitly.
  if (!response.ok) {
    throw new Error(`HTTP ${response.status}, ${await errorText(response)}`);
  }

  const body = (await response.json()) as { answer?: unknown };
  if (typeof body.answer !== "string") {
    throw new Error(`Unexpected response: ${JSON.stringify(body).slice(0, 200)}`);
  }
  return body.answer;
}
// --8<-- [end:ask]

// --8<-- [start:converse]
// Asks each question in turn, printing both sides of the conversation.
// After each answer, the question and the answer join the history that the
// next request carries.
async function converse(): Promise<void> {
  const history: Message[] = [];
  for (const question of questions) {
    const answer = await ask(question, history);
    console.log(`You: ${question}`);
    console.log(`Assistant: ${answer}`);
    history.push(
      { role: "user", content: question },
      { role: "assistant", content: answer },
    );
  }
}
// --8<-- [end:converse]

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
    await converse();
    return 0;
  } catch (err) {
    console.error(`RAG Server error: ${describe(err)}`);
    return 1;
  }
}

process.exitCode = await main();
// --8<-- [end:main]
