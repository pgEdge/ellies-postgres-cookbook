// Ellie's Postgres Cookbook
// Inserting rows and reading generated keys, using the postgres crate.
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

// --8<-- [start:setup]
/// Creates a temporary table whose id column the server fills in.
/// GENERATED ALWAYS AS IDENTITY makes the server assign each id from a
/// sequence, and refuses any attempt to supply one. batch_execute runs
/// statements that take no parameters.
fn create_people(client: &mut Client) -> Result<(), postgres::Error> {
    client.batch_execute(
        "CREATE TEMPORARY TABLE people (
             id int GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
             name text NOT NULL)",
    )
}
// --8<-- [end:setup]

// --8<-- [start:add_person]
/// Inserts a row and returns the id that the server generated.
fn add_person(client: &mut Client, name: &str) -> Result<i32, postgres::Error> {
    // RETURNING makes the INSERT produce a result row, like a SELECT, so
    // the program learns the new id without a second query. The name is a
    // parameter, which the driver sends separately from the SQL text.
    let row = client.query_one(
        "INSERT INTO people (name) VALUES ($1) RETURNING id",
        &[&name],
    )?;

    // An int column maps to i32.
    Ok(row.get(0))
}
// --8<-- [end:add_person]

// --8<-- [start:main]
/// Connects, inserts the rows, and prints their ids. The ? operator
/// returns any error to the caller.
fn run() -> Result<(), postgres::Error> {
    let mut client = connect()?;
    create_people(&mut client)?;
    for name in ["Jane Doe", "John Smith", "Alex Example"] {
        let id = add_person(&mut client, name)?;
        println!("Inserted '{name}' with id {id}");
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
