// Ellie's Postgres Cookbook
// Connecting to PostgreSQL over TLS with full verification, using the
// postgres and postgres-openssl crates.
//
// Copyright (c) 2026, pgEdge, Inc.
// This code is released under the PostgreSQL License.

// --8<-- [start:imports]
use std::env;
use std::error::Error;
use std::process::ExitCode;

use openssl::ssl::{SslConnector, SslMethod};
use postgres::{Client, Config};
use postgres_openssl::MakeTlsConnector;
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

/// Returns the path of the root certificate file. PGSSLROOTCERT has no
/// default, because verification is meaningless without the certificate
/// of the authority that signed the server certificate.
fn root_cert_path() -> Result<String, Box<dyn Error>> {
    env_value("PGSSLROOTCERT").ok_or_else(|| "PGSSLROOTCERT must name the root certificate".into())
}
// --8<-- [end:config]

// --8<-- [start:connect]
/// Builds a TLS connector that trusts only the given root certificate.
/// A connector made by SslConnector::builder verifies the certificate
/// chain and the host name by default, which is the equivalent of
/// sslmode=verify-full; the host name checked is the one in the Config.
fn tls_connector(root_cert: &str) -> Result<MakeTlsConnector, Box<dyn Error>> {
    let mut builder = SslConnector::builder(SslMethod::tls())?;
    builder.set_ca_file(root_cert)?;
    Ok(MakeTlsConnector::new(builder.build()))
}

/// Opens a verified TLS connection with the settings from the
/// environment. The connection fails if verification fails.
fn connect() -> Result<Client, Box<dyn Error>> {
    let tls = tls_connector(&root_cert_path()?)?;
    Ok(config().connect(tls)?)
}
// --8<-- [end:connect]

// --8<-- [start:query]
/// Asks the server whether this connection uses TLS.
fn connection_is_encrypted(client: &mut Client) -> Result<bool, postgres::Error> {
    // pg_stat_ssl has one row for each connection; pg_backend_pid()
    // identifies the one that belongs to this session. The version column
    // holds the protocol version, such as TLSv1.3, and is NULL without
    // TLS, so it maps to an Option.
    let row = client.query_one(
        "SELECT ssl, version FROM pg_catalog.pg_stat_ssl \
         WHERE pid = pg_backend_pid()",
        &[],
    )?;
    let _version: Option<String> = row.get(1);

    // ssl is a boolean, which maps to bool.
    Ok(row.get(0))
}
// --8<-- [end:query]

// --8<-- [start:main]
/// Connects, runs the query, and prints the result. The ? operator
/// returns any error to the caller.
fn run() -> Result<(), Box<dyn Error>> {
    let mut client = connect()?;
    let encrypted = connection_is_encrypted(&mut client)?;
    println!("Connection is encrypted: {encrypted}");
    // Reaching this line means that verification succeeded; a certificate
    // or host name mismatch makes connect() return an error instead.
    println!("Server certificate verified: true");

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
