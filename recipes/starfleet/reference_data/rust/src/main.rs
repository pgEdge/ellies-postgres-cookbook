// Ellie's Postgres Cookbook
// Listing the regions, sizes, and PostgreSQL versions that the pgEdge
// Starfleet Managed API offers, using reqwest and serde_json.
//
// Copyright (c) 2026, pgEdge, Inc.
// This code is released under the PostgreSQL License.

// --8<-- [start:imports]
use std::env;
use std::error::Error;
use std::fmt;
use std::process::ExitCode;
use std::sync::LazyLock;
use std::time::Duration;

use reqwest::blocking::{Client, RequestBuilder};
use serde_json::{json, Value};
// --8<-- [end:imports]

// --8<-- [start:config]
/// Any error, boxed, so that a function can return errors of several types
/// with the ? operator.
type Result<T> = std::result::Result<T, Box<dyn Error>>;

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
/// One client serves every request. Its timeout covers the whole exchange,
/// the body of the reply included.
static CLIENT: LazyLock<Client> = LazyLock::new(|| {
    Client::builder()
        .timeout(Duration::from_secs(30))
        .build()
        .expect("could not create the HTTP client")
});

/// A failed request or an error reply from the API, which the program
/// reports differently from other errors.
#[derive(Debug)]
struct ApiError(String);

impl fmt::Display for ApiError {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        f.write_str(&self.0)
    }
}

impl Error for ApiError {}

/// Sends a request and returns the decoded JSON reply. A failed request,
/// or a 4xx or 5xx reply, returns an ApiError that includes the message
/// from the API, and the chain of causes for a failed request, whose
/// top-level error is often generic ("error sending request").
fn send(request: RequestBuilder, description: &str) -> Result<Value> {
    let chain = |e: reqwest::Error| {
        let mut text = e.to_string();
        let mut cause = e.source();
        while let Some(c) = cause {
            text.push_str(&format!(": {c}"));
            cause = c.source();
        }
        ApiError(text)
    };
    let response = request.send().map_err(chain)?;
    let status = response.status().as_u16();
    let text = response.text().map_err(chain)?;
    if status >= 400 {
        return Err(ApiError(format!(
            "{description} failed with status {status}: {}",
            text.trim()
        ))
        .into());
    }
    Ok(serde_json::from_str(&text)?)
}

/// Exchanges the client ID and secret for an access token, which the
/// Managed API accepts as a bearer token until it expires.
fn get_token(cfg: &Settings) -> Result<String> {
    let (Some(client_id), Some(client_secret)) = (&cfg.client_id, &cfg.client_secret) else {
        return Err("STARFLEET_CLIENT_ID and STARFLEET_CLIENT_SECRET must be set".into());
    };
    let path = "/account/v1/oauth/token";
    let request = CLIENT.post(format!("{}{path}", cfg.base_url)).json(&json!({
        "grant_type": "client_credentials",
        "client_id": client_id,
        "client_secret": client_secret,
    }));
    let token = send(request, &format!("POST {path}"))?;
    Ok(token["access_token"]
        .as_str()
        .ok_or("the token response has no access token")?
        .to_string())
}
// --8<-- [end:token]

// --8<-- [start:api]
/// Sends an authenticated GET request to the Managed API and returns the
/// decoded JSON reply. The query, if there is one, follows the path.
fn api_get(cfg: &Settings, token: &str, path: &str, query: &str) -> Result<Vec<Value>> {
    let mut url = format!("{}/managed/v1{path}", cfg.base_url);
    if !query.is_empty() {
        url = format!("{url}?{query}");
    }
    let reply = send(CLIENT.get(url).bearer_auth(token), &format!("GET {path}"))?;
    match reply {
        Value::Array(items) => Ok(items),
        _ => Err(format!("the reply to {path} is not a list").into()),
    }
}

/// Returns a field of a JSON object as text, and an error if the field is
/// missing.
fn field(value: &Value, name: &str) -> Result<String> {
    match value.get(name) {
        Some(Value::String(text)) => Ok(text.clone()),
        Some(Value::Null) | None => Err(format!("the reply has no {name}").into()),
        Some(other) => Ok(other.to_string()),
    }
}
// --8<-- [end:api]

// --8<-- [start:regions]
/// Returns the identifiers of the regions that can host a database.
fn list_regions(cfg: &Settings, token: &str) -> Result<Vec<String>> {
    api_get(cfg, token, "/regions", "")?
        .iter()
        .map(|region| field(region, "region"))
        .collect()
}
// --8<-- [end:regions]

// --8<-- [start:sizes]
/// Returns a description of each size, smallest first.
fn list_sizes(cfg: &Settings, token: &str) -> Result<Vec<String>> {
    // The pricing option asks the API to include each size's price, which
    // takes a little longer because the API looks it up from billing.
    let mut sizes = Vec::new();
    for size in api_get(cfg, token, "/sizes", "include=pricing")? {
        let mut line = format!(
            "{}: {} connections, {} storage",
            field(&size, "name")?,
            field(&size, "connections")?,
            field(&size, "storage_size")?
        );
        // A size with no configured price omits the pricing field. The
        // amount is in the smallest unit of the currency, such as cents;
        // Rust always formats a decimal point as a full stop.
        if let Some(price) = size.get("pricing").filter(|price| !price.is_null()) {
            let amount = price["price_amount"]
                .as_i64()
                .ok_or("the price has no amount")?;
            line.push_str(&format!(
                ", {:.2} {} per {}",
                amount as f64 / 100.0,
                field(price, "currency")?,
                field(price, "billing_interval")?
            ));
        }
        sizes.push(line);
    }
    Ok(sizes)
}
// --8<-- [end:sizes]

// --8<-- [start:versions]
/// Returns the PostgreSQL major versions, newest first, marking the one
/// that a new database gets by default.
fn list_versions(cfg: &Settings, token: &str) -> Result<Vec<String>> {
    api_get(cfg, token, "/pg-versions", "")?
        .iter()
        .map(|version| {
            let default = version["default"].as_bool() == Some(true);
            Ok(field(version, "version")? + if default { " (default)" } else { "" })
        })
        .collect()
}
// --8<-- [end:versions]

// --8<-- [start:main]
/// Prints the reference data, returning any error to the caller.
fn run() -> Result<()> {
    let cfg = settings();
    let token = get_token(&cfg)?;

    println!("Regions:");
    for region in list_regions(&cfg, &token)? {
        println!("  {region}");
    }

    println!("Sizes (smallest first):");
    for size in list_sizes(&cfg, &token)? {
        println!("  {size}");
    }

    println!("PostgreSQL versions:");
    for version in list_versions(&cfg, &token)? {
        println!("  {version}");
    }
    Ok(())
}

fn main() -> ExitCode {
    match run() {
        Ok(()) => ExitCode::SUCCESS,
        // An ApiError covers failures to connect and error replies from
        // the API; anything else is a setting or a reply that the program
        // cannot use.
        Err(e) if e.is::<ApiError>() => {
            eprintln!("API error: {e}");
            ExitCode::FAILURE
        }
        Err(e) => {
            eprintln!("Error: {e}");
            ExitCode::FAILURE
        }
    }
}
// --8<-- [end:main]
