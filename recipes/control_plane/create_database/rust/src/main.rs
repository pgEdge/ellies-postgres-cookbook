// Ellie's Postgres Cookbook
// Creating a pgEdge Control Plane database on one host, waiting until it
// is available, and deleting it again, using reqwest and serde_json.
//
// These examples are for the Control Plane v0.11.0.
//
// The database runs in containers on the host until it is deleted, so
// this program deletes the database it creates on every path: after a
// success, after a failure, and after Ctrl-C.
//
// Copyright (c) 2026, pgEdge, Inc.
// This code is released under the PostgreSQL License.

// --8<-- [start:imports]
use std::env;
use std::error::Error;
use std::fmt;
use std::fs::File;
use std::io::Read;
use std::process::ExitCode;
use std::sync::atomic::{AtomicBool, Ordering};
use std::thread;
use std::time::{Duration, Instant};

use reqwest::blocking::Client;
use reqwest::Method;
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
    env_or("CONTROL_PLANE_URL", "http://localhost:3000")
        .trim_end_matches('/')
        .to_string()
}

/// The port that the new database listens on, on its host; choose one
/// that is free.
fn port() -> String {
    env_or("CONTROL_PLANE_RECIPE_PORT", "6433")
}

const TIMEOUT: Duration = Duration::from_secs(30);

// How long to wait for a database to become available, or to disappear
// after a delete, and how often to check.
const WAIT_FOR: Duration = Duration::from_secs(600);
const POLL_INTERVAL: Duration = Duration::from_secs(5);

/// Set by Ctrl-C or SIGTERM. The handler sets this flag instead of ending
/// the process, which lets the program delete its database before it
/// exits; the waits check it between requests.
static INTERRUPTED: AtomicBool = AtomicBool::new(false);

/// The errors that the functions below return; a string converts into one
/// with the ? operator or into().
type BoxError = Box<dyn Error>;

/// An error reply from the Control Plane, with its HTTP status.
#[derive(Debug)]
struct ApiError {
    status: u16,
    body: String,
}

impl fmt::Display for ApiError {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        write!(f, "HTTP {}, {}", self.status, self.body)
    }
}

impl Error for ApiError {}

/// Returns the HTTP status of an error reply, or None if no reply arrived
/// or the error is of another kind.
fn status_of(error: &BoxError) -> Option<u16> {
    error.downcast_ref::<ApiError>().map(|e| e.status)
}

/// Returns at most the first 200 characters of a reply.
fn shorten(text: &str) -> String {
    text.chars().take(200).collect()
}

/// Sends a request to the server, with the body encoded as JSON if there
/// is one, and returns the decoded reply.
fn call(client: &Client, method: Method, path: &str, body: Option<&Value>) -> Result<Value, BoxError> {
    let mut request = client.request(method, format!("{}{path}", base_url()));
    if let Some(body) = body {
        request = request.json(body);
    }
    let response = request.send()?;
    let status = response.status();
    let text = response.text()?;
    if !status.is_success() {
        return Err(ApiError { status: status.as_u16(), body: shorten(&text) }.into());
    }
    match serde_json::from_str::<Value>(&text) {
        Ok(reply) if reply.is_object() => Ok(reply),
        _ => Err(format!("Unexpected response: {}", shorten(&text)).into()),
    }
}

/// Waits for the poll interval, and fails if the user presses Ctrl-C.
fn pause() -> Result<(), BoxError> {
    let end = Instant::now() + POLL_INTERVAL;
    while Instant::now() < end {
        if INTERRUPTED.load(Ordering::SeqCst) {
            return Err("interrupted".into());
        }
        thread::sleep(Duration::from_millis(100));
    }
    Ok(())
}
// --8<-- [end:config]

// --8<-- [start:host]
/// Returns the ID of the first host in the cluster. A database places each
/// of its nodes on one or more hosts, which run the Postgres containers.
fn first_host(client: &Client) -> Result<String, BoxError> {
    let reply = call(client, Method::GET, "/v1/hosts", None)?;
    reply["hosts"][0]["id"]
        .as_str()
        .map(str::to_string)
        .ok_or_else(|| "the cluster has no hosts".into())
}
// --8<-- [end:host]

// --8<-- [start:create]
/// Asks the Control Plane to create a database with one node. The reply
/// holds the database and the task that creates it; the work happens in
/// the background after the reply.
fn create_database(client: &Client, database_id: &str, host: &str) -> Result<(), BoxError> {
    let port: u16 = port()
        .parse()
        .map_err(|_| format!("CONTROL_PLANE_RECIPE_PORT is not a port: {}", port()))?;
    let body = json!({
        "id": database_id,
        "spec": {
            "database_name": "recipe",
            "port": port,
            "nodes": [{"name": "n1", "host_ids": [host]}],
        },
    });
    call(client, Method::POST, "/v1/databases", Some(&body))?;
    Ok(())
}
// --8<-- [end:create]

