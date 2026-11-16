# Creating a Database

This recipe asks a pgEdge Control Plane server to create a database with one
node, follows its state until the database is available, and then deletes it
again. Creating a database starts the Postgres containers on the chosen host,
so the program deletes the database on every path, after a success, after a
failure, and after Ctrl-C, and a test run leaves nothing behind. Each step
shows the code in every supported language; selecting a language tab switches
every tab on the site to that language.

These examples are for the Control Plane v0.11.0.

The program prints output like the following; the database ID ends in a random
suffix, and the number of state lines depends on how long the containers take
to start:

```text
Host: cookbook-host-1
Created database cookbook-recipe-3f9a1c
Database state: creating
Database state: available
Database is available on port 6433
Deleted database
```

## Preparing the Ingredients

The examples assume a running Control Plane server with at least one host, and
a free port on that host for the new database. The
`scripts/start_control_plane.sh` script in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook)
starts a suitable server in Docker; the
[Checking the Cluster](cluster_status.md) recipe shows how to check that its
hosts are healthy.

The program calls the following endpoints:

| Endpoint                                 | Description                                         |
|------------------------------------------|-----------------------------------------------------|
| `GET /v1/hosts`                          | Lists the hosts that can run a database node.       |
| `POST /v1/databases`                     | Creates a database, and starts a task to build it.  |
| `GET /v1/databases/{id}`                 | Returns the database, with its state.               |
| `DELETE /v1/databases/{id}`              | Deletes a database, and starts a task to remove it. |
| `GET /v1/databases/{id}/tasks/{task_id}` | Returns a task, with its status.                    |

The client chooses the ID of a new database. An ID has between 1 and 36
characters, which are lowercase letters, digits and single hyphens, so each
program adds a random suffix to `cookbook-recipe-`. The create request
returns at once, with the database in the `creating` state, and the Control
Plane builds it in a task; the database then becomes `available`, or `failed`
if something goes wrong. The other states are `modifying`, `deleting`,
`degraded`, `restoring` and `unknown`.

The following tabs show the dependency declaration from each example project:

=== "Python"

    ```text
    # httpx, an HTTP client with a requests-like API.
    httpx>=0.28,<1
    ```

=== "TypeScript"

    ```json
    {
      "name": "create-database",
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
      <!-- Jackson, for reading and writing JSON; the HTTP client is part of
           the JDK. -->
      <dependency>
        <groupId>tools.jackson.core</groupId>
        <artifactId>jackson-databind</artifactId>
        <version>3.2.4</version>
      </dependency>
    </dependencies>
    ```

=== "C#"

    ```xml
    <!-- HttpClient and System.Text.Json are part of .NET, so the project
         needs no packages. -->
    ```

=== "Go"

    ```text
    // The program uses only the standard library, so there is nothing to add.
    ```

=== "Rust"

    ```toml
    [dependencies]
    # The blocking client, with TLS from rustls and request and response bodies
    # as JSON; the default features add HTTP/2 and other things this example
    # does not use.
    reqwest = { version = "0.13", default-features = false, features = ["blocking", "json", "rustls"] }
    serde_json = "1"
    # Handling Ctrl-C, and with the termination feature SIGTERM, so that the
    # program can delete its database before it exits.
    ctrlc = { version = "3", features = ["termination"] }
    ```

=== "Ruby"

    ```ruby
    source "https://rubygems.org"
    
    # The program uses only Net::HTTP and json from the standard library, so
    # there is no gem to add.
    ```

## Importing the Libraries

Each program begins by importing its HTTP client and JSON library, along with
the standard library modules that it uses for the random suffix and for
handling Ctrl-C. The curl script checks that `curl` and `jq` are installed.
The following tabs show the imports for each language:

=== "Python"

    ```python
    import os
    import re
    import secrets
    import signal
    import sys
    import time
    
    import httpx
    ```

=== "TypeScript"

    ```typescript
    // Node.js provides fetch and AbortSignal as globals; setTimeout from
    // timers/promises returns a promise, which suits a polling loop.
    import { randomBytes } from "node:crypto";
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
    import java.util.concurrent.CompletableFuture;
    import java.util.concurrent.CountDownLatch;
    import java.util.concurrent.ExecutionException;
    import java.util.concurrent.TimeUnit;
    import java.util.concurrent.TimeoutException;
    
    import tools.jackson.core.JacksonException;
    import tools.jackson.databind.JsonNode;
    import tools.jackson.databind.ObjectMapper;
    import tools.jackson.databind.json.JsonMapper;
    ```

=== "C#"

    ```csharp
    using System.Diagnostics;
    using System.Net.Http.Json;
    using System.Runtime.InteropServices;
    using System.Security.Cryptography;
    using System.Text.Json;
    using System.Text.RegularExpressions;
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
    	"strconv"
    	"strings"
    	"syscall"
    	"time"
    )
    
    ```

=== "Rust"

    ```rust
    use std::env;
    use std::error::Error;
    use std::fmt;
    use std::fs::File;
    use std::io::Read;
    use std::process::ExitCode;
    use std::sync::atomic::{AtomicBool, Ordering};
    use std::thread;
    use std::time::{Duration, Instant};
    
    use reqwest::blocking::Client;
    use reqwest::Method;
    use serde_json::{json, Value};
    ```

=== "Ruby"

    ```ruby
    require "json"
    require "net/http"
    require "securerandom"
    require "uri"
    ```

=== "curl"

    ```bash
    # Stop at the first failed command or unset variable, and make a failure
    # anywhere in a pipeline fail the whole pipeline.
    set -euo pipefail
    
    # The script needs curl to call the API and jq to read the JSON replies.
    for tool in curl jq; do
        command -v "$tool" >/dev/null || { echo "Control Plane error: $tool is required" >&2; exit 1; }
    done
    ```

## Configuring the Program

The examples read their settings from environment variables, and treat an
empty value as unset. Each request may take up to 30 seconds, and the program
waits up to 600 seconds for the database, checking every five seconds. The
following table describes the environment variables:

| Variable                    | Default                 | Description                               |
|-----------------------------|-------------------------|-------------------------------------------|
| `CONTROL_PLANE_URL`         | `http://localhost:3000` | The base URL of the Control Plane.        |
| `CONTROL_PLANE_RECIPE_PORT` | `6433`                  | A free port on the host for the database. |

Each program checks that `CONTROL_PLANE_RECIPE_PORT` holds a number from 1 to
65535 before it sends any request, and exits with an error if it does not. The
following tabs show how each program reads its settings, and how it sends
a request to the server:

=== "Python"

    ```python
    # The or operator treats an empty variable as unset. The new database
    # listens on the given port on its host, so choose one that is free.
    BASE_URL = (os.environ.get("CONTROL_PLANE_URL") or "http://localhost:3000").rstrip("/")
    PORT_TEXT = os.environ.get("CONTROL_PLANE_RECIPE_PORT") or "6433"
    
    TIMEOUT_SECONDS = 30.0
    
    # How long to wait for a database to become available, or to disappear
    # after a delete, and how often to check.
    WAIT_SECONDS = 600
    POLL_SECONDS = 5
    
    
    class ControlPlaneError(Exception):
        """Raised when the Control Plane rejects a request or replies oddly.
        The status is the HTTP status of the reply, if there was one."""
    
        def __init__(self, message: str, status: int | None = None):
            super().__init__(message)
            self.status = status
    
    
    def call(client: httpx.Client, method: str, path: str, body: dict | None = None) -> dict:
        """Sends a request to the server, and returns the decoded reply."""
        response = client.request(method, path, json=body)
        if response.is_error:
            raise ControlPlaneError(
                f"HTTP {response.status_code}, {response.text[:200]}",
                response.status_code)
        try:
            reply = response.json()
            if isinstance(reply, dict):
                return reply
        except ValueError:
            pass
        raise ControlPlaneError(f"Unexpected response: {response.text[:200]}")
    ```

=== "TypeScript"

    ```typescript
    // The || operator, unlike ??, also treats an empty variable as unset. The
    // new database listens on the given port on its host, so choose one that
    // is free.
    const baseUrl = (process.env.CONTROL_PLANE_URL || "http://localhost:3000").replace(/\/+$/, "");
    const portText = process.env.CONTROL_PLANE_RECIPE_PORT || "6433";
    
    const timeoutMs = 30_000;
    
    // How long to wait for a database to become available, or to disappear
    // after a delete, and how often to check.
    const waitMs = 600_000;
    const pollMs = 5_000;
    
    // Ctrl-C and SIGTERM abort the signal below instead of ending the process,
    // which lets the program delete its database before it exits. The
    // handlers stay in place, so a further Ctrl-C does not end the process
    // during the cleanup either.
    const interrupt = new AbortController();
    for (const signalName of ["SIGINT", "SIGTERM"] as const) {
      process.on(signalName, () => interrupt.abort());
    }
    
    // An error reply from the Control Plane, with its HTTP status.
    class ControlPlaneError extends Error {
      constructor(
        message: string,
        readonly status?: number,
      ) {
        super(message);
      }
    }
    
    // Sends a request to the server, and returns the decoded reply. The
    // request stops when the user presses Ctrl-C, unless the caller passes a
    // different signal, as the cleanup does.
    async function call<T>(
      method: string,
      path: string,
      body?: unknown,
      signal: AbortSignal = interrupt.signal,
    ): Promise<T> {
      const response = await fetch(`${baseUrl}${path}`, {
        method,
        headers: body === undefined ? {} : { "Content-Type": "application/json" },
        body: body === undefined ? undefined : JSON.stringify(body),
        signal: AbortSignal.any([signal, AbortSignal.timeout(timeoutMs)]),
      });
    
      // fetch only rejects when it cannot reach the server; an error status
      // is a normal response, so check it explicitly.
      const text = await response.text();
      if (!response.ok) {
        throw new ControlPlaneError(
          `HTTP ${response.status}, ${text.slice(0, 200) || response.statusText}`,
          response.status,
        );
      }
      try {
        return JSON.parse(text) as T;
      } catch {
        throw new ControlPlaneError(`Unexpected response: ${text.slice(0, 200)}`);
      }
    }
    ```

=== "Java"

    ```java
    /** Returns the value of an environment variable, or a fallback. */
    static String envOr(String name, String fallback) {
        String value = System.getenv(name);
        return (value != null && !value.isEmpty()) ? value : fallback;
    }
    
    // The new database listens on the given port on its host, so choose
    // one that is free.
    static final String BASE_URL =
            envOr("CONTROL_PLANE_URL", "http://localhost:3000")
                    .replaceAll("/+$", "");
    static final String PORT = envOr("CONTROL_PLANE_RECIPE_PORT", "6433");
    
    static final Duration TIMEOUT = Duration.ofSeconds(30);
    
    // How long to wait for a database to become available, or to
    // disappear after a delete, and how often to check.
    static final Duration WAIT_FOR = Duration.ofSeconds(600);
    static final Duration POLL_INTERVAL = Duration.ofSeconds(5);
    
    /**
     * Thrown when the Control Plane rejects a request or replies oddly.
     * The status is the HTTP status of the reply, or 0 if there was none.
     */
    static class ControlPlaneException extends Exception {
        final int status;
    
        ControlPlaneException(String message, int status) {
            super(message);
            this.status = status;
        }
    
        ControlPlaneException(String message) {
            this(message, 0);
        }
    }
    
    // A client and a mapper are safe to share, so the program creates only
    // one of each.
    static final HttpClient CLIENT = HttpClient.newHttpClient();
    static final ObjectMapper MAPPER = JsonMapper.builder().build();
    
    /** Returns at most the first 200 characters of a reply. */
    static String shorten(String text) {
        return text.length() > 200 ? text.substring(0, 200) : text;
    }
    
    /**
     * Sends a request and returns the response with its whole body. The
     * request timeout stops applying once the headers arrive, so a server
     * that stalls part of the way through the body would hang send(); this
     * applies the same timeout to the whole exchange instead.
     */
    static HttpResponse<String> send(HttpRequest request)
            throws IOException, InterruptedException {
        CompletableFuture<HttpResponse<String>> pending =
                CLIENT.sendAsync(request, HttpResponse.BodyHandlers.ofString());
        try {
            return pending.get(TIMEOUT.toMillis(), TimeUnit.MILLISECONDS);
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
     * Sends a request to the server, with the body encoded as JSON if it
     * is not null, and returns the decoded reply.
     */
    static JsonNode call(String method, String path, Object body)
            throws IOException, InterruptedException, ControlPlaneException {
        HttpRequest.Builder builder = HttpRequest.newBuilder(URI.create(BASE_URL + path))
                .timeout(TIMEOUT);
        if (body == null) {
            builder.method(method, HttpRequest.BodyPublishers.noBody());
        } else {
            builder.header("Content-Type", "application/json")
                    .method(method, HttpRequest.BodyPublishers.ofString(
                            MAPPER.writeValueAsString(body)));
        }
        HttpResponse<String> response = send(builder.build());
        if (response.statusCode() >= 400) {
            throw new ControlPlaneException("HTTP " + response.statusCode()
                    + ", " + shorten(response.body()), response.statusCode());
        }
        try {
            JsonNode reply = MAPPER.readTree(response.body());
            if (reply.isObject()) {
                return reply;
            }
        } catch (JacksonException e) {
            // The body is not JSON; report it below.
        }
        throw new ControlPlaneException(
                "Unexpected response: " + shorten(response.body()));
    }
    ```

=== "C#"

    ```csharp
    // Returns the value of an environment variable, or a fallback if the
    // variable is unset or empty.
    static string EnvOr(string name, string fallback) =>
        Environment.GetEnvironmentVariable(name) is { Length: > 0 } value
            ? value
            : fallback;
    
    static string BaseUrl() =>
        EnvOr("CONTROL_PLANE_URL", "http://localhost:3000").TrimEnd('/');
    
    // The new database listens on the given port on its host, so choose one
    // that is free.
    static string PortText() => EnvOr("CONTROL_PLANE_RECIPE_PORT", "6433");
    
    const int TimeoutSeconds = 30;
    
    // How long to wait for a database to become available, or to disappear
    // after a delete, and how often to check.
    const int WaitSeconds = 600;
    const int PollSeconds = 5;
    
    // Returns at most the first 200 characters of a reply.
    static string Shorten(string text) =>
        text.Length > 200 ? text[..200] : text;
    
    // Sends a request to the server, with the body encoded as JSON if it is
    // not null, and returns the decoded reply. The token stops the request
    // when the user presses Ctrl-C.
    static async Task<JsonObject> CallAsync(
        HttpClient client, HttpMethod method, string path, object? body,
        CancellationToken token)
    {
        using var request = new HttpRequestMessage(method, BaseUrl() + path);
        if (body is not null)
        {
            request.Content = JsonContent.Create(body);
        }
        using var response = await client.SendAsync(request, token);
        var text = await response.Content.ReadAsStringAsync(token);
        if (!response.IsSuccessStatusCode)
        {
            throw new ControlPlaneException(
                $"HTTP {(int)response.StatusCode}, {Shorten(text)}",
                (int)response.StatusCode);
        }
        try
        {
            if (JsonNode.Parse(text) is JsonObject reply)
            {
                return reply;
            }
        }
        catch (JsonException)
        {
            // The body is not JSON; report it below.
        }
        throw new ControlPlaneException($"Unexpected response: {Shorten(text)}");
    }
    ```

=== "Go"

    ```go
    // envOr returns the value of an environment variable, or a fallback if
    // the variable is unset or empty.
    func envOr(name, fallback string) string {
    	if value := os.Getenv(name); value != "" {
    		return value
    	}
    	return fallback
    }
    
    // The new database listens on the given port on its host, so choose one
    // that is free.
    var (
    	baseURL  = strings.TrimRight(envOr("CONTROL_PLANE_URL", "http://localhost:3000"), "/")
    	portText = envOr("CONTROL_PLANE_RECIPE_PORT", "6433")
    )
    
    // parsePort returns the port number in text, and false unless text is a
    // plain decimal number from 1 to 65535.
    func parsePort(text string) (int, bool) {
    	number, err := strconv.Atoi(text)
    	if err != nil || number < 1 || number > 65535 || strconv.Itoa(number) != text {
    		return 0, false
    	}
    	return number, true
    }
    
    const timeout = 30 * time.Second
    
    // How long to wait for a database to become available, or to disappear
    // after a delete, and how often to check.
    const (
    	waitFor      = 600 * time.Second
    	pollInterval = 5 * time.Second
    )
    
    // apiError is an error reply from the Control Plane, with its HTTP status.
    type apiError struct {
    	status int
    	body   string
    }
    
    func (e *apiError) Error() string {
    	return fmt.Sprintf("HTTP %d, %.200s", e.status, e.body)
    }
    
    // statusOf returns the HTTP status of an error reply, or 0 if no reply
    // arrived.
    func statusOf(err error) int {
    	var apiErr *apiError
    	if errors.As(err, &apiErr) {
    		return apiErr.status
    	}
    	return 0
    }
    
    var client = &http.Client{Timeout: timeout}
    
    // call sends a request to the server, and decodes the reply into out if
    // out is not nil. The context stops the request when the user presses
    // Ctrl-C.
    func call(ctx context.Context, method, path string, body, out any) error {
    	var reader io.Reader
    	if body != nil {
    		encoded, err := json.Marshal(body)
    		if err != nil {
    			return err
    		}
    		reader = bytes.NewReader(encoded)
    	}
    	request, err := http.NewRequestWithContext(ctx, method, baseURL+path, reader)
    	if err != nil {
    		return err
    	}
    	if body != nil {
    		request.Header.Set("Content-Type", "application/json")
    	}
    
    	response, err := client.Do(request)
    	if err != nil {
    		return err
    	}
    	defer response.Body.Close()
    	reply, err := io.ReadAll(response.Body)
    	if err != nil {
    		return err
    	}
    
    	// Go treats an error status as a normal response, so check it here.
    	if response.StatusCode >= 400 {
    		return &apiError{response.StatusCode, strings.TrimSpace(string(reply))}
    	}
    	if out != nil {
    		if err := json.Unmarshal(reply, out); err != nil {
    			return fmt.Errorf("unexpected response: %.200s", reply)
    		}
    	}
    	return nil
    }
    
    // sleep waits for the poll interval, or until the context ends.
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
    /// Returns the value of an environment variable, or a fallback if the
    /// variable is unset or empty.
    fn env_or(name: &str, fallback: &str) -> String {
        env::var(name)
            .ok()
            .filter(|value| !value.is_empty())
            .unwrap_or_else(|| fallback.to_string())
    }
    
    fn base_url() -> String {
        env_or("CONTROL_PLANE_URL", "http://localhost:3000")
            .trim_end_matches('/')
            .to_string()
    }
    
    /// The port that the new database listens on, on its host; choose one
    /// that is free.
    fn port_text() -> String {
        env_or("CONTROL_PLANE_RECIPE_PORT", "6433")
    }
    
    /// Returns the port number in text, or None unless text is a plain
    /// decimal number from 1 to 65535.
    fn parse_port(text: &str) -> Option<u16> {
        let plain = !text.starts_with('0')
            && text.len() <= 5
            && text.bytes().all(|b| b.is_ascii_digit());
        if plain { text.parse().ok().filter(|&port| port > 0) } else { None }
    }
    
    const TIMEOUT: Duration = Duration::from_secs(30);
    
    // How long to wait for a database to become available, or to disappear
    // after a delete, and how often to check.
    const WAIT_FOR: Duration = Duration::from_secs(600);
    const POLL_INTERVAL: Duration = Duration::from_secs(5);
    
    /// Set by Ctrl-C or SIGTERM. The handler sets this flag instead of ending
    /// the process, which lets the program delete its database before it
    /// exits; the waits check it between requests.
    static INTERRUPTED: AtomicBool = AtomicBool::new(false);
    
    /// The errors that the functions below return; a string converts into one
    /// with the ? operator or into().
    type BoxError = Box<dyn Error>;
    
    /// An error reply from the Control Plane, with its HTTP status.
    #[derive(Debug)]
    struct ApiError {
        status: u16,
        body: String,
    }
    
    impl fmt::Display for ApiError {
        fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
            write!(f, "HTTP {}, {}", self.status, self.body)
        }
    }
    
    impl Error for ApiError {}
    
    /// Returns the HTTP status of an error reply, or None if no reply arrived
    /// or the error is of another kind.
    fn status_of(error: &BoxError) -> Option<u16> {
        error.downcast_ref::<ApiError>().map(|e| e.status)
    }
    
    /// Returns at most the first 200 characters of a reply.
    fn shorten(text: &str) -> String {
        text.chars().take(200).collect()
    }
    
    /// Sends a request to the server, with the body encoded as JSON if there
    /// is one, and returns the decoded reply.
    fn call(client: &Client, method: Method, path: &str, body: Option<&Value>) -> Result<Value, BoxError> {
        let mut request = client.request(method, format!("{}{path}", base_url()));
        if let Some(body) = body {
            request = request.json(body);
        }
        let response = request.send()?;
        let status = response.status();
        let text = response.text()?;
        if !status.is_success() {
            return Err(ApiError { status: status.as_u16(), body: shorten(&text) }.into());
        }
        match serde_json::from_str::<Value>(&text) {
            Ok(reply) if reply.is_object() => Ok(reply),
            _ => Err(format!("Unexpected response: {}", shorten(&text)).into()),
        }
    }
    
    /// Fails if the user has pressed Ctrl-C. A request does not stop for
    /// Ctrl-C, so the program checks the flag after each one.
    fn check_interrupted() -> Result<(), BoxError> {
        if INTERRUPTED.load(Ordering::SeqCst) {
            return Err("interrupted".into());
        }
        Ok(())
    }
    
    /// Waits for the poll interval, and fails if the user presses Ctrl-C.
    fn pause() -> Result<(), BoxError> {
        let end = Instant::now() + POLL_INTERVAL;
        while Instant::now() < end {
            check_interrupted()?;
            thread::sleep(Duration::from_millis(100));
        }
        Ok(())
    }
    ```

