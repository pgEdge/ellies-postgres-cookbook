// Ellie's Postgres Cookbook
// Passing a list of values as a single array parameter, using the postgres
// crate.
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

// --8<-- [start:query]
/// Returns the names from the list that exist as data types.
fn find_types(client: &mut Client, names: &[&str]) -> Result<Vec<String>, postgres::Error> {
    // The whole list travels as one array parameter, so the SQL text is
    // the same however many values the list holds. The driver converts a
    // slice into a PostgreSQL array.
    let rows = client.query(
        "SELECT typname FROM pg_catalog.pg_type \
         WHERE typname = ANY($1) ORDER BY typname",
        &[&names],
    )?;

    Ok(rows.iter().map(|row| row.get(0)).collect())
}
// --8<-- [end:query]

// --8<-- [start:main]
/// Connects, runs the query, and prints the result. The ? operator
/// returns any error to the caller.
fn run() -> Result<(), postgres::Error> {
    let wanted = ["int4", "text", "bool", "no_such_type"];

    let mut client = connect()?;
    let found = find_types(&mut client, &wanted)?;
    println!(
        "Found {} of {} types: {}",
        found.len(),
        wanted.len(),
        found.join(", ")
    );

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
