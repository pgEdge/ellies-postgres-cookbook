// Ellie's Postgres Cookbook
// Connecting to the pgEdge Postgres MCP Server, using reqwest and
// serde_json.
//
// These examples are for pgEdge Postgres MCP Server 1.1.0.
//
// Copyright (c) 2026, pgEdge, Inc.
// This code is released under the PostgreSQL License.

// --8<-- [start:imports]
use std::env;
use std::error::Error;
use std::process::ExitCode;
use std::time::Duration;

use reqwest::blocking::Client;
use serde_json::{json, Value};
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
    env_or("MCP_URL", "http://localhost:8080")
        .trim_end_matches('/')
        .to_string()
}

fn token() -> String {
    env_or("MCP_TOKEN", "")
}

const TIMEOUT: Duration = Duration::from_secs(30);

/// The errors that the functions below return; a string converts into one
/// with the ? operator or into().
type BoxError = Box<dyn Error>;

/// Returns at most the first 200 characters of a reply.
fn shorten(text: &str) -> String {
    text.chars().take(200).collect()
}

/// Posts a JSON-RPC message to the MCP endpoint with a token, and returns
/// the HTTP status and the body of the reply.
fn post(client: &Client, with_token: &str, message: &Value) -> Result<(u16, String), BoxError> {
    let response = client
        .post(format!("{}/mcp/v1", base_url()))
        .bearer_auth(with_token)
        .json(message)
        .send()?;
    let status = response.status().as_u16();
    Ok((status, response.text()?))
}

/// Sends a JSON-RPC request and returns its result. The server answers a
/// JSON-RPC error with HTTP status 200, so the function checks the reply
/// for an error member as well as the HTTP status.
fn rpc(client: &Client, method: &str, params: Value) -> Result<Value, BoxError> {
    let message = json!({"jsonrpc": "2.0", "id": 1, "method": method, "params": params});
    let (status, body) = post(client, &token(), &message)?;
    if status != 200 {
        return Err(format!("{method} failed with HTTP {status}: {}", shorten(&body)).into());
    }
    let reply = match serde_json::from_str::<Value>(&body) {
        Ok(reply) if reply.get("result").is_some() || reply.get("error").is_some() => reply,
        _ => return Err(format!("{method} failed: unexpected response: {}", shorten(&body)).into()),
    };
    if let Some(error) = reply.get("error") {
        let message = error["message"].as_str().unwrap_or("unknown error");
        return Err(format!("{method} failed: {message}").into());
    }
    Ok(reply["result"].clone())
}
// --8<-- [end:config]

// --8<-- [start:health]
/// Checks that the server is running. The /health endpoint needs no token.
fn check_health(client: &Client) -> Result<(), BoxError> {
    let response = client.get(format!("{}/health", base_url())).send()?;
    let status = response.status().as_u16();
    let body = response.text()?;
    if status != 200 {
        return Err(format!("Health check failed with HTTP {status}: {}", shorten(&body)).into());
    }
    let health: Value = serde_json::from_str(&body).unwrap_or(Value::Null);
    if health["status"].as_str() != Some("ok") {
        return Err(format!("Unexpected response: {}", shorten(&body)).into());
    }
    println!("Health: ok");
    Ok(())
}
// --8<-- [end:health]

// --8<-- [start:initialize]
/// Introduces the client to the server, and prints the server's name and
/// version and the protocol revision that the server chose. The server
/// accepts 2024-11-05, 2025-03-26, 2025-06-18 and 2025-11-25, and answers a
/// revision it does not know with one that it does, so the client checks
/// the answer. The notifications/initialized message then completes the
/// handshake; it is a notification, with no id, so the server replies with
/// HTTP 202 and no body.
fn initialize(client: &Client) -> Result<(), BoxError> {
    let result = rpc(
        client,
        "initialize",
        json!({
            "protocolVersion": "2025-06-18",
            "capabilities": {},
            "clientInfo": {"name": "cookbook", "version": "1.0.0"},
        }),
    )?;
    let info = &result["serverInfo"];
    let (Some(name), Some(version)) = (info["name"].as_str(), info["version"].as_str()) else {
        return Err(format!("Unexpected result: {result}").into());
    };
    println!("Server: {name} {version}");
    let protocol = result["protocolVersion"].as_str().unwrap_or("");
    if protocol != "2025-06-18" {
        return Err(format!("The server chose protocol version {protocol}").into());
    }
    println!("Protocol version: {protocol}");

    let message = json!({"jsonrpc": "2.0", "method": "notifications/initialized"});
    let (status, body) = post(client, &token(), &message)?;
    if status != 202 {
        return Err(format!(
            "notifications/initialized failed with HTTP {status}: {}",
            shorten(&body)
        )
        .into());
    }
    Ok(())
}
// --8<-- [end:initialize]

// --8<-- [start:wrong_token]
/// Sends a request with a token that the server does not know, and prints
/// the HTTP status and the server's message, which is a JSON object with
/// an error member rather than a JSON-RPC reply.
fn wrong_token(client: &Client) -> Result<(), BoxError> {
    let message = json!({"jsonrpc": "2.0", "id": 1, "method": "tools/list", "params": {}});
    let (status, body) = post(client, "not-a-real-token", &message)?;
    if status != 401 {
        return Err(format!("Expected HTTP 401 for a wrong token, but got {status}").into());
    }
    let reply: Value = serde_json::from_str(&body).unwrap_or(Value::Null);
    let message = match reply["error"].as_str() {
        Some(text) if !text.is_empty() => text,
        _ => "no message",
    };
    println!("Wrong token: HTTP {status}, {message}");
    Ok(())
}
// --8<-- [end:wrong_token]

// --8<-- [start:main]
/// Makes the three checks. The ? operator returns any error to the
/// caller.
fn run() -> Result<(), BoxError> {
    if token().is_empty() {
        return Err("MCP_TOKEN must be set".into());
    }
    let client = Client::builder().timeout(TIMEOUT).build()?;
    check_health(&client)?;
    initialize(&client)?;
    wrong_token(&client)
}

/// Reports any error returned by run() and exits with a failure status.
/// The top-level error is often generic ("error sending request"), so the
/// chain of underlying causes is printed too.
fn main() -> ExitCode {
    match run() {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("MCP Server error: {e}");
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
