// Ellie's Postgres Cookbook
// Setting a server-side statement timeout, using the postgres crate.
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
/// connections over an untrusted network should use TLS. The server runs
/// each statement in its own transaction unless the program begins one, so
/// a cancelled statement does not leave the session in a failed
/// transaction.
fn connect() -> Result<Client, postgres::Error> {
    config().connect(NoTls)
}
// --8<-- [end:connect]

// --8<-- [start:timeout]
/// Sets the statement timeout for the rest of the session.
fn set_statement_timeout(
    client: &mut Client,
    timeout: &str,
) -> Result<(), postgres::Error> {
    // SET cannot take a parameter, but set_config() is an ordinary
    // function, so the value can be sent safely. The final argument,
    // false, makes the setting last for the session rather than for the
    // current transaction.
    client.execute(
        "SELECT set_config('statement_timeout', $1, false)",
        &[&timeout],
    )?;
    Ok(())
}

/// Runs a statement that outlasts the timeout, and returns true if the
/// server cancelled it.
fn sleep_exceeds_timeout(client: &mut Client) -> Result<bool, postgres::Error> {
    match client.batch_execute("SELECT pg_sleep(5)") {
        Ok(()) => Ok(false),
        Err(e) if e.code() == Some(&SqlState::QUERY_CANCELED) => Ok(true),
        // Only a cancelled statement is expected here; any other error
        // is a real failure, so it is returned.
        Err(e) => Err(e),
    }
}

/// Returns true if the session can still run a statement.
fn is_usable(client: &mut Client) -> Result<bool, postgres::Error> {
    let row = client.query_one("SELECT 1", &[])?;
    let one: i32 = row.get(0);
    Ok(one == 1)
}
// --8<-- [end:timeout]

// --8<-- [start:main]
/// Connects, sets the timeout, runs the slow statement, and prints the
/// results. The ? operator returns any error to the caller.
fn run() -> Result<(), postgres::Error> {
    let mut client = connect()?;
    set_statement_timeout(&mut client, "100ms")?;

    if sleep_exceeds_timeout(&mut client)? {
        println!("Query cancelled after exceeding the statement timeout");
    }
    println!("Connection still usable: {}", is_usable(&mut client)?);

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
