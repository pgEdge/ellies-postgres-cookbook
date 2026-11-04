// Ellie's Postgres Cookbook
// Reading a large result in batches, using the postgres crate.
//
// Copyright (c) 2026, pgEdge, Inc.
// This code is released under the PostgreSQL License.

// --8<-- [start:imports]
use std::env;
use std::error::Error;
use std::process::ExitCode;

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

// --8<-- [start:read_batches]
const BATCH_SIZE: i32 = 1000;

/// Reads every row of a large result, one batch at a time, and returns
/// the number of rows and the sum of their values.
fn read_in_batches(client: &mut Client) -> Result<(u64, i64), postgres::Error> {
    let mut rows_read = 0;
    let mut total = 0;

    // A portal, which holds a partly read result on the server, exists
    // only inside a transaction.
    let mut transaction = client.transaction()?;
    let portal = transaction.bind("SELECT g FROM generate_series(1, 100000) AS g", &[])?;

    loop {
        // query_portal() returns up to BATCH_SIZE rows, and an empty
        // list once the result is exhausted.
        let batch = transaction.query_portal(&portal, BATCH_SIZE)?;
        if batch.is_empty() {
            break;
        }

        for row in &batch {
            // generate_series over int literals produces an integer,
            // which maps to i32.
            let value: i32 = row.get(0);
            rows_read += 1;
            total += i64::from(value);
        }
    }

    // End the transaction, which also releases the portal.
    transaction.commit()?;
    Ok((rows_read, total))
}
// --8<-- [end:read_batches]

// --8<-- [start:main]
/// Connects, reads the rows, and prints the result. The ? operator
/// returns any error to the caller.
fn run() -> Result<(), postgres::Error> {
    let mut client = connect()?;
    let (rows_read, total) = read_in_batches(&mut client)?;
    println!("Rows read: {rows_read}");
    println!("Sum of values: {total}");

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
