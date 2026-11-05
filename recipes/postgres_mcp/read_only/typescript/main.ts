/*
 * Ellie's Postgres Cookbook
 * Running read-only queries through the pgEdge Postgres MCP Server, using
 * the built-in fetch.
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

const timeoutMs = 30_000;

// Calls a tool with tools/call and returns the text of its reply and
// whether the tool failed, which it reports by setting isError. The server
// answers a JSON-RPC error with HTTP status 200, so the function checks the
// reply for an error member as well as the HTTP status.
async function callTool(
  name: string,
  args: object,
): Promise<{ text: string; failed: boolean }> {
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
  const body = await response.text();
  if (response.status !== 200) {
    throw new Error(`${name} failed with HTTP ${response.status}: ${body.slice(0, 200)}`);
  }
  let reply: any;
  try {
    reply = JSON.parse(body);
  } catch {
    reply = undefined;
  }
  if (typeof reply !== "object" || reply === null || !("result" in reply || "error" in reply)) {
    throw new Error(`${name} failed: unexpected response: ${body.slice(0, 200)}`);
  }
  if ("error" in reply) {
    throw new Error(`${name} failed: ${reply.error?.message}`);
  }
  const text = reply.result?.content?.[0]?.text;
  if (typeof text !== "string") {
    throw new Error(`${name} failed: unexpected result: ${body.slice(0, 200)}`);
  }
  return { text, failed: reply.result.isError === true };
}
// --8<-- [end:config]

// --8<-- [start:select]
// Runs a SELECT with query_database, and prints the column names and each
// row. The reply repeats the query, with the LIMIT that the server adds,
// and then has a line such as "Results (3 rows):", a header line, and one
// line for each row, with the values separated by tabs. The server writes
// a tab or a newline inside a value as \t or \n, and a NULL as an empty
// string.
async function selectCheapProducts(): Promise<void> {
  const { text, failed } = await callTool("query_database", {
    query: "SELECT name, price FROM cookbook_mcp.products WHERE price < 100 ORDER BY price",
  });
  if (failed) {
    throw new Error(`query_database failed: ${text}`);
  }
  const lines = text.split("\n");
  const start = lines.findIndex((line) => line.startsWith("Results "));
  if (start < 0 || start + 1 >= lines.length) {
    throw new Error(`Unexpected reply: ${text.slice(0, 200)}`);
  }
  console.log(`Columns: ${lines[start + 1].split("\t").join(", ")}`);
  for (const line of lines.slice(start + 2)) {
    if (line !== "") {
      console.log(`Row: ${line.split("\t").join(", ")}`);
    }
  }
}
// --8<-- [end:select]

// --8<-- [start:insert]
// Tries to add a row. query_database runs every query in a read-only
// transaction, so PostgreSQL itself refuses the INSERT, and the tool
// returns the error with isError set to true. The function throws an error
// if the server accepts the write.
async function tryInsert(): Promise<void> {
  const { text, failed } = await callTool("query_database", {
    query:
      "INSERT INTO cookbook_mcp.products " +
      "(name, category, price, in_stock, description) " +
      "VALUES ('Acme Test Widget', 'Testing', 1.00, true, " +
      "'A made-up product that is never saved')",
  });
  if (!failed) {
    throw new Error("The server accepted a write");
  }
  console.log(`INSERT rejected: ${text}`);
}
// --8<-- [end:insert]

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
    await selectCheapProducts();
    await tryInsert();
    return 0;
  } catch (err) {
    console.error(`MCP Server error: ${describe(err)}`);
    return 1;
  }
}

process.exitCode = await main();
// --8<-- [end:main]
