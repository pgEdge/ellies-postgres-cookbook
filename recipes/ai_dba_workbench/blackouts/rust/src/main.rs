// Ellie's Postgres Cookbook
// Scheduling a maintenance blackout with the AI DBA Workbench API, using
// reqwest and serde_json.
//
// Copyright (c) 2026, pgEdge, Inc.
// This code is released under the PostgreSQL License.

// --8<-- [start:imports]
use std::env;
use std::error::Error;
use std::process::ExitCode;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::LazyLock;
use std::time::{Duration, SystemTime};

use humantime::format_rfc3339_seconds;
use reqwest::blocking::Client;
use reqwest::Method;
use serde_json::{json, Value};
use signal_hook::consts::{SIGINT, SIGTERM};
// --8<-- [end:imports]

// --8<-- [start:config]
/// Any error, boxed, so that a function can return errors of several types
/// with the ? operator.
type Result<T> = std::result::Result<T, Box<dyn Error>>;

/// The settings that the program reads from the environment.
struct Settings {
    base_url: String,
    token: String,
    connection_id: u64,
}

/// Returns the value of an environment variable, if it is set and not
/// empty; an empty variable counts as unset.
fn env_value(name: &str) -> Option<String> {
    env::var(name).ok().filter(|value| !value.is_empty())
}

/// Reads the settings from the environment.
fn settings() -> Result<Settings> {
    let (Some(token), Some(connection_id)) = (
        env_value("WORKBENCH_TOKEN"),
        env_value("WORKBENCH_CONNECTION_ID"),
    ) else {
        return Err("WORKBENCH_TOKEN and WORKBENCH_CONNECTION_ID must be set".into());
    };
    // parse() alone would also accept a leading plus sign.
    if !connection_id.bytes().all(|b| b.is_ascii_digit()) {
        return Err("WORKBENCH_CONNECTION_ID must be a number".into());
    }
    let connection_id = connection_id.parse()?;
    let base_url = env_value("WORKBENCH_URL")
        .unwrap_or_else(|| "http://localhost:8080".to_string())
        .trim_end_matches('/')
        .to_string();
    Ok(Settings {
        base_url,
        token,
        connection_id,
    })
}
// --8<-- [end:config]

// --8<-- [start:request]
/// The number of the SIGINT or SIGTERM signal that the program received,
/// or 0 if it has received neither.
static INTERRUPTED: AtomicUsize = AtomicUsize::new(0);

/// Catches SIGINT and SIGTERM. The handler records the signal in
/// INTERRUPTED and replaces the default action, which would end the
/// program before it could delete the blackout, so a second signal does
/// nothing more.
fn catch_signals() -> Result<()> {
    for signal in [SIGINT, SIGTERM] {
        signal_hook::flag::register_usize(signal, &INTERRUPTED, signal as usize)?;
    }
    Ok(())
}

/// One client serves every request, with a timeout for each; the client
/// has none by default.
static CLIENT: LazyLock<Client> = LazyLock::new(|| {
    Client::builder()
        .timeout(Duration::from_secs(30))
        .build()
        .expect("could not create the HTTP client")
});

/// Sends a request to the API and returns the JSON reply, or null if the
/// reply has no body. A request that the server rejects returns an error
/// that includes the message from the server. After a signal, every
/// request that is interruptible fails at once; the cleanup and the create
/// call, whose result the program must not lose, pass false.
fn api(
    cfg: &Settings,
    method: Method,
    path: &str,
    interruptible: bool,
    body: Option<&Value>,
) -> Result<Value> {
    if interruptible {
        match INTERRUPTED.load(Ordering::SeqCst) {
            0 => {}
            signal if signal == SIGINT as usize => return Err("interrupted by SIGINT".into()),
            _ => return Err("interrupted by SIGTERM".into()),
        }
    }
    let mut request = CLIENT
        .request(method.clone(), format!("{}/api/v1{path}", cfg.base_url))
        .bearer_auth(&cfg.token);
    if let Some(body) = body {
        request = request.json(body);
    }

    let response = request.send()?;
    let status = response.status().as_u16();
    let text = response.text()?;
    if status >= 400 {
        return Err(format!(
            "{method} {path} failed with status {status}: {}",
            text.trim()
        )
        .into());
    }
    if text.is_empty() {
        return Ok(Value::Null);
    }
    Ok(serde_json::from_str(&text)?)
}
// --8<-- [end:request]

