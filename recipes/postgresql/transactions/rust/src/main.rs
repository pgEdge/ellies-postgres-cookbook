// Ellie's Postgres Cookbook
// Using transactions to move money between accounts, using the postgres
// crate.
//
// Copyright (c) 2026, pgEdge, Inc.
// This code is released under the PostgreSQL License.

// --8<-- [start:imports]
use std::env;
use std::error::Error;
use std::process::ExitCode;

use postgres::error::SqlState;
use postgres::{Client, Config, NoTls};
// --8<-- [end:imports]

// --8<-- [start:config]
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
/// connections over an untrusted network should use TLS.
fn connect() -> Result<Client, postgres::Error> {
    config().connect(NoTls)
}
// --8<-- [end:connect]

// --8<-- [start:setup]
/// Creates a temporary table of two accounts. The CHECK constraint stops
/// any balance from going below zero. batch_execute runs statements that
/// take no parameters.
fn create_accounts(client: &mut Client) -> Result<(), postgres::Error> {
    client.batch_execute(
        "CREATE TEMPORARY TABLE accounts (
             id int PRIMARY KEY,
             balance int NOT NULL CHECK (balance >= 0));
         INSERT INTO accounts VALUES (1, 100), (2, 50)",
    )
}
// --8<-- [end:setup]

// --8<-- [start:transfer]
/// Moves money between two accounts in a single transaction.
fn transfer(
    client: &mut Client,
    source: i32,
    target: i32,
    amount: i32,
) -> Result<(), postgres::Error> {
    // transaction() sends BEGIN. Dropping the transaction without calling
    // commit() rolls it back, so the ? operator that returns an error from
    // this function also undoes the work.
    let mut tx = client.transaction()?;

    // Credit the target first, so that a failure of the debit shows that
    // the rollback undoes the credit as well.
    tx.execute(
        "UPDATE accounts SET balance = balance + $1 WHERE id = $2",
        &[&amount, &target],
    )?;
    tx.execute(
        "UPDATE accounts SET balance = balance - $1 WHERE id = $2",
        &[&amount, &source],
    )?;

    tx.commit()
}
// --8<-- [end:transfer]

// --8<-- [start:balance]
/// Returns the balance of the given account.
fn get_balance(client: &mut Client, account: i32) -> Result<i32, postgres::Error> {
    let row = client.query_one(
        "SELECT balance FROM accounts WHERE id = $1",
        &[&account],
    )?;

    // An int column maps to i32.
    Ok(row.get(0))
}
// --8<-- [end:balance]

// --8<-- [start:main]
/// Connects, makes the transfers, and prints the balances. The ? operator
/// returns any error to the caller.
fn run() -> Result<(), postgres::Error> {
    let mut client = connect()?;
    create_accounts(&mut client)?;

    transfer(&mut client, 1, 2, 30)?;
    println!("Transferred 30 from account 1 to account 2");

    // A check constraint violation is an expected outcome, because the
    // transaction has already been rolled back; any other error is not,
    // and is returned.
    match transfer(&mut client, 1, 2, 500) {
        Ok(()) => println!("Transferred 500 from account 1 to account 2"),
        Err(e) if e.code() == Some(&SqlState::CHECK_VIOLATION) => {
            println!("Transfer of 500 from account 1 to account 2 failed and was rolled back");
        }
        Err(e) => return Err(e),
    }

    for account in [1, 2] {
        println!("Account {account} balance: {}", get_balance(&mut client, account)?);
    }

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
