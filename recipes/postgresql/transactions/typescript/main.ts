/*
 * Ellie's Postgres Cookbook
 * Using transactions to move money between accounts, using node-postgres.
 *
 * Copyright (c) 2026, pgEdge, Inc.
 * This code is released under the PostgreSQL License.
 */

// --8<-- [start:imports]
import pg from "pg";
// --8<-- [end:imports]

// --8<-- [start:config]
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
// Opens a connection with the settings from the environment.
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

// --8<-- [start:setup]
// Creates a temporary table of two accounts. The CHECK constraint stops
// any balance from going below zero.
async function createAccounts(client: pg.Client): Promise<void> {
  await client.query(
    "CREATE TEMPORARY TABLE accounts (" +
      "id int PRIMARY KEY, " +
      "balance int NOT NULL CHECK (balance >= 0))",
  );
  await client.query("INSERT INTO accounts VALUES (1, 100), (2, 50)");
}
// --8<-- [end:setup]

// --8<-- [start:transfer]
// Moves money between two accounts in a single transaction.
async function transfer(
  client: pg.Client,
  source: number,
  target: number,
  amount: number,
): Promise<void> {
  // node-postgres has no transaction object, so the program sends BEGIN,
  // COMMIT, and ROLLBACK itself. Everything sent on this client between
  // BEGIN and COMMIT belongs to the transaction.
  await client.query("BEGIN");
  try {
    // Credit the target first, so that a failure of the debit shows that
    // the rollback undoes the credit as well.
    await client.query(
      "UPDATE accounts SET balance = balance + $1 WHERE id = $2",
      [amount, target],
    );
    await client.query(
      "UPDATE accounts SET balance = balance - $1 WHERE id = $2",
      [amount, source],
    );
    await client.query("COMMIT");
  } catch (err) {
    // Undo the work, then pass the original error to the caller. If the
    // rollback fails too (for example, because the connection has gone),
    // ignore that failure so that it does not hide the original error.
    await client.query("ROLLBACK").catch(() => {});
    throw err;
  }
}
// --8<-- [end:transfer]

// --8<-- [start:balance]
// Returns the balance of the given account.
async function getBalance(client: pg.Client, account: number): Promise<number> {
  const result = await client.query<{ balance: number }>(
    "SELECT balance FROM accounts WHERE id = $1",
    [account],
  );
  return result.rows[0].balance;
}
// --8<-- [end:balance]

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

// Returns true for a check constraint violation, which is SQLSTATE 23514.
function isCheckViolation(err: unknown): boolean {
  return err instanceof pg.DatabaseError && err.code === "23514";
}

async function main(): Promise<number> {
  let client: pg.Client | undefined;
  try {
    client = await connect();
    await createAccounts(client);

    await transfer(client, 1, 2, 30);
    console.log("Transferred 30 from account 1 to account 2");

    try {
      await transfer(client, 1, 2, 500);
      console.log("Transferred 500 from account 1 to account 2");
    } catch (err) {
      // The transaction has already been rolled back, so a check violation
      // is an expected outcome; any other error is not, and reaches the
      // handler below.
      if (!isCheckViolation(err)) {
        throw err;
      }
      console.log(
        "Transfer of 500 from account 1 to account 2 " +
          "failed and was rolled back",
      );
    }

    for (const account of [1, 2]) {
      console.log(`Account ${account} balance: ${await getBalance(client, account)}`);
    }
    return 0;
  } catch (err) {
    // Connection failures and errors reported by the server both arrive
    // here as rejected promises.
    console.error(`Database error: ${describe(err)}`);
    return 1;
  } finally {
    // The finally block runs whether or not an error occurred; client is
    // undefined if the connection attempt failed.
    await client?.end();
  }
}

process.exitCode = await main();
// --8<-- [end:main]