// --8<-- [start:create]
/// Creates a blackout for one monitored server and returns it. The
/// blackout starts a minute ago, so that a small difference between the
/// clocks of this machine and the server cannot leave it inactive, and it
/// ends in one hour. The times are in RFC 3339 format.
fn create_blackout(cfg: &Settings) -> Result<Value> {
    let now = SystemTime::now();
    let body = json!({
        "scope": "server",
        "connection_id": cfg.connection_id,
        "reason": "Cookbook maintenance window",
        "start_time": format_rfc3339_seconds(now - Duration::from_secs(60)).to_string(),
        "end_time": format_rfc3339_seconds(now + Duration::from_secs(3600)).to_string(),
    });
    api(cfg, Method::POST, "/blackouts", false, Some(&body))
}
// --8<-- [end:create]

// --8<-- [start:read]
/// Returns the blackout with the given ID.
fn get_blackout(cfg: &Settings, blackout_id: i64) -> Result<Value> {
    api(
        cfg,
        Method::GET,
        &format!("/blackouts/{blackout_id}"),
        true,
        None,
    )
}
// --8<-- [end:read]

// --8<-- [start:stop]
/// Stops a blackout that is in progress, which sets its end time to now,
/// and returns the stopped blackout.
fn stop_blackout(cfg: &Settings, blackout_id: i64) -> Result<Value> {
    let path = format!("/blackouts/{blackout_id}/stop");
    api(cfg, Method::POST, &path, true, None)
}
// --8<-- [end:stop]

// --8<-- [start:delete]
/// Deletes a blackout by its ID.
fn delete_blackout(cfg: &Settings, blackout_id: i64) -> Result<()> {
    let path = format!("/blackouts/{blackout_id}");
    api(cfg, Method::DELETE, &path, false, None)?;
    Ok(())
}
// --8<-- [end:delete]

// --8<-- [start:main]
/// Returns the is_active flag of a blackout.
fn is_active(blackout: &Value) -> Result<bool> {
    Ok(blackout["is_active"]
        .as_bool()
        .ok_or("the blackout had no active flag")?)
}

/// Does the work. Once it has created a blackout, it records the ID in
/// cleanup, so that main deletes the blackout even if a later step fails.
fn run(cfg: &Settings, cleanup: &mut Option<i64>) -> Result<()> {
    let created = create_blackout(cfg)?;
    let blackout_id = created["id"]
        .as_i64()
        .ok_or("the reply had no blackout ID")?;
    *cleanup = Some(blackout_id);
    println!(
        "Created a blackout for the server (active: {})",
        is_active(&created)?
    );

    let blackout = get_blackout(cfg, blackout_id)?;
    println!("Read the blackout back (active: {})", is_active(&blackout)?);

    let stopped = stop_blackout(cfg, blackout_id)?;
    let active = is_active(&stopped)?;
    println!("Stopped the blackout (active: {active})");
    if active {
        return Err("the blackout is still active".into());
    }

    delete_blackout(cfg, blackout_id)?;
    *cleanup = None;
    println!("Deleted the blackout");
    Ok(())
}

/// Prints an error with the chain of underlying causes, because the
/// top-level error is often generic ("error sending request").
fn report(prefix: &str, e: &dyn Error) {
    eprintln!("{prefix}{e}");
    let mut cause = e.source();
    while let Some(c) = cause {
        eprintln!("  caused by: {c}");
        cause = c.source();
    }
}

fn main() -> ExitCode {
    let cfg = match catch_signals().and_then(|()| settings()) {
        Ok(cfg) => cfg,
        Err(e) => {
            report("Error: ", e.as_ref());
            return ExitCode::FAILURE;
        }
    };

    let mut status = ExitCode::SUCCESS;
    let mut cleanup = None;
    if let Err(e) = run(&cfg, &mut cleanup) {
        report("Error: ", e.as_ref());
        status = ExitCode::FAILURE;
    }

    // Delete the blackout whether or not a later step failed, so that a
    // failed run does not leave alerts suppressed.
    if let Some(blackout_id) = cleanup {
        if let Err(e) = delete_blackout(&cfg, blackout_id) {
            report("Error: could not delete the blackout: ", e.as_ref());
            status = ExitCode::FAILURE;
        }
    }
    status
}
// --8<-- [end:main]
