// Ellie's Postgres Cookbook
// Holding a conversation with the pgEdge RAG Server, using reqwest and
// serde_json.
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

/// The second question does not say which version of the Acme Widget it
/// means, so only the first question and its answer, which the model
/// receives as history, settle that. The search uses only the current
/// question, which is why this one still names the product.
const QUESTIONS: [&str; 2] = [
    "How long does the Acme Widget 2.0 take to charge?",
    "And how many hours does the Acme Widget run for once it is charged?",
];

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

/// Sends a question and the conversation so far to the pipeline, and
/// returns the answer. The server keeps no conversation between requests,
/// so history lists the earlier messages, each with a role of user or
/// assistant, in order.
fn ask(client: &Client, question: &str, history: &[Value]) -> Result<String, BoxError> {
    let response = client
        .post(pipeline_url(&pipeline())?)
        .json(&json!({ "query": question, "messages": history }))
        .send()?;
    let status = response.status();
    let body = response.text()?;

    // reqwest treats an error status as a normal response, so check it
    // here.
    if !status.is_success() {
        return Err(format!("HTTP {}, {}", status.as_u16(), error_text(&body)).into());
    }

    // as_str() gives None when the answer is missing or is not a string.
    let reply: Value = serde_json::from_str(&body).unwrap_or(Value::Null);
    match reply["answer"].as_str() {
        Some(answer) => Ok(answer.to_string()),
        None => Err(format!("Unexpected response: {}", shorten(&body)).into()),
    }
}
// --8<-- [end:ask]

// --8<-- [start:converse]
/// Asks each question in turn, printing both sides of the conversation.
/// After each answer, the question and the answer join the history that
/// the next request carries.
fn converse(client: &Client) -> Result<(), BoxError> {
    let mut history: Vec<Value> = Vec::new();
    for question in QUESTIONS {
        let answer = ask(client, question, &history)?;
        println!("You: {question}");
        println!("Assistant: {answer}");
        history.push(json!({ "role": "user", "content": question }));
        history.push(json!({ "role": "assistant", "content": answer }));
    }
    Ok(())
}
// --8<-- [end:converse]

// --8<-- [start:main]
/// Holds the conversation. The ? operator returns any error to the
/// caller.
fn run() -> Result<(), BoxError> {
    let client = Client::builder().timeout(TIMEOUT).build()?;
    converse(&client)
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
