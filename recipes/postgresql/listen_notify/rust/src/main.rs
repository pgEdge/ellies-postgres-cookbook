// Ellie's Postgres Cookbook
// Listening for notifications with LISTEN and NOTIFY, using the postgres
// crate.
//
// Copyright (c) 2026, pgEdge, Inc.
// This code is released under the PostgreSQL License.

// --8<-- [start:imports]
use std::env;
use std::error::Error;
use std::process::ExitCode;
use std::time::Duration;

use postgres::fallible_iterator::FallibleIterator;
use postgres::{Client, Config, NoTls, Notification};
// --8<-- [end:imports]

// --8<-- [start:config]
const CHANNEL: &str = "cookbook_listen_notify";
const TIMEOUT: Duration = Duration::from_secs(5);

/// Returns the value of an environment variable, if it is set and not
/// empty; libpq also treats an empty variable as unset.
fn env_value(name: &str) -> Option<String> {
    env::var(name).ok().filter(|value| !value.is_empty())
}

/// Returns the value of an environment variable, or a fallback if the
/// variable is unset or empty.
fn env_or(name: &str, fallback: &str) -> String {
    env_value(name).unwrap_or_else(|| fallback.to_string())
}

/// Builds the connection configuration from the standard libpq
/// environment variables, with defaults suitable for a local server.
fn config() -> Config {
    let mut config = Config::new();
    config
        .host(&env_or("PGHOST", "localhost"))
        .port(env_or("PGPORT", "5432").parse().expect("PGPORT must be a number"))
        .dbname(&env_or("PGDATABASE", "postgres"))
        .user(&env_or("PGUSER", "postgres"));
    if let Some(password) = env_value("PGPASSWORD") {
        config.password(&password);
    }
    config
}
// --8<-- [end:config]

// --8<-- [start:connect]
/// Opens a connection with the settings from the environment. NoTls
/// disables TLS, which keeps this example free of certificate set-up;
/// connections over an untrusted network should use TLS. The client runs
/// each statement in autocommit mode unless the program begins a
/// transaction, so LISTEN takes effect, and NOTIFY is delivered, as soon
/// as the statement completes.
fn connect() -> Result<Client, postgres::Error> {
    config().connect(NoTls)
}
// --8<-- [end:connect]

// --8<-- [start:listen]
/// Subscribes the connection to a channel.
fn listen(client: &mut Client, channel: &str) -> Result<(), postgres::Error> {
    // LISTEN takes an identifier rather than a value, so it cannot use a
    // parameter. The crate has no identifier quoting function, so this
    // quotes the name by hand: it wraps the name in double quotes and
    // doubles any double quote inside it.
    let identifier = format!("\"{}\"", channel.replace('"', "\"\""));
    client.batch_execute(&format!("LISTEN {identifier}"))
}
// --8<-- [end:listen]

// --8<-- [start:notify]
/// Sends a notification to every connection listening on a channel.
fn notify(client: &mut Client, channel: &str, payload: &str) -> Result<(), postgres::Error> {
    // pg_notify() takes the channel and payload as ordinary parameters,
    // unlike the NOTIFY command.
    client.execute("SELECT pg_notify($1, $2)", &[&channel, &payload])?;
    Ok(())
}
// --8<-- [end:notify]

// --8<-- [start:wait]
/// Waits for one notification, and returns it, or None on timeout.
fn wait_for_notification(
    client: &mut Client,
    timeout: Duration,
) -> Result<Option<Notification>, postgres::Error> {
    // timeout_iter() yields notifications as they arrive, and ends when
    // the timeout passes without one.
    client.notifications().timeout_iter(timeout).next()
}
// --8<-- [end:wait]

// --8<-- [start:main]
/// Opens two connections, listens on one, notifies from the other, and
/// prints the notification. The ? operator returns any error to the
/// caller.
fn run() -> Result<(), Box<dyn Error>> {
    // Dropping a client closes its connection, including when ? returns
    // early.
    let mut listener = connect()?;
    let mut sender = connect()?;

    listen(&mut listener, CHANNEL)?;
    println!("Listening on channel '{CHANNEL}'");

    notify(&mut sender, CHANNEL, "Hello from connection B")?;

    let message = wait_for_notification(&mut listener, TIMEOUT)?
        .ok_or(format!("no notification within {} seconds", TIMEOUT.as_secs()))?;
    println!(
        "Received notification on '{}': {}",
        message.channel(),
        message.payload()
    );
    Ok(())
}

/// Reports any error returned by run() and exits with a failure status.
/// The top-level error is often generic ("error connecting to server"),
/// so the chain of underlying causes is printed too.
fn main() -> ExitCode {
    match run() {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("Error: {e}");
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
