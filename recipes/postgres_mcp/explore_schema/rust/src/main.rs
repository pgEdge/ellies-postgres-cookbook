// Ellie's Postgres Cookbook
// Exploring a schema through the pgEdge Postgres MCP Server, using reqwest
// and serde_json.
//
// These examples are for pgEdge Postgres MCP Server 1.1.0.
//
// Copyright (c) 2026, pgEdge, Inc.
// This code is released under the PostgreSQL License.

// --8<-- [start:imports]
use std::collections::HashMap;
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

// The schema and table that scripts/start_postgres_mcp.sh creates.
const SCHEMA: &str = "cookbook_mcp";
const TABLE: &str = "products";

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

// --8<-- [start:parse_tsv]
/// Reads the table in a tool's reply into a list of rows, each a map keyed
/// by column name. The reply starts with a line or two about the database,
/// and then has a header line and one line for each row, with the values
/// separated by tabs. The server writes a tab or a newline inside a value
/// as \t or \n, so splitting on them is safe. The header is the first line
/// that starts with "schema", the first column of every table that
/// get_schema_info returns.
fn parse_tsv(text: &str) -> Result<Vec<HashMap<String, String>>, BoxError> {
    let mut lines = text.split('\n').skip_while(|line| !line.starts_with("schema\t"));
    let Some(header) = lines.next() else {
        return Err(format!("The reply had no table: {}", shorten(text)).into());
    };
    let header: Vec<&str> = header.split('\t').collect();
    Ok(lines
        .filter(|line| !line.is_empty())
        .map(|line| {
            header
                .iter()
                .zip(line.split('\t'))
                .map(|(name, value)| (name.to_string(), value.to_string()))
                .collect()
        })
        .collect())
}

/// Returns a column of a row, or an empty string if the row lacks it.
fn column<'a>(row: &'a HashMap<String, String>, name: &str) -> &'a str {
    row.get(name).map(String::as_str).unwrap_or("")
}
// --8<-- [end:parse_tsv]

// --8<-- [start:list_tables]
/// Lists the tables in the schema with their comments. With compact set to
/// true, get_schema_info returns one line for each table, without its
/// columns, which suits a first look at a large database.
fn list_tables(client: &Client) -> Result<(), BoxError> {
    let text = call_tool(
        client,
        "get_schema_info",
        json!({"schema_name": SCHEMA, "compact": true}),
    )?;
    println!("Tables in {SCHEMA}:");
    for row in parse_tsv(&text)? {
        let comment = match column(&row, "table_desc") {
            "" => "(no comment)",
            comment => comment,
        };
        println!("- {}: {comment}", column(&row, "table"));
    }
    Ok(())
}
// --8<-- [end:list_tables]

// --8<-- [start:describe_table]
/// Lists the columns of one table with their types. Given a table_name,
/// get_schema_info returns one line for each column, which also carries
/// the table's details.
fn describe_table(client: &Client) -> Result<(), BoxError> {
    let text = call_tool(
        client,
        "get_schema_info",
        json!({"schema_name": SCHEMA, "table_name": TABLE}),
    )?;
    let rows = parse_tsv(&text)?;
    if rows.is_empty() {
        return Err(format!("{SCHEMA}.{TABLE} has no columns").into());
    }
    println!("Columns of {SCHEMA}.{TABLE}:");
    for row in &rows {
        let key = if column(row, "is_pk") == "true" { " (primary key)" } else { "" };
        println!("- {}: {}{key}", column(row, "column"), column(row, "data_type"));
    }
    Ok(())
}
// --8<-- [end:describe_table]

// --8<-- [start:count_rows]
/// Counts the products in stock with count_rows. The where argument is a
/// condition without the WHERE keyword; the server rejects one that
/// contains a subquery.
fn count_in_stock(client: &Client) -> Result<(), BoxError> {
    let text = call_tool(
        client,
        "count_rows",
        json!({"schema": SCHEMA, "table": TABLE, "where": "in_stock"}),
    )?;
    // The reply ends with a line such as "Count: 4".
    let count = text
        .lines()
        .filter_map(|line| line.strip_prefix("Count: "))
        .find(|count| !count.is_empty() && count.chars().all(|c| c.is_ascii_digit()));
    let Some(count) = count else {
        return Err(format!("The reply had no count: {}", shorten(&text)).into());
    };
    println!("Products in stock: {count}");
    Ok(())
}
// --8<-- [end:count_rows]

// --8<-- [start:main]
/// Makes the three calls. The ? operator returns any error to the caller.
fn run() -> Result<(), BoxError> {
    if token().is_empty() {
        return Err("MCP_TOKEN must be set".into());
    }
    let client = Client::builder().timeout(TIMEOUT).build()?;
    list_tables(&client)?;
    describe_table(&client)?;
    count_in_stock(&client)
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
