# Taking a Backup and Tracking Its Task

This recipe shows how to take an on-demand backup of a pgEdge Starfleet
database, poll the backup until it completes, and list the tasks that the API
recorded for the database. Because the recipe needs a database, the program
creates one with the code from the "Creating a Database and Waiting for It"
recipe, and deletes it at the end. Starfleet bills for the database whilst it
exists, so the program removes it on every path out. The backup is different:
the API has no way to delete a backup, so every run leaves one behind.

These examples are for the pgEdge Starfleet Managed API v1.

The names of the resources, the number of status lines, and the version strings
vary, so the output looks similar to the following:

```text
Region: us-east-2
Size: small
Created database cookbook-3f9a1c
Database status: creating
Database status: available
Database is available
Backup started
Backup status: pending
Backup status: started
Backup status: completed
Task: backup-managed (succeeded)
Task: create-managed (succeeded)
Deleted database
Backup after the database was deleted: still listed
```

## Preparing the Ingredients

You need a pgEdge Starfleet account and an API client with its client ID and
secret. Never put the client secret in a file that you commit to version
control, and never paste it into a command line, because other users of the
machine can read the command lines of running processes. The programs in this
recipe read the secret from the environment and, for the curl script, pass it
to curl on standard input.

The following warning describes what the example creates and what it does to
clean up:

!!! warning "These examples create billable resources"

    Starfleet bills for a database until deletion is requested. The program
    deletes the database that it creates whether the example succeeds, fails,
    or is interrupted with Ctrl-C, and waits until the API no longer lists it.
    If the reply to the create request is lost, the program looks the database
    up by its name before it deletes it, and if that fails it tells you the
    name so that you can delete it by hand. A program that is killed outright,
    with `kill -9` for instance, cannot clean up, so check your account for
    databases whose display names start with `cookbook-` if you stop a run that
    way.

    The API has no way to delete a backup, so every run of this recipe leaves a
    backup behind, and the API specification does not document how long backups
    are kept or whether they are billed. For that reason the scheduled test job
    for this repository does not run this recipe, and you should run it
    sparingly.

