// Ellie's Postgres Cookbook
// Checking the version of the pgEdge Control Plane, its cluster, and the
// state of each host, using reqwest and serde_json.
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

use reqwest::blocking::Client;
use serde_json::Value;
// --8<-- [end:imports]

// --8<-- [start:config]
/// Returns the value of an environment variable, or a fallback if the
/// variable is unset or empty.
fn env_or(name: &str, fallback: &str) -> String {
    env::var(name)
        .ok()
        .filter(|value| !value.is_empty())
        .unwrap_or_else(|| fallback.to_string())
}

fn base_url() -> String {
    env_or("CONTROL_PLANE_URL", "http://localhost:3000")
        .trim_end_matches('/')
        .to_string()
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

// --8<-- [start:version]
/// Prints the version of the Control Plane server.
fn show_version(client: &Client) -> Result<(), BoxError> {
    let reply = get(client, "/v1/version")?;
    let Some(version) = reply["version"].as_str() else {
        return Err("Unexpected response: missing version".into());
    };
    println!("Version: {version}");
    Ok(())
}
// --8<-- [end:version]

// --8<-- [start:cluster]
/// Prints the state of the cluster. A server answers this request only
/// once its cluster has been initialised, and it then reports
/// "available"; the health of the cluster shows in the state of each host.
fn show_cluster(client: &Client) -> Result<(), BoxError> {
    let reply = get(client, "/v1/cluster")?;
    let Some(state) = reply["status"]["state"].as_str() else {
        return Err("Unexpected response: missing state".into());
    };
    println!("Cluster: {state}");
    Ok(())
}
// --8<-- [end:cluster]

// --8<-- [start:hosts]
/// Lists the hosts in the cluster with their states, and returns whether
/// every host is "healthy". The other states are "degraded",
/// "unreachable" and "unknown".
fn show_hosts(client: &Client) -> Result<bool, BoxError> {
    let reply = get(client, "/v1/hosts")?;
    let Some(hosts) = reply["hosts"].as_array() else {
        return Err("Unexpected response: missing hosts".into());
    };

    println!("Hosts ({}):", hosts.len());
    let mut healthy = true;
    for host in hosts {
        let state = host["status"]["state"].as_str().unwrap_or("unknown");
        println!("- {}: {state}", host["id"].as_str().unwrap_or(""));
        healthy = healthy && state == "healthy";
    }
    Ok(healthy)
}
// --8<-- [end:hosts]

// --8<-- [start:main]
/// Runs the three checks, and returns whether every host is healthy. The
/// ? operator returns any error to the caller.
fn run() -> Result<bool, BoxError> {
    let client = Client::builder().timeout(TIMEOUT).build()?;
    show_version(&client)?;
    show_cluster(&client)?;
    show_hosts(&client)
}

/// Reports any error returned by run() and exits with a failure status.
/// The top-level error is often generic ("error sending request"), so the
/// chain of underlying causes is printed too.
fn main() -> ExitCode {
    match run() {
        Ok(true) => ExitCode::SUCCESS,
        // Report an unhealthy host with the exit status.
        Ok(false) => {
            eprintln!("A host is not healthy");
            ExitCode::FAILURE
        }
        Err(e) => {
            eprintln!("Control Plane error: {e}");
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
