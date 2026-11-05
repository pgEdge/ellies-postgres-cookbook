// Ellie's Postgres Cookbook
// Finding the task that created a pgEdge Control Plane database, and
// following its log until the task finishes, using reqwest and serde_json.
//
// These examples are for the Control Plane v0.11.0.
//
// Copyright (c) 2026, pgEdge, Inc.
// This code is released under the PostgreSQL License.

// --8<-- [start:imports]
use std::env;
use std::error::Error;
use std::process::ExitCode;
use std::thread;
use std::time::{Duration, Instant};

use reqwest::blocking::Client;
use serde_json::Value;
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
    env_or("CONTROL_PLANE_URL", "http://localhost:3000")
        .trim_end_matches('/')
        .to_string()
}

fn database_id() -> String {
    env_or("CONTROL_PLANE_DATABASE_ID", "cookbook")
}

const TIMEOUT: Duration = Duration::from_secs(30);

// How long to follow a task that is still running, and how often to check.
const FOLLOW_FOR: Duration = Duration::from_secs(600);
const POLL_INTERVAL: Duration = Duration::from_secs(5);

/// The statuses after which a task does not change again.
const FINAL_STATUSES: [&str; 3] = ["completed", "failed", "canceled"];

/// The errors that the functions below return; a string converts into one
/// with the ? operator or into().
type BoxError = Box<dyn Error>;

/// Returns at most the first 200 characters of a reply.
fn shorten(text: &str) -> String {
    text.chars().take(200).collect()
}

/// Fetches a path from the server, and returns the decoded reply.
fn get(client: &Client, path: &str) -> Result<Value, BoxError> {
    let response = client.get(format!("{}{path}", base_url())).send()?;
    let status = response.status();
    let body = response.text()?;
    if !status.is_success() {
        return Err(format!("HTTP {}, {}", status.as_u16(), shorten(&body)).into());
    }
    match serde_json::from_str::<Value>(&body) {
        Ok(reply) if reply.is_object() => Ok(reply),
        _ => Err(format!("Unexpected response: {}", shorten(&body)).into()),
    }
}
// --8<-- [end:config]

// --8<-- [start:list]
/// Returns the ID of the task that created the database. Every create,
/// update and delete runs as a task. The IDs sort by creation time, and
/// sort_order=asc lists the oldest task first.
fn find_create_task(client: &Client) -> Result<String, BoxError> {
    let path = format!("/v1/databases/{}/tasks?sort_order=asc", database_id());
    let reply = get(client, &path)?;
    let tasks = reply["tasks"].as_array().cloned().unwrap_or_default();
    tasks
        .iter()
        .find(|task| task["type"] == "create")
        .and_then(|task| task["task_id"].as_str())
        .map(str::to_string)
        .ok_or_else(|| format!("no create task for {}", database_id()).into())
}
// --8<-- [end:list]

// --8<-- [start:follow]
/// Prints the log of a task as it grows, until the task finishes, and
/// returns its final status. Each log reply carries last_entry_id, and
/// passing that back as after_entry_id fetches only the newer entries.
/// The status is read before the log, so that once it is final, the log
/// that follows it is complete.
fn follow_task(client: &Client, task_id: &str) -> Result<String, BoxError> {
    let path = format!("/v1/databases/{}/tasks/{task_id}", database_id());
    let deadline = Instant::now() + FOLLOW_FOR;
    let mut after = String::new();
    loop {
        let task = get(client, &path)?;
        let status = task["status"].as_str().unwrap_or("unknown").to_string();

        // Entry IDs are UUIDs, so they need no escaping in a URL.
        let query = if after.is_empty() {
            String::new()
        } else {
            format!("?after_entry_id={after}")
        };
        let log = get(client, &format!("{path}/log{query}"))?;
        for entry in log["entries"].as_array().into_iter().flatten() {
            println!("Log: {}", entry["message"].as_str().unwrap_or(""));
        }
        if let Some(last) = log["last_entry_id"].as_str().filter(|s| !s.is_empty()) {
            after = last.to_string();
        }

        if FINAL_STATUSES.contains(&status.as_str()) {
            return Ok(status);
        }
        if Instant::now() >= deadline {
            return Err(format!(
                "task {task_id} was still {status} after {} seconds",
                FOLLOW_FOR.as_secs()
            )
            .into());
        }
        thread::sleep(POLL_INTERVAL);
    }
}
// --8<-- [end:follow]

// --8<-- [start:main]
/// Finds the task and follows it, and returns its final status. The ?
/// operator returns any error to the caller.
fn run() -> Result<String, BoxError> {
    let client = Client::builder().timeout(TIMEOUT).build()?;
    let task_id = find_create_task(&client)?;
    println!("Task: create");
    follow_task(&client, &task_id)
}

/// Reports any error returned by run() and exits with a failure status.
/// The top-level error is often generic ("error sending request"), so the
/// chain of underlying causes is printed too.
fn main() -> ExitCode {
    match run() {
        Ok(status) => {
            println!("Status: {status}");
            if status == "completed" {
                ExitCode::SUCCESS
            } else {
                ExitCode::FAILURE
            }
        }
        Err(e) => {
            eprintln!("Control Plane error: {e}");
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