The programs need only the HTTP clients of the "Getting an Access Token"
recipe, except that the Rust program also uses
[signal-hook](https://docs.rs/signal-hook) to catch signals. The curl script
needs `curl` and `jq`. The following excerpts show the dependencies:

=== "Python"

    ```text
    # httpx is an HTTP client with a clean, requests-like interface.
    httpx>=0.28,<1
    ```

=== "TypeScript"

    ```json
    {
      "name": "starfleet-backups",
      "private": true,
      "type": "module",
      "scripts": {
        "build": "tsc",
        "start": "node dist/main.js"
      },
      "devDependencies": {
        "@types/node": "^22.0.0",
        "typescript": "^5.9.0"
      }
    }
    
    ```

=== "Java"

    ```xml
    <dependencies>
      <!-- Jackson, for JSON; the HTTP client is part of the JDK. -->
      <dependency>
        <groupId>tools.jackson.core</groupId>
        <artifactId>jackson-databind</artifactId>
        <version>3.2.4</version>
      </dependency>
    </dependencies>
    ```

=== "C#"

    ```xml
    <!-- The program uses only HttpClient and System.Text.Json, which are
         part of .NET, so it needs no packages. -->
    ```

=== "Go"

    ```text
    // The program uses only the Go standard library, so it has no
    // dependencies to declare.
    ```

=== "Rust"

    ```toml
    [dependencies]
    # The blocking client of reqwest, with rustls for TLS and JSON bodies.
    reqwest = { version = "0.13", default-features = false, features = ["blocking", "json", "rustls"] }
    serde_json = "1"
    # The standard library cannot catch a signal, so this small crate does it.
    signal-hook = "0.4"
    ```

=== "Ruby"

    ```ruby
    source "https://rubygems.org"
    
    # The program uses only Net::HTTP and JSON, which come with Ruby, so it
    # needs no gems.
    ```

## Importing the Libraries

The following code shows the imports and, for the curl script, the check for
the tools that it needs:

=== "Python"

    ```python
    import os
    import secrets
    import signal
    import sys
    import time
    
    import httpx
    ```

=== "TypeScript"

    ```typescript
    import { randomBytes } from "node:crypto";
    import process from "node:process";
    import { setTimeout as sleep } from "node:timers/promises";
    ```

=== "Java"

    ```java
    import java.io.IOException;
    import java.net.URI;
    import java.net.http.HttpClient;
    import java.net.http.HttpRequest;
    import java.net.http.HttpResponse;
    import java.net.http.HttpTimeoutException;
    import java.security.SecureRandom;
    import java.time.Duration;
    import java.util.HexFormat;
    import java.util.List;
    import java.util.Map;
    import java.util.Objects;
    import java.util.Set;
    import java.util.concurrent.CompletableFuture;
    import java.util.concurrent.ExecutionException;
    import java.util.concurrent.TimeUnit;
    import java.util.concurrent.TimeoutException;
    import tools.jackson.core.JacksonException;
    import tools.jackson.databind.JsonNode;
    import tools.jackson.databind.ObjectMapper;
    ```

=== "C#"

    ```csharp
    using System.Net;
    using System.Net.Http.Headers;
    using System.Runtime.InteropServices;
    using System.Security.Cryptography;
    using System.Text;
    using System.Text.Json;
    using System.Text.Json.Nodes;
    ```

=== "Go"

    ```go
    import (
    	"bytes"
    	"context"
    	"crypto/rand"
    	"encoding/hex"
    	"encoding/json"
    	"errors"
    	"fmt"
    	"io"
    	"net/http"
    	"os"
    	"os/signal"
    	"strings"
    	"syscall"
    	"time"
    )
    
    ```

=== "Rust"

    ```rust
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
    
    use reqwest::blocking::Client;
    use reqwest::Method;
    use serde_json::{json, Value};
    use signal_hook::consts::{SIGINT, SIGTERM};
    ```

=== "Ruby"

    ```ruby
    require "json"
    require "net/http"
    require "securerandom"
    ```

=== "curl"

    ```bash
    # Stop at the first failed command or unset variable, and make a failure
    # anywhere in a pipeline fail the whole pipeline.
    set -euo pipefail
    
    # The script needs curl to call the API and jq to read the JSON replies.
    for tool in curl jq; do
        command -v "$tool" >/dev/null || { echo "Error: $tool is required" >&2; exit 1; }
    done
    ```

## Configuring the Program

The program reads the same environment variables as the other Starfleet
recipes, and treats an empty variable as unset:

| Variable                  | Default                  | Description         |
|---------------------------|--------------------------|---------------------|
| `STARFLEET_CLIENT_ID`     | None                     | Your client ID.     |
| `STARFLEET_CLIENT_SECRET` | None                     | Your client secret. |
| `STARFLEET_API_URL`       | `https://api.pgedge.com` | The API base URL.   |

The constants set how long to wait for the database and the backup, which can
take several minutes, and how often to check. The following code reads the
settings:

=== "Python"

    ```python
    # How long to wait for a database to become available, or to disappear
    # after a delete, and how often to check.
    TIMEOUT_SECONDS = 900
    POLL_SECONDS = 10
    
    # How many times to look for a database whose create reply was lost.
    LOOKUP_ATTEMPTS = 3
    
    
    def settings() -> dict:
        """Reads the API settings from the environment.
    
        The or operator treats an empty variable as unset. The client ID and
        secret have no defaults, so a missing value becomes None, and the
        token request reports it.
        """
        return {
            "base_url": (
                os.environ.get("STARFLEET_API_URL") or "https://api.pgedge.com"
            ).rstrip("/"),
            "client_id": os.environ.get("STARFLEET_CLIENT_ID") or None,
            "client_secret": os.environ.get("STARFLEET_CLIENT_SECRET") or None,
        }
    ```

=== "TypeScript"

    ```typescript
    // How long to wait for a database to become available, or to disappear
    // after a delete, and how often to check.
    const TIMEOUT_MS = 900_000;
    const POLL_MS = 10_000;
    
    // How many times to look for a database whose create reply was lost.
    const LOOKUP_ATTEMPTS = 3;
    
    // Read the API settings from the environment. The || operator, unlike ??,
    // also treats an empty variable as unset.
    const baseUrl = (
      process.env.STARFLEET_API_URL || "https://api.pgedge.com"
    ).replace(/\/+$/, "");
    const clientId = process.env.STARFLEET_CLIENT_ID || "";
    const clientSecret = process.env.STARFLEET_CLIENT_SECRET || "";
    
    // Ctrl-C and SIGTERM abort the signal below instead of ending the
    // process, which lets the program delete its database before it exits.
    // The handlers stay in place, so a further Ctrl-C does not end the process
    // during the cleanup either.
    const interrupt = new AbortController();
    for (const signalName of ["SIGINT", "SIGTERM"] as const) {
      process.on(signalName, () => interrupt.abort());
    }
    ```

=== "Java"

    ```java
    /**
     * How long to wait for a database to become available, or to disappear
     * after a delete, and how often to check.
     */
    static final int TIMEOUT_SECONDS = 900;
    static final int POLL_SECONDS = 10;
    
    /** How many times to look for a database whose create reply was lost. */
    static final int LOOKUP_ATTEMPTS = 3;
    
    /** The settings that the program reads from the environment. */
    record Settings(String baseUrl, String clientId, String clientSecret) {}
    
    /**
     * Returns the value of an environment variable, or the fallback if the
     * variable is unset or empty, as an unset variable would be.
     */
    static String envOr(String name, String fallback) {
        String value = System.getenv(name);
        return (value != null && !value.isEmpty()) ? value : fallback;
    }
    
    /**
     * Reads the API settings from the environment. The client ID and secret
     * have no defaults, so a missing value becomes null, and the token
     * request reports it.
     */
    static Settings settings() {
        return new Settings(
                envOr("STARFLEET_API_URL", "https://api.pgedge.com")
                        .replaceAll("/+$", ""),
                envOr("STARFLEET_CLIENT_ID", null),
                envOr("STARFLEET_CLIENT_SECRET", null));
    }
    
    /**
     * Returns a deadline the given number of seconds from now, on a clock
     * that only moves forwards.
     */
    static long deadline(int seconds) {
        return System.nanoTime() + TimeUnit.SECONDS.toNanos(seconds);
    }
    
    /** Reports whether a deadline is still in the future. */
    static boolean before(long deadline) {
        return System.nanoTime() - deadline < 0;
    }
    
    /**
     * Guards the state that the clean-up uses, which the main thread and
     * the shutdown hook share (see main).
     */
    static final Object LOCK = new Object();
    
    /** Set by the shutdown hook when SIGINT or SIGTERM arrives. */
    static volatile boolean interrupted;
    
    /**
     * Throws InterruptedException once a signal has arrived, so that the
     * main thread stops making requests. A thread that holds the lock is
     * either creating the database or cleaning up, and both of those must
     * run to the end.
     */
    static void checkInterrupted() throws InterruptedException {
        if (interrupted && !Thread.holdsLock(LOCK)) {
            throw new InterruptedException("interrupted");
        }
    }
    
    /** Waits for the given number of seconds, watching for a signal. */
    static void pause(int seconds) throws InterruptedException {
        long end = deadline(seconds);
        while (before(end)) {
            checkInterrupted();
            Thread.sleep(200);
        }
    }
    ```

=== "C#"

    ```csharp
    // How long to wait for a database to become available, or to disappear
    // after a delete, and how often to check.
    const int TimeoutSeconds = 900;
    const int PollSeconds = 10;
    
    // How many times to look for a database whose create reply was lost.
    const int LookupAttempts = 3;
    
    // Returns the value of an environment variable, or null if the variable
    // is unset or empty, as an unset variable would be.
    static string? EnvValue(string name) =>
        Environment.GetEnvironmentVariable(name) is { Length: > 0 } value
            ? value
            : null;
    
    // Reads the API settings from the environment. The client ID and secret
    // have no defaults, so a missing value becomes null, and the token request
    // reports it.
    static (string BaseUrl, string? ClientId, string? ClientSecret) Settings() =>
        ((EnvValue("STARFLEET_API_URL") ?? "https://api.pgedge.com").TrimEnd('/'),
            EnvValue("STARFLEET_CLIENT_ID"),
            EnvValue("STARFLEET_CLIENT_SECRET"));
    
    var cfg = Settings();
    
    // Returns a deadline the given number of seconds from now, and reports
    // whether it is still in the future, on a clock that only moves forwards.
    static long Deadline(int seconds) => Environment.TickCount64 + seconds * 1000L;
    static bool Before(long deadline) => Environment.TickCount64 < deadline;
    
    // A token that SIGINT or SIGTERM cancels, which abandons the request or
    // the wait in progress. The clean-up replaces it with CancellationToken.None,
    // so that nothing can cut the clean-up short.
    using var signalled = new CancellationTokenSource();
    var cancel = signalled.Token;
    
    // Catches SIGINT and SIGTERM. Setting Cancel stops the default action,
    // which would end the program before it could delete the database, and a
    // second signal does nothing more.
    void OnSignal(PosixSignalContext context)
    {
        context.Cancel = true;
        signalled.Cancel();
    }
    using var onInt = PosixSignalRegistration.Create(PosixSignal.SIGINT, OnSignal);
    using var onTerm = PosixSignalRegistration.Create(PosixSignal.SIGTERM, OnSignal);
    
    // Waits for the given number of seconds; a signal ends the wait early.
    async Task Pause(int seconds) =>
        await Task.Delay(TimeSpan.FromSeconds(seconds), cancel);
    ```

=== "Go"

    ```go
    const (
    	// How long to wait for a database to become available, or to
    	// disappear after a delete, and how often to check.
    	timeout      = 15 * time.Minute
    	pollInterval = 10 * time.Second
    
    	// How many times to look for a database whose create reply was lost.
    	lookupAttempts = 3
    )
    
    // envOr returns the value of an environment variable, or a fallback if
    // the variable is unset or empty.
    func envOr(name, fallback string) string {
    	if value := os.Getenv(name); value != "" {
    		return value
    	}
    	return fallback
    }
    
    // baseURL is the root of the Starfleet API, without a trailing slash.
    func baseURL() string {
    	return strings.TrimRight(envOr("STARFLEET_API_URL", "https://api.pgedge.com"), "/")
    }
    
    // httpClient gives every request a timeout; the default client has none.
    var httpClient = &http.Client{Timeout: 30 * time.Second}
    
    ```

=== "Rust"

    ```rust
    /// How long to wait for a database to become available, or to disappear
    /// after a delete, and how often to check.
    const TIMEOUT: Duration = Duration::from_secs(900);
    const POLL: Duration = Duration::from_secs(10);
    
    /// How many times to look for a database whose create reply was lost.
    const LOOKUP_ATTEMPTS: u32 = 3;
    
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
    ```

=== "Ruby"

    ```ruby
    # How long to wait for a database to become available, or to disappear
    # after a delete, and how often to check.
    TIMEOUT_SECONDS = 900
    POLL_SECONDS = 10
    
    # How many times to look for a database whose create reply was lost.
    LOOKUP_ATTEMPTS = 3
    
    # Returns the value of an environment variable, or a fallback if the
    # variable is unset or empty, as an unset variable would be.
    def env_or(name, fallback)
      value = ENV[name]
      value.nil? || value.empty? ? fallback : value
    end
    
    # Reads the API settings from the environment. The client ID and secret
    # have no defaults, so a missing value becomes nil, and the token request
    # reports it.
    def settings
      {
        base_url: env_or("STARFLEET_API_URL", "https://api.pgedge.com").sub(%r{/+\z}, ""),
        client_id: env_or("STARFLEET_CLIENT_ID", nil),
        client_secret: env_or("STARFLEET_CLIENT_SECRET", nil)
      }
    end
    
    # The current time from a clock that only moves forwards, for deadlines.
    def now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
    ```

=== "curl"

    ```bash
    # How long to wait for a database to become available, or to disappear
    # after a delete, and how often to check.
    timeout_seconds=900
    poll_seconds=10
    
    # The :- expansion treats an empty variable as unset.
    base_url="${STARFLEET_API_URL:-https://api.pgedge.com}"
    base_url="${base_url%/}"
    client_id="${STARFLEET_CLIENT_ID:-}"
    client_secret="${STARFLEET_CLIENT_SECRET:-}"
    ```

## Getting a Token

The program gets a token in the same way as the "Getting an Access Token"
recipe:

=== "Python"

    ```python
    def get_token(config: dict) -> str:
        """Exchanges the client ID and secret for an access token, which the
        Managed API accepts as a bearer token until it expires."""
        if not config["client_id"] or not config["client_secret"]:
            raise RuntimeError(
                "STARFLEET_CLIENT_ID and STARFLEET_CLIENT_SECRET must be set"
            )
    
        response = httpx.post(
            f"{config['base_url']}/account/v1/oauth/token",
            json={
                "grant_type": "client_credentials",
                "client_id": config["client_id"],
                "client_secret": config["client_secret"],
            },
            timeout=30,
        )
        # Turn any 4xx or 5xx status into an httpx.HTTPStatusError.
        response.raise_for_status()
        return response.json()["access_token"]
    ```

=== "TypeScript"

    ```typescript
    // Exchanges the client ID and secret for an access token, which the
    // Managed API accepts as a bearer token until it expires.
    async function getToken(): Promise<string> {
      if (!clientId || !clientSecret) {
        throw new Error(
          "STARFLEET_CLIENT_ID and STARFLEET_CLIENT_SECRET must be set",
        );
      }
    
      const response = await fetch(`${baseUrl}/account/v1/oauth/token`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          grant_type: "client_credentials",
          client_id: clientId,
          client_secret: clientSecret,
        }),
        signal: AbortSignal.timeout(30_000),
      });
    
      // fetch only rejects on network failures, so check the status here.
      if (!response.ok) {
        throw new Error(
          `token request failed: ${response.status} ${await response.text()}`,
        );
      }
      const body = (await response.json()) as { access_token: string };
      return body.access_token;
    }
    ```

=== "Java"

    ```java
    /** One client serves every request; it is safe to share. */
    static final HttpClient CLIENT = HttpClient.newBuilder()
            .connectTimeout(Duration.ofSeconds(30))
            .build();
    
    /** Converts between JSON text and Java objects. */
    static final ObjectMapper JSON = new ObjectMapper();
    
    /** An error reply from the API, with its HTTP status. */
    static class ApiException extends IOException {
        final int status;
    
        ApiException(int status, String message) {
            super(message);
            this.status = status;
        }
    }
    
    /**
     * Sends a request and returns the response with its whole body. The
     * request timeout stops applying once the headers arrive, so a server
     * that stalls part of the way through the body would hang send(); this
     * applies the same timeout to the whole exchange instead.
     */
    static HttpResponse<String> send(HttpRequest request)
            throws IOException, InterruptedException {
        Duration timeout = request.timeout().orElseThrow();
        CompletableFuture<HttpResponse<String>> pending =
                CLIENT.sendAsync(request, HttpResponse.BodyHandlers.ofString());
        try {
            return pending.get(timeout.toMillis(), TimeUnit.MILLISECONDS);
        } catch (TimeoutException e) {
            pending.cancel(true);
            throw new HttpTimeoutException("request timed out");
        } catch (ExecutionException e) {
            if (e.getCause() instanceof IOException cause) {
                throw cause;
            }
            throw new IOException(e.getCause());
        }
    }
    
    /**
     * Sends a request with a JSON body, if there is one, and returns the
     * decoded JSON reply, or null if the reply has no body. A 4xx or 5xx
     * reply throws an ApiException.
     */
    static JsonNode request(String method, String url, String path,
            String token, Object body) throws IOException, InterruptedException {
        checkInterrupted();
        HttpRequest.Builder request = HttpRequest.newBuilder(URI.create(url))
                .timeout(Duration.ofSeconds(30));
        if (token != null) {
            request.header("Authorization", "Bearer " + token);
        }
        HttpRequest.BodyPublisher content = HttpRequest.BodyPublishers.noBody();
        if (body != null) {
            request.header("Content-Type", "application/json");
            content = HttpRequest.BodyPublishers.ofString(
                    JSON.writeValueAsString(body));
        }
    
        HttpResponse<String> response = send(request.method(method, content).build());
        if (response.statusCode() >= 400) {
            throw new ApiException(response.statusCode(), method + " " + path
                    + " failed with status " + response.statusCode() + ": "
                    + response.body().strip());
        }
        String text = response.body();
        return text.isEmpty() ? null : JSON.readTree(text);
    }
    
    /**
     * Returns a field of a JSON object as text, and throws if the field is
     * missing.
     */
    static String field(JsonNode node, String name) {
        JsonNode value = (node == null) ? null : node.get(name);
        if (value == null || value.isNull()) {
            throw new IllegalStateException("the reply has no " + name);
        }
        return value.asString();
    }
    
    /**
     * Exchanges the client ID and secret for an access token, which the
     * Managed API accepts as a bearer token until it expires.
     */
    static String getToken(Settings cfg) throws IOException, InterruptedException {
        if (cfg.clientId() == null || cfg.clientSecret() == null) {
            throw new IllegalStateException(
                    "STARFLEET_CLIENT_ID and STARFLEET_CLIENT_SECRET must be set");
        }
        String path = "/account/v1/oauth/token";
        JsonNode token = request("POST", cfg.baseUrl() + path, path, null, Map.of(
                "grant_type", "client_credentials",
                "client_id", cfg.clientId(),
                "client_secret", cfg.clientSecret()));
        return field(token, "access_token");
    }
    ```

=== "C#"

    ```csharp
    // One client serves every request. Its timeout covers the whole exchange,
    // the body of the reply included.
    var http = new HttpClient { Timeout = TimeSpan.FromSeconds(30) };
    
    // Sends a request with a JSON body, if there is one, and returns the
    // decoded JSON reply, or null if the reply has no body. A 4xx or 5xx reply
    // throws an HttpRequestException that carries the status.
    async Task<JsonNode?> Request(string method, string url, string path,
        string? token, object? body, CancellationToken cancelRequest)
    {
        using var request = new HttpRequestMessage(new HttpMethod(method), url);
        if (token is not null)
        {
            request.Headers.Authorization =
                new AuthenticationHeaderValue("Bearer", token);
        }
        if (body is not null)
        {
            // StringContent sends a Content-Length header; JsonContent would
            // stream the body in chunks, which not every server accepts.
            request.Content = new StringContent(
                JsonSerializer.Serialize(body), Encoding.UTF8, "application/json");
        }
    
        using var response = await http.SendAsync(request, cancelRequest);
        var text = await response.Content.ReadAsStringAsync(cancelRequest);
        if ((int)response.StatusCode >= 400)
        {
            throw new HttpRequestException(
                $"{method} {path} failed with status {(int)response.StatusCode}: "
                + text.Trim(), null, response.StatusCode);
        }
        return text.Length == 0 ? null : JsonNode.Parse(text);
    }
    
    // Returns a field of a JSON object as text, and throws if the field is
    // missing.
    static string Field(JsonNode? node, string name) =>
        node?[name] is JsonNode value
            ? value.ToString()
            : throw new InvalidOperationException($"the reply has no {name}");
    
    // Exchanges the client ID and secret for an access token, which the
    // Managed API accepts as a bearer token until it expires.
    async Task<string> GetToken()
    {
        if (cfg.ClientId is null || cfg.ClientSecret is null)
        {
            throw new InvalidOperationException(
                "STARFLEET_CLIENT_ID and STARFLEET_CLIENT_SECRET must be set");
        }
        const string path = "/account/v1/oauth/token";
        var token = await Request("POST", cfg.BaseUrl + path, path, null, new
        {
            grant_type = "client_credentials",
            client_id = cfg.ClientId,
            client_secret = cfg.ClientSecret,
        }, cancel);
        return Field(token, "access_token");
    }
    ```

=== "Go"

    ```go
    // getToken exchanges the client ID and secret for an access token, which
    // the Managed API accepts as a bearer token until it expires.
    func getToken(ctx context.Context) (string, error) {
    	clientID := os.Getenv("STARFLEET_CLIENT_ID")
    	clientSecret := os.Getenv("STARFLEET_CLIENT_SECRET")
    	if clientID == "" || clientSecret == "" {
    		return "", errors.New("STARFLEET_CLIENT_ID and STARFLEET_CLIENT_SECRET must be set")
    	}
    
    	body, err := json.Marshal(map[string]string{
    		"grant_type":    "client_credentials",
    		"client_id":     clientID,
    		"client_secret": clientSecret,
    	})
    	if err != nil {
    		return "", err
    	}
    
    	req, err := http.NewRequestWithContext(ctx, http.MethodPost,
    		baseURL()+"/account/v1/oauth/token", bytes.NewReader(body))
    	if err != nil {
    		return "", err
    	}
    	req.Header.Set("Content-Type", "application/json")
    
    	resp, err := httpClient.Do(req)
    	if err != nil {
    		return "", fmt.Errorf("token request failed: %w", err)
    	}
    	defer resp.Body.Close()
    
    	// A non-2xx status is not a Go error, so check it explicitly.
    	if resp.StatusCode != http.StatusOK {
    		detail, _ := io.ReadAll(io.LimitReader(resp.Body, 1024))
    		return "", fmt.Errorf("token request failed: %s %s", resp.Status, detail)
    	}
    
    	var token struct {
    		AccessToken string `json:"access_token"`
    	}
    	if err := json.NewDecoder(resp.Body).Decode(&token); err != nil {
    		return "", fmt.Errorf("decoding the token response: %w", err)
    	}
    	return token.AccessToken, nil
    }
    
    ```

=== "Rust"

    ```rust
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
    ```

=== "Ruby"

    ```ruby
    # An error reply from the API, with its HTTP status.
    class ApiError < StandardError
      attr_reader :status
    
      def initialize(status, message)
        super(message)
        @status = status
      end
    end
    
    # Sends a request with a JSON body, if there is one, and returns the
    # response. Net::HTTP has no overall timeout, so this limits both the
    # connection and each read.
    def send_request(method, url, headers, body)
      uri = URI(url)
      headers = headers.merge("Content-Type" => "application/json") if body
      Net::HTTP.start(uri.host, uri.port,
                      use_ssl: uri.scheme == "https",
                      open_timeout: 30, read_timeout: 30, write_timeout: 30) do |http|
        http.send_request(method, uri.request_uri, body&.to_json, headers)
      end
    end
    
    # Raises an ApiError for a 4xx or 5xx reply.
    def check_status(method, path, response)
      return if response.code.to_i < 400
    
      raise ApiError.new(response.code.to_i,
                         "#{method} #{path} failed with status #{response.code}: " \
                         "#{response.body.to_s.strip}")
    end
    
    # Exchanges the client ID and secret for an access token, which the
    # Managed API accepts as a bearer token until it expires.
    def get_token(config)
      unless config[:client_id] && config[:client_secret]
        raise "STARFLEET_CLIENT_ID and STARFLEET_CLIENT_SECRET must be set"
      end
    
      path = "/account/v1/oauth/token"
      response = send_request("POST", "#{config[:base_url]}#{path}", {}, {
                                grant_type: "client_credentials",
                                client_id: config[:client_id],
                                client_secret: config[:client_secret]
                              })
      check_status("POST", path, response)
      JSON.parse(response.body).fetch("access_token")
    end
    ```

=== "curl"

    ```bash
    # Exchanges the client ID and secret for an access token, which the
    # Managed API accepts as a bearer token until it expires, and prints
    # the token.
    get_token() {
        if [[ -z "$client_id" || -z "$client_secret" ]]; then
            echo "Error: STARFLEET_CLIENT_ID and STARFLEET_CLIENT_SECRET must be set" >&2
            return 1
        fi
    
        # jq builds the body from the environment, and curl reads it from
        # standard input with --data @-, so the secret never appears in the
        # process list. --fail-with-body makes curl exit non-zero on an HTTP
        # error status whilst still printing the API's error message.
        jq -n '{grant_type: "client_credentials",
                client_id: env.STARFLEET_CLIENT_ID,
                client_secret: env.STARFLEET_CLIENT_SECRET}' |
            curl --silent --show-error --fail-with-body --max-time 30 \
                --header "Content-Type: application/json" \
                --data @- \
                "$base_url/account/v1/oauth/token" |
            jq -er '.access_token'
    }
    ```

## Calling the Managed API

The `api` function sends an authenticated request and returns the decoded
reply. The program also reacts to particular error statuses, so the error that
the function raises carries the HTTP status:

=== "Python"

    ```python
    def api(config: dict, token: str, method: str, path: str, body=None):
        """Sends an authenticated request to the Managed API and returns the
        decoded JSON reply, or None if the reply has no body."""
        response = httpx.request(
            method,
            f"{config['base_url']}/managed/v1{path}",
            headers={"Authorization": f"Bearer {token}"},
            json=body,
            timeout=30,
        )
        response.raise_for_status()
        return response.json() if response.content else None
    ```

=== "TypeScript"

    ```typescript
    // An error reply from the Managed API, with its HTTP status.
    class ApiError extends Error {
      constructor(
        readonly status: number,
        message: string,
      ) {
        super(message);
      }
    }
    
    // Sends an authenticated request to the Managed API and returns the
    // decoded JSON reply, or undefined if the reply has no body. The request
    // stops when the user presses Ctrl-C, unless the caller passes a
    // different signal, as the cleanup does.
    async function api<T>(
      token: string,
      method: string,
      path: string,
      body?: unknown,
      signal: AbortSignal = interrupt.signal,
    ): Promise<T | undefined> {
      const response = await fetch(`${baseUrl}/managed/v1${path}`, {
        method,
        headers: {
          Authorization: `Bearer ${token}`,
          ...(body === undefined ? {} : { "Content-Type": "application/json" }),
        },
        body: body === undefined ? undefined : JSON.stringify(body),
        signal: AbortSignal.any([signal, AbortSignal.timeout(30_000)]),
      });
      if (!response.ok) {
        throw new ApiError(
          response.status,
          `${method} ${path} failed: ${response.status} ${await response.text()}`,
        );
      }
      const text = await response.text();
      return text ? (JSON.parse(text) as T) : undefined;
    }
    ```

=== "Java"

    ```java
    /**
     * Sends an authenticated request to the Managed API and returns the
     * decoded JSON reply, or null if the reply has no body.
     */
    static JsonNode api(Settings cfg, String token, String method, String path,
            Object body) throws IOException, InterruptedException {
        return request(method, cfg.baseUrl() + "/managed/v1" + path, path,
                token, body);
    }
    ```

=== "C#"

    ```csharp
    // Sends an authenticated request to the Managed API and returns the
    // decoded JSON reply, or null if the reply has no body. The create call
    // passes interruptible: false, so that a signal cannot abandon a request
    // whose result the program must not lose.
    async Task<JsonNode?> Api(string token, string method, string path,
        object? body = null, bool interruptible = true) =>
        await Request(method, $"{cfg.BaseUrl}/managed/v1{path}", path, token,
            body, interruptible ? cancel : CancellationToken.None);
    ```

=== "Go"

    ```go
    // APIError is an error reply from the Managed API, with its HTTP status.
    type APIError struct {
    	Status  int
    	Message string
    }
    
    func (e *APIError) Error() string { return e.Message }
    
    // api sends an authenticated request to the Managed API. It encodes body
    // as JSON if it is not nil, and decodes the reply into result if that is
    // not nil and the reply has content.
    func api(ctx context.Context, token, method, path string, body, result any) error {
    	var reader io.Reader
    	if body != nil {
    		encoded, err := json.Marshal(body)
    		if err != nil {
    			return err
    		}
    		reader = bytes.NewReader(encoded)
    	}
    
    	req, err := http.NewRequestWithContext(ctx, method, baseURL()+"/managed/v1"+path, reader)
    	if err != nil {
    		return err
    	}
    	req.Header.Set("Authorization", "Bearer "+token)
    	if body != nil {
    		req.Header.Set("Content-Type", "application/json")
    	}
    
    	resp, err := httpClient.Do(req)
    	if err != nil {
    		return fmt.Errorf("%s %s failed: %w", method, path, err)
    	}
    	defer resp.Body.Close()
    
    	data, err := io.ReadAll(resp.Body)
    	if err != nil {
    		return err
    	}
    	if resp.StatusCode >= 300 {
    		return &APIError{
    			Status:  resp.StatusCode,
    			Message: fmt.Sprintf("%s %s failed: %s %s", method, path, resp.Status, data),
    		}
    	}
    	if result == nil || len(data) == 0 {
    		return nil
    	}
    	return json.Unmarshal(data, result)
    }
    
    // sleep waits for the interval, or until the context ends.
    func sleep(ctx context.Context) error {
    	select {
    	case <-time.After(pollInterval):
    		return nil
    	case <-ctx.Done():
    		return ctx.Err()
    	}
    }
    
    ```

=== "Rust"

    ```rust
    /// Sends an authenticated request to the Managed API and returns the
    /// decoded JSON reply, or null if the reply has no body. After a signal,
    /// it returns an error without sending anything.
    fn api(cfg: &Settings, token: &str, method: Method, path: &str, body: Option<&Value>) -> Result<Value> {
        check_interrupted()?;
        let url = format!("{}/managed/v1{path}", cfg.base_url);
        request(method, &url, path, Some(token), body)
    }
    ```

=== "Ruby"

    ```ruby
    # Sends an authenticated request to the Managed API and returns the
    # decoded JSON reply, or nil if the reply has no body.
    def api(config, token, method, path, body = nil)
      response = send_request(method, "#{config[:base_url]}/managed/v1#{path}",
                              { "Authorization" => "Bearer #{token}" }, body)
      check_status(method, path, response)
      text = response.body.to_s
      text.empty? ? nil : JSON.parse(text)
    end
    ```

=== "curl"

    ```bash
    # Sends an authenticated request to the Managed API and prints the JSON
    # reply. The first argument is the method, the second is the path, and any
    # others go to curl, such as --data @- to send standard input as the body.
    # The --config option reads the Authorization header from a file that
    # bash creates from the printf command, so the token never appears in the
    # process list; that leaves standard input free for the body.
    api() {
        local method="$1" path="$2"
        shift 2
        curl --silent --show-error --fail-with-body --max-time 30 \
            --request "$method" \
            --config <(printf 'header = "Authorization: Bearer %s"\n' "$token") \
            "$@" "$base_url/managed/v1$path"
    }
    
    # Sends a request and prints only the HTTP status, for the calls that
    # react to a particular status. A status of 000 means no reply arrived.
    api_status() {
        curl --silent --output /dev/null --write-out '%{http_code}' --max-time 30 \
            --request "$1" \
            --config <(printf 'header = "Authorization: Bearer %s"\n' "$token") \
            "$base_url/managed/v1$2" || true
    }
    ```

## Choosing a Region and Size

The program creates its own database, with the code from the "Creating a
Database and Waiting for It" recipe. It chooses the first region and the
smallest size, and the following code makes the choice:

=== "Python"

    ```python
    def choose_placement(config: dict, token: str) -> tuple[str, str]:
        """Returns the region and size for the new database.
    
        The API lists sizes smallest first, so the first one is the cheapest.
        The API does not price regions, so the example takes the first one.
        """
        regions = api(config, token, "GET", "/regions")
        sizes = api(config, token, "GET", "/sizes")
        if not regions or not sizes:
            raise RuntimeError("the API offers no region or size")
        return regions[0]["region"], sizes[0]["name"]
    ```

=== "TypeScript"

    ```typescript
    // Returns the region and size for the new database. The API lists sizes
    // smallest first, so the first one is the cheapest. The API does not
    // price regions, so the example takes the first one.
    async function choosePlacement(
      token: string,
    ): Promise<{ region: string; size: string }> {
      const regions = await api<{ region: string }[]>(token, "GET", "/regions");
      const sizes = await api<{ name: string }[]>(token, "GET", "/sizes");
      if (!regions?.length || !sizes?.length) {
        throw new Error("the API offers no region or size");
      }
      return { region: regions[0].region, size: sizes[0].name };
    }
    ```

=== "Java"

    ```java
    /** The region and size of a new database. */
    record Placement(String region, String size) {}
    
    /**
     * Returns the region and size for the new database. The API lists sizes
     * smallest first, so the first one is the cheapest. The API does not
     * price regions, so the example takes the first one.
     */
    static Placement choosePlacement(Settings cfg, String token)
            throws IOException, InterruptedException {
        JsonNode regions = api(cfg, token, "GET", "/regions", null);
        JsonNode sizes = api(cfg, token, "GET", "/sizes", null);
        if (regions == null || sizes == null || regions.size() == 0
                || sizes.size() == 0) {
            throw new IllegalStateException("the API offers no region or size");
        }
        return new Placement(field(regions.get(0), "region"),
                field(sizes.get(0), "name"));
    }
    ```

=== "C#"

    ```csharp
    // Returns the region and size for the new database. The API lists sizes
    // smallest first, so the first one is the cheapest. The API does not price
    // regions, so the example takes the first one.
    async Task<(string Region, string Size)> ChoosePlacement(string token)
    {
        var regions = await Api(token, "GET", "/regions") as JsonArray;
        var sizes = await Api(token, "GET", "/sizes") as JsonArray;
        if (regions is not { Count: > 0 } || sizes is not { Count: > 0 })
        {
            throw new InvalidOperationException("the API offers no region or size");
        }
        return (Field(regions[0], "region"), Field(sizes[0], "name"));
    }
    ```

=== "Go"

    ```go
    // choosePlacement returns the region and size for the new database. The
    // API lists sizes smallest first, so the first one is the cheapest. The
    // API does not price regions, so the example takes the first one.
    func choosePlacement(ctx context.Context, token string) (region, size string, err error) {
    	var regions []struct {
    		Region string `json:"region"`
    	}
    	var sizes []struct {
    		Name string `json:"name"`
    	}
    	if err = api(ctx, token, http.MethodGet, "/regions", nil, &regions); err != nil {
    		return
    	}
    	if err = api(ctx, token, http.MethodGet, "/sizes", nil, &sizes); err != nil {
    		return
    	}
    	if len(regions) == 0 || len(sizes) == 0 {
    		err = errors.New("the API offers no region or size")
    		return
    	}
    	return regions[0].Region, sizes[0].Name, nil
    }
    
    ```

=== "Rust"

    ```rust
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
    ```

=== "Ruby"

    ```ruby
    # Returns the region and size for the new database. The API lists sizes
    # smallest first, so the first one is the cheapest. The API does not price
    # regions, so the example takes the first one.
    def choose_placement(config, token)
      regions = api(config, token, "GET", "/regions")
      sizes = api(config, token, "GET", "/sizes")
      raise "the API offers no region or size" if regions.to_a.empty? || sizes.to_a.empty?
    
      [regions[0].fetch("region"), sizes[0].fetch("name")]
    end
    ```

=== "curl"

    ```bash
    # Prints the region and size for the new database, separated by a space.
    # The API lists sizes smallest first, so the first one is the cheapest.
    # The API does not price regions, so the example takes the first one.
    choose_placement() {
        local region size
        region="$(api GET /regions | jq -er '.[0].region')"
        size="$(api GET /sizes | jq -er '.[0].name')"
        echo "$region $size"
    }
    ```

## Creating the Database

The following code creates the database, which only your machine can reach, and
names it with the `cookbook-` prefix:

=== "Python"

    ```python
    def client_ip(config: dict, token: str) -> str:
        """Returns the address that the API sees requests come from."""
        # A new database is closed to everyone until an allowlist rule admits
        # an address. The API reports the address it sees this request come
        # from, which is the one to admit; a bare address means a single host.
        return api(config, token, "GET", "/client-ip")["ip_address"]
    
    
    def create_database(
        config: dict, token: str, name: str, display_name: str, region: str,
        size: str, ip: str,
    ) -> dict:
        """Creates a database that only this machine can reach, and returns
        the API's description of it, which includes its ID."""
        return api(config, token, "POST", "/databases", {
            # The name becomes the Postgres database name, so it holds only
            # letters and digits, and the readable cookbook- prefix goes in
            # the display name. The program also uses the name to find the
            # database again if the reply to this request is lost.
            "name": name,
            "display_name": display_name,
            "region": region,
            "size": size,
            "ip_allowlist": {"rules": [{"cidr": ip, "label": "cookbook"}]},
        })
    ```

=== "TypeScript"

    ```typescript
    interface Database {
      id: string;
      display_name: string;
      status: string;
    }
    
    // Returns this machine's public IP address as the API sees it.
    async function clientIp(token: string): Promise<string> {
      // A new database is closed to everyone until an allowlist rule admits
      // an address. The API reports the address it sees this request come
      // from, which is the one to admit; a bare address means a single host.
      const reply = await api<{ ip_address: string }>(token, "GET", "/client-ip");
      return reply!.ip_address;
    }
    
    // Creates a database that only this machine can reach, and returns the
    // API's description of it, which includes its ID.
    async function createDatabase(
      token: string,
      name: string,
      displayName: string,
      region: string,
      size: string,
      ip: string,
    ): Promise<Database> {
      const database = await api<Database>(token, "POST", "/databases", {
        // The name becomes the Postgres database name, so it holds only
        // letters and digits, and the readable cookbook- prefix goes in the
        // display name. The program also uses the name to find the database
        // again if the reply to this request is lost.
        name,
        display_name: displayName,
        region,
        size,
        ip_allowlist: { rules: [{ cidr: ip, label: "cookbook" }] },
      });
      return database!;
    }
    ```

=== "Java"

    ```java
    /** Returns the address that the API sees requests come from. */
    static String clientIp(Settings cfg, String token)
            throws IOException, InterruptedException {
        // A new database is closed to everyone until an allowlist rule
        // admits an address. The API reports the address it sees this
        // request come from, which is the one to admit; a bare address
        // means a single host.
        return field(api(cfg, token, "GET", "/client-ip", null), "ip_address");
    }
    
    /**
     * Creates a database that only this machine can reach, and returns the
     * API's description of it, which includes its ID.
     */
    static JsonNode createDatabase(Settings cfg, String token, String name,
            String displayName, Placement placement, String ip)
            throws IOException, InterruptedException {
        return api(cfg, token, "POST", "/databases", Map.of(
                // The name becomes the Postgres database name, so it holds
                // only letters and digits, and the readable cookbook- prefix
                // goes in the display name. The program also uses the name
                // to find the database again if the reply to this request
                // is lost.
                "name", name,
                "display_name", displayName,
                "region", placement.region(),
                "size", placement.size(),
                "ip_allowlist", Map.of("rules", List.of(
                        Map.of("cidr", ip, "label", "cookbook")))));
    }
    ```

=== "C#"

    ```csharp
    // Returns the address that the API sees requests come from.
    async Task<string> ClientIp(string token)
    {
        // A new database is closed to everyone until an allowlist rule admits
        // an address. The API reports the address it sees this request come
        // from, which is the one to admit; a bare address means a single host.
        return Field(await Api(token, "GET", "/client-ip"), "ip_address");
    }
    
    // Creates a database that only this machine can reach, and returns the
    // API's description of it, which includes its ID.
    async Task<JsonNode?> CreateDatabase(string token, string name,
        string displayName, string region, string size, string ip) =>
        await Api(token, "POST", "/databases", new
        {
            // The name becomes the Postgres database name, so it holds only
            // letters and digits, and the readable cookbook- prefix goes in the
            // display name. The program also uses the name to find the
            // database again if the reply to this request is lost.
            name,
            display_name = displayName,
            region,
            size,
            ip_allowlist = new
            {
                rules = new[] { new { cidr = ip, label = "cookbook" } },
            },
        }, interruptible: false);
    ```

=== "Go"

    ```go
    // Database is the part of the API's description of a database that the
    // example uses.
    type Database struct {
    	ID          string `json:"id"`
    	DisplayName string `json:"display_name"`
    	Status      string `json:"status"`
    }
    
    // randomSuffix returns six random hexadecimal digits.
    func randomSuffix() (string, error) {
    	raw := make([]byte, 3)
    	if _, err := rand.Read(raw); err != nil {
    		return "", err
    	}
    	return hex.EncodeToString(raw), nil
    }
    
    // clientIP returns this machine's public IP address as the API sees it.
    func clientIP(ctx context.Context, token string) (string, error) {
    	// A new database is closed to everyone until an allowlist rule admits
    	// an address. The API reports the address it sees this request come
    	// from, which is the one to admit; a bare address means a single host.
    	var ip struct {
    		IPAddress string `json:"ip_address"`
    	}
    	if err := api(ctx, token, http.MethodGet, "/client-ip", nil, &ip); err != nil {
    		return "", err
    	}
    	return ip.IPAddress, nil
    }
    
    // createDatabase creates a database that only this machine can reach,
    // and returns the API's description of it, which includes its ID.
    func createDatabase(ctx context.Context, token, name, displayName, region, size, ip string) (*Database, error) {
    	var database Database
    	err := api(ctx, token, http.MethodPost, "/databases", map[string]any{
    		// The name becomes the Postgres database name, so it holds only
    		// letters and digits, and the readable cookbook- prefix goes in
    		// the display name. The program also uses the name to find the
    		// database again if the reply to this request is lost.
    		"name":         name,
    		"display_name": displayName,
    		"region":       region,
    		"size":         size,
    		"ip_allowlist": map[string]any{
    			"rules": []map[string]string{{"cidr": ip, "label": "cookbook"}},
    		},
    	}, &database)
    	if err != nil {
    		return nil, err
    	}
    	return &database, nil
    }
    
    ```

=== "Rust"

    ```rust
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
    ```

=== "Ruby"

    ```ruby
    # Returns the address that the API sees requests come from.
    def client_ip(config, token)
      # A new database is closed to everyone until an allowlist rule admits an
      # address. The API reports the address it sees this request come from,
      # which is the one to admit; a bare address means a single host.
      api(config, token, "GET", "/client-ip").fetch("ip_address")
    end
    
    # Creates a database that only this machine can reach, and returns the
    # API's description of it, which includes its ID.
    def create_database(config, token, name, display_name, region, size, ip)
      api(config, token, "POST", "/databases", {
            # The name becomes the Postgres database name, so it holds only
            # letters and digits, and the readable cookbook- prefix goes in the
            # display name. The program also uses the name to find the database
            # again if the reply to this request is lost.
            name: name,
            display_name: display_name,
            region: region,
            size: size,
            ip_allowlist: { rules: [{ cidr: ip, label: "cookbook" }] }
          })
    end
    ```

=== "curl"

    ```bash
    # Prints the address that the API sees requests come from. A new database
    # is closed to everyone until an allowlist rule admits an address, and this
    # is the one to admit; a bare address means a single host.
    client_ip() {
        api GET /client-ip | jq -er '.ip_address'
    }
    
    # Creates a database that only this machine can reach, and prints the
    # API's description of it, which includes its ID.
    create_database() {
        local name="$1" display_name="$2" region="$3" size="$4" ip="$5"
        # The name becomes the Postgres database name, so it holds only letters
        # and digits, and the readable cookbook- prefix goes in the display
        # name. The script also uses the name to find the database again if the
        # reply to this request is lost.
        jq -n --arg name "$name" --arg display_name "$display_name" \
            --arg region "$region" --arg size "$size" --arg ip "$ip" \
            '{name: $name, display_name: $display_name,
              region: $region, size: $size,
              ip_allowlist: {rules: [{cidr: $ip, label: "cookbook"}]}}' |
            api POST /databases --header "Content-Type: application/json" \
                --data @- --write-out '\n%{http_code}'
    }
    ```

## Waiting for the Database

The following code polls the database until its status is `available`, and
stops at once if the status is `degraded` or `failed`:

=== "Python"

    ```python
    # The API does not document its status values; the example treats these
    # two as failures, which end the wait at once instead of leaving it to run
    # until the time limit.
    FAILED_STATUSES = {"degraded", "failed"}
    
    
    def wait_until_available(config: dict, token: str, database_id: str) -> None:
        """Polls the database until its status is available."""
        deadline = time.monotonic() + TIMEOUT_SECONDS
        last = None
        while time.monotonic() < deadline:
            status = api(config, token, "GET", f"/databases/{database_id}")["status"]
            if status != last:
                print(f"Database status: {status}")
                last = status
            if status == "available":
                return
            if status in FAILED_STATUSES:
                raise RuntimeError(f"the database has the status {status}")
            time.sleep(POLL_SECONDS)
        raise TimeoutError(f"the database was not available after {TIMEOUT_SECONDS} seconds")
    ```

=== "TypeScript"

    ```typescript
    // Polls the database until its status is available.
    async function waitUntilAvailable(
      token: string,
      databaseId: string,
    ): Promise<void> {
      const deadline = Date.now() + TIMEOUT_MS;
      let last = "";
      while (Date.now() < deadline) {
        const database = await api<Database>(token, "GET", `/databases/${databaseId}`);
        if (database!.status !== last) {
          console.log(`Database status: ${database!.status}`);
          last = database!.status;
        }
        if (database!.status === "available") {
          return;
        }
        // The API does not document its status values; the example treats
        // these two as failures, which end the wait at once instead of leaving
        // it to run until the time limit.
        if (database!.status === "degraded" || database!.status === "failed") {
          throw new Error(`the database has the status ${database!.status}`);
        }
        await sleep(POLL_MS, undefined, { signal: interrupt.signal });
      }
      throw new Error(`the database was not available after ${TIMEOUT_MS / 1000} seconds`);
    }
    ```

=== "Java"

    ```java
    /**
     * The API does not document its status values; the example treats
     * these two as failures, which end the wait at once instead of leaving
     * it to run until the time limit.
     */
    static final Set<String> FAILED_STATUSES = Set.of("degraded", "failed");
    
    /** Polls the database until its status is available. */
    static void waitUntilAvailable(Settings cfg, String token, String databaseId)
            throws IOException, InterruptedException {
        long deadline = deadline(TIMEOUT_SECONDS);
        String last = null;
        while (before(deadline)) {
            String status = field(
                    api(cfg, token, "GET", "/databases/" + databaseId, null),
                    "status");
            if (!status.equals(last)) {
                System.out.println("Database status: " + status);
                last = status;
            }
            if (status.equals("available")) {
                return;
            }
            if (FAILED_STATUSES.contains(status)) {
                throw new IllegalStateException(
                        "the database has the status " + status);
            }
            pause(POLL_SECONDS);
        }
        throw new IllegalStateException("the database was not available after "
                + TIMEOUT_SECONDS + " seconds");
    }
    ```

=== "C#"

    ```csharp
    // The API does not document its status values; the example treats these
    // two as failures, which end the wait at once instead of leaving it to run
    // until the time limit.
    string[] failedStatuses = ["degraded", "failed"];
    
    // Polls the database until its status is available.
    async Task WaitUntilAvailable(string token, string databaseId)
    {
        var deadline = Deadline(TimeoutSeconds);
        string? last = null;
        while (Before(deadline))
        {
            var status = Field(
                await Api(token, "GET", $"/databases/{databaseId}"), "status");
            if (status != last)
            {
                Console.WriteLine($"Database status: {status}");
                last = status;
            }
            if (status == "available")
            {
                return;
            }
            if (failedStatuses.Contains(status))
            {
                throw new InvalidOperationException(
                    $"the database has the status {status}");
            }
            await Pause(PollSeconds);
        }
        throw new InvalidOperationException(
            $"the database was not available after {TimeoutSeconds} seconds");
    }
    ```

=== "Go"

    ```go
    // waitUntilAvailable polls the database until its status is available.
    func waitUntilAvailable(ctx context.Context, token, id string) error {
    	deadline := time.Now().Add(timeout)
    	last := ""
    	for time.Now().Before(deadline) {
    		var database Database
    		if err := api(ctx, token, http.MethodGet, "/databases/"+id, nil, &database); err != nil {
    			return err
    		}
    		if database.Status != last {
    			fmt.Printf("Database status: %s\n", database.Status)
    			last = database.Status
    		}
    		if database.Status == "available" {
    			return nil
    		}
    		// The API does not document its status values; the example
    		// treats these two as failures, which end the wait at once
    		// instead of leaving it to run until the time limit.
    		if database.Status == "degraded" || database.Status == "failed" {
    			return fmt.Errorf("the database has the status %s", database.Status)
    		}
    		if err := sleep(ctx); err != nil {
    			return err
    		}
    	}
    	return fmt.Errorf("the database was not available after %s", timeout)
    }
    
    ```

=== "Rust"

    ```rust
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
    ```

=== "Ruby"

    ```ruby
    # The API does not document its status values; the example treats these
    # two as failures, which end the wait at once instead of leaving it to run
    # until the time limit.
    FAILED_STATUSES = %w[degraded failed].freeze
    
    # Polls the database until its status is available.
    def wait_until_available(config, token, database_id)
      deadline = now + TIMEOUT_SECONDS
      last = nil
      while now < deadline
        status = api(config, token, "GET", "/databases/#{database_id}").fetch("status")
        if status != last
          puts "Database status: #{status}"
          last = status
        end
        return if status == "available"
        raise "the database has the status #{status}" if FAILED_STATUSES.include?(status)
    
        sleep POLL_SECONDS
      end
      raise "the database was not available after #{TIMEOUT_SECONDS} seconds"
    end
    ```

=== "curl"

    ```bash
    # Polls the database until its status is available.
    wait_until_available() {
        local id="$1" deadline=$((SECONDS + timeout_seconds)) status last=""
        while ((SECONDS < deadline)); do
            status="$(api GET "/databases/$id" | jq -er '.status')"
            if [[ "$status" != "$last" ]]; then
                echo "Database status: $status"
                last="$status"
            fi
            [[ "$status" == "available" ]] && return 0
            # The API does not document its status values; the example treats
            # these two as failures, which end the wait at once instead of
            # leaving it to run until the time limit.
            if [[ "$status" == "degraded" || "$status" == "failed" ]]; then
                echo "Error: the database has the status $status" >&2
                return 1
            fi
            sleep "$poll_seconds"
        done
        echo "Error: the database was not available after $timeout_seconds seconds" >&2
        return 1
    }
    ```

## Taking and Tracking the Backup

The API takes an on-demand backup from a `POST` request to the backup endpoint
of a database, with a `kind` of `hot` or `durable`. The API documents a hot
backup as a fast local snapshot, and a durable backup as a fresh base backup
that streams to object storage and needs the durable tier to be enabled for the
database, so the example takes a hot backup. The API answers 202 with the
pending backup, and runs the backup in the background. The API documents
`completed` as the status of a usable backup but does not list the others. In
testing, the status went from `pending` to `started` to `completed`, so the
program treats `failed` as a failure that ends the wait at once, and anything
else as still in progress. The API records the progress of managed database
operations as tasks, with the subject kind `database` and the database ID as
the subject, and in testing a database with one backup had two tasks, named
`create-managed` and `backup-managed`, that had both succeeded. The task names
are not in the specification. After the database is deleted, the program asks
for the backup once more and reports what it finds, because the specification
does not say what happens to a backup when its database goes. In testing, the
API still listed the backup. The following code takes the backup, waits for it,
and lists the tasks:

=== "Python"

    ```python
    # The API does not document its backup status values beyond "completed",
    # which marks a usable backup; the example treats "failed" as a failure,
    # which ends the wait at once instead of leaving it to run until the time
    # limit.
    FAILED_BACKUP_STATUSES = {"failed"}
    
    
    def take_backup(config: dict, token: str, database_id: str) -> dict:
        """Starts an on-demand backup and returns the pending backup."""
        # The hot kind is a fast local snapshot. The durable kind streams a
        # base backup to object storage, and needs the durable tier to be
        # enabled for the database. The API answers 202 at once and runs the
        # backup in the background.
        return api(
            config, token, "POST", f"/databases/{database_id}/backup",
            {"kind": "hot"},
        )
    
    
    def wait_for_backup(config: dict, token: str, backup_id: str) -> None:
        """Polls the backup until its status is completed."""
        deadline = time.monotonic() + TIMEOUT_SECONDS
        last = None
        while time.monotonic() < deadline:
            status = api(config, token, "GET", f"/backups/{backup_id}")["status"]
            if status != last:
                print(f"Backup status: {status}")
                last = status
            if status == "completed":
                return
            if status in FAILED_BACKUP_STATUSES:
                raise RuntimeError(f"the backup has the status {status}")
            time.sleep(POLL_SECONDS)
        raise TimeoutError(f"the backup was not completed after {TIMEOUT_SECONDS} seconds")
    
    
    def print_tasks(config: dict, token: str, database_id: str) -> None:
        """Prints the name and status of each task recorded for the database."""
        # Managed database operations record their progress as tasks, with the
        # kind "database" and the database ID as the subject.
        tasks = api(
            config, token, "GET",
            f"/tasks?subject_kind=database&subject_id={database_id}",
        )
        for task in tasks or []:
            print(f"Task: {task['name']} ({task['status']})")
    
    
    def backup_after_delete(config: dict, token: str, backup_id: str) -> str:
        """Reports whether the API still lists a backup once its database has
        been deleted. The API specification gives no rule for this, so the
        example only observes it."""
        prefix = "Backup after the database was deleted:"
        try:
            api(config, token, "GET", f"/backups/{backup_id}")
            return f"{prefix} still listed"
        except httpx.HTTPStatusError as e:
            return f"{prefix} {'gone' if e.response.status_code == 404 else 'unknown'}"
        except httpx.TransportError:
            return f"{prefix} unknown"
    ```

=== "TypeScript"

    ```typescript
    interface Backup {
      id: string;
      status: string;
    }
    
    // The API does not document its backup status values beyond "completed",
    // which marks a usable backup; the example treats "failed" as a failure,
    // which ends the wait at once instead of leaving it to run until the time
    // limit.
    const FAILED_BACKUP_STATUSES = new Set(["failed"]);
    
    // Starts an on-demand backup and returns the pending backup.
    async function takeBackup(token: string, databaseId: string): Promise<Backup> {
      // The hot kind is a fast local snapshot. The durable kind streams a base
      // backup to object storage, and needs the durable tier to be enabled for
      // the database. The API answers 202 at once and runs the backup in the
      // background.
      const backup = await api<Backup>(
        token,
        "POST",
        `/databases/${databaseId}/backup`,
        { kind: "hot" },
      );
      return backup!;
    }
    
    // Polls the backup until its status is completed.
    async function waitForBackup(token: string, backupId: string): Promise<void> {
      const deadline = Date.now() + TIMEOUT_MS;
      let last = "";
      while (Date.now() < deadline) {
        const backup = await api<Backup>(token, "GET", `/backups/${backupId}`);
        if (backup!.status !== last) {
          console.log(`Backup status: ${backup!.status}`);
          last = backup!.status;
        }
        if (backup!.status === "completed") {
          return;
        }
        if (FAILED_BACKUP_STATUSES.has(backup!.status)) {
          throw new Error(`the backup has the status ${backup!.status}`);
        }
        await sleep(POLL_MS, undefined, { signal: interrupt.signal });
      }
      throw new Error(`the backup was not completed after ${TIMEOUT_MS / 1000} seconds`);
    }
    
    // Prints the name and status of each task recorded for the database.
    async function printTasks(token: string, databaseId: string): Promise<void> {
      // Managed database operations record their progress as tasks, with the
      // kind "database" and the database ID as the subject.
      const tasks = await api<{ name: string; status: string }[]>(
        token,
        "GET",
        `/tasks?subject_kind=database&subject_id=${databaseId}`,
      );
      for (const task of tasks ?? []) {
        console.log(`Task: ${task.name} (${task.status})`);
      }
    }
    
    // Reports whether the API still lists a backup once its database has been
    // deleted. The API specification gives no rule for this, so the example
    // only observes it.
    async function backupAfterDelete(token: string, backupId: string): Promise<string> {
      const prefix = "Backup after the database was deleted:";
      try {
        await api(token, "GET", `/backups/${backupId}`, undefined, new AbortController().signal);
        return `${prefix} still listed`;
      } catch (err) {
        return `${prefix} ${err instanceof ApiError && err.status === 404 ? "gone" : "unknown"}`;
      }
    }
    ```

=== "Java"

    ```java
    /**
     * The API does not document its backup status values beyond
     * "completed", which marks a usable backup; the example treats "failed"
     * as a failure, which ends the wait at once instead of leaving it to
     * run until the time limit.
     */
    static final Set<String> FAILED_BACKUP_STATUSES = Set.of("failed");
    
    /** Starts an on-demand backup and returns the pending backup. */
    static JsonNode takeBackup(Settings cfg, String token, String databaseId)
            throws IOException, InterruptedException {
        // The hot kind is a fast local snapshot. The durable kind streams a
        // base backup to object storage, and needs the durable tier to be
        // enabled for the database. The API answers 202 at once and runs
        // the backup in the background.
        return api(cfg, token, "POST", "/databases/" + databaseId + "/backup",
                Map.of("kind", "hot"));
    }
    
    /** Polls the backup until its status is completed. */
    static void waitForBackup(Settings cfg, String token, String backupId)
            throws IOException, InterruptedException {
        long deadline = deadline(TIMEOUT_SECONDS);
        String last = null;
        while (before(deadline)) {
            String status = field(
                    api(cfg, token, "GET", "/backups/" + backupId, null), "status");
            if (!status.equals(last)) {
                System.out.println("Backup status: " + status);
                last = status;
            }
            if (status.equals("completed")) {
                return;
            }
            if (FAILED_BACKUP_STATUSES.contains(status)) {
                throw new IllegalStateException(
                        "the backup has the status " + status);
            }
            pause(POLL_SECONDS);
        }
        throw new IllegalStateException("the backup was not completed after "
                + TIMEOUT_SECONDS + " seconds");
    }
    
    /** Prints the name and status of each task recorded for the database. */
    static void printTasks(Settings cfg, String token, String databaseId)
            throws IOException, InterruptedException {
        // Managed database operations record their progress as tasks, with
        // the kind "database" and the database ID as the subject.
        JsonNode tasks = api(cfg, token, "GET",
                "/tasks?subject_kind=database&subject_id=" + databaseId, null);
        if (tasks != null) {
            for (JsonNode task : tasks) {
                System.out.println("Task: " + field(task, "name") + " ("
                        + field(task, "status") + ")");
            }
        }
    }
    
    /**
     * Reports whether the API still lists a backup once its database has
     * been deleted. The API specification gives no rule for this, so the
     * example only observes it.
     */
    static String backupAfterDelete(Settings cfg, String token, String backupId)
            throws InterruptedException {
        String prefix = "Backup after the database was deleted:";
        try {
            api(cfg, token, "GET", "/backups/" + backupId, null);
            return prefix + " still listed";
        } catch (ApiException e) {
            return prefix + (e.status == 404 ? " gone" : " unknown");
        } catch (IOException e) {
            return prefix + " unknown";
        }
    }
    ```

=== "C#"

    ```csharp
    // The API does not document its backup status values beyond "completed",
    // which marks a usable backup; the example treats "failed" as a failure,
    // which ends the wait at once instead of leaving it to run until the time
    // limit.
    string[] failedBackupStatuses = ["failed"];
    
    // Starts an on-demand backup and returns the pending backup.
    async Task<JsonNode?> TakeBackup(string token, string databaseId)
    {
        // The hot kind is a fast local snapshot. The durable kind streams a base
        // backup to object storage, and needs the durable tier to be enabled for
        // the database. The API answers 202 at once and runs the backup in the
        // background.
        return await Api(token, "POST", $"/databases/{databaseId}/backup",
            new { kind = "hot" });
    }
    
    // Polls the backup until its status is completed.
    async Task WaitForBackup(string token, string backupId)
    {
        var deadline = Deadline(TimeoutSeconds);
        string? last = null;
        while (Before(deadline))
        {
            var status = Field(
                await Api(token, "GET", $"/backups/{backupId}"), "status");
            if (status != last)
            {
                Console.WriteLine($"Backup status: {status}");
                last = status;
            }
            if (status == "completed")
            {
                return;
            }
            if (failedBackupStatuses.Contains(status))
            {
                throw new InvalidOperationException(
                    $"the backup has the status {status}");
            }
            await Pause(PollSeconds);
        }
        throw new InvalidOperationException(
            $"the backup was not completed after {TimeoutSeconds} seconds");
    }
    
    // Prints the name and status of each task recorded for the database.
    async Task PrintTasks(string token, string databaseId)
    {
        // Managed database operations record their progress as tasks, with the
        // kind "database" and the database ID as the subject.
        var tasks = await Api(token, "GET",
            $"/tasks?subject_kind=database&subject_id={databaseId}");
        foreach (var task in tasks as JsonArray ?? [])
        {
            Console.WriteLine($"Task: {Field(task, "name")} ({Field(task, "status")})");
        }
    }
    
    // Reports whether the API still lists a backup once its database has been
    // deleted. The API specification gives no rule for this, so the example
    // only observes it.
    async Task<string> BackupAfterDelete(string token, string backupId)
    {
        const string prefix = "Backup after the database was deleted:";
        try
        {
            await Api(token, "GET", $"/backups/{backupId}");
            return $"{prefix} still listed";
        }
        catch (HttpRequestException e)
        {
            return $"{prefix} "
                + (e.StatusCode == HttpStatusCode.NotFound ? "gone" : "unknown");
        }
        catch (TaskCanceledException)
        {
            return $"{prefix} unknown";
        }
    }
    ```

=== "Go"

    ```go
    // Backup is the part of the API's description of a backup that the example
    // uses.
    type Backup struct {
    	ID     string `json:"id"`
    	Status string `json:"status"`
    }
    
    // takeBackup starts an on-demand backup and returns the pending backup.
    func takeBackup(ctx context.Context, token, databaseID string) (*Backup, error) {
    	// The hot kind is a fast local snapshot. The durable kind streams a
    	// base backup to object storage, and needs the durable tier to be
    	// enabled for the database. The API answers 202 at once and runs the
    	// backup in the background.
    	var backup Backup
    	err := api(ctx, token, http.MethodPost, "/databases/"+databaseID+"/backup",
    		map[string]string{"kind": "hot"}, &backup)
    	if err != nil {
    		return nil, err
    	}
    	return &backup, nil
    }
    
    // waitForBackup polls the backup until its status is completed.
    func waitForBackup(ctx context.Context, token, id string) error {
    	deadline := time.Now().Add(timeout)
    	last := ""
    	for time.Now().Before(deadline) {
    		var backup Backup
    		if err := api(ctx, token, http.MethodGet, "/backups/"+id, nil, &backup); err != nil {
    			return err
    		}
    		if backup.Status != last {
    			fmt.Printf("Backup status: %s\n", backup.Status)
    			last = backup.Status
    		}
    		if backup.Status == "completed" {
    			return nil
    		}
    		// The API does not document its backup status values beyond
    		// "completed", which marks a usable backup; the example treats
    		// "failed" as a failure, which ends the wait at once instead of
    		// leaving it to run until the time limit.
    		if backup.Status == "failed" {
    			return fmt.Errorf("the backup has the status %s", backup.Status)
    		}
    		if err := sleep(ctx); err != nil {
    			return err
    		}
    	}
    	return fmt.Errorf("the backup was not completed after %s", timeout)
    }
    
    // printTasks prints the name and status of each task recorded for the
    // database.
    func printTasks(ctx context.Context, token, databaseID string) error {
    	// Managed database operations record their progress as tasks, with
    	// the kind "database" and the database ID as the subject.
    	var tasks []struct {
    		Name   string `json:"name"`
    		Status string `json:"status"`
    	}
    	err := api(ctx, token, http.MethodGet,
    		"/tasks?subject_kind=database&subject_id="+databaseID, nil, &tasks)
    	if err != nil {
    		return err
    	}
    	for _, task := range tasks {
    		fmt.Printf("Task: %s (%s)\n", task.Name, task.Status)
    	}
    	return nil
    }
    
    // backupAfterDelete reports whether the API still lists a backup once its
    // database has been deleted. The API specification gives no rule for this,
    // so the example only observes it.
    func backupAfterDelete(ctx context.Context, token, id string) string {
    	const prefix = "Backup after the database was deleted:"
    	err := api(ctx, token, http.MethodGet, "/backups/"+id, nil, nil)
    	switch {
    	case err == nil:
    		return prefix + " still listed"
    	case isStatus(err, http.StatusNotFound):
    		return prefix + " gone"
    	default:
    		return prefix + " unknown"
    	}
    }
    
    ```

=== "Rust"

    ```rust
    /// The API does not document its backup status values beyond "completed",
    /// which marks a usable backup; the example treats "failed" as a failure,
    /// which ends the wait at once instead of leaving it to run until the time
    /// limit.
    const FAILED_BACKUP_STATUSES: [&str; 1] = ["failed"];
    
    /// Starts an on-demand backup and returns the pending backup.
    fn take_backup(cfg: &Settings, token: &str, database_id: &str) -> Result<Value> {
        // The hot kind is a fast local snapshot. The durable kind streams a
        // base backup to object storage, and needs the durable tier to be
        // enabled for the database. The API answers 202 at once and runs the
        // backup in the background.
        let path = format!("/databases/{database_id}/backup");
        api(cfg, token, Method::POST, &path, Some(&json!({"kind": "hot"})))
    }
    
    /// Polls the backup until its status is completed.
    fn wait_for_backup(cfg: &Settings, token: &str, backup_id: &str) -> Result<()> {
        let deadline = Instant::now() + TIMEOUT;
        let mut last = String::new();
        while Instant::now() < deadline {
            let path = format!("/backups/{backup_id}");
            let status = field(&api(cfg, token, Method::GET, &path, None)?, "status")?;
            if status != last {
                println!("Backup status: {status}");
                last = status.clone();
            }
            if status == "completed" {
                return Ok(());
            }
            if FAILED_BACKUP_STATUSES.contains(&status.as_str()) {
                return Err(format!("the backup has the status {status}").into());
            }
            pause(POLL)?;
        }
        Err(format!("the backup was not completed after {} seconds", TIMEOUT.as_secs()).into())
    }
    
    /// Prints the name and status of each task recorded for the database.
    fn print_tasks(cfg: &Settings, token: &str, database_id: &str) -> Result<()> {
        // Managed database operations record their progress as tasks, with the
        // kind "database" and the database ID as the subject.
        let path = format!("/tasks?subject_kind=database&subject_id={database_id}");
        let tasks = api(cfg, token, Method::GET, &path, None)?;
        for task in tasks.as_array().into_iter().flatten() {
            println!("Task: {} ({})", field(task, "name")?, field(task, "status")?);
        }
        Ok(())
    }
    
    /// Reports whether the API still lists a backup once its database has been
    /// deleted. The API specification gives no rule for this, so the example
    /// only observes it.
    fn backup_after_delete(cfg: &Settings, token: &str, backup_id: &str) -> Result<String> {
        let prefix = "Backup after the database was deleted:";
        let outcome = match api(cfg, token, Method::GET, &format!("/backups/{backup_id}"), None) {
            Ok(_) => "still listed",
            Err(e) => match e.downcast_ref::<ApiError>() {
                Some(api) if api.status == 404 => "gone",
                Some(_) => "unknown",
                None if e.is::<reqwest::Error>() => "unknown",
                None => return Err(e),
            },
        };
        Ok(format!("{prefix} {outcome}"))
    }
    ```

=== "Ruby"

    ```ruby
    # The API does not document its backup status values beyond "completed",
    # which marks a usable backup; the example treats "failed" as a failure,
    # which ends the wait at once instead of leaving it to run until the time
    # limit.
    FAILED_BACKUP_STATUSES = %w[failed].freeze
    
    # Starts an on-demand backup and returns the pending backup.
    def take_backup(config, token, database_id)
      # The hot kind is a fast local snapshot. The durable kind streams a base
      # backup to object storage, and needs the durable tier to be enabled for
      # the database. The API answers 202 at once and runs the backup in the
      # background.
      api(config, token, "POST", "/databases/#{database_id}/backup", { kind: "hot" })
    end
    
    # Polls the backup until its status is completed.
    def wait_for_backup(config, token, backup_id)
      deadline = now + TIMEOUT_SECONDS
      last = nil
      while now < deadline
        status = api(config, token, "GET", "/backups/#{backup_id}").fetch("status")
        if status != last
          puts "Backup status: #{status}"
          last = status
        end
        return if status == "completed"
        raise "the backup has the status #{status}" if FAILED_BACKUP_STATUSES.include?(status)
    
        sleep POLL_SECONDS
      end
      raise "the backup was not completed after #{TIMEOUT_SECONDS} seconds"
    end
    
    # Prints the name and status of each task recorded for the database.
    def print_tasks(config, token, database_id)
      # Managed database operations record their progress as tasks, with the
      # kind "database" and the database ID as the subject.
      tasks = api(config, token, "GET",
                  "/tasks?subject_kind=database&subject_id=#{database_id}")
      tasks.to_a.each do |task|
        puts "Task: #{task.fetch('name')} (#{task.fetch('status')})"
      end
    end
    
    # Reports whether the API still lists a backup once its database has been
    # deleted. The API specification gives no rule for this, so the example
    # only observes it.
    def backup_after_delete(config, token, backup_id)
      prefix = "Backup after the database was deleted:"
      begin
        api(config, token, "GET", "/backups/#{backup_id}")
        "#{prefix} still listed"
      rescue ApiError => e
        "#{prefix} #{e.status == 404 ? 'gone' : 'unknown'}"
      rescue *TRANSPORT_ERRORS
        "#{prefix} unknown"
      end
    end
    ```

=== "curl"

    ```bash
    # Starts an on-demand backup and prints the pending backup. The hot kind is
    # a fast local snapshot. The durable kind streams a base backup to object
    # storage, and needs the durable tier to be enabled for the database. The
    # API answers 202 at once and runs the backup in the background.
    take_backup() {
        jq -n '{kind: "hot"}' |
            api POST "/databases/$1/backup" \
                --header "Content-Type: application/json" --data @-
    }
    
    # Polls the backup until its status is completed.
    wait_for_backup() {
        local id="$1" deadline=$((SECONDS + timeout_seconds)) status last=""
        while ((SECONDS < deadline)); do
            status="$(api GET "/backups/$id" | jq -er '.status')"
            if [[ "$status" != "$last" ]]; then
                echo "Backup status: $status"
                last="$status"
            fi
            [[ "$status" == "completed" ]] && return 0
            # The API does not document its backup status values beyond
            # "completed", which marks a usable backup; the example treats
            # "failed" as a failure, which ends the wait at once instead of
            # leaving it to run until the time limit.
            if [[ "$status" == "failed" ]]; then
                echo "Error: the backup has the status $status" >&2
                return 1
            fi
            sleep "$poll_seconds"
        done
        echo "Error: the backup was not completed after $timeout_seconds seconds" >&2
        return 1
    }
    
    # Prints the name and status of each task recorded for the database.
    # Managed database operations record their progress as tasks, with the kind
    # "database" and the database ID as the subject.
    print_tasks() {
        local tasks
        tasks="$(api GET "/tasks?subject_kind=database&subject_id=$1")"
        jq -r '.[] | "Task: \(.name) (\(.status))"' <<<"$tasks"
    }
    
    # Reports whether the API still lists a backup once its database has been
    # deleted. The API specification gives no rule for this, so the example
    # only observes it.
    backup_after_delete() {
        local status prefix="Backup after the database was deleted:"
        status="$(api_status GET "/backups/$1")"
        case "$status" in
            200) echo "$prefix still listed" ;;
            404) echo "$prefix gone" ;;
            *)   echo "$prefix unknown" ;;
        esac
    }
    ```

## Deleting the Resources

The program deletes the database when it has finished with the backup. The API
documents a 409 reply to a delete as meaning that the database has branches,
and offers a `force` parameter for that case. In testing, the API also answered
409 whilst a database was still being created, so the program repeats the
request after a 409, after a 429 or 5xx status, and after a failure to get any
reply, until the time limit passes. A 404 means that the database has gone
already. A delete only starts the teardown, so the program then polls until the
API answers 404, which in testing was the sign that the database had gone. If
the outcome of the create request is unknown (no reply arrived, the service
answered with a 5xx status, the reply could not be read, or you interrupted the
program during the request), the program has no database ID, so it first lists
the databases and picks the one with the name that it chose before the request,
trying up to three times, ten seconds apart, and then reports the name so that
you can check your account by hand. It does not look after a 4xx reply, because
that is a definite refusal. The list request passes `limit=100` and
`descending=true`, but the API specification does not say which property it
sorts on. If the delete or the lookup fails, the program tells you to delete
the database by hand. The program cannot delete the backup, because the API has
no way to do so, and the specification does not say what happens to a backup
when its database is deleted. The following code deletes the database:

=== "Python"

    ```python
    def is_transient(error: Exception) -> bool:
        """Reports whether a failed request is worth repeating: no reply
        arrived, the service is overloaded or failing, or it answered 409,
        which the API does whilst a database is still being created."""
        if isinstance(error, httpx.TransportError):
            return True
        if isinstance(error, httpx.HTTPStatusError):
            status = error.response.status_code
            return status in (409, 429) or status >= 500
        return False
    
    
    def is_gone(error: Exception) -> bool:
        """Reports whether an error is a 404 reply, which means that the
        database does not exist."""
        return (
            isinstance(error, httpx.HTTPStatusError)
            and error.response.status_code == 404
        )
    
    
    def find_database(config: dict, token: str, name: str):
        """Returns the ID of the database with the given name, or None. The
        program uses this when it cannot tell whether a create request worked.
        It repeats the request, as the delete does, because the fault that
        lost the reply to the create request may still be there. The request
        asks for the newest databases first, but the API does not say which
        property it sorts on."""
        deadline = time.monotonic() + TIMEOUT_SECONDS
        while True:
            try:
                databases = api(
                    config, token, "GET", "/databases?limit=100&descending=true"
                )
                break
            except httpx.HTTPError as e:
                if not is_transient(e) or time.monotonic() > deadline:
                    raise
                time.sleep(POLL_SECONDS)
        for database in databases or []:
            if database["name"] == name:
                return database["id"]
        return None
    
    
    def find_created_database(config: dict, token: str, name: str):
        """Looks for the database a few times, because the service may not
        have recorded a request whose reply was lost until a little later.
        Returns None if the database never appears."""
        for attempt in range(LOOKUP_ATTEMPTS):
            database_id = find_database(config, token, name)
            if database_id is not None:
                return database_id
            if attempt < LOOKUP_ATTEMPTS - 1:
                time.sleep(POLL_SECONDS)
        return None
    
    
    def outcome_unknown(error: Exception) -> bool:
        """Reports whether a failed create request might still have created
        the database: no reply arrived, or the service failed with a 5xx
        status. A 4xx reply is a definite refusal."""
        if isinstance(error, httpx.HTTPStatusError):
            return error.response.status_code >= 500
        return True
    
    
    def delete_database(config: dict, token: str, database_id: str) -> None:
        """Deletes the database and waits until the API no longer lists it."""
        deadline = time.monotonic() + TIMEOUT_SECONDS
        while True:
            try:
                api(config, token, "DELETE", f"/databases/{database_id}")
                break
            except httpx.HTTPError as e:
                if is_gone(e):
                    return
                if not is_transient(e) or time.monotonic() > deadline:
                    raise
                time.sleep(POLL_SECONDS)
    
        # The delete starts the teardown; a 404 shows that it has finished.
        while time.monotonic() < deadline:
            try:
                api(config, token, "GET", f"/databases/{database_id}")
            except httpx.HTTPError as e:
                if is_gone(e):
                    return
                if not is_transient(e):
                    raise
            time.sleep(POLL_SECONDS)
        raise TimeoutError(f"the database was still present after {TIMEOUT_SECONDS} seconds")
    ```

=== "TypeScript"

    ```typescript
    // Reports whether a failed request is worth repeating: no reply arrived
    // (fetch rejects, and the error is not an ApiError), the service is
    // overloaded or failing, or it answered 409, which the API does whilst a
    // database is still being created.
    function isTransient(err: unknown): boolean {
      if (!(err instanceof ApiError)) {
        return true;
      }
      return err.status === 409 || err.status === 429 || err.status >= 500;
    }
    
    // Looks for the database a few times, because the service may not have
    // recorded a request whose reply was lost until a little later. Returns
    // undefined if the database never appears.
    async function findCreatedDatabase(
      token: string,
      name: string,
      signal: AbortSignal,
    ): Promise<string | undefined> {
      for (let attempt = 1; ; attempt++) {
        const id = await findDatabase(token, name, signal);
        if (id || attempt === LOOKUP_ATTEMPTS) {
          return id;
        }
        await sleep(POLL_MS);
      }
    }
    
    // Reports whether a failed create request might still have created the
    // database: no reply arrived, the reply could not be decoded, or the
    // service failed with a 5xx status. A 4xx reply is a definite refusal.
    function outcomeUnknown(err: unknown): boolean {
      return !(err instanceof ApiError) || err.status >= 500;
    }
    
    // Returns the ID of the database with the given name, or undefined. The
    // program uses this when it cannot tell whether a create request worked.
    // It repeats the request, as the delete does, because the fault that lost
    // the reply to the create request may still be there. The request asks for
    // the newest databases first, but the API does not say which property it
    // sorts on.
    async function findDatabase(
      token: string,
      name: string,
      signal: AbortSignal,
    ): Promise<string | undefined> {
      const deadline = Date.now() + TIMEOUT_MS;
      for (;;) {
        try {
          const databases = await api<{ id: string; name: string }[]>(
            token,
            "GET",
            "/databases?limit=100&descending=true",
            undefined,
            signal,
          );
          return databases?.find((database) => database.name === name)?.id;
        } catch (err) {
          if (!isTransient(err) || Date.now() > deadline) {
            throw err;
          }
          await sleep(POLL_MS);
        }
      }
    }
    
    // Deletes the database and waits until the API no longer lists it. The
    // requests ignore Ctrl-C, so that a second interrupt cannot leave the
    // database behind.
    async function deleteDatabase(token: string, databaseId: string): Promise<void> {
      const never = new AbortController().signal;
      const deadline = Date.now() + TIMEOUT_MS;
    
      for (;;) {
        try {
          await api(token, "DELETE", `/databases/${databaseId}`, undefined, never);
          break;
        } catch (err) {
          if (err instanceof ApiError && err.status === 404) {
            return;
          }
          if (!isTransient(err) || Date.now() > deadline) {
            throw err;
          }
          await sleep(POLL_MS);
        }
      }
    
      // The delete starts the teardown; a 404 shows that it has finished.
      while (Date.now() < deadline) {
        try {
          await api(token, "GET", `/databases/${databaseId}`, undefined, never);
        } catch (err) {
          if (err instanceof ApiError && err.status === 404) {
            return;
          }
          if (!isTransient(err)) {
            throw err;
          }
        }
        await sleep(POLL_MS);
      }
      throw new Error(`the database was still present after ${TIMEOUT_MS / 1000} seconds`);
    }
    ```

=== "Java"

    ```java
    /**
     * Reports whether a failed request is worth repeating: no reply arrived,
     * the service is overloaded or failing, or it answered 409, which the
     * API does whilst a database is still being created. Any IOException
     * other than an ApiException means that no reply arrived, such as a
     * refused connection or a timeout.
     */
    static boolean isTransient(Exception e) {
        if (e instanceof ApiException api) {
            return api.status == 409 || api.status == 429 || api.status >= 500;
        }
        return e instanceof IOException;
    }
    
    /**
     * Reports whether an error is a 404 reply, which means that the database
     * does not exist.
     */
    static boolean isGone(Exception e) {
        return e instanceof ApiException api && api.status == 404;
    }
    
    /**
     * Returns the ID of the database with the given name, or null. The
     * program uses this when it cannot tell whether a create request worked.
     * It repeats the request, as the delete does, because the fault that
     * lost the reply to the create request may still be there. The request
     * asks for the newest databases first, but the API does not say which
     * property it sorts on.
     */
    static String findDatabase(Settings cfg, String token, String name)
            throws IOException, InterruptedException {
        long deadline = deadline(TIMEOUT_SECONDS);
        JsonNode databases;
        while (true) {
            try {
                databases = api(cfg, token, "GET",
                        "/databases?limit=100&descending=true", null);
                break;
            } catch (IOException e) {
                if (!isTransient(e) || !before(deadline)) {
                    throw e;
                }
                pause(POLL_SECONDS);
            }
        }
        if (databases != null) {
            for (JsonNode database : databases) {
                if (name.equals(database.path("name").asString())) {
                    return field(database, "id");
                }
            }
        }
        return null;
    }
    
    /**
     * Looks for the database a few times, because the service may not have
     * recorded a request whose reply was lost until a little later. Returns
     * null if the database never appears.
     */
    static String findCreatedDatabase(Settings cfg, String token, String name)
            throws IOException, InterruptedException {
        for (int attempt = 0; attempt < LOOKUP_ATTEMPTS; attempt++) {
            String databaseId = findDatabase(cfg, token, name);
            if (databaseId != null) {
                return databaseId;
            }
            if (attempt < LOOKUP_ATTEMPTS - 1) {
                pause(POLL_SECONDS);
            }
        }
        return null;
    }
    
    /**
     * Reports whether a failed create request might still have created the
     * database: no reply arrived, the reply could not be read, or the
     * service failed with a 5xx status. A 4xx reply is a definite refusal.
     */
    static boolean outcomeUnknown(Exception e) {
        if (e instanceof ApiException api) {
            return api.status >= 500;
        }
        return true;
    }
    
    /** Deletes the database and waits until the API no longer lists it. */
    static void deleteDatabase(Settings cfg, String token, String databaseId)
            throws IOException, InterruptedException {
        long deadline = deadline(TIMEOUT_SECONDS);
        while (true) {
            try {
                api(cfg, token, "DELETE", "/databases/" + databaseId, null);
                break;
            } catch (IOException e) {
                if (isGone(e)) {
                    return;
                }
                if (!isTransient(e) || !before(deadline)) {
                    throw e;
                }
                pause(POLL_SECONDS);
            }
        }
    
        // The delete starts the teardown; a 404 shows that it has finished.
        while (before(deadline)) {
            try {
                api(cfg, token, "GET", "/databases/" + databaseId, null);
            } catch (IOException e) {
                if (isGone(e)) {
                    return;
                }
                if (!isTransient(e)) {
                    throw e;
                }
            }
            pause(POLL_SECONDS);
        }
        throw new IllegalStateException("the database was still present after "
                + TIMEOUT_SECONDS + " seconds");
    }
    ```

=== "C#"

    ```csharp
    // Reports whether a failed request is worth repeating: no reply arrived,
    // such as a refused connection or a timeout, the service is overloaded or
    // failing, or it answered 409, which the API does whilst a database is
    // still being created.
    static bool IsTransient(Exception e) => e switch
    {
        HttpRequestException { StatusCode: HttpStatusCode code } =>
            (int)code is 409 or 429 or >= 500,
        HttpRequestException or TaskCanceledException => true,
        _ => false,
    };
    
    // Reports whether an error is a 404 reply, which means that the database
    // does not exist.
    static bool IsGone(Exception e) =>
        e is HttpRequestException { StatusCode: HttpStatusCode.NotFound };
    
    // Returns the ID of the database with the given name, or null. The program
    // uses this when it cannot tell whether a create request worked. It
    // repeats the request, as the delete does, because the fault that lost the
    // reply to the create request may still be there. The request asks for
    // the newest databases first, but the API does not say which property it
    // sorts on.
    async Task<string?> FindDatabase(string token, string name)
    {
        var deadline = Deadline(TimeoutSeconds);
        JsonNode? databases;
        while (true)
        {
            try
            {
                databases = await Api(
                    token, "GET", "/databases?limit=100&descending=true");
                break;
            }
            catch (Exception e) when (IsTransient(e) && Before(deadline))
            {
                await Pause(PollSeconds);
            }
        }
        foreach (var database in databases as JsonArray ?? [])
        {
            if (database?["name"]?.ToString() == name)
            {
                return Field(database, "id");
            }
        }
        return null;
    }
    
    // Looks for the database a few times, because the service may not have
    // recorded a request whose reply was lost until a little later. Returns
    // null if the database never appears.
    async Task<string?> FindCreatedDatabase(string token, string name)
    {
        for (var attempt = 0; attempt < LookupAttempts; attempt++)
        {
            if (await FindDatabase(token, name) is string databaseId)
            {
                return databaseId;
            }
            if (attempt < LookupAttempts - 1)
            {
                await Pause(PollSeconds);
            }
        }
        return null;
    }
    
    // Reports whether a failed create request might still have created the
    // database: no reply arrived, the reply could not be read, or the service
    // failed with a 5xx status. A 4xx reply is a definite refusal.
    static bool OutcomeUnknown(Exception e) =>
        e is not HttpRequestException { StatusCode: HttpStatusCode code }
            || (int)code >= 500;
    
    // Deletes the database and waits until the API no longer lists it.
    async Task DeleteDatabase(string token, string databaseId)
    {
        var deadline = Deadline(TimeoutSeconds);
        while (true)
        {
            try
            {
                await Api(token, "DELETE", $"/databases/{databaseId}");
                break;
            }
            catch (Exception e) when (IsGone(e))
            {
                return;
            }
            catch (Exception e) when (IsTransient(e) && Before(deadline))
            {
                await Pause(PollSeconds);
            }
        }
    
        // The delete starts the teardown; a 404 shows that it has finished.
        while (Before(deadline))
        {
            try
            {
                await Api(token, "GET", $"/databases/{databaseId}");
            }
            catch (Exception e) when (IsGone(e))
            {
                return;
            }
            catch (Exception e) when (IsTransient(e))
            {
            }
            await Pause(PollSeconds);
        }
        throw new InvalidOperationException(
            $"the database was still present after {TimeoutSeconds} seconds");
    }
    ```

=== "Go"

    ```go
    // isStatus reports whether err is an API error with the given status.
    func isStatus(err error, status int) bool {
    	var apiErr *APIError
    	return errors.As(err, &apiErr) && apiErr.Status == status
    }
    
    // isTransient reports whether a failed request is worth repeating: no
    // reply arrived, the service is overloaded or failing, or it answered 409,
    // which the API does whilst a database is still being created.
    func isTransient(err error) bool {
    	var apiErr *APIError
    	if !errors.As(err, &apiErr) {
    		return true
    	}
    	return apiErr.Status == http.StatusConflict ||
    		apiErr.Status == http.StatusTooManyRequests ||
    		apiErr.Status >= 500
    }
    
    // findCreatedDatabase looks for the database a few times, because the
    // service may not have recorded a request whose reply was lost until a
    // little later. It returns an empty string if the database never appears.
    func findCreatedDatabase(ctx context.Context, token, name string) (string, error) {
    	for attempt := 1; ; attempt++ {
    		id, err := findDatabase(ctx, token, name)
    		if err != nil || id != "" || attempt == lookupAttempts {
    			return id, err
    		}
    		if err := sleep(ctx); err != nil {
    			return "", err
    		}
    	}
    }
    
    // outcomeUnknown reports whether a failed create request might still have
    // created the database: no reply arrived, the reply could not be decoded,
    // or the service failed with a 5xx status. A 4xx reply is a definite
    // refusal.
    func outcomeUnknown(err error) bool {
    	var apiErr *APIError
    	if !errors.As(err, &apiErr) {
    		return true
    	}
    	return apiErr.Status >= 500
    }
    
    // findDatabase returns the ID of the database with the given name, or an
    // empty string. The program uses it when it cannot tell whether a create
    // request worked. It repeats the request, as the delete does, because the
    // fault that lost the reply to the create request may still be there. The
    // request asks for the newest databases first, but the API does not say
    // which property it sorts on.
    func findDatabase(ctx context.Context, token, name string) (string, error) {
    	var databases []struct {
    		ID   string `json:"id"`
    		Name string `json:"name"`
    	}
    	deadline := time.Now().Add(timeout)
    	for {
    		err := api(ctx, token, http.MethodGet, "/databases?limit=100&descending=true", nil, &databases)
    		if err == nil {
    			break
    		}
    		if !isTransient(err) || time.Now().After(deadline) {
    			return "", err
    		}
    		if err := sleep(ctx); err != nil {
    			return "", err
    		}
    	}
    	for _, database := range databases {
    		if database.Name == name {
    			return database.ID, nil
    		}
    	}
    	return "", nil
    }
    
    // deleteDatabase deletes the database and waits until the API no longer
    // lists it.
    func deleteDatabase(ctx context.Context, token, id string) error {
    	deadline := time.Now().Add(timeout)
    	for {
    		err := api(ctx, token, http.MethodDelete, "/databases/"+id, nil, nil)
    		if err == nil {
    			break
    		}
    		if isStatus(err, http.StatusNotFound) {
    			return nil
    		}
    		if !isTransient(err) || time.Now().After(deadline) {
    			return err
    		}
    		if err := sleep(ctx); err != nil {
    			return err
    		}
    	}
    
    	// The delete starts the teardown; a 404 shows that it has finished.
    	for time.Now().Before(deadline) {
    		err := api(ctx, token, http.MethodGet, "/databases/"+id, nil, nil)
    		if isStatus(err, http.StatusNotFound) {
    			return nil
    		}
    		if err != nil && !isTransient(err) {
    			return err
    		}
    		if err := sleep(ctx); err != nil {
    			return err
    		}
    	}
    	return fmt.Errorf("the database was still present after %s", timeout)
    }
    
    ```

=== "Rust"

    ```rust
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
    ```

=== "Ruby"

    ```ruby
    # The errors that mean that no reply arrived: a refused or reset
    # connection, a failed name lookup, a TLS failure, or a timeout.
    TRANSPORT_ERRORS = [SystemCallError, IOError, SocketError, Timeout::Error,
                        OpenSSL::SSL::SSLError].freeze
    
    # Reports whether a failed request is worth repeating: no reply arrived,
    # the service is overloaded or failing, or it answered 409, which the API
    # does whilst a database is still being created.
    def transient?(error)
      return true if TRANSPORT_ERRORS.any? { |type| error.is_a?(type) }
      return false unless error.is_a?(ApiError)
    
      [409, 429].include?(error.status) || error.status >= 500
    end
    
    # Reports whether an error is a 404 reply, which means that the database
    # does not exist.
    def gone?(error)
      error.is_a?(ApiError) && error.status == 404
    end
    
    # Returns the ID of the database with the given name, or nil. The program
    # uses this when it cannot tell whether a create request worked. It repeats
    # the request, as the delete does, because the fault that lost the reply to
    # the create request may still be there. The request asks for the newest
    # databases first, but the API does not say which property it sorts on.
    def find_database(config, token, name)
      deadline = now + TIMEOUT_SECONDS
      databases = begin
        api(config, token, "GET", "/databases?limit=100&descending=true")
      rescue StandardError => e
        raise if !transient?(e) || now > deadline
    
        sleep POLL_SECONDS
        retry
      end
      database = databases.to_a.find { |d| d["name"] == name }
      database&.fetch("id")
    end
    
    # Looks for the database a few times, because the service may not have
    # recorded a request whose reply was lost until a little later. Returns nil
    # if the database never appears.
    def find_created_database(config, token, name)
      LOOKUP_ATTEMPTS.times do |attempt|
        database_id = find_database(config, token, name)
        return database_id if database_id
    
        sleep POLL_SECONDS if attempt < LOOKUP_ATTEMPTS - 1
      end
      nil
    end
    
    # Reports whether a failed create request might still have created the
    # database: no reply arrived, the reply could not be read, or the service
    # failed with a 5xx status. A 4xx reply is a definite refusal.
    def outcome_unknown?(error)
      return error.status >= 500 if error.is_a?(ApiError)
    
      true
    end
    
    # Deletes the database and waits until the API no longer lists it.
    def delete_database(config, token, database_id)
      deadline = now + TIMEOUT_SECONDS
      begin
        api(config, token, "DELETE", "/databases/#{database_id}")
      rescue StandardError => e
        return if gone?(e)
        raise if !transient?(e) || now > deadline
    
        sleep POLL_SECONDS
        retry
      end
    
      # The delete starts the teardown; a 404 shows that it has finished.
      while now < deadline
        begin
          api(config, token, "GET", "/databases/#{database_id}")
        rescue StandardError => e
          return if gone?(e)
          raise unless transient?(e)
        end
        sleep POLL_SECONDS
      end
      raise "the database was still present after #{TIMEOUT_SECONDS} seconds"
    end
    ```

=== "curl"

    ```bash
    # Prints the ID of the database with the given name, or nothing. The script
    # uses this when it cannot tell whether the create request worked. It
    # repeats the request, as the delete does, because the fault that lost the
    # reply to the create request may still be there.
    find_database() {
        local deadline=$((SECONDS + timeout_seconds)) reply status
        while true; do
            # The --write-out option adds the HTTP status on a last line, and
            # prints 000 if no reply arrived. The request asks for the newest
            # databases first, but the API does not say which property it
            # sorts on.
            reply="$(api GET "/databases?limit=100&descending=true" \
                --write-out '\n%{http_code}')" || true
            status="${reply##*$'\n'}"
            case "$status" in
                200) break ;;
                000|409|429|5??) ;;
                *) echo "Error: listing the databases returned HTTP status $status" >&2
                   return 1 ;;
            esac
            if ((SECONDS >= deadline)); then
                echo "Error: the list was still failing after $timeout_seconds seconds" >&2
                return 1
            fi
            sleep "$poll_seconds"
        done
        jq -r --arg name "$1" 'first(.[] | select(.name == $name) | .id) // empty' \
            <<<"${reply%$'\n'*}"
    }
    
    # Prints the ID of the database with the given name, looking up to three
    # times because the service may not have recorded a request whose reply was
    # lost until a little later. Prints nothing if the database never appears,
    # and fails if a lookup fails.
    find_created_database() {
        local attempt id
        for ((attempt = 1; attempt <= 3; attempt++)); do
            id="$(find_database "$1")" || return 1
            if [[ -n "$id" ]]; then
                echo "$id"
                return 0
            fi
            ((attempt < 3)) && sleep "$poll_seconds"
        done
        return 0
    }
    
    # Deletes the database and waits until the API no longer lists it. A status
    # of 000 means that no reply arrived; that, 409 (which the API gives whilst a
    # database is still being created), 429, and the 5xx statuses are worth
    # repeating until the time limit.
    delete_database() {
        local id="$1" deadline=$((SECONDS + timeout_seconds)) status
    
        while true; do
            status="$(api_status DELETE "/databases/$id")"
            case "$status" in
                204) break ;;
                404) return 0 ;;
                000|409|429|5??) ;;
                *) echo "Error: deleting the database returned HTTP status $status" >&2
                   return 1 ;;
            esac
            if ((SECONDS >= deadline)); then
                echo "Error: the delete was still failing after $timeout_seconds seconds" >&2
                return 1
            fi
            sleep "$poll_seconds"
        done
    
        # The delete starts the teardown; a 404 shows that it has finished.
        while true; do
            status="$(api_status GET "/databases/$id")"
            case "$status" in
                404) return 0 ;;
                200|000|429|5??) ;;
                *) echo "Error: checking the database returned HTTP status $status" >&2
                   return 1 ;;
            esac
            if ((SECONDS >= deadline)); then
                echo "Error: the database was still present after $timeout_seconds seconds" >&2
                return 1
            fi
            sleep "$poll_seconds"
        done
    }
    ```

## Running the Program

The `main` function runs the steps in order, and deletes the database on every
path: in a `finally` block in Python, TypeScript, Java, and C#, in an `ensure`
block in Ruby, after `run` returns in Rust, with a `defer` in Go, and with a
trap on `EXIT` in the curl script. The deletion therefore happens when a step
fails or when you press Ctrl-C, and the Rust program catches a panic with
`catch_unwind` so that one cannot skip the deletion either. Each program also
handles the SIGTERM signal as it does Ctrl-C (SIGINT), so that `kill` cleans up
as well. The C# program registers `PosixSignalRegistration` handlers that
cancel the request in progress, the Rust program sets a flag with signal-hook
that stops it before its next request, and the Ruby program receives each
signal as an exception. Java's supported API cannot catch a signal, so the Java
program registers a shutdown hook, which the JVM runs when SIGINT or SIGTERM
ends the program; the hook deletes the database, or waits for the main thread
to finish doing so, and then ends the program. The program chooses the database
name before it sends the create request, so the cleanup can find the database
by name if the reply never arrives. The cleanup ignores further interrupts,
because a second Ctrl-C must not leave a billable database behind. The
following code shows the function:

=== "Python"

    ```python
    def stop(*_) -> None:
        """Handles SIGTERM like Ctrl-C, by raising KeyboardInterrupt."""
        raise KeyboardInterrupt
    
    
    def main() -> int:
        # Turn SIGTERM into a KeyboardInterrupt, so that the finally block
        # runs, as it does for Ctrl-C.
        signal.signal(signal.SIGTERM, stop)
    
        config = settings()
        exit_code = 0
        token = None
        name = None
        database_id = None
        backup_id = None
        lookup = False
        try:
            token = get_token(config)
    
            region, size = choose_placement(config, token)
            print(f"Region: {region}")
            print(f"Size: {size}")
    
            # Choose the name before the request, so that the program can find
            # the database even if the reply to the request never arrives.
            suffix = secrets.token_hex(3)
            name, display_name = f"cookbook{suffix}", f"cookbook-{suffix}"
            # Look the database up by name afterwards only if the outcome of
            # the request is unknown, so that a refusal cannot lead the
            # cleanup to delete another database that has the same name.
            ip = client_ip(config, token)
            lookup = True
            try:
                database = create_database(
                    config, token, name, display_name, region, size, ip
                )
            except (httpx.HTTPError, ValueError) as e:
                lookup = outcome_unknown(e)
                raise
            database_id = database["id"]
            print(f"Created database {database['display_name']}")
    
            wait_until_available(config, token, database_id)
            print("Database is available")
    
            backup_id = take_backup(config, token, database_id)["id"]
            print("Backup started")
            wait_for_backup(config, token, backup_id)
            print_tasks(config, token, database_id)
        # httpx.HTTPError covers connection failures and, through
        # raise_for_status(), error responses from the API.
        except (httpx.HTTPError, KeyError, ValueError, RuntimeError, TimeoutError) as e:
            print(f"Error: {e}", file=sys.stderr)
            exit_code = 1
        except KeyboardInterrupt:
            print("Interrupted", file=sys.stderr)
            exit_code = 130
        finally:
            # Delete the database whether the example succeeded, failed, or
            # was interrupted, because the service bills for it until then.
            # Ignore further interrupts, so that they cannot cut it short.
            signal.signal(signal.SIGINT, signal.SIG_IGN)
            signal.signal(signal.SIGTERM, signal.SIG_IGN)
            if token is not None and name is not None:
                try:
                    if database_id is None and lookup:
                        database_id = find_created_database(config, token, name)
                        if database_id is None:
                            print(
                                f"Error: the database {name} was not found; "
                                "check your account for it by hand",
                                file=sys.stderr,
                            )
                            exit_code = 1
                    if database_id is not None:
                        delete_database(config, token, database_id)
                        print("Deleted database")
                        if backup_id is not None:
                            print(backup_after_delete(config, token, backup_id))
                except (httpx.HTTPError, KeyError, ValueError, TimeoutError) as e:
                    print(f"Error: {e}", file=sys.stderr)
                    print(
                        f"Delete the database {database_id or name} by hand, "
                        "because it may still be billing",
                        file=sys.stderr,
                    )
                    exit_code = 1
    
        return exit_code
    
    
    if __name__ == "__main__":
        sys.exit(main())
    ```

=== "TypeScript"

    ```typescript
    // Returns a readable description of an error. A failure to connect
    // arrives as a TypeError whose cause holds the details, and Node reports
    // a failure to reach several addresses as an AggregateError.
    function describe(err: unknown): string {
      if (err instanceof AggregateError) {
        return err.errors.map(describe).join("; ");
      }
      if (err instanceof Error && err.cause) {
        return `${err.message}: ${describe(err.cause)}`;
      }
      return err instanceof Error ? err.message : String(err);
    }
    
    async function main(): Promise<number> {
      let exitCode = 0;
      let token: string | undefined;
      let name: string | undefined;
      let databaseId: string | undefined;
      let backupId: string | undefined;
      let lookup = false;
      try {
        token = await getToken();
    
        const { region, size } = await choosePlacement(token);
        console.log(`Region: ${region}`);
        console.log(`Size: ${size}`);
    
        // Choose the name before the request, so that the program can find
        // the database even if the reply to the request never arrives.
        const suffix = randomBytes(3).toString("hex");
        name = `cookbook${suffix}`;
        // Look the database up by name afterwards only if the outcome of the
        // request is unknown, so that a refusal cannot lead the cleanup to
        // delete another database that has the same name.
        const ip = await clientIp(token);
        lookup = true;
        let database;
        try {
          database = await createDatabase(
            token,
            name,
            `cookbook-${suffix}`,
            region,
            size,
            ip,
          );
        } catch (err) {
          lookup = outcomeUnknown(err);
          throw err;
        }
        databaseId = database.id;
        console.log(`Created database ${database.display_name}`);
    
        await waitUntilAvailable(token, databaseId);
        console.log("Database is available");
    
        backupId = (await takeBackup(token, databaseId)).id;
        console.log("Backup started");
        await waitForBackup(token, backupId);
        await printTasks(token, databaseId);
      } catch (err) {
        if (interrupt.signal.aborted) {
          console.error("Interrupted");
          exitCode = 130;
        } else {
          console.error(`Error: ${describe(err)}`);
          exitCode = 1;
        }
      } finally {
        // Delete the database whether the example succeeded, failed, or was
        // interrupted, because the service bills for it until then.
        if (token && name) {
          try {
            if (!databaseId && lookup) {
              databaseId = await findCreatedDatabase(
                token,
                name,
                new AbortController().signal,
              );
              if (!databaseId) {
                console.error(
                  `Error: the database ${name} was not found; check your account for it by hand`,
                );
                exitCode = 1;
              }
            }
            if (databaseId) {
              await deleteDatabase(token, databaseId);
              console.log("Deleted database");
              if (backupId) {
                console.log(await backupAfterDelete(token, backupId));
              }
            }
          } catch (err) {
            console.error(`Error: ${describe(err)}`);
            console.error(
              `Delete the database ${databaseId ?? name} by hand, because it may still be billing`,
            );
            exitCode = 1;
          }
        }
      }
      return exitCode;
    }
    
    process.exitCode = await main();
    ```

=== "Java"

    ```java
    // What the clean-up needs to know, guarded by LOCK.
    static Settings cfg;
    static String token;
    static String name;
    static String databaseId;
    static boolean lookup;
    static String backupId;
    /** The exit status, once the clean-up has run. */
    static Integer result;
    /** Set once the clean-up has started. */
    static volatile boolean cleaning;
    /** Set once the main thread has finished, clean-up included. */
    static volatile boolean exiting;
    
    /**
     * Returns the message of an error. Some errors, such as a refused
     * connection, have no message, so their type stands in for one.
     */
    static String describe(Exception e) {
        return Objects.requireNonNullElse(e.getMessage(), e.toString());
    }
    
    /**
     * Deletes the database, if the program created one, and returns the
     * exit status. The main thread and the shutdown hook both call this,
     * and whichever comes first does the work; the other waits for it and
     * gets the same status.
     */
    static int cleanUp(int status) {
        synchronized (LOCK) {
            if (result != null) {
                return result;
            }
            cleaning = true;
            if (token != null && name != null) {
                try {
                    if (databaseId == null && lookup) {
                        databaseId = findCreatedDatabase(cfg, token, name);
                        if (databaseId == null) {
                            System.err.println("Error: the database " + name
                                    + " was not found; check your account for"
                                    + " it by hand");
                            status = 1;
                        }
                    }
                    if (databaseId != null) {
                        deleteDatabase(cfg, token, databaseId);
                        System.out.println("Deleted database");
                        if (backupId != null) {
                            System.out.println(backupAfterDelete(cfg, token, backupId));
                        }
                    }
                } catch (IOException | InterruptedException | JacksonException
                        | IllegalStateException e) {
                    System.err.println("Error: " + describe(e));
                    System.err.println("Delete the database "
                            + (databaseId != null ? databaseId : name)
                            + " by hand, because it may still be billing");
                    status = 1;
                }
            }
            result = status;
            return status;
        }
    }
    
    public static void main(String[] args) {
        // Java cannot catch a signal with its supported API, but SIGINT and
        // SIGTERM start an orderly shutdown that runs this hook. The hook
        // stops the main thread's requests, deletes the database (or waits
        // for the main thread to finish doing so), and ends the program
        // with the status of the clean-up. A normal exit runs the hook too,
        // after the main thread has cleaned up.
        Runtime.getRuntime().addShutdownHook(new Thread(() -> {
            if (!exiting) {
                interrupted = true;
                if (!cleaning) {
                    System.err.println("Interrupted");
                }
            }
            int status = cleanUp(130);
            System.out.flush();
            Runtime.getRuntime().halt(status);
        }));
    
        // The status stays 1 unless every step succeeds, so that an
        // unexpected error, which the catch does not handle, still ends
        // the program with a failure.
        int status = 1;
        try {
            cfg = settings();
            String bearer = getToken(cfg);
            synchronized (LOCK) {
                token = bearer;
            }
    
            Placement placement = choosePlacement(cfg, bearer);
            System.out.println("Region: " + placement.region());
            System.out.println("Size: " + placement.size());
    
            // Choose the name before the request, so that the program can
            // find the database even if the reply to the request never
            // arrives.
            byte[] random = new byte[3];
            new SecureRandom().nextBytes(random);
            String suffix = HexFormat.of().formatHex(random);
            String displayName = "cookbook-" + suffix;
            String ip = clientIp(cfg, bearer);
            JsonNode database;
            // Hold the lock until the ID is recorded, so that a signal
            // during the create call cannot leave the database behind.
            synchronized (LOCK) {
                name = "cookbook" + suffix;
                // Look the database up by name afterwards only if the
                // outcome of the request is unknown, so that a refusal
                // cannot lead the clean-up to delete another database that
                // has the same name.
                lookup = true;
                try {
                    database = createDatabase(cfg, bearer, name, displayName,
                            placement, ip);
                } catch (IOException | JacksonException e) {
                    lookup = outcomeUnknown(e);
                    throw e;
                }
                databaseId = field(database, "id");
            }
            System.out.println("Created database " + field(database, "display_name"));
    
            waitUntilAvailable(cfg, bearer, databaseId);
            System.out.println("Database is available");
    
            String backup = field(takeBackup(cfg, bearer, databaseId), "id");
            synchronized (LOCK) {
                backupId = backup;
            }
            System.out.println("Backup started");
            waitForBackup(cfg, bearer, backup);
            printTasks(cfg, bearer, databaseId);
            status = 0;
        // IOException covers failures to connect and error replies from the
        // API; InterruptedException means that a signal arrived, which the
        // shutdown hook reports; Jackson throws JacksonException for a
        // reply that is not JSON; and IllegalStateException covers replies
        // that the program cannot use.
        } catch (IOException | InterruptedException | JacksonException
                | IllegalStateException e) {
            if (!interrupted) {
                System.err.println("Error: " + describe(e));
            }
        } finally {
            // Delete the database whether the example succeeded, failed, or
            // was interrupted, because the service bills for it until then.
            // The finally block also runs for an error that the catch does
            // not handle.
            status = cleanUp(interrupted ? 130 : status);
        }
        exiting = true;
        System.exit(status);
    }
    ```

=== "C#"

    ```csharp
    // Reports whether an error is one that the program expects: a failure to
    // connect, an error reply from the API, a request that timed out, a reply
    // that is not JSON, or a reply that the program cannot use.
    static bool Expected(Exception e) => e is HttpRequestException
        or TaskCanceledException or JsonException or InvalidOperationException;
    
    string? token = null;
    string? name = null;
    string? databaseId = null;
    var lookup = false;
    string? backupId = null;
    var exitCode = 0;
    try
    {
        token = await GetToken();
    
        var (region, size) = await ChoosePlacement(token);
        Console.WriteLine($"Region: {region}");
        Console.WriteLine($"Size: {size}");
    
        // Choose the name before the request, so that the program can find the
        // database even if the reply to the request never arrives.
        var suffix = Convert.ToHexStringLower(RandomNumberGenerator.GetBytes(3));
        name = $"cookbook{suffix}";
        var displayName = $"cookbook-{suffix}";
        // Look the database up by name afterwards only if the outcome of the
        // request is unknown, so that a refusal cannot lead the clean-up to
        // delete another database that has the same name.
        var ip = await ClientIp(token);
        lookup = true;
        JsonNode? database;
        try
        {
            database = await CreateDatabase(token, name, displayName, region, size, ip);
        }
        catch (Exception e) when (Expected(e))
        {
            lookup = OutcomeUnknown(e);
            throw;
        }
        databaseId = Field(database, "id");
        Console.WriteLine($"Created database {Field(database, "display_name")}");
    
        await WaitUntilAvailable(token, databaseId);
        Console.WriteLine("Database is available");
    
        backupId = Field(await TakeBackup(token, databaseId), "id");
        Console.WriteLine("Backup started");
        await WaitForBackup(token, backupId);
        await PrintTasks(token, databaseId);
    }
    // After a signal, the request or wait in progress fails, whatever the
    // error that it reports.
    catch (Exception) when (signalled.IsCancellationRequested)
    {
        Console.Error.WriteLine("Interrupted");
        exitCode = 130;
    }
    catch (Exception e) when (Expected(e))
    {
        Console.Error.WriteLine($"Error: {e.Message}");
        exitCode = 1;
    }
    finally
    {
        // Delete the database whether the example succeeded, failed, or was
        // interrupted, because the service bills for it until then. Signals
        // no longer cancel anything, so that they cannot cut the clean-up
        // short. The finally block also runs for an error that the catch does
        // not handle.
        cancel = CancellationToken.None;
        if (token is not null && name is not null)
        {
            try
            {
                if (databaseId is null && lookup)
                {
                    databaseId = await FindCreatedDatabase(token, name);
                    if (databaseId is null)
                    {
                        Console.Error.WriteLine(
                            $"Error: the database {name} was not found; "
                            + "check your account for it by hand");
                        exitCode = 1;
                    }
                }
                if (databaseId is not null)
                {
                    await DeleteDatabase(token, databaseId);
                    Console.WriteLine("Deleted database");
                    if (backupId is not null)
                    {
                        Console.WriteLine(await BackupAfterDelete(token, backupId));
                    }
                }
            }
            catch (Exception e) when (Expected(e))
            {
                Console.Error.WriteLine($"Error: {e.Message}");
                Console.Error.WriteLine(
                    $"Delete the database {databaseId ?? name} by hand, "
                    + "because it may still be billing");
                exitCode = 1;
            }
        }
    }
    
    return exitCode;
    ```

=== "Go"

    ```go
    // run creates the database, waits for it, and always deletes it, returning
    // any error to the caller.
    func run() (err error) {
    	// Ctrl-C and SIGTERM cancel ctx instead of ending the process, so the
    	// deferred cleanup below still runs.
    	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
    	defer stop()
    	// Note whether a signal arrived, after the deferred clean-up below has
    	// run, so that main can report an interruption.
    	defer func() {
    		if ctx.Err() != nil {
    			interrupted = true
    		}
    	}()
    
    	token, err := getToken(ctx)
    	if err != nil {
    		return err
    	}
    
    	region, size, err := choosePlacement(ctx, token)
    	if err != nil {
    		return err
    	}
    	fmt.Printf("Region: %s\n", region)
    	fmt.Printf("Size: %s\n", size)
    
    	// Choose the name before the request, so that the program can find
    	// the database even if the reply to the request never arrives.
    	suffix, err := randomSuffix()
    	if err != nil {
    		return err
    	}
    	name, displayName := "cookbook"+suffix, "cookbook-"+suffix
    
    	// Delete the database whether the example succeeded, failed, or was
    	// interrupted, because the service bills for it until then. The
    	// cleanup uses its own context, because ctx ends on Ctrl-C, and the
    	// signal handler above keeps absorbing any further signals until run
    	// returns.
    	var databaseID, backupID string
    	lookup := false
    	defer func() {
    		cleanup := context.Background()
    		if databaseID == "" && lookup {
    			id, findErr := findCreatedDatabase(cleanup, token, name)
    			if findErr != nil {
    				err = errors.Join(err, fmt.Errorf("looking for database %s: %w", name, findErr),
    					fmt.Errorf("delete the database %s by hand, because it may still be billing", name))
    				return
    			}
    			if id == "" {
    				err = errors.Join(err, fmt.Errorf("the database %s was not found; check your account for it by hand", name))
    				return
    			}
    			databaseID = id
    		}
    		if databaseID == "" {
    			return
    		}
    		if delErr := deleteDatabase(cleanup, token, databaseID); delErr != nil {
    			err = errors.Join(err, fmt.Errorf("deleting database %s: %w", databaseID, delErr),
    				fmt.Errorf("delete the database %s by hand, because it may still be billing", databaseID))
    			return
    		}
    		fmt.Println("Deleted database")
    		if backupID != "" {
    			fmt.Println(backupAfterDelete(cleanup, token, backupID))
    		}
    	}()
    
    	// Look the database up by name afterwards only if the outcome of the
    	// request is unknown, so that a refusal cannot lead the cleanup to
    	// delete another database that has the same name.
    	ip, err := clientIP(ctx, token)
    	if err != nil {
    		return err
    	}
    	lookup = true
    	database, err := createDatabase(ctx, token, name, displayName, region, size, ip)
    	if err != nil {
    		lookup = outcomeUnknown(err)
    		return err
    	}
    	databaseID = database.ID
    	fmt.Printf("Created database %s\n", database.DisplayName)
    
    	if err := waitUntilAvailable(ctx, token, database.ID); err != nil {
    		return err
    	}
    	fmt.Println("Database is available")
    
    	backup, err := takeBackup(ctx, token, database.ID)
    	if err != nil {
    		return err
    	}
    	backupID = backup.ID
    	fmt.Println("Backup started")
    	if err := waitForBackup(ctx, token, backup.ID); err != nil {
    		return err
    	}
    	return printTasks(ctx, token, database.ID)
    }
    
    // interrupted is set when Ctrl-C or SIGTERM arrived before run() returned.
    var interrupted bool
    
    // main reports any error returned by run() and exits with a non-zero
    // status. After a signal, it prints "Interrupted" and exits with 130, the
    // status of a program that the user stopped, unless the clean-up failed as
    // well, which errors.Join reports on a line of its own.
    func main() {
    	if err := run(); err != nil {
    		if interrupted {
    			fmt.Fprintln(os.Stderr, "Interrupted")
    			if strings.Contains(err.Error(), "\n") {
    				fmt.Fprintf(os.Stderr, "Error: %v\n", err)
    				os.Exit(1)
    			}
    			os.Exit(130)
    		}
    		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
    		os.Exit(1)
    	}
    }
    
    ```

=== "Rust"

    ```rust
    /// What the clean-up needs to know about the database that run created.
    #[derive(Default)]
    struct Created {
        token: Option<String>,
        name: Option<String>,
        database_id: Option<String>,
        lookup: bool,
        backup_id: Option<String>,
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
    
        let backup_id = field(&take_backup(cfg, &token, &database_id)?, "id")?;
        created.backup_id = Some(backup_id.clone());
        println!("Backup started");
        wait_for_backup(cfg, &token, &backup_id)?;
        print_tasks(cfg, &token, &database_id)?;
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
                if let Some(backup_id) = &created.backup_id {
                    println!("{}", backup_after_delete(cfg, token, backup_id)?);
                }
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
    ```

=== "Ruby"

    ```ruby
    def main
      config = settings
      exit_code = 0
      token = nil
      name = nil
      database_id = nil
      lookup = false
      backup_id = nil
      begin
        token = get_token(config)
    
        region, size = choose_placement(config, token)
        puts "Region: #{region}"
        puts "Size: #{size}"
    
        # Choose the name before the request, so that the program can find the
        # database even if the reply to the request never arrives.
        suffix = SecureRandom.hex(3)
        name = "cookbook#{suffix}"
        display_name = "cookbook-#{suffix}"
        # Look the database up by name afterwards only if the outcome of the
        # request is unknown, so that a refusal cannot lead the cleanup to
        # delete another database that has the same name.
        ip = client_ip(config, token)
        lookup = true
        begin
          database = create_database(config, token, name, display_name, region, size, ip)
        rescue StandardError => e
          lookup = outcome_unknown?(e)
          raise
        end
        database_id = database.fetch("id")
        puts "Created database #{database.fetch('display_name')}"
    
        wait_until_available(config, token, database_id)
        puts "Database is available"
    
        backup_id = take_backup(config, token, database_id).fetch("id")
        puts "Backup started"
        wait_for_backup(config, token, backup_id)
        print_tasks(config, token, database_id)
      # Net::HTTP raises errors of many classes, such as SystemCallError for a
      # refused connection and Net::OpenTimeout for a timeout, and the program
      # raises ApiError and RuntimeError for replies that it cannot use, so
      # this catches StandardError, their common ancestor.
      rescue StandardError => e
        warn "Error: #{e.message}"
        exit_code = 1
      # Ruby raises Interrupt for Ctrl-C and SignalException for SIGTERM.
      rescue SignalException
        warn "Interrupted"
        exit_code = 130
      ensure
        # Delete the database whether the example succeeded, failed, or was
        # interrupted, because the service bills for it until then. Ignore
        # further interrupts, so that they cannot cut it short.
        trap("INT", "IGNORE")
        trap("TERM", "IGNORE")
        if token && name
          begin
            if database_id.nil? && lookup
              database_id = find_created_database(config, token, name)
              if database_id.nil?
                warn "Error: the database #{name} was not found; " \
                     "check your account for it by hand"
                exit_code = 1
              end
            end
            if database_id
              delete_database(config, token, database_id)
              puts "Deleted database"
              puts backup_after_delete(config, token, backup_id) if backup_id
            end
          rescue StandardError => e
            warn "Error: #{e.message}"
            warn "Delete the database #{database_id || name} by hand, " \
                 "because it may still be billing"
            exit_code = 1
          end
        end
      end
      exit_code
    end
    
    exit main
    ```

=== "curl"

    ```bash
    # Deletes the database, if the script created one. The EXIT trap runs this
    # function when the script finishes, whether the example succeeded, failed,
    # or was interrupted, because the service bills for the database until then.
    cleanup() {
        local status=$?
        # Ignore further interrupts, so that they cannot cut the cleanup short.
        trap '' INT TERM
        if [[ -n "$token" && -n "$name" ]]; then
            # If the script has no ID and cannot tell whether the create request
            # worked, look for the database by name.
            if [[ -z "$database_id" && "$lookup" == 1 ]]; then
                if ! database_id="$(find_created_database "$name")"; then
                    echo "Error: could not look for database $name" >&2
                    echo "Delete the database $name by hand, because it may still be billing" >&2
                    database_id=""
                    status=1
                elif [[ -z "$database_id" ]]; then
                    echo "Error: the database $name was not found; check your account for it by hand" >&2
                    status=1
                fi
            fi
            if [[ -n "$database_id" ]]; then
                if delete_database "$database_id"; then
                    echo "Deleted database"
                    if [[ -n "$backup_id" ]]; then backup_after_delete "$backup_id"; fi
                else
                    echo "Error: could not delete database $database_id" >&2
                    echo "Delete the database $database_id by hand, because it may still be billing" >&2
                    status=1
                fi
            fi
        fi
        exit "$status"
    }
    
    main() {
        token="" name="" database_id="" backup_id="" lookup=0
        trap cleanup EXIT
        # Turn Ctrl-C and SIGTERM into a normal exit, so that cleanup runs.
        trap 'echo "Interrupted" >&2; exit 130' INT TERM
    
        token="$(get_token)"
    
        local placement region size suffix database display_name reply status ip
        placement="$(choose_placement)"
        region="${placement% *}"
        size="${placement#* }"
        echo "Region: $region"
        echo "Size: $size"
    
        # Choose the name before the request, so that the cleanup can find the
        # database even if the reply to the request never arrives.
        suffix="$(od -An -N3 -tx1 /dev/urandom | tr -d ' \n')"
        name="cookbook$suffix"
    
        # Look the database up by name afterwards only if the outcome of the
        # request is unknown, so that a refusal cannot lead the cleanup to
        # delete another database that has the same name. The create_database
        # function ends its output with the HTTP status on a line of its own,
        # which is 000 if no reply arrived.
        ip="$(client_ip)"
        lookup=1
        if ! reply="$(create_database "$name" "cookbook-$suffix" "$region" "$size" "$ip")"; then
            status="${reply##*$'\n'}"
            echo "Error: creating the database failed" >&2
            echo "${reply%$'\n'*}" >&2
            [[ "$status" =~ ^4[0-9][0-9]$ ]] && lookup=0
            return 1
        fi
        database="${reply%$'\n'*}"
        database_id="$(jq -er '.id' <<<"$database")"
        display_name="$(jq -er '.display_name' <<<"$database")"
        echo "Created database $display_name"
    
        wait_until_available "$database_id"
        echo "Database is available"
    
        local backup
        backup="$(take_backup "$database_id")"
        backup_id="$(jq -er '.id' <<<"$backup")"
        echo "Backup started"
        wait_for_backup "$backup_id"
        print_tasks "$database_id"
    }
    
    main
    ```

## Running the Example

The complete project for each language is available in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/starfleet/backups).
Set the environment variables for your account, and then run the command for
your language from the corresponding project directory. The following tabs show
the commands that build and run each example:

