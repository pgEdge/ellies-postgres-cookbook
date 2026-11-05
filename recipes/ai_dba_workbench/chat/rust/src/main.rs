// Ellie's Postgres Cookbook
// Chatting with the LLM through the AI DBA Workbench API, using reqwest
// and serde_json.
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
use reqwest::Method;
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
}

/// Returns the value of an environment variable, if it is set and not
/// empty; an empty variable counts as unset.
fn env_value(name: &str) -> Option<String> {
    env::var(name).ok().filter(|value| !value.is_empty())
}

/// Reads the settings from the environment.
fn settings() -> Result<Settings> {
    let token = env_value("WORKBENCH_TOKEN").ok_or("WORKBENCH_TOKEN must be set")?;
    let base_url = env_value("WORKBENCH_URL")
        .unwrap_or_else(|| "http://localhost:8080".to_string())
        .trim_end_matches('/')
        .to_string();
    Ok(Settings { base_url, token })
}
// --8<-- [end:config]

// --8<-- [start:request]
/// One client serves every request. A small model on a CPU can take a
/// while to answer, so the timeout is generous.
static CLIENT: LazyLock<Client> = LazyLock::new(|| {
    Client::builder()
        .timeout(Duration::from_secs(300))
        .build()
        .expect("could not create the HTTP client")
});

/// Sends a request to the API and returns the JSON reply. A request that
/// the server rejects returns an error that includes the message from the
/// server.
fn api(cfg: &Settings, method: Method, path: &str, body: Option<&Value>) -> Result<Value> {
    let mut request = CLIENT
        .request(method.clone(), format!("{}/api/v1{path}", cfg.base_url))
        .bearer_auth(&cfg.token);
    if let Some(body) = body {
        request = request.json(body);
    }

    let response = request.send()?;
    let status = response.status().as_u16();
    if status >= 400 {
        let text = response.text()?;
        return Err(format!(
            "{method} {path} failed with status {status}: {}",
            text.trim()
        )
        .into());
    }
    Ok(response.json()?)
}
// --8<-- [end:request]

// --8<-- [start:providers]
/// Prints the default provider and model, which the chat endpoint uses
/// when a request names neither.
fn show_provider(cfg: &Settings) -> Result<()> {
    let reply = api(cfg, Method::GET, "/llm/providers", None)?;
    let default = reply["providers"]
        .as_array()
        .and_then(|providers| providers.iter().find(|p| p["isDefault"] == true))
        .ok_or("the Workbench has no default LLM provider")?;
    let name = default["name"].as_str().ok_or("the provider had no name")?;
    let model = reply["defaultModel"]
        .as_str()
        .ok_or("the reply had no default model")?;
    println!("Provider: {name} (model {model})");
    Ok(())
}
// --8<-- [end:providers]

// --8<-- [start:chat]
/// Sends a conversation to the model and returns the reply. The messages
/// are the conversation so far, each with a role of user or assistant and
/// some content.
fn chat(cfg: &Settings, messages: &[Value]) -> Result<Value> {
    api(
        cfg,
        Method::POST,
        "/llm/chat",
        Some(&json!({ "messages": messages })),
    )
}

/// Returns the text of a reply on a single line. A small model may spread
/// its answer over several lines, so the function joins the text blocks
/// and collapses the white space. It fails when the reply holds no text.
fn reply_text(reply: &Value) -> Result<String> {
    let blocks: Vec<&str> = reply["content"]
        .as_array()
        .map(Vec::as_slice)
        .unwrap_or_default()
        .iter()
        .filter(|b| b["type"] == "text")
        .filter_map(|b| b["text"].as_str())
        .collect();
    let joined = blocks.join(" ");
    let text = joined.split_whitespace().collect::<Vec<_>>().join(" ");
    if text.is_empty() {
        return Err("the model returned no text".into());
    }
    Ok(text)
}
// --8<-- [end:chat]

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
    show_provider(&cfg)?;

    // The first message starts the conversation.
    let question = "Name one type of PostgreSQL index, in one sentence.";
    let mut messages = vec![json!({ "role": "user", "content": question })];
    let text = reply_text(&chat(&cfg, &messages)?)?;
    println!("Reply: {text}");

    // The server keeps no conversation, so the follow-up repeats the
    // earlier messages, including the model's reply, and adds the new
    // question.
    messages.push(json!({ "role": "assistant", "content": text }));
    messages.push(json!({ "role": "user", "content": "Summarise your answer in five words." }));
    let follow_up = chat(&cfg, &messages)?;
    println!("Follow-up reply: {}", reply_text(&follow_up)?);
    let stop_reason = follow_up["stop_reason"].as_str().unwrap_or_default();
    println!("Stop reason: {stop_reason}");
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
