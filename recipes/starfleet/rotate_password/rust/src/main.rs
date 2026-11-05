// Ellie's Postgres Cookbook
// Rotating the password of a role in a pgEdge Starfleet database, and
// connecting with the new password, using reqwest, serde_json, and the
// postgres crate.
//
// The program creates a database of its own to rotate a password in. The
// Starfleet service bills for every database from the moment that it
// becomes connectable, so the program deletes the database on every path:
// after a success, after a failure, after a panic, and after Ctrl-C. The
// program never prints either password.
//
// Copyright (c) 2026, pgEdge, Inc.
// This code is released under the PostgreSQL License.

// --8<-- [start:imports]
use std::collections::hash_map::RandomState;
use std::env;
use std::error::Error;
use std::fmt;
use std::hash::{BuildHasher, Hasher};
use std::panic::{self, AssertUnwindSafe};
use std::process::ExitCode;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::LazyLock;
use std::thread;
use std::time::{Duration, Instant};

use openssl::ssl::{SslConnector, SslMethod, SslVerifyMode};
use postgres::config::SslMode;
use postgres::error::SqlState;
use postgres::Config;
use postgres_openssl::MakeTlsConnector;
use reqwest::blocking::Client;
use reqwest::Method;
use serde_json::{json, Value};
use signal_hook::consts::{SIGINT, SIGTERM};
// --8<-- [end:imports]

// --8<-- [start:config]
/// How long to wait for a database to become available, or to disappear
/// after a delete, and how often to check.
const TIMEOUT: Duration = Duration::from_secs(900);
const POLL: Duration = Duration::from_secs(10);

/// How many times to look for a database whose create reply was lost.
const LOOKUP_ATTEMPTS: u32 = 3;

/// How many times to try connecting to the database before giving up.
const CONNECT_ATTEMPTS: u32 = 6;

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

/// Set when SIGINT or SIGTERM arrives.
static INTERRUPTED: AtomicBool = AtomicBool::new(false);

/// Set once the clean-up has started, which nothing may cut short.
static CLEANING: AtomicBool = AtomicBool::new(false);

/// Catches SIGINT and SIGTERM. The handler sets INTERRUPTED and replaces
/// the default action, which would end the program before it could delete
/// the database, so a second signal does nothing more.
fn catch_signals() -> Result<()> {
    for signal in [SIGINT, SIGTERM] {
        signal_hook::flag::register(signal, &INTERRUPTED)?;
    }
    Ok(())
}

/// The error that a request or a wait returns once a signal has arrived.
#[derive(Debug)]
struct Interrupted;

impl fmt::Display for Interrupted {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        f.write_str("interrupted")
    }
}

impl Error for Interrupted {}

/// Returns an error once a signal has arrived, so that the program stops
/// making requests, unless the clean-up has started.
fn check_interrupted() -> Result<()> {
    if INTERRUPTED.load(Ordering::SeqCst) && !CLEANING.load(Ordering::SeqCst) {
        return Err(Interrupted.into());
    }
    Ok(())
}

/// Waits for the given time, watching for a signal.
fn pause(duration: Duration) -> Result<()> {
    let end = Instant::now() + duration;
    while Instant::now() < end {
        check_interrupted()?;
        thread::sleep(Duration::from_millis(200));
    }
    Ok(())
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

/// An error reply from the API, with its HTTP status.
#[derive(Debug)]
struct ApiError {
    status: u16,
    message: String,
}

impl fmt::Display for ApiError {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        f.write_str(&self.message)
    }
}

impl Error for ApiError {}

