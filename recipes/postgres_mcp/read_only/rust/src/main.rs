// Ellie's Postgres Cookbook
// Running read-only queries through the pgEdge Postgres MCP Server, using
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

/// Calls a tool with tools/call and returns the text of its reply and
/// whether the tool failed, which it reports by setting isError. The
/// server answers a JSON-RPC error with HTTP status 200, so the function
/// checks the reply for an error member as well as the HTTP status.
fn call_tool(client: &Client, name: &str, arguments: Value) -> Result<(String, bool), BoxError> {
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
    Ok((text.to_string(), result["isError"].as_bool() == Some(true)))
}
// --8<-- [end:config]

// --8<-- [start:select]
/// Runs a SELECT with query_database, and prints the column names and each
/// row. The reply repeats the query, with the LIMIT that the server adds,
/// and then has a line such as "Results (3 rows):", a header line, and one
/// line for each row, with the values separated by tabs. The server writes
/// a tab or a newline inside a value as \t or \n, and a NULL as an empty
/// string.
fn select_cheap_products(client: &Client) -> Result<(), BoxError> {
    let (text, failed) = call_tool(
        client,
        "query_database",
        json!({
            "query": "SELECT name, price FROM cookbook_mcp.products \
                      WHERE price < 100 ORDER BY price",
        }),
    )?;
    if failed {
        return Err(format!("query_database failed: {text}").into());
    }
    let mut lines = text.split('\n').skip_while(|line| !line.starts_with("Results "));
    let (Some(_), Some(header)) = (lines.next(), lines.next()) else {
        return Err(format!("Unexpected reply: {}", shorten(&text)).into());
    };
    println!("Columns: {}", header.replace('\t', ", "));
    for line in lines.filter(|line| !line.is_empty()) {
        println!("Row: {}", line.replace('\t', ", "));
    }
    Ok(())
}
// --8<-- [end:select]

// --8<-- [start:insert]
/// Tries to add a row. query_database runs every query in a read-only
/// transaction, so PostgreSQL itself refuses the INSERT with SQLSTATE
/// 25006, and the tool returns the error with isError set to true. The
/// INSERT leaves out id, which the table requires, so that even a server
/// that allows writes would refuse it rather than save a row. That is
/// why the function checks for the read-only error itself rather than
/// for any error, and fails if the write succeeds or fails for another
/// reason. It prints only the last line of the error, which holds
/// PostgreSQL's message, because some errors start with the query.
fn try_insert(client: &Client) -> Result<(), BoxError> {
    let (text, failed) = call_tool(
        client,
        "query_database",
        json!({
            "query": "INSERT INTO cookbook_mcp.products \
                      (name, category, price, in_stock, description) \
                      VALUES ('Acme Test Widget', 'Testing', 1.00, true, \
                      'A made-up product that is never saved')",
        }),
    )?;
    let error_line = text.trim().lines().last().unwrap_or("");
    if !failed {
        return Err("The server accepted a write".into());
    }
    if !text.contains("SQLSTATE 25006") {
        return Err(format!("The INSERT failed for another reason: {error_line}").into());
    }
    println!("INSERT rejected: {error_line}");
    Ok(())
}
// --8<-- [end:insert]

// --8<-- [start:main]
/// Makes the two calls. The ? operator returns any error to the caller.
fn run() -> Result<(), BoxError> {
    if token().is_empty() {
        return Err("MCP_TOKEN must be set".into());
    }
    let client = Client::builder().timeout(TIMEOUT).build()?;
    select_cheap_products(&client)?;
    try_insert(&client)
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