=== "Python"

    ```bash
    python3 -m venv .venv
    .venv/bin/pip install -r requirements.txt
    .venv/bin/python main.py
    ```

=== "TypeScript"

    ```bash
    npm install
    npm run build
    npm start
    ```

=== "Java"

    ```bash
    mvn compile exec:java
    ```

=== "C#"

    ```bash
    dotnet run
    ```

=== "Go"

    ```bash
    go run .
    ```

=== "Rust"

    ```bash
    cargo run
    ```

=== "Ruby"

    ```bash
    bundle install
    bundle exec ruby main.rb
    ```

=== "curl"

    ```bash
    ./main.sh
    ```

The run takes several minutes, almost all of it spent waiting for the database
to become available.

## Viewing the Complete Program

The following tabs show the complete program for each language:

=== "Python"

    ```python
    """
    Ellie's Postgres Cookbook
    Taking an on-demand backup of a pgEdge Starfleet database, and tracking it
    until it completes, using httpx.
    
    The program creates a database of its own to back up. The Starfleet service
    bills for every database from the moment that it becomes connectable, so
    the program deletes the database on every path: after a success, after a
    failure, and after Ctrl-C.
    
    Copyright (c) 2026, pgEdge, Inc.
    This code is released under the PostgreSQL License.
    """
    
    import os
    import secrets
    import signal
    import sys
    import time
    
    import httpx
    
    
    # How long to wait for a database to become available, or to disappear
    # after a delete, and how often to check.
    TIMEOUT_SECONDS = 900
    POLL_SECONDS = 10
    
    # How many times to look for a database whose create reply was lost.
    LOOKUP_ATTEMPTS = 3
    
    
    def settings() -> dict:
        """Reads the API settings from the environment.
    
        The or operator treats an empty variable as unset. The client ID and
        secret have no defaults, so a missing value becomes None, and the
        token request reports it.
        """
        return {
            "base_url": (
                os.environ.get("STARFLEET_API_URL") or "https://api.pgedge.com"
            ).rstrip("/"),
            "client_id": os.environ.get("STARFLEET_CLIENT_ID") or None,
            "client_secret": os.environ.get("STARFLEET_CLIENT_SECRET") or None,
        }
    
    
    def get_token(config: dict) -> str:
        """Exchanges the client ID and secret for an access token, which the
        Managed API accepts as a bearer token until it expires."""
        if not config["client_id"] or not config["client_secret"]:
            raise RuntimeError(
                "STARFLEET_CLIENT_ID and STARFLEET_CLIENT_SECRET must be set"
            )
    
        response = httpx.post(
            f"{config['base_url']}/account/v1/oauth/token",
            json={
                "grant_type": "client_credentials",
                "client_id": config["client_id"],
                "client_secret": config["client_secret"],
            },
            timeout=30,
        )
        # Turn any 4xx or 5xx status into an httpx.HTTPStatusError.
        response.raise_for_status()
        return response.json()["access_token"]
    
    
    def api(config: dict, token: str, method: str, path: str, body=None):
        """Sends an authenticated request to the Managed API and returns the
        decoded JSON reply, or None if the reply has no body."""
        response = httpx.request(
            method,
            f"{config['base_url']}/managed/v1{path}",
            headers={"Authorization": f"Bearer {token}"},
            json=body,
            timeout=30,
        )
        response.raise_for_status()
        return response.json() if response.content else None
    
    
    def choose_placement(config: dict, token: str) -> tuple[str, str]:
        """Returns the region and size for the new database.
    
        The API lists sizes smallest first, so the first one is the cheapest.
        The API does not price regions, so the example takes the first one.
        """
        regions = api(config, token, "GET", "/regions")
        sizes = api(config, token, "GET", "/sizes")
        if not regions or not sizes:
            raise RuntimeError("the API offers no region or size")
        return regions[0]["region"], sizes[0]["name"]
    
    
    def client_ip(config: dict, token: str) -> str:
        """Returns the address that the API sees requests come from."""
        # A new database is closed to everyone until an allowlist rule admits
        # an address. The API reports the address it sees this request come
        # from, which is the one to admit; a bare address means a single host.
        return api(config, token, "GET", "/client-ip")["ip_address"]
    
    
    def create_database(
        config: dict, token: str, name: str, display_name: str, region: str,
        size: str, ip: str,
    ) -> dict:
        """Creates a database that only this machine can reach, and returns
        the API's description of it, which includes its ID."""
        return api(config, token, "POST", "/databases", {
            # The name becomes the Postgres database name, so it holds only
            # letters and digits, and the readable cookbook- prefix goes in
            # the display name. The program also uses the name to find the
            # database again if the reply to this request is lost.
            "name": name,
            "display_name": display_name,
            "region": region,
            "size": size,
            "ip_allowlist": {"rules": [{"cidr": ip, "label": "cookbook"}]},
        })
    
    
    # The API does not document its status values; the example treats these
    # two as failures, which end the wait at once instead of leaving it to run
    # until the time limit.
    FAILED_STATUSES = {"degraded", "failed"}
    
    
    def wait_until_available(config: dict, token: str, database_id: str) -> None:
        """Polls the database until its status is available."""
        deadline = time.monotonic() + TIMEOUT_SECONDS
        last = None
        while time.monotonic() < deadline:
            status = api(config, token, "GET", f"/databases/{database_id}")["status"]
            if status != last:
                print(f"Database status: {status}")
                last = status
            if status == "available":
                return
            if status in FAILED_STATUSES:
                raise RuntimeError(f"the database has the status {status}")
            time.sleep(POLL_SECONDS)
        raise TimeoutError(f"the database was not available after {TIMEOUT_SECONDS} seconds")
    
    
    # The API does not document its backup status values beyond "completed",
    # which marks a usable backup; the example treats "failed" as a failure,
    # which ends the wait at once instead of leaving it to run until the time
    # limit.
    FAILED_BACKUP_STATUSES = {"failed"}
    
    
    def take_backup(config: dict, token: str, database_id: str) -> dict:
        """Starts an on-demand backup and returns the pending backup."""
        # The hot kind is a fast local snapshot. The durable kind streams a
        # base backup to object storage, and needs the durable tier to be
        # enabled for the database. The API answers 202 at once and runs the
        # backup in the background.
        return api(
            config, token, "POST", f"/databases/{database_id}/backup",
            {"kind": "hot"},
        )
    
    
    def wait_for_backup(config: dict, token: str, backup_id: str) -> None:
        """Polls the backup until its status is completed."""
        deadline = time.monotonic() + TIMEOUT_SECONDS
        last = None
        while time.monotonic() < deadline:
            status = api(config, token, "GET", f"/backups/{backup_id}")["status"]
            if status != last:
                print(f"Backup status: {status}")
                last = status
            if status == "completed":
                return
            if status in FAILED_BACKUP_STATUSES:
                raise RuntimeError(f"the backup has the status {status}")
            time.sleep(POLL_SECONDS)
        raise TimeoutError(f"the backup was not completed after {TIMEOUT_SECONDS} seconds")
    
    
    def print_tasks(config: dict, token: str, database_id: str) -> None:
        """Prints the name and status of each task recorded for the database."""
        # Managed database operations record their progress as tasks, with the
        # kind "database" and the database ID as the subject.
        tasks = api(
            config, token, "GET",
            f"/tasks?subject_kind=database&subject_id={database_id}",
        )
        for task in tasks or []:
            print(f"Task: {task['name']} ({task['status']})")
    
    
    def backup_after_delete(config: dict, token: str, backup_id: str) -> str:
        """Reports whether the API still lists a backup once its database has
        been deleted. The API specification gives no rule for this, so the
        example only observes it."""
        prefix = "Backup after the database was deleted:"
        try:
            api(config, token, "GET", f"/backups/{backup_id}")
            return f"{prefix} still listed"
        except httpx.HTTPStatusError as e:
            return f"{prefix} {'gone' if e.response.status_code == 404 else 'unknown'}"
        except httpx.TransportError:
            return f"{prefix} unknown"
    
    
    def is_transient(error: Exception) -> bool:
        """Reports whether a failed request is worth repeating: no reply
        arrived, the service is overloaded or failing, or it answered 409,
        which the API does whilst a database is still being created."""
        if isinstance(error, httpx.TransportError):
            return True
        if isinstance(error, httpx.HTTPStatusError):
            status = error.response.status_code
            return status in (409, 429) or status >= 500
        return False
    
    
    def is_gone(error: Exception) -> bool:
        """Reports whether an error is a 404 reply, which means that the
        database does not exist."""
        return (
            isinstance(error, httpx.HTTPStatusError)
            and error.response.status_code == 404
        )
    
    
    def find_database(config: dict, token: str, name: str):
        """Returns the ID of the database with the given name, or None. The
        program uses this when it cannot tell whether a create request worked.
        It repeats the request, as the delete does, because the fault that
        lost the reply to the create request may still be there. The request
        asks for the newest databases first, but the API does not say which
        property it sorts on."""
        deadline = time.monotonic() + TIMEOUT_SECONDS
        while True:
            try:
                databases = api(
                    config, token, "GET", "/databases?limit=100&descending=true"
                )
                break
            except httpx.HTTPError as e:
                if not is_transient(e) or time.monotonic() > deadline:
                    raise
                time.sleep(POLL_SECONDS)
        for database in databases or []:
            if database["name"] == name:
                return database["id"]
        return None
    
    
    def find_created_database(config: dict, token: str, name: str):
        """Looks for the database a few times, because the service may not
        have recorded a request whose reply was lost until a little later.
        Returns None if the database never appears."""
        for attempt in range(LOOKUP_ATTEMPTS):
            database_id = find_database(config, token, name)
            if database_id is not None:
                return database_id
            if attempt < LOOKUP_ATTEMPTS - 1:
                time.sleep(POLL_SECONDS)
        return None
    
    
    def outcome_unknown(error: Exception) -> bool:
        """Reports whether a failed create request might still have created
        the database: no reply arrived, or the service failed with a 5xx
        status. A 4xx reply is a definite refusal."""
        if isinstance(error, httpx.HTTPStatusError):
            return error.response.status_code >= 500
        return True
    
    
    def delete_database(config: dict, token: str, database_id: str) -> None:
        """Deletes the database and waits until the API no longer lists it."""
        deadline = time.monotonic() + TIMEOUT_SECONDS
        while True:
            try:
                api(config, token, "DELETE", f"/databases/{database_id}")
                break
            except httpx.HTTPError as e:
                if is_gone(e):
                    return
                if not is_transient(e) or time.monotonic() > deadline:
                    raise
                time.sleep(POLL_SECONDS)
    
        # The delete starts the teardown; a 404 shows that it has finished.
        while time.monotonic() < deadline:
            try:
                api(config, token, "GET", f"/databases/{database_id}")
            except httpx.HTTPError as e:
                if is_gone(e):
                    return
                if not is_transient(e):
                    raise
            time.sleep(POLL_SECONDS)
        raise TimeoutError(f"the database was still present after {TIMEOUT_SECONDS} seconds")
    
    
    def stop(*_) -> None:
        """Handles SIGTERM like Ctrl-C, by raising KeyboardInterrupt."""
        raise KeyboardInterrupt
    
    
    def main() -> int:
        # Turn SIGTERM into a KeyboardInterrupt, so that the finally block
        # runs, as it does for Ctrl-C.
        signal.signal(signal.SIGTERM, stop)
    
        config = settings()
        exit_code = 0
        token = None
        name = None
        database_id = None
        backup_id = None
        lookup = False
        try:
            token = get_token(config)
    
            region, size = choose_placement(config, token)
            print(f"Region: {region}")
            print(f"Size: {size}")
    
            # Choose the name before the request, so that the program can find
            # the database even if the reply to the request never arrives.
            suffix = secrets.token_hex(3)
            name, display_name = f"cookbook{suffix}", f"cookbook-{suffix}"
            # Look the database up by name afterwards only if the outcome of
            # the request is unknown, so that a refusal cannot lead the
            # cleanup to delete another database that has the same name.
            ip = client_ip(config, token)
            lookup = True
            try:
                database = create_database(
                    config, token, name, display_name, region, size, ip
                )
            except (httpx.HTTPError, ValueError) as e:
                lookup = outcome_unknown(e)
                raise
            database_id = database["id"]
            print(f"Created database {database['display_name']}")
    
            wait_until_available(config, token, database_id)
            print("Database is available")
    
            backup_id = take_backup(config, token, database_id)["id"]
            print("Backup started")
            wait_for_backup(config, token, backup_id)
            print_tasks(config, token, database_id)
        # httpx.HTTPError covers connection failures and, through
        # raise_for_status(), error responses from the API.
        except (httpx.HTTPError, KeyError, ValueError, RuntimeError, TimeoutError) as e:
            print(f"Error: {e}", file=sys.stderr)
            exit_code = 1
        except KeyboardInterrupt:
            print("Interrupted", file=sys.stderr)
            exit_code = 130
        finally:
            # Delete the database whether the example succeeded, failed, or
            # was interrupted, because the service bills for it until then.
            # Ignore further interrupts, so that they cannot cut it short.
            signal.signal(signal.SIGINT, signal.SIG_IGN)
            signal.signal(signal.SIGTERM, signal.SIG_IGN)
            if token is not None and name is not None:
                try:
                    if database_id is None and lookup:
                        database_id = find_created_database(config, token, name)
                        if database_id is None:
                            print(
                                f"Error: the database {name} was not found; "
                                "check your account for it by hand",
                                file=sys.stderr,
                            )
                            exit_code = 1
                    if database_id is not None:
                        delete_database(config, token, database_id)
                        print("Deleted database")
                        if backup_id is not None:
                            print(backup_after_delete(config, token, backup_id))
                except (httpx.HTTPError, KeyError, ValueError, TimeoutError) as e:
                    print(f"Error: {e}", file=sys.stderr)
                    print(
                        f"Delete the database {database_id or name} by hand, "
                        "because it may still be billing",
                        file=sys.stderr,
                    )
                    exit_code = 1
    
        return exit_code
    
    
    if __name__ == "__main__":
        sys.exit(main())
    
    ```