=== "Ruby"

    ```ruby
    # Returns the value of an environment variable, or a fallback if the
    # variable is unset or empty.
    def env_or(name, fallback)
      value = ENV[name]
      value.nil? || value.empty? ? fallback : value
    end
    
    # The new database listens on the given port on its host, so choose one
    # that is free.
    BASE_URL = env_or("CONTROL_PLANE_URL", "http://localhost:3000").sub(%r{/+\z}, "")
    PORT_TEXT = env_or("CONTROL_PLANE_RECIPE_PORT", "6433")
    
    TIMEOUT_SECONDS = 30
    
    # How long to wait for a database to become available, or to disappear
    # after a delete, and how often to check.
    WAIT_SECONDS = 600
    POLL_SECONDS = 5
    
    # Raised when the Control Plane rejects a request or replies oddly. The
    # status is the HTTP status of the reply, if there was one.
    class ControlPlaneError < StandardError
      attr_reader :status
    
      def initialize(message, status = nil)
        super(message)
        @status = status
      end
    end
    
    # The errors that mean no reply arrived: SystemCallError covers a refused
    # connection, Timeout::Error covers the connection and read timeouts, and
    # SocketError covers an unknown host.
    NETWORK_ERRORS = [SystemCallError, Timeout::Error, SocketError, IOError].freeze
    
    # Sends a request to the server, and returns the decoded reply.
    def call(method, path, body = nil)
      uri = URI("#{BASE_URL}#{path}")
      request = Net::HTTPGenericRequest.new(method, !body.nil?, true, uri)
      if body
        request["Content-Type"] = "application/json"
        request.body = JSON.generate(body)
      end
      # start opens a connection, and closes it when the block exits, whether
      # or not an error occurred.
      response = Net::HTTP.start(
        uri.host, uri.port,
        use_ssl: uri.scheme == "https",
        open_timeout: TIMEOUT_SECONDS, read_timeout: TIMEOUT_SECONDS
      ) { |http| http.request(request) }
      unless response.is_a?(Net::HTTPSuccess)
        raise ControlPlaneError.new(
          "HTTP #{response.code}, #{response.body.to_s[0, 200]}", response.code.to_i
        )
      end
    
      begin
        reply = JSON.parse(response.body.to_s)
        return reply if reply.is_a?(Hash)
      rescue JSON::ParserError
        # The body is not JSON; report it below.
      end
      raise ControlPlaneError, "Unexpected response: #{response.body.to_s[0, 200]}"
    end
    ```

=== "curl"

    ```bash
    # The :- expansion treats an empty variable as unset. The new database
    # listens on the given port on its host, so choose one that is free.
    base_url="${CONTROL_PLANE_URL:-http://localhost:3000}"
    base_url="${base_url%/}"
    port="${CONTROL_PLANE_RECIPE_PORT:-6433}"
    
    # How long to wait for a database to become available, or to disappear
    # after a delete, and how often to check.
    wait_seconds=600
    poll_seconds=5
    
    # Sends a request and prints the reply, followed by the HTTP status on a
    # line of its own; the status is 000 if no reply arrived. Any further
    # arguments go to curl, such as --data @- to send standard input as the
    # body.
    request() {
        local method="$1" path="$2"
        shift 2
        curl --silent --show-error --max-time 30 --request "$method" \
            --write-out '\n%{http_code}' "$@" "$base_url$path" || true
    }
    
    # Fetches a path from the server and prints the reply, or reports the
    # error and fails.
    get() {
        local reply status
        reply="$(request GET "$1")"
        status="${reply##*$'\n'}"
        if [[ "$status" != 200 ]]; then
            echo "Control Plane error: HTTP $status, ${reply%$'\n'*}" >&2
            return 1
        fi
        printf '%s\n' "${reply%$'\n'*}"
    }
    ```

## Choosing a Host

A database places each of its nodes on one or more hosts, which run the
Postgres containers. Each program places its single node on the first host in
the cluster. The following tabs show how each program finds the host:

=== "Python"

    ```python
    def first_host(client: httpx.Client) -> str:
        """Returns the ID of the first host in the cluster. A database places
        each of its nodes on one or more hosts, which run the Postgres
        containers."""
        hosts = call(client, "GET", "/v1/hosts").get("hosts") or []
        if not hosts:
            raise ControlPlaneError("the cluster has no hosts")
        return hosts[0]["id"]
    ```

=== "TypeScript"

    ```typescript
    // Returns the ID of the first host in the cluster. A database places each
    // of its nodes on one or more hosts, which run the Postgres containers.
    async function firstHost(): Promise<string> {
      const reply = await call<{ hosts?: { id: string }[] }>("GET", "/v1/hosts");
      const host = reply.hosts?.[0];
      if (!host) {
        throw new ControlPlaneError("the cluster has no hosts");
      }
      return host.id;
    }
    ```

=== "Java"

    ```java
    /**
     * Returns the ID of the first host in the cluster. A database places
     * each of its nodes on one or more hosts, which run the Postgres
     * containers.
     */
    static String firstHost()
            throws IOException, InterruptedException, ControlPlaneException {
        JsonNode hosts = call("GET", "/v1/hosts", null).path("hosts");
        if (hosts.isEmpty()) {
            throw new ControlPlaneException("the cluster has no hosts");
        }
        return hosts.get(0).path("id").asString();
    }
    ```

=== "C#"

    ```csharp
    // Returns the ID of the first host in the cluster. A database places each
    // of its nodes on one or more hosts, which run the Postgres containers.
    static async Task<string> FirstHostAsync(HttpClient client, CancellationToken token)
    {
        var reply = await CallAsync(client, HttpMethod.Get, "/v1/hosts", null, token);
        if (reply["hosts"] is not JsonArray { Count: > 0 } hosts ||
            hosts[0]?["id"]?.ToString() is not { } host)
        {
            throw new ControlPlaneException("the cluster has no hosts");
        }
        return host;
    }
    ```

=== "Go"

    ```go
    // firstHost returns the ID of the first host in the cluster. A database
    // places each of its nodes on one or more hosts, which run the Postgres
    // containers.
    func firstHost(ctx context.Context) (string, error) {
    	var reply struct {
    		Hosts []struct {
    			ID string `json:"id"`
    		} `json:"hosts"`
    	}
    	if err := call(ctx, http.MethodGet, "/v1/hosts", nil, &reply); err != nil {
    		return "", err
    	}
    	if len(reply.Hosts) == 0 {
    		return "", errors.New("the cluster has no hosts")
    	}
    	return reply.Hosts[0].ID, nil
    }
    
    ```

=== "Rust"

    ```rust
    /// Returns the ID of the first host in the cluster. A database places each
    /// of its nodes on one or more hosts, which run the Postgres containers.
    fn first_host(client: &Client) -> Result<String, BoxError> {
        let reply = call(client, Method::GET, "/v1/hosts", None)?;
        reply["hosts"][0]["id"]
            .as_str()
            .map(str::to_string)
            .ok_or_else(|| "the cluster has no hosts".into())
    }
    ```

=== "Ruby"

    ```ruby
    # Returns the ID of the first host in the cluster. A database places each
    # of its nodes on one or more hosts, which run the Postgres containers.
    def first_host
      host = (call("GET", "/v1/hosts")["hosts"] || []).first
      raise ControlPlaneError, "the cluster has no hosts" unless host
    
      host["id"]
    end
    ```

=== "curl"

    ```bash
    # Prints the ID of the first host in the cluster. A database places each of
    # its nodes on one or more hosts, which run the Postgres containers.
    first_host() {
        get /v1/hosts | jq -er '.hosts[0].id'
    }
    ```

## Creating the Database

The create request carries the ID and a specification of the database. Only
the database name and the nodes, each with its hosts, are required in the
specification; the program also sets the port that Postgres listens on, so
that it does not clash with another database on the host, and leaves out the
optional fields, such as the Postgres version. The following tabs show the
create request:

=== "Python"

    ```python
    def create_database(client: httpx.Client, database_id: str, host: str) -> None:
        """Asks the Control Plane to create a database with one node. The reply
        holds the database and the task that creates it; the work happens in
        the background after the reply."""
        call(client, "POST", "/v1/databases", {
            "id": database_id,
            "spec": {
                "database_name": "recipe",
                "port": int(PORT_TEXT),
                "nodes": [{"name": "n1", "host_ids": [host]}],
            },
        })
    ```

=== "TypeScript"

    ```typescript
    // Asks the Control Plane to create a database with one node. The reply
    // holds the database and the task that creates it; the work happens in the
    // background after the reply.
    async function createDatabase(databaseId: string, host: string): Promise<void> {
      await call("POST", "/v1/databases", {
        id: databaseId,
        spec: {
          database_name: "recipe",
          port: Number(portText),
          nodes: [{ name: "n1", host_ids: [host] }],
        },
      });
    }
    ```

=== "Java"

    ```java
    /**
     * Asks the Control Plane to create a database with one node. The reply
     * holds the database and the task that creates it; the work happens in
     * the background after the reply.
     */
    static void createDatabase(String databaseId, String host)
            throws IOException, InterruptedException, ControlPlaneException {
        Map<String, Object> body = Map.of(
                "id", databaseId,
                "spec", Map.of(
                        "database_name", "recipe",
                        "port", Integer.parseInt(PORT),
                        "nodes", List.of(Map.of(
                                "name", "n1",
                                "host_ids", List.of(host)))));
        call("POST", "/v1/databases", body);
    }
    ```

=== "C#"

    ```csharp
    // Asks the Control Plane to create a database with one node. The reply
    // holds the database and the task that creates it; the work happens in the
    // background after the reply.
    static async Task CreateDatabaseAsync(
        HttpClient client, string databaseId, string host, CancellationToken token)
    {
        var body = new
        {
            id = databaseId,
            spec = new
            {
                database_name = "recipe",
                port = int.Parse(PortText()),
                nodes = new[] { new { name = "n1", host_ids = new[] { host } } },
            },
        };
        await CallAsync(client, HttpMethod.Post, "/v1/databases", body, token);
    }
    ```

=== "Go"

    ```go
    // createDatabase asks the Control Plane to create a database with one
    // node. The reply holds the database and the task that creates it; the
    // work happens in the background after the reply.
    func createDatabase(ctx context.Context, databaseID, host string, port int) error {
    	body := map[string]any{
    		"id": databaseID,
    		"spec": map[string]any{
    			"database_name": "recipe",
    			"port":          port,
    			"nodes": []map[string]any{
    				{"name": "n1", "host_ids": []string{host}},
    			},
    		},
    	}
    	return call(ctx, http.MethodPost, "/v1/databases", body, nil)
    }
    
    ```

=== "Rust"

    ```rust
    /// Asks the Control Plane to create a database with one node. The reply
    /// holds the database and the task that creates it; the work happens in
    /// the background after the reply.
    fn create_database(
        client: &Client,
        database_id: &str,
        host: &str,
        port: u16,
    ) -> Result<(), BoxError> {
        let body = json!({
            "id": database_id,
            "spec": {
                "database_name": "recipe",
                "port": port,
                "nodes": [{"name": "n1", "host_ids": [host]}],
            },
        });
        call(client, Method::POST, "/v1/databases", Some(&body))?;
        Ok(())
    }
    ```

=== "Ruby"

    ```ruby
    # Asks the Control Plane to create a database with one node. The reply
    # holds the database and the task that creates it; the work happens in the
    # background after the reply.
    def create_database(database_id, host)
      call("POST", "/v1/databases", {
             id: database_id,
             spec: {
               database_name: "recipe",
               port: Integer(PORT_TEXT, 10),
               nodes: [{ name: "n1", host_ids: [host] }]
             }
           })
    end
    ```

=== "curl"

    ```bash
    # Asks the Control Plane to create a database with one node, and prints the
    # reply followed by the HTTP status, as request() does. The reply holds the
    # database and the task that creates it; the work happens in the
    # background after the reply.
    create_database() {
        local id="$1" host="$2"
        jq -n --arg id "$id" --arg host "$host" --argjson port "$port" \
            '{id: $id,
              spec: {database_name: "recipe",
                     port: $port,
                     nodes: [{name: "n1", host_ids: [$host]}]}}' |
            request POST /v1/databases \
                --header "Content-Type: application/json" --data @-
    }
    ```

## Waiting for the Database

Each program polls the database every five seconds, prints its state when the
state changes, and stops when the database is `available` or `failed`. The
`connection_info` of each instance holds the address and port that clients use;
an available database with no instances is reported as an error. The following
tabs show the wait:

=== "Python"

    ```python
    def wait_until_available(client: httpx.Client, database_id: str) -> int:
        """Polls the database, printing its state each time it changes, until
        the state is available, and returns the port of its first instance.
        Each instance runs one node, and its connection_info holds the address
        and port that clients use. A failed state ends the wait at once."""
        deadline = time.monotonic() + WAIT_SECONDS
        last = None
        while time.monotonic() < deadline:
            database = call(client, "GET", f"/v1/databases/{database_id}")
            state = database.get("state")
            if state != last:
                print(f"Database state: {state}")
                last = state
            if state == "available":
                instances = database.get("instances") or []
                if not instances:
                    raise ControlPlaneError("the database is available but has no instances")
                return instances[0]["connection_info"]["port"]
            if state == "failed":
                raise ControlPlaneError("the database has the state failed")
            time.sleep(POLL_SECONDS)
        raise ControlPlaneError(
            f"the database was not available after {WAIT_SECONDS} seconds")
    ```

=== "TypeScript"

    ```typescript
    interface Database {
      state?: string;
      instances?: { connection_info: { port: number } }[];
    }
    
    // Polls the database, printing its state each time it changes, until the
    // state is available, and returns the port of its first instance. Each
    // instance runs one node, and its connection_info holds the address and
    // port that clients use. A failed state ends the wait at once.
    async function waitUntilAvailable(databaseId: string): Promise<number> {
      const deadline = Date.now() + waitMs;
      let last: string | undefined;
      while (Date.now() < deadline) {
        const database = await call<Database>("GET", `/v1/databases/${databaseId}`);
        if (database.state !== last) {
          console.log(`Database state: ${database.state}`);
          last = database.state;
        }
        if (database.state === "available") {
          const instance = database.instances?.[0];
          if (!instance) {
            throw new ControlPlaneError("the database is available but has no instances");
          }
          return instance.connection_info.port;
        }
        if (database.state === "failed") {
          throw new ControlPlaneError("the database has the state failed");
        }
        await sleep(pollMs, undefined, { signal: interrupt.signal });
      }
      throw new ControlPlaneError(`the database was not available after ${waitMs / 1000} seconds`);
    }
    ```

=== "Java"

    ```java
    /**
     * Polls the database, printing its state each time it changes, until
     * the state is available, and returns the port of its first instance.
     * Each instance runs one node, and its connection_info holds the
     * address and port that clients use. A failed state ends the wait at
     * once.
     */
    static int waitUntilAvailable(String databaseId)
            throws IOException, InterruptedException, ControlPlaneException {
        long deadline = System.nanoTime() + WAIT_FOR.toNanos();
        String last = "";
        while (System.nanoTime() < deadline) {
            JsonNode database = call("GET", "/v1/databases/" + databaseId, null);
            String state = database.path("state").asString("");
            if (!state.equals(last)) {
                System.out.println("Database state: " + state);
                last = state;
            }
            if (state.equals("available")) {
                JsonNode instance = database.path("instances").path(0);
                if (instance.isMissingNode()) {
                    throw new ControlPlaneException(
                            "the database is available but has no instances");
                }
                return instance.path("connection_info").path("port").asInt();
            }
            if (state.equals("failed")) {
                throw new ControlPlaneException("the database has the state failed");
            }
            Thread.sleep(POLL_INTERVAL.toMillis());
        }
        throw new ControlPlaneException("the database was not available after "
                + WAIT_FOR.toSeconds() + " seconds");
    }
    ```

=== "C#"

    ```csharp
    // Polls the database, printing its state each time it changes, until the
    // state is available, and returns the port of its first instance. Each
    // instance runs one node, and its connection_info holds the address and
    // port that clients use. A failed state ends the wait at once.
    static async Task<string> WaitUntilAvailableAsync(
        HttpClient client, string databaseId, CancellationToken token)
    {
        var clock = Stopwatch.StartNew();
        string? last = null;
        while (clock.Elapsed.TotalSeconds < WaitSeconds)
        {
            var database = await CallAsync(
                client, HttpMethod.Get, $"/v1/databases/{databaseId}", null, token);
            var state = database["state"]?.ToString();
            if (state != last)
            {
                Console.WriteLine($"Database state: {state}");
                last = state;
            }
            if (state == "available")
            {
                if (database["instances"] is not JsonArray { Count: > 0 } instances)
                {
                    throw new ControlPlaneException(
                        "the database is available but has no instances");
                }
                return instances[0]?["connection_info"]?["port"]?.ToString() ?? "";
            }
            if (state == "failed")
            {
                throw new ControlPlaneException("the database has the state failed");
            }
            await Task.Delay(TimeSpan.FromSeconds(PollSeconds), token);
        }
        throw new ControlPlaneException(
            $"the database was not available after {WaitSeconds} seconds");
    }
    ```

=== "Go"

    ```go
    // waitUntilAvailable polls the database, printing its state each time it
    // changes, until the state is available, and returns the port of its
    // first instance. Each instance runs one node, and its connection_info
    // holds the address and port that clients use. A failed state ends the
    // wait at once.
    func waitUntilAvailable(ctx context.Context, databaseID string) (int, error) {
    	deadline := time.Now().Add(waitFor)
    	last := ""
    	for time.Now().Before(deadline) {
    		var database struct {
    			State     string `json:"state"`
    			Instances []struct {
    				ConnectionInfo struct {
    					Port int `json:"port"`
    				} `json:"connection_info"`
    			} `json:"instances"`
    		}
    		err := call(ctx, http.MethodGet, "/v1/databases/"+databaseID, nil, &database)
    		if err != nil {
    			return 0, err
    		}
    		if database.State != last {
    			fmt.Printf("Database state: %s\n", database.State)
    			last = database.State
    		}
    		switch {
    		case database.State == "available" && len(database.Instances) == 0:
    			return 0, errors.New("the database is available but has no instances")
    		case database.State == "available":
    			return database.Instances[0].ConnectionInfo.Port, nil
    		case database.State == "failed":
    			return 0, errors.New("the database has the state failed")
    		}
    		if err := sleep(ctx); err != nil {
    			return 0, err
    		}
    	}
    	return 0, fmt.Errorf("the database was not available after %v", waitFor)
    }
    
    ```

=== "Rust"

    ```rust
    /// Polls the database, printing its state each time it changes, until the
    /// state is available, and returns the port of its first instance. Each
    /// instance runs one node, and its connection_info holds the address and
    /// port that clients use. A failed state ends the wait at once.
    fn wait_until_available(client: &Client, database_id: &str) -> Result<u64, BoxError> {
        let deadline = Instant::now() + WAIT_FOR;
        let mut last = String::new();
        while Instant::now() < deadline {
            let database = call(client, Method::GET, &format!("/v1/databases/{database_id}"), None)?;
            check_interrupted()?;
            let state = database["state"].as_str().unwrap_or("unknown").to_string();
            if state != last {
                println!("Database state: {state}");
                last = state.clone();
            }
            if state == "available" {
                let instance = database["instances"]
                    .get(0)
                    .ok_or("the database is available but has no instances")?;
                return instance["connection_info"]["port"]
                    .as_u64()
                    .ok_or_else(|| "Unexpected response: missing port".into());
            }
            if state == "failed" {
                return Err("the database has the state failed".into());
            }
            pause()?;
        }
        Err(format!("the database was not available after {} seconds", WAIT_FOR.as_secs()).into())
    }
    ```

