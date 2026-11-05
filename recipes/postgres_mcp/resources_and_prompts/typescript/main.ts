/*
 * Ellie's Postgres Cookbook
 * Reading resources and prompts from the pgEdge Postgres MCP Server,
 * using the built-in fetch.
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

// Sends a JSON-RPC request and returns its result. The server answers a
// JSON-RPC error with HTTP status 200, so the function checks the reply
// for an error member as well as the HTTP status.
async function rpc(method: string, params: object): Promise<any> {
  const response = await fetch(`${baseUrl}/mcp/v1`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ jsonrpc: "2.0", id: 1, method, params }),
    signal: AbortSignal.timeout(timeoutMs),
  });
  const text = await response.text();
  if (response.status !== 200) {
    throw new Error(`${method} failed with HTTP ${response.status}: ${text.slice(0, 200)}`);
  }
  let reply: any;
  try {
    reply = JSON.parse(text);
  } catch {
    reply = undefined;
  }
  if (typeof reply !== "object" || reply === null || !("result" in reply || "error" in reply)) {
    throw new Error(`${method} failed: unexpected response: ${text.slice(0, 200)}`);
  }
  if ("error" in reply) {
    throw new Error(`${method} failed: ${reply.error?.message}`);
  }
  return reply.result;
}
// --8<-- [end:config]

// --8<-- [start:resources]
// Lists the resources that the server offers, and then reads
// pg://system_info, which describes the PostgreSQL server. The contents of
// a resource are text, which for this one holds a JSON object, so the
// function parses the text a second time. version_number is a string such
// as "180006", from which integer division by 10000 gives the major
// version.
async function readSystemInfo(): Promise<void> {
  const list = await rpc("resources/list", {});
  console.log(`Resources: ${list.resources.map((r: any) => r.uri).join(", ")}`);

  const result = await rpc("resources/read", { uri: "pg://system_info" });
  const info = JSON.parse(result.contents[0].text);
  const versionNumber = Number(info.version_number);
  if (!Number.isInteger(versionNumber) || typeof info.allow_writes !== "boolean") {
    throw new Error(`Unexpected result: ${JSON.stringify(result).slice(0, 200)}`);
  }
  console.log(`PostgreSQL major version: ${Math.floor(versionNumber / 10000)}`);
  console.log(`Writes allowed: ${info.allow_writes}`);
}
// --8<-- [end:resources]

// --8<-- [start:prompts]
// Lists the prompts that the server offers, and then fetches
// explore-database, which takes no arguments. A prompt is a set of
// messages, ready to hand to a language model, that guide it through a
// task with the server's tools.
async function readPrompts(): Promise<void> {
  const list = await rpc("prompts/list", {});
  console.log(`Prompts: ${list.prompts.map((p: any) => p.name).join(", ")}`);

  const result = await rpc("prompts/get", { name: "explore-database", arguments: {} });
  console.log(`explore-database: ${result.description}`);
  console.log(`First message role: ${result.messages[0].role}`);
}
// --8<-- [end:prompts]

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
    await readSystemInfo();
    await readPrompts();
    return 0;
  } catch (err) {
    console.error(`MCP Server error: ${describe(err)}`);
    return 1;
  }
}

process.exitCode = await main();
// --8<-- [end:main]