=== "TypeScript"

    ```typescript
    /*
     * Ellie's Postgres Cookbook
     * Taking an on-demand backup of a pgEdge Starfleet database, and tracking
     * it until it completes, using the built-in fetch function.
     *
     * The program creates a database of its own to back up. The Starfleet
     * service bills for every database from the moment that it becomes
     * connectable, so the program deletes the database on every path: after a
     * success, after a failure, and after Ctrl-C.
     *
     * Copyright (c) 2026, pgEdge, Inc.
     * This code is released under the PostgreSQL License.
     */
    
    import { randomBytes } from "node:crypto";
    import process from "node:process";
    import { setTimeout as sleep } from "node:timers/promises";
    
    // How long to wait for a database to become available, or to disappear
    // after a delete, and how often to check.
    const TIMEOUT_MS = 900_000;
    const POLL_MS = 10_000;
    
    // How many times to look for a database whose create reply was lost.
    const LOOKUP_ATTEMPTS = 3;
    
    // Read the API settings from the environment. The || operator, unlike ??,
    // also treats an empty variable as unset.
    const baseUrl = (
      process.env.STARFLEET_API_URL || "https://api.pgedge.com"
    ).replace(/\/+$/, "");
    const clientId = process.env.STARFLEET_CLIENT_ID || "";
    const clientSecret = process.env.STARFLEET_CLIENT_SECRET || "";
    
    // Ctrl-C and SIGTERM abort the signal below instead of ending the
    // process, which lets the program delete its database before it exits.
    // The handlers stay in place, so a further Ctrl-C does not end the process
    // during the cleanup either.
    const interrupt = new AbortController();
    for (const signalName of ["SIGINT", "SIGTERM"] as const) {
      process.on(signalName, () => interrupt.abort());
    }
    
    // Exchanges the client ID and secret for an access token, which the
    // Managed API accepts as a bearer token until it expires.
    async function getToken(): Promise<string> {
      if (!clientId || !clientSecret) {
        throw new Error(
          "STARFLEET_CLIENT_ID and STARFLEET_CLIENT_SECRET must be set",
        );
      }
    
      const response = await fetch(`${baseUrl}/account/v1/oauth/token`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          grant_type: "client_credentials",
          client_id: clientId,
          client_secret: clientSecret,
        }),
        signal: AbortSignal.timeout(30_000),
      });
    
      // fetch only rejects on network failures, so check the status here.
      if (!response.ok) {
        throw new Error(
          `token request failed: ${response.status} ${await response.text()}`,
        );
      }
      const body = (await response.json()) as { access_token: string };
      return body.access_token;
    }
    
    // An error reply from the Managed API, with its HTTP status.
    class ApiError extends Error {
      constructor(
        readonly status: number,
        message: string,
      ) {
        super(message);
      }
    }
    
    // Sends an authenticated request to the Managed API and returns the
    // decoded JSON reply, or undefined if the reply has no body. The request
    // stops when the user presses Ctrl-C, unless the caller passes a
    // different signal, as the cleanup does.
    async function api<T>(
      token: string,
      method: string,
      path: string,
      body?: unknown,
      signal: AbortSignal = interrupt.signal,
    ): Promise<T | undefined> {
      const response = await fetch(`${baseUrl}/managed/v1${path}`, {
        method,
        headers: {
          Authorization: `Bearer ${token}`,
          ...(body === undefined ? {} : { "Content-Type": "application/json" }),
        },
        body: body === undefined ? undefined : JSON.stringify(body),
        signal: AbortSignal.any([signal, AbortSignal.timeout(30_000)]),
      });
      if (!response.ok) {
        throw new ApiError(
          response.status,
          `${method} ${path} failed: ${response.status} ${await response.text()}`,
        );
      }
      const text = await response.text();
      return text ? (JSON.parse(text) as T) : undefined;
    }
    
    // Returns the region and size for the new database. The API lists sizes
    // smallest first, so the first one is the cheapest. The API does not
    // price regions, so the example takes the first one.
    async function choosePlacement(
      token: string,
    ): Promise<{ region: string; size: string }> {
      const regions = await api<{ region: string }[]>(token, "GET", "/regions");
      const sizes = await api<{ name: string }[]>(token, "GET", "/sizes");
      if (!regions?.length || !sizes?.length) {
        throw new Error("the API offers no region or size");
      }
      return { region: regions[0].region, size: sizes[0].name };
    }
    
    interface Database {
      id: string;
      display_name: string;
      status: string;
    }
    
    // Returns this machine's public IP address as the API sees it.
    async function clientIp(token: string): Promise<string> {
      // A new database is closed to everyone until an allowlist rule admits
      // an address. The API reports the address it sees this request come
      // from, which is the one to admit; a bare address means a single host.
      const reply = await api<{ ip_address: string }>(token, "GET", "/client-ip");
      return reply!.ip_address;
    }
    
    // Creates a database that only this machine can reach, and returns the
    // API's description of it, which includes its ID.
    async function createDatabase(
      token: string,
      name: string,
      displayName: string,
      region: string,
      size: string,
      ip: string,
    ): Promise<Database> {
      const database = await api<Database>(token, "POST", "/databases", {
        // The name becomes the Postgres database name, so it holds only
        // letters and digits, and the readable cookbook- prefix goes in the
        // display name. The program also uses the name to find the database
        // again if the reply to this request is lost.
        name,
        display_name: displayName,
        region,
        size,
        ip_allowlist: { rules: [{ cidr: ip, label: "cookbook" }] },
      });
      return database!;
    }
    
    // Polls the database until its status is available.
    async function waitUntilAvailable(
      token: string,
      databaseId: string,
    ): Promise<void> {
      const deadline = Date.now() + TIMEOUT_MS;
      let last = "";
      while (Date.now() < deadline) {
        const database = await api<Database>(token, "GET", `/databases/${databaseId}`);
        if (database!.status !== last) {
          console.log(`Database status: ${database!.status}`);
          last = database!.status;
        }
        if (database!.status === "available") {
          return;
        }
        // The API does not document its status values; the example treats
        // these two as failures, which end the wait at once instead of leaving
        // it to run until the time limit.
        if (database!.status === "degraded" || database!.status === "failed") {
          throw new Error(`the database has the status ${database!.status}`);
        }
        await sleep(POLL_MS, undefined, { signal: interrupt.signal });
      }
      throw new Error(`the database was not available after ${TIMEOUT_MS / 1000} seconds`);
    }
    
    interface Backup {
      id: string;
      status: string;
    }
    
    // The API does not document its backup status values beyond "completed",
    // which marks a usable backup; the example treats "failed" as a failure,
    // which ends the wait at once instead of leaving it to run until the time
    // limit.
    const FAILED_BACKUP_STATUSES = new Set(["failed"]);
    
    // Starts an on-demand backup and returns the pending backup.
    async function takeBackup(token: string, databaseId: string): Promise<Backup> {
      // The hot kind is a fast local snapshot. The durable kind streams a base
      // backup to object storage, and needs the durable tier to be enabled for
      // the database. The API answers 202 at once and runs the backup in the
      // background.
      const backup = await api<Backup>(
        token,
        "POST",
        `/databases/${databaseId}/backup`,
        { kind: "hot" },
      );
      return backup!;
    }
    
    // Polls the backup until its status is completed.
    async function waitForBackup(token: string, backupId: string): Promise<void> {
      const deadline = Date.now() + TIMEOUT_MS;
      let last = "";
      while (Date.now() < deadline) {
        const backup = await api<Backup>(token, "GET", `/backups/${backupId}`);
        if (backup!.status !== last) {
          console.log(`Backup status: ${backup!.status}`);
          last = backup!.status;
        }
        if (backup!.status === "completed") {
          return;
        }
        if (FAILED_BACKUP_STATUSES.has(backup!.status)) {
          throw new Error(`the backup has the status ${backup!.status}`);
        }
        await sleep(POLL_MS, undefined, { signal: interrupt.signal });
      }
      throw new Error(`the backup was not completed after ${TIMEOUT_MS / 1000} seconds`);
    }
    
    // Prints the name and status of each task recorded for the database.
    async function printTasks(token: string, databaseId: string): Promise<void> {
      // Managed database operations record their progress as tasks, with the
      // kind "database" and the database ID as the subject.
      const tasks = await api<{ name: string; status: string }[]>(
        token,
        "GET",
        `/tasks?subject_kind=database&subject_id=${databaseId}`,
      );
      for (const task of tasks ?? []) {
        console.log(`Task: ${task.name} (${task.status})`);
      }
    }
    
    // Reports whether the API still lists a backup once its database has been
    // deleted. The API specification gives no rule for this, so the example
    // only observes it.
    async function backupAfterDelete(token: string, backupId: string): Promise<string> {
      const prefix = "Backup after the database was deleted:";
      try {
        await api(token, "GET", `/backups/${backupId}`, undefined, new AbortController().signal);
        return `${prefix} still listed`;
      } catch (err) {
        return `${prefix} ${err instanceof ApiError && err.status === 404 ? "gone" : "unknown"}`;
      }
    }
    
    // Reports whether a failed request is worth repeating: no reply arrived
    // (fetch rejects, and the error is not an ApiError), the service is
    // overloaded or failing, or it answered 409, which the API does whilst a
    // database is still being created.
    function isTransient(err: unknown): boolean {
      if (!(err instanceof ApiError)) {
        return true;
      }
      return err.status === 409 || err.status === 429 || err.status >= 500;
    }
    
    // Looks for the database a few times, because the service may not have
    // recorded a request whose reply was lost until a little later. Returns
    // undefined if the database never appears.
    async function findCreatedDatabase(
      token: string,
      name: string,
      signal: AbortSignal,
    ): Promise<string | undefined> {
      for (let attempt = 1; ; attempt++) {
        const id = await findDatabase(token, name, signal);
        if (id || attempt === LOOKUP_ATTEMPTS) {
          return id;
        }
        await sleep(POLL_MS);
      }
    }
    
    // Reports whether a failed create request might still have created the
    // database: no reply arrived, the reply could not be decoded, or the
    // service failed with a 5xx status. A 4xx reply is a definite refusal.
    function outcomeUnknown(err: unknown): boolean {
      return !(err instanceof ApiError) || err.status >= 500;
    }
    
    // Returns the ID of the database with the given name, or undefined. The
    // program uses this when it cannot tell whether a create request worked.
    // It repeats the request, as the delete does, because the fault that lost
    // the reply to the create request may still be there. The request asks for
    // the newest databases first, but the API does not say which property it
    // sorts on.
    async function findDatabase(
      token: string,
      name: string,
      signal: AbortSignal,
    ): Promise<string | undefined> {
      const deadline = Date.now() + TIMEOUT_MS;
      for (;;) {
        try {
          const databases = await api<{ id: string; name: string }[]>(
            token,
            "GET",
            "/databases?limit=100&descending=true",
            undefined,
            signal,
          );
          return databases?.find((database) => database.name === name)?.id;
        } catch (err) {
          if (!isTransient(err) || Date.now() > deadline) {
            throw err;
          }
          await sleep(POLL_MS);
        }
      }
    }
    
    // Deletes the database and waits until the API no longer lists it. The
    // requests ignore Ctrl-C, so that a second interrupt cannot leave the
    // database behind.
    async function deleteDatabase(token: string, databaseId: string): Promise<void> {
      const never = new AbortController().signal;
      const deadline = Date.now() + TIMEOUT_MS;
    
      for (;;) {
        try {
          await api(token, "DELETE", `/databases/${databaseId}`, undefined, never);
          break;
        } catch (err) {
          if (err instanceof ApiError && err.status === 404) {
            return;
          }
          if (!isTransient(err) || Date.now() > deadline) {
            throw err;
          }
          await sleep(POLL_MS);
        }
      }
    
      // The delete starts the teardown; a 404 shows that it has finished.
      while (Date.now() < deadline) {
        try {
          await api(token, "GET", `/databases/${databaseId}`, undefined, never);
        } catch (err) {
          if (err instanceof ApiError && err.status === 404) {
            return;
          }
          if (!isTransient(err)) {
            throw err;
          }
        }
        await sleep(POLL_MS);
      }
      throw new Error(`the database was still present after ${TIMEOUT_MS / 1000} seconds`);
    }
    
    // Returns a readable description of an error. A failure to connect
    // arrives as a TypeError whose cause holds the details, and Node reports
    // a failure to reach several addresses as an AggregateError.
    function describe(err: unknown): string {
      if (err instanceof AggregateError) {
        return err.errors.map(describe).join("; ");
      }
      if (err instanceof Error && err.cause) {
        return `${err.message}: ${describe(err.cause)}`;
      }
      return err instanceof Error ? err.message : String(err);
    }
    
    async function main(): Promise<number> {
      let exitCode = 0;
      let token: string | undefined;
      let name: string | undefined;
      let databaseId: string | undefined;
      let backupId: string | undefined;
      let lookup = false;
      try {
        token = await getToken();
    
        const { region, size } = await choosePlacement(token);
        console.log(`Region: ${region}`);
        console.log(`Size: ${size}`);
    
        // Choose the name before the request, so that the program can find
        // the database even if the reply to the request never arrives.
        const suffix = randomBytes(3).toString("hex");
        name = `cookbook${suffix}`;
        // Look the database up by name afterwards only if the outcome of the
        // request is unknown, so that a refusal cannot lead the cleanup to
        // delete another database that has the same name.
        const ip = await clientIp(token);
        lookup = true;
        let database;
        try {
          database = await createDatabase(
            token,
            name,
            `cookbook-${suffix}`,
            region,
            size,
            ip,
          );
        } catch (err) {
          lookup = outcomeUnknown(err);
          throw err;
        }
        databaseId = database.id;
        console.log(`Created database ${database.display_name}`);
    
        await waitUntilAvailable(token, databaseId);
        console.log("Database is available");
    
        backupId = (await takeBackup(token, databaseId)).id;
        console.log("Backup started");
        await waitForBackup(token, backupId);
        await printTasks(token, databaseId);
      } catch (err) {
        if (interrupt.signal.aborted) {
          console.error("Interrupted");
          exitCode = 130;
        } else {
          console.error(`Error: ${describe(err)}`);
          exitCode = 1;
        }
      } finally {
        // Delete the database whether the example succeeded, failed, or was
        // interrupted, because the service bills for it until then.
        if (token && name) {
          try {
            if (!databaseId && lookup) {
              databaseId = await findCreatedDatabase(
                token,
                name,
                new AbortController().signal,
              );
              if (!databaseId) {
                console.error(
                  `Error: the database ${name} was not found; check your account for it by hand`,
                );
                exitCode = 1;
              }
            }
            if (databaseId) {
              await deleteDatabase(token, databaseId);
              console.log("Deleted database");
              if (backupId) {
                console.log(await backupAfterDelete(token, backupId));
              }
            }
          } catch (err) {
            console.error(`Error: ${describe(err)}`);
            console.error(
              `Delete the database ${databaseId ?? name} by hand, because it may still be billing`,
            );
            exitCode = 1;
          }
        }
      }
      return exitCode;
    }
    
    process.exitCode = await main();
    
    ```