=== "Ruby"

    ```ruby
    # Polls the database, printing its state each time it changes, until the
    # state is available, and returns the port of its first instance. Each
    # instance runs one node, and its connection_info holds the address and
    # port that clients use. A failed state ends the wait at once.
    def wait_until_available(database_id)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + WAIT_SECONDS
      last = nil
      while Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
        database = call("GET", "/v1/databases/#{database_id}")
        state = database["state"]
        if state != last
          puts "Database state: #{state}"
          last = state
        end
        if state == "available"
          instance = (database["instances"] || []).first
          raise ControlPlaneError, "the database is available but has no instances" unless instance
    
          return instance.fetch("connection_info").fetch("port")
        end
        raise ControlPlaneError, "the database has the state failed" if state == "failed"
    
        sleep POLL_SECONDS
      end
      raise ControlPlaneError, "the database was not available after #{WAIT_SECONDS} seconds"
    end
    ```

=== "curl"

    ```bash
    # Polls the database, printing its state each time it changes, until the
    # state is available, and then sets available_port to the port of its
    # first instance. Each instance runs one node, and its connection_info
    # holds the address and port that clients use. A failed state ends the
    # wait at once.
    wait_until_available() {
        local id="$1" deadline=$((SECONDS + wait_seconds)) database state last=""
        while ((SECONDS < deadline)); do
            database="$(get "/v1/databases/$id")"
            state="$(jq -er '.state' <<<"$database")"
            if [[ "$state" != "$last" ]]; then
                echo "Database state: $state"
                last="$state"
            fi
            if [[ "$state" == "available" ]]; then
                available_port="$(jq -er '.instances[0].connection_info.port' <<<"$database")" || {
                    echo "Control Plane error: the database is available but has no instances" >&2
                    return 1
                }
                return 0
            fi
            if [[ "$state" == "failed" ]]; then
                echo "Control Plane error: the database has the state failed" >&2
                return 1
            fi
            sleep "$poll_seconds"
        done
        echo "Control Plane error: the database was not available after $wait_seconds seconds" >&2
        return 1
    }
    ```

## Deleting the Database

The delete request also starts a task, and the Control Plane answers 409 whilst
another task, such as the create, is still running, so each program repeats the
request until the server accepts it. The reply holds the delete task, and the
program then polls until the database is gone, which a 404 reply shows; whilst
the database is still there, it also checks the task, and stops with an error
if the task has `failed` or been `canceled`. The cleanup ignores Ctrl-C, so
that a second interrupt cannot leave the database behind. The following tabs
show the delete:

=== "Python"

    ```python
    def is_transient(error: Exception) -> bool:
        """Reports whether a failed request is worth repeating: no reply
        arrived, the server failed, or it answered 409, which the Control
        Plane does whilst another task, such as the create, is still running
        on the database."""
        if isinstance(error, httpx.TransportError):
            return True
        status = getattr(error, "status", None)
        return status is not None and (status == 409 or status >= 500)
    
    
    def delete_database(client: httpx.Client, database_id: str) -> None:
        """Deletes the database and waits until the API no longer has it. A
        404 means that the database is already gone."""
        path = f"/v1/databases/{database_id}"
        deadline = time.monotonic() + WAIT_SECONDS
        while True:
            try:
                task_id = call(client, "DELETE", path)["task"]["task_id"]
                break
            except (httpx.TransportError, ControlPlaneError) as e:
                if getattr(e, "status", None) == 404:
                    return
                if not is_transient(e) or time.monotonic() >= deadline:
                    raise
                time.sleep(POLL_SECONDS)
    
        # The delete starts a task that removes the database; a 404 shows that
        # it has finished. Whilst the database is still there, the status of
        # the task shows whether the delete failed.
        while time.monotonic() < deadline:
            try:
                call(client, "GET", path)
                status = call(client, "GET", f"{path}/tasks/{task_id}").get("status")
                if status in ("failed", "canceled"):
                    raise ControlPlaneError(
                        f"the delete task finished with the status {status}")
            except (httpx.TransportError, ControlPlaneError) as e:
                if getattr(e, "status", None) == 404:
                    return
                if not is_transient(e):
                    raise
            time.sleep(POLL_SECONDS)
        raise ControlPlaneError(
            f"the database was still present after {WAIT_SECONDS} seconds")
    ```

=== "TypeScript"

    ```typescript
    // Reports whether a failed request is worth repeating: no reply arrived,
    // the server failed, or it answered 409, which the Control Plane does
    // whilst another task, such as the create, is still running on the
    // database.
    function isTransient(err: unknown): boolean {
      if (!(err instanceof ControlPlaneError)) {
        return true;
      }
      return err.status !== undefined && (err.status === 409 || err.status >= 500);
    }
    
    function isGone(err: unknown): boolean {
      return err instanceof ControlPlaneError && err.status === 404;
    }
    
    // Deletes the database and waits until the API no longer has it. A 404
    // means that the database is already gone. The cleanup runs after Ctrl-C,
    // so its requests and waits use a signal that never aborts.
    async function deleteDatabase(databaseId: string): Promise<void> {
      const never = new AbortController().signal;
      const path = `/v1/databases/${databaseId}`;
      const deadline = Date.now() + waitMs;
      let taskId: string;
      for (;;) {
        try {
          const reply = await call<{ task: { task_id: string } }>("DELETE", path, undefined, never);
          taskId = reply.task.task_id;
          break;
        } catch (err) {
          if (isGone(err)) {
            return;
          }
          if (!isTransient(err) || Date.now() >= deadline) {
            throw err;
          }
          await sleep(pollMs);
        }
      }
    
      // The delete starts a task that removes the database; a 404 shows that
      // it has finished. Whilst the database is still there, the status of the
      // task shows whether the delete failed.
      while (Date.now() < deadline) {
        try {
          await call("GET", path, undefined, never);
          const task = await call<{ status: string }>("GET", `${path}/tasks/${taskId}`, undefined, never);
          if (task.status === "failed" || task.status === "canceled") {
            throw new ControlPlaneError(`the delete task finished with the status ${task.status}`);
          }
        } catch (err) {
          if (isGone(err)) {
            return;
          }
          if (!isTransient(err)) {
            throw err;
          }
        }
        await sleep(pollMs);
      }
      throw new ControlPlaneError(`the database was still present after ${waitMs / 1000} seconds`);
    }
    ```

=== "Java"

    ```java
    /**
     * Reports whether a failed request is worth repeating: no reply
     * arrived, the server failed, or it answered 409, which the Control
     * Plane does whilst another task, such as the create, is still running
     * on the database.
     */
    static boolean isTransient(Exception e) {
        if (e instanceof ControlPlaneException cpe) {
            return cpe.status == 409 || cpe.status >= 500;
        }
        return e instanceof IOException;
    }
    
    static boolean isGone(Exception e) {
        return e instanceof ControlPlaneException cpe && cpe.status == 404;
    }
    
    /**
     * Deletes the database and waits until the API no longer has it. A 404
     * means that the database is already gone.
     */
    static void deleteDatabase(String databaseId)
            throws IOException, InterruptedException, ControlPlaneException {
        String path = "/v1/databases/" + databaseId;
        long deadline = System.nanoTime() + WAIT_FOR.toNanos();
        String taskId;
        while (true) {
            try {
                taskId = call("DELETE", path, null).path("task").path("task_id").asString("");
                break;
            } catch (IOException | ControlPlaneException e) {
                if (isGone(e)) {
                    return;
                }
                if (!isTransient(e) || System.nanoTime() >= deadline) {
                    throw e;
                }
            }
            Thread.sleep(POLL_INTERVAL.toMillis());
        }
    
        if (taskId.isEmpty()) {
            throw new ControlPlaneException("the delete reply has no task");
        }
    
        // The delete starts a task that removes the database; a 404 shows
        // that it has finished. Whilst the database is still there, the
        // status of the task shows whether the delete failed.
        while (System.nanoTime() < deadline) {
            try {
                call("GET", path, null);
                String status = call("GET", path + "/tasks/" + taskId, null)
                        .path("status").asString("");
                if (status.equals("failed") || status.equals("canceled")) {
                    throw new ControlPlaneException(
                            "the delete task finished with the status " + status);
                }
            } catch (IOException | ControlPlaneException e) {
                if (isGone(e)) {
                    return;
                }
                if (!isTransient(e)) {
                    throw e;
                }
            }
            Thread.sleep(POLL_INTERVAL.toMillis());
        }
        throw new ControlPlaneException("the database was still present after "
                + WAIT_FOR.toSeconds() + " seconds");
    }
    ```

=== "C#"

    ```csharp
    // Reports whether a failed request is worth repeating: no reply arrived,
    // the server failed, or it answered 409, which the Control Plane does
    // whilst another task, such as the create, is still running on the
    // database. TaskCanceledException is a timeout here, because the cleanup
    // does not pass a token that can be cancelled.
    static bool IsTransient(Exception e) => e switch
    {
        ControlPlaneException cpe => cpe.Status is 409 or >= 500,
        HttpRequestException or TaskCanceledException => true,
        _ => false,
    };
    
    // Deletes the database and waits until the API no longer has it. A 404
    // means that the database is already gone. The cleanup runs after Ctrl-C,
    // so it uses no cancellation token.
    static async Task DeleteDatabaseAsync(HttpClient client, string databaseId)
    {
        var path = $"/v1/databases/{databaseId}";
        var clock = Stopwatch.StartNew();
        string taskId;
        while (true)
        {
            try
            {
                var reply = await CallAsync(
                    client, HttpMethod.Delete, path, null, CancellationToken.None);
                taskId = reply["task"]?["task_id"]?.ToString()
                    ?? throw new ControlPlaneException("the delete reply has no task");
                break;
            }
            catch (ControlPlaneException e) when (e.Status == 404)
            {
                return;
            }
            catch (Exception e) when (IsTransient(e) && clock.Elapsed.TotalSeconds < WaitSeconds)
            {
                await Task.Delay(TimeSpan.FromSeconds(PollSeconds));
            }
        }
    
        // The delete starts a task that removes the database; a 404 shows that
        // it has finished. Whilst the database is still there, the status of the
        // task shows whether the delete failed.
        while (clock.Elapsed.TotalSeconds < WaitSeconds)
        {
            try
            {
                await CallAsync(client, HttpMethod.Get, path, null, CancellationToken.None);
                var task = await CallAsync(
                    client, HttpMethod.Get, $"{path}/tasks/{taskId}", null, CancellationToken.None);
                var status = task["status"]?.ToString();
                if (status is "failed" or "canceled")
                {
                    throw new ControlPlaneException(
                        $"the delete task finished with the status {status}");
                }
            }
            catch (ControlPlaneException e) when (e.Status == 404)
            {
                return;
            }
            catch (Exception e) when (IsTransient(e))
            {
                // Check again after the pause.
            }
            await Task.Delay(TimeSpan.FromSeconds(PollSeconds));
        }
        throw new ControlPlaneException(
            $"the database was still present after {WaitSeconds} seconds");
    }
    ```

=== "Go"

    ```go
    // isTransient reports whether a failed request is worth repeating: no
    // reply arrived, the server failed, or it answered 409, which the Control
    // Plane does whilst another task, such as the create, is still running on
    // the database.
    func isTransient(err error) bool {
    	status := statusOf(err)
    	return status == 0 || status == http.StatusConflict || status >= 500
    }
    
    // deleteDatabase deletes the database and waits until the API no longer
    // has it. A 404 means that the database is already gone. The cleanup runs
    // after Ctrl-C, so it uses a context that never ends.
    func deleteDatabase(databaseID string) error {
    	ctx := context.Background()
    	path := "/v1/databases/" + databaseID
    	deadline := time.Now().Add(waitFor)
    	var reply struct {
    		Task struct {
    			TaskID string `json:"task_id"`
    		} `json:"task"`
    	}
    	for {
    		err := call(ctx, http.MethodDelete, path, nil, &reply)
    		if err == nil {
    			break
    		}
    		if statusOf(err) == http.StatusNotFound {
    			return nil
    		}
    		if !isTransient(err) || time.Now().After(deadline) {
    			return err
    		}
    		time.Sleep(pollInterval)
    	}
    
    	// The delete starts a task that removes the database; a 404 shows that
    	// it has finished. Whilst the database is still there, the status of
    	// the task shows whether the delete failed.
    	for time.Now().Before(deadline) {
    		err := call(ctx, http.MethodGet, path, nil, nil)
    		if err == nil {
    			var task struct {
    				Status string `json:"status"`
    			}
    			err = call(ctx, http.MethodGet, path+"/tasks/"+reply.Task.TaskID, nil, &task)
    			if err == nil && (task.Status == "failed" || task.Status == "canceled") {
    				return fmt.Errorf("the delete task finished with the status %s", task.Status)
    			}
    		}
    		if statusOf(err) == http.StatusNotFound {
    			return nil
    		}
    		if err != nil && !isTransient(err) {
    			return err
    		}
    		time.Sleep(pollInterval)
    	}
    	return fmt.Errorf("the database was still present after %v", waitFor)
    }
    
    ```

=== "Rust"

    ```rust
    /// Reports whether a failed request is worth repeating: no reply arrived,
    /// the server failed, or it answered 409, which the Control Plane does
    /// whilst another task, such as the create, is still running on the
    /// database.
    fn is_transient(error: &BoxError) -> bool {
        match status_of(error) {
            Some(status) => status == 409 || status >= 500,
            None => error.is::<reqwest::Error>(),
        }
    }
    
    /// Deletes the database and waits until the API no longer has it. A 404
    /// means that the database is already gone. The cleanup runs after
    /// Ctrl-C, so its waits do not check the flag.
    fn delete_database(client: &Client, database_id: &str) -> Result<(), BoxError> {
        let path = format!("/v1/databases/{database_id}");
        let deadline = Instant::now() + WAIT_FOR;
        let task_id = loop {
            match call(client, Method::DELETE, &path, None) {
                Ok(reply) => break reply["task"]["task_id"].as_str().unwrap_or_default().to_string(),
                Err(e) if status_of(&e) == Some(404) => return Ok(()),
                Err(e) if !is_transient(&e) || Instant::now() >= deadline => return Err(e),
                Err(_) => thread::sleep(POLL_INTERVAL),
            }
        };
        if task_id.is_empty() {
            return Err("the delete reply has no task".into());
        }
    
        // The delete starts a task that removes the database; a 404 shows that
        // it has finished. Whilst the database is still there, the status of
        // the task shows whether the delete failed.
        let task_path = format!("{path}/tasks/{task_id}");
        while Instant::now() < deadline {
            let polled = call(client, Method::GET, &path, None)
                .and_then(|_| call(client, Method::GET, &task_path, None));
            match polled {
                Ok(task) if matches!(task["status"].as_str(), Some("failed" | "canceled")) => {
                    let status = task["status"].as_str().unwrap_or_default();
                    return Err(format!("the delete task finished with the status {status}").into());
                }
                Err(e) if status_of(&e) == Some(404) => return Ok(()),
                Err(e) if !is_transient(&e) => return Err(e),
                _ => thread::sleep(POLL_INTERVAL),
            }
        }
        Err(format!("the database was still present after {} seconds", WAIT_FOR.as_secs()).into())
    }
    ```

=== "Ruby"

    ```ruby
    # Reports whether a failed request is worth repeating: no reply arrived,
    # the server failed, or it answered 409, which the Control Plane does
    # whilst another task, such as the create, is still running on the
    # database.
    def transient?(error)
      return true unless error.is_a?(ControlPlaneError)
    
      !error.status.nil? && (error.status == 409 || error.status >= 500)
    end
    
    # Deletes the database and waits until the API no longer has it. A 404
    # means that the database is already gone.
    def delete_database(database_id)
      path = "/v1/databases/#{database_id}"
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + WAIT_SECONDS
      begin
        task_id = call("DELETE", path).fetch("task").fetch("task_id")
      rescue ControlPlaneError, *NETWORK_ERRORS => e
        return if e.is_a?(ControlPlaneError) && e.status == 404
        raise if !transient?(e) || Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
    
        sleep POLL_SECONDS
        retry
      end
    
      # The delete starts a task that removes the database; a 404 shows that
      # it has finished. Whilst the database is still there, the status of the
      # task shows whether the delete failed.
      while Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
        begin
          call("GET", path)
          status = call("GET", "#{path}/tasks/#{task_id}")["status"]
          if %w[failed canceled].include?(status)
            raise ControlPlaneError, "the delete task finished with the status #{status}"
          end
        rescue ControlPlaneError, *NETWORK_ERRORS => e
          return if e.is_a?(ControlPlaneError) && e.status == 404
          raise unless transient?(e)
        end
        sleep POLL_SECONDS
      end
      raise ControlPlaneError, "the database was still present after #{WAIT_SECONDS} seconds"
    end
    ```

=== "curl"

    ```bash
    # Deletes the database and waits until the API no longer has it. The
    # Control Plane answers 409 whilst another task, such as the create, is
    # still running on the database, so the script repeats the request, as it
    # does when no reply arrived or the server failed. A 404 means that the
    # database is already gone.
    delete_database() {
        local id="$1" deadline=$((SECONDS + wait_seconds)) reply status
        local task_id task_status
    
        while true; do
            reply="$(request DELETE "/v1/databases/$id")"
            status="${reply##*$'\n'}"
            case "$status" in
                200) task_id="$(jq -er '.task.task_id' <<<"${reply%$'\n'*}")" || {
                         echo "Control Plane error: Unexpected response: ${reply%$'\n'*}" >&2
                         return 1
                     }
                     break ;;
                404) return 0 ;;
                000|409|5??) ;;
                *) echo "Control Plane error: HTTP $status, ${reply%$'\n'*}" >&2
                   return 1 ;;
            esac
            if ((SECONDS >= deadline)); then
                echo "Control Plane error: the delete was still failing after $wait_seconds seconds" >&2
                return 1
            fi
            sleep "$poll_seconds"
        done
    
        # The delete starts a task that removes the database; a 404 shows that
        # it has finished. Whilst the database is still there, the status of
        # the task shows whether the delete failed.
        while true; do
            reply="$(request GET "/v1/databases/$id")"
            status="${reply##*$'\n'}"
            case "$status" in
                404) return 0 ;;
                200) reply="$(request GET "/v1/databases/$id/tasks/$task_id")"
                     if [[ "${reply##*$'\n'}" == 200 ]]; then
                         task_status="$(jq -r '.status // empty' <<<"${reply%$'\n'*}")"
                         if [[ "$task_status" == failed || "$task_status" == canceled ]]; then
                             echo "Control Plane error: the delete task finished with the status $task_status" >&2
                             return 1
                         fi
                     fi ;;
                000|5??) ;;
                *) echo "Control Plane error: HTTP $status, ${reply%$'\n'*}" >&2
                   return 1 ;;
            esac
            if ((SECONDS >= deadline)); then
                echo "Control Plane error: the database was still present after $wait_seconds seconds" >&2
                return 1
            fi
            sleep "$poll_seconds"
        done
    }
    ```

## Handling Errors

The main part of each program creates the database and waits for it, then
deletes it whether the example succeeded, failed, or was interrupted. Ctrl-C
and `SIGTERM` stop the example without ending the process, so that the cleanup
can run. The program sets a flag before the create request, because the
database may exist even when no reply arrives, and clears it only if the server
refuses the request with a 4xx status, which means that it created nothing. If
the delete fails, the program names the database to delete by hand. The
following tabs show the main part of each program:

