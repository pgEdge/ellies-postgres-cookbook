// Ellie's Postgres Cookbook
// Changing a Postgres setting of a pgEdge Control Plane database, checking
// it from a connection, and putting the original settings back, using
// reqwest, serde_json and the postgres crate.
//
// These examples are for the Control Plane v0.11.0.
//
// The program restores the original settings on every path: after a
// success, after a failure, and after Ctrl-C.
//
// Copyright (c) 2026, pgEdge, Inc.
// This code is released under the PostgreSQL License.

// --8<-- [start:imports]
use std::env;
use std::error::Error;
use std::fmt;
use std::process::ExitCode;
use std::sync::atomic::{AtomicBool, Ordering};
use std::thread;
use std::time::{Duration, Instant};

use postgres::{Config, NoTls};
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

fn database_id() -> String {
    env_or("CONTROL_PLANE_DATABASE_ID", "cookbook")
}

const TIMEOUT: Duration = Duration::from_secs(30);

// The setting to change, and its new value.
const SETTING: &str = "work_mem";
const VALUE: &str = "16MB";

// How long to wait for an update to finish, and how often to check.
const WAIT_FOR: Duration = Duration::from_secs(600);
const POLL_INTERVAL: Duration = Duration::from_secs(5);

/// Set by Ctrl-C or SIGTERM. The handler sets this flag instead of ending
/// the process, which lets the program restore the settings before it
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

/// Fails if check is true and the user has pressed Ctrl-C. A request does
/// not stop for Ctrl-C, so the program checks the flag after each one; the
/// cleanup passes false, so that it carries on.
fn check_interrupted(check: bool) -> Result<(), BoxError> {
    if check && INTERRUPTED.load(Ordering::SeqCst) {
        return Err("interrupted".into());
    }
    Ok(())
}

/// Waits for the poll interval, checking for Ctrl-C as above.
fn pause(check: bool) -> Result<(), BoxError> {
    let end = Instant::now() + POLL_INTERVAL;
    while Instant::now() < end {
        check_interrupted(check)?;
        thread::sleep(Duration::from_millis(100));
    }
    Ok(())
}
// --8<-- [end:config]

// --8<-- [start:update]
/// Sends a whole database spec as an update, and returns the ID of the
/// task that applies it. The Control Plane compares the spec with the
/// current one and changes only what differs; the work happens in the
/// task after the reply.
fn update_database(client: &Client, spec: &Value) -> Result<String, BoxError> {
    let reply = call(
        client,
        Method::POST,
        &format!("/v1/databases/{}", database_id()),
        Some(&json!({ "spec": spec })),
    )?;
    reply["task"]["task_id"]
        .as_str()
        .map(str::to_string)
        .ok_or_else(|| "Unexpected response: missing task_id".into())
}

/// Returns a copy of the spec with the setting changed. postgresql_conf
/// holds the Postgres settings that the Control Plane manages, and may be
/// missing.
fn changed_spec(spec: &Value) -> Value {
    let mut changed = spec.clone();
    if !changed["postgresql_conf"].is_object() {
        changed["postgresql_conf"] = json!({});
    }
    changed["postgresql_conf"][SETTING] = json!(VALUE);
    changed
}
// --8<-- [end:update]

// --8<-- [start:wait]
/// Reports whether a failed request is worth repeating: no reply arrived,
/// the server failed, or it answered 409, which the Control Plane does
/// whilst another task, such as the update, is still running on the
/// database.
fn is_transient(error: &BoxError) -> bool {
    match status_of(error) {
        Some(status) => status == 409 || status >= 500,
        None => error.is::<reqwest::Error>(),
    }
}

/// Polls a task until it finishes, and fails unless it completed. A failed
/// poll is repeated if it is worth repeating. When check is true, Ctrl-C
/// ends the wait.
fn wait_for_task(client: &Client, task_id: &str, check: bool) -> Result<(), BoxError> {
    let path = format!("/v1/databases/{}/tasks/{task_id}", database_id());
    let deadline = Instant::now() + WAIT_FOR;
    while Instant::now() < deadline {
        let task = call(client, Method::GET, &path, None);
        check_interrupted(check)?;
        match task {
            Ok(task) => match task["status"].as_str() {
                Some("completed") => return Ok(()),
                Some(status @ ("failed" | "canceled")) => {
                    return Err(format!("the task finished with the status {status}").into())
                }
                _ => {}
            },
            Err(e) if !is_transient(&e) => return Err(e),
            Err(_) => {}
        }
        pause(check)?;
    }
    Err(format!("the task was still running after {} seconds", WAIT_FOR.as_secs()).into())
}
// --8<-- [end:wait]

// --8<-- [start:connect]
/// The result of show_setting: a database error is reported differently
/// from a Control Plane one.
enum ShowError {
    ControlPlane(BoxError),
    Database(postgres::Error),
}

impl From<BoxError> for ShowError {
    fn from(e: BoxError) -> Self {
        ShowError::ControlPlane(e)
    }
}

impl From<postgres::Error> for ShowError {
    fn from(e: postgres::Error) -> Self {
        ShowError::Database(e)
    }
}