=== "Java"

    ```java
    /*
     * Ellie's Postgres Cookbook
     * Taking an on-demand backup of a pgEdge Starfleet database, and tracking it
     * until it completes, using java.net.http and Jackson.
     *
     * The program creates a database of its own to back up. The Starfleet
     * service bills for every database from the moment that it becomes
     * connectable, so the program deletes the database on every path: after a
     * success, after a failure, and after Ctrl-C.
     *
     * Copyright (c) 2026, pgEdge, Inc.
     * This code is released under the PostgreSQL License.
     */
    
    import java.io.IOException;
    import java.net.URI;
    import java.net.http.HttpClient;
    import java.net.http.HttpRequest;
    import java.net.http.HttpResponse;
    import java.net.http.HttpTimeoutException;
    import java.security.SecureRandom;
    import java.time.Duration;
    import java.util.HexFormat;
    import java.util.List;
    import java.util.Map;
    import java.util.Objects;
    import java.util.Set;
    import java.util.concurrent.CompletableFuture;
    import java.util.concurrent.ExecutionException;
    import java.util.concurrent.TimeUnit;
    import java.util.concurrent.TimeoutException;
    import tools.jackson.core.JacksonException;
    import tools.jackson.databind.JsonNode;
    import tools.jackson.databind.ObjectMapper;
    
    public class Main {
    
        /**
         * How long to wait for a database to become available, or to disappear
         * after a delete, and how often to check.
         */
        static final int TIMEOUT_SECONDS = 900;
        static final int POLL_SECONDS = 10;
    
        /** How many times to look for a database whose create reply was lost. */
        static final int LOOKUP_ATTEMPTS = 3;
    
        /** The settings that the program reads from the environment. */
        record Settings(String baseUrl, String clientId, String clientSecret) {}
    
        /**
         * Returns the value of an environment variable, or the fallback if the
         * variable is unset or empty, as an unset variable would be.
         */
        static String envOr(String name, String fallback) {
            String value = System.getenv(name);
            return (value != null && !value.isEmpty()) ? value : fallback;
        }
    
        /**
         * Reads the API settings from the environment. The client ID and secret
         * have no defaults, so a missing value becomes null, and the token
         * request reports it.
         */
        static Settings settings() {
            return new Settings(
                    envOr("STARFLEET_API_URL", "https://api.pgedge.com")
                            .replaceAll("/+$", ""),
                    envOr("STARFLEET_CLIENT_ID", null),
                    envOr("STARFLEET_CLIENT_SECRET", null));
        }
    
        /**
         * Returns a deadline the given number of seconds from now, on a clock
         * that only moves forwards.
         */
        static long deadline(int seconds) {
            return System.nanoTime() + TimeUnit.SECONDS.toNanos(seconds);
        }
    
        /** Reports whether a deadline is still in the future. */
        static boolean before(long deadline) {
            return System.nanoTime() - deadline < 0;
        }
    
        /**
         * Guards the state that the clean-up uses, which the main thread and
         * the shutdown hook share (see main).
         */
        static final Object LOCK = new Object();
    
        /** Set by the shutdown hook when SIGINT or SIGTERM arrives. */
        static volatile boolean interrupted;
    
        /**
         * Throws InterruptedException once a signal has arrived, so that the
         * main thread stops making requests. A thread that holds the lock is
         * either creating the database or cleaning up, and both of those must
         * run to the end.
         */
        static void checkInterrupted() throws InterruptedException {
            if (interrupted && !Thread.holdsLock(LOCK)) {
                throw new InterruptedException("interrupted");
            }
        }
    
        /** Waits for the given number of seconds, watching for a signal. */
        static void pause(int seconds) throws InterruptedException {
            long end = deadline(seconds);
            while (before(end)) {
                checkInterrupted();
                Thread.sleep(200);
            }
        }
    
        /** One client serves every request; it is safe to share. */
        static final HttpClient CLIENT = HttpClient.newBuilder()
                .connectTimeout(Duration.ofSeconds(30))
                .build();
    
        /** Converts between JSON text and Java objects. */
        static final ObjectMapper JSON = new ObjectMapper();
    
        /** An error reply from the API, with its HTTP status. */
        static class ApiException extends IOException {
            final int status;
    
            ApiException(int status, String message) {
                super(message);
                this.status = status;
            }
        }
    
        /**
         * Sends a request and returns the response with its whole body. The
         * request timeout stops applying once the headers arrive, so a server
         * that stalls part of the way through the body would hang send(); this
         * applies the same timeout to the whole exchange instead.
         */
        static HttpResponse<String> send(HttpRequest request)
                throws IOException, InterruptedException {
            Duration timeout = request.timeout().orElseThrow();
            CompletableFuture<HttpResponse<String>> pending =
                    CLIENT.sendAsync(request, HttpResponse.BodyHandlers.ofString());
            try {
                return pending.get(timeout.toMillis(), TimeUnit.MILLISECONDS);
            } catch (TimeoutException e) {
                pending.cancel(true);
                throw new HttpTimeoutException("request timed out");
            } catch (ExecutionException e) {
                if (e.getCause() instanceof IOException cause) {
                    throw cause;
                }
                throw new IOException(e.getCause());
            }
        }
    
        /**
         * Sends a request with a JSON body, if there is one, and returns the
         * decoded JSON reply, or null if the reply has no body. A 4xx or 5xx
         * reply throws an ApiException.
         */
        static JsonNode request(String method, String url, String path,
                String token, Object body) throws IOException, InterruptedException {
            checkInterrupted();
            HttpRequest.Builder request = HttpRequest.newBuilder(URI.create(url))
                    .timeout(Duration.ofSeconds(30));
            if (token != null) {
                request.header("Authorization", "Bearer " + token);
            }
            HttpRequest.BodyPublisher content = HttpRequest.BodyPublishers.noBody();
            if (body != null) {
                request.header("Content-Type", "application/json");
                content = HttpRequest.BodyPublishers.ofString(
                        JSON.writeValueAsString(body));
            }
    
            HttpResponse<String> response = send(request.method(method, content).build());
            if (response.statusCode() >= 400) {
                throw new ApiException(response.statusCode(), method + " " + path
                        + " failed with status " + response.statusCode() + ": "
                        + response.body().strip());
            }
            String text = response.body();
            return text.isEmpty() ? null : JSON.readTree(text);
        }
    
        /**
         * Returns a field of a JSON object as text, and throws if the field is
         * missing.
         */
        static String field(JsonNode node, String name) {
            JsonNode value = (node == null) ? null : node.get(name);
            if (value == null || value.isNull()) {
                throw new IllegalStateException("the reply has no " + name);
            }
            return value.asString();
        }
    
        /**
         * Exchanges the client ID and secret for an access token, which the
         * Managed API accepts as a bearer token until it expires.
         */
        static String getToken(Settings cfg) throws IOException, InterruptedException {
            if (cfg.clientId() == null || cfg.clientSecret() == null) {
                throw new IllegalStateException(
                        "STARFLEET_CLIENT_ID and STARFLEET_CLIENT_SECRET must be set");
            }
            String path = "/account/v1/oauth/token";
            JsonNode token = request("POST", cfg.baseUrl() + path, path, null, Map.of(
                    "grant_type", "client_credentials",
                    "client_id", cfg.clientId(),
                    "client_secret", cfg.clientSecret()));
            return field(token, "access_token");
        }
    
        /**
         * Sends an authenticated request to the Managed API and returns the
         * decoded JSON reply, or null if the reply has no body.
         */
        static JsonNode api(Settings cfg, String token, String method, String path,
                Object body) throws IOException, InterruptedException {
            return request(method, cfg.baseUrl() + "/managed/v1" + path, path,
                    token, body);
        }
    
        /** The region and size of a new database. */
        record Placement(String region, String size) {}
    
        /**
         * Returns the region and size for the new database. The API lists sizes
         * smallest first, so the first one is the cheapest. The API does not
         * price regions, so the example takes the first one.
         */
        static Placement choosePlacement(Settings cfg, String token)
                throws IOException, InterruptedException {
            JsonNode regions = api(cfg, token, "GET", "/regions", null);
            JsonNode sizes = api(cfg, token, "GET", "/sizes", null);
            if (regions == null || sizes == null || regions.size() == 0
                    || sizes.size() == 0) {
                throw new IllegalStateException("the API offers no region or size");
            }
            return new Placement(field(regions.get(0), "region"),
                    field(sizes.get(0), "name"));
        }
    
        /** Returns the address that the API sees requests come from. */
        static String clientIp(Settings cfg, String token)
                throws IOException, InterruptedException {
            // A new database is closed to everyone until an allowlist rule
            // admits an address. The API reports the address it sees this
            // request come from, which is the one to admit; a bare address
            // means a single host.
            return field(api(cfg, token, "GET", "/client-ip", null), "ip_address");
        }
    
        /**
         * Creates a database that only this machine can reach, and returns the
         * API's description of it, which includes its ID.
         */
        static JsonNode createDatabase(Settings cfg, String token, String name,
                String displayName, Placement placement, String ip)
                throws IOException, InterruptedException {
            return api(cfg, token, "POST", "/databases", Map.of(
                    // The name becomes the Postgres database name, so it holds
                    // only letters and digits, and the readable cookbook- prefix
                    // goes in the display name. The program also uses the name
                    // to find the database again if the reply to this request
                    // is lost.
                    "name", name,
                    "display_name", displayName,
                    "region", placement.region(),
                    "size", placement.size(),
                    "ip_allowlist", Map.of("rules", List.of(
                            Map.of("cidr", ip, "label", "cookbook")))));
        }
    
        /**
         * The API does not document its status values; the example treats
         * these two as failures, which end the wait at once instead of leaving
         * it to run until the time limit.
         */
        static final Set<String> FAILED_STATUSES = Set.of("degraded", "failed");
    
        /** Polls the database until its status is available. */
        static void waitUntilAvailable(Settings cfg, String token, String databaseId)
                throws IOException, InterruptedException {
            long deadline = deadline(TIMEOUT_SECONDS);
            String last = null;
            while (before(deadline)) {
                String status = field(
                        api(cfg, token, "GET", "/databases/" + databaseId, null),
                        "status");
                if (!status.equals(last)) {
                    System.out.println("Database status: " + status);
                    last = status;
                }
                if (status.equals("available")) {
                    return;
                }
                if (FAILED_STATUSES.contains(status)) {
                    throw new IllegalStateException(
                            "the database has the status " + status);
                }
                pause(POLL_SECONDS);
            }
            throw new IllegalStateException("the database was not available after "
                    + TIMEOUT_SECONDS + " seconds");
        }
    
        /**
         * The API does not document its backup status values beyond
         * "completed", which marks a usable backup; the example treats "failed"
         * as a failure, which ends the wait at once instead of leaving it to
         * run until the time limit.
         */
        static final Set<String> FAILED_BACKUP_STATUSES = Set.of("failed");
    
        /** Starts an on-demand backup and returns the pending backup. */
        static JsonNode takeBackup(Settings cfg, String token, String databaseId)
                throws IOException, InterruptedException {
            // The hot kind is a fast local snapshot. The durable kind streams a
            // base backup to object storage, and needs the durable tier to be
            // enabled for the database. The API answers 202 at once and runs
            // the backup in the background.
            return api(cfg, token, "POST", "/databases/" + databaseId + "/backup",
                    Map.of("kind", "hot"));
        }
    
        /** Polls the backup until its status is completed. */
        static void waitForBackup(Settings cfg, String token, String backupId)
                throws IOException, InterruptedException {
            long deadline = deadline(TIMEOUT_SECONDS);
            String last = null;
            while (before(deadline)) {
                String status = field(
                        api(cfg, token, "GET", "/backups/" + backupId, null), "status");
                if (!status.equals(last)) {
                    System.out.println("Backup status: " + status);
                    last = status;
                }
                if (status.equals("completed")) {
                    return;
                }
                if (FAILED_BACKUP_STATUSES.contains(status)) {
                    throw new IllegalStateException(
                            "the backup has the status " + status);
                }
                pause(POLL_SECONDS);
            }
            throw new IllegalStateException("the backup was not completed after "
                    + TIMEOUT_SECONDS + " seconds");
        }
    
        /** Prints the name and status of each task recorded for the database. */
        static void printTasks(Settings cfg, String token, String databaseId)
                throws IOException, InterruptedException {
            // Managed database operations record their progress as tasks, with
            // the kind "database" and the database ID as the subject.
            JsonNode tasks = api(cfg, token, "GET",
                    "/tasks?subject_kind=database&subject_id=" + databaseId, null);
            if (tasks != null) {
                for (JsonNode task : tasks) {
                    System.out.println("Task: " + field(task, "name") + " ("
                            + field(task, "status") + ")");
                }
            }
        }
    
        /**
         * Reports whether the API still lists a backup once its database has
         * been deleted. The API specification gives no rule for this, so the
         * example only observes it.
         */
        static String backupAfterDelete(Settings cfg, String token, String backupId)
                throws InterruptedException {
            String prefix = "Backup after the database was deleted:";
            try {
                api(cfg, token, "GET", "/backups/" + backupId, null);
                return prefix + " still listed";
            } catch (ApiException e) {
                return prefix + (e.status == 404 ? " gone" : " unknown");
            } catch (IOException e) {
                return prefix + " unknown";
            }
        }
    
        /**
         * Reports whether a failed request is worth repeating: no reply arrived,
         * the service is overloaded or failing, or it answered 409, which the
         * API does whilst a database is still being created. Any IOException
         * other than an ApiException means that no reply arrived, such as a
         * refused connection or a timeout.
         */
        static boolean isTransient(Exception e) {
            if (e instanceof ApiException api) {
                return api.status == 409 || api.status == 429 || api.status >= 500;
            }
            return e instanceof IOException;
        }
    
        /**
         * Reports whether an error is a 404 reply, which means that the database
         * does not exist.
         */
        static boolean isGone(Exception e) {
            return e instanceof ApiException api && api.status == 404;
        }
    
        /**
         * Returns the ID of the database with the given name, or null. The
         * program uses this when it cannot tell whether a create request worked.
         * It repeats the request, as the delete does, because the fault that
         * lost the reply to the create request may still be there. The request
         * asks for the newest databases first, but the API does not say which
         * property it sorts on.
         */
        static String findDatabase(Settings cfg, String token, String name)
                throws IOException, InterruptedException {
            long deadline = deadline(TIMEOUT_SECONDS);
            JsonNode databases;
            while (true) {
                try {
                    databases = api(cfg, token, "GET",
                            "/databases?limit=100&descending=true", null);
                    break;
                } catch (IOException e) {
                    if (!isTransient(e) || !before(deadline)) {
                        throw e;
                    }
                    pause(POLL_SECONDS);
                }
            }
            if (databases != null) {
                for (JsonNode database : databases) {
                    if (name.equals(database.path("name").asString())) {
                        return field(database, "id");
                    }
                }
            }
            return null;
        }
    
        /**
         * Looks for the database a few times, because the service may not have
         * recorded a request whose reply was lost until a little later. Returns
         * null if the database never appears.
         */
        static String findCreatedDatabase(Settings cfg, String token, String name)
                throws IOException, InterruptedException {
            for (int attempt = 0; attempt < LOOKUP_ATTEMPTS; attempt++) {
                String databaseId = findDatabase(cfg, token, name);
                if (databaseId != null) {
                    return databaseId;
                }
                if (attempt < LOOKUP_ATTEMPTS - 1) {
                    pause(POLL_SECONDS);
                }
            }
            return null;
        }
    
        /**
         * Reports whether a failed create request might still have created the
         * database: no reply arrived, the reply could not be read, or the
         * service failed with a 5xx status. A 4xx reply is a definite refusal.
         */
        static boolean outcomeUnknown(Exception e) {
            if (e instanceof ApiException api) {
                return api.status >= 500;
            }
            return true;
        }
    
        /** Deletes the database and waits until the API no longer lists it. */
        static void deleteDatabase(Settings cfg, String token, String databaseId)
                throws IOException, InterruptedException {
            long deadline = deadline(TIMEOUT_SECONDS);
            while (true) {
                try {
                    api(cfg, token, "DELETE", "/databases/" + databaseId, null);
                    break;
                } catch (IOException e) {
                    if (isGone(e)) {
                        return;
                    }
                    if (!isTransient(e) || !before(deadline)) {
                        throw e;
                    }
                    pause(POLL_SECONDS);
                }
            }
    
            // The delete starts the teardown; a 404 shows that it has finished.
            while (before(deadline)) {
                try {
                    api(cfg, token, "GET", "/databases/" + databaseId, null);
                } catch (IOException e) {
                    if (isGone(e)) {
                        return;
                    }
                    if (!isTransient(e)) {
                        throw e;
                    }
                }
                pause(POLL_SECONDS);
            }
            throw new IllegalStateException("the database was still present after "
                    + TIMEOUT_SECONDS + " seconds");
        }
    
        // What the clean-up needs to know, guarded by LOCK.
        static Settings cfg;
        static String token;
        static String name;
        static String databaseId;
        static boolean lookup;
        static String backupId;
        /** The exit status, once the clean-up has run. */
        static Integer result;
        /** Set once the clean-up has started. */
        static volatile boolean cleaning;
        /** Set once the main thread has finished, clean-up included. */
        static volatile boolean exiting;
    
        /**
         * Returns the message of an error. Some errors, such as a refused
         * connection, have no message, so their type stands in for one.
         */
        static String describe(Exception e) {
            return Objects.requireNonNullElse(e.getMessage(), e.toString());
        }
    
        /**
         * Deletes the database, if the program created one, and returns the
         * exit status. The main thread and the shutdown hook both call this,
         * and whichever comes first does the work; the other waits for it and
         * gets the same status.
         */
        static int cleanUp(int status) {
            synchronized (LOCK) {
                if (result != null) {
                    return result;
                }
                cleaning = true;
                if (token != null && name != null) {
                    try {
                        if (databaseId == null && lookup) {
                            databaseId = findCreatedDatabase(cfg, token, name);
                            if (databaseId == null) {
                                System.err.println("Error: the database " + name
                                        + " was not found; check your account for"
                                        + " it by hand");
                                status = 1;
                            }
                        }
                        if (databaseId != null) {
                            deleteDatabase(cfg, token, databaseId);
                            System.out.println("Deleted database");
                            if (backupId != null) {
                                System.out.println(backupAfterDelete(cfg, token, backupId));
                            }
                        }
                    } catch (IOException | InterruptedException | JacksonException
                            | IllegalStateException e) {
                        System.err.println("Error: " + describe(e));
                        System.err.println("Delete the database "
                                + (databaseId != null ? databaseId : name)
                                + " by hand, because it may still be billing");
                        status = 1;
                    }
                }
                result = status;
                return status;
            }
        }
    
        public static void main(String[] args) {
            // Java cannot catch a signal with its supported API, but SIGINT and
            // SIGTERM start an orderly shutdown that runs this hook. The hook
            // stops the main thread's requests, deletes the database (or waits
            // for the main thread to finish doing so), and ends the program
            // with the status of the clean-up. A normal exit runs the hook too,
            // after the main thread has cleaned up.
            Runtime.getRuntime().addShutdownHook(new Thread(() -> {
                if (!exiting) {
                    interrupted = true;
                    if (!cleaning) {
                        System.err.println("Interrupted");
                    }
                }
                int status = cleanUp(130);
                System.out.flush();
                Runtime.getRuntime().halt(status);
            }));
    
            // The status stays 1 unless every step succeeds, so that an
            // unexpected error, which the catch does not handle, still ends
            // the program with a failure.
            int status = 1;
            try {
                cfg = settings();
                String bearer = getToken(cfg);
                synchronized (LOCK) {
                    token = bearer;
                }
    
                Placement placement = choosePlacement(cfg, bearer);
                System.out.println("Region: " + placement.region());
                System.out.println("Size: " + placement.size());
    
                // Choose the name before the request, so that the program can
                // find the database even if the reply to the request never
                // arrives.
                byte[] random = new byte[3];
                new SecureRandom().nextBytes(random);
                String suffix = HexFormat.of().formatHex(random);
                String displayName = "cookbook-" + suffix;
                String ip = clientIp(cfg, bearer);
                JsonNode database;
                // Hold the lock until the ID is recorded, so that a signal
                // during the create call cannot leave the database behind.
                synchronized (LOCK) {
                    name = "cookbook" + suffix;
                    // Look the database up by name afterwards only if the
                    // outcome of the request is unknown, so that a refusal
                    // cannot lead the clean-up to delete another database that
                    // has the same name.
                    lookup = true;
                    try {
                        database = createDatabase(cfg, bearer, name, displayName,
                                placement, ip);
                    } catch (IOException | JacksonException e) {
                        lookup = outcomeUnknown(e);
                        throw e;
                    }
                    databaseId = field(database, "id");
                }
                System.out.println("Created database " + field(database, "display_name"));
    
                waitUntilAvailable(cfg, bearer, databaseId);
                System.out.println("Database is available");
    
                String backup = field(takeBackup(cfg, bearer, databaseId), "id");
                synchronized (LOCK) {
                    backupId = backup;
                }
                System.out.println("Backup started");
                waitForBackup(cfg, bearer, backup);
                printTasks(cfg, bearer, databaseId);
                status = 0;
            // IOException covers failures to connect and error replies from the
            // API; InterruptedException means that a signal arrived, which the
            // shutdown hook reports; Jackson throws JacksonException for a
            // reply that is not JSON; and IllegalStateException covers replies
            // that the program cannot use.
            } catch (IOException | InterruptedException | JacksonException
                    | IllegalStateException e) {
                if (!interrupted) {
                    System.err.println("Error: " + describe(e));
                }
            } finally {
                // Delete the database whether the example succeeded, failed, or
                // was interrupted, because the service bills for it until then.
                // The finally block also runs for an error that the catch does
                // not handle.
                status = cleanUp(interrupted ? 130 : status);
            }
            exiting = true;
            System.exit(status);
        }
    }
    
    ```

