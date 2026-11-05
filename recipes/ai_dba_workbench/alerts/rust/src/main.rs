// Ellie's Postgres Cookbook
// Listing and acknowledging alerts with the AI DBA Workbench API, using
// reqwest and serde_json.
//
// Copyright (c) 2026, pgEdge, Inc.
// This code is released under the PostgreSQL License.

// --8<-- [start:imports]
use std::env;
use std::error::Error;
use std::process::ExitCode;
use std::sync::LazyLock;
use std::thread;
use std::time::{Duration, Instant};

use reqwest::blocking::Client;
use reqwest::{Method, Url};
use serde_json::{json, Value};
// --8<-- [end:imports]

// --8<-- [start:config]
/// The rule that the program makes fire. The metric_staleness rule alerts
/// when a probe's data is out of date, and the alerter checks it every
/// minute.
const RULE_NAME: &str = "metric_staleness";

/// The longest the whole run waits for alerts. The alerter evaluates its
/// rules once a minute and clears an alert up to 30 seconds after it
/// fires, so this allows for waiting out the alert from an earlier run,
/// one alert that clears before the program can acknowledge it, and a
/// second evaluation.
const WAIT_TIME: Duration = Duration::from_secs(150);

/// How often the program polls the alerts.
const POLL_INTERVAL: Duration = Duration::from_millis(500);

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

