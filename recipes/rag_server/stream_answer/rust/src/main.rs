// Ellie's Postgres Cookbook
// Streaming an answer from the pgEdge RAG Server, using reqwest and
// serde_json.
//
// These examples are for pgEdge RAG Server 2.0.0.
//
// Copyright (c) 2026, pgEdge, Inc.
// This code is released under the PostgreSQL License.

// --8<-- [start:imports]
use std::env;
use std::error::Error;
use std::io::{self, BufRead, BufReader, Read, Write};
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

/// The blocking client applies the timeout to the wait for the response
/// and to each wait for data, rather than to the whole stream, but the
/// server may wait for the language model to begin, and a small model on a
/// modest machine can take a while, so allow plenty of time.
const TIMEOUT: Duration = Duration::from_secs(300);
// --8<-- [end:config]

// --8<-- [start:events]
/// The errors that the functions below return; a string converts into one
/// with the ? operator or into().
type BoxError = Box<dyn Error>;

/// Parses Server-Sent Events from a reader, and passes the JSON that the
/// data of each event holds to handle, as each event arrives.
///
/// An event is one or more "data:" lines followed by a blank line. The
/// stream may end without the final blank line, so the last event is sent
/// when the lines run out as well.
fn read_events(reader: impl BufRead, mut handle: impl FnMut(Value)) -> Result<(), BoxError> {
    let mut data: Vec<String> = Vec::new();
    for line in reader.lines() {
        let line = line?;
        if line.is_empty() {
            if !data.is_empty() {
                handle(serde_json::from_str(&data.join("\n"))?);
                data.clear();
            }
        } else if let Some(value) = line.strip_prefix("data:") {
            // A single space after the colon is not part of the data.
            data.push(value.strip_prefix(' ').unwrap_or(value).to_string());
        }
        // Comment lines (which start with a colon) and other fields are
        // ignored.
    }
    if !data.is_empty() {
        handle(serde_json::from_str(&data.join("\n"))?);
    }
    Ok(())
}
// --8<-- [end:events]

// --8<-- [start:stream]
/// Describes an error response, which carries a JSON body of the form
/// {"error": {"code": "...", "message": "..."}}.
fn error_text(body: &str) -> String {
    // A body that is not JSON becomes Null, and indexing Null (or any
    // missing field) gives Null again, which as_str() turns into None.
    let reply: Value = serde_json::from_str(body).unwrap_or(Value::Null);
    let error = &reply["error"];
    match (error["code"].as_str(), error["message"].as_str()) {
        (Some(code), message) => format!("{code}: {}", message.unwrap_or("")),
        _ => body.trim().chars().take(200).collect(),
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

/// Prints the answer as it arrives, and returns the number of chunks.
fn stream_answer(client: &Client, question: &str) -> Result<u32, BoxError> {
    // send() returns as soon as the headers arrive, and the response can
    // then be read as the server sends the body.
    let response = client
        .post(pipeline_url(&pipeline())?)
        .json(&json!({ "query": question, "stream": true }))
        .send()?;

    // A request the server rejects gets an ordinary error status. Once
    // streaming starts the status is always 200, so later failures arrive
    // as events instead.
    let status = response.status();
    if !status.is_success() {
        let mut body = String::new();
        response.take(4096).read_to_string(&mut body)?;
        return Err(format!("HTTP {}, {}", status.as_u16(), error_text(&body)).into());
    }

    let mut chunks = 0;
    let mut error: Option<String> = None;
    let mut done = false;
    let mut stdout = io::stdout();

    read_events(BufReader::new(response), |event| {
        match event["type"].as_str() {
            Some("chunk") => {
                // The last chunk has no content.
                let content = event["content"].as_str().unwrap_or("");
                if !content.is_empty() {
                    // Rust buffers standard output by line, so flush it to
                    // show each chunk at once.
                    print!("{content}");
                    let _ = stdout.flush();
                    chunks += 1;
                }
            }
            Some("error") => {
                let message = event["error"].as_str().unwrap_or("");
                error = Some(if message.is_empty() { "unknown error" } else { message }.to_string());
            }
            Some("done") => done = true,
            _ => {}
        }
    })?;

    println!();
    // The server sends a done event after an error event, so keep reading
    // until the stream ends before reporting the error.
    if let Some(error) = error {
        return Err(format!("The stream reported an error: {error}").into());
    }
    if !done {
        return Err("The stream ended before the done event".into());
    }
    Ok(chunks)
}
// --8<-- [end:stream]

// --8<-- [start:main]
/// Asks the question and prints the answer as it streams in. The ?
/// operator returns any error to the caller.
fn run() -> Result<(), BoxError> {
    let client = Client::builder().timeout(TIMEOUT).build()?;

    println!("Question: {QUESTION}");
    println!("Answer:");
    let chunks = stream_answer(&client, QUESTION)?;
    println!("Chunks received: {chunks}");
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