=== "C#"

    ```csharp
    /*
     * Ellie's Postgres Cookbook
     * Taking an on-demand backup of a pgEdge Starfleet database, and tracking it
     * until it completes, using HttpClient and System.Text.Json.
     *
     * The program creates a database of its own to back up. The Starfleet
     * service bills for every database from the moment that it becomes
     * connectable, so the program deletes the database on every path: after a
     * success, after a failure, and after Ctrl-C.
     *
     * Copyright (c) 2026, pgEdge, Inc.
     * This code is released under the PostgreSQL License.
     */
    
    using System.Net;
    using System.Net.Http.Headers;
    using System.Runtime.InteropServices;
    using System.Security.Cryptography;
    using System.Text;
    using System.Text.Json;
    using System.Text.Json.Nodes;
    
    // How long to wait for a database to become available, or to disappear
    // after a delete, and how often to check.
    const int TimeoutSeconds = 900;
    const int PollSeconds = 10;
    
    // How many times to look for a database whose create reply was lost.
    const int LookupAttempts = 3;
    
    // Returns the value of an environment variable, or null if the variable
    // is unset or empty, as an unset variable would be.
    static string? EnvValue(string name) =>
        Environment.GetEnvironmentVariable(name) is { Length: > 0 } value
            ? value
            : null;
    
    // Reads the API settings from the environment. The client ID and secret
    // have no defaults, so a missing value becomes null, and the token request
    // reports it.
    static (string BaseUrl, string? ClientId, string? ClientSecret) Settings() =>
        ((EnvValue("STARFLEET_API_URL") ?? "https://api.pgedge.com").TrimEnd('/'),
            EnvValue("STARFLEET_CLIENT_ID"),
            EnvValue("STARFLEET_CLIENT_SECRET"));
    
    var cfg = Settings();
    
    // Returns a deadline the given number of seconds from now, and reports
    // whether it is still in the future, on a clock that only moves forwards.
    static long Deadline(int seconds) => Environment.TickCount64 + seconds * 1000L;
    static bool Before(long deadline) => Environment.TickCount64 < deadline;
    
    // A token that SIGINT or SIGTERM cancels, which abandons the request or
    // the wait in progress. The clean-up replaces it with CancellationToken.None,
    // so that nothing can cut the clean-up short.
    using var signalled = new CancellationTokenSource();
    var cancel = signalled.Token;
    
    // Catches SIGINT and SIGTERM. Setting Cancel stops the default action,
    // which would end the program before it could delete the database, and a
    // second signal does nothing more.
    void OnSignal(PosixSignalContext context)
    {
        context.Cancel = true;
        signalled.Cancel();
    }
    using var onInt = PosixSignalRegistration.Create(PosixSignal.SIGINT, OnSignal);
    using var onTerm = PosixSignalRegistration.Create(PosixSignal.SIGTERM, OnSignal);
    
    // Waits for the given number of seconds; a signal ends the wait early.
    async Task Pause(int seconds) =>
        await Task.Delay(TimeSpan.FromSeconds(seconds), cancel);
    
    // One client serves every request. Its timeout covers the whole exchange,
    // the body of the reply included.
    var http = new HttpClient { Timeout = TimeSpan.FromSeconds(30) };
    
    // Sends a request with a JSON body, if there is one, and returns the
    // decoded JSON reply, or null if the reply has no body. A 4xx or 5xx reply
    // throws an HttpRequestException that carries the status.
    async Task<JsonNode?> Request(string method, string url, string path,
        string? token, object? body, CancellationToken cancelRequest)
    {
        using var request = new HttpRequestMessage(new HttpMethod(method), url);
        if (token is not null)
        {
            request.Headers.Authorization =
                new AuthenticationHeaderValue("Bearer", token);
        }
        if (body is not null)
        {
            // StringContent sends a Content-Length header; JsonContent would
            // stream the body in chunks, which not every server accepts.
            request.Content = new StringContent(
                JsonSerializer.Serialize(body), Encoding.UTF8, "application/json");
        }
    
        using var response = await http.SendAsync(request, cancelRequest);
        var text = await response.Content.ReadAsStringAsync(cancelRequest);
        if ((int)response.StatusCode >= 400)
        {
            throw new HttpRequestException(
                $"{method} {path} failed with status {(int)response.StatusCode}: "
                + text.Trim(), null, response.StatusCode);
        }
        return text.Length == 0 ? null : JsonNode.Parse(text);
    }
    
    // Returns a field of a JSON object as text, and throws if the field is
    // missing.
    static string Field(JsonNode? node, string name) =>
        node?[name] is JsonNode value
            ? value.ToString()
            : throw new InvalidOperationException($"the reply has no {name}");
    
    // Exchanges the client ID and secret for an access token, which the
    // Managed API accepts as a bearer token until it expires.
    async Task<string> GetToken()
    {
        if (cfg.ClientId is null || cfg.ClientSecret is null)
        {
            throw new InvalidOperationException(
                "STARFLEET_CLIENT_ID and STARFLEET_CLIENT_SECRET must be set");
        }
        const string path = "/account/v1/oauth/token";
        var token = await Request("POST", cfg.BaseUrl + path, path, null, new
        {
            grant_type = "client_credentials",
            client_id = cfg.ClientId,
            client_secret = cfg.ClientSecret,
        }, cancel);
        return Field(token, "access_token");
    }
    
    // Sends an authenticated request to the Managed API and returns the
    // decoded JSON reply, or null if the reply has no body. The create call
    // passes interruptible: false, so that a signal cannot abandon a request
    // whose result the program must not lose.
    async Task<JsonNode?> Api(string token, string method, string path,
        object? body = null, bool interruptible = true) =>
        await Request(method, $"{cfg.BaseUrl}/managed/v1{path}", path, token,
            body, interruptible ? cancel : CancellationToken.None);
    
    // Returns the region and size for the new database. The API lists sizes
    // smallest first, so the first one is the cheapest. The API does not price
    // regions, so the example takes the first one.
    async Task<(string Region, string Size)> ChoosePlacement(string token)
    {
        var regions = await Api(token, "GET", "/regions") as JsonArray;
        var sizes = await Api(token, "GET", "/sizes") as JsonArray;
        if (regions is not { Count: > 0 } || sizes is not { Count: > 0 })
        {
            throw new InvalidOperationException("the API offers no region or size");
        }
        return (Field(regions[0], "region"), Field(sizes[0], "name"));
    }
    
    // Returns the address that the API sees requests come from.
    async Task<string> ClientIp(string token)
    {
        // A new database is closed to everyone until an allowlist rule admits
        // an address. The API reports the address it sees this request come
        // from, which is the one to admit; a bare address means a single host.
        return Field(await Api(token, "GET", "/client-ip"), "ip_address");
    }
    
    // Creates a database that only this machine can reach, and returns the
    // API's description of it, which includes its ID.
    async Task<JsonNode?> CreateDatabase(string token, string name,
        string displayName, string region, string size, string ip) =>
        await Api(token, "POST", "/databases", new
        {
            // The name becomes the Postgres database name, so it holds only
            // letters and digits, and the readable cookbook- prefix goes in the
            // display name. The program also uses the name to find the
            // database again if the reply to this request is lost.
            name,
            display_name = displayName,
            region,
            size,
            ip_allowlist = new
            {
                rules = new[] { new { cidr = ip, label = "cookbook" } },
            },
        }, interruptible: false);
    
    // The API does not document its status values; the example treats these
    // two as failures, which end the wait at once instead of leaving it to run
    // until the time limit.
    string[] failedStatuses = ["degraded", "failed"];
    
    // Polls the database until its status is available.
    async Task WaitUntilAvailable(string token, string databaseId)
    {
        var deadline = Deadline(TimeoutSeconds);
        string? last = null;
        while (Before(deadline))
        {
            var status = Field(
                await Api(token, "GET", $"/databases/{databaseId}"), "status");
            if (status != last)
            {
                Console.WriteLine($"Database status: {status}");
                last = status;
            }
            if (status == "available")
            {
                return;
            }
            if (failedStatuses.Contains(status))
            {
                throw new InvalidOperationException(
                    $"the database has the status {status}");
            }
            await Pause(PollSeconds);
        }
        throw new InvalidOperationException(
            $"the database was not available after {TimeoutSeconds} seconds");
    }
    
    // The API does not document its backup status values beyond "completed",
    // which marks a usable backup; the example treats "failed" as a failure,
    // which ends the wait at once instead of leaving it to run until the time
    // limit.
    string[] failedBackupStatuses = ["failed"];
    
    // Starts an on-demand backup and returns the pending backup.
    async Task<JsonNode?> TakeBackup(string token, string databaseId)
    {
        // The hot kind is a fast local snapshot. The durable kind streams a base
        // backup to object storage, and needs the durable tier to be enabled for
        // the database. The API answers 202 at once and runs the backup in the
        // background.
        return await Api(token, "POST", $"/databases/{databaseId}/backup",
            new { kind = "hot" });
    }
    
    // Polls the backup until its status is completed.
    async Task WaitForBackup(string token, string backupId)
    {
        var deadline = Deadline(TimeoutSeconds);
        string? last = null;
        while (Before(deadline))
        {
            var status = Field(
                await Api(token, "GET", $"/backups/{backupId}"), "status");
            if (status != last)
            {
                Console.WriteLine($"Backup status: {status}");
                last = status;
            }
            if (status == "completed")
            {
                return;
            }
            if (failedBackupStatuses.Contains(status))
            {
                throw new InvalidOperationException(
                    $"the backup has the status {status}");
            }
            await Pause(PollSeconds);
        }
        throw new InvalidOperationException(
            $"the backup was not completed after {TimeoutSeconds} seconds");
    }
    
    // Prints the name and status of each task recorded for the database.
    async Task PrintTasks(string token, string databaseId)
    {
        // Managed database operations record their progress as tasks, with the
        // kind "database" and the database ID as the subject.
        var tasks = await Api(token, "GET",
            $"/tasks?subject_kind=database&subject_id={databaseId}");
        foreach (var task in tasks as JsonArray ?? [])
        {
            Console.WriteLine($"Task: {Field(task, "name")} ({Field(task, "status")})");
        }
    }
    
    // Reports whether the API still lists a backup once its database has been
    // deleted. The API specification gives no rule for this, so the example
    // only observes it.
    async Task<string> BackupAfterDelete(string token, string backupId)
    {
        const string prefix = "Backup after the database was deleted:";
        try
        {
            await Api(token, "GET", $"/backups/{backupId}");
            return $"{prefix} still listed";
        }
        catch (HttpRequestException e)
        {
            return $"{prefix} "
                + (e.StatusCode == HttpStatusCode.NotFound ? "gone" : "unknown");
        }
        catch (TaskCanceledException)
        {
            return $"{prefix} unknown";
        }
    }
    
    // Reports whether a failed request is worth repeating: no reply arrived,
    // such as a refused connection or a timeout, the service is overloaded or
    // failing, or it answered 409, which the API does whilst a database is
    // still being created.
    static bool IsTransient(Exception e) => e switch
    {
        HttpRequestException { StatusCode: HttpStatusCode code } =>
            (int)code is 409 or 429 or >= 500,
        HttpRequestException or TaskCanceledException => true,
        _ => false,
    };
    
    // Reports whether an error is a 404 reply, which means that the database
    // does not exist.
    static bool IsGone(Exception e) =>
        e is HttpRequestException { StatusCode: HttpStatusCode.NotFound };
    
    // Returns the ID of the database with the given name, or null. The program
    // uses this when it cannot tell whether a create request worked. It
    // repeats the request, as the delete does, because the fault that lost the
    // reply to the create request may still be there. The request asks for
    // the newest databases first, but the API does not say which property it
    // sorts on.
    async Task<string?> FindDatabase(string token, string name)
    {
        var deadline = Deadline(TimeoutSeconds);
        JsonNode? databases;
        while (true)
        {
            try
            {
                databases = await Api(
                    token, "GET", "/databases?limit=100&descending=true");
                break;
            }
            catch (Exception e) when (IsTransient(e) && Before(deadline))
            {
                await Pause(PollSeconds);
            }
        }
        foreach (var database in databases as JsonArray ?? [])
        {
            if (database?["name"]?.ToString() == name)
            {
                return Field(database, "id");
            }
        }
        return null;
    }
    
    // Looks for the database a few times, because the service may not have
    // recorded a request whose reply was lost until a little later. Returns
    // null if the database never appears.
    async Task<string?> FindCreatedDatabase(string token, string name)
    {
        for (var attempt = 0; attempt < LookupAttempts; attempt++)
        {
            if (await FindDatabase(token, name) is string databaseId)
            {
                return databaseId;
            }
            if (attempt < LookupAttempts - 1)
            {
                await Pause(PollSeconds);
            }
        }
        return null;
    }
    
    // Reports whether a failed create request might still have created the
    // database: no reply arrived, the reply could not be read, or the service
    // failed with a 5xx status. A 4xx reply is a definite refusal.
    static bool OutcomeUnknown(Exception e) =>
        e is not HttpRequestException { StatusCode: HttpStatusCode code }
            || (int)code >= 500;
    
    // Deletes the database and waits until the API no longer lists it.
    async Task DeleteDatabase(string token, string databaseId)
    {
        var deadline = Deadline(TimeoutSeconds);
        while (true)
        {
            try
            {
                await Api(token, "DELETE", $"/databases/{databaseId}");
                break;
            }
            catch (Exception e) when (IsGone(e))
            {
                return;
            }
            catch (Exception e) when (IsTransient(e) && Before(deadline))
            {
                await Pause(PollSeconds);
            }
        }
    
        // The delete starts the teardown; a 404 shows that it has finished.
        while (Before(deadline))
        {
            try
            {
                await Api(token, "GET", $"/databases/{databaseId}");
            }
            catch (Exception e) when (IsGone(e))
            {
                return;
            }
            catch (Exception e) when (IsTransient(e))
            {
            }
            await Pause(PollSeconds);
        }
        throw new InvalidOperationException(
            $"the database was still present after {TimeoutSeconds} seconds");
    }
    
    // Reports whether an error is one that the program expects: a failure to
    // connect, an error reply from the API, a request that timed out, a reply
    // that is not JSON, or a reply that the program cannot use.
    static bool Expected(Exception e) => e is HttpRequestException
        or TaskCanceledException or JsonException or InvalidOperationException;
    
    string? token = null;
    string? name = null;
    string? databaseId = null;
    var lookup = false;
    string? backupId = null;
    var exitCode = 0;
    try
    {
        token = await GetToken();
    
        var (region, size) = await ChoosePlacement(token);
        Console.WriteLine($"Region: {region}");
        Console.WriteLine($"Size: {size}");
    
        // Choose the name before the request, so that the program can find the
        // database even if the reply to the request never arrives.
        var suffix = Convert.ToHexStringLower(RandomNumberGenerator.GetBytes(3));
        name = $"cookbook{suffix}";
        var displayName = $"cookbook-{suffix}";
        // Look the database up by name afterwards only if the outcome of the
        // request is unknown, so that a refusal cannot lead the clean-up to
        // delete another database that has the same name.
        var ip = await ClientIp(token);
        lookup = true;
        JsonNode? database;
        try
        {
            database = await CreateDatabase(token, name, displayName, region, size, ip);
        }
        catch (Exception e) when (Expected(e))
        {
            lookup = OutcomeUnknown(e);
            throw;
        }
        databaseId = Field(database, "id");
        Console.WriteLine($"Created database {Field(database, "display_name")}");
    
        await WaitUntilAvailable(token, databaseId);
        Console.WriteLine("Database is available");
    
        backupId = Field(await TakeBackup(token, databaseId), "id");
        Console.WriteLine("Backup started");
        await WaitForBackup(token, backupId);
        await PrintTasks(token, databaseId);
    }
    // After a signal, the request or wait in progress fails, whatever the
    // error that it reports.
    catch (Exception) when (signalled.IsCancellationRequested)
    {
        Console.Error.WriteLine("Interrupted");
        exitCode = 130;
    }
    catch (Exception e) when (Expected(e))
    {
        Console.Error.WriteLine($"Error: {e.Message}");
        exitCode = 1;
    }
    finally
    {
        // Delete the database whether the example succeeded, failed, or was
        // interrupted, because the service bills for it until then. Signals
        // no longer cancel anything, so that they cannot cut the clean-up
        // short. The finally block also runs for an error that the catch does
        // not handle.
        cancel = CancellationToken.None;
        if (token is not null && name is not null)
        {
            try
            {
                if (databaseId is null && lookup)
                {
                    databaseId = await FindCreatedDatabase(token, name);
                    if (databaseId is null)
                    {
                        Console.Error.WriteLine(
                            $"Error: the database {name} was not found; "
                            + "check your account for it by hand");
                        exitCode = 1;
                    }
                }
                if (databaseId is not null)
                {
                    await DeleteDatabase(token, databaseId);
                    Console.WriteLine("Deleted database");
                    if (backupId is not null)
                    {
                        Console.WriteLine(await BackupAfterDelete(token, backupId));
                    }
                }
            }
            catch (Exception e) when (Expected(e))
            {
                Console.Error.WriteLine($"Error: {e.Message}");
                Console.Error.WriteLine(
                    $"Delete the database {databaseId ?? name} by hand, "
                    + "because it may still be billing");
                exitCode = 1;
            }
        }
    }
    
    return exitCode;
    
    ```