/// Connects to the first available instance and returns the current
/// value of the setting. Each instance runs one node, and its
/// connection_info holds the address and port that clients use. NoTls
/// disables TLS, which keeps this example free of certificate set-up;
/// connections over an untrusted network should use TLS.
fn show_setting(client: &Client, password: &str) -> Result<String, ShowError> {
    let database = call(client, Method::GET, &format!("/v1/databases/{}", database_id()), None)?;
    let info = database["instances"]
        .as_array()
        .into_iter()
        .flatten()
        .find(|i| i["state"] == "available" && i["connection_info"]["addresses"][0].is_string())
        .map(|i| &i["connection_info"])
        .ok_or_else(|| BoxError::from(format!("no available instance of {}", database_id())))?;
    let port = info["port"]
        .as_u64()
        .and_then(|p| u16::try_from(p).ok())
        .ok_or_else(|| BoxError::from("Unexpected response: missing port"))?;

    let mut db = Config::new()
        .host(info["addresses"][0].as_str().unwrap_or_default())
        .port(port)
        .dbname(database["spec"]["database_name"].as_str().unwrap_or_default())
        .user(&env_or("CONTROL_PLANE_DATABASE_USER", "cookbook"))
        .password(password)
        .connect_timeout(TIMEOUT)
        .connect(NoTls)?;
    let current: String = db.query_one("SELECT current_setting($1)", &[&SETTING])?.get(0);
    // The client closes its connection when it goes out of scope.
    Ok(current)
}
// --8<-- [end:connect]

// --8<-- [start:restore]
/// Sends the original spec back and waits for the task. The Control Plane
/// answers 409 whilst another task, such as the update, is still running
/// on the database, so the program repeats the request, as it does when
/// no reply arrived or the server failed. The cleanup runs after Ctrl-C,
/// so its waits do not check the flag.
fn restore(client: &Client, original: &Value) -> Result<(), BoxError> {
    let deadline = Instant::now() + WAIT_FOR;
    let task_id = loop {
        match update_database(client, original) {
            Ok(task_id) => break task_id,
            Err(e) => {
                if !is_transient(&e) || Instant::now() >= deadline {
                    return Err(e);
                }
                thread::sleep(POLL_INTERVAL);
            }
        }
    };
    wait_for_task(client, &task_id, false)
}
// --8<-- [end:restore]

// --8<-- [start:main]
/// Prints an error and the chain of its underlying causes, because the
/// top-level error is often generic ("error sending request").
fn report(prefix: &str, e: &dyn Error) {
    eprintln!("{prefix}: {e}");
    let mut cause = e.source();
    while let Some(c) = cause {
        eprintln!("  caused by: {c}");
        cause = c.source();
    }
}

/// Changes the setting and checks it. It fills in original, and sets
/// changed once the settings may have changed, so that the caller knows
/// whether to restore them.
fn run(client: &Client, password: &str, original: &mut Value, changed: &mut bool) -> Result<(), ShowError> {
    // The spec that the API returns leaves out the passwords of the
    // database users, and an update may leave them out too, which keeps
    // them unchanged.
    let database = call(client, Method::GET, &format!("/v1/databases/{}", database_id()), None)?;
    check_interrupted(true)?;
    *original = database["spec"].clone();

    // Restore unless the server refused the request with a 4xx status,
    // which means that it changed nothing.
    println!("Setting {SETTING} to {VALUE}");
    *changed = true;
    let task_id = match update_database(client, &changed_spec(original)) {
        Ok(task_id) => task_id,
        Err(e) => {
            if matches!(status_of(&e), Some(400..=499)) {
                *changed = false;
            }
            return Err(e.into());
        }
    };
    check_interrupted(true)?;
    wait_for_task(client, &task_id, true)?;
    println!("Update completed");

    println!("{SETTING} is now {}", show_setting(client, password)?);
    Ok(())
}

/// Restores the original settings whether the example succeeded, failed,
/// or was interrupted, and exits with a failure status after a failure.
fn main() -> ExitCode {
    let password = env_or("CONTROL_PLANE_DATABASE_PASSWORD", "");
    if password.is_empty() {
        eprintln!("CONTROL_PLANE_DATABASE_PASSWORD must be set");
        return ExitCode::FAILURE;
    }

    // The handler stays in place, so a further Ctrl-C does not end the
    // process during the cleanup either. The termination feature of the
    // ctrlc crate makes it handle SIGTERM too.
    if let Err(e) = ctrlc::set_handler(|| INTERRUPTED.store(true, Ordering::SeqCst)) {
        report("Control Plane error", &e);
        return ExitCode::FAILURE;
    }

    let client = match Client::builder().timeout(TIMEOUT).build() {
        Ok(client) => client,
        Err(e) => {
            report("Control Plane error", &e);
            return ExitCode::FAILURE;
        }
    };

    let mut original = Value::Null;
    let mut changed = false;
    let mut exit_code = ExitCode::SUCCESS;
    // A signal that arrives after the last request, or whilst the program
    // is connected to the database, still counts.
    let result = run(&client, &password, &mut original, &mut changed);
    if INTERRUPTED.load(Ordering::SeqCst) {
        eprintln!("Interrupted");
        exit_code = ExitCode::from(130);
    } else if let Err(e) = result {
        exit_code = ExitCode::FAILURE;
        match e {
            ShowError::ControlPlane(e) => report("Control Plane error", e.as_ref()),
            ShowError::Database(e) => report("Database error", &e),
        }
    }

    if changed {
        match restore(&client, &original) {
            Ok(()) => println!("Restored the original settings"),
            Err(e) => {
                report("Control Plane error", e.as_ref());
                eprintln!("Restore the settings of the database {} by hand", database_id());
                exit_code = ExitCode::FAILURE;
            }
        }
    }
    exit_code
}
// --8<-- [end:main]
