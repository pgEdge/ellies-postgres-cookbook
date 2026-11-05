// Ellie's Postgres Cookbook
// Calling AI DBA Workbench MCP tools, using reqwest and serde_json.
//
// Copyright (c) 2026, pgEdge, Inc.
// This code is released under the PostgreSQL License.

// --8<-- [start:imports]
use std::env;
use std::error::Error;
use std::process::ExitCode;
use std::sync::LazyLock;
use std::time::Duration;

use reqwest::blocking::Client;
use serde_json::{json, Value};
// --8<-- [end:imports]

// --8<-- [start:config]
/// Any error, boxed, so that a function can return errors of several types
/// with the ? operator.
type Result<T> = std::result::Result<T, Box<dyn Error>>;

/// The settings that the program reads from the environment.
struct Settings {
    base_url: String,
    token: String,
    connection_id: u64,
}

/// Returns the value of an environment variable, if it is set and not
/// empty; an empty variable counts as unset.
fn env_value(name: &str) -> Option<String> {
    env::var(name).ok().filter(|value| !value.is_empty())
}

/// Reads the settings from the environment.
fn settings() -> Result<Settings> {
    let (Some(token), Some(connection_id)) = (
        env_value("WORKBENCH_TOKEN"),
        env_value("WORKBENCH_CONNECTION_ID"),
    ) else {
        return Err("WORKBENCH_TOKEN and WORKBENCH_CONNECTION_ID must be set".into());
    };
    let connection_id = connection_id
        .parse()
        .map_err(|_| "WORKBENCH_CONNECTION_ID must be a number")?;
    let base_url = env_value("WORKBENCH_URL")
        .unwrap_or_else(|| "http://localhost:8080".to_string())
        .trim_end_matches('/')
        .to_string();
    Ok(Settings {
        base_url,
        token,
        connection_id,
    })
}
// --8<-- [end:config]

// --8<-- [start:rpc]
/// One client serves every request, with a timeout for each; the client
/// has none by default.
static CLIENT: LazyLock<Client> = LazyLock::new(|| {
    Client::builder()
        .timeout(Duration::from_secs(30))
        .build()
        .expect("could not create the HTTP client")
});

/// Sends a JSON-RPC request to the MCP endpoint and returns the result.
/// The server answers a JSON-RPC error with HTTP status 200, so the
/// function checks the reply for an error member as well as for an HTTP
/// failure.
fn rpc(cfg: &Settings, method: &str, params: Value) -> Result<Value> {
    let response = CLIENT
        .post(format!("{}/mcp/v1", cfg.base_url))
        .bearer_auth(&cfg.token)
        .json(&json!({ "jsonrpc": "2.0", "id": 1, "method": method, "params": params }))
        .send()?;
    let status = response.status().as_u16();
    if status >= 400 {
        let text = response.text()?;
        return Err(format!("{method} failed with status {status}: {}", text.trim()).into());
    }
    let mut reply: Value = response.json()?;
    if let Some(error) = reply.get("error") {
        let message = error["message"].as_str().unwrap_or_default();
        return Err(format!("{method} failed: {message}").into());
    }
    match reply.get_mut("result") {
        Some(result) => Ok(result.take()),
        None => Err(format!("{method} had no result").into()),
    }
}
// --8<-- [end:rpc]

// --8<-- [start:initialize]
/// Introduces the client to the server and prints the server's name and
/// version. The Workbench keeps no session, so a client can skip this
/// step.
fn initialize(cfg: &Settings) -> Result<()> {
    let result = rpc(
        cfg,
        "initialize",
        json!({
            "protocolVersion": "2024-11-05",
            "capabilities": {},
            "clientInfo": { "name": "cookbook", "version": "1.0.0" },
        }),
    )?;
    let info = &result["serverInfo"];
    let name = info["name"]
        .as_str()
        .ok_or("the reply had no server name")?;
    let version = info["version"]
        .as_str()
        .ok_or("the reply had no server version")?;
    println!("Server: {name} {version}");
    Ok(())
}
// --8<-- [end:initialize]

