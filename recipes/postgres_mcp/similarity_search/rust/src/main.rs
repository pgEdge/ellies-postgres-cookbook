// Ellie's Postgres Cookbook
// Searching by meaning through the pgEdge Postgres MCP Server, using
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

/// The server turns the query into an embedding before it searches, which
/// can take a while if the embedding model has to load first, so the
/// timeout is longer than in the other recipes.
const TIMEOUT: Duration = Duration::from_secs(90);

const QUERY: &str = "a gift for an amateur astronomer";

/// The errors that the functions below return; a string converts into one
/// with the ? operator or into().
type BoxError = Box<dyn Error>;

/// Returns at most the first 200 characters of a reply.
fn shorten(text: &str) -> String {
    text.chars().take(200).collect()
}

/// Calls a tool with tools/call and returns the text of its reply. The
/// server answers a JSON-RPC error with HTTP status 200, and a tool that
/// fails returns a normal result with isError set, so the function checks
/// for both as well as the HTTP status.
fn call_tool(client: &Client, name: &str, arguments: Value) -> Result<String, BoxError> {
    let message = json!({
        "jsonrpc": "2.0", "id": 1, "method": "tools/call",
        "params": {"name": name, "arguments": arguments},
    });
    let response = client
        .post(format!("{}/mcp/v1", base_url()))
        .bearer_auth(token())
        .json(&message)
        .send()?;
    let status = response.status().as_u16();
    let body = response.text()?;
    if status != 200 {
        return Err(format!("{name} failed with HTTP {status}: {}", shorten(&body)).into());
    }
    let reply = match serde_json::from_str::<Value>(&body) {
        Ok(reply) if reply.get("result").is_some() || reply.get("error").is_some() => reply,
        _ => return Err(format!("{name} failed: unexpected response: {}", shorten(&body)).into()),
    };
    if let Some(error) = reply.get("error") {
        let message = error["message"].as_str().unwrap_or("unknown error");
        return Err(format!("{name} failed: {message}").into());
    }
    let result = &reply["result"];
    let Some(text) = result["content"][0]["text"].as_str() else {
        return Err(format!("{name} failed: unexpected result: {}", shorten(&body)).into());
    };
    if result["isError"].as_bool() == Some(true) {
        return Err(format!("{name} failed: {text}").into());
    }
    Ok(text.to_string())
}
// --8<-- [end:config]

// --8<-- [start:search]
/// Returns true for the line that starts each result, such as
/// "Result 1/3".
fn is_result_line(line: &str) -> bool {
    let Some(numbers) = line.strip_prefix("Result ") else {
        return false;
    };
    let Some((index, total)) = numbers.split_once('/') else {
        return false;
    };
    [index, total]
        .iter()
        .all(|n| !n.is_empty() && n.chars().all(|c| c.is_ascii_digit()))
}

/// Searches the product descriptions for the query, and prints the number
/// of results and the name of the product that matches it most closely.
/// similarity_search finds the closest rows by vector distance, and then
/// reorders them, mixing in a keyword score and favouring variety, so the
/// first result in the reply is not always the closest. Each result has a
/// line such as "Source: cookbook_mcp.products.description (vector search
/// rank: #1, chunk: 1)"; the function picks the result ranked first by the
/// vector search, whose text follows the first blank line after it. Every
/// description starts with the product's name and a colon.
fn search(client: &Client) -> Result<(), BoxError> {
    let text = call_tool(
        client,
        "similarity_search",
        json!({
            "table_name": "cookbook_mcp.products",
            "query_text": QUERY,
            "top_n": 3,
        }),
    )?;
    println!("Query: {QUERY}");
    let count = text.split('\n').filter(|line| is_result_line(line)).count();
    println!("Results: {count}");

    let best = text
        .split('\n')
        .skip_while(|line| {
            !(line.starts_with("Source: ")
                && line.ends_with("(vector search rank: #1, chunk: 1)"))
        })
        .skip_while(|line| !line.is_empty())
        .nth(1);
    let Some((name, _)) = best.and_then(|line| line.split_once(": ")) else {
        return Err(format!("The reply had no closest match: {}", shorten(&text)).into());
    };
    println!("Best match: {name}");
    Ok(())
}
// --8<-- [end:search]

// --8<-- [start:main]
/// Makes the search. The ? operator returns any error to the caller.
fn run() -> Result<(), BoxError> {
    if token().is_empty() {
        return Err("MCP_TOKEN must be set".into());
    }
    let client = Client::builder().timeout(TIMEOUT).build()?;
    search(&client)
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
