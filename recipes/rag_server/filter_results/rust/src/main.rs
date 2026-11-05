// Ellie's Postgres Cookbook
// Filtering the documents that the pgEdge RAG Server retrieves, using
// reqwest and serde_json.
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
use reqwest::Url;
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
    env_or("RAG_SERVER_URL", "http://localhost:8080")
        .trim_end_matches('/')
        .to_string()
}

fn pipeline() -> String {
    env_or("RAG_PIPELINE", "cookbook")
}

const QUESTION: &str = "How long does the Acme Widget take to charge?";

/// The product to search, and the versions to ask about in turn. The
/// question names no version, so only the filter tells the pipeline which
/// documents to use.
const PRODUCT: &str = "Acme Widget";
const VERSIONS: [&str; 2] = ["1.0", "2.0"];

/// The server waits for the language model before it replies, and a small
/// model on a modest machine can take a while, so allow plenty of time.
const TIMEOUT: Duration = Duration::from_secs(300);
// --8<-- [end:config]

// --8<-- [start:filter]
/// Returns the filter for a product and a version. The conditions are
/// joined with AND, which is the default, and each one compares a column
/// of the pipeline's table with a value. The server passes the values to
/// PostgreSQL as parameters, so they need no escaping.
fn build_filter(product: &str, version: &str) -> Value {
    json!({
        "logic": "AND",
        "conditions": [
            { "column": "product", "operator": "=", "value": product },
            { "column": "version", "operator": "=", "value": version },
        ],
    })
}
// --8<-- [end:filter]

// --8<-- [start:ask]
/// The errors that the functions below return; a string converts into one
/// with the ? operator or into().
type BoxError = Box<dyn Error>;

/// Returns at most the first 200 characters of a reply.
fn shorten(text: &str) -> String {
    text.chars().take(200).collect()
}

/// Describes an error response, which carries a JSON body of the form
/// {"error": {"code": "...", "message": "..."}}.
fn error_text(body: &str) -> String {
    // A body that is not JSON becomes Null, and indexing Null (or any
    // missing field) gives Null again, which as_str() turns into None.
    let reply: Value = serde_json::from_str(body).unwrap_or(Value::Null);
    let error = &reply["error"];
    match (error["code"].as_str(), error["message"].as_str()) {
        (Some(code), message) => format!("{code}: {}", message.unwrap_or("")),
        _ => shorten(body.trim()),
    }
}

/// Returns the URL of a pipeline. push() escapes any character in the
/// pipeline name that is not safe in a URL path.
fn pipeline_url(name: &str) -> Result<Url, BoxError> {
    let mut url = Url::parse(&format!("{}/v1/pipelines/", base_url()))?;
    url.path_segments_mut()
        .map_err(|()| "RAG_SERVER_URL cannot be a base URL")?
        .pop_if_empty()
        .push(name);
    Ok(url)
}

/// Sends the question and the filter to the pipeline, and asks for the
/// documents that the answer came from. Returns the decoded reply.
fn ask(client: &Client, question: &str, filter: Value) -> Result<Value, BoxError> {
    let response = client
        .post(pipeline_url(&pipeline())?)
        .json(&json!({ "query": question, "filter": filter, "include_sources": true }))
        .send()?;
    let status = response.status();
    let body = response.text()?;

    // reqwest treats an error status as a normal response, so check it
    // here.
    if !status.is_success() {
        return Err(format!("HTTP {}, {}", status.as_u16(), error_text(&body)).into());
    }

    let reply: Value = serde_json::from_str(&body).unwrap_or(Value::Null);
    if !reply["answer"].is_string() {
        return Err(format!("Unexpected response: {}", shorten(&body)).into());
    }
    Ok(reply)
}
// --8<-- [end:ask]

// --8<-- [start:show]
/// Prints the answer in a reply, and then the IDs of its sources.
fn show(reply: &Value) {
    // as_array() gives None when the reply has no sources.
    let ids: Vec<&str> = reply["sources"]
        .as_array()
        .map(|sources| {
            sources
                .iter()
                .map(|source| source["id"].as_str().unwrap_or("(no id)"))
                .collect()
        })
        .unwrap_or_default();
    println!("Answer:\n{}", reply["answer"].as_str().unwrap_or(""));
    println!("Sources: {}", ids.join(", "));
}
// --8<-- [end:show]

// --8<-- [start:main]
/// Asks the question once for each version. The ? operator returns any
/// error to the caller.
fn run() -> Result<(), BoxError> {
    let client = Client::builder().timeout(TIMEOUT).build()?;
    println!("Question: {QUESTION}");
    for version in VERSIONS {
        let reply = ask(&client, QUESTION, build_filter(PRODUCT, version))?;
        println!();
        println!("Filter: product = {PRODUCT}, version = {version}");
        show(&reply);
    }
    Ok(())
}

/// Reports any error returned by run() and exits with a failure status.
/// The top-level error is often generic ("error sending request"), so the
/// chain of underlying causes is printed too.
fn main() -> ExitCode {
    match run() {
        Ok(()) => ExitCode::SUCCESS,
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