/// Sends a request to the API, with any query parameters, and returns the
/// JSON reply, or null if the reply has no body. A request that the server
/// rejects returns an error that includes the message from the server.
fn api(
    method: Method,
    cfg: &Settings,
    path: &str,
    params: &[(&str, &str)],
    body: Option<&Value>,
) -> Result<Value> {
    let mut url = Url::parse(&format!("{}/api/v1{path}", cfg.base_url))?;
    // Adding no pairs would still leave an empty query string.
    if !params.is_empty() {
        url.query_pairs_mut().extend_pairs(params);
    }
    let mut request = CLIENT.request(method.clone(), url).bearer_auth(&cfg.token);
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

// --8<-- [start:find_rule]
/// Returns the ID of an alert rule, given its name.
fn find_rule(cfg: &Settings, name: &str) -> Result<i64> {
    let rules = api(Method::GET, cfg, "/alert-rules", &[], None)?;
    rules
        .as_array()
        .and_then(|rules| rules.iter().find(|r| r["name"] == name))
        .and_then(|rule| rule["id"].as_i64())
        .ok_or_else(|| format!("there is no alert rule named '{name}'").into())
}
// --8<-- [end:find_rule]

// --8<-- [start:set_override]
/// Overrides the threshold of a rule for one server. A threshold of -1 is
/// below any value that the staleness ratio can take, so the rule is
/// violated on the next evaluation.
fn set_override(cfg: &Settings, rule_id: i64) -> Result<()> {
    let path = format!("/alert-overrides/server/{}/{rule_id}", cfg.connection_id);
    let body = json!({ "operator": ">", "threshold": -1, "severity": "info", "enabled": true });
    api(Method::PUT, cfg, &path, &[], Some(&body))?;
    Ok(())
}
// --8<-- [end:set_override]

// --8<-- [start:wait_for_alert]
/// Returns the threshold alerts for the server that have the given status.
/// The request asks for the most alerts that the API returns at once, so
/// that the result does not depend on the first 100 alerts of a busy
/// Workbench.
fn list_alerts(cfg: &Settings, status: &str) -> Result<Vec<Value>> {
    let params = [
        ("connection_id", cfg.connection_id.as_str()),
        ("status", status),
        ("alert_type", "threshold"),
        ("limit", "1000"),
    ];
    let mut reply = api(Method::GET, cfg, "/alerts", &params, None)?;
    match reply["alerts"].take() {
        Value::Array(alerts) => Ok(alerts),
        _ => Err("the reply had no alerts".into()),
    }
}

/// Returns the active alerts that the given rule raised for the server.
fn active_alerts(cfg: &Settings, rule_id: i64) -> Result<Vec<Value>> {
    let mut alerts = list_alerts(cfg, "active")?;
    alerts.retain(|alert| alert["rule_id"] == rule_id);
    Ok(alerts)
}

/// Waits until the rule has no active alert. The alerter raises no new
/// alert for a rule while one is active, so an alert left by an earlier
/// run, which clears within 30 seconds, would otherwise stand in for the
/// one that this run causes.
fn wait_until_quiet(cfg: &Settings, rule_id: i64, deadline: Instant) -> Result<()> {
    while !active_alerts(cfg, rule_id)?.is_empty() {
        if Instant::now() >= deadline {
            return Err("an earlier alert did not clear in time".into());
        }
        thread::sleep(POLL_INTERVAL);
    }
    Ok(())
}

/// Polls until the given rule raises an alert, and returns it. The alert
/// clears itself within 30 seconds of firing, so the program polls twice a
/// second.
fn wait_for_alert(cfg: &Settings, rule_id: i64, deadline: Instant) -> Result<Value> {
    loop {
        if let Some(alert) = active_alerts(cfg, rule_id)?.into_iter().next() {
            return Ok(alert);
        }
        if Instant::now() >= deadline {
            let seconds = WAIT_TIME.as_secs();
            return Err(format!("no alert was raised within {seconds} seconds").into());
        }
        thread::sleep(POLL_INTERVAL);
    }
}
// --8<-- [end:wait_for_alert]

// --8<-- [start:acknowledge]
/// Acknowledges an alert, with a message that the interface shows.
fn acknowledge_alert(cfg: &Settings, alert_id: i64) -> Result<()> {
    let body = json!({ "alert_id": alert_id, "message": "Acknowledged by the cookbook" });
    api(Method::POST, cfg, "/alerts/acknowledge", &[], Some(&body))?;
    Ok(())
}
// --8<-- [end:acknowledge]

// --8<-- [start:check]
/// Returns the status of an alert, found by its ID in the list of
/// acknowledged alerts.
fn alert_status(cfg: &Settings, alert_id: i64) -> Result<String> {
    list_alerts(cfg, "acknowledged")?
        .iter()
        .find(|alert| alert["id"] == alert_id)
        .and_then(|alert| alert["status"].as_str())
        .map(str::to_string)
        .ok_or_else(|| "the alert is missing from the acknowledged alerts".into())
}
// --8<-- [end:check]

// --8<-- [start:unacknowledge]
/// Returns an acknowledged alert to the active state. The alerter clears
/// only active alerts, so an alert that stays acknowledged also stops the
/// rule from raising a new one.
fn unacknowledge_alert(cfg: &Settings, alert_id: i64) -> Result<()> {
    let id = alert_id.to_string();
    api(
        Method::DELETE,
        cfg,
        "/alerts/acknowledge",
        &[("alert_id", &id)],
        None,
    )?;
    Ok(())
}
// --8<-- [end:unacknowledge]

// --8<-- [start:remove_override]
/// Removes the override, so that the rule reverts to its default
/// threshold.
fn remove_override(cfg: &Settings, rule_id: i64) -> Result<()> {
    let path = format!("/alert-overrides/server/{}/{rule_id}", cfg.connection_id);
    api(Method::DELETE, cfg, &path, &[], None)?;
    Ok(())
}
// --8<-- [end:remove_override]

// --8<-- [start:main]
/// The changes that the program must undo when it finishes: the rule whose
/// override it set, and the alert that it acknowledged.
#[derive(Default)]
struct Cleanup {
    override_rule: Option<i64>,
    acknowledged_alert: Option<i64>,
}

/// Reports whether a list of alerts includes the one with an ID.
fn contains(alerts: &[Value], alert_id: i64) -> bool {
    alerts.iter().any(|alert| alert["id"] == alert_id)
}

/// Does the work. Each time it makes a change it records it in cleanup,
/// and clears the record once it has reversed the change itself.
fn run(cfg: &Settings, cleanup: &mut Cleanup) -> Result<()> {
    let deadline = Instant::now() + WAIT_TIME;

    let rule_id = find_rule(cfg, RULE_NAME)?;
    println!("Found the rule '{RULE_NAME}'");

    // An alert from an earlier run may still be active.
    wait_until_quiet(cfg, rule_id, deadline)?;

    cleanup.override_rule = Some(rule_id);
    set_override(cfg, rule_id)?;
    println!("Set an override that makes the rule fire");

    println!("Waiting for the alerter to raise an alert");
    let alert = loop {
        let alert = wait_for_alert(cfg, rule_id, deadline)?;
        let alert_id = alert["id"].as_i64().ok_or("the alert had no ID")?;

        // Record the alert before acknowledging it, so that the clean-up
        // returns it to the active state even if the request times out
        // after the server has acted on it.
        cleanup.acknowledged_alert = Some(alert_id);
        let Err(e) = acknowledge_alert(cfg, alert_id) else {
            break alert;
        };

        // The alerter may have cleared the alert since the poll. The
        // override is still in place, so the rule fires again at the next
        // evaluation; any other failure is real.
        if contains(&active_alerts(cfg, rule_id)?, alert_id) {
            // The server did not acknowledge it, so there is nothing to
            // undo.
            cleanup.acknowledged_alert = None;
            return Err(e);
        }
        // If the server acted on a request that timed out, the alert is
        // acknowledged and must go back to active. When that fails, the
        // error propagates and the clean-up tries again, because the
        // record is still set.
        if contains(&list_alerts(cfg, "acknowledged")?, alert_id) {
            unacknowledge_alert(cfg, alert_id)?;
        }
        cleanup.acknowledged_alert = None;
        eprintln!("The alert cleared first; waiting for the next one");
    };
    let alert_id = alert["id"].as_i64().ok_or("the alert had no ID")?;
    let severity = alert["severity"].as_str().unwrap_or_default();
    println!("An alert is active (severity: {severity})");
    println!("Acknowledged the alert");

    println!("The alert is now {}", alert_status(cfg, alert_id)?);

    unacknowledge_alert(cfg, alert_id)?;
    cleanup.acknowledged_alert = None;
    println!("Returned the alert to the active state");

    remove_override(cfg, rule_id)?;
    cleanup.override_rule = None;
    println!("Removed the override");
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
    let cfg = match settings() {
        Ok(cfg) => cfg,
        Err(e) => {
            report("Error: ", e.as_ref());
            return ExitCode::FAILURE;
        }
    };

    let mut status = ExitCode::SUCCESS;
    let mut cleanup = Cleanup::default();
    if let Err(e) = run(&cfg, &mut cleanup) {
        report("Error: ", e.as_ref());
        status = ExitCode::FAILURE;
    }

    // Undo the changes whether or not a step failed, so that the server
    // does not keep raising alerts or hold an acknowledged one.
    if let Some(alert_id) = cleanup.acknowledged_alert {
        if let Err(e) = unacknowledge_alert(&cfg, alert_id) {
            report("Error: could not undo a change: ", e.as_ref());
            status = ExitCode::FAILURE;
        }
    }
    if let Some(rule_id) = cleanup.override_rule {
        if let Err(e) = remove_override(&cfg, rule_id) {
            report("Error: could not undo a change: ", e.as_ref());
            status = ExitCode::FAILURE;
        }
    }
    status
}
// --8<-- [end:main]
