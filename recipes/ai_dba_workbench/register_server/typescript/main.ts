/*
 * Ellie's Postgres Cookbook
 * Registering a server to monitor with the AI DBA Workbench API, using the
 * built-in fetch.
 *
 * Copyright (c) 2026, pgEdge, Inc.
 * This code is released under the PostgreSQL License.
 */

// --8<-- [start:imports]
// The program needs no imports: fetch and process are built in to Node.js.
// --8<-- [end:imports]

// --8<-- [start:config]
const SERVER_NAME = "cookbook-register-server";

interface Settings {
  baseUrl: string;
  username: string;
  password: string;
  connectionId: string;
  serverPassword: string;
}

// Read the settings from the environment. The || operator, unlike ??, also
// treats an empty variable as unset.
function settings(): Settings {
  const username = process.env.WORKBENCH_USERNAME || "";
  const password = process.env.WORKBENCH_PASSWORD || "";
  const connectionId = process.env.WORKBENCH_CONNECTION_ID || "";
  if (!username || !password || !connectionId) {
    throw new Error(
      "WORKBENCH_USERNAME, WORKBENCH_PASSWORD, and WORKBENCH_CONNECTION_ID " +
        "must be set",
    );
  }
  const baseUrl = process.env.WORKBENCH_URL || "http://localhost:8080";
  return {
    baseUrl: baseUrl.replace(/\/+$/, ""),
    username,
    password,
    connectionId,
    // The Workbench refuses to register a server without a password, even
    // one that uses trust authentication, so fall back to a placeholder.
    serverPassword:
      process.env.PGPASSWORD || "unused-with-trust-authentication",
  };
}
// --8<-- [end:config]

// --8<-- [start:request]
// Sends a request to the API and returns the response. A request that the
// server rejects throws an error that includes the message from the server.
async function api(
  method: string,
  baseUrl: string,
  path: string,
  token?: string,
  body?: unknown,
): Promise<Response> {
  const headers: Record<string, string> = {};
  if (token) headers["Authorization"] = `Bearer ${token}`;
  if (body !== undefined) headers["Content-Type"] = "application/json";

  const response = await fetch(`${baseUrl}/api/v1${path}`, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
    signal: AbortSignal.timeout(30_000),
  });
  if (!response.ok) {
    const text = (await response.text()).trim();
    throw new Error(
      `${method} ${path} failed with status ${response.status}: ${text}`,
    );
  }
  return response;
}
// --8<-- [end:request]

// --8<-- [start:login]
// Logs in and returns the session token. The server returns the token in a
// session_token cookie, not in the body of the reply.
async function login(
  baseUrl: string,
  username: string,
  password: string,
): Promise<string> {
  const response = await api("POST", baseUrl, "/auth/login", undefined, {
    username,
    password,
  });
  for (const cookie of response.headers.getSetCookie()) {
    const match = /^session_token=([^;]*)/.exec(cookie);
    if (match) return match[1];
  }
  throw new Error("The login reply had no session_token cookie");
}
// --8<-- [end:login]

// --8<-- [start:lookup]
interface Connection {
  id: number;
  name: string;
  host: string;
  port: number;
  database_name: string;
  username: string;
  ssl_mode?: string;
  is_monitored: boolean;
}

// Returns the details of an existing connection, which the program uses as
// the address of the server to register.
async function getConnection(
  baseUrl: string,
  session: string,
  connectionId: string,
): Promise<Connection> {
  const response = await api(
    "GET",
    baseUrl,
    `/connections/${connectionId}`,
    session,
  );
  return (await response.json()) as Connection;
}
// --8<-- [end:lookup]

// --8<-- [start:register]
// Registers a server and returns the ID of the new connection. The address
// comes from an existing connection. The request must include a password,
// and a description, which the server needs in version 1.0.0.
async function registerServer(
  baseUrl: string,
  session: string,
  name: string,
  template: Connection,
  password: string,
): Promise<number> {
  const response = await api("POST", baseUrl, "/connections", session, {
    name,
    description: "Registered by the cookbook",
    host: template.host,
    port: template.port,
    database_name: template.database_name,
    username: template.username,
    ssl_mode: template.ssl_mode,
    password,
    is_monitored: true,
    is_shared: false,
  });
  return ((await response.json()) as Connection).id;
}
// --8<-- [end:register]

// --8<-- [start:list]
// Returns the named connection from the list, or undefined if the list has
// no such connection.
async function findConnection(
  baseUrl: string,
  session: string,
  name: string,
): Promise<Connection | undefined> {
  const response = await api("GET", baseUrl, "/connections", session);
  const connections = (await response.json()) as Connection[];
  return connections.find((c) => c.name === name);
}
// --8<-- [end:list]

// --8<-- [start:delete]
// Deletes a connection by its ID.
async function deleteConnection(
  baseUrl: string,
  session: string,
  connectionId: number,
): Promise<void> {
  await api("DELETE", baseUrl, `/connections/${connectionId}`, session);
}
// --8<-- [end:delete]

// --8<-- [start:main]
async function main(): Promise<number> {
  let exitCode = 0;
  let cleanup: (() => Promise<void>) | undefined;
  try {
    const s = settings();

    const session = await login(s.baseUrl, s.username, s.password);
    const template = await getConnection(s.baseUrl, session, s.connectionId);

    const newId = await registerServer(
      s.baseUrl,
      session,
      SERVER_NAME,
      template,
      s.serverPassword,
    );
    // Delete the connection whether or not a later step fails, so that a
    // failed run does not leave a server registered.
    cleanup = () => deleteConnection(s.baseUrl, session, newId);
    console.log(`Registered the server '${SERVER_NAME}'`);

    const found = await findConnection(s.baseUrl, session, SERVER_NAME);
    if (!found) throw new Error("The new connection is missing from the list");
    console.log(
      `Found '${SERVER_NAME}' in the list (monitored: ${found.is_monitored})`,
    );

    await cleanup();
    cleanup = undefined;
    console.log("Deleted the connection");

    if (await findConnection(s.baseUrl, session, SERVER_NAME)) {
      throw new Error("The connection is still in the list");
    }
    console.log("The connection is no longer in the list");
  } catch (err) {
    console.error(`Error: ${err instanceof Error ? err.message : err}`);
    exitCode = 1;
  }

  if (cleanup) {
    try {
      await cleanup();
    } catch (err) {
      console.error(
        `Error: could not delete the connection: ${
          err instanceof Error ? err.message : err
        }`,
      );
      exitCode = 1;
    }
  }
  return exitCode;
}

process.exitCode = await main();
// --8<-- [end:main]