=== "Python"

    ```python
    def stop(*_) -> None:
        """Handles SIGTERM like Ctrl-C, by raising KeyboardInterrupt."""
        raise KeyboardInterrupt
    
    
    def main() -> int:
        # The new database listens on this port, so check it before creating
        # anything.
        if not re.fullmatch(r"[1-9][0-9]{0,4}", PORT_TEXT) or int(PORT_TEXT) > 65535:
            print("CONTROL_PLANE_RECIPE_PORT must be a port number from 1 to 65535",
                  file=sys.stderr)
            return 1
    
        # Turn SIGTERM into a KeyboardInterrupt, so that the finally block
        # runs, as it does for Ctrl-C.
        signal.signal(signal.SIGTERM, stop)
    
        exit_code = 0
        created = False
        # The client chooses the ID of a new database, so the program knows it
        # before the request, and can delete the database even if the reply
        # never arrives. The random suffix keeps the ID unique.
        database_id = f"cookbook-recipe-{secrets.token_hex(3)}"
        with httpx.Client(base_url=BASE_URL, timeout=TIMEOUT_SECONDS) as client:
            try:
                host = first_host(client)
                print(f"Host: {host}")
    
                # Clean up unless the server refused the request with a 4xx
                # status, which means it created nothing; a 409, for example,
                # means that a database with this ID already exists, and is
                # not this program's to delete.
                created = True
                try:
                    create_database(client, database_id, host)
                except ControlPlaneError as e:
                    if e.status is not None and 400 <= e.status < 500:
                        created = False
                    raise
                print(f"Created database {database_id}")
    
                port = wait_until_available(client, database_id)
                print(f"Database is available on port {port}")
            # httpx.HTTPError is the base class for failures to reach the
            # server, such as a refused connection or a timeout.
            except (httpx.HTTPError, ControlPlaneError, KeyError) as e:
                print(f"Control Plane error: {e}", file=sys.stderr)
                exit_code = 1
            except KeyboardInterrupt:
                print("Interrupted", file=sys.stderr)
                exit_code = 130
            finally:
                # Delete the database whether the example succeeded, failed, or
                # was interrupted. Ignore further interrupts, so that they
                # cannot cut the cleanup short.
                signal.signal(signal.SIGINT, signal.SIG_IGN)
                signal.signal(signal.SIGTERM, signal.SIG_IGN)
                if created:
                    try:
                        delete_database(client, database_id)
                        print("Deleted database")
                    except (httpx.HTTPError, ControlPlaneError, KeyError) as e:
                        print(f"Control Plane error: {e}", file=sys.stderr)
                        print(f"Delete the database {database_id} by hand",
                              file=sys.stderr)
                        exit_code = 1
    
        return exit_code
    
    
    if __name__ == "__main__":
        sys.exit(main())
    ```

=== "TypeScript"

    ```typescript
    // Returns a readable description of an error. fetch reports a connection
    // failure as a TypeError with the cause (often an AggregateError, whose
    // own message is empty) attached.
    function describe(err: unknown): string {
      if (err instanceof AggregateError) {
        return err.errors.map(describe).join("; ");
      }
      if (err instanceof Error) {
        return err.cause ? `${err.message}: ${describe(err.cause)}` : err.message;
      }
      return String(err);
    }
    
    async function main(): Promise<number> {
      // The new database listens on this port, so check it before creating
      // anything.
      if (!/^[1-9][0-9]{0,4}$/.test(portText) || Number(portText) > 65535) {
        console.error("CONTROL_PLANE_RECIPE_PORT must be a port number from 1 to 65535");
        return 1;
      }
    
      let exitCode = 0;
      let created = false;
      // The client chooses the ID of a new database, so the program knows it
      // before the request, and can delete the database even if the reply
      // never arrives. The random suffix keeps the ID unique.
      const databaseId = `cookbook-recipe-${randomBytes(3).toString("hex")}`;
      try {
        const host = await firstHost();
        console.log(`Host: ${host}`);
    
        // Clean up unless the server refused the request with a 4xx status,
        // which means it created nothing; a 409, for example, means that a
        // database with this ID already exists, and is not this program's to
        // delete.
        created = true;
        try {
          await createDatabase(databaseId, host);
        } catch (err) {
          if (err instanceof ControlPlaneError && err.status && err.status < 500) {
            created = false;
          }
          throw err;
        }
        console.log(`Created database ${databaseId}`);
    
        const instancePort = await waitUntilAvailable(databaseId);
        console.log(`Database is available on port ${instancePort}`);
        // A signal that arrives after the last request still counts.
        if (interrupt.signal.aborted) {
          throw new Error("Interrupted");
        }
      } catch (err) {
        if (interrupt.signal.aborted) {
          console.error("Interrupted");
          exitCode = 130;
        } else {
          console.error(`Control Plane error: ${describe(err)}`);
          exitCode = 1;
        }
      } finally {
        // Delete the database whether the example succeeded, failed, or was
        // interrupted.
        if (created) {
          try {
            await deleteDatabase(databaseId);
            console.log("Deleted database");
          } catch (err) {
            console.error(`Control Plane error: ${describe(err)}`);
            console.error(`Delete the database ${databaseId} by hand`);
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
    // Ctrl-C and SIGTERM start the JVM's shutdown, which runs the hook
    // below and then ends the process. The hook interrupts the main thread
    // and waits until it has deleted the database. The lock and the
    // cleaning flag stop the hook from interrupting the cleanup itself.
    static final Object LOCK = new Object();
    static final CountDownLatch FINISHED = new CountDownLatch(1);
    static boolean cleaning = false;
    static volatile boolean shuttingDown = false;
    
    public static void main(String[] args) {
        // The new database listens on this port, so check it before
        // creating anything.
        if (!PORT.matches("[1-9][0-9]{0,4}") || Integer.parseInt(PORT) > 65535) {
            System.err.println("CONTROL_PLANE_RECIPE_PORT must be a port number from 1 to 65535");
            System.exit(1);
        }
    
        Thread mainThread = Thread.currentThread();
        Runtime.getRuntime().addShutdownHook(new Thread(() -> {
            shuttingDown = true;
            synchronized (LOCK) {
                if (!cleaning) {
                    mainThread.interrupt();
                }
            }
            try {
                FINISHED.await();
            } catch (InterruptedException e) {
                // The JVM is ending anyway.
            }
        }));
    
        int exitCode = 0;
        boolean created = false;
        // The client chooses the ID of a new database, so the program knows
        // it before the request, and can delete the database even if the
        // reply never arrives. The random suffix keeps the ID unique.
        byte[] suffix = new byte[3];
        new SecureRandom().nextBytes(suffix);
        String databaseId = "cookbook-recipe-" + HexFormat.of().formatHex(suffix);
        try {
            String host = firstHost();
            System.out.println("Host: " + host);
    
            // Clean up unless the server refused the request with a 4xx
            // status, which means it created nothing; a 409, for example,
            // means that a database with this ID already exists, and is not
            // this program's to delete.
            created = true;
            try {
                createDatabase(databaseId, host);
            } catch (ControlPlaneException e) {
                if (e.status >= 400 && e.status < 500) {
                    created = false;
                }
                throw e;
            }
            System.out.println("Created database " + databaseId);
    
            int port = waitUntilAvailable(databaseId);
            System.out.println("Database is available on port " + port);
        } catch (InterruptedException e) {
            System.err.println("Interrupted");
            exitCode = 130;
        // IOException covers failures to reach the server, such as a
        // refused connection or a timeout. The message of a refused
        // connection can be empty, so print the exception itself, which
        // includes its type.
        } catch (IOException e) {
            System.err.println("Control Plane error: " + e);
            exitCode = 1;
        } catch (ControlPlaneException | RuntimeException e) {
            System.err.println("Control Plane error: " + e.getMessage());
            exitCode = 1;
        } finally {
            // From here on, a signal does not interrupt the main thread, and
            // any interrupt that arrived before this point is cleared, so
            // that the cleanup can wait between its requests.
            synchronized (LOCK) {
                cleaning = true;
                // A signal that arrived after the last request still counts.
                if (Thread.interrupted() && exitCode == 0) {
                    System.err.println("Interrupted");
                    exitCode = 130;
                }
            }
            // Delete the database whether the example succeeded, failed, or
            // was interrupted.
            if (created) {
                try {
                    deleteDatabase(databaseId);
                    System.out.println("Deleted database");
                } catch (IOException | InterruptedException | ControlPlaneException e) {
                    System.err.println("Control Plane error: " + e);
                    System.err.println("Delete the database " + databaseId + " by hand");
                    exitCode = 1;
                }
            }
        }
    
        System.out.flush();
        FINISHED.countDown();
        // Once the JVM has started to shut down, System.exit() would wait
        // for the hook forever, so after a signal the program halts with
        // its exit code instead.
        if (shuttingDown) {
            Runtime.getRuntime().halt(exitCode);
        }
        System.exit(exitCode);
    }
    ```

=== "C#"

    ```csharp
    // The new database listens on this port, so check it before creating
    // anything.
    if (!Regex.IsMatch(PortText(), @"^[1-9][0-9]{0,4}\z") || int.Parse(PortText()) > 65535)
    {
        Console.Error.WriteLine("CONTROL_PLANE_RECIPE_PORT must be a port number from 1 to 65535");
        return 1;
    }
    
    // Ctrl-C and SIGTERM cancel the token below instead of ending the process,
    // which lets the program delete its database before it exits. The
    // registrations stay in place, so a further Ctrl-C does not end the
    // process during the cleanup either.
    using var interrupt = new CancellationTokenSource();
    void OnSignal(PosixSignalContext context)
    {
        context.Cancel = true;
        interrupt.Cancel();
    }
    using var sigint = PosixSignalRegistration.Create(PosixSignal.SIGINT, OnSignal);
    using var sigterm = PosixSignalRegistration.Create(PosixSignal.SIGTERM, OnSignal);
    
    // using disposes of the client, and closes its connections, when the
    // program ends.
    using var client = new HttpClient
    {
        Timeout = TimeSpan.FromSeconds(TimeoutSeconds),
    };
    
    var exitCode = 0;
    var created = false;
    // The client chooses the ID of a new database, so the program knows it
    // before the request, and can delete the database even if the reply never
    // arrives. The random suffix keeps the ID unique.
    var databaseId = $"cookbook-recipe-{Convert.ToHexStringLower(RandomNumberGenerator.GetBytes(3))}";
    try
    {
        var host = await FirstHostAsync(client, interrupt.Token);
        Console.WriteLine($"Host: {host}");
    
        // Clean up unless the server refused the request with a 4xx status,
        // which means it created nothing; a 409, for example, means that a
        // database with this ID already exists, and is not this program's to
        // delete.
        created = true;
        try
        {
            await CreateDatabaseAsync(client, databaseId, host, interrupt.Token);
        }
        catch (ControlPlaneException e) when (e.Status is >= 400 and < 500)
        {
            created = false;
            throw;
        }
        Console.WriteLine($"Created database {databaseId}");
    
        var port = await WaitUntilAvailableAsync(client, databaseId, interrupt.Token);
        Console.WriteLine($"Database is available on port {port}");
        // A signal that arrives after the last request still counts.
        interrupt.Token.ThrowIfCancellationRequested();
    }
    catch (OperationCanceledException) when (interrupt.IsCancellationRequested)
    {
        Console.Error.WriteLine("Interrupted");
        exitCode = 130;
    }
    // HttpRequestException covers failures to reach the server, such as a
    // refused connection, and TaskCanceledException covers a timeout.
    catch (Exception e) when (
        e is HttpRequestException or TaskCanceledException or ControlPlaneException)
    {
        Console.Error.WriteLine($"Control Plane error: {e.Message}");
        exitCode = 1;
    }
    finally
    {
        // Delete the database whether the example succeeded, failed, or was
        // interrupted.
        if (created)
        {
            try
            {
                await DeleteDatabaseAsync(client, databaseId);
                Console.WriteLine("Deleted database");
            }
            catch (Exception e) when (
                e is HttpRequestException or TaskCanceledException or ControlPlaneException)
            {
                Console.Error.WriteLine($"Control Plane error: {e.Message}");
                Console.Error.WriteLine($"Delete the database {databaseId} by hand");
                exitCode = 1;
            }
        }
    }
    return exitCode;
    
    // C# requires type declarations to follow the top-level statements, so
    // the exception that the program throws for an error reply is declared
    // here, at the end. The status is the HTTP status of the reply, or 0 if
    // there was none.
    class ControlPlaneException(string message, int status = 0) : Exception(message)
    {
        public int Status { get; } = status;
    }
    ```

=== "Go"

    ```go
    // run creates the database and waits for it, and returns any error to the
    // caller. It sets created once the database may exist, so that the caller
    // knows whether to delete it.
    func run(ctx context.Context, databaseID string, port int, created *bool) error {
    	host, err := firstHost(ctx)
    	if err != nil {
    		return err
    	}
    	fmt.Printf("Host: %s\n", host)
    
    	// Clean up unless the server refused the request with a 4xx status,
    	// which means it created nothing; a 409, for example, means that a
    	// database with this ID already exists, and is not this program's to
    	// delete.
    	*created = true
    	if err := createDatabase(ctx, databaseID, host, port); err != nil {
    		if status := statusOf(err); status >= 400 && status < 500 {
    			*created = false
    		}
    		return err
    	}
    	fmt.Printf("Created database %s\n", databaseID)
    
    	instancePort, err := waitUntilAvailable(ctx, databaseID)
    	if err != nil {
    		return err
    	}
    	fmt.Printf("Database is available on port %d\n", instancePort)
    	return nil
    }
    
    // main deletes the database whether the example succeeded, failed, or was
    // interrupted, and exits with a non-zero status after a failure.
    func main() {
    	// The new database listens on this port, so check it before creating
    	// anything.
    	port, ok := parsePort(portText)
    	if !ok {
    		fmt.Fprintln(os.Stderr, "CONTROL_PLANE_RECIPE_PORT must be a port number from 1 to 65535")
    		os.Exit(1)
    	}
    
    	// Ctrl-C and SIGTERM end the context instead of the process, which
    	// lets the program delete its database before it exits. The handlers
    	// stay in place, so a further Ctrl-C does not end the process during
    	// the cleanup either.
    	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
    
    	// The client chooses the ID of a new database, so the program knows it
    	// before the request, and can delete the database even if the reply
    	// never arrives. The random suffix keeps the ID unique.
    	suffix := make([]byte, 3)
    	rand.Read(suffix)
    	databaseID := "cookbook-recipe-" + hex.EncodeToString(suffix)
    
    	exitCode := 0
    	created := false
    	err := run(ctx, databaseID, port, &created)
    	switch {
    	case ctx.Err() != nil:
    		fmt.Fprintln(os.Stderr, "Interrupted")
    		exitCode = 130
    	case err != nil:
    		fmt.Fprintf(os.Stderr, "Control Plane error: %v\n", err)
    		exitCode = 1
    	}
    
    	if created {
    		if err := deleteDatabase(databaseID); err != nil {
    			fmt.Fprintf(os.Stderr, "Control Plane error: %v\n", err)
    			fmt.Fprintf(os.Stderr, "Delete the database %s by hand\n", databaseID)
    			exitCode = 1
    		} else {
    			fmt.Println("Deleted database")
    		}
    	}
    	// os.Exit skips deferred calls, so release the signal handlers here.
    	stop()
    	os.Exit(exitCode)
    }
    
    ```

=== "Rust"

    ```rust
    /// Prints an error and the chain of its underlying causes, because the
    /// top-level error is often generic ("error sending request").
    fn report(e: &BoxError) {
        eprintln!("Control Plane error: {e}");
        let mut cause = e.source();
        while let Some(c) = cause {
            eprintln!("  caused by: {c}");
            cause = c.source();
        }
    }
    
    /// Returns a random suffix of six hexadecimal digits, read from the
    /// operating system's random number source.
    fn random_suffix() -> Result<String, BoxError> {
        let mut bytes = [0u8; 3];
        File::open("/dev/urandom")?.read_exact(&mut bytes)?;
        Ok(bytes.iter().map(|b| format!("{b:02x}")).collect())
    }
    
    /// Creates the database and waits for it. It sets created once the
    /// database may exist, so that the caller knows whether to delete it.
    fn run(client: &Client, database_id: &str, port: u16, created: &mut bool) -> Result<(), BoxError> {
        let host = first_host(client)?;
        check_interrupted()?;
        println!("Host: {host}");
    
        // Clean up unless the server refused the request with a 4xx status,
        // which means it created nothing; a 409, for example, means that a
        // database with this ID already exists, and is not this program's to
        // delete.
        *created = true;
        if let Err(e) = create_database(client, database_id, host.as_str(), port) {
            if matches!(status_of(&e), Some(400..=499)) {
                *created = false;
            }
            return Err(e);
        }
        check_interrupted()?;
        println!("Created database {database_id}");
    
        let port = wait_until_available(client, database_id)?;
        println!("Database is available on port {port}");
        Ok(())
    }
    
    /// Deletes the database whether the example succeeded, failed, or was
    /// interrupted, and exits with a failure status after a failure.
    fn main() -> ExitCode {
        // The new database listens on this port, so check it before creating
        // anything.
        let Some(port) = parse_port(&port_text()) else {
            eprintln!("CONTROL_PLANE_RECIPE_PORT must be a port number from 1 to 65535");
            return ExitCode::FAILURE;
        };
    
        // The handler stays in place, so a further Ctrl-C does not end the
        // process during the cleanup either. The termination feature of the
        // ctrlc crate makes it handle SIGTERM too.
        if let Err(e) = ctrlc::set_handler(|| INTERRUPTED.store(true, Ordering::SeqCst)) {
            eprintln!("Control Plane error: {e}");
            return ExitCode::FAILURE;
        }
    
        let client = match Client::builder().timeout(TIMEOUT).build() {
            Ok(client) => client,
            Err(e) => {
                report(&e.into());
                return ExitCode::FAILURE;
            }
        };
        // The client chooses the ID of a new database, so the program knows it
        // before the request, and can delete the database even if the reply
        // never arrives. The random suffix keeps the ID unique.
        let database_id = match random_suffix() {
            Ok(suffix) => format!("cookbook-recipe-{suffix}"),
            Err(e) => {
                report(&e);
                return ExitCode::FAILURE;
            }
        };
    
        let mut created = false;
        let mut exit_code = ExitCode::SUCCESS;
        // A signal that arrives after the last request still counts.
        let result = run(&client, &database_id, port, &mut created);
        if INTERRUPTED.load(Ordering::SeqCst) {
            eprintln!("Interrupted");
            exit_code = ExitCode::from(130);
        } else if let Err(e) = result {
            report(&e);
            exit_code = ExitCode::FAILURE;
        }
    
        if created {
            match delete_database(&client, &database_id) {
                Ok(()) => println!("Deleted database"),
                Err(e) => {
                    report(&e);
                    eprintln!("Delete the database {database_id} by hand");
                    exit_code = ExitCode::FAILURE;
                }
            }
        }
        exit_code
    }
    ```

=== "Ruby"

    ```ruby
    # The new database listens on this port, so check it before creating
    # anything.
    unless PORT_TEXT.match?(/\A[1-9][0-9]{0,4}\z/) && Integer(PORT_TEXT, 10) <= 65_535
      warn "CONTROL_PLANE_RECIPE_PORT must be a port number from 1 to 65535"
      exit 1
    end
    
    exit_code = 0
    created = false
    # The client chooses the ID of a new database, so the program knows it
    # before the request, and can delete the database even if the reply never
    # arrives. The random suffix keeps the ID unique.
    database_id = "cookbook-recipe-#{SecureRandom.hex(3)}"
    begin
      host = first_host
      puts "Host: #{host}"
    
      # Clean up unless the server refused the request with a 4xx status,
      # which means it created nothing; a 409, for example, means that a
      # database with this ID already exists, and is not this program's to
      # delete.
      created = true
      begin
        create_database(database_id, host)
      rescue ControlPlaneError => e
        created = false if e.status&.between?(400, 499)
        raise
      end
      puts "Created database #{database_id}"
    
      port = wait_until_available(database_id)
      puts "Database is available on port #{port}"
    rescue ControlPlaneError, KeyError, *NETWORK_ERRORS => e
      warn "Control Plane error: #{e.message}"
      exit_code = 1
    # Ctrl-C raises Interrupt, and SIGTERM raises SignalException.
    rescue SignalException
      warn "Interrupted"
      exit_code = 130
    ensure
      # Delete the database whether the example succeeded, failed, or was
      # interrupted. Ignore further interrupts, so that they cannot cut the
      # cleanup short.
      trap("INT", "IGNORE")
      trap("TERM", "IGNORE")
      if created
        begin
          delete_database(database_id)
          puts "Deleted database"
        rescue ControlPlaneError, KeyError, *NETWORK_ERRORS => e
          warn "Control Plane error: #{e.message}"
          warn "Delete the database #{database_id} by hand"
          exit_code = 1
        end
      end
    end
    
    exit exit_code
    ```