=== "Go"

    ```go
    // Ellie's Postgres Cookbook
    // Taking an on-demand backup of a pgEdge Starfleet database, and tracking
    // it until it completes, using the net/http package.
    //
    // The program creates a database of its own to back up. The Starfleet
    // service bills for every database from the moment that it becomes
    // connectable, so the program deletes the database on every path: after a
    // success, after a failure, and after Ctrl-C.
    //
    // Copyright (c) 2026, pgEdge, Inc.
    // This code is released under the PostgreSQL License.
    
    package main
    
    import (
    	"bytes"
    	"context"
    	"crypto/rand"
    	"encoding/hex"
    	"encoding/json"
    	"errors"
    	"fmt"
    	"io"
    	"net/http"
    	"os"
    	"os/signal"
    	"strings"
    	"syscall"
    	"time"
    )
    
    
    const (
    	// How long to wait for a database to become available, or to
    	// disappear after a delete, and how often to check.
    	timeout      = 15 * time.Minute
    	pollInterval = 10 * time.Second
    
    	// How many times to look for a database whose create reply was lost.
    	lookupAttempts = 3
    )
    
    // envOr returns the value of an environment variable, or a fallback if
    // the variable is unset or empty.
    func envOr(name, fallback string) string {
    	if value := os.Getenv(name); value != "" {
    		return value
    	}
    	return fallback
    }
    
    // baseURL is the root of the Starfleet API, without a trailing slash.
    func baseURL() string {
    	return strings.TrimRight(envOr("STARFLEET_API_URL", "https://api.pgedge.com"), "/")
    }
    
    // httpClient gives every request a timeout; the default client has none.
    var httpClient = &http.Client{Timeout: 30 * time.Second}
    
    
    // getToken exchanges the client ID and secret for an access token, which
    // the Managed API accepts as a bearer token until it expires.
    func getToken(ctx context.Context) (string, error) {
    	clientID := os.Getenv("STARFLEET_CLIENT_ID")
    	clientSecret := os.Getenv("STARFLEET_CLIENT_SECRET")
    	if clientID == "" || clientSecret == "" {
    		return "", errors.New("STARFLEET_CLIENT_ID and STARFLEET_CLIENT_SECRET must be set")
    	}
    
    	body, err := json.Marshal(map[string]string{
    		"grant_type":    "client_credentials",
    		"client_id":     clientID,
    		"client_secret": clientSecret,
    	})
    	if err != nil {
    		return "", err
    	}
    
    	req, err := http.NewRequestWithContext(ctx, http.MethodPost,
    		baseURL()+"/account/v1/oauth/token", bytes.NewReader(body))
    	if err != nil {
    		return "", err
    	}
    	req.Header.Set("Content-Type", "application/json")
    
    	resp, err := httpClient.Do(req)
    	if err != nil {
    		return "", fmt.Errorf("token request failed: %w", err)
    	}
    	defer resp.Body.Close()
    
    	// A non-2xx status is not a Go error, so check it explicitly.
    	if resp.StatusCode != http.StatusOK {
    		detail, _ := io.ReadAll(io.LimitReader(resp.Body, 1024))
    		return "", fmt.Errorf("token request failed: %s %s", resp.Status, detail)
    	}
    
    	var token struct {
    		AccessToken string `json:"access_token"`
    	}
    	if err := json.NewDecoder(resp.Body).Decode(&token); err != nil {
    		return "", fmt.Errorf("decoding the token response: %w", err)
    	}
    	return token.AccessToken, nil
    }
    
    
    // APIError is an error reply from the Managed API, with its HTTP status.
    type APIError struct {
    	Status  int
    	Message string
    }
    
    func (e *APIError) Error() string { return e.Message }
    
    // api sends an authenticated request to the Managed API. It encodes body
    // as JSON if it is not nil, and decodes the reply into result if that is
    // not nil and the reply has content.
    func api(ctx context.Context, token, method, path string, body, result any) error {
    	var reader io.Reader
    	if body != nil {
    		encoded, err := json.Marshal(body)
    		if err != nil {
    			return err
    		}
    		reader = bytes.NewReader(encoded)
    	}
    
    	req, err := http.NewRequestWithContext(ctx, method, baseURL()+"/managed/v1"+path, reader)
    	if err != nil {
    		return err
    	}
    	req.Header.Set("Authorization", "Bearer "+token)
    	if body != nil {
    		req.Header.Set("Content-Type", "application/json")
    	}
    
    	resp, err := httpClient.Do(req)
    	if err != nil {
    		return fmt.Errorf("%s %s failed: %w", method, path, err)
    	}
    	defer resp.Body.Close()
    
    	data, err := io.ReadAll(resp.Body)
    	if err != nil {
    		return err
    	}
    	if resp.StatusCode >= 300 {
    		return &APIError{
    			Status:  resp.StatusCode,
    			Message: fmt.Sprintf("%s %s failed: %s %s", method, path, resp.Status, data),
    		}
    	}
    	if result == nil || len(data) == 0 {
    		return nil
    	}
    	return json.Unmarshal(data, result)
    }
    
    // sleep waits for the interval, or until the context ends.
    func sleep(ctx context.Context) error {
    	select {
    	case <-time.After(pollInterval):
    		return nil
    	case <-ctx.Done():
    		return ctx.Err()
    	}
    }
    
    
    // choosePlacement returns the region and size for the new database. The
    // API lists sizes smallest first, so the first one is the cheapest. The
    // API does not price regions, so the example takes the first one.
    func choosePlacement(ctx context.Context, token string) (region, size string, err error) {
    	var regions []struct {
    		Region string `json:"region"`
    	}
    	var sizes []struct {
    		Name string `json:"name"`
    	}
    	if err = api(ctx, token, http.MethodGet, "/regions", nil, &regions); err != nil {
    		return
    	}
    	if err = api(ctx, token, http.MethodGet, "/sizes", nil, &sizes); err != nil {
    		return
    	}
    	if len(regions) == 0 || len(sizes) == 0 {
    		err = errors.New("the API offers no region or size")
    		return
    	}
    	return regions[0].Region, sizes[0].Name, nil
    }
    
    
    // Database is the part of the API's description of a database that the
    // example uses.
    type Database struct {
    	ID          string `json:"id"`
    	DisplayName string `json:"display_name"`
    	Status      string `json:"status"`
    }
    
    // randomSuffix returns six random hexadecimal digits.
    func randomSuffix() (string, error) {
    	raw := make([]byte, 3)
    	if _, err := rand.Read(raw); err != nil {
    		return "", err
    	}
    	return hex.EncodeToString(raw), nil
    }
    
    // clientIP returns this machine's public IP address as the API sees it.
    func clientIP(ctx context.Context, token string) (string, error) {
    	// A new database is closed to everyone until an allowlist rule admits
    	// an address. The API reports the address it sees this request come
    	// from, which is the one to admit; a bare address means a single host.
    	var ip struct {
    		IPAddress string `json:"ip_address"`
    	}
    	if err := api(ctx, token, http.MethodGet, "/client-ip", nil, &ip); err != nil {
    		return "", err
    	}
    	return ip.IPAddress, nil
    }
    
    // createDatabase creates a database that only this machine can reach,
    // and returns the API's description of it, which includes its ID.
    func createDatabase(ctx context.Context, token, name, displayName, region, size, ip string) (*Database, error) {
    	var database Database
    	err := api(ctx, token, http.MethodPost, "/databases", map[string]any{
    		// The name becomes the Postgres database name, so it holds only
    		// letters and digits, and the readable cookbook- prefix goes in
    		// the display name. The program also uses the name to find the
    		// database again if the reply to this request is lost.
    		"name":         name,
    		"display_name": displayName,
    		"region":       region,
    		"size":         size,
    		"ip_allowlist": map[string]any{
    			"rules": []map[string]string{{"cidr": ip, "label": "cookbook"}},
    		},
    	}, &database)
    	if err != nil {
    		return nil, err
    	}
    	return &database, nil
    }
    
    
    // waitUntilAvailable polls the database until its status is available.
    func waitUntilAvailable(ctx context.Context, token, id string) error {
    	deadline := time.Now().Add(timeout)
    	last := ""
    	for time.Now().Before(deadline) {
    		var database Database
    		if err := api(ctx, token, http.MethodGet, "/databases/"+id, nil, &database); err != nil {
    			return err
    		}
    		if database.Status != last {
    			fmt.Printf("Database status: %s\n", database.Status)
    			last = database.Status
    		}
    		if database.Status == "available" {
    			return nil
    		}
    		// The API does not document its status values; the example
    		// treats these two as failures, which end the wait at once
    		// instead of leaving it to run until the time limit.
    		if database.Status == "degraded" || database.Status == "failed" {
    			return fmt.Errorf("the database has the status %s", database.Status)
    		}
    		if err := sleep(ctx); err != nil {
    			return err
    		}
    	}
    	return fmt.Errorf("the database was not available after %s", timeout)
    }
    
    
    // Backup is the part of the API's description of a backup that the example
    // uses.
    type Backup struct {
    	ID     string `json:"id"`
    	Status string `json:"status"`
    }
    
    // takeBackup starts an on-demand backup and returns the pending backup.
    func takeBackup(ctx context.Context, token, databaseID string) (*Backup, error) {
    	// The hot kind is a fast local snapshot. The durable kind streams a
    	// base backup to object storage, and needs the durable tier to be
    	// enabled for the database. The API answers 202 at once and runs the
    	// backup in the background.
    	var backup Backup
    	err := api(ctx, token, http.MethodPost, "/databases/"+databaseID+"/backup",
    		map[string]string{"kind": "hot"}, &backup)
    	if err != nil {
    		return nil, err
    	}
    	return &backup, nil
    }
    
    // waitForBackup polls the backup until its status is completed.
    func waitForBackup(ctx context.Context, token, id string) error {
    	deadline := time.Now().Add(timeout)
    	last := ""
    	for time.Now().Before(deadline) {
    		var backup Backup
    		if err := api(ctx, token, http.MethodGet, "/backups/"+id, nil, &backup); err != nil {
    			return err
    		}
    		if backup.Status != last {
    			fmt.Printf("Backup status: %s\n", backup.Status)
    			last = backup.Status
    		}
    		if backup.Status == "completed" {
    			return nil
    		}
    		// The API does not document its backup status values beyond
    		// "completed", which marks a usable backup; the example treats
    		// "failed" as a failure, which ends the wait at once instead of
    		// leaving it to run until the time limit.
    		if backup.Status == "failed" {
    			return fmt.Errorf("the backup has the status %s", backup.Status)
    		}
    		if err := sleep(ctx); err != nil {
    			return err
    		}
    	}
    	return fmt.Errorf("the backup was not completed after %s", timeout)
    }
    
    // printTasks prints the name and status of each task recorded for the
    // database.
    func printTasks(ctx context.Context, token, databaseID string) error {
    	// Managed database operations record their progress as tasks, with
    	// the kind "database" and the database ID as the subject.
    	var tasks []struct {
    		Name   string `json:"name"`
    		Status string `json:"status"`
    	}
    	err := api(ctx, token, http.MethodGet,
    		"/tasks?subject_kind=database&subject_id="+databaseID, nil, &tasks)
    	if err != nil {
    		return err
    	}
    	for _, task := range tasks {
    		fmt.Printf("Task: %s (%s)\n", task.Name, task.Status)
    	}
    	return nil
    }
    
    // backupAfterDelete reports whether the API still lists a backup once its
    // database has been deleted. The API specification gives no rule for this,
    // so the example only observes it.
    func backupAfterDelete(ctx context.Context, token, id string) string {
    	const prefix = "Backup after the database was deleted:"
    	err := api(ctx, token, http.MethodGet, "/backups/"+id, nil, nil)
    	switch {
    	case err == nil:
    		return prefix + " still listed"
    	case isStatus(err, http.StatusNotFound):
    		return prefix + " gone"
    	default:
    		return prefix + " unknown"
    	}
    }
    
    
    // isStatus reports whether err is an API error with the given status.
    func isStatus(err error, status int) bool {
    	var apiErr *APIError
    	return errors.As(err, &apiErr) && apiErr.Status == status
    }
    
    // isTransient reports whether a failed request is worth repeating: no
    // reply arrived, the service is overloaded or failing, or it answered 409,
    // which the API does whilst a database is still being created.
    func isTransient(err error) bool {
    	var apiErr *APIError
    	if !errors.As(err, &apiErr) {
    		return true
    	}
    	return apiErr.Status == http.StatusConflict ||
    		apiErr.Status == http.StatusTooManyRequests ||
    		apiErr.Status >= 500
    }
    
    // findCreatedDatabase looks for the database a few times, because the
    // service may not have recorded a request whose reply was lost until a
    // little later. It returns an empty string if the database never appears.
    func findCreatedDatabase(ctx context.Context, token, name string) (string, error) {
    	for attempt := 1; ; attempt++ {
    		id, err := findDatabase(ctx, token, name)
    		if err != nil || id != "" || attempt == lookupAttempts {
    			return id, err
    		}
    		if err := sleep(ctx); err != nil {
    			return "", err
    		}
    	}
    }
    
    // outcomeUnknown reports whether a failed create request might still have
    // created the database: no reply arrived, the reply could not be decoded,
    // or the service failed with a 5xx status. A 4xx reply is a definite
    // refusal.
    func outcomeUnknown(err error) bool {
    	var apiErr *APIError
    	if !errors.As(err, &apiErr) {
    		return true
    	}
    	return apiErr.Status >= 500
    }
    
    // findDatabase returns the ID of the database with the given name, or an
    // empty string. The program uses it when it cannot tell whether a create
    // request worked. It repeats the request, as the delete does, because the
    // fault that lost the reply to the create request may still be there. The
    // request asks for the newest databases first, but the API does not say
    // which property it sorts on.
    func findDatabase(ctx context.Context, token, name string) (string, error) {
    	var databases []struct {
    		ID   string `json:"id"`
    		Name string `json:"name"`
    	}
    	deadline := time.Now().Add(timeout)
    	for {
    		err := api(ctx, token, http.MethodGet, "/databases?limit=100&descending=true", nil, &databases)
    		if err == nil {
    			break
    		}
    		if !isTransient(err) || time.Now().After(deadline) {
    			return "", err
    		}
    		if err := sleep(ctx); err != nil {
    			return "", err
    		}
    	}
    	for _, database := range databases {
    		if database.Name == name {
    			return database.ID, nil
    		}
    	}
    	return "", nil
    }
    
    // deleteDatabase deletes the database and waits until the API no longer
    // lists it.
    func deleteDatabase(ctx context.Context, token, id string) error {
    	deadline := time.Now().Add(timeout)
    	for {
    		err := api(ctx, token, http.MethodDelete, "/databases/"+id, nil, nil)
    		if err == nil {
    			break
    		}
    		if isStatus(err, http.StatusNotFound) {
    			return nil
    		}
    		if !isTransient(err) || time.Now().After(deadline) {
    			return err
    		}
    		if err := sleep(ctx); err != nil {
    			return err
    		}
    	}
    
    	// The delete starts the teardown; a 404 shows that it has finished.
    	for time.Now().Before(deadline) {
    		err := api(ctx, token, http.MethodGet, "/databases/"+id, nil, nil)
    		if isStatus(err, http.StatusNotFound) {
    			return nil
    		}
    		if err != nil && !isTransient(err) {
    			return err
    		}
    		if err := sleep(ctx); err != nil {
    			return err
    		}
    	}
    	return fmt.Errorf("the database was still present after %s", timeout)
    }
    
    
    // run creates the database, waits for it, and always deletes it, returning
    // any error to the caller.
    func run() (err error) {
    	// Ctrl-C and SIGTERM cancel ctx instead of ending the process, so the
    	// deferred cleanup below still runs.
    	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
    	defer stop()
    	// Note whether a signal arrived, after the deferred clean-up below has
    	// run, so that main can report an interruption.
    	defer func() {
    		if ctx.Err() != nil {
    			interrupted = true
    		}
    	}()
    
    	token, err := getToken(ctx)
    	if err != nil {
    		return err
    	}
    
    	region, size, err := choosePlacement(ctx, token)
    	if err != nil {
    		return err
    	}
    	fmt.Printf("Region: %s\n", region)
    	fmt.Printf("Size: %s\n", size)
    
    	// Choose the name before the request, so that the program can find
    	// the database even if the reply to the request never arrives.
    	suffix, err := randomSuffix()
    	if err != nil {
    		return err
    	}
    	name, displayName := "cookbook"+suffix, "cookbook-"+suffix
    
    	// Delete the database whether the example succeeded, failed, or was
    	// interrupted, because the service bills for it until then. The
    	// cleanup uses its own context, because ctx ends on Ctrl-C, and the
    	// signal handler above keeps absorbing any further signals until run
    	// returns.
    	var databaseID, backupID string
    	lookup := false
    	defer func() {
    		cleanup := context.Background()
    		if databaseID == "" && lookup {
    			id, findErr := findCreatedDatabase(cleanup, token, name)
    			if findErr != nil {
    				err = errors.Join(err, fmt.Errorf("looking for database %s: %w", name, findErr),
    					fmt.Errorf("delete the database %s by hand, because it may still be billing", name))
    				return
    			}
    			if id == "" {
    				err = errors.Join(err, fmt.Errorf("the database %s was not found; check your account for it by hand", name))
    				return
    			}
    			databaseID = id
    		}
    		if databaseID == "" {
    			return
    		}
    		if delErr := deleteDatabase(cleanup, token, databaseID); delErr != nil {
    			err = errors.Join(err, fmt.Errorf("deleting database %s: %w", databaseID, delErr),
    				fmt.Errorf("delete the database %s by hand, because it may still be billing", databaseID))
    			return
    		}
    		fmt.Println("Deleted database")
    		if backupID != "" {
    			fmt.Println(backupAfterDelete(cleanup, token, backupID))
    		}
    	}()
    
    	// Look the database up by name afterwards only if the outcome of the
    	// request is unknown, so that a refusal cannot lead the cleanup to
    	// delete another database that has the same name.
    	ip, err := clientIP(ctx, token)
    	if err != nil {
    		return err
    	}
    	lookup = true
    	database, err := createDatabase(ctx, token, name, displayName, region, size, ip)
    	if err != nil {
    		lookup = outcomeUnknown(err)
    		return err
    	}
    	databaseID = database.ID
    	fmt.Printf("Created database %s\n", database.DisplayName)
    
    	if err := waitUntilAvailable(ctx, token, database.ID); err != nil {
    		return err
    	}
    	fmt.Println("Database is available")
    
    	backup, err := takeBackup(ctx, token, database.ID)
    	if err != nil {
    		return err
    	}
    	backupID = backup.ID
    	fmt.Println("Backup started")
    	if err := waitForBackup(ctx, token, backup.ID); err != nil {
    		return err
    	}
    	return printTasks(ctx, token, database.ID)
    }
    
    // interrupted is set when Ctrl-C or SIGTERM arrived before run() returned.
    var interrupted bool
    
    // main reports any error returned by run() and exits with a non-zero
    // status. After a signal, it prints "Interrupted" and exits with 130, the
    // status of a program that the user stopped, unless the clean-up failed as
    // well, which errors.Join reports on a line of its own.
    func main() {
    	if err := run(); err != nil {
    		if interrupted {
    			fmt.Fprintln(os.Stderr, "Interrupted")
    			if strings.Contains(err.Error(), "\n") {
    				fmt.Fprintf(os.Stderr, "Error: %v\n", err)
    				os.Exit(1)
    			}
    			os.Exit(130)
    		}
    		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
    		os.Exit(1)
    	}
    }
    
    
    ```