// --8<-- [start:wait]
/// Polls the database, printing its state each time it changes, until the
/// state is available, and returns the port of its first instance. Each
/// instance runs one node, and its connection_info holds the address and
/// port that clients use. A failed state ends the wait at once.
fn wait_until_available(client: &Client, database_id: &str) -> Result<u64, BoxError> {
    let deadline = Instant::now() + WAIT_FOR;
    let mut last = String::new();
    while Instant::now() < deadline {
        let database = call(client, Method::GET, &format!("/v1/databases/{database_id}"), None)?;
        let state = database["state"].as_str().unwrap_or("unknown").to_string();
        if state != last {
            println!("Database state: {state}");
            last = state.clone();
        }
        if state == "available" {
            return database["instances"][0]["connection_info"]["port"]
                .as_u64()
                .ok_or_else(|| "Unexpected response: missing port".into());
        }
        if state == "failed" {
            return Err("the database has the state failed".into());
        }
        pause()?;
    }
    Err(format!("the database was not available after {} seconds", WAIT_FOR.as_secs()).into())
}
// --8<-- [end:wait]

// --8<-- [start:delete]
/// Reports whether a failed request is worth repeating: no reply arrived,
/// the server failed, or it answered 409, which the Control Plane does
/// whilst another task, such as the create, is still running on the
/// database.
fn is_transient(error: &BoxError) -> bool {
    match status_of(error) {
        Some(status) => status == 409 || status >= 500,
        None => error.is::<reqwest::Error>(),
    }
}

/// Deletes the database and waits until the API no longer has it. A 404
/// means that the database is already gone. The cleanup runs after
/// Ctrl-C, so its waits do not check the flag.
fn delete_database(client: &Client, database_id: &str) -> Result<(), BoxError> {
    let path = format!("/v1/databases/{database_id}");
    let deadline = Instant::now() + WAIT_FOR;
    loop {
        match call(client, Method::DELETE, &path, None) {
            Ok(_) => break,
            Err(e) if status_of(&e) == Some(404) => return Ok(()),
            Err(e) if !is_transient(&e) || Instant::now() >= deadline => return Err(e),
            Err(_) => thread::sleep(POLL_INTERVAL),
        }
    }

    // The delete starts a task that removes the database; a 404 shows that
    // it has finished.
    while Instant::now() < deadline {
        match call(client, Method::GET, &path, None) {
            Err(e) if status_of(&e) == Some(404) => return Ok(()),
            Err(e) if !is_transient(&e) => return Err(e),
            _ => thread::sleep(POLL_INTERVAL),
        }
    }
    Err(format!("the database was still present after {} seconds", WAIT_FOR.as_secs()).into())
}
// --8<-- [end:delete]

// --8<-- [start:main]
/// Prints an error and the chain of its underlying causes, because the
/// top-level error is often generic ("error sending request").
fn report(e: &BoxError) {
    eprintln!("Control Plane error: {e}");
    let mut cause = e.source();
    while let Some(c) = cause {
        eprintln!("  caused by: {c}");
        cause = c.source();
    }
}

/// Returns a random suffix of six hexadecimal digits, read from the
/// operating system's random number source.
fn random_suffix() -> Result<String, BoxError> {
    let mut bytes = [0u8; 3];
    File::open("/dev/urandom")?.read_exact(&mut bytes)?;
    Ok(bytes.iter().map(|b| format!("{b:02x}")).collect())
}

/// Creates the database and waits for it. It sets created once the
/// database may exist, so that the caller knows whether to delete it.
fn run(client: &Client, database_id: &str, created: &mut bool) -> Result<(), BoxError> {
    let host = first_host(client)?;
    println!("Host: {host}");

    // Clean up unless the server refused the request with a 4xx status,
    // which means it created nothing; a 409, for example, means that a
    // database with this ID already exists, and is not this program's to
    // delete.
    *created = true;
    if let Err(e) = create_database(client, database_id, host.as_str()) {
        if matches!(status_of(&e), Some(400..=499)) {
            *created = false;
        }
        return Err(e);
    }
    println!("Created database {database_id}");

    let port = wait_until_available(client, database_id)?;
    println!("Database is available on port {port}");
    Ok(())
}

/// Deletes the database whether the example succeeded, failed, or was
/// interrupted, and exits with a failure status after a failure.
fn main() -> ExitCode {
    // The handler stays in place, so a further Ctrl-C does not end the
    // process during the cleanup either. The termination feature of the
    // ctrlc crate makes it handle SIGTERM too.
    if let Err(e) = ctrlc::set_handler(|| INTERRUPTED.store(true, Ordering::SeqCst)) {
        eprintln!("Control Plane error: {e}");
        return ExitCode::FAILURE;
    }

    let client = match Client::builder().timeout(TIMEOUT).build() {
        Ok(client) => client,
        Err(e) => {
            report(&e.into());
            return ExitCode::FAILURE;
        }
    };
    // The client chooses the ID of a new database, so the program knows it
    // before the request, and can delete the database even if the reply
    // never arrives. The random suffix keeps the ID unique.
    let database_id = match random_suffix() {
        Ok(suffix) => format!("cookbook-recipe-{suffix}"),
        Err(e) => {
            report(&e);
            return ExitCode::FAILURE;
        }
    };

    let mut created = false;
    let mut exit_code = ExitCode::SUCCESS;
    if let Err(e) = run(&client, &database_id, &mut created) {
        if INTERRUPTED.load(Ordering::SeqCst) {
            eprintln!("Interrupted");
            exit_code = ExitCode::from(130);
        } else {
            report(&e);
            exit_code = ExitCode::FAILURE;
        }
    }

    if created {
        match delete_database(&client, &database_id) {
            Ok(()) => println!("Deleted database"),
            Err(e) => {
                report(&e);
                eprintln!("Delete the database {database_id} by hand");
                exit_code = ExitCode::FAILURE;
            }
        }
    }
    exit_code
}
// --8<-- [end:main]