=== "curl"

    ```bash
    # Deletes the database, if the script may have created one. The EXIT trap
    # runs this function when the script finishes, whether the example
    # succeeded, failed, or was interrupted.
    cleanup() {
        local status=$?
        # Ignore further interrupts, so that they cannot cut the cleanup short.
        trap '' INT TERM
        if [[ "$created" == 1 ]]; then
            if delete_database "$database_id"; then
                echo "Deleted database"
            else
                echo "Delete the database $database_id by hand" >&2
                status=1
            fi
        fi
        exit "$status"
    }
    
    main() {
        database_id="" created=0 available_port=""
        if ! [[ "$port" =~ ^[1-9][0-9]{0,4}$ ]] || ((port > 65535)); then
            echo "CONTROL_PLANE_RECIPE_PORT must be a port number from 1 to 65535" >&2
            exit 1
        fi
    
        trap cleanup EXIT
        # Turn Ctrl-C and SIGTERM into a normal exit, so that cleanup runs.
        trap 'echo "Interrupted" >&2; exit 130' INT TERM
    
        local host reply status
        host="$(first_host)"
        echo "Host: $host"
    
        # The client chooses the ID of a new database, so the script knows it
        # before the request, and can delete the database even if the reply
        # never arrives. The random suffix keeps the ID unique.
        database_id="cookbook-recipe-$(od -An -N3 -tx1 /dev/urandom | tr -d ' \n')"
    
        # Clean up unless the server refused the request with a 4xx status,
        # which means it created nothing; a 409, for example, means that a
        # database with this ID already exists, and is not this script's to
        # delete.
        created=1
        reply="$(create_database "$database_id" "$host")"
        status="${reply##*$'\n'}"
        if [[ "$status" != 200 ]]; then
            [[ "$status" =~ ^4[0-9][0-9]$ ]] && created=0
            echo "Control Plane error: HTTP $status, ${reply%$'\n'*}" >&2
            return 1
        fi
        echo "Created database $database_id"
    
        wait_until_available "$database_id"
        echo "Database is available on port $available_port"
    }
    
    main
    ```

## Running the Example

