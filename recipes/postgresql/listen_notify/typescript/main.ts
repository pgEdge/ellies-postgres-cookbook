/*
 * Ellie's Postgres Cookbook
 * Listening for notifications with LISTEN and NOTIFY, using node-postgres.
 *
 * Copyright (c) 2026, pgEdge, Inc.
 * This code is released under the PostgreSQL License.
 */

// --8<-- [start:imports]
import pg from "pg";
// --8<-- [end:imports]

// --8<-- [start:config]
const CHANNEL = "cookbook_listen_notify";
const TIMEOUT_MS = 5000;

// Read the connection settings from the standard libpq environment
// variables, with defaults suitable for a local development server.
// The || operator, unlike ??, also treats an empty variable as unset, as
// libpq does.
const config: pg.ClientConfig = {
  host: process.env.PGHOST || "localhost",
  port: Number(process.env.PGPORT || "5432"),
  database: process.env.PGDATABASE || "postgres",
  user: process.env.PGUSER || "postgres",
  password: process.env.PGPASSWORD || undefined,
};
// --8<-- [end:config]

// --8<-- [start:connect]
// Opens a connection with the settings from the environment. node-postgres
// runs each query in autocommit mode unless the program sends BEGIN, so
// LISTEN takes effect, and NOTIFY is delivered, as soon as it completes.
async function connect(): Promise<pg.Client> {
  const client = new pg.Client(config);
  try {
    await client.connect();
  } catch (err) {
    // Release the client before passing the failure to the caller.
    await client.end();
    throw err;
  }
  return client;
}
// --8<-- [end:connect]

// --8<-- [start:listen]
// Subscribes the connection to a channel.
async function listen(client: pg.Client, channel: string): Promise<void> {
  // LISTEN takes an identifier rather than a value, so it cannot use a
  // parameter; escapeIdentifier quotes the name safely.
  await client.query(`LISTEN ${client.escapeIdentifier(channel)}`);
}
// --8<-- [end:listen]

// --8<-- [start:notify]
// Sends a notification to every connection listening on a channel.
async function notify(
  client: pg.Client,
  channel: string,
  payload: string,
): Promise<void> {
  // pg_notify() takes the channel and payload as ordinary parameters,
  // unlike the NOTIFY command.
  await client.query("SELECT pg_notify($1, $2)", [channel, payload]);
}
// --8<-- [end:notify]

// --8<-- [start:wait]
// Starts waiting for one notification. The promise resolves with the
// notification, or rejects if none arrives within the timeout. Call this
// before sending the notification: node-postgres emits a notification as
// soon as it arrives, and an event with no listener is lost. Calling
// cancel() stops the timer and the listener, which lets the program exit
// at once if it gives up waiting.
function waitForNotification(
  client: pg.Client,
  timeoutMs: number,
): { promise: Promise<pg.Notification>; cancel: () => void } {
  let cancel = (): void => {};
  const promise = new Promise<pg.Notification>((resolve, reject) => {
    const timer = setTimeout(() => {
      client.removeListener("notification", onNotification);
      reject(new Error(`No notification within ${timeoutMs / 1000} seconds`));
    }, timeoutMs);

    function onNotification(message: pg.Notification): void {
      clearTimeout(timer);
      resolve(message);
    }

    client.once("notification", onNotification);
    cancel = () => {
      clearTimeout(timer);
      client.removeListener("notification", onNotification);
    };
  });
  return { promise, cancel };
}
// --8<-- [end:wait]

// --8<-- [start:main]
// Returns a readable description of an error. When a host name resolves
// to several addresses, Node reports a failure to reach all of them as an
// AggregateError, whose own message is empty.
function describe(err: unknown): string {
  if (err instanceof AggregateError) {
    return err.errors.map(describe).join("; ");
  }
  return err instanceof Error ? err.message : String(err);
}

async function main(): Promise<number> {
  let listener: pg.Client | undefined;
  let sender: pg.Client | undefined;
  try {
    listener = await connect();
    sender = await connect();

    await listen(listener, CHANNEL);
    console.log(`Listening on channel '${CHANNEL}'`);

    const pending = waitForNotification(listener, TIMEOUT_MS);
    try {
      await notify(sender, CHANNEL, "Hello from connection B");
    } catch (err) {
      // Stop the timer, so the program does not wait for it, and mark the
      // promise as handled, so Node does not report it as unhandled.
      pending.cancel();
      pending.promise.catch(() => {});
      throw err;
    }

    const message = await pending.promise;
    console.log(
      `Received notification on '${message.channel}': ${message.payload}`,
    );
    return 0;
  } catch (err) {
    // Connection failures, errors reported by the server, and the
    // notification timeout all arrive here as rejected promises.
    console.error(`Error: ${describe(err)}`);
    return 1;
  } finally {
    // The finally block runs whether or not an error occurred; a client is
    // undefined if its connection attempt failed.
    await listener?.end();
    await sender?.end();
  }
}

process.exitCode = await main();
// --8<-- [end:main]
