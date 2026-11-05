// Ellie's Postgres Cookbook
// Handling errors from the pgEdge RAG Server, using reqwest and
// serde_json.
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
    env_or("RAG_PIPELINE", "cookbook")
}

/// A pipeline name that no server has, to cause PIPELINE_NOT_FOUND.
const MISSING_PIPELINE: &str = "no-such-pipeline";

/// The server rejects both requests before it calls a language model, so
/// they answer quickly.
const TIMEOUT: Duration = Duration::from_secs(30);
// --8<-- [end:config]

// --8<-- [start:request]
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

/// The outcome of a query that reached the server: an ApiError when the
/// server replied with an error, or any other error when the reply could
/// not be had or understood.
enum QueryError {
    Api(ApiError),
    Other(BoxError),
}

/// Lets the ? operator turn any other error into QueryError::Other.
impl<E: Into<BoxError>> From<E> for QueryError {
    fn from(e: E) -> Self {
        QueryError::Other(e.into())
    }
}

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

/// Sends a query to a pipeline, and returns the decoded reply. Returns
/// QueryError::Api when the server replies with an error.
fn send_query(client: &Client, pipeline: &str, query: &str) -> Result<Value, QueryError> {
    let response = client
        .post(pipeline_url(pipeline)?)
        .json(&json!({ "query": query }))
        .send()?;
    let status = response.status();
    let body = response.text()?;

    let reply: Value = match serde_json::from_str(&body) {
        Ok(reply) => reply,
        Err(_) => return Err(format!("HTTP {}, {}", status.as_u16(), shorten(&body)).into()),
    };

    if !status.is_success() {
        let error = &reply["error"];
        return match (error["code"].as_str(), error["message"].as_str()) {
            (Some(code), Some(message)) => Err(QueryError::Api(ApiError {
                status: status.as_u16(),
                code: code.to_string(),
                message: message.to_string(),
            })),
            _ => Err(format!("HTTP {}, {}", status.as_u16(), shorten(&body)).into()),
        };
    }
    Ok(reply)
}
// --8<-- [end:request]

// --8<-- [start:advise]
/// Returns advice for an error, chosen by the error code. Branch on the
/// code rather than on the message, which is meant for people and may
/// change; branch on the HTTP status only for the temporary failures that
/// have no code worth handling individually.
fn advise(err: &ApiError) -> String {
    match (err.code.as_str(), err.status) {
        ("PIPELINE_NOT_FOUND", _) => {
            "Check the pipeline name; GET /v1/pipelines lists the pipelines.".to_string()
        }
        ("INVALID_REQUEST", _) => {
            "Fix the request; the body must be JSON with a non-empty query.".to_string()
        }
        (_, 503 | 504) => "The failure may be temporary, so retry the request later.".to_string(),
        (code, _) => format!("This program does not handle {code}."),
    }
}
// --8<-- [end:advise]

// --8<-- [start:main]
/// Sends one query that the server must refuse with the expected error
/// code, and prints how the program handles the refusal. Any other outcome
/// is a failure.
fn demonstrate(
    client: &Client,
    title: &str,
    pipeline: &str,
    query: &str,
    expected: &str,
) -> Result<(), BoxError> {
    println!("{title}");
    match send_query(client, pipeline, query) {
        Err(QueryError::Api(e)) => {
            println!("  {} (HTTP {}): {}", e.code, e.status, e.message);
            println!("  {}", advise(&e));
            if e.code != expected {
                return Err(format!("expected {expected}, got {}", e.code).into());
            }
            Ok(())
        }
        Err(QueryError::Other(e)) => Err(e),
        Ok(_) => Err("the request unexpectedly succeeded".into()),
    }
}

/// Sends the two queries. The ? operator returns any error to the caller.
fn run() -> Result<(), BoxError> {
    let client = Client::builder().timeout(TIMEOUT).build()?;
    demonstrate(
        &client,
        "Asking a pipeline that does not exist",
        MISSING_PIPELINE,
        "Hello",
        "PIPELINE_NOT_FOUND",
    )?;
    demonstrate(&client, "Asking an empty question", &pipeline(), "", "INVALID_REQUEST")
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
