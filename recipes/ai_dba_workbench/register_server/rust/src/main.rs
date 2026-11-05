// Ellie's Postgres Cookbook
// Registering a server to monitor with the AI DBA Workbench API, using
// reqwest and serde_json.
//
// Copyright (c) 2026, pgEdge, Inc.
// This code is released under the PostgreSQL License.

// --8<-- [start:imports]
use std::env;
use std::error::Error;
use std::process::ExitCode;
use std::sync::LazyLock;
use std::time::Duration;

use reqwest::blocking::{Client, Response};
use reqwest::Method;
use serde_json::{json, Value};
// --8<-- [end:imports]

// --8<-- [start:config]
const SERVER_NAME: &str = "cookbook-register-server";

/// Any error, boxed, so that a function can return errors of several types
/// with the ? operator.
type Result<T> = std::result::Result<T, Box<dyn Error>>;

/// The settings that the program reads from the environment.
struct Settings {
    base_url: String,
    username: String,
    password: String,
    connection_id: String,
    server_password: String,
}

/// Returns the value of an environment variable, if it is set and not
/// empty; an empty variable counts as unset.
fn env_value(name: &str) -> Option<String> {
    env::var(name).ok().filter(|value| !value.is_empty())
}

/// Reads the settings from the environment.
fn settings() -> Result<Settings> {
    let (Some(username), Some(password), Some(connection_id)) = (
        env_value("WORKBENCH_USERNAME"),
        env_value("WORKBENCH_PASSWORD"),
        env_value("WORKBENCH_CONNECTION_ID"),
    ) else {
        return Err("WORKBENCH_USERNAME, WORKBENCH_PASSWORD, and \
                    WORKBENCH_CONNECTION_ID must be set"
            .into());
    };
    let base_url = env_value("WORKBENCH_URL")
        .unwrap_or_else(|| "http://localhost:8080".to_string())
        .trim_end_matches('/')
        .to_string();
    // The Workbench refuses to register a server without a password, even
    // one that uses trust authentication, so fall back to a placeholder.
    let server_password =
        env_value("PGPASSWORD").unwrap_or_else(|| "unused-with-trust-authentication".to_string());
    Ok(Settings {
        base_url,
        username,
        password,
        connection_id,
        server_password,
    })
}
// --8<-- [end:config]

// --8<-- [start:request]
/// One client serves every request, with a timeout for each; the client
/// has none by default.
static CLIENT: LazyLock<Client> = LazyLock::new(|| {
    Client::builder()
        .timeout(Duration::from_secs(30))
        .build()
        .expect("could not create the HTTP client")
});

/// Sends a request to the API and returns the response. A request that the
/// server rejects returns an error that includes the message from the
/// server.
fn api(
    method: Method,
    base_url: &str,
    path: &str,
    token: Option<&str>,
    body: Option<&Value>,
) -> Result<Response> {
    let mut request = CLIENT.request(method.clone(), format!("{base_url}/api/v1{path}"));
    if let Some(token) = token {
        request = request.bearer_auth(token);
    }
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
    Ok(response)
}
// --8<-- [end:request]

// --8<-- [start:login]
/// Logs in and returns the session token. The server returns the token in
/// a session_token cookie, not in the body of the reply.
fn login(base_url: &str, username: &str, password: &str) -> Result<String> {
    let body = json!({ "username": username, "password": password });
    let response = api(Method::POST, base_url, "/auth/login", None, Some(&body))?;
    for cookie in response.headers().get_all("set-cookie") {
        if let Some(rest) = cookie.to_str()?.strip_prefix("session_token=") {
            // The value runs up to the first attribute, if there is one.
            let value = rest.split(';').next().unwrap_or_default();
            return Ok(value.to_string());
        }
    }
    Err("the login reply had no session_token cookie".into())
}
// --8<-- [end:login]

// --8<-- [start:lookup]
/// Returns the details of an existing connection, which the program uses
/// as the address of the server to register.
fn get_connection(base_url: &str, session: &str, connection_id: &str) -> Result<Value> {
    let path = format!("/connections/{connection_id}");
    Ok(api(Method::GET, base_url, &path, Some(session), None)?.json()?)
}
// --8<-- [end:lookup]

