// Ellie's Postgres Cookbook
// Authenticating with the AI DBA Workbench API, using reqwest and
// serde_json.
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
/// Any error, boxed, so that a function can return errors of several types
/// with the ? operator.
type Result<T> = std::result::Result<T, Box<dyn Error>>;

/// The settings that the program reads from the environment.
struct Settings {
    base_url: String,
    username: String,
    password: String,
}

/// Returns the value of an environment variable, if it is set and not
/// empty; an empty variable counts as unset.
fn env_value(name: &str) -> Option<String> {
    env::var(name).ok().filter(|value| !value.is_empty())
}

/// Reads the settings from the environment.
fn settings() -> Result<Settings> {
    let (Some(username), Some(password)) = (
        env_value("WORKBENCH_USERNAME"),
        env_value("WORKBENCH_PASSWORD"),
    ) else {
        return Err("WORKBENCH_USERNAME and WORKBENCH_PASSWORD must be set".into());
    };
    let base_url = env_value("WORKBENCH_URL")
        .unwrap_or_else(|| "http://localhost:8080".to_string())
        .trim_end_matches('/')
        .to_string();
    Ok(Settings {
        base_url,
        username,
        password,
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

// --8<-- [start:user_info]
/// Returns the user that a token belongs to, with its superuser flag.
fn user_info(base_url: &str, token: &str) -> Result<String> {
    let info: Value = api(Method::GET, base_url, "/user/info", Some(token), None)?.json()?;
    let username = info["username"]
        .as_str()
        .ok_or("the reply had no username")?;
    let superuser = info["is_superuser"]
        .as_bool()
        .ok_or("the reply had no superuser flag")?;
    Ok(format!("{username} (superuser: {superuser})"))
}
// --8<-- [end:user_info]

// --8<-- [start:create_token]
/// Creates an API token for a user and returns its ID and its value. The
/// server shows the value only once. The token expires after an hour.
fn create_token(
    base_url: &str,
    session: &str,
    owner: &str,
    annotation: &str,
) -> Result<(i64, String)> {
    let body = json!({
        "owner_username": owner,
        "annotation": annotation,
        "expires_in": "1h",
    });
    let created: Value = api(
        Method::POST,
        base_url,
        "/rbac/tokens",
        Some(session),
        Some(&body),
    )?
    .json()?;
    let id = created["id"].as_i64().ok_or("the reply had no token ID")?;
    let token = created["token"].as_str().ok_or("the reply had no token")?;
    Ok((id, token.to_string()))
}
// --8<-- [end:create_token]

// --8<-- [start:delete_token]
/// Deletes an API token by its ID.
fn delete_token(base_url: &str, session: &str, token_id: i64) -> Result<()> {
    let path = format!("/rbac/tokens/{token_id}");
    api(Method::DELETE, base_url, &path, Some(session), None)?;
    Ok(())
}
// --8<-- [end:delete_token]

// --8<-- [start:main]
/// What the program must delete when it finishes: the token's ID, and the
/// session token that has the right to delete it.
struct Cleanup {
    session: String,
    token_id: i64,
}

/// Does the work. Once it has created a token, it records the token in
/// cleanup, so that main deletes the token even if a later step fails.
fn run(s: &Settings, cleanup: &mut Option<Cleanup>) -> Result<()> {
    let session = login(&s.base_url, &s.username, &s.password)?;
    println!("Logged in with a session token");
    println!(
        "Session token belongs to {}",
        user_info(&s.base_url, &session)?
    );

    let (token_id, api_token) =
        create_token(&s.base_url, &session, &s.username, "cookbook-authenticate")?;
    *cleanup = Some(Cleanup { session, token_id });
    println!("Created the API token 'cookbook-authenticate'");
    println!(
        "API token belongs to {}",
        user_info(&s.base_url, &api_token)?
    );
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

    // Delete the token whether or not a later step failed, so that a
    // failed run does not leave a token behind.
    if let Some(c) = cleanup {
        match delete_token(&s.base_url, &c.session, c.token_id) {
            Ok(()) => println!("Deleted the API token"),
            Err(e) => {
                report("Error: could not delete the token: ", e.as_ref());
                status = ExitCode::FAILURE;
            }
        }
    }
    status
}
// --8<-- [end:main]
