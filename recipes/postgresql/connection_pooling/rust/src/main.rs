// Ellie's Postgres Cookbook
// Using a connection pool, with the r2d2_postgres crate.
//
// Copyright (c) 2026, pgEdge, Inc.
// This code is released under the PostgreSQL License.

// --8<-- [start:imports]
use std::env;
use std::error::Error;
use std::process::ExitCode;
use std::thread;
use std::time::Duration;

use r2d2_postgres::postgres::{Config, NoTls};
use r2d2_postgres::{r2d2, PostgresConnectionManager};
// --8<-- [end:imports]

// --8<-- [start:config]
/// The most connections that the pool opens at any one time.
const POOL_SIZE: u32 = 2;

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

// --8<-- [start:pool]
/// A pool of connections made by the postgres crate.
type Pool = r2d2::Pool<PostgresConnectionManager<NoTls>>;

/// Creates a pool that holds at most POOL_SIZE connections. NoTls
/// disables TLS, which keeps this example free of certificate set-up;
/// connections over an untrusted network should use TLS.
fn create_pool() -> Result<Pool, r2d2::Error> {
    let manager = PostgresConnectionManager::new(config(), NoTls);
    Pool::builder()
        .max_size(POOL_SIZE)
        // A request for a connection fails after this long if the pool
        // can neither lend an idle connection nor open a new one.
        .connection_timeout(Duration::from_secs(5))
        // build() opens the connections up front, and returns an error if
        // it cannot, for example because the server is unreachable.
        .build(manager)
}
// --8<-- [end:pool]

// --8<-- [start:query]
/// Borrows a connection from the pool, and returns the number back.
fn run_query(pool: &Pool, number: i32) -> Result<i32, Box<dyn Error + Send + Sync>> {
    // get() lends a connection, which returns to the pool when it goes out
    // of scope, whether or not an error occurred; dropping a pooled
    // connection does not disconnect it from the server.
    let mut client = pool.get()?;

    // Pass values as parameters rather than building them into the SQL
    // string. The cast gives the parameter a type, which the server cannot
    // infer from SELECT $1 alone.
    let row = client.query_one("SELECT $1::int", &[&number])?;
    Ok(row.get(0))
}
// --8<-- [end:query]

// --8<-- [start:main]
/// Creates the pool, runs five queries through it at once, and prints the
/// sum. The ? operator returns any error to the caller.
fn run() -> Result<(), Box<dyn Error + Send + Sync>> {
    let pool = create_pool()?;

    // Five threads ask for a connection at once, but the pool has only
    // two, so the other threads wait their turn. Cloning a pool is cheap,
    // because every clone shares the same connections.
    let handles: Vec<_> = (1..=5)
        .map(|number| {
            let pool = pool.clone();
            thread::spawn(move || run_query(&pool, number))
        })
        .collect();

    let mut results = Vec::new();
    for handle in handles {
        results.push(handle.join().map_err(|_| "a query thread panicked")??);
    }

    println!(
        "Ran {} queries through a pool of at most {POOL_SIZE} connections",
        results.len()
    );
    println!("Sum of results: {}", results.iter().sum::<i32>());

    // Dropping the pool closes every connection in it.
    Ok(())
}

/// Reports any error returned by run() and exits with a failure status.
/// The top-level error is often generic, so the chain of underlying
/// causes is printed too.
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