// --8<-- [start:register]
/// Registers a server and returns the ID of the new connection. The
/// address comes from an existing connection. The request must include a
/// password, and a description, which the server needs in version 1.0.0.
fn register_server(
    base_url: &str,
    session: &str,
    name: &str,
    template: &Value,
    password: &str,
) -> Result<i64> {
    // Indexing a missing field gives null rather than a panic.
    let body = json!({
        "name": name,
        "description": "Registered by the cookbook",
        "host": template["host"],
        "port": template["port"],
        "database_name": template["database_name"],
        "username": template["username"],
        "ssl_mode": template["ssl_mode"],
        "password": password,
        "is_monitored": true,
        "is_shared": false,
    });
    let created: Value = api(
        Method::POST,
        base_url,
        "/connections",
        Some(session),
        Some(&body),
    )?
    .json()?;
    Ok(created["id"]
        .as_i64()
        .ok_or("the reply had no connection ID")?)
}
// --8<-- [end:register]

// --8<-- [start:list]
/// Returns the named connection from the list, or None if the list has no
/// such connection.
fn find_connection(base_url: &str, session: &str, name: &str) -> Result<Option<Value>> {
    let connections: Vec<Value> =
        api(Method::GET, base_url, "/connections", Some(session), None)?.json()?;
    Ok(connections.into_iter().find(|c| c["name"] == name))
}
// --8<-- [end:list]

// --8<-- [start:delete]
/// Deletes a connection by its ID.
fn delete_connection(base_url: &str, session: &str, connection_id: i64) -> Result<()> {
    let path = format!("/connections/{connection_id}");
    api(Method::DELETE, base_url, &path, Some(session), None)?;
    Ok(())
}
// --8<-- [end:delete]

// --8<-- [start:main]
/// What the program must delete when it finishes: the new connection's
/// ID, and the session token that has the right to delete it.
struct Cleanup {
    session: String,
    connection_id: i64,
}

/// Does the work. Once it has registered the server, it records the new
/// connection in cleanup, so that main deletes it even if a later step
/// fails.
fn run(s: &Settings, cleanup: &mut Option<Cleanup>) -> Result<()> {
    let session = login(&s.base_url, &s.username, &s.password)?;
    let template = get_connection(&s.base_url, &session, &s.connection_id)?;

    let new_id = register_server(
        &s.base_url,
        &session,
        SERVER_NAME,
        &template,
        &s.server_password,
    )?;
    *cleanup = Some(Cleanup {
        session: session.clone(),
        connection_id: new_id,
    });
    println!("Registered the server '{SERVER_NAME}'");

    let found = find_connection(&s.base_url, &session, SERVER_NAME)?
        .ok_or("the new connection is missing from the list")?;
    let monitored = found["is_monitored"]
        .as_bool()
        .ok_or("the connection had no monitored flag")?;
    println!("Found '{SERVER_NAME}' in the list (monitored: {monitored})");

    delete_connection(&s.base_url, &session, new_id)?;
    *cleanup = None;
    println!("Deleted the connection");

    if find_connection(&s.base_url, &session, SERVER_NAME)?.is_some() {
        return Err("the connection is still in the list".into());
    }
    println!("The connection is no longer in the list");
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
    let s = match settings() {
        Ok(s) => s,
        Err(e) => {
            report("Error: ", e.as_ref());
            return ExitCode::FAILURE;
        }
    };

    let mut status = ExitCode::SUCCESS;
    let mut cleanup = None;
    if let Err(e) = run(&s, &mut cleanup) {
        report("Error: ", e.as_ref());
        status = ExitCode::FAILURE;
    }

    // Delete the connection whether or not a later step failed, so that a
    // failed run does not leave a server registered.
    if let Some(c) = cleanup {
        if let Err(e) = delete_connection(&s.base_url, &c.session, c.connection_id) {
            report("Error: could not delete the connection: ", e.as_ref());
            status = ExitCode::FAILURE;
        }
    }
    status
}
// --8<-- [end:main]
