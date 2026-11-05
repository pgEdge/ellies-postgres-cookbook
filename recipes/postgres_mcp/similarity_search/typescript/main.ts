/*
 * Ellie's Postgres Cookbook
 * Searching by meaning through the pgEdge Postgres MCP Server, using the
 * built-in fetch.
 *
 * These examples are for pgEdge Postgres MCP Server 1.1.0.
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
const baseUrl = (process.env.MCP_URL || "http://localhost:8080").replace(/\/+$/, "");
const token = process.env.MCP_TOKEN || "";

// The server turns the query into an embedding before it searches, which
// can take a while if the embedding model has to load first, so the
// timeout is longer than in the other recipes.
const timeoutMs = 90_000;

const query = "a gift for an amateur astronomer";

// Calls a tool with tools/call and returns the text of its reply. The
// server answers a JSON-RPC error with HTTP status 200, and a tool that
// fails returns a normal result with isError set, so the function checks
// for both as well as the HTTP status.
async function callTool(name: string, args: object): Promise<string> {
  const response = await fetch(`${baseUrl}/mcp/v1`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      jsonrpc: "2.0",
      id: 1,
      method: "tools/call",
      params: { name, arguments: args },
    }),
    signal: AbortSignal.timeout(timeoutMs),
  });
  const text = await response.text();
  if (response.status !== 200) {
    throw new Error(`${name} failed with HTTP ${response.status}: ${text.slice(0, 200)}`);
  }
  let reply: any;
  try {
    reply = JSON.parse(text);
  } catch {
    reply = undefined;
  }
  if (typeof reply !== "object" || reply === null || !("result" in reply || "error" in reply)) {
    throw new Error(`${name} failed: unexpected response: ${text.slice(0, 200)}`);
  }
  if ("error" in reply) {
    throw new Error(`${name} failed: ${reply.error?.message}`);
  }
  const content = reply.result?.content?.[0]?.text;
  if (typeof content !== "string") {
    throw new Error(`${name} failed: unexpected result: ${text.slice(0, 200)}`);
  }
  if (reply.result.isError) {
    throw new Error(`${name} failed: ${content}`);
  }
  return content;
}
// --8<-- [end:config]

// --8<-- [start:search]
// Searches the product descriptions for the query, and prints the number
// of results and the name of the product that matches it most closely.
// similarity_search finds the closest rows by vector distance, and then
// reorders them, mixing in a keyword score and favouring variety, so the
// first result in the reply is not always the closest. Each result has a
// line such as "Source: cookbook_mcp.products.description (vector search
// rank: #1, chunk: 1)"; the function picks the result ranked first by the
// vector search, whose text follows the first blank line after it. Every
// description starts with the product's name and a colon.
async function search(): Promise<void> {
  const text = await callTool("similarity_search", {
    table_name: "cookbook_mcp.products",
    query_text: query,
    top_n: 3,
  });
  console.log(`Query: ${query}`);
  const lines = text.split("\n");
  const count = lines.filter((line) => /^Result \d+\/\d+$/.test(line)).length;
  console.log(`Results: ${count}`);

  const source = lines.findIndex(
    (line) =>
      line.startsWith("Source: ") && line.endsWith("(vector search rank: #1, chunk: 1)"),
  );
  const blank = source < 0 ? -1 : lines.findIndex((line, i) => i > source && line === "");
  const best = blank < 0 ? undefined : lines[blank + 1];
  if (best === undefined || !best.includes(": ")) {
    throw new Error(`The reply had no closest match: ${text.slice(0, 200)}`);
  }
  console.log(`Best match: ${best.split(": ")[0]}`);
}
// --8<-- [end:search]

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
  if (!token) {
    console.error("MCP_TOKEN must be set");
    return 1;
  }
  try {
    await search();
    return 0;
  } catch (err) {
    console.error(`MCP Server error: ${describe(err)}`);
    return 1;
  }
}

process.exitCode = await main();
// --8<-- [end:main]
