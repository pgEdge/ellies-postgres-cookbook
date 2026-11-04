// Ellie's Postgres Cookbook
// Retrying a transaction after a serialisation failure, using the postgres
// crate.
//
// Copyright (c) 2026, pgEdge, Inc.
// This code is released under the PostgreSQL License.

// --8<-- [start:imports]
use std::env;
use std::error::Error;
use std::process::ExitCode;
use std::thread::sleep;
use std::time::Duration;

use postgres::error::SqlState;
use postgres::{Client, Config, IsolationLevel, NoTls, Transaction};
// --8<-- [end:imports]

// --8<-- [start:config]
const MAX_ATTEMPTS: u32 = 5;

/// Returns true if the error carries a SQLSTATE code that means "run the
/// transaction again": a serialisation failure or a deadlock.
fn is_retryable(error: &postgres::Error) -> bool {
    matches!(
        error.code(),
        Some(code) if *code == SqlState::T_R_SERIALIZATION_FAILURE
            || *code == SqlState::T_R_DEADLOCK_DETECTED
    )
}

/// Returns the value of an environment variable, if it is set and not
/// empty; libpq also treats an empty variable as unset.
fn env_value(name: &str) -> Option<String> {
    env::var(name).ok().filter(|value| !value.is_empty())
}

/// Returns the value of an environment variable, or a fallback if the
/// variable is unset or empty.
fn env_or(name: &str, fallback: &str) -> String {
    env_value(name).unwrap_or_else(|| fallback.to_string())
}

/// Builds the connection configuration from the standard libpq
/// environment variables, with defaults suitable for a local server.
fn config() -> Config {
    let mut config = Config::new();
    config
        .host(&env_or("PGHOST", "localhost"))
        .port(env_or("PGPORT", "5432").parse().expect("PGPORT must be a number"))
        .dbname(&env_or("PGDATABASE", "postgres"))
        .user(&env_or("PGUSER", "postgres"));
    if let Some(password) = env_value("PGPASSWORD") {
        config.password(&password);
    }
    config
}
// --8<-- [end:config]

// --8<-- [start:connect]
/// Opens a connection with the settings from the environment. NoTls
/// disables TLS, which keeps this example free of certificate set-up;
/// connections over an untrusted network should use TLS. The server runs
/// each statement in its own transaction unless the program begins one, so
/// the program decides where each transaction starts and ends.
fn connect() -> Result<Client, postgres::Error> {
    config().connect(NoTls)
}
// --8<-- [end:connect]

// --8<-- [start:setup]
/// Drops the shared counter table if it exists.
fn drop_table(client: &mut Client) -> Result<(), postgres::Error> {
    client.batch_execute("DROP TABLE IF EXISTS cookbook_retry_transactions")
}

/// Creates the shared counter table, with a single row set to zero. The
/// table must be visible to a second connection, so it cannot be
/// temporary; the name is specific to this recipe, and any earlier copy is
/// dropped first.
fn create_table(client: &mut Client) -> Result<(), postgres::Error> {
    drop_table(client)?;
    client.batch_execute(
        "CREATE TABLE cookbook_retry_transactions \
         (id int PRIMARY KEY, value int NOT NULL)",
    )?;
    client.execute(
        "INSERT INTO cookbook_retry_transactions (id, value) VALUES ($1, $2)",
        &[&1_i32, &0_i32],
    )?;
    Ok(())
}
// --8<-- [end:setup]

// --8<-- [start:work]
/// Reads the counter and writes back the value plus one.
fn increment_counter(
    tx: &mut Transaction,
    attempt: u32,
) -> Result<(), postgres::Error> {
    let row = tx.query_one(
        "SELECT value FROM cookbook_retry_transactions WHERE id = $1",
        &[&1_i32],
    )?;
    let value: i32 = row.get(0);

    // Simulate another client by updating the row from a second
    // connection, after this transaction has read the row but before it
    // writes. This happens on the first attempt only.
    if attempt == 1 {
        let mut other = connect()?;
        other.execute(
            "UPDATE cookbook_retry_transactions SET value = value + 1 \
             WHERE id = $1",
            &[&1_i32],
        )?;
    }

    // Under REPEATABLE READ, updating a row that another transaction
    // changed and committed since this transaction's snapshot was taken
    // fails with SQLSTATE 40001.
    tx.execute(
        "UPDATE cookbook_retry_transactions SET value = $1 WHERE id = $2",
        &[&(value + 1), &1_i32],
    )?;
    Ok(())
}

/// Returns the current value of the counter.
fn read_counter(client: &mut Client) -> Result<i32, postgres::Error> {
    let row = client.query_one(
        "SELECT value FROM cookbook_retry_transactions WHERE id = $1",
        &[&1_i32],
    )?;
    Ok(row.get(0))
}
// --8<-- [end:work]

// --8<-- [start:retry]
/// The type of a function that does the work of one transaction.
type Work = fn(&mut Transaction, u32) -> Result<(), postgres::Error>;

/// Runs the work in a single REPEATABLE READ transaction. Dropping the
/// transaction without committing rolls it back, so an error from the
/// work or from the commit leaves nothing behind.
fn run_once(
    client: &mut Client,
    attempt: u32,
    work: Work,
) -> Result<(), postgres::Error> {
    let mut tx = client
        .build_transaction()
        .isolation_level(IsolationLevel::RepeatableRead)
        .start()?;
    work(&mut tx, attempt)?;
    tx.commit()
}

/// Runs the work in a REPEATABLE READ transaction, and runs it again if
/// the server reports a serialisation failure or a deadlock.
fn run_with_retry(client: &mut Client, work: Work) -> Result<(), postgres::Error> {
    for attempt in 1..=MAX_ATTEMPTS {
        match run_once(client, attempt, work) {
            Ok(()) => {
                println!("Attempt {attempt}: committed");
                return Ok(());
            }
            // Any other error, or running out of attempts, is a real
            // failure that the caller must handle.
            Err(e) if !is_retryable(&e) || attempt == MAX_ATTEMPTS => {
                return Err(e);
            }
            Err(_) => {
                println!("Attempt {attempt}: serialisation failure, retrying");
                // A short, growing pause gives the competing transaction
                // time to finish.
                sleep(Duration::from_millis(50 * u64::from(attempt)));
            }
        }
    }
    unreachable!("the final attempt returns above")
}
// --8<-- [end:retry]

// --8<-- [start:main]
/// Connects, runs the transaction with retries, and prints the result.
/// The ? operator returns any error to the caller.
fn run() -> Result<(), postgres::Error> {
    let mut client = connect()?;

    let result = create_table(&mut client)
        .and_then(|()| run_with_retry(&mut client, increment_counter))
        .and_then(|()| read_counter(&mut client));

    // Drop the shared table even if the work failed, but report the error
    // from the work first.
    let dropped = drop_table(&mut client);
    let counter = result?;
    dropped?;
    println!("Counter value: {counter}");

    // Dropping the client also closes the connection, including when ?
    // returns early, but close() lets us see any error that occurs while
    // doing so.
    client.close()?;
    Ok(())
}

/// Reports any error returned by run() and exits with a failure status.
/// The top-level error is often generic ("error connecting to server"),
/// so the chain of underlying causes is printed too.
fn main() -> ExitCode {
    match run() {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("Database error: {e}");
            let mut cause = e.source();
            while let Some(c) = cause {
                eprintln!("  caused by: {c}");
                cause = c.source();
            }
            ExitCode::FAILURE
        }
    }
}
// --8<-- [end:main]
