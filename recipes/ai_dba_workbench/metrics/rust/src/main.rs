// Ellie's Postgres Cookbook
// Querying metrics and top queries with the AI DBA Workbench API, using
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

use reqwest::blocking::Client;
use reqwest::Url;
use serde_json::Value;
// --8<-- [end:imports]

// --8<-- [start:config]
/// Any error, boxed, so that a function can return errors of several types
/// with the ? operator.
type Result<T> = std::result::Result<T, Box<dyn Error>>;

/// The settings that the program reads from the environment.
struct Settings {
    base_url: String,
    token: String,
    connection_id: String,
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
/// One client serves every request, with a timeout for each; the client
/// has none by default.
static CLIENT: LazyLock<Client> = LazyLock::new(|| {
    Client::builder()
        .timeout(Duration::from_secs(30))
        .build()
        .expect("could not create the HTTP client")
});

/// Sends a GET request to the API, with the parameters in the query
/// string, and returns the JSON reply. A request that the server rejects
/// returns an error that includes the message from the server.
fn api(cfg: &Settings, path: &str, params: &[(&str, &str)]) -> Result<Vec<Value>> {
    let url = Url::parse_with_params(&format!("{}/api/v1{path}", cfg.base_url), params)?;
    let response = CLIENT.get(url).bearer_auth(&cfg.token).send()?;
    let status = response.status().as_u16();
    if status >= 400 {
        let text = response.text()?;
        return Err(format!("GET {path} failed with status {status}: {}", text.trim()).into());
    }
    Ok(response.json()?)
}
// --8<-- [end:request]

// --8<-- [start:query_metrics]
/// Prints one line for each series that the pg_stat_database probe
/// collected over the last hour, in six buckets: the metric, the number of
/// points, and the latest value.
fn query_metrics(cfg: &Settings) -> Result<()> {
    let series = api(
        cfg,
        "/metrics/query",
        &[
            ("connection_id", cfg.connection_id.as_str()),
            ("probe_name", "pg_stat_database"),
            ("time_range", "1h"),
            ("buckets", "6"),
            ("metrics", "numbackends,xact_commit"),
        ],
    )?;
    if series.is_empty() {
        return Err("the Workbench returned no series; has the collector run yet?".into());
    }
    for s in &series {
        let name = s["name"].as_str().ok_or("a series had no name")?;
        let points = s["data"].as_array().map(Vec::as_slice).unwrap_or_default();
        let Some(last) = points.last() else {
            println!("{name}: no data");
            continue;
        };
        let latest = last["value"].as_f64().ok_or("a point had no value")?;
        // Display prints a float without an exponent or trailing zeros.
        println!("{name}: {} points, latest {latest}", points.len());
    }
    Ok(())
}
// --8<-- [end:query_metrics]

// --8<-- [start:top_queries]
/// Prints the queries that have used the most execution time, as the
/// pg_stat_statements extension on the monitored server recorded them. The
/// query text is cut to 50 characters on one line.
fn top_queries(cfg: &Settings) -> Result<()> {
    let queries = api(
        cfg,
        "/metrics/top-queries",
        &[
            ("connection_id", cfg.connection_id.as_str()),
            ("limit", "5"),
            ("order_by", "total_exec_time"),
            ("exclude_collector", "true"),
        ],
    )?;
    if queries.is_empty() {
        println!("No statements recorded (is pg_stat_statements installed?)");
        return Ok(());
    }

    println!("Top queries by total execution time:");
    for (rank, q) in queries.iter().enumerate() {
        let query = q["query"].as_str().ok_or("a query had no text")?;
        let words: Vec<&str> = query.split_whitespace().collect();
        let text: String = words.join(" ").chars().take(50).collect();
        let calls = q["calls"].as_i64().ok_or("a query had no call count")?;
        let mean = q["mean_exec_time"]
            .as_f64()
            .ok_or("a query had no mean time")?;
        let mean = (mean * 100.0).round() / 100.0;
        println!("{}. {calls} calls, {mean} ms mean: {text}", rank + 1);
    }
    Ok(())
}
// --8<-- [end:top_queries]

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
    query_metrics(&cfg)?;
    top_queries(&cfg)?;
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
