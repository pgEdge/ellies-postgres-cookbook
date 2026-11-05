// Ellie's Postgres Cookbook
// Reading resources and prompts from the pgEdge Postgres MCP Server, using
// reqwest and serde_json.
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

/// Sends a JSON-RPC request and returns its result. The server answers a
/// JSON-RPC error with HTTP status 200, so the function checks the reply
/// for an error member as well as the HTTP status.
fn rpc(client: &Client, method: &str, params: Value) -> Result<Value, BoxError> {
    let message = json!({"jsonrpc": "2.0", "id": 1, "method": method, "params": params});
    let response = client
        .post(format!("{}/mcp/v1", base_url()))
        .bearer_auth(token())
        .json(&message)
        .send()?;
    let status = response.status().as_u16();
    let body = response.text()?;
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

/// Returns the strings found under one key in each object of a list.
fn strings(list: &Value, key: &str) -> Vec<String> {
    list.as_array()
        .map(|items| {
            items
                .iter()
                .filter_map(|item| item[key].as_str().map(String::from))
                .collect()
        })
        .unwrap_or_default()
}
// --8<-- [end:config]

// --8<-- [start:resources]
/// Lists the resources that the server offers, and then reads
/// pg://system_info, which describes the PostgreSQL server. The contents
/// of a resource are text, which for this one holds a JSON object, so the
/// function parses the text a second time. version_number is a string such
/// as "180006", from which integer division by 10000 gives the major
/// version.
fn read_system_info(client: &Client) -> Result<(), BoxError> {
    let list = rpc(client, "resources/list", json!({}))?;
    println!("Resources: {}", strings(&list["resources"], "uri").join(", "));

    let result = rpc(client, "resources/read", json!({"uri": "pg://system_info"}))?;
    let text = result["contents"][0]["text"].as_str().unwrap_or("");
    let info: Value = serde_json::from_str(text).unwrap_or(Value::Null);
    let version_number = info["version_number"]
        .as_str()
        .and_then(|number| number.parse::<u32>().ok());
    let (Some(version_number), Some(allow_writes)) =
        (version_number, info["allow_writes"].as_bool())
    else {
        return Err(format!("Unexpected result: {}", shorten(&result.to_string())).into());
    };
    println!("PostgreSQL major version: {}", version_number / 10000);
    println!("Writes allowed: {allow_writes}");
    Ok(())
}
// --8<-- [end:resources]

// --8<-- [start:prompts]
/// Lists the prompts that the server offers, and then fetches
/// explore-database, which takes no arguments. A prompt is a set of
/// messages, ready to hand to a language model, that guide it through a
/// task with the server's tools.
fn read_prompts(client: &Client) -> Result<(), BoxError> {
    let list = rpc(client, "prompts/list", json!({}))?;
    println!("Prompts: {}", strings(&list["prompts"], "name").join(", "));

    let prompt = rpc(
        client,
        "prompts/get",
        json!({"name": "explore-database", "arguments": {}}),
    )?;
    let (Some(description), Some(role)) = (
        prompt["description"].as_str(),
        prompt["messages"][0]["role"].as_str(),
    ) else {
        return Err(format!("Unexpected result: {}", shorten(&prompt.to_string())).into());
    };
    println!("explore-database: {description}");
    println!("First message role: {role}");
    Ok(())
}
// --8<-- [end:prompts]

// --8<-- [start:main]
/// Makes the requests. The ? operator returns any error to the caller.
fn run() -> Result<(), BoxError> {
    if token().is_empty() {
        return Err("MCP_TOKEN must be set".into());
    }
    let client = Client::builder().timeout(TIMEOUT).build()?;
    read_system_info(&client)?;
    read_prompts(&client)
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
