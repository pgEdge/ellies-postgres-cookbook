/*
 * Ellie's Postgres Cookbook
 * Authenticating with the AI DBA Workbench API, using the built-in fetch.
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
  username: string;
  password: string;
}

// Read the settings from the environment. The || operator, unlike ??, also
// treats an empty variable as unset.
function settings(): Settings {
  const username = process.env.WORKBENCH_USERNAME || "";
  const password = process.env.WORKBENCH_PASSWORD || "";
  if (!username || !password) {
    throw new Error("WORKBENCH_USERNAME and WORKBENCH_PASSWORD must be set");
  }
  const baseUrl = process.env.WORKBENCH_URL || "http://localhost:8080";
  return { baseUrl: baseUrl.replace(/\/+$/, ""), username, password };
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

// --8<-- [start:user_info]
interface UserInfo {
  username: string;
  is_superuser: boolean;
}

// Returns the user that a token belongs to, with its superuser flag.
async function userInfo(baseUrl: string, token: string): Promise<string> {
  const response = await api("GET", baseUrl, "/user/info", token);
  const info = (await response.json()) as UserInfo;
  return `${info.username} (superuser: ${info.is_superuser})`;
}
// --8<-- [end:user_info]

// --8<-- [start:create_token]
interface CreatedToken {
  id: number;
  token: string;
}

// Creates an API token for a user and returns its ID and its value. The
// server shows the value only once. The token expires after an hour.
async function createToken(
  baseUrl: string,
  session: string,
  owner: string,
  annotation: string,
): Promise<CreatedToken> {
  const response = await api("POST", baseUrl, "/rbac/tokens", session, {
    owner_username: owner,
    annotation,
    expires_in: "1h",
  });
  return (await response.json()) as CreatedToken;
}
// --8<-- [end:create_token]

// --8<-- [start:delete_token]
// Deletes an API token by its ID.
async function deleteToken(
  baseUrl: string,
  session: string,
  tokenId: number,
): Promise<void> {
  await api("DELETE", baseUrl, `/rbac/tokens/${tokenId}`, session);
}
// --8<-- [end:delete_token]

// --8<-- [start:main]
async function main(): Promise<number> {
  let exitCode = 0;
  let cleanup: (() => Promise<void>) | undefined;
  try {
    const { baseUrl, username, password } = settings();

    const session = await login(baseUrl, username, password);
    console.log("Logged in with a session token");
    console.log(`Session token belongs to ${await userInfo(baseUrl, session)}`);

    const created = await createToken(
      baseUrl,
      session,
      username,
      "cookbook-authenticate",
    );
    // Delete the token whether or not a later step fails, so that a failed
    // run does not leave a token behind.
    cleanup = () => deleteToken(baseUrl, session, created.id);
    console.log("Created the API token 'cookbook-authenticate'");
    console.log(
      `API token belongs to ${await userInfo(baseUrl, created.token)}`,
    );
  } catch (err) {
    console.error(`Error: ${err instanceof Error ? err.message : err}`);
    exitCode = 1;
  }

  if (cleanup) {
    try {
      await cleanup();
      console.log("Deleted the API token");
    } catch (err) {
      console.error(
        `Error: could not delete the token: ${
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
