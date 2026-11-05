/*
 * Ellie's Postgres Cookbook
 * Connecting to the pgEdge Postgres MCP Server, using the built-in fetch.
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

// Posts a JSON-RPC message to the MCP endpoint with a token.
async function post(withToken: string, message: object): Promise<Response> {
  return fetch(`${baseUrl}/mcp/v1`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${withToken}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(message),
    signal: AbortSignal.timeout(timeoutMs),
  });
}

// Sends a JSON-RPC request and returns its result. The server answers a
// JSON-RPC error with HTTP status 200, so the function checks the reply
// for an error member as well as the HTTP status.
async function rpc(method: string, params: object): Promise<any> {
  const response = await post(token, { jsonrpc: "2.0", id: 1, method, params });
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

// --8<-- [start:health]
// Checks that the server is running. The /health endpoint needs no token.
async function checkHealth(): Promise<void> {
  const response = await fetch(`${baseUrl}/health`, {
    signal: AbortSignal.timeout(timeoutMs),
  });
  const text = await response.text();
  if (response.status !== 200) {
    throw new Error(`Health check failed with HTTP ${response.status}: ${text.slice(0, 200)}`);
  }
  let status: unknown;
  try {
    status = JSON.parse(text)?.status;
  } catch {
    status = undefined;
  }
  if (status !== "ok") {
    throw new Error(`Unexpected response: ${text.slice(0, 200)}`);
  }
  console.log("Health: ok");
}
// --8<-- [end:health]

// --8<-- [start:initialize]
// Introduces the client to the server, and prints the server's name and
// version and the protocol revision that the server chose. The server
// accepts 2024-11-05, 2025-03-26, 2025-06-18 and 2025-11-25, and answers a
// revision it does not know with one that it does, so the client checks
// the answer. The notifications/initialized message then completes the
// handshake; it is a notification, with no id, so the server replies with
// HTTP 202 and no body.
async function initialize(): Promise<void> {
  const result = await rpc("initialize", {
    protocolVersion: "2025-06-18",
    capabilities: {},
    clientInfo: { name: "cookbook", version: "1.0.0" },
  });
  const info = result?.serverInfo;
  if (typeof info?.name !== "string" || typeof info?.version !== "string") {
    throw new Error(`Unexpected result: ${JSON.stringify(result)}`);
  }
  console.log(`Server: ${info.name} ${info.version}`);
  const protocol = result.protocolVersion;
  if (protocol !== "2025-06-18") {
    throw new Error(`The server chose protocol version ${protocol}`);
  }
  console.log(`Protocol version: ${protocol}`);

  const response = await post(token, {
    jsonrpc: "2.0",
    method: "notifications/initialized",
  });
  const text = await response.text();
  if (response.status !== 202) {
    throw new Error(
      `notifications/initialized failed with HTTP ${response.status}: ${text.slice(0, 200)}`,
    );
  }
}
// --8<-- [end:initialize]

// --8<-- [start:wrong_token]
// Sends a request with a token that the server does not know, and prints
// the HTTP status and the server's message, which is a JSON object with an
// error member rather than a JSON-RPC reply.
async function wrongToken(): Promise<void> {
  const response = await post("not-a-real-token", {
    jsonrpc: "2.0",
    id: 1,
    method: "tools/list",
    params: {},
  });
  const text = await response.text();
  if (response.status !== 401) {
    throw new Error(`Expected HTTP 401 for a wrong token, but got ${response.status}`);
  }
  let message = "no message";
  try {
    message = JSON.parse(text)?.error || message;
  } catch {
    // The body is not JSON; keep the default message.
  }
  console.log(`Wrong token: HTTP ${response.status}, ${message}`);
}
// --8<-- [end:wrong_token]

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
    await checkHealth();
    await initialize();
    await wrongToken();
    return 0;
  } catch (err) {
    console.error(`MCP Server error: ${describe(err)}`);
    return 1;
  }
}

process.exitCode = await main();
// --8<-- [end:main]
