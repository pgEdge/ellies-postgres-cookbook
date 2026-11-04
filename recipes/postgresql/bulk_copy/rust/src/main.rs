// Ellie's Postgres Cookbook
// Loading rows in bulk with COPY, using the postgres crate.
//
// Copyright (c) 2026, pgEdge, Inc.
// This code is released under the PostgreSQL License.

// --8<-- [start:imports]
use std::env;
use std::error::Error;
use std::io::Write;
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

// --8<-- [start:create_table]
/// Creates a temporary table, which only this session can see and which
/// PostgreSQL drops when the session ends.
fn create_table(client: &mut Client) -> Result<(), postgres::Error> {
    client.batch_execute(
        "CREATE TEMPORARY TABLE items (id int PRIMARY KEY, name text NOT NULL)",
    )
}
// --8<-- [end:create_table]

// --8<-- [start:generate_rows]
/// Escapes a value for the COPY text format, in which a backslash, a tab,
/// a newline, and a carriage return all have a special meaning.
fn escape_text(value: &str) -> String {
    value
        .replace('\\', "\\\\")
        .replace('\t', "\\t")
        .replace('\n', "\\n")
        .replace('\r', "\\r")
}

/// Returns an iterator over the rows to load, each as one line of COPY
/// text: the columns are separated by a tab, and the row ends with a
/// newline. The iterator produces the rows one at a time, so the program
/// never holds them all.
fn generate_rows(count: i32) -> impl Iterator<Item = String> {
    (1..=count).map(|id| format!("{id}\t{}\n", escape_text(&format!("item {id}"))))
}
// --8<-- [end:generate_rows]

// --8<-- [start:copy_rows]
/// Loads the rows with COPY ... FROM STDIN and returns how many rows the
/// server stored.
fn copy_rows(
    client: &mut Client,
    rows: impl Iterator<Item = String>,
) -> Result<u64, Box<dyn Error>> {
    // copy_in() returns a writer that streams data to the server, which
    // is much faster than one INSERT for each row. The writer buffers
    // the data, so writing one row at a time is efficient.
    let mut writer = client.copy_in("COPY items (id, name) FROM STDIN")?;

    for line in rows {
        writer.write_all(line.as_bytes())?;
    }

    // finish() ends the copy and returns the row count. Dropping the
    // writer without calling finish() would cancel the copy instead.
    Ok(writer.finish()?)
}
// --8<-- [end:copy_rows]

// --8<-- [start:summarise]
/// Returns the number of rows in the table and the sum of their ids.
fn summarise(client: &mut Client) -> Result<(i64, i64), postgres::Error> {
    let row = client.query_one("SELECT count(*), sum(id) FROM items", &[])?;

    // count returns a bigint, and sum of an int returns a bigint too;
    // both map to i64.
    Ok((row.get(0), row.get(1)))
}
// --8<-- [end:summarise]

// --8<-- [start:main]
/// Connects, loads the rows, and prints the result. The ? operator
/// returns any error to the caller.
fn run() -> Result<(), Box<dyn Error>> {
    let mut client = connect()?;
    create_table(&mut client)?;

    let copied = copy_rows(&mut client, generate_rows(1000))?;
    println!("Copied {copied} rows");

    let (count, total) = summarise(&mut client)?;
    println!("Rows in table: {count}");
    println!("Sum of ids: {total}");

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
