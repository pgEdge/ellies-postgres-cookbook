/*
 * Ellie's Postgres Cookbook
 * Calling AI DBA Workbench MCP tools, using the built-in fetch.
 *
 * Copyright (c) 2026, pgEdge, Inc.
 * This code is released under the PostgreSQL License.
 */

// --8<-- [start:imports]
// The program needs no imports: fetch and process are built in to Node.js.
// --8<-- [end:imports]

// --8<-- [start:config]
interface Settings {
  baseUrl: string;
  token: string;
  connectionId: number;
}

// Read the settings from the environment. The || operator, unlike ??, also
// treats an empty variable as unset.
function settings(): Settings {
  const token = process.env.WORKBENCH_TOKEN || "";
  const connectionId = process.env.WORKBENCH_CONNECTION_ID || "";
  if (!token || !connectionId) {
    throw new Error("WORKBENCH_TOKEN and WORKBENCH_CONNECTION_ID must be set");
  }
  if (!/^\d+$/.test(connectionId)) {
    throw new Error("WORKBENCH_CONNECTION_ID must be a number");
  }
  const baseUrl = process.env.WORKBENCH_URL || "http://localhost:8080";
  return {
    baseUrl: baseUrl.replace(/\/+$/, ""),
    token,
    connectionId: Number(connectionId),
  };
}
// --8<-- [end:config]

// --8<-- [start:rpc]
// Sends a JSON-RPC request to the MCP endpoint and returns the result. The
// server answers a JSON-RPC error with HTTP status 200, so the function
// checks the reply for an error member as well as for an HTTP failure.
async function rpc<T>(
  s: Settings,
  method: string,
  params: unknown,
): Promise<T> {
  const response = await fetch(`${s.baseUrl}/mcp/v1`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${s.token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ jsonrpc: "2.0", id: 1, method, params }),
    signal: AbortSignal.timeout(30_000),
  });
  if (!response.ok) {
    const text = (await response.text()).trim();
    throw new Error(`${method} failed with status ${response.status}: ${text}`);
  }
  const reply = (await response.json()) as {
    result?: T;
    error?: { message: string };
  };
  if (reply.error) throw new Error(`${method} failed: ${reply.error.message}`);
  return reply.result as T;
}
// --8<-- [end:rpc]

// --8<-- [start:initialize]
// Introduces the client to the server and prints the server's name and
// version. The Workbench keeps no session, so a client can skip this step.
async function initialize(s: Settings): Promise<void> {
  const result = await rpc<{ serverInfo: { name: string; version: string } }>(
    s,
    "initialize",
    {
      protocolVersion: "2024-11-05",
      capabilities: {},
      clientInfo: { name: "cookbook", version: "1.0.0" },
    },
  );
  console.log(`Server: ${result.serverInfo.name} ${result.serverInfo.version}`);
}
// --8<-- [end:initialize]

// --8<-- [start:list_tools]
interface Tool {
  name: string;
  inputSchema: { required: string[] };
}

// Lists the tools, checks that the two that the program calls are present,
// and prints the arguments that each one requires.
async function listTools(s: Settings): Promise<void> {
  const result = await rpc<{ tools: Tool[] }>(s, "tools/list", {});
  // The server lists its tools in no fixed order, so look the two tools up
  // by name.
  for (const name of ["query_database", "execute_explain"]) {
    const tool = result.tools.find((t) => t.name === name);
    if (!tool) throw new Error(`The server does not offer ${name}`);
    console.log(`${name} requires: ${tool.inputSchema.required.join(", ")}`);
  }
}
// --8<-- [end:list_tools]

// --8<-- [start:call_tool]
// Calls a tool and returns the text of its reply. A tool that fails returns a
// normal result with isError set, so the function checks that flag too.
async function callTool(
  s: Settings,
  name: string,
  args: Record<string, unknown>,
): Promise<string> {
  const result = await rpc<{
    content: { text: string }[];
    isError?: boolean;
  }>(s, "tools/call", { name, arguments: args });
  const text = result.content[0].text;
  if (result.isError) throw new Error(`${name} failed: ${text}`);
  return text;
}
// --8<-- [end:call_tool]

// --8<-- [start:query_database]
// Runs a harmless read-only query with query_database and prints the column
// names and the rows. The reply is text that starts with the connection and
// the query, and then has a "Results" line followed by the rows in
// tab-separated form, so the function prints only what follows that line.
async function queryDatabase(s: Settings): Promise<void> {
  const text = await callTool(s, "query_database", {
    connection_id: s.connectionId,
    query: "SELECT 'Hello from the Workbench' AS greeting, 6 * 7 AS answer",
  });
  const start = text.indexOf("\nResults");
  if (start < 0) throw new Error("The reply had no results");
  // Skip the rest of the Results line, then turn the tabs into commas.
  const lines = text
    .slice(start + 1)
    .split("\n")
    .slice(1)
    .filter((line) => line !== "");
  lines.forEach((line, number) => {
    const label = number === 0 ? "Columns" : "Row";
    console.log(`${label}: ${line.split("\t").join(", ")}`);
  });
}
// --8<-- [end:query_database]

// --8<-- [start:execute_explain]
// Plans a query with execute_explain, without running it, and prints the type
// of the first node of the plan. Setting analyze to true would run the query.
async function executeExplain(s: Settings): Promise<void> {
  const text = await callTool(s, "execute_explain", {
    connection_id: s.connectionId,
    query: "SELECT 1 + 1",
    analyze: false,
  });
  // The plan follows a line of equals signs.
  const match = /Execution Plan:\n=+\n(\S+)/.exec(text);
  if (!match) throw new Error("The reply had no execution plan");
  console.log(`Plan starts with: ${match[1]}`);
}
// --8<-- [end:execute_explain]

// --8<-- [start:main]
async function main(): Promise<number> {
  try {
    const s = settings();
    await initialize(s);
    await listTools(s);
    await queryDatabase(s);
    await executeExplain(s);
  } catch (err) {
    console.error(`Error: ${err instanceof Error ? err.message : err}`);
    return 1;
  }
  return 0;
}

process.exitCode = await main();
// --8<-- [end:main]
