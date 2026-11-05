// Ellie's Postgres Cookbook
// Checking the health of the pgEdge RAG Server and listing its pipelines,
// using reqwest and serde_json.
//
// These examples are for pgEdge RAG Server 2.0.0.
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
    env_or("RAG_SERVER_URL", "http://localhost:8080")
        .trim_end_matches('/')
        .to_string()
}

/// None of these endpoints calls a language model, but the health check
/// contacts each provider, so allow it some time.
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

// --8<-- [start:live]
/// Checks that the server process is running. The /v1/live endpoint is
/// cheap and calls nothing else, so it suits a frequent liveness probe.
fn check_live(client: &Client) -> Result<(), BoxError> {
    let reply = get(client, "/v1/live")?;
    if reply["status"].as_str() != Some("ok") {
        return Err(format!("Unexpected response: {reply}").into());
    }
    println!("Live: ok");
    Ok(())
}
// --8<-- [end:live]

// --8<-- [start:health]
/// Describes whether a language model provider answered the check.
fn describe_provider(provider: &Value) -> String {
    if provider["reachable"].as_bool() == Some(true) {
        return "reachable".to_string();
    }
    format!("unreachable ({})", provider["error"].as_str().unwrap_or("unknown"))
}

/// Checks whether each pipeline can reach its language model providers.
/// The /v1/health endpoint answers with HTTP 200 even when a provider is
/// down, so the status field is the thing to check: it is "healthy" or
/// "degraded". Prints the report, and returns whether the server is
/// healthy.
fn check_health(client: &Client) -> Result<bool, BoxError> {
    let reply = get(client, "/v1/health")?;
    let Some(status) = reply["status"].as_str() else {
        return Err(format!("Unexpected response: {reply}").into());
    };

    println!("Health: {status}");
    // as_array() gives None when the reply lists no pipelines.
    for pipeline in reply["pipelines"].as_array().into_iter().flatten() {
        println!(
            "- {}: embedding {}, completion {}",
            pipeline["name"].as_str().unwrap_or(""),
            describe_provider(&pipeline["embedding"]),
            describe_provider(&pipeline["completion"]),
        );
    }
    Ok(status == "healthy")
}
// --8<-- [end:health]

// --8<-- [start:pipelines]
/// Lists the pipelines that the server offers, with their descriptions.
fn list_pipelines(client: &Client) -> Result<(), BoxError> {
    let reply = get(client, "/v1/pipelines")?;
    let Some(pipelines) = reply["pipelines"].as_array() else {
        return Err("Unexpected response: missing pipelines".into());
    };

    println!("Pipelines ({}):", pipelines.len());
    for pipeline in pipelines {
        let description = match pipeline["description"].as_str() {
            Some(text) if !text.is_empty() => text,
            _ => "(no description)",
        };
        println!("- {}: {description}", pipeline["name"].as_str().unwrap_or(""));
    }
    Ok(())
}
// --8<-- [end:pipelines]

// --8<-- [start:main]
/// Runs the three checks, and returns whether the server is healthy. The
/// ? operator returns any error to the caller.
fn run() -> Result<bool, BoxError> {
    let client = Client::builder().timeout(TIMEOUT).build()?;
    check_live(&client)?;
    let healthy = check_health(&client)?;
    list_pipelines(&client)?;
    Ok(healthy)
}

/// Reports any error returned by run() and exits with a failure status.
/// The top-level error is often generic ("error sending request"), so the
/// chain of underlying causes is printed too.
fn main() -> ExitCode {
    match run() {
        Ok(true) => ExitCode::SUCCESS,
        // A degraded server still answers with HTTP 200, so report it
        // with the exit status.
        Ok(false) => {
            eprintln!("RAG Server is not healthy");
            ExitCode::FAILURE
        }
        Err(e) => {
            eprintln!("RAG Server error: {e}");
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
