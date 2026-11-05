// Ellie's Postgres Cookbook
// Getting an access token for the pgEdge Starfleet Managed API, using
// reqwest and serde_json.
//
// Copyright (c) 2026, pgEdge, Inc.
// This code is released under the PostgreSQL License.

// --8<-- [start:imports]
use std::env;
use std::error::Error;
use std::process::ExitCode;
use std::time::Duration;

use reqwest::blocking::Client;
use serde_json::{json, Value};
// --8<-- [end:imports]

// --8<-- [start:config]
/// The settings that the program reads from the environment.
struct Settings {
    base_url: String,
    client_id: Option<String>,
    client_secret: Option<String>,
}

/// Returns the value of an environment variable, if it is set and not
/// empty; an empty variable counts as unset.
fn env_value(name: &str) -> Option<String> {
    env::var(name).ok().filter(|value| !value.is_empty())
}

/// Reads the API settings from the environment. The client ID and secret
/// have no defaults, so a missing value becomes None, and the token
/// request reports it.
fn settings() -> Settings {
    Settings {
        base_url: env_value("STARFLEET_API_URL")
            .unwrap_or_else(|| "https://api.pgedge.com".to_string())
            .trim_end_matches('/')
            .to_string(),
        client_id: env_value("STARFLEET_CLIENT_ID"),
        client_secret: env_value("STARFLEET_CLIENT_SECRET"),
    }
}
// --8<-- [end:config]

// --8<-- [start:token]
/// The ways in which getting a token can fail: the request itself, or
/// what the program needs from the settings and the reply.
enum TokenError {
    Api(String),
    Other(String),
}

/// Exchanges the client ID and secret for an access token. The token
/// endpoint belongs to the account API, and accepts the OAuth 2.0 client
/// credentials grant as a JSON body.
fn get_token(cfg: &Settings) -> Result<Value, TokenError> {
    let (Some(client_id), Some(client_secret)) = (&cfg.client_id, &cfg.client_secret) else {
        return Err(TokenError::Other(
            "STARFLEET_CLIENT_ID and STARFLEET_CLIENT_SECRET must be set".into(),
        ));
    };

    // The client's timeout covers the whole exchange, the body of the
    // reply included.
    let client = Client::builder()
        .timeout(Duration::from_secs(30))
        .build()
        .map_err(|e| TokenError::Other(e.to_string()))?;
    let path = "/account/v1/oauth/token";
    let response = client
        .post(format!("{}{path}", cfg.base_url))
        .json(&json!({
            "grant_type": "client_credentials",
            "client_id": client_id,
            "client_secret": client_secret,
        }))
        .send()
        .map_err(|e| TokenError::Api(describe(&e)))?;
    let status = response.status().as_u16();
    let text = response.text().map_err(|e| TokenError::Api(describe(&e)))?;
    if status >= 400 {
        return Err(TokenError::Api(format!(
            "POST {path} failed with status {status}: {}",
            text.trim()
        )));
    }

    let token: Value = serde_json::from_str(&text).map_err(|e| TokenError::Other(e.to_string()))?;
    if token["access_token"].as_str().is_none_or(str::is_empty) {
        return Err(TokenError::Other("the token response has no access token".into()));
    }
    Ok(token)
}
// --8<-- [end:token]

// --8<-- [start:main]
/// Returns an error with the chain of underlying causes, because the
/// top-level error is often generic ("error sending request").
fn describe(e: &dyn Error) -> String {
    let mut text = e.to_string();
    let mut cause = e.source();
    while let Some(c) = cause {
        text.push_str(&format!(": {c}"));
        cause = c.source();
    }
    text
}

fn main() -> ExitCode {
    match get_token(&settings()) {
        Ok(token) => {
            // Never print the token itself; it grants access to the account.
            // The length counts characters, as the other languages do.
            let length = token["access_token"].as_str().unwrap_or("").chars().count();
            println!("Token type: {}", token["token_type"].as_str().unwrap_or(""));
            println!("Token length: {length} characters");
            println!("Expires in: {} seconds", token["expires_in"]);
            ExitCode::SUCCESS
        }
        Err(TokenError::Api(message)) => {
            eprintln!("API error: {message}");
            ExitCode::FAILURE
        }
        Err(TokenError::Other(message)) => {
            eprintln!("Error: {message}");
            ExitCode::FAILURE
        }
    }
}
// --8<-- [end:main]