/// Sends a request with a JSON body, if there is one, and returns the
/// decoded JSON reply, or null if the reply has no body. A 4xx or 5xx
/// reply returns an ApiError.
fn request(
    method: Method,
    url: &str,
    path: &str,
    token: Option<&str>,
    body: Option<&Value>,
) -> Result<Value> {
    let mut request = CLIENT.request(method.clone(), url);
    if let Some(token) = token {
        request = request.bearer_auth(token);
    }
    if let Some(body) = body {
        request = request.json(body);
    }

    let response = request.send()?;
    let status = response.status().as_u16();
    let text = response.text()?;
    if status >= 400 {
        return Err(ApiError {
            status,
            message: format!("{method} {path} failed with status {status}: {}", text.trim()),
        }
        .into());
    }
    if text.is_empty() {
        return Ok(Value::Null);
    }
    Ok(serde_json::from_str(&text)?)
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

/// Exchanges the client ID and secret for an access token, which the
/// Managed API accepts as a bearer token until it expires.
fn get_token(cfg: &Settings) -> Result<String> {
    let (Some(client_id), Some(client_secret)) = (&cfg.client_id, &cfg.client_secret) else {
        return Err("STARFLEET_CLIENT_ID and STARFLEET_CLIENT_SECRET must be set".into());
    };
    check_interrupted()?;
    let path = "/account/v1/oauth/token";
    let body = json!({
        "grant_type": "client_credentials",
        "client_id": client_id,
        "client_secret": client_secret,
    });
    let token = request(
        Method::POST,
        &format!("{}{path}", cfg.base_url),
        path,
        None,
        Some(&body),
    )?;
    field(&token, "access_token")
}
// --8<-- [end:token]

// --8<-- [start:api]
/// Sends an authenticated request to the Managed API and returns the
/// decoded JSON reply, or null if the reply has no body. After a signal,
/// it returns an error without sending anything.
fn api(cfg: &Settings, token: &str, method: Method, path: &str, body: Option<&Value>) -> Result<Value> {
    check_interrupted()?;
    let url = format!("{}/managed/v1{path}", cfg.base_url);
    request(method, &url, path, Some(token), body)
}
// --8<-- [end:api]

// --8<-- [start:placement]
/// Returns the region and size for the new database. The API lists sizes
/// smallest first, so the first one is the cheapest. The API does not
/// price regions, so the example takes the first one.
fn choose_placement(cfg: &Settings, token: &str) -> Result<(String, String)> {
    let regions = api(cfg, token, Method::GET, "/regions", None)?;
    let sizes = api(cfg, token, Method::GET, "/sizes", None)?;
    match (regions.get(0), sizes.get(0)) {
        (Some(region), Some(size)) => Ok((field(region, "region")?, field(size, "name")?)),
        _ => Err("the API offers no region or size".into()),
    }
}
// --8<-- [end:placement]

// --8<-- [start:create]
/// Returns the address that the API sees requests come from.
fn client_ip(cfg: &Settings, token: &str) -> Result<String> {
    // A new database is closed to everyone until an allowlist rule admits
    // an address. The API reports the address it sees this request come
    // from, which is the one to admit; a bare address means a single host.
    field(&api(cfg, token, Method::GET, "/client-ip", None)?, "ip_address")
}

/// Creates a database that only this machine can reach, and returns the
/// API's description of it, which includes its ID.
fn create_database(
    cfg: &Settings,
    token: &str,
    name: &str,
    display_name: &str,
    placement: &(String, String),
    ip: &str,
) -> Result<Value> {
    let body = json!({
        // The name becomes the Postgres database name, so it holds only
        // letters and digits, and the readable cookbook- prefix goes in the
        // display name. The program also uses the name to find the
        // database again if the reply to this request is lost.
        "name": name,
        "display_name": display_name,
        "region": placement.0,
        "size": placement.1,
        "ip_allowlist": {"rules": [{"cidr": ip, "label": "cookbook"}]},
    });
    // This calls request rather than api, so that a signal cannot stop a
    // request whose result the program must not lose.
    let path = "/databases";
    let url = format!("{}/managed/v1{path}", cfg.base_url);
    request(Method::POST, &url, path, Some(token), Some(&body))
}
// --8<-- [end:create]

// --8<-- [start:wait]
/// The API does not document its status values; the example treats these
/// two as failures, which end the wait at once instead of leaving it to
/// run until the time limit.
const FAILED_STATUSES: [&str; 2] = ["degraded", "failed"];

/// Polls the database until its status is available.
fn wait_until_available(cfg: &Settings, token: &str, database_id: &str) -> Result<()> {
    let deadline = Instant::now() + TIMEOUT;
    let mut last = String::new();
    while Instant::now() < deadline {
        let path = format!("/databases/{database_id}");
        let status = field(&api(cfg, token, Method::GET, &path, None)?, "status")?;
        if status != last {
            println!("Database status: {status}");
            last = status.clone();
        }
        if status == "available" {
            return Ok(());
        }
        if FAILED_STATUSES.contains(&status.as_str()) {
            return Err(format!("the database has the status {status}").into());
        }
        pause(POLL)?;
    }
    Err(format!("the database was not available after {} seconds", TIMEOUT.as_secs()).into())
}
// --8<-- [end:wait]

// --8<-- [start:connection]
/// Reads the connection details of an available database, and returns
/// them as a postgres connection configuration.
fn connection_settings(cfg: &Settings, token: &str, database_id: &str) -> Result<Config> {
    // The connection details, including the password of the application
    // user, come with the description of the database. They are present
    // only once the database is available. The API does not require the
    // host, so fall back to the external IP address if it is missing.
    let database = api(cfg, token, Method::GET, &format!("/databases/{database_id}"), None)?;
    let connection = &database["connection"];
    let value = |key: &str| field(connection, key).ok().filter(|value| !value.is_empty());
    let (Some(host), Some(port), Some(dbname), Some(user), Some(password)) = (
        value("host").or_else(|| value("external_ip_address")),
        value("port"),
        value("database"),
        value("username"),
        value("password"),
    ) else {
        return Err("the database description has incomplete connection details".into());
    };

    let mut config = Config::new();
    config
        .host(&host)
        .port(port.parse()?)
        .dbname(&dbname)
        .user(&user)
        .password(&password)
        // Encrypt the connection. The crate's default, Prefer, would fall
        // back to a plain connection, so Require is set explicitly.
        .ssl_mode(SslMode::Require)
        .connect_timeout(Duration::from_secs(15));
    Ok(config)
}

/// Builds the TLS connector for the connection. The certificate of a
/// Starfleet database is not signed by a public authority, so the example
/// does not verify it.
fn tls_connector() -> Result<MakeTlsConnector> {
    let mut builder = SslConnector::builder(SslMethod::tls())?;
    builder.set_verify(SslVerifyMode::NONE);
    Ok(MakeTlsConnector::new(builder.build()))
}
// --8<-- [end:connection]

// --8<-- [start:rotate]
/// The built-in role that the application connects as. The API also has
/// the roles admin and app_read_only.
const ROLE: &str = "app";

/// Asks the API to rotate the password of the role. The API answers 204
/// with no body once it has accepted the rotation and started the work.
fn rotate_password(cfg: &Settings, token: &str, database_id: &str) -> Result<()> {
    let path = format!("/databases/{database_id}/roles/{ROLE}/rotate-password");
    api(cfg, token, Method::POST, &path, None)?;
    Ok(())
}

/// Polls the database until it is available again with a new password.
fn wait_for_rotation(cfg: &Settings, token: &str, database_id: &str, old_password: &[u8]) -> Result<()> {
    // The API moves the database to the modifying status until the
    // rotation is live, and until then the previous password still
    // authenticates and the new one does not. The wait therefore ends only
    // when the status is available and the password in the description
    // differs from the old one. A rotation that fails leaves the database
    // degraded with the previous password still working, so the example
    // treats degraded and failed as failures, which end the wait at once.
    let deadline = Instant::now() + TIMEOUT;
    let mut last = "available".to_string();
    while Instant::now() < deadline {
        let database = api(cfg, token, Method::GET, &format!("/databases/{database_id}"), None)?;
        let status = field(&database, "status")?;
        if status != last {
            println!("Database status: {status}");
            last = status.clone();
        }
        if FAILED_STATUSES.contains(&status.as_str()) {
            return Err(format!("the database has the status {status}").into());
        }
        let password = database["connection"]["password"].as_str().unwrap_or("");
        if status == "available" && !password.is_empty() && password.as_bytes() != old_password {
            return Ok(());
        }
        pause(POLL)?;
    }
    Err(format!("the password was not rotated after {} seconds", TIMEOUT.as_secs()).into())
}
// --8<-- [end:rotate]

// --8<-- [start:query]
/// Connects to the database and returns the name of the user that the
/// server logged in.
fn current_user(connection: &Config) -> Result<String> {
    // A database can refuse connections for a short while after the API
    // reports it as available, so try a few times before giving up. An
    // error that carries an SQLSTATE code came from the server itself and
    // will not change on a second attempt, except for a failed login
    // (28P01), which the example also repeats: the API may report the
    // database as available a moment before the new password works.
    let retryable = |e: &postgres::Error| matches!(e.code(), None | Some(&SqlState::INVALID_PASSWORD));
    let mut attempt = 0;
    loop {
        let result = connection.connect(tls_connector()?).and_then(|mut client| {
            let user: String = client.query_one("SELECT current_user", &[])?.get(0);
            // Dropping the client also closes the connection, but close()
            // reports any error that occurs whilst doing so.
            client.close()?;
            Ok(user)
        });
        match result {
            Ok(user) => return Ok(user),
            Err(e) if retryable(&e) && attempt < CONNECT_ATTEMPTS - 1 => pause(POLL)?,
            Err(e) => return Err(e.into()),
        }
        attempt += 1;
    }
}
// --8<-- [end:query]

// --8<-- [start:delete]
/// Reports whether a failed request is worth repeating: no reply arrived,
/// such as a refused connection or a timeout, the service is overloaded or
/// failing, or it answered 409, which the API does whilst a database is
/// still being created.
fn is_transient(e: &(dyn Error + 'static)) -> bool {
    if let Some(api) = e.downcast_ref::<ApiError>() {
        return matches!(api.status, 409 | 429 | 500..);
    }
    e.is::<reqwest::Error>()
}

/// Reports whether an error is a 404 reply, which means that the database
/// does not exist.
fn is_gone(e: &(dyn Error + 'static)) -> bool {
    matches!(e.downcast_ref::<ApiError>(), Some(api) if api.status == 404)
}

/// Returns the ID of the database with the given name, if there is one.
/// The program uses this when it cannot tell whether a create request
/// worked. It repeats the request, as the delete does, because the fault
/// that lost the reply to the create request may still be there. The
/// request asks for the newest databases first, but the API does not say
/// which property it sorts on.
fn find_database(cfg: &Settings, token: &str, name: &str) -> Result<Option<String>> {
    let deadline = Instant::now() + TIMEOUT;
    let databases = loop {
        match api(cfg, token, Method::GET, "/databases?limit=100&descending=true", None) {
            Ok(databases) => break databases,
            Err(e) if is_transient(e.as_ref()) && Instant::now() < deadline => pause(POLL)?,
            Err(e) => return Err(e),
        }
    };
    for database in databases.as_array().into_iter().flatten() {
        if database["name"].as_str() == Some(name) {
            return Ok(Some(field(database, "id")?));
        }
    }
    Ok(None)
}

/// Looks for the database a few times, because the service may not have
/// recorded a request whose reply was lost until a little later. Returns
/// None if the database never appears.
fn find_created_database(cfg: &Settings, token: &str, name: &str) -> Result<Option<String>> {
    for attempt in 0..LOOKUP_ATTEMPTS {
        if let Some(database_id) = find_database(cfg, token, name)? {
            return Ok(Some(database_id));
        }
        if attempt < LOOKUP_ATTEMPTS - 1 {
            pause(POLL)?;
        }
    }
    Ok(None)
}

/// Reports whether a failed create request might still have created the
/// database: no reply arrived, the reply could not be read, or the service
/// failed with a 5xx status. A 4xx reply is a definite refusal.
fn outcome_unknown(e: &(dyn Error + 'static)) -> bool {
    match e.downcast_ref::<ApiError>() {
        Some(api) => api.status >= 500,
        None => true,
    }
}

/// Deletes the database and waits until the API no longer lists it.
fn delete_database(cfg: &Settings, token: &str, database_id: &str) -> Result<()> {
    let deadline = Instant::now() + TIMEOUT;
    let path = format!("/databases/{database_id}");
    loop {
        match api(cfg, token, Method::DELETE, &path, None) {
            Ok(_) => break,
            Err(e) if is_gone(e.as_ref()) => return Ok(()),
            Err(e) if is_transient(e.as_ref()) && Instant::now() < deadline => pause(POLL)?,
            Err(e) => return Err(e),
        }
    }

    // The delete starts the teardown; a 404 shows that it has finished.
    while Instant::now() < deadline {
        match api(cfg, token, Method::GET, &path, None) {
            Err(e) if is_gone(e.as_ref()) => return Ok(()),
            Err(e) if !is_transient(e.as_ref()) => return Err(e),
            _ => {}
        }
        pause(POLL)?;
    }
    Err(format!("the database was still present after {} seconds", TIMEOUT.as_secs()).into())
}
// --8<-- [end:delete]

// --8<-- [start:main]
/// What the clean-up needs to know about the database that run created.
#[derive(Default)]
struct Created {
    token: Option<String>,
    name: Option<String>,
    database_id: Option<String>,
    lookup: bool,
}

/// Returns six random hexadecimal digits. The standard library has no
/// random number generator, but it seeds the keys of each RandomState
/// from the operating system, so the hash of nothing is a random number.
fn random_suffix() -> String {
    format!("{:06x}", RandomState::new().build_hasher().finish() & 0xff_ffff)
}

/// Does the work, recording in created what the clean-up needs to know.
fn run(cfg: &Settings, created: &mut Created) -> Result<()> {
    let token = get_token(cfg)?;
    created.token = Some(token.clone());

    let placement = choose_placement(cfg, &token)?;
    println!("Region: {}", placement.0);
    println!("Size: {}", placement.1);

    // Choose the name before the request, so that the program can find the
    // database even if the reply to the request never arrives.
    let suffix = random_suffix();
    let name = format!("cookbook{suffix}");
    let display_name = format!("cookbook-{suffix}");
    let ip = client_ip(cfg, &token)?;
    created.name = Some(name.clone());
    // Look the database up by name afterwards only if the outcome of the
    // request is unknown, so that a refusal cannot lead the clean-up to
    // delete another database that has the same name.
    created.lookup = true;
    let database = create_database(cfg, &token, &name, &display_name, &placement, &ip)
        .inspect_err(|e| created.lookup = outcome_unknown(e.as_ref()))?;
    let database_id = field(&database, "id")?;
    created.database_id = Some(database_id.clone());
    println!("Created database {}", field(&database, "display_name")?);

    wait_until_available(cfg, &token, &database_id)?;
    println!("Database is available");

    // Keep the old password only to see when the new one arrives.
    let old_password = connection_settings(cfg, &token, &database_id)?
        .get_password()
        .unwrap_or_default()
        .to_vec();
    println!("Rotating the password of the {ROLE} role");
    rotate_password(cfg, &token, &database_id)?;
    wait_for_rotation(cfg, &token, &database_id, &old_password)?;
    println!("Password rotated");

    let connection = connection_settings(cfg, &token, &database_id)?;
    println!("Connected as {} with the new password", current_user(&connection)?);
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

/// Deletes the database, if run created one, and returns the exit status.
fn clean_up(cfg: &Settings, created: &mut Created, mut status: u8) -> u8 {
    let (Some(token), Some(name)) = (&created.token, &created.name) else {
        return status;
    };
    let result = (|| -> Result<()> {
        if created.database_id.is_none() && created.lookup {
            created.database_id = find_created_database(cfg, token, name)?;
            if created.database_id.is_none() {
                eprintln!("Error: the database {name} was not found; check your account for it by hand");
                status = 1;
            }
        }
        if let Some(database_id) = &created.database_id {
            delete_database(cfg, token, database_id)?;
            println!("Deleted database");
        }
        Ok(())
    })();
    if let Err(e) = result {
        report("Error: ", e.as_ref());
        let database = created.database_id.as_ref().unwrap_or(name);
        eprintln!("Delete the database {database} by hand, because it may still be billing");
        status = 1;
    }
    status
}

fn main() -> ExitCode {
    if let Err(e) = catch_signals() {
        report("Error: ", e.as_ref());
        return ExitCode::FAILURE;
    }
    let cfg = settings();

    // catch_unwind turns a panic in run into an Err, so that the clean-up
    // below runs after a panic too; the panic message has already been
    // printed by then.
    let mut created = Created::default();
    let outcome = panic::catch_unwind(AssertUnwindSafe(|| run(&cfg, &mut created)));
    let status = match outcome {
        Ok(Ok(())) => 0,
        _ if INTERRUPTED.load(Ordering::SeqCst) => {
            eprintln!("Interrupted");
            130
        }
        Ok(Err(e)) => {
            report("Error: ", e.as_ref());
            1
        }
        Err(_) => 1,
    };

    // Delete the database whether the example succeeded, failed, or was
    // interrupted, because the service bills for it until then. Signals no
    // longer stop anything, so that they cannot cut the clean-up short.
    CLEANING.store(true, Ordering::SeqCst);
    ExitCode::from(clean_up(&cfg, &mut created, status))
}
// --8<-- [end:main]
