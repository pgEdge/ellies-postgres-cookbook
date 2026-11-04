// Ellie's Postgres Cookbook
// Storing and searching vectors with pgvector, using the postgres crate.
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

// --8<-- [start:schema]
/// Enables pgvector and creates a temporary table of colours.
fn create_schema(client: &mut Client) -> Result<(), postgres::Error> {
    // vector(3) fixes the number of dimensions, one for each of the red,
    // green, and blue components. The temporary table disappears when the
    // session ends, so the program can run repeatedly. An HNSW index
    // speeds up nearest-neighbour searches; vector_l2_ops matches the <->
    // (Euclidean distance) operator used by the search. batch_execute runs
    // statements that take no parameters.
    client.batch_execute(
        "CREATE EXTENSION IF NOT EXISTS vector;
         CREATE TEMPORARY TABLE colours (
             name text PRIMARY KEY, rgb vector(3) NOT NULL);
         CREATE INDEX ON colours USING hnsw (rgb vector_l2_ops)",
    )
}
// --8<-- [end:schema]

// --8<-- [start:insert]
/// Stores five colours, each as a vector of its RGB components.
fn insert_colours(client: &mut Client) -> Result<(), postgres::Error> {
    let colours = [
        ("red", "[1,0,0]"),
        ("green", "[0,1,0]"),
        ("blue", "[0,0,1]"),
        ("yellow", "[1,1,0]"),
        ("white", "[1,1,1]"),
    ];
    for (name, rgb) in colours {
        // A vector travels as text in pgvector's [x,y,z] format, and the
        // casts convert it on the server, so the driver needs no
        // vector-specific support. The driver checks parameter types, so
        // ::text declares the parameter as text before ::vector converts
        // it.
        client.execute(
            "INSERT INTO colours (name, rgb) VALUES ($1, $2::text::vector)",
            &[&name, &rgb],
        )?;
    }
    Ok(())
}
// --8<-- [end:insert]

// --8<-- [start:search]
/// Returns the names of the colours nearest to the target vector.
fn nearest_colours(
    client: &mut Client,
    target: &str,
    count: i64,
) -> Result<Vec<String>, postgres::Error> {
    // <-> is the Euclidean (L2) distance operator, so ordering by it puts
    // the nearest colour first. As when inserting, ::text declares the
    // parameter as text before ::vector converts it. LIMIT takes a
    // bigint, which maps to i64.
    let rows = client.query(
        "SELECT name FROM colours ORDER BY rgb <-> $1::text::vector LIMIT $2",
        &[&target, &count],
    )?;
    Ok(rows.iter().map(|row| row.get(0)).collect())
}
// --8<-- [end:search]

// --8<-- [start:main]
/// Connects, stores the colours, searches them, and prints the result. The
/// ? operator returns any error to the caller.
fn run() -> Result<(), postgres::Error> {
    let target = "[0.9,0.7,0.2]";
    let mut client = connect()?;
    create_schema(&mut client)?;
    insert_colours(&mut client)?;

    println!("Colours nearest to {target}:");
    for (i, name) in nearest_colours(&mut client, target, 3)?.iter().enumerate() {
        println!("{}. {name}", i + 1);
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