=== "Rust"

    ```rust
    // Ellie's Postgres Cookbook
    // Taking an on-demand backup of a pgEdge Starfleet database, and tracking
    // it until it completes, using reqwest and serde_json.
    //
    // The program creates a database of its own to back up. The Starfleet
    // service bills for every database from the moment that it becomes
    // connectable, so the program deletes the database on every path: after a
    // success, after a failure, after a panic, and after Ctrl-C.
    //
    // Copyright (c) 2026, pgEdge, Inc.
    // This code is released under the PostgreSQL License.
    
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
    
    use reqwest::blocking::Client;
    use reqwest::Method;
    use serde_json::{json, Value};
    use signal_hook::consts::{SIGINT, SIGTERM};
    
    /// How long to wait for a database to become available, or to disappear
    /// after a delete, and how often to check.
    const TIMEOUT: Duration = Duration::from_secs(900);
    const POLL: Duration = Duration::from_secs(10);
    
    /// How many times to look for a database whose create reply was lost.
    const LOOKUP_ATTEMPTS: u32 = 3;
    
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
    
    /// Sends an authenticated request to the Managed API and returns the
    /// decoded JSON reply, or null if the reply has no body. After a signal,
    /// it returns an error without sending anything.
    fn api(cfg: &Settings, token: &str, method: Method, path: &str, body: Option<&Value>) -> Result<Value> {
        check_interrupted()?;
        let url = format!("{}/managed/v1{path}", cfg.base_url);
        request(method, &url, path, Some(token), body)
    }
    
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
    
    /// The API does not document its backup status values beyond "completed",
    /// which marks a usable backup; the example treats "failed" as a failure,
    /// which ends the wait at once instead of leaving it to run until the time
    /// limit.
    const FAILED_BACKUP_STATUSES: [&str; 1] = ["failed"];
    
    /// Starts an on-demand backup and returns the pending backup.
    fn take_backup(cfg: &Settings, token: &str, database_id: &str) -> Result<Value> {
        // The hot kind is a fast local snapshot. The durable kind streams a
        // base backup to object storage, and needs the durable tier to be
        // enabled for the database. The API answers 202 at once and runs the
        // backup in the background.
        let path = format!("/databases/{database_id}/backup");
        api(cfg, token, Method::POST, &path, Some(&json!({"kind": "hot"})))
    }
    
    /// Polls the backup until its status is completed.
    fn wait_for_backup(cfg: &Settings, token: &str, backup_id: &str) -> Result<()> {
        let deadline = Instant::now() + TIMEOUT;
        let mut last = String::new();
        while Instant::now() < deadline {
            let path = format!("/backups/{backup_id}");
            let status = field(&api(cfg, token, Method::GET, &path, None)?, "status")?;
            if status != last {
                println!("Backup status: {status}");
                last = status.clone();
            }
            if status == "completed" {
                return Ok(());
            }
            if FAILED_BACKUP_STATUSES.contains(&status.as_str()) {
                return Err(format!("the backup has the status {status}").into());
            }
            pause(POLL)?;
        }
        Err(format!("the backup was not completed after {} seconds", TIMEOUT.as_secs()).into())
    }
    
    /// Prints the name and status of each task recorded for the database.
    fn print_tasks(cfg: &Settings, token: &str, database_id: &str) -> Result<()> {
        // Managed database operations record their progress as tasks, with the
        // kind "database" and the database ID as the subject.
        let path = format!("/tasks?subject_kind=database&subject_id={database_id}");
        let tasks = api(cfg, token, Method::GET, &path, None)?;
        for task in tasks.as_array().into_iter().flatten() {
            println!("Task: {} ({})", field(task, "name")?, field(task, "status")?);
        }
        Ok(())
    }
    
    /// Reports whether the API still lists a backup once its database has been
    /// deleted. The API specification gives no rule for this, so the example
    /// only observes it.
    fn backup_after_delete(cfg: &Settings, token: &str, backup_id: &str) -> Result<String> {
        let prefix = "Backup after the database was deleted:";
        let outcome = match api(cfg, token, Method::GET, &format!("/backups/{backup_id}"), None) {
            Ok(_) => "still listed",
            Err(e) => match e.downcast_ref::<ApiError>() {
                Some(api) if api.status == 404 => "gone",
                Some(_) => "unknown",
                None if e.is::<reqwest::Error>() => "unknown",
                None => return Err(e),
            },
        };
        Ok(format!("{prefix} {outcome}"))
    }
    
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
    
    /// What the clean-up needs to know about the database that run created.
    #[derive(Default)]
    struct Created {
        token: Option<String>,
        name: Option<String>,
        database_id: Option<String>,
        lookup: bool,
        backup_id: Option<String>,
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
    
        let backup_id = field(&take_backup(cfg, &token, &database_id)?, "id")?;
        created.backup_id = Some(backup_id.clone());
        println!("Backup started");
        wait_for_backup(cfg, &token, &backup_id)?;
        print_tasks(cfg, &token, &database_id)?;
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
                if let Some(backup_id) = &created.backup_id {
                    println!("{}", backup_after_delete(cfg, token, backup_id)?);
                }
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
    
    ```

=== "Ruby"

    ```ruby
    # Ellie's Postgres Cookbook
    # Taking an on-demand backup of a pgEdge Starfleet database, and tracking it
    # until it completes, using Net::HTTP.
    #
    # The program creates a database of its own to back up. The Starfleet service
    # bills for every database from the moment that it becomes connectable, so
    # the program deletes the database on every path: after a success, after a
    # failure, and after Ctrl-C.
    #
    # Copyright (c) 2026, pgEdge, Inc.
    # This code is released under the PostgreSQL License.
    
    require "json"
    require "net/http"
    require "securerandom"
    
    # How long to wait for a database to become available, or to disappear
    # after a delete, and how often to check.
    TIMEOUT_SECONDS = 900
    POLL_SECONDS = 10
    
    # How many times to look for a database whose create reply was lost.
    LOOKUP_ATTEMPTS = 3
    
    # Returns the value of an environment variable, or a fallback if the
    # variable is unset or empty, as an unset variable would be.
    def env_or(name, fallback)
      value = ENV[name]
      value.nil? || value.empty? ? fallback : value
    end
    
    # Reads the API settings from the environment. The client ID and secret
    # have no defaults, so a missing value becomes nil, and the token request
    # reports it.
    def settings
      {
        base_url: env_or("STARFLEET_API_URL", "https://api.pgedge.com").sub(%r{/+\z}, ""),
        client_id: env_or("STARFLEET_CLIENT_ID", nil),
        client_secret: env_or("STARFLEET_CLIENT_SECRET", nil)
      }
    end
    
    # The current time from a clock that only moves forwards, for deadlines.
    def now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
    
    # An error reply from the API, with its HTTP status.
    class ApiError < StandardError
      attr_reader :status
    
      def initialize(status, message)
        super(message)
        @status = status
      end
    end
    
    # Sends a request with a JSON body, if there is one, and returns the
    # response. Net::HTTP has no overall timeout, so this limits both the
    # connection and each read.
    def send_request(method, url, headers, body)
      uri = URI(url)
      headers = headers.merge("Content-Type" => "application/json") if body
      Net::HTTP.start(uri.host, uri.port,
                      use_ssl: uri.scheme == "https",
                      open_timeout: 30, read_timeout: 30, write_timeout: 30) do |http|
        http.send_request(method, uri.request_uri, body&.to_json, headers)
      end
    end
    
    # Raises an ApiError for a 4xx or 5xx reply.
    def check_status(method, path, response)
      return if response.code.to_i < 400
    
      raise ApiError.new(response.code.to_i,
                         "#{method} #{path} failed with status #{response.code}: " \
                         "#{response.body.to_s.strip}")
    end
    
    # Exchanges the client ID and secret for an access token, which the
    # Managed API accepts as a bearer token until it expires.
    def get_token(config)
      unless config[:client_id] && config[:client_secret]
        raise "STARFLEET_CLIENT_ID and STARFLEET_CLIENT_SECRET must be set"
      end
    
      path = "/account/v1/oauth/token"
      response = send_request("POST", "#{config[:base_url]}#{path}", {}, {
                                grant_type: "client_credentials",
                                client_id: config[:client_id],
                                client_secret: config[:client_secret]
                              })
      check_status("POST", path, response)
      JSON.parse(response.body).fetch("access_token")
    end
    
    # Sends an authenticated request to the Managed API and returns the
    # decoded JSON reply, or nil if the reply has no body.
    def api(config, token, method, path, body = nil)
      response = send_request(method, "#{config[:base_url]}/managed/v1#{path}",
                              { "Authorization" => "Bearer #{token}" }, body)
      check_status(method, path, response)
      text = response.body.to_s
      text.empty? ? nil : JSON.parse(text)
    end
    
    # Returns the region and size for the new database. The API lists sizes
    # smallest first, so the first one is the cheapest. The API does not price
    # regions, so the example takes the first one.
    def choose_placement(config, token)
      regions = api(config, token, "GET", "/regions")
      sizes = api(config, token, "GET", "/sizes")
      raise "the API offers no region or size" if regions.to_a.empty? || sizes.to_a.empty?
    
      [regions[0].fetch("region"), sizes[0].fetch("name")]
    end
    
    # Returns the address that the API sees requests come from.
    def client_ip(config, token)
      # A new database is closed to everyone until an allowlist rule admits an
      # address. The API reports the address it sees this request come from,
      # which is the one to admit; a bare address means a single host.
      api(config, token, "GET", "/client-ip").fetch("ip_address")
    end
    
    # Creates a database that only this machine can reach, and returns the
    # API's description of it, which includes its ID.
    def create_database(config, token, name, display_name, region, size, ip)
      api(config, token, "POST", "/databases", {
            # The name becomes the Postgres database name, so it holds only
            # letters and digits, and the readable cookbook- prefix goes in the
            # display name. The program also uses the name to find the database
            # again if the reply to this request is lost.
            name: name,
            display_name: display_name,
            region: region,
            size: size,
            ip_allowlist: { rules: [{ cidr: ip, label: "cookbook" }] }
          })
    end
    
    # The API does not document its status values; the example treats these
    # two as failures, which end the wait at once instead of leaving it to run
    # until the time limit.
    FAILED_STATUSES = %w[degraded failed].freeze
    
    # Polls the database until its status is available.
    def wait_until_available(config, token, database_id)
      deadline = now + TIMEOUT_SECONDS
      last = nil
      while now < deadline
        status = api(config, token, "GET", "/databases/#{database_id}").fetch("status")
        if status != last
          puts "Database status: #{status}"
          last = status
        end
        return if status == "available"
        raise "the database has the status #{status}" if FAILED_STATUSES.include?(status)
    
        sleep POLL_SECONDS
      end
      raise "the database was not available after #{TIMEOUT_SECONDS} seconds"
    end
    
    # The API does not document its backup status values beyond "completed",
    # which marks a usable backup; the example treats "failed" as a failure,
    # which ends the wait at once instead of leaving it to run until the time
    # limit.
    FAILED_BACKUP_STATUSES = %w[failed].freeze
    
    # Starts an on-demand backup and returns the pending backup.
    def take_backup(config, token, database_id)
      # The hot kind is a fast local snapshot. The durable kind streams a base
      # backup to object storage, and needs the durable tier to be enabled for
      # the database. The API answers 202 at once and runs the backup in the
      # background.
      api(config, token, "POST", "/databases/#{database_id}/backup", { kind: "hot" })
    end
    
    # Polls the backup until its status is completed.
    def wait_for_backup(config, token, backup_id)
      deadline = now + TIMEOUT_SECONDS
      last = nil
      while now < deadline
        status = api(config, token, "GET", "/backups/#{backup_id}").fetch("status")
        if status != last
          puts "Backup status: #{status}"
          last = status
        end
        return if status == "completed"
        raise "the backup has the status #{status}" if FAILED_BACKUP_STATUSES.include?(status)
    
        sleep POLL_SECONDS
      end
      raise "the backup was not completed after #{TIMEOUT_SECONDS} seconds"
    end
    
    # Prints the name and status of each task recorded for the database.
    def print_tasks(config, token, database_id)
      # Managed database operations record their progress as tasks, with the
      # kind "database" and the database ID as the subject.
      tasks = api(config, token, "GET",
                  "/tasks?subject_kind=database&subject_id=#{database_id}")
      tasks.to_a.each do |task|
        puts "Task: #{task.fetch('name')} (#{task.fetch('status')})"
      end
    end
    
    # Reports whether the API still lists a backup once its database has been
    # deleted. The API specification gives no rule for this, so the example
    # only observes it.
    def backup_after_delete(config, token, backup_id)
      prefix = "Backup after the database was deleted:"
      begin
        api(config, token, "GET", "/backups/#{backup_id}")
        "#{prefix} still listed"
      rescue ApiError => e
        "#{prefix} #{e.status == 404 ? 'gone' : 'unknown'}"
      rescue *TRANSPORT_ERRORS
        "#{prefix} unknown"
      end
    end
    
    # The errors that mean that no reply arrived: a refused or reset
    # connection, a failed name lookup, a TLS failure, or a timeout.
    TRANSPORT_ERRORS = [SystemCallError, IOError, SocketError, Timeout::Error,
                        OpenSSL::SSL::SSLError].freeze
    
    # Reports whether a failed request is worth repeating: no reply arrived,
    # the service is overloaded or failing, or it answered 409, which the API
    # does whilst a database is still being created.
    def transient?(error)
      return true if TRANSPORT_ERRORS.any? { |type| error.is_a?(type) }
      return false unless error.is_a?(ApiError)
    
      [409, 429].include?(error.status) || error.status >= 500
    end
    
    # Reports whether an error is a 404 reply, which means that the database
    # does not exist.
    def gone?(error)
      error.is_a?(ApiError) && error.status == 404
    end
    
    # Returns the ID of the database with the given name, or nil. The program
    # uses this when it cannot tell whether a create request worked. It repeats
    # the request, as the delete does, because the fault that lost the reply to
    # the create request may still be there. The request asks for the newest
    # databases first, but the API does not say which property it sorts on.
    def find_database(config, token, name)
      deadline = now + TIMEOUT_SECONDS
      databases = begin
        api(config, token, "GET", "/databases?limit=100&descending=true")
      rescue StandardError => e
        raise if !transient?(e) || now > deadline
    
        sleep POLL_SECONDS
        retry
      end
      database = databases.to_a.find { |d| d["name"] == name }
      database&.fetch("id")
    end
    
    # Looks for the database a few times, because the service may not have
    # recorded a request whose reply was lost until a little later. Returns nil
    # if the database never appears.
    def find_created_database(config, token, name)
      LOOKUP_ATTEMPTS.times do |attempt|
        database_id = find_database(config, token, name)
        return database_id if database_id
    
        sleep POLL_SECONDS if attempt < LOOKUP_ATTEMPTS - 1
      end
      nil
    end
    
    # Reports whether a failed create request might still have created the
    # database: no reply arrived, the reply could not be read, or the service
    # failed with a 5xx status. A 4xx reply is a definite refusal.
    def outcome_unknown?(error)
      return error.status >= 500 if error.is_a?(ApiError)
    
      true
    end
    
    # Deletes the database and waits until the API no longer lists it.
    def delete_database(config, token, database_id)
      deadline = now + TIMEOUT_SECONDS
      begin
        api(config, token, "DELETE", "/databases/#{database_id}")
      rescue StandardError => e
        return if gone?(e)
        raise if !transient?(e) || now > deadline
    
        sleep POLL_SECONDS
        retry
      end
    
      # The delete starts the teardown; a 404 shows that it has finished.
      while now < deadline
        begin
          api(config, token, "GET", "/databases/#{database_id}")
        rescue StandardError => e
          return if gone?(e)
          raise unless transient?(e)
        end
        sleep POLL_SECONDS
      end
      raise "the database was still present after #{TIMEOUT_SECONDS} seconds"
    end
    
    def main
      config = settings
      exit_code = 0
      token = nil
      name = nil
      database_id = nil
      lookup = false
      backup_id = nil
      begin
        token = get_token(config)
    
        region, size = choose_placement(config, token)
        puts "Region: #{region}"
        puts "Size: #{size}"
    
        # Choose the name before the request, so that the program can find the
        # database even if the reply to the request never arrives.
        suffix = SecureRandom.hex(3)
        name = "cookbook#{suffix}"
        display_name = "cookbook-#{suffix}"
        # Look the database up by name afterwards only if the outcome of the
        # request is unknown, so that a refusal cannot lead the cleanup to
        # delete another database that has the same name.
        ip = client_ip(config, token)
        lookup = true
        begin
          database = create_database(config, token, name, display_name, region, size, ip)
        rescue StandardError => e
          lookup = outcome_unknown?(e)
          raise
        end
        database_id = database.fetch("id")
        puts "Created database #{database.fetch('display_name')}"
    
        wait_until_available(config, token, database_id)
        puts "Database is available"
    
        backup_id = take_backup(config, token, database_id).fetch("id")
        puts "Backup started"
        wait_for_backup(config, token, backup_id)
        print_tasks(config, token, database_id)
      # Net::HTTP raises errors of many classes, such as SystemCallError for a
      # refused connection and Net::OpenTimeout for a timeout, and the program
      # raises ApiError and RuntimeError for replies that it cannot use, so
      # this catches StandardError, their common ancestor.
      rescue StandardError => e
        warn "Error: #{e.message}"
        exit_code = 1
      # Ruby raises Interrupt for Ctrl-C and SignalException for SIGTERM.
      rescue SignalException
        warn "Interrupted"
        exit_code = 130
      ensure
        # Delete the database whether the example succeeded, failed, or was
        # interrupted, because the service bills for it until then. Ignore
        # further interrupts, so that they cannot cut it short.
        trap("INT", "IGNORE")
        trap("TERM", "IGNORE")
        if token && name
          begin
            if database_id.nil? && lookup
              database_id = find_created_database(config, token, name)
              if database_id.nil?
                warn "Error: the database #{name} was not found; " \
                     "check your account for it by hand"
                exit_code = 1
              end
            end
            if database_id
              delete_database(config, token, database_id)
              puts "Deleted database"
              puts backup_after_delete(config, token, backup_id) if backup_id
            end
          rescue StandardError => e
            warn "Error: #{e.message}"
            warn "Delete the database #{database_id || name} by hand, " \
                 "because it may still be billing"
            exit_code = 1
          end
        end
      end
      exit_code
    end
    
    exit main
    
    ```

=== "curl"

    ```bash
    #!/usr/bin/env bash
    #
    # Ellie's Postgres Cookbook
    # Taking an on-demand backup of a pgEdge Starfleet database, and tracking it
    # until it completes, using curl and jq.
    #
    # The script creates a database of its own to back up. The Starfleet
    # service bills for every database from the moment that it becomes
    # connectable, so the script deletes the database on every path: after a
    # success, after a failure, and after Ctrl-C.
    #
    # Copyright (c) 2026, pgEdge, Inc.
    # This code is released under the PostgreSQL License.
    
    # Stop at the first failed command or unset variable, and make a failure
    # anywhere in a pipeline fail the whole pipeline.
    set -euo pipefail
    
    # The script needs curl to call the API and jq to read the JSON replies.
    for tool in curl jq; do
        command -v "$tool" >/dev/null || { echo "Error: $tool is required" >&2; exit 1; }
    done
    
    # How long to wait for a database to become available, or to disappear
    # after a delete, and how often to check.
    timeout_seconds=900
    poll_seconds=10
    
    # The :- expansion treats an empty variable as unset.
    base_url="${STARFLEET_API_URL:-https://api.pgedge.com}"
    base_url="${base_url%/}"
    client_id="${STARFLEET_CLIENT_ID:-}"
    client_secret="${STARFLEET_CLIENT_SECRET:-}"
    
    # Exchanges the client ID and secret for an access token, which the
    # Managed API accepts as a bearer token until it expires, and prints
    # the token.
    get_token() {
        if [[ -z "$client_id" || -z "$client_secret" ]]; then
            echo "Error: STARFLEET_CLIENT_ID and STARFLEET_CLIENT_SECRET must be set" >&2
            return 1
        fi
    
        # jq builds the body from the environment, and curl reads it from
        # standard input with --data @-, so the secret never appears in the
        # process list. --fail-with-body makes curl exit non-zero on an HTTP
        # error status whilst still printing the API's error message.
        jq -n '{grant_type: "client_credentials",
                client_id: env.STARFLEET_CLIENT_ID,
                client_secret: env.STARFLEET_CLIENT_SECRET}' |
            curl --silent --show-error --fail-with-body --max-time 30 \
                --header "Content-Type: application/json" \
                --data @- \
                "$base_url/account/v1/oauth/token" |
            jq -er '.access_token'
    }
    
    # Sends an authenticated request to the Managed API and prints the JSON
    # reply. The first argument is the method, the second is the path, and any
    # others go to curl, such as --data @- to send standard input as the body.
    # The --config option reads the Authorization header from a file that
    # bash creates from the printf command, so the token never appears in the
    # process list; that leaves standard input free for the body.
    api() {
        local method="$1" path="$2"
        shift 2
        curl --silent --show-error --fail-with-body --max-time 30 \
            --request "$method" \
            --config <(printf 'header = "Authorization: Bearer %s"\n' "$token") \
            "$@" "$base_url/managed/v1$path"
    }
    
    # Sends a request and prints only the HTTP status, for the calls that
    # react to a particular status. A status of 000 means no reply arrived.
    api_status() {
        curl --silent --output /dev/null --write-out '%{http_code}' --max-time 30 \
            --request "$1" \
            --config <(printf 'header = "Authorization: Bearer %s"\n' "$token") \
            "$base_url/managed/v1$2" || true
    }
    
    # Prints the region and size for the new database, separated by a space.
    # The API lists sizes smallest first, so the first one is the cheapest.
    # The API does not price regions, so the example takes the first one.
    choose_placement() {
        local region size
        region="$(api GET /regions | jq -er '.[0].region')"
        size="$(api GET /sizes | jq -er '.[0].name')"
        echo "$region $size"
    }
    
    # Prints the address that the API sees requests come from. A new database
    # is closed to everyone until an allowlist rule admits an address, and this
    # is the one to admit; a bare address means a single host.
    client_ip() {
        api GET /client-ip | jq -er '.ip_address'
    }
    
    # Creates a database that only this machine can reach, and prints the
    # API's description of it, which includes its ID.
    create_database() {
        local name="$1" display_name="$2" region="$3" size="$4" ip="$5"
        # The name becomes the Postgres database name, so it holds only letters
        # and digits, and the readable cookbook- prefix goes in the display
        # name. The script also uses the name to find the database again if the
        # reply to this request is lost.
        jq -n --arg name "$name" --arg display_name "$display_name" \
            --arg region "$region" --arg size "$size" --arg ip "$ip" \
            '{name: $name, display_name: $display_name,
              region: $region, size: $size,
              ip_allowlist: {rules: [{cidr: $ip, label: "cookbook"}]}}' |
            api POST /databases --header "Content-Type: application/json" \
                --data @- --write-out '\n%{http_code}'
    }
    
    # Polls the database until its status is available.
    wait_until_available() {
        local id="$1" deadline=$((SECONDS + timeout_seconds)) status last=""
        while ((SECONDS < deadline)); do
            status="$(api GET "/databases/$id" | jq -er '.status')"
            if [[ "$status" != "$last" ]]; then
                echo "Database status: $status"
                last="$status"
            fi
            [[ "$status" == "available" ]] && return 0
            # The API does not document its status values; the example treats
            # these two as failures, which end the wait at once instead of
            # leaving it to run until the time limit.
            if [[ "$status" == "degraded" || "$status" == "failed" ]]; then
                echo "Error: the database has the status $status" >&2
                return 1
            fi
            sleep "$poll_seconds"
        done
        echo "Error: the database was not available after $timeout_seconds seconds" >&2
        return 1
    }
    
    # Starts an on-demand backup and prints the pending backup. The hot kind is
    # a fast local snapshot. The durable kind streams a base backup to object
    # storage, and needs the durable tier to be enabled for the database. The
    # API answers 202 at once and runs the backup in the background.
    take_backup() {
        jq -n '{kind: "hot"}' |
            api POST "/databases/$1/backup" \
                --header "Content-Type: application/json" --data @-
    }
    
    # Polls the backup until its status is completed.
    wait_for_backup() {
        local id="$1" deadline=$((SECONDS + timeout_seconds)) status last=""
        while ((SECONDS < deadline)); do
            status="$(api GET "/backups/$id" | jq -er '.status')"
            if [[ "$status" != "$last" ]]; then
                echo "Backup status: $status"
                last="$status"
            fi
            [[ "$status" == "completed" ]] && return 0
            # The API does not document its backup status values beyond
            # "completed", which marks a usable backup; the example treats
            # "failed" as a failure, which ends the wait at once instead of
            # leaving it to run until the time limit.
            if [[ "$status" == "failed" ]]; then
                echo "Error: the backup has the status $status" >&2
                return 1
            fi
            sleep "$poll_seconds"
        done
        echo "Error: the backup was not completed after $timeout_seconds seconds" >&2
        return 1
    }
    
    # Prints the name and status of each task recorded for the database.
    # Managed database operations record their progress as tasks, with the kind
    # "database" and the database ID as the subject.
    print_tasks() {
        local tasks
        tasks="$(api GET "/tasks?subject_kind=database&subject_id=$1")"
        jq -r '.[] | "Task: \(.name) (\(.status))"' <<<"$tasks"
    }
    
    # Reports whether the API still lists a backup once its database has been
    # deleted. The API specification gives no rule for this, so the example
    # only observes it.
    backup_after_delete() {
        local status prefix="Backup after the database was deleted:"
        status="$(api_status GET "/backups/$1")"
        case "$status" in
            200) echo "$prefix still listed" ;;
            404) echo "$prefix gone" ;;
            *)   echo "$prefix unknown" ;;
        esac
    }
    
    # Prints the ID of the database with the given name, or nothing. The script
    # uses this when it cannot tell whether the create request worked. It
    # repeats the request, as the delete does, because the fault that lost the
    # reply to the create request may still be there.
    find_database() {
        local deadline=$((SECONDS + timeout_seconds)) reply status
        while true; do
            # The --write-out option adds the HTTP status on a last line, and
            # prints 000 if no reply arrived. The request asks for the newest
            # databases first, but the API does not say which property it
            # sorts on.
            reply="$(api GET "/databases?limit=100&descending=true" \
                --write-out '\n%{http_code}')" || true
            status="${reply##*$'\n'}"
            case "$status" in
                200) break ;;
                000|409|429|5??) ;;
                *) echo "Error: listing the databases returned HTTP status $status" >&2
                   return 1 ;;
            esac
            if ((SECONDS >= deadline)); then
                echo "Error: the list was still failing after $timeout_seconds seconds" >&2
                return 1
            fi
            sleep "$poll_seconds"
        done
        jq -r --arg name "$1" 'first(.[] | select(.name == $name) | .id) // empty' \
            <<<"${reply%$'\n'*}"
    }
    
    # Prints the ID of the database with the given name, looking up to three
    # times because the service may not have recorded a request whose reply was
    # lost until a little later. Prints nothing if the database never appears,
    # and fails if a lookup fails.
    find_created_database() {
        local attempt id
        for ((attempt = 1; attempt <= 3; attempt++)); do
            id="$(find_database "$1")" || return 1
            if [[ -n "$id" ]]; then
                echo "$id"
                return 0
            fi
            ((attempt < 3)) && sleep "$poll_seconds"
        done
        return 0
    }
    
    # Deletes the database and waits until the API no longer lists it. A status
    # of 000 means that no reply arrived; that, 409 (which the API gives whilst a
    # database is still being created), 429, and the 5xx statuses are worth
    # repeating until the time limit.
    delete_database() {
        local id="$1" deadline=$((SECONDS + timeout_seconds)) status
    
        while true; do
            status="$(api_status DELETE "/databases/$id")"
            case "$status" in
                204) break ;;
                404) return 0 ;;
                000|409|429|5??) ;;
                *) echo "Error: deleting the database returned HTTP status $status" >&2
                   return 1 ;;
            esac
            if ((SECONDS >= deadline)); then
                echo "Error: the delete was still failing after $timeout_seconds seconds" >&2
                return 1
            fi
            sleep "$poll_seconds"
        done
    
        # The delete starts the teardown; a 404 shows that it has finished.
        while true; do
            status="$(api_status GET "/databases/$id")"
            case "$status" in
                404) return 0 ;;
                200|000|429|5??) ;;
                *) echo "Error: checking the database returned HTTP status $status" >&2
                   return 1 ;;
            esac
            if ((SECONDS >= deadline)); then
                echo "Error: the database was still present after $timeout_seconds seconds" >&2
                return 1
            fi
            sleep "$poll_seconds"
        done
    }
    
    # Deletes the database, if the script created one. The EXIT trap runs this
    # function when the script finishes, whether the example succeeded, failed,
    # or was interrupted, because the service bills for the database until then.
    cleanup() {
        local status=$?
        # Ignore further interrupts, so that they cannot cut the cleanup short.
        trap '' INT TERM
        if [[ -n "$token" && -n "$name" ]]; then
            # If the script has no ID and cannot tell whether the create request
            # worked, look for the database by name.
            if [[ -z "$database_id" && "$lookup" == 1 ]]; then
                if ! database_id="$(find_created_database "$name")"; then
                    echo "Error: could not look for database $name" >&2
                    echo "Delete the database $name by hand, because it may still be billing" >&2
                    database_id=""
                    status=1
                elif [[ -z "$database_id" ]]; then
                    echo "Error: the database $name was not found; check your account for it by hand" >&2
                    status=1
                fi
            fi
            if [[ -n "$database_id" ]]; then
                if delete_database "$database_id"; then
                    echo "Deleted database"
                    if [[ -n "$backup_id" ]]; then backup_after_delete "$backup_id"; fi
                else
                    echo "Error: could not delete database $database_id" >&2
                    echo "Delete the database $database_id by hand, because it may still be billing" >&2
                    status=1
                fi
            fi
        fi
        exit "$status"
    }
    
    main() {
        token="" name="" database_id="" backup_id="" lookup=0
        trap cleanup EXIT
        # Turn Ctrl-C and SIGTERM into a normal exit, so that cleanup runs.
        trap 'echo "Interrupted" >&2; exit 130' INT TERM
    
        token="$(get_token)"
    
        local placement region size suffix database display_name reply status ip
        placement="$(choose_placement)"
        region="${placement% *}"
        size="${placement#* }"
        echo "Region: $region"
        echo "Size: $size"
    
        # Choose the name before the request, so that the cleanup can find the
        # database even if the reply to the request never arrives.
        suffix="$(od -An -N3 -tx1 /dev/urandom | tr -d ' \n')"
        name="cookbook$suffix"
    
        # Look the database up by name afterwards only if the outcome of the
        # request is unknown, so that a refusal cannot lead the cleanup to
        # delete another database that has the same name. The create_database
        # function ends its output with the HTTP status on a line of its own,
        # which is 000 if no reply arrived.
        ip="$(client_ip)"
        lookup=1
        if ! reply="$(create_database "$name" "cookbook-$suffix" "$region" "$size" "$ip")"; then
            status="${reply##*$'\n'}"
            echo "Error: creating the database failed" >&2
            echo "${reply%$'\n'*}" >&2
            [[ "$status" =~ ^4[0-9][0-9]$ ]] && lookup=0
            return 1
        fi
        database="${reply%$'\n'*}"
        database_id="$(jq -er '.id' <<<"$database")"
        display_name="$(jq -er '.display_name' <<<"$database")"
        echo "Created database $display_name"
    
        wait_until_available "$database_id"
        echo "Database is available"
    
        local backup
        backup="$(take_backup "$database_id")"
        backup_id="$(jq -er '.id' <<<"$backup")"
        echo "Backup started"
        wait_for_backup "$backup_id"
        print_tasks "$database_id"
    }
    
    main
    
    ```

## Next Steps

The following resources provide more information about the topics in this
recipe:

- The "Creating a Database and Waiting for It" recipe explains the creation and
  deletion steps in more detail.
- The "Getting an Access Token" recipe explains the token exchange in more
  detail.
