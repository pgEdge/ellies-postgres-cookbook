// Ellie's Postgres Cookbook
// Finding the address of a pgEdge Control Plane database and connecting
// to it, using reqwest, serde_json and the postgres crate.
//
// These examples are for the Control Plane v0.11.0.
//
// Copyright (c) 2026, pgEdge, Inc.
// This code is released under the PostgreSQL License.

// --8<-- [start:imports]
use std::env;
use std::error::Error;
use std::process::ExitCode;
use std::time::Duration;

use postgres::{Config, NoTls};
use reqwest::blocking::Client;
use serde_json::Value;
// --8<-- [end:imports]

// --8<-- [start:config]
/// Returns the value of an environment variable, or None if the variable
/// is unset or empty.
fn env_value(name: &str) -> Option<String> {
    env::var(name).ok().filter(|value| !value.is_empty())
}

/// Returns the value of an environment variable, or a fallback.
fn env_or(name: &str, fallback: &str) -> String {
    env_value(name).unwrap_or_else(|| fallback.to_string())
}

fn base_url() -> String {
    env_or("CONTROL_PLANE_URL", "http://localhost:3000")
        .trim_end_matches('/')
        .to_string()
}

// The password has no default; the Control Plane never returns it, so it
// comes from whoever created the database user.
fn database_id() -> String {
    env_or("CONTROL_PLANE_DATABASE_ID", "cookbook")
}

const TIMEOUT: Duration = Duration::from_secs(30);

/// The errors that the functions below return; a string converts into one
/// with the ? operator or into().
type BoxError = Box<dyn Error>;

/// Returns at most the first 200 characters of a reply.
fn shorten(text: &str) -> String {
    text.chars().take(200).collect()
}

/// Fetches a path from the server, and returns the decoded reply.
fn get(client: &Client, path: &str) -> Result<Value, BoxError> {
    let response = client.get(format!("{}{path}", base_url())).send()?;
    let status = response.status();
    let body = response.text()?;
    if !status.is_success() {
        return Err(format!("HTTP {}, {}", status.as_u16(), shorten(&body)).into());
    }
    match serde_json::from_str::<Value>(&body) {
        Ok(reply) if reply.is_object() => Ok(reply),
        _ => Err(format!("Unexpected response: {}", shorten(&body)).into()),
    }
}
// --8<-- [end:config]

// --8<-- [start:find]
/// The settings for connecting to one instance.
struct Instance {
    node: String,
    host: String,
    port: u16,
    database: String,
}

/// Returns the connection settings for the first instance of the database
/// that is available. Each instance runs one node of the database, and
/// its connection_info holds the addresses and port that clients use.
fn find_instance(client: &Client) -> Result<Instance, BoxError> {
    let database = get(client, &format!("/v1/databases/{}", database_id()))?;
    // as_array() gives None when the reply lists no instances.
    for instance in database["instances"].as_array().into_iter().flatten() {
        let info = &instance["connection_info"];
        if let (Some("available"), Some(address)) =
            (instance["state"].as_str(), info["addresses"][0].as_str())
        {
            return Ok(Instance {
                node: instance["node_name"].as_str().unwrap_or("").to_string(),
                host: address.to_string(),
                port: info["port"].as_u64().unwrap_or(0).try_into()?,
                database: database["spec"]["database_name"]
                    .as_str()
                    .unwrap_or("")
                    .to_string(),
            });
        }
    }
    Err(format!("no available instance of {}", database_id()).into())
}
// --8<-- [end:find]

// --8<-- [start:connect]
/// Connects to the instance, and returns the name of the database and the
/// version of the Spock extension. NoTls disables TLS, which keeps this
/// example free of certificate set-up; connections over an untrusted
/// network should use TLS.
fn query(instance: &Instance, password: &str) -> Result<(String, String), postgres::Error> {
    let mut client = Config::new()
        .host(&instance.host)
        .port(instance.port)
        .dbname(&instance.database)
        .user(&env_or("CONTROL_PLANE_DATABASE_USER", "cookbook"))
        .password(password)
        .connect_timeout(TIMEOUT)
        .connect(NoTls)?;

    let database: String = client.query_one("SELECT current_database()", &[])?.get(0);
    // query_opt returns None when no row matches.
    let spock = client
        .query_opt("SELECT extversion FROM pg_extension WHERE extname = 'spock'", &[])?
        .map(|row| row.get(0))
        .unwrap_or_else(|| "not installed".to_string());
    // The client closes its connection when it goes out of scope.
    Ok((database, spock))
}
// --8<-- [end:connect]

// --8<-- [start:main]
/// Prints an error with the chain of underlying causes, since the
/// top-level error is often generic ("error sending request").
fn report(prefix: &str, e: &dyn Error) {
    eprintln!("{prefix}: {e}");
    let mut cause = e.source();
    while let Some(c) = cause {
        eprintln!("  caused by: {c}");
        cause = c.source();
    }
}

fn main() -> ExitCode {
    let Some(password) = env_value("CONTROL_PLANE_DATABASE_PASSWORD") else {
        eprintln!("CONTROL_PLANE_DATABASE_PASSWORD must be set");
        return ExitCode::FAILURE;
    };

    let instance = match Client::builder()
        .timeout(TIMEOUT)
        .build()
        .map_err(BoxError::from)
        .and_then(|client| find_instance(&client))
    {
        Ok(instance) => instance,
        Err(e) => {
            report("Control Plane error", e.as_ref());
            return ExitCode::FAILURE;
        }
    };
    println!("Connecting to node {}", instance.node);

    match query(&instance, &password) {
        Ok((database, spock)) => {
            println!("Connected to database {database}");
            println!("Spock: {spock}");
            ExitCode::SUCCESS
        }
        Err(e) => {
            report("Database error", &e);
            ExitCode::FAILURE
        }
    }
}
// --8<-- [end:main]
