/*
 * Ellie's Postgres Cookbook
 * Exploring a schema through the pgEdge Postgres MCP Server, using the
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

const timeoutMs = 30_000;

// The schema and table that scripts/start_postgres_mcp.sh creates.
const schema = "cookbook_mcp";
const table = "products";

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

// --8<-- [start:parse_tsv]
// Reads the table in a tool's reply into a list of rows, each an object
// keyed by column name. The reply starts with a line or two about the
// database, and then has a header line and one line for each row, with
// the values separated by tabs. The server writes a tab or a newline
// inside a value as \t or \n, so splitting on them is safe. The header is
// the first line that starts with "schema", the first column of every
// table that get_schema_info returns.
function parseTsv(text: string): Record<string, string>[] {
  const lines = text.split("\n");
  const start = lines.findIndex((line) => line.startsWith("schema\t"));
  if (start < 0) {
    throw new Error(`The reply had no table: ${text.slice(0, 200)}`);
  }
  const header = lines[start].split("\t");
  return lines
    .slice(start + 1)
    .filter((line) => line !== "")
    .map((line) => {
      const values = line.split("\t");
      return Object.fromEntries(header.map((name, i) => [name, values[i] ?? ""]));
    });
}
// --8<-- [end:parse_tsv]

// --8<-- [start:list_tables]
// Lists the tables in the schema with their comments. With compact set to
// true, get_schema_info returns one line for each table, without its
// columns, which suits a first look at a large database.
async function listTables(): Promise<void> {
  const text = await callTool("get_schema_info", { schema_name: schema, compact: true });
  console.log(`Tables in ${schema}:`);
  for (const row of parseTsv(text)) {
    console.log(`- ${row.table}: ${row.table_desc || "(no comment)"}`);
  }
}
// --8<-- [end:list_tables]

// --8<-- [start:describe_table]
// Lists the columns of one table with their types. Given a table_name,
// get_schema_info returns one line for each column, which also carries
// the table's details.
async function describeTable(): Promise<void> {
  const text = await callTool("get_schema_info", { schema_name: schema, table_name: table });
  const rows = parseTsv(text);
  if (rows.length === 0) {
    throw new Error(`${schema}.${table} has no columns`);
  }
  console.log(`Columns of ${schema}.${table}:`);
  for (const row of rows) {
    const key = row.is_pk === "true" ? " (primary key)" : "";
    console.log(`- ${row.column}: ${row.data_type}${key}`);
  }
}
// --8<-- [end:describe_table]

// --8<-- [start:count_rows]
// Counts the products in stock with count_rows. The where argument is a
// condition without the WHERE keyword; the server rejects one that
// contains a subquery.
async function countInStock(): Promise<void> {
  const text = await callTool("count_rows", { schema, table, where: "in_stock" });
  // The reply ends with a line such as "Count: 4".
  const match = text.match(/^Count: (\d+)$/m);
  if (!match) {
    throw new Error(`The reply had no count: ${text.slice(0, 200)}`);
  }
  console.log(`Products in stock: ${match[1]}`);
}
// --8<-- [end:count_rows]

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
    await listTables();
    await describeTable();
    await countInStock();
    return 0;
  } catch (err) {
    console.error(`MCP Server error: ${describe(err)}`);
    return 1;
  }
}

process.exitCode = await main();
// --8<-- [end:main]
