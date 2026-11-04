// Ellie's Postgres Cookbook
// Connecting to PostgreSQL and running a scalar query, using the postgres
// crate.
//
// Copyright (c) 2026, pgEdge, Inc.
// This code is released under the PostgreSQL License.

// --8<-- [start:imports]
use std::env;
use std::error::Error;
use std::process::ExitCode;

use postgres::{Config, NoTls};
// --8<-- [end:imports]

// --8<-- [start:config]
/// Returns the value of an environment variable, or a fallback if unset.
fn env_or(name: &str, fallback: &str) -> String {
    env::var(name).unwrap_or_else(|_| fallback.to_string())
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
    if let Ok(password) = env::var("PGPASSWORD") {
        config.password(&password);
    }
    config
}
// --8<-- [end:config]

fn run() -> Result<(), postgres::Error> {
    // --8<-- [start:connect]
    // NoTls disables TLS; see the TLS recipes for encrypted connections.
    // The ? operator returns any error to the caller.
    let mut client = config().connect(NoTls)?;
    // --8<-- [end:connect]

    // --8<-- [start:query]
    // Always pass values as parameters rather than building them into the
    // SQL string; the driver sends them separately, which prevents SQL
    // injection.
    let row = client.query_one(
        "SELECT count(*) FROM pg_catalog.pg_type WHERE typname = $1",
        &[&"int4"],
    )?;

    // count(*) returns a bigint, which maps to i64.
    let count: i64 = row.get(0);

    println!("Number of types named 'int4': {count}");
    // --8<-- [end:query]

    // --8<-- [start:cleanup]
    // Dropping the client also closes the connection, but close() lets us
    // see any error that occurs while doing so.
    client.close()?;
    // --8<-- [end:cleanup]

    Ok(())
}

// --8<-- [start:errors]
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
// --8<-- [end:errors]
