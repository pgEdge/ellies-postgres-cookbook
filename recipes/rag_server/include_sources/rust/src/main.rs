// Ellie's Postgres Cookbook
// Showing the documents behind a pgEdge RAG Server answer, using reqwest
// and serde_json.
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

const QUESTION: &str = "How long does the Acme Widget 2.0 take to charge?";

/// The server waits for the language model before it replies, and a small
/// model on a modest machine can take a while, so allow plenty of time.
const TIMEOUT: Duration = Duration::from_secs(300);
// --8<-- [end:config]

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

/// Sends the question to the pipeline, and asks for the documents that the
/// answer came from as well. Returns the decoded reply.
fn ask(client: &Client, question: &str) -> Result<Value, BoxError> {
    let response = client
        .post(pipeline_url(&pipeline())?)
        .json(&json!({ "query": question, "include_sources": true }))
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

// --8<-- [start:sources]
/// Returns one line for a source: its ID and the start of its text.
fn describe_source(source: &Value) -> String {
    // Collapse any line breaks, and shorten long text for display. The
    // length counts characters rather than bytes.
    let mut content = source["content"]
        .as_str()
        .unwrap_or("")
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ");
    if content.chars().count() > 60 {
        content = content.chars().take(57).collect::<String>() + "...";
    }
    format!("- {}: {content}", source["id"].as_str().unwrap_or("(no id)"))
}

/// Prints the sources in a reply, in the order the server returns.
fn print_sources(reply: &Value) {
    // The server leaves out the sources array, without an error, when the
    // pipeline does not set allow_include_sources.
    let sources = match reply["sources"].as_array() {
        Some(sources) if !sources.is_empty() => sources,
        _ => {
            println!("No sources were returned. Does the pipeline set allow_include_sources?");
            return;
        }
    };

    println!("Sources ({}):", sources.len());
    for source in sources {
        println!("{}", describe_source(source));
    }
}
// --8<-- [end:sources]

// --8<-- [start:main]
/// Asks the question and prints the reply. The ? operator returns any
/// error to the caller.
fn run() -> Result<(), BoxError> {
    let client = Client::builder().timeout(TIMEOUT).build()?;
    let reply = ask(&client, QUESTION)?;

    println!("Question: {QUESTION}");
    println!("Answer:\n{}", reply["answer"].as_str().unwrap_or(""));
    print_sources(&reply);
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