The complete project for each language is available in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/control_plane/create_database).
Set the environment variables for your Control Plane, and then run the command
for your language from the corresponding project directory. The following tabs
show the commands that build and run each example:

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
    bash main.sh
    ```

## Viewing the Complete Program

The following tabs show the complete program for each language:

=== "Python"

    ```python
    """
    Ellie's Postgres Cookbook
    Creating a pgEdge Control Plane database on one host, waiting until it is
    available, and deleting it again, using httpx.
    
    These examples are for the Control Plane v0.11.0.
    
    The database runs in containers on the host until it is deleted, so this
    program deletes the database it creates on every path: after a success,
    after a failure, and after Ctrl-C.
    
    Copyright (c) 2026, pgEdge, Inc.
    This code is released under the PostgreSQL License.
    """
    
    import os
    import re
    import secrets
    import signal
    import sys
    import time
    
    import httpx
    
    
    # The or operator treats an empty variable as unset. The new database
    # listens on the given port on its host, so choose one that is free.
    BASE_URL = (os.environ.get("CONTROL_PLANE_URL") or "http://localhost:3000").rstrip("/")
    PORT_TEXT = os.environ.get("CONTROL_PLANE_RECIPE_PORT") or "6433"
    
    TIMEOUT_SECONDS = 30.0
    
    # How long to wait for a database to become available, or to disappear
    # after a delete, and how often to check.
    WAIT_SECONDS = 600
    POLL_SECONDS = 5
    
    
    class ControlPlaneError(Exception):
        """Raised when the Control Plane rejects a request or replies oddly.
        The status is the HTTP status of the reply, if there was one."""
    
        def __init__(self, message: str, status: int | None = None):
            super().__init__(message)
            self.status = status
    
    
    def call(client: httpx.Client, method: str, path: str, body: dict | None = None) -> dict:
        """Sends a request to the server, and returns the decoded reply."""
        response = client.request(method, path, json=body)
        if response.is_error:
            raise ControlPlaneError(
                f"HTTP {response.status_code}, {response.text[:200]}",
                response.status_code)
        try:
            reply = response.json()
            if isinstance(reply, dict):
                return reply
        except ValueError:
            pass
        raise ControlPlaneError(f"Unexpected response: {response.text[:200]}")
    
    
    def first_host(client: httpx.Client) -> str:
        """Returns the ID of the first host in the cluster. A database places
        each of its nodes on one or more hosts, which run the Postgres
        containers."""
        hosts = call(client, "GET", "/v1/hosts").get("hosts") or []
        if not hosts:
            raise ControlPlaneError("the cluster has no hosts")
        return hosts[0]["id"]
    
    
    def create_database(client: httpx.Client, database_id: str, host: str) -> None:
        """Asks the Control Plane to create a database with one node. The reply
        holds the database and the task that creates it; the work happens in
        the background after the reply."""
        call(client, "POST", "/v1/databases", {
            "id": database_id,
            "spec": {
                "database_name": "recipe",
                "port": int(PORT_TEXT),
                "nodes": [{"name": "n1", "host_ids": [host]}],
            },
        })
    
    
    def wait_until_available(client: httpx.Client, database_id: str) -> int:
        """Polls the database, printing its state each time it changes, until
        the state is available, and returns the port of its first instance.
        Each instance runs one node, and its connection_info holds the address
        and port that clients use. A failed state ends the wait at once."""
        deadline = time.monotonic() + WAIT_SECONDS
        last = None
        while time.monotonic() < deadline:
            database = call(client, "GET", f"/v1/databases/{database_id}")
            state = database.get("state")
            if state != last:
                print(f"Database state: {state}")
                last = state
            if state == "available":
                instances = database.get("instances") or []
                if not instances:
                    raise ControlPlaneError("the database is available but has no instances")
                return instances[0]["connection_info"]["port"]
            if state == "failed":
                raise ControlPlaneError("the database has the state failed")
            time.sleep(POLL_SECONDS)
        raise ControlPlaneError(
            f"the database was not available after {WAIT_SECONDS} seconds")
    
    
    def is_transient(error: Exception) -> bool:
        """Reports whether a failed request is worth repeating: no reply
        arrived, the server failed, or it answered 409, which the Control
        Plane does whilst another task, such as the create, is still running
        on the database."""
        if isinstance(error, httpx.TransportError):
            return True
        status = getattr(error, "status", None)
        return status is not None and (status == 409 or status >= 500)
    
    
    def delete_database(client: httpx.Client, database_id: str) -> None:
        """Deletes the database and waits until the API no longer has it. A
        404 means that the database is already gone."""
        path = f"/v1/databases/{database_id}"
        deadline = time.monotonic() + WAIT_SECONDS
        while True:
            try:
                task_id = call(client, "DELETE", path)["task"]["task_id"]
                break
            except (httpx.TransportError, ControlPlaneError) as e:
                if getattr(e, "status", None) == 404:
                    return
                if not is_transient(e) or time.monotonic() >= deadline:
                    raise
                time.sleep(POLL_SECONDS)
    
        # The delete starts a task that removes the database; a 404 shows that
        # it has finished. Whilst the database is still there, the status of
        # the task shows whether the delete failed.
        while time.monotonic() < deadline:
            try:
                call(client, "GET", path)
                status = call(client, "GET", f"{path}/tasks/{task_id}").get("status")
                if status in ("failed", "canceled"):
                    raise ControlPlaneError(
                        f"the delete task finished with the status {status}")
            except (httpx.TransportError, ControlPlaneError) as e:
                if getattr(e, "status", None) == 404:
                    return
                if not is_transient(e):
                    raise
            time.sleep(POLL_SECONDS)
        raise ControlPlaneError(
            f"the database was still present after {WAIT_SECONDS} seconds")
    
    
    def stop(*_) -> None:
        """Handles SIGTERM like Ctrl-C, by raising KeyboardInterrupt."""
        raise KeyboardInterrupt
    
    
    def main() -> int:
        # The new database listens on this port, so check it before creating
        # anything.
        if not re.fullmatch(r"[1-9][0-9]{0,4}", PORT_TEXT) or int(PORT_TEXT) > 65535:
            print("CONTROL_PLANE_RECIPE_PORT must be a port number from 1 to 65535",
                  file=sys.stderr)
            return 1
    
        # Turn SIGTERM into a KeyboardInterrupt, so that the finally block
        # runs, as it does for Ctrl-C.
        signal.signal(signal.SIGTERM, stop)
    
        exit_code = 0
        created = False
        # The client chooses the ID of a new database, so the program knows it
        # before the request, and can delete the database even if the reply
        # never arrives. The random suffix keeps the ID unique.
        database_id = f"cookbook-recipe-{secrets.token_hex(3)}"
        with httpx.Client(base_url=BASE_URL, timeout=TIMEOUT_SECONDS) as client:
            try:
                host = first_host(client)
                print(f"Host: {host}")
    
                # Clean up unless the server refused the request with a 4xx
                # status, which means it created nothing; a 409, for example,
                # means that a database with this ID already exists, and is
                # not this program's to delete.
                created = True
                try:
                    create_database(client, database_id, host)
                except ControlPlaneError as e:
                    if e.status is not None and 400 <= e.status < 500:
                        created = False
                    raise
                print(f"Created database {database_id}")
    
                port = wait_until_available(client, database_id)
                print(f"Database is available on port {port}")
            # httpx.HTTPError is the base class for failures to reach the
            # server, such as a refused connection or a timeout.
            except (httpx.HTTPError, ControlPlaneError, KeyError) as e:
                print(f"Control Plane error: {e}", file=sys.stderr)
                exit_code = 1
            except KeyboardInterrupt:
                print("Interrupted", file=sys.stderr)
                exit_code = 130
            finally:
                # Delete the database whether the example succeeded, failed, or
                # was interrupted. Ignore further interrupts, so that they
                # cannot cut the cleanup short.
                signal.signal(signal.SIGINT, signal.SIG_IGN)
                signal.signal(signal.SIGTERM, signal.SIG_IGN)
                if created:
                    try:
                        delete_database(client, database_id)
                        print("Deleted database")
                    except (httpx.HTTPError, ControlPlaneError, KeyError) as e:
                        print(f"Control Plane error: {e}", file=sys.stderr)
                        print(f"Delete the database {database_id} by hand",
                              file=sys.stderr)
                        exit_code = 1
    
        return exit_code
    
    
    if __name__ == "__main__":
        sys.exit(main())
    
    ```

=== "TypeScript"

    ```typescript
    /*
     * Ellie's Postgres Cookbook
     * Creating a pgEdge Control Plane database on one host, waiting until it
     * is available, and deleting it again, using the built-in fetch.
     *
     * These examples are for the Control Plane v0.11.0.
     *
     * The database runs in containers on the host until it is deleted, so
     * this program deletes the database it creates on every path: after a
     * success, after a failure, and after Ctrl-C.
     *
     * Copyright (c) 2026, pgEdge, Inc.
     * This code is released under the PostgreSQL License.
     */
    
    // Node.js provides fetch and AbortSignal as globals; setTimeout from
    // timers/promises returns a promise, which suits a polling loop.
    import { randomBytes } from "node:crypto";
    import { setTimeout as sleep } from "node:timers/promises";
    
    // The || operator, unlike ??, also treats an empty variable as unset. The
    // new database listens on the given port on its host, so choose one that
    // is free.
    const baseUrl = (process.env.CONTROL_PLANE_URL || "http://localhost:3000").replace(/\/+$/, "");
    const portText = process.env.CONTROL_PLANE_RECIPE_PORT || "6433";
    
    const timeoutMs = 30_000;
    
    // How long to wait for a database to become available, or to disappear
    // after a delete, and how often to check.
    const waitMs = 600_000;
    const pollMs = 5_000;
    
    // Ctrl-C and SIGTERM abort the signal below instead of ending the process,
    // which lets the program delete its database before it exits. The
    // handlers stay in place, so a further Ctrl-C does not end the process
    // during the cleanup either.
    const interrupt = new AbortController();
    for (const signalName of ["SIGINT", "SIGTERM"] as const) {
      process.on(signalName, () => interrupt.abort());
    }
    
    // An error reply from the Control Plane, with its HTTP status.
    class ControlPlaneError extends Error {
      constructor(
        message: string,
        readonly status?: number,
      ) {
        super(message);
      }
    }
    
    // Sends a request to the server, and returns the decoded reply. The
    // request stops when the user presses Ctrl-C, unless the caller passes a
    // different signal, as the cleanup does.
    async function call<T>(
      method: string,
      path: string,
      body?: unknown,
      signal: AbortSignal = interrupt.signal,
    ): Promise<T> {
      const response = await fetch(`${baseUrl}${path}`, {
        method,
        headers: body === undefined ? {} : { "Content-Type": "application/json" },
        body: body === undefined ? undefined : JSON.stringify(body),
        signal: AbortSignal.any([signal, AbortSignal.timeout(timeoutMs)]),
      });
    
      // fetch only rejects when it cannot reach the server; an error status
      // is a normal response, so check it explicitly.
      const text = await response.text();
      if (!response.ok) {
        throw new ControlPlaneError(
          `HTTP ${response.status}, ${text.slice(0, 200) || response.statusText}`,
          response.status,
        );
      }
      try {
        return JSON.parse(text) as T;
      } catch {
        throw new ControlPlaneError(`Unexpected response: ${text.slice(0, 200)}`);
      }
    }
    
    // Returns the ID of the first host in the cluster. A database places each
    // of its nodes on one or more hosts, which run the Postgres containers.
    async function firstHost(): Promise<string> {
      const reply = await call<{ hosts?: { id: string }[] }>("GET", "/v1/hosts");
      const host = reply.hosts?.[0];
      if (!host) {
        throw new ControlPlaneError("the cluster has no hosts");
      }
      return host.id;
    }
    
    // Asks the Control Plane to create a database with one node. The reply
    // holds the database and the task that creates it; the work happens in the
    // background after the reply.
    async function createDatabase(databaseId: string, host: string): Promise<void> {
      await call("POST", "/v1/databases", {
        id: databaseId,
        spec: {
          database_name: "recipe",
          port: Number(portText),
          nodes: [{ name: "n1", host_ids: [host] }],
        },
      });
    }
    
    interface Database {
      state?: string;
      instances?: { connection_info: { port: number } }[];
    }
    
    // Polls the database, printing its state each time it changes, until the
    // state is available, and returns the port of its first instance. Each
    // instance runs one node, and its connection_info holds the address and
    // port that clients use. A failed state ends the wait at once.
    async function waitUntilAvailable(databaseId: string): Promise<number> {
      const deadline = Date.now() + waitMs;
      let last: string | undefined;
      while (Date.now() < deadline) {
        const database = await call<Database>("GET", `/v1/databases/${databaseId}`);
        if (database.state !== last) {
          console.log(`Database state: ${database.state}`);
          last = database.state;
        }
        if (database.state === "available") {
          const instance = database.instances?.[0];
          if (!instance) {
            throw new ControlPlaneError("the database is available but has no instances");
          }
          return instance.connection_info.port;
        }
        if (database.state === "failed") {
          throw new ControlPlaneError("the database has the state failed");
        }
        await sleep(pollMs, undefined, { signal: interrupt.signal });
      }
      throw new ControlPlaneError(`the database was not available after ${waitMs / 1000} seconds`);
    }
    
    // Reports whether a failed request is worth repeating: no reply arrived,
    // the server failed, or it answered 409, which the Control Plane does
    // whilst another task, such as the create, is still running on the
    // database.
    function isTransient(err: unknown): boolean {
      if (!(err instanceof ControlPlaneError)) {
        return true;
      }
      return err.status !== undefined && (err.status === 409 || err.status >= 500);
    }
    
    function isGone(err: unknown): boolean {
      return err instanceof ControlPlaneError && err.status === 404;
    }
    
    // Deletes the database and waits until the API no longer has it. A 404
    // means that the database is already gone. The cleanup runs after Ctrl-C,
    // so its requests and waits use a signal that never aborts.
    async function deleteDatabase(databaseId: string): Promise<void> {
      const never = new AbortController().signal;
      const path = `/v1/databases/${databaseId}`;
      const deadline = Date.now() + waitMs;
      let taskId: string;
      for (;;) {
        try {
          const reply = await call<{ task: { task_id: string } }>("DELETE", path, undefined, never);
          taskId = reply.task.task_id;
          break;
        } catch (err) {
          if (isGone(err)) {
            return;
          }
          if (!isTransient(err) || Date.now() >= deadline) {
            throw err;
          }
          await sleep(pollMs);
        }
      }
    
      // The delete starts a task that removes the database; a 404 shows that
      // it has finished. Whilst the database is still there, the status of the
      // task shows whether the delete failed.
      while (Date.now() < deadline) {
        try {
          await call("GET", path, undefined, never);
          const task = await call<{ status: string }>("GET", `${path}/tasks/${taskId}`, undefined, never);
          if (task.status === "failed" || task.status === "canceled") {
            throw new ControlPlaneError(`the delete task finished with the status ${task.status}`);
          }
        } catch (err) {
          if (isGone(err)) {
            return;
          }
          if (!isTransient(err)) {
            throw err;
          }
        }
        await sleep(pollMs);
      }
      throw new ControlPlaneError(`the database was still present after ${waitMs / 1000} seconds`);
    }
    
    // Returns a readable description of an error. fetch reports a connection
    // failure as a TypeError with the cause (often an AggregateError, whose
    // own message is empty) attached.
    function describe(err: unknown): string {
      if (err instanceof AggregateError) {
        return err.errors.map(describe).join("; ");
      }
      if (err instanceof Error) {
        return err.cause ? `${err.message}: ${describe(err.cause)}` : err.message;
      }
      return String(err);
    }
    
    async function main(): Promise<number> {
      // The new database listens on this port, so check it before creating
      // anything.
      if (!/^[1-9][0-9]{0,4}$/.test(portText) || Number(portText) > 65535) {
        console.error("CONTROL_PLANE_RECIPE_PORT must be a port number from 1 to 65535");
        return 1;
      }
    
      let exitCode = 0;
      let created = false;
      // The client chooses the ID of a new database, so the program knows it
      // before the request, and can delete the database even if the reply
      // never arrives. The random suffix keeps the ID unique.
      const databaseId = `cookbook-recipe-${randomBytes(3).toString("hex")}`;
      try {
        const host = await firstHost();
        console.log(`Host: ${host}`);
    
        // Clean up unless the server refused the request with a 4xx status,
        // which means it created nothing; a 409, for example, means that a
        // database with this ID already exists, and is not this program's to
        // delete.
        created = true;
        try {
          await createDatabase(databaseId, host);
        } catch (err) {
          if (err instanceof ControlPlaneError && err.status && err.status < 500) {
            created = false;
          }
          throw err;
        }
        console.log(`Created database ${databaseId}`);
    
        const instancePort = await waitUntilAvailable(databaseId);
        console.log(`Database is available on port ${instancePort}`);
        // A signal that arrives after the last request still counts.
        if (interrupt.signal.aborted) {
          throw new Error("Interrupted");
        }
      } catch (err) {
        if (interrupt.signal.aborted) {
          console.error("Interrupted");
          exitCode = 130;
        } else {
          console.error(`Control Plane error: ${describe(err)}`);
          exitCode = 1;
        }
      } finally {
        // Delete the database whether the example succeeded, failed, or was
        // interrupted.
        if (created) {
          try {
            await deleteDatabase(databaseId);
            console.log("Deleted database");
          } catch (err) {
            console.error(`Control Plane error: ${describe(err)}`);
            console.error(`Delete the database ${databaseId} by hand`);
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
     * Creating a pgEdge Control Plane database on one host, waiting until it
     * is available, and deleting it again, using java.net.http and Jackson.
     *
     * These examples are for the Control Plane v0.11.0.
     *
     * The database runs in containers on the host until it is deleted, so
     * this program deletes the database it creates on every path: after a
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
    import java.util.concurrent.CompletableFuture;
    import java.util.concurrent.CountDownLatch;
    import java.util.concurrent.ExecutionException;
    import java.util.concurrent.TimeUnit;
    import java.util.concurrent.TimeoutException;
    
    import tools.jackson.core.JacksonException;
    import tools.jackson.databind.JsonNode;
    import tools.jackson.databind.ObjectMapper;
    import tools.jackson.databind.json.JsonMapper;
    
    public class Main {
    
        /** Returns the value of an environment variable, or a fallback. */
        static String envOr(String name, String fallback) {
            String value = System.getenv(name);
            return (value != null && !value.isEmpty()) ? value : fallback;
        }
    
        // The new database listens on the given port on its host, so choose
        // one that is free.
        static final String BASE_URL =
                envOr("CONTROL_PLANE_URL", "http://localhost:3000")
                        .replaceAll("/+$", "");
        static final String PORT = envOr("CONTROL_PLANE_RECIPE_PORT", "6433");
    
        static final Duration TIMEOUT = Duration.ofSeconds(30);
    
        // How long to wait for a database to become available, or to
        // disappear after a delete, and how often to check.
        static final Duration WAIT_FOR = Duration.ofSeconds(600);
        static final Duration POLL_INTERVAL = Duration.ofSeconds(5);
    
        /**
         * Thrown when the Control Plane rejects a request or replies oddly.
         * The status is the HTTP status of the reply, or 0 if there was none.
         */
        static class ControlPlaneException extends Exception {
            final int status;
    
            ControlPlaneException(String message, int status) {
                super(message);
                this.status = status;
            }
    
            ControlPlaneException(String message) {
                this(message, 0);
            }
        }
    
        // A client and a mapper are safe to share, so the program creates only
        // one of each.
        static final HttpClient CLIENT = HttpClient.newHttpClient();
        static final ObjectMapper MAPPER = JsonMapper.builder().build();
    
        /** Returns at most the first 200 characters of a reply. */
        static String shorten(String text) {
            return text.length() > 200 ? text.substring(0, 200) : text;
        }
    
        /**
         * Sends a request and returns the response with its whole body. The
         * request timeout stops applying once the headers arrive, so a server
         * that stalls part of the way through the body would hang send(); this
         * applies the same timeout to the whole exchange instead.
         */
        static HttpResponse<String> send(HttpRequest request)
                throws IOException, InterruptedException {
            CompletableFuture<HttpResponse<String>> pending =
                    CLIENT.sendAsync(request, HttpResponse.BodyHandlers.ofString());
            try {
                return pending.get(TIMEOUT.toMillis(), TimeUnit.MILLISECONDS);
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
         * Sends a request to the server, with the body encoded as JSON if it
         * is not null, and returns the decoded reply.
         */
        static JsonNode call(String method, String path, Object body)
                throws IOException, InterruptedException, ControlPlaneException {
            HttpRequest.Builder builder = HttpRequest.newBuilder(URI.create(BASE_URL + path))
                    .timeout(TIMEOUT);
            if (body == null) {
                builder.method(method, HttpRequest.BodyPublishers.noBody());
            } else {
                builder.header("Content-Type", "application/json")
                        .method(method, HttpRequest.BodyPublishers.ofString(
                                MAPPER.writeValueAsString(body)));
            }
            HttpResponse<String> response = send(builder.build());
            if (response.statusCode() >= 400) {
                throw new ControlPlaneException("HTTP " + response.statusCode()
                        + ", " + shorten(response.body()), response.statusCode());
            }
            try {
                JsonNode reply = MAPPER.readTree(response.body());
                if (reply.isObject()) {
                    return reply;
                }
            } catch (JacksonException e) {
                // The body is not JSON; report it below.
            }
            throw new ControlPlaneException(
                    "Unexpected response: " + shorten(response.body()));
        }
    
        /**
         * Returns the ID of the first host in the cluster. A database places
         * each of its nodes on one or more hosts, which run the Postgres
         * containers.
         */
        static String firstHost()
                throws IOException, InterruptedException, ControlPlaneException {
            JsonNode hosts = call("GET", "/v1/hosts", null).path("hosts");
            if (hosts.isEmpty()) {
                throw new ControlPlaneException("the cluster has no hosts");
            }
            return hosts.get(0).path("id").asString();
        }
    
        /**
         * Asks the Control Plane to create a database with one node. The reply
         * holds the database and the task that creates it; the work happens in
         * the background after the reply.
         */
        static void createDatabase(String databaseId, String host)
                throws IOException, InterruptedException, ControlPlaneException {
            Map<String, Object> body = Map.of(
                    "id", databaseId,
                    "spec", Map.of(
                            "database_name", "recipe",
                            "port", Integer.parseInt(PORT),
                            "nodes", List.of(Map.of(
                                    "name", "n1",
                                    "host_ids", List.of(host)))));
            call("POST", "/v1/databases", body);
        }
    
        /**
         * Polls the database, printing its state each time it changes, until
         * the state is available, and returns the port of its first instance.
         * Each instance runs one node, and its connection_info holds the
         * address and port that clients use. A failed state ends the wait at
         * once.
         */
        static int waitUntilAvailable(String databaseId)
                throws IOException, InterruptedException, ControlPlaneException {
            long deadline = System.nanoTime() + WAIT_FOR.toNanos();
            String last = "";
            while (System.nanoTime() < deadline) {
                JsonNode database = call("GET", "/v1/databases/" + databaseId, null);
                String state = database.path("state").asString("");
                if (!state.equals(last)) {
                    System.out.println("Database state: " + state);
                    last = state;
                }
                if (state.equals("available")) {
                    JsonNode instance = database.path("instances").path(0);
                    if (instance.isMissingNode()) {
                        throw new ControlPlaneException(
                                "the database is available but has no instances");
                    }
                    return instance.path("connection_info").path("port").asInt();
                }
                if (state.equals("failed")) {
                    throw new ControlPlaneException("the database has the state failed");
                }
                Thread.sleep(POLL_INTERVAL.toMillis());
            }
            throw new ControlPlaneException("the database was not available after "
                    + WAIT_FOR.toSeconds() + " seconds");
        }
    
        /**
         * Reports whether a failed request is worth repeating: no reply
         * arrived, the server failed, or it answered 409, which the Control
         * Plane does whilst another task, such as the create, is still running
         * on the database.
         */
        static boolean isTransient(Exception e) {
            if (e instanceof ControlPlaneException cpe) {
                return cpe.status == 409 || cpe.status >= 500;
            }
            return e instanceof IOException;
        }
    
        static boolean isGone(Exception e) {
            return e instanceof ControlPlaneException cpe && cpe.status == 404;
        }
    
        /**
         * Deletes the database and waits until the API no longer has it. A 404
         * means that the database is already gone.
         */
        static void deleteDatabase(String databaseId)
                throws IOException, InterruptedException, ControlPlaneException {
            String path = "/v1/databases/" + databaseId;
            long deadline = System.nanoTime() + WAIT_FOR.toNanos();
            String taskId;
            while (true) {
                try {
                    taskId = call("DELETE", path, null).path("task").path("task_id").asString("");
                    break;
                } catch (IOException | ControlPlaneException e) {
                    if (isGone(e)) {
                        return;
                    }
                    if (!isTransient(e) || System.nanoTime() >= deadline) {
                        throw e;
                    }
                }
                Thread.sleep(POLL_INTERVAL.toMillis());
            }
    
            if (taskId.isEmpty()) {
                throw new ControlPlaneException("the delete reply has no task");
            }
    
            // The delete starts a task that removes the database; a 404 shows
            // that it has finished. Whilst the database is still there, the
            // status of the task shows whether the delete failed.
            while (System.nanoTime() < deadline) {
                try {
                    call("GET", path, null);
                    String status = call("GET", path + "/tasks/" + taskId, null)
                            .path("status").asString("");
                    if (status.equals("failed") || status.equals("canceled")) {
                        throw new ControlPlaneException(
                                "the delete task finished with the status " + status);
                    }
                } catch (IOException | ControlPlaneException e) {
                    if (isGone(e)) {
                        return;
                    }
                    if (!isTransient(e)) {
                        throw e;
                    }
                }
                Thread.sleep(POLL_INTERVAL.toMillis());
            }
            throw new ControlPlaneException("the database was still present after "
                    + WAIT_FOR.toSeconds() + " seconds");
        }
    
        // Ctrl-C and SIGTERM start the JVM's shutdown, which runs the hook
        // below and then ends the process. The hook interrupts the main thread
        // and waits until it has deleted the database. The lock and the
        // cleaning flag stop the hook from interrupting the cleanup itself.
        static final Object LOCK = new Object();
        static final CountDownLatch FINISHED = new CountDownLatch(1);
        static boolean cleaning = false;
        static volatile boolean shuttingDown = false;
    
        public static void main(String[] args) {
            // The new database listens on this port, so check it before
            // creating anything.
            if (!PORT.matches("[1-9][0-9]{0,4}") || Integer.parseInt(PORT) > 65535) {
                System.err.println("CONTROL_PLANE_RECIPE_PORT must be a port number from 1 to 65535");
                System.exit(1);
            }
    
            Thread mainThread = Thread.currentThread();
            Runtime.getRuntime().addShutdownHook(new Thread(() -> {
                shuttingDown = true;
                synchronized (LOCK) {
                    if (!cleaning) {
                        mainThread.interrupt();
                    }
                }
                try {
                    FINISHED.await();
                } catch (InterruptedException e) {
                    // The JVM is ending anyway.
                }
            }));
    
            int exitCode = 0;
            boolean created = false;
            // The client chooses the ID of a new database, so the program knows
            // it before the request, and can delete the database even if the
            // reply never arrives. The random suffix keeps the ID unique.
            byte[] suffix = new byte[3];
            new SecureRandom().nextBytes(suffix);
            String databaseId = "cookbook-recipe-" + HexFormat.of().formatHex(suffix);
            try {
                String host = firstHost();
                System.out.println("Host: " + host);
    
                // Clean up unless the server refused the request with a 4xx
                // status, which means it created nothing; a 409, for example,
                // means that a database with this ID already exists, and is not
                // this program's to delete.
                created = true;
                try {
                    createDatabase(databaseId, host);
                } catch (ControlPlaneException e) {
                    if (e.status >= 400 && e.status < 500) {
                        created = false;
                    }
                    throw e;
                }
                System.out.println("Created database " + databaseId);
    
                int port = waitUntilAvailable(databaseId);
                System.out.println("Database is available on port " + port);
            } catch (InterruptedException e) {
                System.err.println("Interrupted");
                exitCode = 130;
            // IOException covers failures to reach the server, such as a
            // refused connection or a timeout. The message of a refused
            // connection can be empty, so print the exception itself, which
            // includes its type.
            } catch (IOException e) {
                System.err.println("Control Plane error: " + e);
                exitCode = 1;
            } catch (ControlPlaneException | RuntimeException e) {
                System.err.println("Control Plane error: " + e.getMessage());
                exitCode = 1;
            } finally {
                // From here on, a signal does not interrupt the main thread, and
                // any interrupt that arrived before this point is cleared, so
                // that the cleanup can wait between its requests.
                synchronized (LOCK) {
                    cleaning = true;
                    // A signal that arrived after the last request still counts.
                    if (Thread.interrupted() && exitCode == 0) {
                        System.err.println("Interrupted");
                        exitCode = 130;
                    }
                }
                // Delete the database whether the example succeeded, failed, or
                // was interrupted.
                if (created) {
                    try {
                        deleteDatabase(databaseId);
                        System.out.println("Deleted database");
                    } catch (IOException | InterruptedException | ControlPlaneException e) {
                        System.err.println("Control Plane error: " + e);
                        System.err.println("Delete the database " + databaseId + " by hand");
                        exitCode = 1;
                    }
                }
            }
    
            System.out.flush();
            FINISHED.countDown();
            // Once the JVM has started to shut down, System.exit() would wait
            // for the hook forever, so after a signal the program halts with
            // its exit code instead.
            if (shuttingDown) {
                Runtime.getRuntime().halt(exitCode);
            }
            System.exit(exitCode);
        }
    }
    
    ```

=== "C#"

    ```csharp
    /*
     * Ellie's Postgres Cookbook
     * Creating a pgEdge Control Plane database on one host, waiting until it
     * is available, and deleting it again, using HttpClient and
     * System.Text.Json.
     *
     * These examples are for the Control Plane v0.11.0.
     *
     * The database runs in containers on the host until it is deleted, so
     * this program deletes the database it creates on every path: after a
     * success, after a failure, and after Ctrl-C.
     *
     * Copyright (c) 2026, pgEdge, Inc.
     * This code is released under the PostgreSQL License.
     */
    
    using System.Diagnostics;
    using System.Net.Http.Json;
    using System.Runtime.InteropServices;
    using System.Security.Cryptography;
    using System.Text.Json;
    using System.Text.RegularExpressions;
    using System.Text.Json.Nodes;
    
    // Returns the value of an environment variable, or a fallback if the
    // variable is unset or empty.
    static string EnvOr(string name, string fallback) =>
        Environment.GetEnvironmentVariable(name) is { Length: > 0 } value
            ? value
            : fallback;
    
    static string BaseUrl() =>
        EnvOr("CONTROL_PLANE_URL", "http://localhost:3000").TrimEnd('/');
    
    // The new database listens on the given port on its host, so choose one
    // that is free.
    static string PortText() => EnvOr("CONTROL_PLANE_RECIPE_PORT", "6433");
    
    const int TimeoutSeconds = 30;
    
    // How long to wait for a database to become available, or to disappear
    // after a delete, and how often to check.
    const int WaitSeconds = 600;
    const int PollSeconds = 5;
    
    // Returns at most the first 200 characters of a reply.
    static string Shorten(string text) =>
        text.Length > 200 ? text[..200] : text;
    
    // Sends a request to the server, with the body encoded as JSON if it is
    // not null, and returns the decoded reply. The token stops the request
    // when the user presses Ctrl-C.
    static async Task<JsonObject> CallAsync(
        HttpClient client, HttpMethod method, string path, object? body,
        CancellationToken token)
    {
        using var request = new HttpRequestMessage(method, BaseUrl() + path);
        if (body is not null)
        {
            request.Content = JsonContent.Create(body);
        }
        using var response = await client.SendAsync(request, token);
        var text = await response.Content.ReadAsStringAsync(token);
        if (!response.IsSuccessStatusCode)
        {
            throw new ControlPlaneException(
                $"HTTP {(int)response.StatusCode}, {Shorten(text)}",
                (int)response.StatusCode);
        }
        try
        {
            if (JsonNode.Parse(text) is JsonObject reply)
            {
                return reply;
            }
        }
        catch (JsonException)
        {
            // The body is not JSON; report it below.
        }
        throw new ControlPlaneException($"Unexpected response: {Shorten(text)}");
    }
    
    // Returns the ID of the first host in the cluster. A database places each
    // of its nodes on one or more hosts, which run the Postgres containers.
    static async Task<string> FirstHostAsync(HttpClient client, CancellationToken token)
    {
        var reply = await CallAsync(client, HttpMethod.Get, "/v1/hosts", null, token);
        if (reply["hosts"] is not JsonArray { Count: > 0 } hosts ||
            hosts[0]?["id"]?.ToString() is not { } host)
        {
            throw new ControlPlaneException("the cluster has no hosts");
        }
        return host;
    }
    
    // Asks the Control Plane to create a database with one node. The reply
    // holds the database and the task that creates it; the work happens in the
    // background after the reply.
    static async Task CreateDatabaseAsync(
        HttpClient client, string databaseId, string host, CancellationToken token)
    {
        var body = new
        {
            id = databaseId,
            spec = new
            {
                database_name = "recipe",
                port = int.Parse(PortText()),
                nodes = new[] { new { name = "n1", host_ids = new[] { host } } },
            },
        };
        await CallAsync(client, HttpMethod.Post, "/v1/databases", body, token);
    }
    
    // Polls the database, printing its state each time it changes, until the
    // state is available, and returns the port of its first instance. Each
    // instance runs one node, and its connection_info holds the address and
    // port that clients use. A failed state ends the wait at once.
    static async Task<string> WaitUntilAvailableAsync(
        HttpClient client, string databaseId, CancellationToken token)
    {
        var clock = Stopwatch.StartNew();
        string? last = null;
        while (clock.Elapsed.TotalSeconds < WaitSeconds)
        {
            var database = await CallAsync(
                client, HttpMethod.Get, $"/v1/databases/{databaseId}", null, token);
            var state = database["state"]?.ToString();
            if (state != last)
            {
                Console.WriteLine($"Database state: {state}");
                last = state;
            }
            if (state == "available")
            {
                if (database["instances"] is not JsonArray { Count: > 0 } instances)
                {
                    throw new ControlPlaneException(
                        "the database is available but has no instances");
                }
                return instances[0]?["connection_info"]?["port"]?.ToString() ?? "";
            }
            if (state == "failed")
            {
                throw new ControlPlaneException("the database has the state failed");
            }
            await Task.Delay(TimeSpan.FromSeconds(PollSeconds), token);
        }
        throw new ControlPlaneException(
            $"the database was not available after {WaitSeconds} seconds");
    }
    
    // Reports whether a failed request is worth repeating: no reply arrived,
    // the server failed, or it answered 409, which the Control Plane does
    // whilst another task, such as the create, is still running on the
    // database. TaskCanceledException is a timeout here, because the cleanup
    // does not pass a token that can be cancelled.
    static bool IsTransient(Exception e) => e switch
    {
        ControlPlaneException cpe => cpe.Status is 409 or >= 500,
        HttpRequestException or TaskCanceledException => true,
        _ => false,
    };
    
    // Deletes the database and waits until the API no longer has it. A 404
    // means that the database is already gone. The cleanup runs after Ctrl-C,
    // so it uses no cancellation token.
    static async Task DeleteDatabaseAsync(HttpClient client, string databaseId)
    {
        var path = $"/v1/databases/{databaseId}";
        var clock = Stopwatch.StartNew();
        string taskId;
        while (true)
        {
            try
            {
                var reply = await CallAsync(
                    client, HttpMethod.Delete, path, null, CancellationToken.None);
                taskId = reply["task"]?["task_id"]?.ToString()
                    ?? throw new ControlPlaneException("the delete reply has no task");
                break;
            }
            catch (ControlPlaneException e) when (e.Status == 404)
            {
                return;
            }
            catch (Exception e) when (IsTransient(e) && clock.Elapsed.TotalSeconds < WaitSeconds)
            {
                await Task.Delay(TimeSpan.FromSeconds(PollSeconds));
            }
        }
    
        // The delete starts a task that removes the database; a 404 shows that
        // it has finished. Whilst the database is still there, the status of the
        // task shows whether the delete failed.
        while (clock.Elapsed.TotalSeconds < WaitSeconds)
        {
            try
            {
                await CallAsync(client, HttpMethod.Get, path, null, CancellationToken.None);
                var task = await CallAsync(
                    client, HttpMethod.Get, $"{path}/tasks/{taskId}", null, CancellationToken.None);
                var status = task["status"]?.ToString();
                if (status is "failed" or "canceled")
                {
                    throw new ControlPlaneException(
                        $"the delete task finished with the status {status}");
                }
            }
            catch (ControlPlaneException e) when (e.Status == 404)
            {
                return;
            }
            catch (Exception e) when (IsTransient(e))
            {
                // Check again after the pause.
            }
            await Task.Delay(TimeSpan.FromSeconds(PollSeconds));
        }
        throw new ControlPlaneException(
            $"the database was still present after {WaitSeconds} seconds");
    }
    
    // The new database listens on this port, so check it before creating
    // anything.
    if (!Regex.IsMatch(PortText(), @"^[1-9][0-9]{0,4}\z") || int.Parse(PortText()) > 65535)
    {
        Console.Error.WriteLine("CONTROL_PLANE_RECIPE_PORT must be a port number from 1 to 65535");
        return 1;
    }
    
    // Ctrl-C and SIGTERM cancel the token below instead of ending the process,
    // which lets the program delete its database before it exits. The
    // registrations stay in place, so a further Ctrl-C does not end the
    // process during the cleanup either.
    using var interrupt = new CancellationTokenSource();
    void OnSignal(PosixSignalContext context)
    {
        context.Cancel = true;
        interrupt.Cancel();
    }
    using var sigint = PosixSignalRegistration.Create(PosixSignal.SIGINT, OnSignal);
    using var sigterm = PosixSignalRegistration.Create(PosixSignal.SIGTERM, OnSignal);
    
    // using disposes of the client, and closes its connections, when the
    // program ends.
    using var client = new HttpClient
    {
        Timeout = TimeSpan.FromSeconds(TimeoutSeconds),
    };
    
    var exitCode = 0;
    var created = false;
    // The client chooses the ID of a new database, so the program knows it
    // before the request, and can delete the database even if the reply never
    // arrives. The random suffix keeps the ID unique.
    var databaseId = $"cookbook-recipe-{Convert.ToHexStringLower(RandomNumberGenerator.GetBytes(3))}";
    try
    {
        var host = await FirstHostAsync(client, interrupt.Token);
        Console.WriteLine($"Host: {host}");
    
        // Clean up unless the server refused the request with a 4xx status,
        // which means it created nothing; a 409, for example, means that a
        // database with this ID already exists, and is not this program's to
        // delete.
        created = true;
        try
        {
            await CreateDatabaseAsync(client, databaseId, host, interrupt.Token);
        }
        catch (ControlPlaneException e) when (e.Status is >= 400 and < 500)
        {
            created = false;
            throw;
        }
        Console.WriteLine($"Created database {databaseId}");
    
        var port = await WaitUntilAvailableAsync(client, databaseId, interrupt.Token);
        Console.WriteLine($"Database is available on port {port}");
        // A signal that arrives after the last request still counts.
        interrupt.Token.ThrowIfCancellationRequested();
    }
    catch (OperationCanceledException) when (interrupt.IsCancellationRequested)
    {
        Console.Error.WriteLine("Interrupted");
        exitCode = 130;
    }
    // HttpRequestException covers failures to reach the server, such as a
    // refused connection, and TaskCanceledException covers a timeout.
    catch (Exception e) when (
        e is HttpRequestException or TaskCanceledException or ControlPlaneException)
    {
        Console.Error.WriteLine($"Control Plane error: {e.Message}");
        exitCode = 1;
    }
    finally
    {
        // Delete the database whether the example succeeded, failed, or was
        // interrupted.
        if (created)
        {
            try
            {
                await DeleteDatabaseAsync(client, databaseId);
                Console.WriteLine("Deleted database");
            }
            catch (Exception e) when (
                e is HttpRequestException or TaskCanceledException or ControlPlaneException)
            {
                Console.Error.WriteLine($"Control Plane error: {e.Message}");
                Console.Error.WriteLine($"Delete the database {databaseId} by hand");
                exitCode = 1;
            }
        }
    }
    return exitCode;
    
    // C# requires type declarations to follow the top-level statements, so
    // the exception that the program throws for an error reply is declared
    // here, at the end. The status is the HTTP status of the reply, or 0 if
    // there was none.
    class ControlPlaneException(string message, int status = 0) : Exception(message)
    {
        public int Status { get; } = status;
    }
    
    ```

=== "Go"

    ```go
    // Ellie's Postgres Cookbook
    // Creating a pgEdge Control Plane database on one host, waiting until it
    // is available, and deleting it again, using net/http.
    //
    // These examples are for the Control Plane v0.11.0.
    //
    // The database runs in containers on the host until it is deleted, so
    // this program deletes the database it creates on every path: after a
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
    	"strconv"
    	"strings"
    	"syscall"
    	"time"
    )
    
    
    // envOr returns the value of an environment variable, or a fallback if
    // the variable is unset or empty.
    func envOr(name, fallback string) string {
    	if value := os.Getenv(name); value != "" {
    		return value
    	}
    	return fallback
    }
    
    // The new database listens on the given port on its host, so choose one
    // that is free.
    var (
    	baseURL  = strings.TrimRight(envOr("CONTROL_PLANE_URL", "http://localhost:3000"), "/")
    	portText = envOr("CONTROL_PLANE_RECIPE_PORT", "6433")
    )
    
    // parsePort returns the port number in text, and false unless text is a
    // plain decimal number from 1 to 65535.
    func parsePort(text string) (int, bool) {
    	number, err := strconv.Atoi(text)
    	if err != nil || number < 1 || number > 65535 || strconv.Itoa(number) != text {
    		return 0, false
    	}
    	return number, true
    }
    
    const timeout = 30 * time.Second
    
    // How long to wait for a database to become available, or to disappear
    // after a delete, and how often to check.
    const (
    	waitFor      = 600 * time.Second
    	pollInterval = 5 * time.Second
    )
    
    // apiError is an error reply from the Control Plane, with its HTTP status.
    type apiError struct {
    	status int
    	body   string
    }
    
    func (e *apiError) Error() string {
    	return fmt.Sprintf("HTTP %d, %.200s", e.status, e.body)
    }
    
    // statusOf returns the HTTP status of an error reply, or 0 if no reply
    // arrived.
    func statusOf(err error) int {
    	var apiErr *apiError
    	if errors.As(err, &apiErr) {
    		return apiErr.status
    	}
    	return 0
    }
    
    var client = &http.Client{Timeout: timeout}
    
    // call sends a request to the server, and decodes the reply into out if
    // out is not nil. The context stops the request when the user presses
    // Ctrl-C.
    func call(ctx context.Context, method, path string, body, out any) error {
    	var reader io.Reader
    	if body != nil {
    		encoded, err := json.Marshal(body)
    		if err != nil {
    			return err
    		}
    		reader = bytes.NewReader(encoded)
    	}
    	request, err := http.NewRequestWithContext(ctx, method, baseURL+path, reader)
    	if err != nil {
    		return err
    	}
    	if body != nil {
    		request.Header.Set("Content-Type", "application/json")
    	}
    
    	response, err := client.Do(request)
    	if err != nil {
    		return err
    	}
    	defer response.Body.Close()
    	reply, err := io.ReadAll(response.Body)
    	if err != nil {
    		return err
    	}
    
    	// Go treats an error status as a normal response, so check it here.
    	if response.StatusCode >= 400 {
    		return &apiError{response.StatusCode, strings.TrimSpace(string(reply))}
    	}
    	if out != nil {
    		if err := json.Unmarshal(reply, out); err != nil {
    			return fmt.Errorf("unexpected response: %.200s", reply)
    		}
    	}
    	return nil
    }
    
    // sleep waits for the poll interval, or until the context ends.
    func sleep(ctx context.Context) error {
    	select {
    	case <-time.After(pollInterval):
    		return nil
    	case <-ctx.Done():
    		return ctx.Err()
    	}
    }
    
    
    // firstHost returns the ID of the first host in the cluster. A database
    // places each of its nodes on one or more hosts, which run the Postgres
    // containers.
    func firstHost(ctx context.Context) (string, error) {
    	var reply struct {
    		Hosts []struct {
    			ID string `json:"id"`
    		} `json:"hosts"`
    	}
    	if err := call(ctx, http.MethodGet, "/v1/hosts", nil, &reply); err != nil {
    		return "", err
    	}
    	if len(reply.Hosts) == 0 {
    		return "", errors.New("the cluster has no hosts")
    	}
    	return reply.Hosts[0].ID, nil
    }
    
    
    // createDatabase asks the Control Plane to create a database with one
    // node. The reply holds the database and the task that creates it; the
    // work happens in the background after the reply.
    func createDatabase(ctx context.Context, databaseID, host string, port int) error {
    	body := map[string]any{
    		"id": databaseID,
    		"spec": map[string]any{
    			"database_name": "recipe",
    			"port":          port,
    			"nodes": []map[string]any{
    				{"name": "n1", "host_ids": []string{host}},
    			},
    		},
    	}
    	return call(ctx, http.MethodPost, "/v1/databases", body, nil)
    }
    
    
    // waitUntilAvailable polls the database, printing its state each time it
    // changes, until the state is available, and returns the port of its
    // first instance. Each instance runs one node, and its connection_info
    // holds the address and port that clients use. A failed state ends the
    // wait at once.
    func waitUntilAvailable(ctx context.Context, databaseID string) (int, error) {
    	deadline := time.Now().Add(waitFor)
    	last := ""
    	for time.Now().Before(deadline) {
    		var database struct {
    			State     string `json:"state"`
    			Instances []struct {
    				ConnectionInfo struct {
    					Port int `json:"port"`
    				} `json:"connection_info"`
    			} `json:"instances"`
    		}
    		err := call(ctx, http.MethodGet, "/v1/databases/"+databaseID, nil, &database)
    		if err != nil {
    			return 0, err
    		}
    		if database.State != last {
    			fmt.Printf("Database state: %s\n", database.State)
    			last = database.State
    		}
    		switch {
    		case database.State == "available" && len(database.Instances) == 0:
    			return 0, errors.New("the database is available but has no instances")
    		case database.State == "available":
    			return database.Instances[0].ConnectionInfo.Port, nil
    		case database.State == "failed":
    			return 0, errors.New("the database has the state failed")
    		}
    		if err := sleep(ctx); err != nil {
    			return 0, err
    		}
    	}
    	return 0, fmt.Errorf("the database was not available after %v", waitFor)
    }
    
    
    // isTransient reports whether a failed request is worth repeating: no
    // reply arrived, the server failed, or it answered 409, which the Control
    // Plane does whilst another task, such as the create, is still running on
    // the database.
    func isTransient(err error) bool {
    	status := statusOf(err)
    	return status == 0 || status == http.StatusConflict || status >= 500
    }
    
    // deleteDatabase deletes the database and waits until the API no longer
    // has it. A 404 means that the database is already gone. The cleanup runs
    // after Ctrl-C, so it uses a context that never ends.
    func deleteDatabase(databaseID string) error {
    	ctx := context.Background()
    	path := "/v1/databases/" + databaseID
    	deadline := time.Now().Add(waitFor)
    	var reply struct {
    		Task struct {
    			TaskID string `json:"task_id"`
    		} `json:"task"`
    	}
    	for {
    		err := call(ctx, http.MethodDelete, path, nil, &reply)
    		if err == nil {
    			break
    		}
    		if statusOf(err) == http.StatusNotFound {
    			return nil
    		}
    		if !isTransient(err) || time.Now().After(deadline) {
    			return err
    		}
    		time.Sleep(pollInterval)
    	}
    
    	// The delete starts a task that removes the database; a 404 shows that
    	// it has finished. Whilst the database is still there, the status of
    	// the task shows whether the delete failed.
    	for time.Now().Before(deadline) {
    		err := call(ctx, http.MethodGet, path, nil, nil)
    		if err == nil {
    			var task struct {
    				Status string `json:"status"`
    			}
    			err = call(ctx, http.MethodGet, path+"/tasks/"+reply.Task.TaskID, nil, &task)
    			if err == nil && (task.Status == "failed" || task.Status == "canceled") {
    				return fmt.Errorf("the delete task finished with the status %s", task.Status)
    			}
    		}
    		if statusOf(err) == http.StatusNotFound {
    			return nil
    		}
    		if err != nil && !isTransient(err) {
    			return err
    		}
    		time.Sleep(pollInterval)
    	}
    	return fmt.Errorf("the database was still present after %v", waitFor)
    }
    
    
    // run creates the database and waits for it, and returns any error to the
    // caller. It sets created once the database may exist, so that the caller
    // knows whether to delete it.
    func run(ctx context.Context, databaseID string, port int, created *bool) error {
    	host, err := firstHost(ctx)
    	if err != nil {
    		return err
    	}
    	fmt.Printf("Host: %s\n", host)
    
    	// Clean up unless the server refused the request with a 4xx status,
    	// which means it created nothing; a 409, for example, means that a
    	// database with this ID already exists, and is not this program's to
    	// delete.
    	*created = true
    	if err := createDatabase(ctx, databaseID, host, port); err != nil {
    		if status := statusOf(err); status >= 400 && status < 500 {
    			*created = false
    		}
    		return err
    	}
    	fmt.Printf("Created database %s\n", databaseID)
    
    	instancePort, err := waitUntilAvailable(ctx, databaseID)
    	if err != nil {
    		return err
    	}
    	fmt.Printf("Database is available on port %d\n", instancePort)
    	return nil
    }
    
    // main deletes the database whether the example succeeded, failed, or was
    // interrupted, and exits with a non-zero status after a failure.
    func main() {
    	// The new database listens on this port, so check it before creating
    	// anything.
    	port, ok := parsePort(portText)
    	if !ok {
    		fmt.Fprintln(os.Stderr, "CONTROL_PLANE_RECIPE_PORT must be a port number from 1 to 65535")
    		os.Exit(1)
    	}
    
    	// Ctrl-C and SIGTERM end the context instead of the process, which
    	// lets the program delete its database before it exits. The handlers
    	// stay in place, so a further Ctrl-C does not end the process during
    	// the cleanup either.
    	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
    
    	// The client chooses the ID of a new database, so the program knows it
    	// before the request, and can delete the database even if the reply
    	// never arrives. The random suffix keeps the ID unique.
    	suffix := make([]byte, 3)
    	rand.Read(suffix)
    	databaseID := "cookbook-recipe-" + hex.EncodeToString(suffix)
    
    	exitCode := 0
    	created := false
    	err := run(ctx, databaseID, port, &created)
    	switch {
    	case ctx.Err() != nil:
    		fmt.Fprintln(os.Stderr, "Interrupted")
    		exitCode = 130
    	case err != nil:
    		fmt.Fprintf(os.Stderr, "Control Plane error: %v\n", err)
    		exitCode = 1
    	}
    
    	if created {
    		if err := deleteDatabase(databaseID); err != nil {
    			fmt.Fprintf(os.Stderr, "Control Plane error: %v\n", err)
    			fmt.Fprintf(os.Stderr, "Delete the database %s by hand\n", databaseID)
    			exitCode = 1
    		} else {
    			fmt.Println("Deleted database")
    		}
    	}
    	// os.Exit skips deferred calls, so release the signal handlers here.
    	stop()
    	os.Exit(exitCode)
    }
    
    
    ```

=== "Rust"

    ```rust
    // Ellie's Postgres Cookbook
    // Creating a pgEdge Control Plane database on one host, waiting until it
    // is available, and deleting it again, using reqwest and serde_json.
    //
    // These examples are for the Control Plane v0.11.0.
    //
    // The database runs in containers on the host until it is deleted, so
    // this program deletes the database it creates on every path: after a
    // success, after a failure, and after Ctrl-C.
    //
    // Copyright (c) 2026, pgEdge, Inc.
    // This code is released under the PostgreSQL License.
    
    use std::env;
    use std::error::Error;
    use std::fmt;
    use std::fs::File;
    use std::io::Read;
    use std::process::ExitCode;
    use std::sync::atomic::{AtomicBool, Ordering};
    use std::thread;
    use std::time::{Duration, Instant};
    
    use reqwest::blocking::Client;
    use reqwest::Method;
    use serde_json::{json, Value};
    
    /// Returns the value of an environment variable, or a fallback if the
    /// variable is unset or empty.
    fn env_or(name: &str, fallback: &str) -> String {
        env::var(name)
            .ok()
            .filter(|value| !value.is_empty())
            .unwrap_or_else(|| fallback.to_string())
    }
    
    fn base_url() -> String {
        env_or("CONTROL_PLANE_URL", "http://localhost:3000")
            .trim_end_matches('/')
            .to_string()
    }
    
    /// The port that the new database listens on, on its host; choose one
    /// that is free.
    fn port_text() -> String {
        env_or("CONTROL_PLANE_RECIPE_PORT", "6433")
    }
    
    /// Returns the port number in text, or None unless text is a plain
    /// decimal number from 1 to 65535.
    fn parse_port(text: &str) -> Option<u16> {
        let plain = !text.starts_with('0')
            && text.len() <= 5
            && text.bytes().all(|b| b.is_ascii_digit());
        if plain { text.parse().ok().filter(|&port| port > 0) } else { None }
    }
    
    const TIMEOUT: Duration = Duration::from_secs(30);
    
    // How long to wait for a database to become available, or to disappear
    // after a delete, and how often to check.
    const WAIT_FOR: Duration = Duration::from_secs(600);
    const POLL_INTERVAL: Duration = Duration::from_secs(5);
    
    /// Set by Ctrl-C or SIGTERM. The handler sets this flag instead of ending
    /// the process, which lets the program delete its database before it
    /// exits; the waits check it between requests.
    static INTERRUPTED: AtomicBool = AtomicBool::new(false);
    
    /// The errors that the functions below return; a string converts into one
    /// with the ? operator or into().
    type BoxError = Box<dyn Error>;
    
    /// An error reply from the Control Plane, with its HTTP status.
    #[derive(Debug)]
    struct ApiError {
        status: u16,
        body: String,
    }
    
    impl fmt::Display for ApiError {
        fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
            write!(f, "HTTP {}, {}", self.status, self.body)
        }
    }
    
    impl Error for ApiError {}
    
    /// Returns the HTTP status of an error reply, or None if no reply arrived
    /// or the error is of another kind.
    fn status_of(error: &BoxError) -> Option<u16> {
        error.downcast_ref::<ApiError>().map(|e| e.status)
    }
    
    /// Returns at most the first 200 characters of a reply.
    fn shorten(text: &str) -> String {
        text.chars().take(200).collect()
    }
    
    /// Sends a request to the server, with the body encoded as JSON if there
    /// is one, and returns the decoded reply.
    fn call(client: &Client, method: Method, path: &str, body: Option<&Value>) -> Result<Value, BoxError> {
        let mut request = client.request(method, format!("{}{path}", base_url()));
        if let Some(body) = body {
            request = request.json(body);
        }
        let response = request.send()?;
        let status = response.status();
        let text = response.text()?;
        if !status.is_success() {
            return Err(ApiError { status: status.as_u16(), body: shorten(&text) }.into());
        }
        match serde_json::from_str::<Value>(&text) {
            Ok(reply) if reply.is_object() => Ok(reply),
            _ => Err(format!("Unexpected response: {}", shorten(&text)).into()),
        }
    }
    
    /// Fails if the user has pressed Ctrl-C. A request does not stop for
    /// Ctrl-C, so the program checks the flag after each one.
    fn check_interrupted() -> Result<(), BoxError> {
        if INTERRUPTED.load(Ordering::SeqCst) {
            return Err("interrupted".into());
        }
        Ok(())
    }
    
    /// Waits for the poll interval, and fails if the user presses Ctrl-C.
    fn pause() -> Result<(), BoxError> {
        let end = Instant::now() + POLL_INTERVAL;
        while Instant::now() < end {
            check_interrupted()?;
            thread::sleep(Duration::from_millis(100));
        }
        Ok(())
    }
    
    /// Returns the ID of the first host in the cluster. A database places each
    /// of its nodes on one or more hosts, which run the Postgres containers.
    fn first_host(client: &Client) -> Result<String, BoxError> {
        let reply = call(client, Method::GET, "/v1/hosts", None)?;
        reply["hosts"][0]["id"]
            .as_str()
            .map(str::to_string)
            .ok_or_else(|| "the cluster has no hosts".into())
    }
    
    /// Asks the Control Plane to create a database with one node. The reply
    /// holds the database and the task that creates it; the work happens in
    /// the background after the reply.
    fn create_database(
        client: &Client,
        database_id: &str,
        host: &str,
        port: u16,
    ) -> Result<(), BoxError> {
        let body = json!({
            "id": database_id,
            "spec": {
                "database_name": "recipe",
                "port": port,
                "nodes": [{"name": "n1", "host_ids": [host]}],
            },
        });
        call(client, Method::POST, "/v1/databases", Some(&body))?;
        Ok(())
    }
    
    /// Polls the database, printing its state each time it changes, until the
    /// state is available, and returns the port of its first instance. Each
    /// instance runs one node, and its connection_info holds the address and
    /// port that clients use. A failed state ends the wait at once.
    fn wait_until_available(client: &Client, database_id: &str) -> Result<u64, BoxError> {
        let deadline = Instant::now() + WAIT_FOR;
        let mut last = String::new();
        while Instant::now() < deadline {
            let database = call(client, Method::GET, &format!("/v1/databases/{database_id}"), None)?;
            check_interrupted()?;
            let state = database["state"].as_str().unwrap_or("unknown").to_string();
            if state != last {
                println!("Database state: {state}");
                last = state.clone();
            }
            if state == "available" {
                let instance = database["instances"]
                    .get(0)
                    .ok_or("the database is available but has no instances")?;
                return instance["connection_info"]["port"]
                    .as_u64()
                    .ok_or_else(|| "Unexpected response: missing port".into());
            }
            if state == "failed" {
                return Err("the database has the state failed".into());
            }
            pause()?;
        }
        Err(format!("the database was not available after {} seconds", WAIT_FOR.as_secs()).into())
    }
    
    /// Reports whether a failed request is worth repeating: no reply arrived,
    /// the server failed, or it answered 409, which the Control Plane does
    /// whilst another task, such as the create, is still running on the
    /// database.
    fn is_transient(error: &BoxError) -> bool {
        match status_of(error) {
            Some(status) => status == 409 || status >= 500,
            None => error.is::<reqwest::Error>(),
        }
    }
    
    /// Deletes the database and waits until the API no longer has it. A 404
    /// means that the database is already gone. The cleanup runs after
    /// Ctrl-C, so its waits do not check the flag.
    fn delete_database(client: &Client, database_id: &str) -> Result<(), BoxError> {
        let path = format!("/v1/databases/{database_id}");
        let deadline = Instant::now() + WAIT_FOR;
        let task_id = loop {
            match call(client, Method::DELETE, &path, None) {
                Ok(reply) => break reply["task"]["task_id"].as_str().unwrap_or_default().to_string(),
                Err(e) if status_of(&e) == Some(404) => return Ok(()),
                Err(e) if !is_transient(&e) || Instant::now() >= deadline => return Err(e),
                Err(_) => thread::sleep(POLL_INTERVAL),
            }
        };
        if task_id.is_empty() {
            return Err("the delete reply has no task".into());
        }
    
        // The delete starts a task that removes the database; a 404 shows that
        // it has finished. Whilst the database is still there, the status of
        // the task shows whether the delete failed.
        let task_path = format!("{path}/tasks/{task_id}");
        while Instant::now() < deadline {
            let polled = call(client, Method::GET, &path, None)
                .and_then(|_| call(client, Method::GET, &task_path, None));
            match polled {
                Ok(task) if matches!(task["status"].as_str(), Some("failed" | "canceled")) => {
                    let status = task["status"].as_str().unwrap_or_default();
                    return Err(format!("the delete task finished with the status {status}").into());
                }
                Err(e) if status_of(&e) == Some(404) => return Ok(()),
                Err(e) if !is_transient(&e) => return Err(e),
                _ => thread::sleep(POLL_INTERVAL),
            }
        }
        Err(format!("the database was still present after {} seconds", WAIT_FOR.as_secs()).into())
    }
    
    /// Prints an error and the chain of its underlying causes, because the
    /// top-level error is often generic ("error sending request").
    fn report(e: &BoxError) {
        eprintln!("Control Plane error: {e}");
        let mut cause = e.source();
        while let Some(c) = cause {
            eprintln!("  caused by: {c}");
            cause = c.source();
        }
    }
    
    /// Returns a random suffix of six hexadecimal digits, read from the
    /// operating system's random number source.
    fn random_suffix() -> Result<String, BoxError> {
        let mut bytes = [0u8; 3];
        File::open("/dev/urandom")?.read_exact(&mut bytes)?;
        Ok(bytes.iter().map(|b| format!("{b:02x}")).collect())
    }
    
    /// Creates the database and waits for it. It sets created once the
    /// database may exist, so that the caller knows whether to delete it.
    fn run(client: &Client, database_id: &str, port: u16, created: &mut bool) -> Result<(), BoxError> {
        let host = first_host(client)?;
        check_interrupted()?;
        println!("Host: {host}");
    
        // Clean up unless the server refused the request with a 4xx status,
        // which means it created nothing; a 409, for example, means that a
        // database with this ID already exists, and is not this program's to
        // delete.
        *created = true;
        if let Err(e) = create_database(client, database_id, host.as_str(), port) {
            if matches!(status_of(&e), Some(400..=499)) {
                *created = false;
            }
            return Err(e);
        }
        check_interrupted()?;
        println!("Created database {database_id}");
    
        let port = wait_until_available(client, database_id)?;
        println!("Database is available on port {port}");
        Ok(())
    }
    
    /// Deletes the database whether the example succeeded, failed, or was
    /// interrupted, and exits with a failure status after a failure.
    fn main() -> ExitCode {
        // The new database listens on this port, so check it before creating
        // anything.
        let Some(port) = parse_port(&port_text()) else {
            eprintln!("CONTROL_PLANE_RECIPE_PORT must be a port number from 1 to 65535");
            return ExitCode::FAILURE;
        };
    
        // The handler stays in place, so a further Ctrl-C does not end the
        // process during the cleanup either. The termination feature of the
        // ctrlc crate makes it handle SIGTERM too.
        if let Err(e) = ctrlc::set_handler(|| INTERRUPTED.store(true, Ordering::SeqCst)) {
            eprintln!("Control Plane error: {e}");
            return ExitCode::FAILURE;
        }
    
        let client = match Client::builder().timeout(TIMEOUT).build() {
            Ok(client) => client,
            Err(e) => {
                report(&e.into());
                return ExitCode::FAILURE;
            }
        };
        // The client chooses the ID of a new database, so the program knows it
        // before the request, and can delete the database even if the reply
        // never arrives. The random suffix keeps the ID unique.
        let database_id = match random_suffix() {
            Ok(suffix) => format!("cookbook-recipe-{suffix}"),
            Err(e) => {
                report(&e);
                return ExitCode::FAILURE;
            }
        };
    
        let mut created = false;
        let mut exit_code = ExitCode::SUCCESS;
        // A signal that arrives after the last request still counts.
        let result = run(&client, &database_id, port, &mut created);
        if INTERRUPTED.load(Ordering::SeqCst) {
            eprintln!("Interrupted");
            exit_code = ExitCode::from(130);
        } else if let Err(e) = result {
            report(&e);
            exit_code = ExitCode::FAILURE;
        }
    
        if created {
            match delete_database(&client, &database_id) {
                Ok(()) => println!("Deleted database"),
                Err(e) => {
                    report(&e);
                    eprintln!("Delete the database {database_id} by hand");
                    exit_code = ExitCode::FAILURE;
                }
            }
        }
        exit_code
    }
    
    ```

=== "Ruby"

    ```ruby
    # Ellie's Postgres Cookbook
    # Creating a pgEdge Control Plane database on one host, waiting until it is
    # available, and deleting it again, using Net::HTTP.
    #
    # These examples are for the Control Plane v0.11.0.
    #
    # The database runs in containers on the host until it is deleted, so this
    # program deletes the database it creates on every path: after a success,
    # after a failure, and after Ctrl-C.
    #
    # Copyright (c) 2026, pgEdge, Inc.
    # This code is released under the PostgreSQL License.
    
    require "json"
    require "net/http"
    require "securerandom"
    require "uri"
    
    # Returns the value of an environment variable, or a fallback if the
    # variable is unset or empty.
    def env_or(name, fallback)
      value = ENV[name]
      value.nil? || value.empty? ? fallback : value
    end
    
    # The new database listens on the given port on its host, so choose one
    # that is free.
    BASE_URL = env_or("CONTROL_PLANE_URL", "http://localhost:3000").sub(%r{/+\z}, "")
    PORT_TEXT = env_or("CONTROL_PLANE_RECIPE_PORT", "6433")
    
    TIMEOUT_SECONDS = 30
    
    # How long to wait for a database to become available, or to disappear
    # after a delete, and how often to check.
    WAIT_SECONDS = 600
    POLL_SECONDS = 5
    
    # Raised when the Control Plane rejects a request or replies oddly. The
    # status is the HTTP status of the reply, if there was one.
    class ControlPlaneError < StandardError
      attr_reader :status
    
      def initialize(message, status = nil)
        super(message)
        @status = status
      end
    end
    
    # The errors that mean no reply arrived: SystemCallError covers a refused
    # connection, Timeout::Error covers the connection and read timeouts, and
    # SocketError covers an unknown host.
    NETWORK_ERRORS = [SystemCallError, Timeout::Error, SocketError, IOError].freeze
    
    # Sends a request to the server, and returns the decoded reply.
    def call(method, path, body = nil)
      uri = URI("#{BASE_URL}#{path}")
      request = Net::HTTPGenericRequest.new(method, !body.nil?, true, uri)
      if body
        request["Content-Type"] = "application/json"
        request.body = JSON.generate(body)
      end
      # start opens a connection, and closes it when the block exits, whether
      # or not an error occurred.
      response = Net::HTTP.start(
        uri.host, uri.port,
        use_ssl: uri.scheme == "https",
        open_timeout: TIMEOUT_SECONDS, read_timeout: TIMEOUT_SECONDS
      ) { |http| http.request(request) }
      unless response.is_a?(Net::HTTPSuccess)
        raise ControlPlaneError.new(
          "HTTP #{response.code}, #{response.body.to_s[0, 200]}", response.code.to_i
        )
      end
    
      begin
        reply = JSON.parse(response.body.to_s)
        return reply if reply.is_a?(Hash)
      rescue JSON::ParserError
        # The body is not JSON; report it below.
      end
      raise ControlPlaneError, "Unexpected response: #{response.body.to_s[0, 200]}"
    end
    
    # Returns the ID of the first host in the cluster. A database places each
    # of its nodes on one or more hosts, which run the Postgres containers.
    def first_host
      host = (call("GET", "/v1/hosts")["hosts"] || []).first
      raise ControlPlaneError, "the cluster has no hosts" unless host
    
      host["id"]
    end
    
    # Asks the Control Plane to create a database with one node. The reply
    # holds the database and the task that creates it; the work happens in the
    # background after the reply.
    def create_database(database_id, host)
      call("POST", "/v1/databases", {
             id: database_id,
             spec: {
               database_name: "recipe",
               port: Integer(PORT_TEXT, 10),
               nodes: [{ name: "n1", host_ids: [host] }]
             }
           })
    end
    
    # Polls the database, printing its state each time it changes, until the
    # state is available, and returns the port of its first instance. Each
    # instance runs one node, and its connection_info holds the address and
    # port that clients use. A failed state ends the wait at once.
    def wait_until_available(database_id)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + WAIT_SECONDS
      last = nil
      while Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
        database = call("GET", "/v1/databases/#{database_id}")
        state = database["state"]
        if state != last
          puts "Database state: #{state}"
          last = state
        end
        if state == "available"
          instance = (database["instances"] || []).first
          raise ControlPlaneError, "the database is available but has no instances" unless instance
    
          return instance.fetch("connection_info").fetch("port")
        end
        raise ControlPlaneError, "the database has the state failed" if state == "failed"
    
        sleep POLL_SECONDS
      end
      raise ControlPlaneError, "the database was not available after #{WAIT_SECONDS} seconds"
    end
    
    # Reports whether a failed request is worth repeating: no reply arrived,
    # the server failed, or it answered 409, which the Control Plane does
    # whilst another task, such as the create, is still running on the
    # database.
    def transient?(error)
      return true unless error.is_a?(ControlPlaneError)
    
      !error.status.nil? && (error.status == 409 || error.status >= 500)
    end
    
    # Deletes the database and waits until the API no longer has it. A 404
    # means that the database is already gone.
    def delete_database(database_id)
      path = "/v1/databases/#{database_id}"
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + WAIT_SECONDS
      begin
        task_id = call("DELETE", path).fetch("task").fetch("task_id")
      rescue ControlPlaneError, *NETWORK_ERRORS => e
        return if e.is_a?(ControlPlaneError) && e.status == 404
        raise if !transient?(e) || Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
    
        sleep POLL_SECONDS
        retry
      end
    
      # The delete starts a task that removes the database; a 404 shows that
      # it has finished. Whilst the database is still there, the status of the
      # task shows whether the delete failed.
      while Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
        begin
          call("GET", path)
          status = call("GET", "#{path}/tasks/#{task_id}")["status"]
          if %w[failed canceled].include?(status)
            raise ControlPlaneError, "the delete task finished with the status #{status}"
          end
        rescue ControlPlaneError, *NETWORK_ERRORS => e
          return if e.is_a?(ControlPlaneError) && e.status == 404
          raise unless transient?(e)
        end
        sleep POLL_SECONDS
      end
      raise ControlPlaneError, "the database was still present after #{WAIT_SECONDS} seconds"
    end
    
    # The new database listens on this port, so check it before creating
    # anything.
    unless PORT_TEXT.match?(/\A[1-9][0-9]{0,4}\z/) && Integer(PORT_TEXT, 10) <= 65_535
      warn "CONTROL_PLANE_RECIPE_PORT must be a port number from 1 to 65535"
      exit 1
    end
    
    exit_code = 0
    created = false
    # The client chooses the ID of a new database, so the program knows it
    # before the request, and can delete the database even if the reply never
    # arrives. The random suffix keeps the ID unique.
    database_id = "cookbook-recipe-#{SecureRandom.hex(3)}"
    begin
      host = first_host
      puts "Host: #{host}"
    
      # Clean up unless the server refused the request with a 4xx status,
      # which means it created nothing; a 409, for example, means that a
      # database with this ID already exists, and is not this program's to
      # delete.
      created = true
      begin
        create_database(database_id, host)
      rescue ControlPlaneError => e
        created = false if e.status&.between?(400, 499)
        raise
      end
      puts "Created database #{database_id}"
    
      port = wait_until_available(database_id)
      puts "Database is available on port #{port}"
    rescue ControlPlaneError, KeyError, *NETWORK_ERRORS => e
      warn "Control Plane error: #{e.message}"
      exit_code = 1
    # Ctrl-C raises Interrupt, and SIGTERM raises SignalException.
    rescue SignalException
      warn "Interrupted"
      exit_code = 130
    ensure
      # Delete the database whether the example succeeded, failed, or was
      # interrupted. Ignore further interrupts, so that they cannot cut the
      # cleanup short.
      trap("INT", "IGNORE")
      trap("TERM", "IGNORE")
      if created
        begin
          delete_database(database_id)
          puts "Deleted database"
        rescue ControlPlaneError, KeyError, *NETWORK_ERRORS => e
          warn "Control Plane error: #{e.message}"
          warn "Delete the database #{database_id} by hand"
          exit_code = 1
        end
      end
    end
    
    exit exit_code
    
    ```

=== "curl"

    ```bash
    #!/usr/bin/env bash
    #
    # Ellie's Postgres Cookbook
    # Creating a pgEdge Control Plane database on one host, waiting until it is
    # available, and deleting it again, using curl and jq.
    #
    # These examples are for the Control Plane v0.11.0.
    #
    # The database runs in containers on the host until it is deleted, so this
    # script deletes the database it creates on every path: after a success,
    # after a failure, and after Ctrl-C.
    #
    # Copyright (c) 2026, pgEdge, Inc.
    # This code is released under the PostgreSQL License.
    
    # Stop at the first failed command or unset variable, and make a failure
    # anywhere in a pipeline fail the whole pipeline.
    set -euo pipefail
    
    # The script needs curl to call the API and jq to read the JSON replies.
    for tool in curl jq; do
        command -v "$tool" >/dev/null || { echo "Control Plane error: $tool is required" >&2; exit 1; }
    done
    
    # The :- expansion treats an empty variable as unset. The new database
    # listens on the given port on its host, so choose one that is free.
    base_url="${CONTROL_PLANE_URL:-http://localhost:3000}"
    base_url="${base_url%/}"
    port="${CONTROL_PLANE_RECIPE_PORT:-6433}"
    
    # How long to wait for a database to become available, or to disappear
    # after a delete, and how often to check.
    wait_seconds=600
    poll_seconds=5
    
    # Sends a request and prints the reply, followed by the HTTP status on a
    # line of its own; the status is 000 if no reply arrived. Any further
    # arguments go to curl, such as --data @- to send standard input as the
    # body.
    request() {
        local method="$1" path="$2"
        shift 2
        curl --silent --show-error --max-time 30 --request "$method" \
            --write-out '\n%{http_code}' "$@" "$base_url$path" || true
    }
    
    # Fetches a path from the server and prints the reply, or reports the
    # error and fails.
    get() {
        local reply status
        reply="$(request GET "$1")"
        status="${reply##*$'\n'}"
        if [[ "$status" != 200 ]]; then
            echo "Control Plane error: HTTP $status, ${reply%$'\n'*}" >&2
            return 1
        fi
        printf '%s\n' "${reply%$'\n'*}"
    }
    
    # Prints the ID of the first host in the cluster. A database places each of
    # its nodes on one or more hosts, which run the Postgres containers.
    first_host() {
        get /v1/hosts | jq -er '.hosts[0].id'
    }
    
    # Asks the Control Plane to create a database with one node, and prints the
    # reply followed by the HTTP status, as request() does. The reply holds the
    # database and the task that creates it; the work happens in the
    # background after the reply.
    create_database() {
        local id="$1" host="$2"
        jq -n --arg id "$id" --arg host "$host" --argjson port "$port" \
            '{id: $id,
              spec: {database_name: "recipe",
                     port: $port,
                     nodes: [{name: "n1", host_ids: [$host]}]}}' |
            request POST /v1/databases \
                --header "Content-Type: application/json" --data @-
    }
    
    # Polls the database, printing its state each time it changes, until the
    # state is available, and then sets available_port to the port of its
    # first instance. Each instance runs one node, and its connection_info
    # holds the address and port that clients use. A failed state ends the
    # wait at once.
    wait_until_available() {
        local id="$1" deadline=$((SECONDS + wait_seconds)) database state last=""
        while ((SECONDS < deadline)); do
            database="$(get "/v1/databases/$id")"
            state="$(jq -er '.state' <<<"$database")"
            if [[ "$state" != "$last" ]]; then
                echo "Database state: $state"
                last="$state"
            fi
            if [[ "$state" == "available" ]]; then
                available_port="$(jq -er '.instances[0].connection_info.port' <<<"$database")" || {
                    echo "Control Plane error: the database is available but has no instances" >&2
                    return 1
                }
                return 0
            fi
            if [[ "$state" == "failed" ]]; then
                echo "Control Plane error: the database has the state failed" >&2
                return 1
            fi
            sleep "$poll_seconds"
        done
        echo "Control Plane error: the database was not available after $wait_seconds seconds" >&2
        return 1
    }
    
    # Deletes the database and waits until the API no longer has it. The
    # Control Plane answers 409 whilst another task, such as the create, is
    # still running on the database, so the script repeats the request, as it
    # does when no reply arrived or the server failed. A 404 means that the
    # database is already gone.
    delete_database() {
        local id="$1" deadline=$((SECONDS + wait_seconds)) reply status
        local task_id task_status
    
        while true; do
            reply="$(request DELETE "/v1/databases/$id")"
            status="${reply##*$'\n'}"
            case "$status" in
                200) task_id="$(jq -er '.task.task_id' <<<"${reply%$'\n'*}")" || {
                         echo "Control Plane error: Unexpected response: ${reply%$'\n'*}" >&2
                         return 1
                     }
                     break ;;
                404) return 0 ;;
                000|409|5??) ;;
                *) echo "Control Plane error: HTTP $status, ${reply%$'\n'*}" >&2
                   return 1 ;;
            esac
            if ((SECONDS >= deadline)); then
                echo "Control Plane error: the delete was still failing after $wait_seconds seconds" >&2
                return 1
            fi
            sleep "$poll_seconds"
        done
    
        # The delete starts a task that removes the database; a 404 shows that
        # it has finished. Whilst the database is still there, the status of
        # the task shows whether the delete failed.
        while true; do
            reply="$(request GET "/v1/databases/$id")"
            status="${reply##*$'\n'}"
            case "$status" in
                404) return 0 ;;
                200) reply="$(request GET "/v1/databases/$id/tasks/$task_id")"
                     if [[ "${reply##*$'\n'}" == 200 ]]; then
                         task_status="$(jq -r '.status // empty' <<<"${reply%$'\n'*}")"
                         if [[ "$task_status" == failed || "$task_status" == canceled ]]; then
                             echo "Control Plane error: the delete task finished with the status $task_status" >&2
                             return 1
                         fi
                     fi ;;
                000|5??) ;;
                *) echo "Control Plane error: HTTP $status, ${reply%$'\n'*}" >&2
                   return 1 ;;
            esac
            if ((SECONDS >= deadline)); then
                echo "Control Plane error: the database was still present after $wait_seconds seconds" >&2
                return 1
            fi
            sleep "$poll_seconds"
        done
    }
    
    # Deletes the database, if the script may have created one. The EXIT trap
    # runs this function when the script finishes, whether the example
    # succeeded, failed, or was interrupted.
    cleanup() {
        local status=$?
        # Ignore further interrupts, so that they cannot cut the cleanup short.
        trap '' INT TERM
        if [[ "$created" == 1 ]]; then
            if delete_database "$database_id"; then
                echo "Deleted database"
            else
                echo "Delete the database $database_id by hand" >&2
                status=1
            fi
        fi
        exit "$status"
    }
    
    main() {
        database_id="" created=0 available_port=""
        if ! [[ "$port" =~ ^[1-9][0-9]{0,4}$ ]] || ((port > 65535)); then
            echo "CONTROL_PLANE_RECIPE_PORT must be a port number from 1 to 65535" >&2
            exit 1
        fi
    
        trap cleanup EXIT
        # Turn Ctrl-C and SIGTERM into a normal exit, so that cleanup runs.
        trap 'echo "Interrupted" >&2; exit 130' INT TERM
    
        local host reply status
        host="$(first_host)"
        echo "Host: $host"
    
        # The client chooses the ID of a new database, so the script knows it
        # before the request, and can delete the database even if the reply
        # never arrives. The random suffix keeps the ID unique.
        database_id="cookbook-recipe-$(od -An -N3 -tx1 /dev/urandom | tr -d ' \n')"
    
        # Clean up unless the server refused the request with a 4xx status,
        # which means it created nothing; a 409, for example, means that a
        # database with this ID already exists, and is not this script's to
        # delete.
        created=1
        reply="$(create_database "$database_id" "$host")"
        status="${reply##*$'\n'}"
        if [[ "$status" != 200 ]]; then
            [[ "$status" =~ ^4[0-9][0-9]$ ]] && created=0
            echo "Control Plane error: HTTP $status, ${reply%$'\n'*}" >&2
            return 1
        fi
        echo "Created database $database_id"
    
        wait_until_available "$database_id"
        echo "Database is available on port $available_port"
    }
    
    main
    
    ```

## Next Steps

The following resources provide more information about the topics in this
recipe:

- The [Following a Task](track_tasks.md) recipe shows how to read the log of
  the task that builds a database.
- The [Connecting to a Database](connect_database.md) recipe shows how to
  connect to a database once it is available.
- The
  [pgEdge Control Plane documentation](https://docs.pgedge.com/control-plane/v0-11/)
  describes every endpoint and setting.
- The [Contributing a Recipe](../contributing.md) page explains how to add a
  recipe or a language to the cookbook.
