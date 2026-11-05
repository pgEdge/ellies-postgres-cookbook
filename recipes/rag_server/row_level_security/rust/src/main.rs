// Ellie's Postgres Cookbook
// Answering each caller from only their own documents with the pgEdge RAG
// Server and row-level security, using reqwest and serde_json.
//
// These examples are for pgEdge RAG Server 2.0.0.
//
// Copyright (c) 2026, pgEdge, Inc.
// This code is released under the PostgreSQL License.

// --8<-- [start:imports]
use std::env;
use std::error::Error;
use std::fmt;
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
    env_or("RAG_PIPELINE", "cookbook_private")
}

const QUESTION: &str = "What is the status of my warranty claim?";

/// The callers to ask for. The fictional documents in the pipeline's table
/// belong to these two people.
const CALLERS: [&str; 2] = ["jane.doe@example.com", "john.smith@example.com"];

/// The header in which the server expects a trusted proxy to put the
/// claims of the caller. This is the server's default; the
/// identity.claims_header setting changes it.
const CLAIMS_HEADER: &str = "X-Forwarded-Claims";

/// The server waits for the language model before it replies, and a small
/// model on a modest machine can take a while, so allow plenty of time.
const TIMEOUT: Duration = Duration::from_secs(300);
// --8<-- [end:config]

// --8<-- [start:ask]
/// The errors that the functions below return; a string converts into one
/// with the ? operator or into().
type BoxError = Box<dyn Error>;

/// An error reply from the RAG Server, which has an HTTP status and a JSON
/// body of the form {"error": {"code": "...", "message": "..."}}.
#[derive(Debug)]
struct ApiError {
    status: u16,
    code: String,
    message: String,
}

impl fmt::Display for ApiError {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        write!(f, "{}: {}", self.code, self.message)
    }
}

impl Error for ApiError {}

/// Returns at most the first 200 characters of a reply.
fn shorten(text: &str) -> String {
    text.chars().take(200).collect()
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

/// Sends the question to the pipeline on behalf of a caller, and asks for
/// the documents that the answer came from. Returns the decoded reply, or
/// an ApiError, which the caller can recover with downcast_ref(), when the
/// server replies with an error. A subject of None sends no identity at
/// all.
fn ask(client: &Client, subject: Option<&str>) -> Result<Value, BoxError> {
    let mut request = client
        .post(pipeline_url(&pipeline())?)
        .json(&json!({ "query": QUESTION, "include_sources": true }));
    // The claims are a JSON object, which json! builds, so that the subject
    // needs no escaping.
    if let Some(subject) = subject {
        request = request.header(CLAIMS_HEADER, json!({ "sub": subject }).to_string());
    }
    let response = request.send()?;
    let status = response.status();
    let body = response.text()?;

    // A body that is not JSON becomes Null, and indexing Null (or any
    // missing field) gives Null again, which as_str() turns into None.
    let reply: Value = serde_json::from_str(&body).unwrap_or(Value::Null);

    if !status.is_success() {
        let error = &reply["error"];
        return match (error["code"].as_str(), error["message"].as_str()) {
            (Some(code), Some(message)) => Err(Box::new(ApiError {
                status: status.as_u16(),
                code: code.to_string(),
                message: message.to_string(),
            })),
            _ => Err(format!("HTTP {}, {}", status.as_u16(), shorten(&body)).into()),
        };
    }

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
/// Asks the question without an identity. The server must refuse with
/// IDENTITY_REQUIRED, because it never falls back to the pipeline's own
/// database role; any other outcome is a failure.
fn ask_anonymously(client: &Client) -> Result<(), BoxError> {
    println!();
    println!("Caller: (no identity)");
    let e = match ask(client, None) {
        Ok(_) => {
            return Err("the server answered without an identity; is identity.enabled set?".into())
        }
        Err(e) => e,
    };
    // Any error other than an ApiError, such as a refused connection, is
    // returned as it is.
    let Some(api) = e.downcast_ref::<ApiError>() else {
        return Err(e);
    };
    println!("{} (HTTP {})", api.code, api.status);
    if api.code != "IDENTITY_REQUIRED" {
        return Err(format!("expected IDENTITY_REQUIRED, got {api}").into());
    }
    Ok(())
}

/// Asks the question for each caller, and then without an identity. The ?
/// operator returns any error to the caller.
fn run() -> Result<(), BoxError> {
    let client = Client::builder().timeout(TIMEOUT).build()?;
    println!("Question: {QUESTION}");
    for caller in CALLERS {
        let reply = ask(&client, Some(caller))?;
        println!();
        println!("Caller: {caller}");
        show(&reply);
    }
    ask_anonymously(&client)
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