// --8<-- [start:list_tools]
/// Lists the tools, checks that the two that the program calls are
/// present, and prints the arguments that each one requires.
fn list_tools(cfg: &Settings) -> Result<()> {
    let result = rpc(cfg, "tools/list", json!({}))?;
    let tools = result["tools"].as_array().ok_or("the reply had no tools")?;
    // The server lists its tools in no fixed order, so look the two tools
    // up by name.
    for name in ["query_database", "execute_explain"] {
        let tool = tools
            .iter()
            .find(|t| t["name"] == name)
            .ok_or(format!("the server does not offer {name}"))?;
        let required: Vec<&str> = tool["inputSchema"]["required"]
            .as_array()
            .ok_or("the tool lists no required arguments")?
            .iter()
            .filter_map(Value::as_str)
            .collect();
        println!("{name} requires: {}", required.join(", "));
    }
    Ok(())
}
// --8<-- [end:list_tools]

// --8<-- [start:call_tool]
/// Calls a tool and returns the text of its reply. A tool that fails
/// returns a normal result with isError set, so the function checks that
/// flag too.
fn call_tool(cfg: &Settings, name: &str, arguments: Value) -> Result<String> {
    let result = rpc(
        cfg,
        "tools/call",
        json!({ "name": name, "arguments": arguments }),
    )?;
    let text = result["content"][0]["text"]
        .as_str()
        .ok_or("the reply had no text")?;
    if result["isError"].as_bool().unwrap_or(false) {
        return Err(format!("{name} failed: {text}").into());
    }
    Ok(text.to_string())
}
// --8<-- [end:call_tool]

// --8<-- [start:query_database]
/// Runs a harmless read-only query with query_database and prints the
/// column names and the rows. The reply is text that starts with the
/// connection and the query, and then has a "Results" line followed by the
/// rows in tab-separated form, so the function prints only what follows
/// that line.
fn query_database(cfg: &Settings) -> Result<()> {
    let text = call_tool(
        cfg,
        "query_database",
        json!({
            "connection_id": cfg.connection_id,
            "query": "SELECT 'Hello from the Workbench' AS greeting, 6 * 7 AS answer",
        }),
    )?;
    let (_, results) = text
        .split_once("\nResults")
        .ok_or("the reply had no results")?;
    // Skip the rest of the Results line, then turn the tabs into commas.
    let lines = results.split('\n').skip(1).filter(|line| !line.is_empty());
    for (number, line) in lines.enumerate() {
        let label = if number == 0 { "Columns" } else { "Row" };
        let values: Vec<&str> = line.split('\t').collect();
        println!("{label}: {}", values.join(", "));
    }
    Ok(())
}
// --8<-- [end:query_database]

// --8<-- [start:execute_explain]
/// Plans a query with execute_explain, without running it, and prints the
/// type of the first node of the plan. Setting analyze to true would run
/// the query.
fn execute_explain(cfg: &Settings) -> Result<()> {
    let text = call_tool(
        cfg,
        "execute_explain",
        json!({
            "connection_id": cfg.connection_id,
            "query": "SELECT 1 + 1",
            "analyze": false,
        }),
    )?;
    // The plan follows a line of equals signs. The standard library has no
    // regular expressions, so find the line after it by hand.
    let mut lines = text
        .split_once("Execution Plan:\n")
        .ok_or("the reply had no execution plan")?
        .1
        .split('\n');
    let rule = lines.next().unwrap_or_default();
    if rule.is_empty() || !rule.chars().all(|c| c == '=') {
        return Err("the reply had no execution plan".into());
    }
    let node = lines
        .next()
        .and_then(|line| line.split(char::is_whitespace).next())
        .filter(|node| !node.is_empty())
        .ok_or("the reply had no execution plan")?;
    println!("Plan starts with: {node}");
    Ok(())
}
// --8<-- [end:execute_explain]

// --8<-- [start:main]
/// Prints an error with the chain of underlying causes, because the
/// top-level error is often generic ("error sending request").
fn report(e: &dyn Error) {
    eprintln!("Error: {e}");
    let mut cause = e.source();
    while let Some(c) = cause {
        eprintln!("  caused by: {c}");
        cause = c.source();
    }
}

fn run() -> Result<()> {
    let cfg = settings()?;
    initialize(&cfg)?;
    list_tools(&cfg)?;
    query_database(&cfg)?;
    execute_explain(&cfg)?;
    Ok(())
}

fn main() -> ExitCode {
    match run() {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            report(e.as_ref());
            ExitCode::FAILURE
        }
    }
}
// --8<-- [end:main]
