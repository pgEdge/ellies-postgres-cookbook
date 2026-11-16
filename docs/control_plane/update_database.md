# Changing a Database's Settings

This recipe changes a Postgres setting of a database through a pgEdge Control
Plane server, waits for the update to finish, checks the new value over a
connection to the database, and then puts the original settings back. The
Control Plane writes the Postgres configuration of the instances that it
manages, so a change to a setting goes through the database's specification in
the API. Each step shows the code in every supported language; selecting a
language tab switches every tab on the site to that language.

These examples are for the Control Plane v0.11.0.

The program prints the following output for the cookbook database:

```text
Setting work_mem to 16MB
Update completed
work_mem is now 16MB
Restored the original settings
```

## Preparing the Ingredients

The examples assume a running Control Plane server with an available database,
and a database user with the `LOGIN` attribute. The
`scripts/start_control_plane.sh` script in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook)
starts a server in Docker and creates a database with the ID `cookbook` and a
`cookbook` user, and prints the password that it generated for that user.

The program calls the following endpoints:

| Endpoint                                 | Description                                    |
|------------------------------------------|------------------------------------------------|
| `GET /v1/databases/{id}`                 | Returns the database, with its specification.  |
| `POST /v1/databases/{id}`                | Replaces the specification, and starts a task. |
| `GET /v1/databases/{id}/tasks/{task_id}` | Returns a task, with its status.               |

An update sends the whole specification of the database, in a `spec` object,
and the Control Plane changes whatever differs from the current one. Each
program therefore reads the current specification, changes one field, and
sends it back. The `postgresql_conf` object of the specification holds extra
`postgresql.conf` settings, which the Control Plane merges with the settings
that it provides itself; it is missing until a setting is first added. The
specification that the API returns leaves out the
passwords of the database users, and an update that leaves them out keeps them
unchanged.

The following table lists the PostgreSQL driver that each example uses
alongside its HTTP client:

| Language   | PostgreSQL driver                                               |
|------------|-----------------------------------------------------------------|
| Python     | [psycopg](https://www.psycopg.org/psycopg3/)                    |
| TypeScript | [node-postgres](https://node-postgres.com/)                     |
| Java       | [pgJDBC](https://jdbc.postgresql.org/)                          |
| C#         | [Npgsql](https://www.npgsql.org/)                               |
| Go         | [pgx](https://github.com/jackc/pgx)                             |
| Rust       | [rust-postgres](https://github.com/rust-postgres/rust-postgres) |
| Ruby       | [ruby-pg](https://github.com/ged/ruby-pg)                       |
| curl       | [psql](https://www.postgresql.org/docs/current/app-psql.html)   |

The following tabs show the dependency declaration from each example project:

=== "Python"

    ```text
    # httpx, an HTTP client with a requests-like API.
    httpx>=0.28,<1
    # psycopg 3, with the pre-built binary package that bundles libpq.
    psycopg[binary]>=3.2,<4
    ```

=== "TypeScript"

    ```json
    {
      "name": "update-database",
      "private": true,
      "type": "module",
      "scripts": {
        "build": "tsc",
        "start": "node dist/main.js"
      },
      "dependencies": {
        "pg": "^8.23.1"
      },
      "devDependencies": {
        "@types/node": "^22.0.0",
        "@types/pg": "^8.23.1",
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
      <!-- The PostgreSQL JDBC driver (pgJDBC). -->
      <dependency>
        <groupId>org.postgresql</groupId>
        <artifactId>postgresql</artifactId>
        <version>42.7.14</version>
      </dependency>
    </dependencies>
    ```

=== "C#"

    ```xml
    <ItemGroup>
      <!-- Npgsql, the ADO.NET data provider for PostgreSQL. HttpClient and
           System.Text.Json are part of .NET. -->
      <PackageReference Include="Npgsql" Version="10.0.3" />
    </ItemGroup>
    ```

=== "Go"

    ```text
    // pgx is a pure Go driver and toolkit for PostgreSQL.
    require github.com/jackc/pgx/v5 v5.12.0
    
    require (
    	github.com/jackc/pgpassfile v1.0.0 // indirect
    	github.com/jackc/pgservicefile v0.0.0-20240606120523-5a60cdf6a761 // indirect
    	golang.org/x/text v0.41.0 // indirect
    )
    
    ```

=== "Rust"

    ```toml
    [dependencies]
    # The blocking client, with TLS from rustls and request and response bodies
    # as JSON; the default features add HTTP/2 and other things this example
    # does not use.
    reqwest = { version = "0.13", default-features = false, features = ["blocking", "json", "rustls"] }
    serde_json = "1"
    # The synchronous PostgreSQL client; tokio-postgres is the asynchronous
    # equivalent.
    postgres = "0.19"
    # Handling Ctrl-C, and with the termination feature SIGTERM, so that the
    # program can restore the settings before it exits.
    ctrlc = { version = "3", features = ["termination"] }
    ```

=== "Ruby"

    ```ruby
    source "https://rubygems.org"
    
    # Net::HTTP and json are part of the standard library. The pg gem wraps
    # libpq, so libpq and its headers must be installed.
    gem "pg", "~> 1.6"
    ```

## Importing the Libraries

Each program begins by importing its HTTP client, its JSON library and its
PostgreSQL driver, along with the standard library modules that it uses for
handling Ctrl-C. The curl script checks that `curl`, `jq` and `psql` are
installed. The following tabs show the imports for each language:

=== "Python"

    ```python
    import copy
    import os
    import signal
    import sys
    import time
    
    import httpx
    import psycopg
    ```

=== "TypeScript"

    ```typescript
    // Node.js provides fetch and AbortSignal as globals; setTimeout from
    // timers/promises returns a promise, which suits a polling loop. pg is
    // node-postgres.
    import { setTimeout as sleep } from "node:timers/promises";
    import pg from "pg";
    ```

=== "Java"

    ```java
    import java.io.IOException;
    import java.net.URI;
    import java.net.http.HttpClient;
    import java.net.http.HttpRequest;
    import java.net.http.HttpResponse;
    import java.net.http.HttpTimeoutException;
    import java.sql.Connection;
    import java.sql.DriverManager;
    import java.sql.PreparedStatement;
    import java.sql.ResultSet;
    import java.sql.SQLException;
    import java.time.Duration;
    import java.util.Map;
    import java.util.Properties;
    import java.util.concurrent.CompletableFuture;
    import java.util.concurrent.CountDownLatch;
    import java.util.concurrent.ExecutionException;
    import java.util.concurrent.TimeUnit;
    import java.util.concurrent.TimeoutException;
    
    import tools.jackson.core.JacksonException;
    import tools.jackson.databind.JsonNode;
    import tools.jackson.databind.ObjectMapper;
    import tools.jackson.databind.json.JsonMapper;
    import tools.jackson.databind.node.ObjectNode;
    ```

=== "C#"

    ```csharp
    using System.Diagnostics;
    using System.Net.Http.Json;
    using System.Runtime.InteropServices;
    using System.Text.Json;
    using System.Text.Json.Nodes;
    using Npgsql;
    ```

=== "Go"

    ```go
    import (
    	"bytes"
    	"context"
    	"encoding/json"
    	"errors"
    	"fmt"
    	"io"
    	"maps"
    	"net"
    	"net/http"
    	"net/url"
    	"os"
    	"os/signal"
    	"strconv"
    	"strings"
    	"syscall"
    	"time"
    
    	"github.com/jackc/pgx/v5"
    )
    
    ```

=== "Rust"

    ```rust
    use std::env;
    use std::error::Error;
    use std::fmt;
    use std::process::ExitCode;
    use std::sync::atomic::{AtomicBool, Ordering};
    use std::thread;
    use std::time::{Duration, Instant};
    
    use postgres::{Config, NoTls};
    use reqwest::blocking::Client;
    use reqwest::Method;
    use serde_json::{json, Value};
    ```

=== "Ruby"

    ```ruby
    require "json"
    require "net/http"
    require "pg"
    require "uri"
    ```

=== "curl"

    ```bash
    # Stop at the first failed command or unset variable, and make a failure
    # anywhere in a pipeline fail the whole pipeline.
    set -euo pipefail
    
    # The script needs curl to call the API, jq to read and build the JSON,
    # and psql to connect to the database.
    for tool in curl jq psql; do
        command -v "$tool" >/dev/null || { echo "Control Plane error: $tool is required" >&2; exit 1; }
    done
    ```

## Configuring the Program

The examples read their settings from environment variables, and treat an
empty value as unset. Each request, and the connection to the database, may
take up to 30 seconds, and the program waits up to 600 seconds for each task,
checking every five seconds. The setting and its new value are constants in
the program. The following table describes the environment variables:

| Variable                          | Default                 | Description                        |
|-----------------------------------|-------------------------|------------------------------------|
| `CONTROL_PLANE_URL`               | `http://localhost:3000` | The base URL of the Control Plane. |
| `CONTROL_PLANE_DATABASE_ID`       | `cookbook`              | The ID of the database.            |
| `CONTROL_PLANE_DATABASE_USER`     | `cookbook`              | The database user to connect as.   |
| `CONTROL_PLANE_DATABASE_PASSWORD` | None                    | The password of the database user. |

The following tabs show how each program reads its settings, and how it sends
a request to the server:

=== "Python"

    ```python
    # The or operator treats an empty variable as unset. The password has no
    # default; the Control Plane never returns it, so it comes from whoever
    # created the database user.
    BASE_URL = (os.environ.get("CONTROL_PLANE_URL") or "http://localhost:3000").rstrip("/")
    DATABASE_ID = os.environ.get("CONTROL_PLANE_DATABASE_ID") or "cookbook"
    DATABASE_USER = os.environ.get("CONTROL_PLANE_DATABASE_USER") or "cookbook"
    DATABASE_PASSWORD = os.environ.get("CONTROL_PLANE_DATABASE_PASSWORD") or None
    
    TIMEOUT_SECONDS = 30
    
    # The setting to change, and its new value.
    SETTING = "work_mem"
    VALUE = "16MB"
    
    # How long to wait for an update to finish, and how often to check.
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
    // password has no default; the Control Plane never returns it, so it
    // comes from whoever created the database user.
    const baseUrl = (process.env.CONTROL_PLANE_URL || "http://localhost:3000").replace(/\/+$/, "");
    const databaseId = process.env.CONTROL_PLANE_DATABASE_ID || "cookbook";
    const databaseUser = process.env.CONTROL_PLANE_DATABASE_USER || "cookbook";
    const databasePassword = process.env.CONTROL_PLANE_DATABASE_PASSWORD || undefined;
    
    const timeoutMs = 30_000;
    
    // The setting to change, and its new value.
    const setting = "work_mem";
    const value = "16MB";
    
    // How long to wait for an update to finish, and how often to check.
    const waitMs = 600_000;
    const pollMs = 5_000;
    
    // Ctrl-C and SIGTERM abort the signal below instead of ending the process,
    // which lets the program restore the settings before it exits. The
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
    
    // An error from the database connection or its query.
    class DatabaseError extends Error {}
    
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
    
    // The password has no default; the Control Plane never returns it, so
    // it comes from whoever created the database user.
    static final String BASE_URL =
            envOr("CONTROL_PLANE_URL", "http://localhost:3000")
                    .replaceAll("/+$", "");
    static final String DATABASE_ID = envOr("CONTROL_PLANE_DATABASE_ID", "cookbook");
    static final String DATABASE_USER = envOr("CONTROL_PLANE_DATABASE_USER", "cookbook");
    static final String DATABASE_PASSWORD = envOr("CONTROL_PLANE_DATABASE_PASSWORD", null);
    
    static final Duration TIMEOUT = Duration.ofSeconds(30);
    
    // The setting to change, and its new value.
    static final String SETTING = "work_mem";
    static final String VALUE = "16MB";
    
    // How long to wait for an update to finish, and how often to check.
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
    static string? EnvOr(string name, string? fallback) =>
        Environment.GetEnvironmentVariable(name) is { Length: > 0 } value
            ? value
            : fallback;
    
    static string BaseUrl() =>
        EnvOr("CONTROL_PLANE_URL", "http://localhost:3000")!.TrimEnd('/');
    
    static string DatabaseId() => EnvOr("CONTROL_PLANE_DATABASE_ID", "cookbook")!;
    
    // The password has no default; the Control Plane never returns it, so it
    // comes from whoever created the database user.
    static string DatabaseUser() => EnvOr("CONTROL_PLANE_DATABASE_USER", "cookbook")!;
    static string? DatabasePassword() => EnvOr("CONTROL_PLANE_DATABASE_PASSWORD", null);
    
    const int TimeoutSeconds = 30;
    
    // The setting to change, and its new value.
    const string Setting = "work_mem";
    const string Value = "16MB";
    
    // How long to wait for an update to finish, and how often to check.
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
    
    // The password has no default; the Control Plane never returns it, so it
    // comes from whoever created the database user.
    var (
    	baseURL          = strings.TrimRight(envOr("CONTROL_PLANE_URL", "http://localhost:3000"), "/")
    	databaseID       = envOr("CONTROL_PLANE_DATABASE_ID", "cookbook")
    	databaseUser     = envOr("CONTROL_PLANE_DATABASE_USER", "cookbook")
    	databasePassword = os.Getenv("CONTROL_PLANE_DATABASE_PASSWORD")
    )
    
    const timeout = 30 * time.Second
    
    // The setting to change, and its new value.
    const (
    	setting = "work_mem"
    	value   = "16MB"
    )
    
    // How long to wait for an update to finish, and how often to check.
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
    
    // dbError marks an error from the database connection or its query.
    type dbError struct{ err error }
    
    func (e *dbError) Error() string { return e.err.Error() }
    
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
    
    fn database_id() -> String {
        env_or("CONTROL_PLANE_DATABASE_ID", "cookbook")
    }
    
    const TIMEOUT: Duration = Duration::from_secs(30);
    
    // The setting to change, and its new value.
    const SETTING: &str = "work_mem";
    const VALUE: &str = "16MB";
    
    // How long to wait for an update to finish, and how often to check.
    const WAIT_FOR: Duration = Duration::from_secs(600);
    const POLL_INTERVAL: Duration = Duration::from_secs(5);
    
    /// Set by Ctrl-C or SIGTERM. The handler sets this flag instead of ending
    /// the process, which lets the program restore the settings before it
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
    
    /// Fails if check is true and the user has pressed Ctrl-C. A request does
    /// not stop for Ctrl-C, so the program checks the flag after each one; the
    /// cleanup passes false, so that it carries on.
    fn check_interrupted(check: bool) -> Result<(), BoxError> {
        if check && INTERRUPTED.load(Ordering::SeqCst) {
            return Err("interrupted".into());
        }
        Ok(())
    }
    
    /// Waits for the poll interval, checking for Ctrl-C as above.
    fn pause(check: bool) -> Result<(), BoxError> {
        let end = Instant::now() + POLL_INTERVAL;
        while Instant::now() < end {
            check_interrupted(check)?;
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
    
    # The password has no default; the Control Plane never returns it, so it
    # comes from whoever created the database user.
    BASE_URL = env_or("CONTROL_PLANE_URL", "http://localhost:3000").sub(%r{/+\z}, "")
    DATABASE_ID = env_or("CONTROL_PLANE_DATABASE_ID", "cookbook")
    DATABASE_USER = env_or("CONTROL_PLANE_DATABASE_USER", "cookbook")
    DATABASE_PASSWORD = env_or("CONTROL_PLANE_DATABASE_PASSWORD", nil)
    
    TIMEOUT_SECONDS = 30
    
    # The setting to change, and its new value.
    SETTING = "work_mem"
    VALUE = "16MB"
    
    # How long to wait for an update to finish, and how often to check.
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
    # The :- expansion treats an empty variable as unset. The password has no
    # default; the Control Plane never returns it, so it comes from whoever
    # created the database user.
    base_url="${CONTROL_PLANE_URL:-http://localhost:3000}"
    base_url="${base_url%/}"
    database_id="${CONTROL_PLANE_DATABASE_ID:-cookbook}"
    database_user="${CONTROL_PLANE_DATABASE_USER:-cookbook}"
    database_password="${CONTROL_PLANE_DATABASE_PASSWORD:-}"
    
    timeout_seconds=30
    
    # The setting to change, and its new value.
    setting=work_mem
    value=16MB
    
    # How long to wait for an update to finish, and how often to check.
    wait_seconds=600
    poll_seconds=5
    
    # Sends a request and prints the reply, followed by the HTTP status on a
    # line of its own; the status is 000 if no reply arrived. Any further
    # arguments go to curl, such as --data @- to send standard input as the
    # body.
    request() {
        local method="$1" path="$2"
        shift 2
        curl --silent --show-error --max-time "$timeout_seconds" --request "$method" \
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

## Sending the Update

Each program copies the specification, adds the setting to its
`postgresql_conf` object, and posts the result. The reply carries the task
that applies the change; the work happens in that task after the reply. The
following tabs show the update:

=== "Python"

    ```python
    def update_database(client: httpx.Client, spec: dict) -> str:
        """Sends a whole database spec as an update, and returns the ID of the
        task that applies it. The Control Plane compares the spec with the
        current one and changes only what differs; the work happens in the
        task after the reply."""
        reply = call(client, "POST", f"/v1/databases/{DATABASE_ID}", {"spec": spec})
        return reply["task"]["task_id"]
    
    
    def changed_spec(spec: dict) -> dict:
        """Returns a copy of the spec with the setting changed.
        postgresql_conf holds the Postgres settings that the Control Plane
        manages, and may be missing."""
        changed = copy.deepcopy(spec)
        changed.setdefault("postgresql_conf", {})[SETTING] = VALUE
        return changed
    ```

=== "TypeScript"

    ```typescript
    // The spec is kept as plain JSON, so that the update sends back every
    // field that the server returned, including any that this program does
    // not know about.
    type Spec = Record<string, unknown> & { postgresql_conf?: Record<string, unknown> };
    
    // Sends a whole database spec as an update, and returns the ID of the
    // task that applies it. The Control Plane compares the spec with the
    // current one and changes only what differs; the work happens in the task
    // after the reply.
    async function updateDatabase(spec: Spec, signal?: AbortSignal): Promise<string> {
      const reply = await call<{ task: { task_id: string } }>(
        "POST",
        `/v1/databases/${databaseId}`,
        { spec },
        signal,
      );
      return reply.task.task_id;
    }
    
    // Returns a copy of the spec with the setting changed. postgresql_conf
    // holds the Postgres settings that the Control Plane manages, and may be
    // missing.
    function changedSpec(spec: Spec): Spec {
      return { ...spec, postgresql_conf: { ...spec.postgresql_conf, [setting]: value } };
    }
    ```

=== "Java"

    ```java
    /**
     * Sends a whole database spec as an update, and returns the ID of the
     * task that applies it. The Control Plane compares the spec with the
     * current one and changes only what differs; the work happens in the
     * task after the reply. The spec is kept as a JSON tree, so that the
     * update sends back every field that the server returned.
     */
    static String updateDatabase(JsonNode spec)
            throws IOException, InterruptedException, ControlPlaneException {
        JsonNode reply = call("POST", "/v1/databases/" + DATABASE_ID, Map.of("spec", spec));
        String taskId = reply.path("task").path("task_id").asString("");
        if (taskId.isEmpty()) {
            throw new ControlPlaneException("Unexpected response: missing task_id");
        }
        return taskId;
    }
    
    /**
     * Returns a copy of the spec with the setting changed. postgresql_conf
     * holds the Postgres settings that the Control Plane manages, and may
     * be missing.
     */
    static JsonNode changedSpec(JsonNode spec) {
        ObjectNode changed = (ObjectNode) spec.deepCopy();
        if (!changed.path("postgresql_conf").isObject()) {
            changed.putObject("postgresql_conf");
        }
        ((ObjectNode) changed.get("postgresql_conf")).put(SETTING, VALUE);
        return changed;
    }
    ```

=== "C#"

    ```csharp
    // Sends a whole database spec as an update, and returns the ID of the task
    // that applies it. The Control Plane compares the spec with the current
    // one and changes only what differs; the work happens in the task after
    // the reply. The spec is kept as a JSON tree, so that the update sends back
    // every field that the server returned.
    static async Task<string> UpdateDatabaseAsync(
        HttpClient client, JsonObject spec, CancellationToken token)
    {
        var body = new JsonObject { ["spec"] = spec.DeepClone() };
        var reply = await CallAsync(
            client, HttpMethod.Post, $"/v1/databases/{DatabaseId()}", body, token);
        return reply["task"]?["task_id"]?.ToString()
            ?? throw new ControlPlaneException("Unexpected response: missing task_id");
    }
    
    // Returns a copy of the spec with the setting changed. postgresql_conf
    // holds the Postgres settings that the Control Plane manages, and may be
    // missing.
    static JsonObject ChangedSpec(JsonObject spec)
    {
        var changed = spec.DeepClone().AsObject();
        if (changed["postgresql_conf"] is not JsonObject conf)
        {
            conf = new JsonObject();
            changed["postgresql_conf"] = conf;
        }
        conf[Setting] = Value;
        return changed;
    }
    ```

=== "Go"

    ```go
    // spec is kept as plain JSON, so that the update sends back every field
    // that the server returned, including any that this program does not
    // know about.
    type spec = map[string]any
    
    // updateDatabase sends a whole database spec as an update, and returns
    // the ID of the task that applies it. The Control Plane compares the spec
    // with the current one and changes only what differs; the work happens in
    // the task after the reply.
    func updateDatabase(ctx context.Context, s spec) (string, error) {
    	var reply struct {
    		Task struct {
    			TaskID string `json:"task_id"`
    		} `json:"task"`
    	}
    	err := call(ctx, http.MethodPost, "/v1/databases/"+databaseID, map[string]any{"spec": s}, &reply)
    	return reply.Task.TaskID, err
    }
    
    // changedSpec returns a copy of the spec with the setting changed.
    // postgresql_conf holds the Postgres settings that the Control Plane
    // manages, and may be missing.
    func changedSpec(s spec) spec {
    	conf := map[string]any{}
    	if current, ok := s["postgresql_conf"].(map[string]any); ok {
    		maps.Copy(conf, current)
    	}
    	conf[setting] = value
    	changed := maps.Clone(s)
    	changed["postgresql_conf"] = conf
    	return changed
    }
    
    ```

=== "Rust"

    ```rust
    /// Sends a whole database spec as an update, and returns the ID of the
    /// task that applies it. The Control Plane compares the spec with the
    /// current one and changes only what differs; the work happens in the
    /// task after the reply.
    fn update_database(client: &Client, spec: &Value) -> Result<String, BoxError> {
        let reply = call(
            client,
            Method::POST,
            &format!("/v1/databases/{}", database_id()),
            Some(&json!({ "spec": spec })),
        )?;
        reply["task"]["task_id"]
            .as_str()
            .map(str::to_string)
            .ok_or_else(|| "Unexpected response: missing task_id".into())
    }
    
    /// Returns a copy of the spec with the setting changed. postgresql_conf
    /// holds the Postgres settings that the Control Plane manages, and may be
    /// missing.
    fn changed_spec(spec: &Value) -> Value {
        let mut changed = spec.clone();
        if !changed["postgresql_conf"].is_object() {
            changed["postgresql_conf"] = json!({});
        }
        changed["postgresql_conf"][SETTING] = json!(VALUE);
        changed
    }
    ```

=== "Ruby"

    ```ruby
    # Sends a whole database spec as an update, and returns the ID of the task
    # that applies it. The Control Plane compares the spec with the current
    # one and changes only what differs; the work happens in the task after
    # the reply.
    def update_database(spec)
      reply = call("POST", "/v1/databases/#{DATABASE_ID}", { "spec" => spec })
      reply.dig("task", "task_id") or
        raise ControlPlaneError, "Unexpected response: missing task_id"
    end
    
    # Returns a copy of the spec with the setting changed. postgresql_conf
    # holds the Postgres settings that the Control Plane manages, and may be
    # missing.
    def changed_spec(spec)
      spec.merge("postgresql_conf" => (spec["postgresql_conf"] || {}).merge(SETTING => VALUE))
    end
    ```

=== "curl"

    ```bash
    # Sends a whole database spec as an update, and prints the reply followed
    # by the HTTP status, as request() does. The Control Plane compares the
    # spec with the current one and changes only what differs; the work
    # happens in a task after the reply.
    update_database() {
        jq '{spec: .}' <<<"$1" |
            request POST "/v1/databases/$database_id" \
                --header "Content-Type: application/json" --data @-
    }
    
    # Prints the spec with the setting changed. postgresql_conf holds the
    # Postgres settings that the Control Plane manages, and may be missing.
    changed_spec() {
        jq --arg name "$setting" --arg value "$value" \
            '.postgresql_conf = ((.postgresql_conf // {}) + {($name): $value})' <<<"$1"
    }
    ```

## Waiting for the Task

Each program polls the task every five seconds until its status is
`completed`, and treats `failed` or `canceled` as an error. A poll that gets
no reply, a 409 or a server failure is repeated until the wait runs out, rather
than ending the wait. Against the
cookbook's one-node database, each update task took about 40 seconds. The
following tabs show the wait:

=== "Python"

    ```python
    def is_transient(error: Exception) -> bool:
        """Reports whether a failed request is worth repeating: no reply
        arrived, the server failed, or it answered 409, which the Control
        Plane does whilst another task is still running on the database."""
        if isinstance(error, httpx.TransportError):
            return True
        status = getattr(error, "status", None)
        return status is not None and (status == 409 or status >= 500)
    
    
    def wait_for_task(client: httpx.Client, task_id: str) -> None:
        """Polls a task until it finishes, and raises an error unless it
        completed. A failed poll is repeated if it is worth repeating."""
        deadline = time.monotonic() + WAIT_SECONDS
        while time.monotonic() < deadline:
            try:
                task = call(client, "GET", f"/v1/databases/{DATABASE_ID}/tasks/{task_id}")
            except (httpx.TransportError, ControlPlaneError) as e:
                if not is_transient(e):
                    raise
                time.sleep(POLL_SECONDS)
                continue
            status = task.get("status")
            if status == "completed":
                return
            if status in ("failed", "canceled"):
                raise ControlPlaneError(f"the task finished with the status {status}")
            time.sleep(POLL_SECONDS)
        raise ControlPlaneError(f"the task was still running after {WAIT_SECONDS} seconds")
    ```

=== "TypeScript"

    ```typescript
    // Reports whether a failed request is worth repeating: no reply arrived,
    // the server failed, or it answered 409, which the Control Plane does
    // whilst another task, such as the update, is still running on the
    // database.
    function isTransient(err: unknown): boolean {
      if (!(err instanceof ControlPlaneError)) {
        return true;
      }
      return err.status !== undefined && (err.status === 409 || err.status >= 500);
    }
    
    // Polls a task until it finishes, and throws an error unless it
    // completed. A failed poll is repeated if it is worth repeating. The
    // cleanup passes a signal that never aborts.
    async function waitForTask(taskId: string, signal: AbortSignal = interrupt.signal): Promise<void> {
      const deadline = Date.now() + waitMs;
      while (Date.now() < deadline) {
        let task: { status?: string } = {};
        try {
          task = await call<{ status?: string }>(
            "GET",
            `/v1/databases/${databaseId}/tasks/${taskId}`,
            undefined,
            signal,
          );
        } catch (err) {
          if (signal.aborted || !isTransient(err)) {
            throw err;
          }
        }
        if (task.status === "completed") {
          return;
        }
        if (task.status === "failed" || task.status === "canceled") {
          throw new ControlPlaneError(`the task finished with the status ${task.status}`);
        }
        await sleep(pollMs, undefined, { signal });
      }
      throw new ControlPlaneError(`the task was still running after ${waitMs / 1000} seconds`);
    }
    ```

=== "Java"

    ```java
    /**
     * Reports whether a failed request is worth repeating: no reply
     * arrived, the server failed, or it answered 409, which the Control
     * Plane does whilst another task, such as the update, is still running
     * on the database.
     */
    static boolean isTransient(Exception e) {
        if (e instanceof ControlPlaneException cpe) {
            return cpe.status == 409 || cpe.status >= 500;
        }
        return e instanceof IOException;
    }
    
    /**
     * Polls a task until it finishes, and throws unless it completed. A
     * failed poll is repeated if it is worth repeating.
     */
    static void waitForTask(String taskId)
            throws IOException, InterruptedException, ControlPlaneException {
        String path = "/v1/databases/" + DATABASE_ID + "/tasks/" + taskId;
        long deadline = System.nanoTime() + WAIT_FOR.toNanos();
        while (System.nanoTime() < deadline) {
            String status = "";
            try {
                status = call("GET", path, null).path("status").asString("");
            } catch (IOException | ControlPlaneException e) {
                if (!isTransient(e)) {
                    throw e;
                }
            }
            if (status.equals("completed")) {
                return;
            }
            if (status.equals("failed") || status.equals("canceled")) {
                throw new ControlPlaneException(
                        "the task finished with the status " + status);
            }
            Thread.sleep(POLL_INTERVAL.toMillis());
        }
        throw new ControlPlaneException("the task was still running after "
                + WAIT_FOR.toSeconds() + " seconds");
    }
    ```

=== "C#"

    ```csharp
    // Reports whether a failed request is worth repeating: no reply arrived,
    // the server failed, or it answered 409, which the Control Plane does
    // whilst another task, such as the update, is still running on the
    // database. TaskCanceledException is a timeout unless the caller's token
    // was cancelled, which the caller checks.
    static bool IsTransient(Exception e) => e switch
    {
        ControlPlaneException cpe => cpe.Status is 409 or >= 500,
        HttpRequestException or TaskCanceledException => true,
        _ => false,
    };
    
    // Polls a task until it finishes, and throws an exception unless it
    // completed. A failed poll is repeated if it is worth repeating.
    static async Task WaitForTaskAsync(HttpClient client, string taskId, CancellationToken token)
    {
        var clock = Stopwatch.StartNew();
        while (clock.Elapsed.TotalSeconds < WaitSeconds)
        {
            string? status = null;
            try
            {
                var task = await CallAsync(
                    client, HttpMethod.Get, $"/v1/databases/{DatabaseId()}/tasks/{taskId}", null, token);
                status = task["status"]?.ToString();
            }
            catch (Exception e) when (IsTransient(e) && !token.IsCancellationRequested)
            {
                // Check again after the pause.
            }
            if (status == "completed")
            {
                return;
            }
            if (status is "failed" or "canceled")
            {
                throw new ControlPlaneException($"the task finished with the status {status}");
            }
            await Task.Delay(TimeSpan.FromSeconds(PollSeconds), token);
        }
        throw new ControlPlaneException($"the task was still running after {WaitSeconds} seconds");
    }
    ```

=== "Go"

    ```go
    // isTransient reports whether a failed request is worth repeating: no
    // reply arrived, the server failed, or it answered 409, which the Control
    // Plane does whilst another task is still running on the database.
    func isTransient(err error) bool {
    	status := statusOf(err)
    	return status == 0 || status == http.StatusConflict || status >= 500
    }
    
    // waitForTask polls a task until it finishes, and returns an error unless
    // it completed. A failed poll is repeated if it is worth repeating.
    func waitForTask(ctx context.Context, taskID string) error {
    	deadline := time.Now().Add(waitFor)
    	for time.Now().Before(deadline) {
    		var task struct {
    			Status string `json:"status"`
    		}
    		err := call(ctx, http.MethodGet, "/v1/databases/"+databaseID+"/tasks/"+taskID, nil, &task)
    		if err != nil && (ctx.Err() != nil || !isTransient(err)) {
    			return err
    		}
    		switch {
    		case err != nil:
    		case task.Status == "completed":
    			return nil
    		case task.Status == "failed" || task.Status == "canceled":
    			return fmt.Errorf("the task finished with the status %s", task.Status)
    		}
    		if err := sleep(ctx); err != nil {
    			return err
    		}
    	}
    	return fmt.Errorf("the task was still running after %d seconds", int(waitFor.Seconds()))
    }
    
    ```

=== "Rust"

    ```rust
    /// Reports whether a failed request is worth repeating: no reply arrived,
    /// the server failed, or it answered 409, which the Control Plane does
    /// whilst another task, such as the update, is still running on the
    /// database.
    fn is_transient(error: &BoxError) -> bool {
        match status_of(error) {
            Some(status) => status == 409 || status >= 500,
            None => error.is::<reqwest::Error>(),
        }
    }
    
    /// Polls a task until it finishes, and fails unless it completed. A failed
    /// poll is repeated if it is worth repeating. When check is true, Ctrl-C
    /// ends the wait.
    fn wait_for_task(client: &Client, task_id: &str, check: bool) -> Result<(), BoxError> {
        let path = format!("/v1/databases/{}/tasks/{task_id}", database_id());
        let deadline = Instant::now() + WAIT_FOR;
        while Instant::now() < deadline {
            let task = call(client, Method::GET, &path, None);
            check_interrupted(check)?;
            match task {
                Ok(task) => match task["status"].as_str() {
                    Some("completed") => return Ok(()),
                    Some(status @ ("failed" | "canceled")) => {
                        return Err(format!("the task finished with the status {status}").into())
                    }
                    _ => {}
                },
                Err(e) if !is_transient(&e) => return Err(e),
                Err(_) => {}
            }
            pause(check)?;
        }
        Err(format!("the task was still running after {} seconds", WAIT_FOR.as_secs()).into())
    }
    ```

=== "Ruby"

    ```ruby
    # Reports whether a failed request is worth repeating: no reply arrived,
    # the server failed, or it answered 409, which the Control Plane does
    # whilst another task is still running on the database.
    def transient?(error)
      return true unless error.is_a?(ControlPlaneError)
    
      !error.status.nil? && (error.status == 409 || error.status >= 500)
    end
    
    # Polls a task until it finishes, and raises an error unless it completed.
    # A failed poll is repeated if it is worth repeating.
    def wait_for_task(task_id)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + WAIT_SECONDS
      while Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
        begin
          status = call("GET", "/v1/databases/#{DATABASE_ID}/tasks/#{task_id}")["status"]
        rescue ControlPlaneError, *NETWORK_ERRORS => e
          raise unless transient?(e)
    
          sleep POLL_SECONDS
          next
        end
        return if status == "completed"
        if %w[failed canceled].include?(status)
          raise ControlPlaneError, "the task finished with the status #{status}"
        end
    
        sleep POLL_SECONDS
      end
      raise ControlPlaneError, "the task was still running after #{WAIT_SECONDS} seconds"
    end
    ```

=== "curl"

    ```bash
    # Polls a task until it finishes, and fails unless it completed. A poll
    # that gets no reply, a 409 or a server failure is repeated. The function
    # returns on every error itself, because the restore runs it where errexit
    # does not apply.
    wait_for_task() {
        local task_id="$1" deadline=$((SECONDS + wait_seconds)) reply code status
        while ((SECONDS < deadline)); do
            reply="$(request GET "/v1/databases/$database_id/tasks/$task_id")"
            code="${reply##*$'\n'}"
            case "$code" in
                200) status="$(jq -er '.status | strings' <<<"${reply%$'\n'*}")" || {
                         echo "Control Plane error: Unexpected response: ${reply%$'\n'*}" >&2
                         return 1
                     }
                     case "$status" in
                         completed) return 0 ;;
                         failed|canceled)
                             echo "Control Plane error: the task finished with the status $status" >&2
                             return 1 ;;
                     esac ;;
                000|409|5??) ;;
                *) echo "Control Plane error: HTTP $code, ${reply%$'\n'*}" >&2
                   return 1 ;;
            esac
            sleep "$poll_seconds"
        done
        echo "Control Plane error: the task was still running after $wait_seconds seconds" >&2
        return 1
    }
    ```

## Checking the Setting

Each program connects to the first available instance, as the
[Connecting to a Database](connect_database.md) recipe does, and reads the
current value of the setting. The following tabs show the check:

=== "Python"

    ```python
    def show_setting(client: httpx.Client) -> str:
        """Connects to the first available instance and returns the current
        value of the setting. Each instance runs one node, and its
        connection_info holds the address and port that clients use."""
        database = call(client, "GET", f"/v1/databases/{DATABASE_ID}")
        for instance in database.get("instances") or []:
            info = instance.get("connection_info") or {}
            if instance.get("state") == "available" and info.get("addresses"):
                break
        else:
            raise ControlPlaneError(f"no available instance of {DATABASE_ID}")
    
        # The with block closes the connection when it exits, whether or not
        # an error occurred.
        with psycopg.connect(
            host=info["addresses"][0],
            port=info["port"],
            dbname=database["spec"]["database_name"],
            user=DATABASE_USER,
            password=DATABASE_PASSWORD,
            connect_timeout=TIMEOUT_SECONDS,
        ) as conn:
            return conn.execute("SELECT current_setting(%s)", (SETTING,)).fetchone()[0]
    ```

=== "TypeScript"

    ```typescript
    interface Database {
      spec: { database_name: string };
      instances?: {
        state?: string;
        connection_info?: { addresses?: string[]; port?: number };
      }[];
    }
    
    // Connects to the first available instance and returns the current value
    // of the setting. Each instance runs one node, and its connection_info
    // holds the address and port that clients use.
    async function showSetting(): Promise<string> {
      const database = await call<Database>("GET", `/v1/databases/${databaseId}`);
      const info = database.instances?.find(
        (i) => i.state === "available" && i.connection_info?.addresses?.length,
      )?.connection_info;
      if (!info) {
        throw new ControlPlaneError(`no available instance of ${databaseId}`);
      }
    
      const client = new pg.Client({
        host: info.addresses![0],
        port: info.port,
        database: database.spec.database_name,
        user: databaseUser,
        password: databasePassword,
        connectionTimeoutMillis: timeoutMs,
      });
      try {
        await client.connect();
      } catch (err) {
        throw new DatabaseError(describe(err));
      }
      try {
        const result = await client.query<{ current_setting: string }>(
          "SELECT current_setting($1)",
          [setting],
        );
        return result.rows[0].current_setting;
      } catch (err) {
        throw new DatabaseError(describe(err));
      } finally {
        // Close the connection whether or not the query failed.
        await client.end();
      }
    }
    ```

=== "Java"

    ```java
    /**
     * Connects to the first available instance and returns the current
     * value of the setting. Each instance runs one node, and its
     * connection_info holds the address and port that clients use.
     */
    static String showSetting()
            throws IOException, InterruptedException, ControlPlaneException, SQLException {
        JsonNode database = call("GET", "/v1/databases/" + DATABASE_ID, null);
        JsonNode info = null;
        for (JsonNode instance : database.path("instances")) {
            JsonNode candidate = instance.path("connection_info");
            if (instance.path("state").asString("").equals("available")
                    && !candidate.path("addresses").isEmpty()) {
                info = candidate;
                break;
            }
        }
        if (info == null) {
            throw new ControlPlaneException("no available instance of " + DATABASE_ID);
        }
    
        Properties props = new Properties();
        props.setProperty("user", DATABASE_USER);
        props.setProperty("password", DATABASE_PASSWORD);
        props.setProperty("connectTimeout", String.valueOf(TIMEOUT.toSeconds()));
        props.setProperty("loginTimeout", String.valueOf(TIMEOUT.toSeconds()));
        String url = "jdbc:postgresql://" + info.path("addresses").get(0).asString()
                + ":" + info.path("port").asInt() + "/"
                + database.path("spec").path("database_name").asString();
    
        // try-with-resources closes the connection and statement when the
        // block exits, whether or not the query failed.
        try (Connection conn = DriverManager.getConnection(url, props);
             PreparedStatement stmt = conn.prepareStatement("SELECT current_setting(?)")) {
            stmt.setString(1, SETTING);
            try (ResultSet rs = stmt.executeQuery()) {
                rs.next();
                return rs.getString(1);
            }
        }
    }
    ```

=== "C#"

    ```csharp
    // Connects to the first available instance and returns the current value
    // of the setting. Each instance runs one node, and its connection_info
    // holds the address and port that clients use.
    static async Task<string> ShowSettingAsync(HttpClient client, CancellationToken token)
    {
        var database = await CallAsync(
            client, HttpMethod.Get, $"/v1/databases/{DatabaseId()}", null, token);
        var info = (database["instances"] as JsonArray ?? [])
            .FirstOrDefault(i => i?["state"]?.ToString() == "available"
                && i["connection_info"]?["addresses"] is JsonArray { Count: > 0 })
            ?["connection_info"]
            ?? throw new ControlPlaneException($"no available instance of {DatabaseId()}");
    
        // The builder takes care of quoting any special characters.
        var connectionString = new NpgsqlConnectionStringBuilder
        {
            Host = info["addresses"]![0]!.ToString(),
            Port = info["port"]!.GetValue<int>(),
            Database = database["spec"]?["database_name"]?.ToString(),
            Username = DatabaseUser(),
            Password = DatabasePassword(),
            Timeout = TimeoutSeconds,
        }.ConnectionString;
    
        // await using closes the connection and command when the block exits,
        // whether or not the query failed.
        await using var conn = new NpgsqlConnection(connectionString);
        await conn.OpenAsync(token);
        await using var cmd = new NpgsqlCommand("SELECT current_setting($1)", conn);
        cmd.Parameters.Add(new NpgsqlParameter { Value = Setting });
        return (string)(await cmd.ExecuteScalarAsync(token))!;
    }
    ```

=== "Go"

    ```go
    // showSetting connects to the first available instance and returns the
    // current value of the setting. Each instance runs one node, and its
    // connection_info holds the address and port that clients use.
    func showSetting(ctx context.Context) (string, error) {
    	var database struct {
    		Spec struct {
    			DatabaseName string `json:"database_name"`
    		} `json:"spec"`
    		Instances []struct {
    			State          string `json:"state"`
    			ConnectionInfo struct {
    				Addresses []string `json:"addresses"`
    				Port      int      `json:"port"`
    			} `json:"connection_info"`
    		} `json:"instances"`
    	}
    	if err := call(ctx, http.MethodGet, "/v1/databases/"+databaseID, nil, &database); err != nil {
    		return "", err
    	}
    	host, port := "", 0
    	for _, i := range database.Instances {
    		if i.State == "available" && len(i.ConnectionInfo.Addresses) > 0 {
    			host, port = i.ConnectionInfo.Addresses[0], i.ConnectionInfo.Port
    			break
    		}
    	}
    	if host == "" {
    		return "", fmt.Errorf("no available instance of %s", databaseID)
    	}
    
    	// net/url takes care of escaping any special characters in the user
    	// name, password, or database name.
    	u := url.URL{
    		Scheme:   "postgres",
    		User:     url.UserPassword(databaseUser, databasePassword),
    		Host:     net.JoinHostPort(host, strconv.Itoa(port)),
    		Path:     "/" + database.Spec.DatabaseName,
    		RawQuery: "connect_timeout=30",
    	}
    	conn, err := pgx.Connect(ctx, u.String())
    	if err != nil {
    		return "", &dbError{err}
    	}
    	// Close the connection when the function returns, whether or not the
    	// query failed.
    	defer conn.Close(ctx)
    
    	var current string
    	if err := conn.QueryRow(ctx, "SELECT current_setting($1)", setting).Scan(&current); err != nil {
    		return "", &dbError{err}
    	}
    	return current, nil
    }
    
    ```

=== "Rust"

    ```rust
    /// The result of show_setting: a database error is reported differently
    /// from a Control Plane one.
    enum ShowError {
        ControlPlane(BoxError),
        Database(postgres::Error),
    }
    
    impl From<BoxError> for ShowError {
        fn from(e: BoxError) -> Self {
            ShowError::ControlPlane(e)
        }
    }
    
    impl From<postgres::Error> for ShowError {
        fn from(e: postgres::Error) -> Self {
            ShowError::Database(e)
        }
    }
    
    /// Connects to the first available instance and returns the current
    /// value of the setting. Each instance runs one node, and its
    /// connection_info holds the address and port that clients use. NoTls
    /// disables TLS, which keeps this example free of certificate set-up;
    /// connections over an untrusted network should use TLS.
    fn show_setting(client: &Client, password: &str) -> Result<String, ShowError> {
        let database = call(client, Method::GET, &format!("/v1/databases/{}", database_id()), None)?;
        let info = database["instances"]
            .as_array()
            .into_iter()
            .flatten()
            .find(|i| i["state"] == "available" && i["connection_info"]["addresses"][0].is_string())
            .map(|i| &i["connection_info"])
            .ok_or_else(|| BoxError::from(format!("no available instance of {}", database_id())))?;
        let port = info["port"]
            .as_u64()
            .and_then(|p| u16::try_from(p).ok())
            .ok_or_else(|| BoxError::from("Unexpected response: missing port"))?;
    
        let mut db = Config::new()
            .host(info["addresses"][0].as_str().unwrap_or_default())
            .port(port)
            .dbname(database["spec"]["database_name"].as_str().unwrap_or_default())
            .user(&env_or("CONTROL_PLANE_DATABASE_USER", "cookbook"))
            .password(password)
            .connect_timeout(TIMEOUT)
            .connect(NoTls)?;
        let current: String = db.query_one("SELECT current_setting($1)", &[&SETTING])?.get(0);
        // The client closes its connection when it goes out of scope.
        Ok(current)
    }
    ```

=== "Ruby"

    ```ruby
    # Connects to the first available instance and returns the current value
    # of the setting. Each instance runs one node, and its connection_info
    # holds the address and port that clients use.
    def show_setting
      database = call("GET", "/v1/databases/#{DATABASE_ID}")
      instance = (database["instances"] || []).find do |i|
        i["state"] == "available" && !Array(i.dig("connection_info", "addresses")).empty?
      end
      raise ControlPlaneError, "no available instance of #{DATABASE_ID}" unless instance
    
      info = instance["connection_info"]
      conn = PG.connect(
        host: info["addresses"][0], port: info["port"],
        dbname: database.dig("spec", "database_name"),
        user: DATABASE_USER, password: DATABASE_PASSWORD,
        connect_timeout: TIMEOUT_SECONDS
      )
      begin
        conn.exec_params("SELECT current_setting($1)", [SETTING]).getvalue(0, 0)
      ensure
        # Close the connection whether or not the query failed.
        conn.close
      end
    end
    ```

=== "curl"

    ```bash
    # Connects to the first available instance with psql and prints the
    # current value of the setting. Each instance runs one node, and its
    # connection_info holds the address and port that clients use. PGPASSWORD
    # passes the password through the environment, so it never appears in the
    # process list.
    show_setting() {
        local database name address port
        database="$(get "/v1/databases/$database_id")"
        read -r name address port < <(jq -er '
            .spec.database_name as $name
            | first(.instances[]?
                    | select(.state == "available"
                             and (.connection_info.addresses | length) > 0))
            | "\($name) \(.connection_info.addresses[0]) \(.connection_info.port)"
            ' <<<"$database") || {
            echo "Control Plane error: no available instance of $database_id" >&2
            return 1
        }
        PGPASSWORD="$database_password" PGCONNECT_TIMEOUT="$timeout_seconds" \
            psql -X -A -t -v ON_ERROR_STOP=1 \
            --host "$address" --port "$port" \
            --username "$database_user" --dbname "$name" \
            -c "SHOW $setting" || {
            echo "Database error: could not query $name" >&2
            return 1
        }
    }
    ```

## Restoring the Original Settings

To restore the settings, each program sends the original specification back,
without the setting, and waits for that task as well. The Control Plane
answers 409 whilst another task, such as the update, is still running on the
database, so each program repeats the request until the server accepts it, as
it does when no reply arrived or the server failed. The following tabs show
the restore:

=== "Python"

    ```python
    def restore(client: httpx.Client, spec: dict) -> None:
        """Sends the original spec back and waits for the task. The Control
        Plane answers 409 whilst another task, such as the update, is still
        running on the database, so the program repeats the request, as it
        does when no reply arrived or the server failed."""
        deadline = time.monotonic() + WAIT_SECONDS
        while True:
            try:
                task_id = update_database(client, spec)
                break
            except (httpx.TransportError, ControlPlaneError) as e:
                if not is_transient(e) or time.monotonic() >= deadline:
                    raise
                time.sleep(POLL_SECONDS)
        wait_for_task(client, task_id)
    ```

=== "TypeScript"

    ```typescript
    // Sends the original spec back and waits for the task. The Control Plane
    // answers 409 whilst another task, such as the update, is still running on
    // the database, so the program repeats the request, as it does when no
    // reply arrived or the server failed. The cleanup runs after Ctrl-C, so
    // its requests and waits use a signal that never aborts.
    async function restore(spec: Spec): Promise<void> {
      const never = new AbortController().signal;
      const deadline = Date.now() + waitMs;
      let taskId: string;
      for (;;) {
        try {
          taskId = await updateDatabase(spec, never);
          break;
        } catch (err) {
          if (!isTransient(err) || Date.now() >= deadline) {
            throw err;
          }
          await sleep(pollMs);
        }
      }
      await waitForTask(taskId, never);
    }
    ```

=== "Java"

    ```java
    /**
     * Sends the original spec back and waits for the task. The Control
     * Plane answers 409 whilst another task, such as the update, is still
     * running on the database, so the program repeats the request, as it
     * does when no reply arrived or the server failed.
     */
    static void restore(JsonNode original)
            throws IOException, InterruptedException, ControlPlaneException {
        long deadline = System.nanoTime() + WAIT_FOR.toNanos();
        String taskId;
        while (true) {
            try {
                taskId = updateDatabase(original);
                break;
            } catch (IOException | ControlPlaneException e) {
                if (!isTransient(e) || System.nanoTime() >= deadline) {
                    throw e;
                }
            }
            Thread.sleep(POLL_INTERVAL.toMillis());
        }
        waitForTask(taskId);
    }
    ```

=== "C#"

    ```csharp
    // Sends the original spec back and waits for the task. The Control Plane
    // answers 409 whilst another task, such as the update, is still running on
    // the database, so the program repeats the request, as it does when no
    // reply arrived or the server failed. TaskCanceledException is a timeout
    // here, because the cleanup runs after Ctrl-C and so passes no token that
    // can be cancelled.
    static async Task RestoreAsync(HttpClient client, JsonObject original)
    {
        var clock = Stopwatch.StartNew();
        string taskId;
        while (true)
        {
            try
            {
                taskId = await UpdateDatabaseAsync(client, original, CancellationToken.None);
                break;
            }
            catch (Exception e) when (IsTransient(e) && clock.Elapsed.TotalSeconds < WaitSeconds)
            {
                await Task.Delay(TimeSpan.FromSeconds(PollSeconds));
            }
        }
        await WaitForTaskAsync(client, taskId, CancellationToken.None);
    }
    ```

=== "Go"

    ```go
    // restore sends the original spec back and waits for the task. The
    // Control Plane answers 409 whilst another task, such as the update, is
    // still running on the database, so the program repeats the request, as
    // it does when no reply arrived or the server failed. The cleanup runs
    // after Ctrl-C, so it uses a context that never ends.
    func restore(original spec) error {
    	ctx := context.Background()
    	deadline := time.Now().Add(waitFor)
    	for {
    		taskID, err := updateDatabase(ctx, original)
    		if err == nil {
    			return waitForTask(ctx, taskID)
    		}
    		if !isTransient(err) || time.Now().After(deadline) {
    			return err
    		}
    		sleep(ctx)
    	}
    }
    
    ```

=== "Rust"

    ```rust
    /// Sends the original spec back and waits for the task. The Control Plane
    /// answers 409 whilst another task, such as the update, is still running
    /// on the database, so the program repeats the request, as it does when
    /// no reply arrived or the server failed. The cleanup runs after Ctrl-C,
    /// so its waits do not check the flag.
    fn restore(client: &Client, original: &Value) -> Result<(), BoxError> {
        let deadline = Instant::now() + WAIT_FOR;
        let task_id = loop {
            match update_database(client, original) {
                Ok(task_id) => break task_id,
                Err(e) => {
                    if !is_transient(&e) || Instant::now() >= deadline {
                        return Err(e);
                    }
                    thread::sleep(POLL_INTERVAL);
                }
            }
        };
        wait_for_task(client, &task_id, false)
    }
    ```

=== "Ruby"

    ```ruby
    # Sends the original spec back and waits for the task. The Control Plane
    # answers 409 whilst another task, such as the update, is still running on
    # the database, so the program repeats the request, as it does when no
    # reply arrived or the server failed.
    def restore(spec)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + WAIT_SECONDS
      begin
        task_id = update_database(spec)
      rescue ControlPlaneError, *NETWORK_ERRORS => e
        raise if !transient?(e) || Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
    
        sleep POLL_SECONDS
        retry
      end
      wait_for_task(task_id)
    end
    ```

=== "curl"

    ```bash
    # Sends the original spec back and waits for the task. The Control Plane
    # answers 409 whilst another task, such as the update, is still running on
    # the database, so the script repeats the request, as it does when no
    # reply arrived or the server failed. The cleanup runs this function where
    # errexit does not apply, so it checks every step itself.
    restore() {
        local deadline=$((SECONDS + wait_seconds)) reply status task_id
        while true; do
            reply="$(update_database "$original")"
            status="${reply##*$'\n'}"
            case "$status" in
                200) break ;;
                000|409|5??) ;;
                *) echo "Control Plane error: HTTP $status, ${reply%$'\n'*}" >&2
                   return 1 ;;
            esac
            if ((SECONDS >= deadline)); then
                echo "Control Plane error: the restore was still failing after $wait_seconds seconds" >&2
                return 1
            fi
            sleep "$poll_seconds"
        done
        task_id="$(jq -er '.task.task_id | strings' <<<"${reply%$'\n'*}")" || {
            echo "Control Plane error: Unexpected response: ${reply%$'\n'*}" >&2
            return 1
        }
        wait_for_task "$task_id"
    }
    ```

## Handling Errors

The main part of each program reads the original specification, sends the
update, waits for it, and checks the setting, then restores the original
settings whether the example succeeded, failed, or was interrupted. Ctrl-C and
`SIGTERM` stop the example without ending the process, so that the cleanup can
run; a signal that arrives during a step that cannot be interrupted, such as
some drivers' connection attempts, takes effect when that step returns. The
program sets a flag before the update request, because the change may
take effect even when no reply arrives, and clears it only if the server
refuses the request with a 4xx status, which means that it changed nothing.
If the restore fails, the program names the database whose settings to restore
by hand. The following tabs show the main part of each program:

=== "Python"

    ```python
    def stop(*_) -> None:
        """Handles SIGTERM like Ctrl-C, by raising KeyboardInterrupt."""
        raise KeyboardInterrupt
    
    
    def main() -> int:
        if not DATABASE_PASSWORD:
            print("CONTROL_PLANE_DATABASE_PASSWORD must be set", file=sys.stderr)
            return 1
    
        # Turn SIGTERM into a KeyboardInterrupt, so that the finally block
        # runs, as it does for Ctrl-C.
        signal.signal(signal.SIGTERM, stop)
    
        exit_code = 0
        changed = False
        original = None
        with httpx.Client(base_url=BASE_URL, timeout=TIMEOUT_SECONDS) as client:
            try:
                # The spec that the API returns leaves out the passwords of the
                # database users, and an update may leave them out too, which
                # keeps them unchanged.
                original = call(client, "GET", f"/v1/databases/{DATABASE_ID}")["spec"]
    
                # Restore unless the server refused the request with a 4xx
                # status, which means that it changed nothing.
                print(f"Setting {SETTING} to {VALUE}")
                changed = True
                try:
                    task_id = update_database(client, changed_spec(original))
                except ControlPlaneError as e:
                    if e.status is not None and 400 <= e.status < 500:
                        changed = False
                    raise
                wait_for_task(client, task_id)
                print("Update completed")
    
                print(f"{SETTING} is now {show_setting(client)}")
            # httpx.HTTPError is the base class for failures to reach the
            # server, such as a refused connection or a timeout.
            except (httpx.HTTPError, ControlPlaneError, KeyError) as e:
                print(f"Control Plane error: {e}", file=sys.stderr)
                exit_code = 1
            # psycopg.Error is the base class for the driver's errors, including
            # a failure to connect.
            except psycopg.Error as e:
                print(f"Database error: {e}", file=sys.stderr)
                exit_code = 1
            except KeyboardInterrupt:
                print("Interrupted", file=sys.stderr)
                exit_code = 130
            finally:
                # Restore the original settings whether the example succeeded,
                # failed, or was interrupted. Ignore further interrupts, so
                # that they cannot cut the cleanup short.
                signal.signal(signal.SIGINT, signal.SIG_IGN)
                signal.signal(signal.SIGTERM, signal.SIG_IGN)
                if changed:
                    try:
                        restore(client, original)
                        print("Restored the original settings")
                    except (httpx.HTTPError, ControlPlaneError, KeyError) as e:
                        print(f"Control Plane error: {e}", file=sys.stderr)
                        print(f"Restore the settings of the database {DATABASE_ID} by hand",
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
      if (databasePassword === undefined) {
        console.error("CONTROL_PLANE_DATABASE_PASSWORD must be set");
        return 1;
      }
    
      let exitCode = 0;
      let changed = false;
      let original: Spec | undefined;
      try {
        // The spec that the API returns leaves out the passwords of the
        // database users, and an update may leave them out too, which keeps
        // them unchanged.
        original = (await call<{ spec: Spec }>("GET", `/v1/databases/${databaseId}`)).spec;
    
        // Restore unless the server refused the request with a 4xx status,
        // which means that it changed nothing.
        console.log(`Setting ${setting} to ${value}`);
        changed = true;
        let taskId: string;
        try {
          taskId = await updateDatabase(changedSpec(original));
        } catch (err) {
          if (err instanceof ControlPlaneError && err.status && err.status < 500) {
            changed = false;
          }
          throw err;
        }
        await waitForTask(taskId);
        console.log("Update completed");
    
        console.log(`${setting} is now ${await showSetting()}`);
        // The database connection does not stop for Ctrl-C, so check whether
        // a signal arrived whilst it was open.
        if (interrupt.signal.aborted) {
          throw new Error("Interrupted");
        }
      } catch (err) {
        if (interrupt.signal.aborted) {
          console.error("Interrupted");
          exitCode = 130;
        } else if (err instanceof DatabaseError) {
          console.error(`Database error: ${err.message}`);
          exitCode = 1;
        } else {
          console.error(`Control Plane error: ${describe(err)}`);
          exitCode = 1;
        }
      } finally {
        // Restore the original settings whether the example succeeded,
        // failed, or was interrupted.
        if (changed && original) {
          try {
            await restore(original);
            console.log("Restored the original settings");
          } catch (err) {
            console.error(`Control Plane error: ${describe(err)}`);
            console.error(`Restore the settings of the database ${databaseId} by hand`);
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
    // and waits until it has restored the settings. The lock and the
    // cleaning flag stop the hook from interrupting the cleanup itself.
    static final Object LOCK = new Object();
    static final CountDownLatch FINISHED = new CountDownLatch(1);
    static boolean cleaning = false;
    static volatile boolean shuttingDown = false;
    
    public static void main(String[] args) {
        if (DATABASE_PASSWORD == null) {
            System.err.println("CONTROL_PLANE_DATABASE_PASSWORD must be set");
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
        boolean changed = false;
        JsonNode original = null;
        try {
            // The spec that the API returns leaves out the passwords of the
            // database users, and an update may leave them out too, which
            // keeps them unchanged.
            original = call("GET", "/v1/databases/" + DATABASE_ID, null).path("spec");
    
            // Restore unless the server refused the request with a 4xx
            // status, which means that it changed nothing.
            System.out.println("Setting " + SETTING + " to " + VALUE);
            changed = true;
            String taskId;
            try {
                taskId = updateDatabase(changedSpec(original));
            } catch (ControlPlaneException e) {
                if (e.status >= 400 && e.status < 500) {
                    changed = false;
                }
                throw e;
            }
            waitForTask(taskId);
            System.out.println("Update completed");
    
            System.out.println(SETTING + " is now " + showSetting());
        } catch (InterruptedException e) {
            System.err.println("Interrupted");
            exitCode = 130;
        // SQLException covers the driver's errors, including a failure to
        // connect.
        } catch (SQLException e) {
            System.err.println("Database error: " + e.getMessage());
            exitCode = 1;
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
                // The database connection does not stop for a signal, so
                // check whether one arrived whilst it was open.
                if (Thread.interrupted() && exitCode == 0) {
                    System.err.println("Interrupted");
                    exitCode = 130;
                }
            }
            // Restore the original settings whether the example succeeded,
            // failed, or was interrupted.
            if (changed) {
                try {
                    restore(original);
                    System.out.println("Restored the original settings");
                } catch (IOException | InterruptedException | ControlPlaneException e) {
                    System.err.println("Control Plane error: " + e);
                    System.err.println("Restore the settings of the database "
                            + DATABASE_ID + " by hand");
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
    if (DatabasePassword() is null)
    {
        Console.Error.WriteLine("CONTROL_PLANE_DATABASE_PASSWORD must be set");
        return 1;
    }
    
    // Ctrl-C and SIGTERM cancel the token below instead of ending the process,
    // which lets the program restore the settings before it exits. The
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
    var changed = false;
    JsonObject original = [];
    try
    {
        // The spec that the API returns leaves out the passwords of the
        // database users, and an update may leave them out too, which keeps
        // them unchanged.
        var database = await CallAsync(
            client, HttpMethod.Get, $"/v1/databases/{DatabaseId()}", null, interrupt.Token);
        original = database["spec"] as JsonObject
            ?? throw new ControlPlaneException("Unexpected response: missing spec");
    
        // Restore unless the server refused the request with a 4xx status,
        // which means that it changed nothing.
        Console.WriteLine($"Setting {Setting} to {Value}");
        changed = true;
        string taskId;
        try
        {
            taskId = await UpdateDatabaseAsync(client, ChangedSpec(original), interrupt.Token);
        }
        catch (ControlPlaneException e) when (e.Status is >= 400 and < 500)
        {
            changed = false;
            throw;
        }
        await WaitForTaskAsync(client, taskId, interrupt.Token);
        Console.WriteLine("Update completed");
    
        Console.WriteLine($"{Setting} is now {await ShowSettingAsync(client, interrupt.Token)}");
        // A signal that arrives after the last request still counts.
        interrupt.Token.ThrowIfCancellationRequested();
    }
    catch (OperationCanceledException) when (interrupt.IsCancellationRequested)
    {
        Console.Error.WriteLine("Interrupted");
        exitCode = 130;
    }
    // NpgsqlException is the base class for the driver's errors, including a
    // failure to connect.
    catch (NpgsqlException e)
    {
        Console.Error.WriteLine($"Database error: {e.Message}");
        exitCode = 1;
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
        // Restore the original settings whether the example succeeded, failed,
        // or was interrupted.
        if (changed)
        {
            try
            {
                await RestoreAsync(client, original);
                Console.WriteLine("Restored the original settings");
            }
            catch (Exception e) when (
                e is HttpRequestException or TaskCanceledException or ControlPlaneException)
            {
                Console.Error.WriteLine($"Control Plane error: {e.Message}");
                Console.Error.WriteLine($"Restore the settings of the database {DatabaseId()} by hand");
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
    // run changes the setting and checks it, and returns any error to the
    // caller. It fills in original, and sets changed once the settings may
    // have changed, so that the caller knows whether to restore them.
    func run(ctx context.Context, original *spec, changed *bool) error {
    	// The spec that the API returns leaves out the passwords of the
    	// database users, and an update may leave them out too, which keeps
    	// them unchanged.
    	var database struct {
    		Spec spec `json:"spec"`
    	}
    	if err := call(ctx, http.MethodGet, "/v1/databases/"+databaseID, nil, &database); err != nil {
    		return err
    	}
    	*original = database.Spec
    
    	// Restore unless the server refused the request with a 4xx status,
    	// which means that it changed nothing.
    	fmt.Printf("Setting %s to %s\n", setting, value)
    	*changed = true
    	taskID, err := updateDatabase(ctx, changedSpec(*original))
    	if err != nil {
    		if status := statusOf(err); status >= 400 && status < 500 {
    			*changed = false
    		}
    		return err
    	}
    	if err := waitForTask(ctx, taskID); err != nil {
    		return err
    	}
    	fmt.Println("Update completed")
    
    	current, err := showSetting(ctx)
    	if err != nil {
    		return err
    	}
    	fmt.Printf("%s is now %s\n", setting, current)
    	return nil
    }
    
    // main restores the original settings whether the example succeeded,
    // failed, or was interrupted, and exits with a non-zero status after a
    // failure.
    func main() {
    	if databasePassword == "" {
    		fmt.Fprintln(os.Stderr, "CONTROL_PLANE_DATABASE_PASSWORD must be set")
    		os.Exit(1)
    	}
    
    	// Ctrl-C and SIGTERM end the context instead of the process, which
    	// lets the program restore the settings before it exits. The handlers
    	// stay in place, so a further Ctrl-C does not end the process during
    	// the cleanup either.
    	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
    
    	exitCode := 0
    	changed := false
    	var original spec
    	if err := run(ctx, &original, &changed); err != nil {
    		var dbErr *dbError
    		switch {
    		case ctx.Err() != nil:
    			fmt.Fprintln(os.Stderr, "Interrupted")
    			exitCode = 130
    		case errors.As(err, &dbErr):
    			fmt.Fprintf(os.Stderr, "Database error: %v\n", err)
    			exitCode = 1
    		default:
    			fmt.Fprintf(os.Stderr, "Control Plane error: %v\n", err)
    			exitCode = 1
    		}
    	}
    
    	if changed {
    		if err := restore(original); err != nil {
    			fmt.Fprintf(os.Stderr, "Control Plane error: %v\n", err)
    			fmt.Fprintf(os.Stderr, "Restore the settings of the database %s by hand\n", databaseID)
    			exitCode = 1
    		} else {
    			fmt.Println("Restored the original settings")
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
    fn report(prefix: &str, e: &dyn Error) {
        eprintln!("{prefix}: {e}");
        let mut cause = e.source();
        while let Some(c) = cause {
            eprintln!("  caused by: {c}");
            cause = c.source();
        }
    }
    
    /// Changes the setting and checks it. It fills in original, and sets
    /// changed once the settings may have changed, so that the caller knows
    /// whether to restore them.
    fn run(client: &Client, password: &str, original: &mut Value, changed: &mut bool) -> Result<(), ShowError> {
        // The spec that the API returns leaves out the passwords of the
        // database users, and an update may leave them out too, which keeps
        // them unchanged.
        let database = call(client, Method::GET, &format!("/v1/databases/{}", database_id()), None)?;
        check_interrupted(true)?;
        *original = database["spec"].clone();
    
        // Restore unless the server refused the request with a 4xx status,
        // which means that it changed nothing.
        println!("Setting {SETTING} to {VALUE}");
        *changed = true;
        let task_id = match update_database(client, &changed_spec(original)) {
            Ok(task_id) => task_id,
            Err(e) => {
                if matches!(status_of(&e), Some(400..=499)) {
                    *changed = false;
                }
                return Err(e.into());
            }
        };
        check_interrupted(true)?;
        wait_for_task(client, &task_id, true)?;
        println!("Update completed");
    
        println!("{SETTING} is now {}", show_setting(client, password)?);
        Ok(())
    }
    
    /// Restores the original settings whether the example succeeded, failed,
    /// or was interrupted, and exits with a failure status after a failure.
    fn main() -> ExitCode {
        let password = env_or("CONTROL_PLANE_DATABASE_PASSWORD", "");
        if password.is_empty() {
            eprintln!("CONTROL_PLANE_DATABASE_PASSWORD must be set");
            return ExitCode::FAILURE;
        }
    
        // The handler stays in place, so a further Ctrl-C does not end the
        // process during the cleanup either. The termination feature of the
        // ctrlc crate makes it handle SIGTERM too.
        if let Err(e) = ctrlc::set_handler(|| INTERRUPTED.store(true, Ordering::SeqCst)) {
            report("Control Plane error", &e);
            return ExitCode::FAILURE;
        }
    
        let client = match Client::builder().timeout(TIMEOUT).build() {
            Ok(client) => client,
            Err(e) => {
                report("Control Plane error", &e);
                return ExitCode::FAILURE;
            }
        };
    
        let mut original = Value::Null;
        let mut changed = false;
        let mut exit_code = ExitCode::SUCCESS;
        // A signal that arrives after the last request, or whilst the program
        // is connected to the database, still counts.
        let result = run(&client, &password, &mut original, &mut changed);
        if INTERRUPTED.load(Ordering::SeqCst) {
            eprintln!("Interrupted");
            exit_code = ExitCode::from(130);
        } else if let Err(e) = result {
            exit_code = ExitCode::FAILURE;
            match e {
                ShowError::ControlPlane(e) => report("Control Plane error", e.as_ref()),
                ShowError::Database(e) => report("Database error", &e),
            }
        }
    
        if changed {
            match restore(&client, &original) {
                Ok(()) => println!("Restored the original settings"),
                Err(e) => {
                    report("Control Plane error", e.as_ref());
                    eprintln!("Restore the settings of the database {} by hand", database_id());
                    exit_code = ExitCode::FAILURE;
                }
            }
        }
        exit_code
    }
    ```

=== "Ruby"

    ```ruby
    if DATABASE_PASSWORD.nil?
      warn "CONTROL_PLANE_DATABASE_PASSWORD must be set"
      exit 1
    end
    
    exit_code = 0
    changed = false
    original = nil
    begin
      # The spec that the API returns leaves out the passwords of the database
      # users, and an update may leave them out too, which keeps them
      # unchanged.
      original = call("GET", "/v1/databases/#{DATABASE_ID}")["spec"]
    
      # Restore unless the server refused the request with a 4xx status, which
      # means that it changed nothing.
      puts "Setting #{SETTING} to #{VALUE}"
      changed = true
      begin
        task_id = update_database(changed_spec(original))
      rescue ControlPlaneError => e
        changed = false if e.status&.between?(400, 499)
        raise
      end
      wait_for_task(task_id)
      puts "Update completed"
    
      puts "#{SETTING} is now #{show_setting}"
    rescue ControlPlaneError, *NETWORK_ERRORS => e
      warn "Control Plane error: #{e.message}"
      exit_code = 1
    # PG::Error is the base class for the gem's errors, including a failure to
    # connect.
    rescue PG::Error => e
      warn "Database error: #{e.message}"
      exit_code = 1
    # Ctrl-C raises Interrupt, and SIGTERM raises SignalException.
    rescue SignalException
      warn "Interrupted"
      exit_code = 130
    ensure
      # Restore the original settings whether the example succeeded, failed,
      # or was interrupted. Ignore further interrupts, so that they cannot cut
      # the cleanup short.
      trap("INT", "IGNORE")
      trap("TERM", "IGNORE")
      if changed
        begin
          restore(original)
          puts "Restored the original settings"
        rescue ControlPlaneError, *NETWORK_ERRORS => e
          warn "Control Plane error: #{e.message}"
          warn "Restore the settings of the database #{DATABASE_ID} by hand"
          exit_code = 1
        end
      end
    end
    
    exit exit_code
    ```

=== "curl"

    ```bash
    # Restores the original settings, if the script may have changed them. The
    # EXIT trap runs this function when the script finishes, whether the
    # example succeeded, failed, or was interrupted.
    cleanup() {
        local status=$?
        # Ignore further interrupts, so that they cannot cut the cleanup short.
        trap '' INT TERM
        if [[ "$changed" == 1 ]]; then
            if restore; then
                echo "Restored the original settings"
            else
                echo "Restore the settings of the database $database_id by hand" >&2
                status=1
            fi
        fi
        exit "$status"
    }
    
    main() {
        original="" changed=0
        trap cleanup EXIT
        # Turn Ctrl-C and SIGTERM into a normal exit, so that cleanup runs.
        trap 'echo "Interrupted" >&2; exit 130' INT TERM
    
        if [[ -z "$database_password" ]]; then
            echo "CONTROL_PLANE_DATABASE_PASSWORD must be set" >&2
            return 1
        fi
    
        # The spec that the API returns leaves out the passwords of the
        # database users, and an update may leave them out too, which keeps
        # them unchanged.
        local reply status task_id current
        original="$(get "/v1/databases/$database_id" | jq -e '.spec')"
    
        # Restore unless the server refused the request with a 4xx status,
        # which means that it changed nothing.
        echo "Setting $setting to $value"
        changed=1
        reply="$(update_database "$(changed_spec "$original")")"
        status="${reply##*$'\n'}"
        if [[ "$status" != 200 ]]; then
            [[ "$status" =~ ^4[0-9][0-9]$ ]] && changed=0
            echo "Control Plane error: HTTP $status, ${reply%$'\n'*}" >&2
            return 1
        fi
        task_id="$(jq -er '.task.task_id | strings' <<<"${reply%$'\n'*}")" || {
            echo "Control Plane error: Unexpected response: ${reply%$'\n'*}" >&2
            return 1
        }
        wait_for_task "$task_id"
        echo "Update completed"
    
        current="$(show_setting)"
        echo "$setting is now $current"
    }
    
    main
    ```

## Running the Example

The complete project for each language is available in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/control_plane/update_database).
Set the environment variables for your Control Plane and database user, and
then run the command for your language from the corresponding project
directory. The following tabs show the commands that build and run each
example:

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
    Changing a Postgres setting of a pgEdge Control Plane database, checking
    it from a connection, and putting the original settings back, using httpx
    and psycopg.
    
    These examples are for the Control Plane v0.11.0.
    
    The program restores the original settings on every path: after a
    success, after a failure, and after Ctrl-C.
    
    Copyright (c) 2026, pgEdge, Inc.
    This code is released under the PostgreSQL License.
    """
    
    import copy
    import os
    import signal
    import sys
    import time
    
    import httpx
    import psycopg
    
    
    # The or operator treats an empty variable as unset. The password has no
    # default; the Control Plane never returns it, so it comes from whoever
    # created the database user.
    BASE_URL = (os.environ.get("CONTROL_PLANE_URL") or "http://localhost:3000").rstrip("/")
    DATABASE_ID = os.environ.get("CONTROL_PLANE_DATABASE_ID") or "cookbook"
    DATABASE_USER = os.environ.get("CONTROL_PLANE_DATABASE_USER") or "cookbook"
    DATABASE_PASSWORD = os.environ.get("CONTROL_PLANE_DATABASE_PASSWORD") or None
    
    TIMEOUT_SECONDS = 30
    
    # The setting to change, and its new value.
    SETTING = "work_mem"
    VALUE = "16MB"
    
    # How long to wait for an update to finish, and how often to check.
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
    
    
    def update_database(client: httpx.Client, spec: dict) -> str:
        """Sends a whole database spec as an update, and returns the ID of the
        task that applies it. The Control Plane compares the spec with the
        current one and changes only what differs; the work happens in the
        task after the reply."""
        reply = call(client, "POST", f"/v1/databases/{DATABASE_ID}", {"spec": spec})
        return reply["task"]["task_id"]
    
    
    def changed_spec(spec: dict) -> dict:
        """Returns a copy of the spec with the setting changed.
        postgresql_conf holds the Postgres settings that the Control Plane
        manages, and may be missing."""
        changed = copy.deepcopy(spec)
        changed.setdefault("postgresql_conf", {})[SETTING] = VALUE
        return changed
    
    
    def is_transient(error: Exception) -> bool:
        """Reports whether a failed request is worth repeating: no reply
        arrived, the server failed, or it answered 409, which the Control
        Plane does whilst another task is still running on the database."""
        if isinstance(error, httpx.TransportError):
            return True
        status = getattr(error, "status", None)
        return status is not None and (status == 409 or status >= 500)
    
    
    def wait_for_task(client: httpx.Client, task_id: str) -> None:
        """Polls a task until it finishes, and raises an error unless it
        completed. A failed poll is repeated if it is worth repeating."""
        deadline = time.monotonic() + WAIT_SECONDS
        while time.monotonic() < deadline:
            try:
                task = call(client, "GET", f"/v1/databases/{DATABASE_ID}/tasks/{task_id}")
            except (httpx.TransportError, ControlPlaneError) as e:
                if not is_transient(e):
                    raise
                time.sleep(POLL_SECONDS)
                continue
            status = task.get("status")
            if status == "completed":
                return
            if status in ("failed", "canceled"):
                raise ControlPlaneError(f"the task finished with the status {status}")
            time.sleep(POLL_SECONDS)
        raise ControlPlaneError(f"the task was still running after {WAIT_SECONDS} seconds")
    
    
    def show_setting(client: httpx.Client) -> str:
        """Connects to the first available instance and returns the current
        value of the setting. Each instance runs one node, and its
        connection_info holds the address and port that clients use."""
        database = call(client, "GET", f"/v1/databases/{DATABASE_ID}")
        for instance in database.get("instances") or []:
            info = instance.get("connection_info") or {}
            if instance.get("state") == "available" and info.get("addresses"):
                break
        else:
            raise ControlPlaneError(f"no available instance of {DATABASE_ID}")
    
        # The with block closes the connection when it exits, whether or not
        # an error occurred.
        with psycopg.connect(
            host=info["addresses"][0],
            port=info["port"],
            dbname=database["spec"]["database_name"],
            user=DATABASE_USER,
            password=DATABASE_PASSWORD,
            connect_timeout=TIMEOUT_SECONDS,
        ) as conn:
            return conn.execute("SELECT current_setting(%s)", (SETTING,)).fetchone()[0]
    
    
    def restore(client: httpx.Client, spec: dict) -> None:
        """Sends the original spec back and waits for the task. The Control
        Plane answers 409 whilst another task, such as the update, is still
        running on the database, so the program repeats the request, as it
        does when no reply arrived or the server failed."""
        deadline = time.monotonic() + WAIT_SECONDS
        while True:
            try:
                task_id = update_database(client, spec)
                break
            except (httpx.TransportError, ControlPlaneError) as e:
                if not is_transient(e) or time.monotonic() >= deadline:
                    raise
                time.sleep(POLL_SECONDS)
        wait_for_task(client, task_id)
    
    
    def stop(*_) -> None:
        """Handles SIGTERM like Ctrl-C, by raising KeyboardInterrupt."""
        raise KeyboardInterrupt
    
    
    def main() -> int:
        if not DATABASE_PASSWORD:
            print("CONTROL_PLANE_DATABASE_PASSWORD must be set", file=sys.stderr)
            return 1
    
        # Turn SIGTERM into a KeyboardInterrupt, so that the finally block
        # runs, as it does for Ctrl-C.
        signal.signal(signal.SIGTERM, stop)
    
        exit_code = 0
        changed = False
        original = None
        with httpx.Client(base_url=BASE_URL, timeout=TIMEOUT_SECONDS) as client:
            try:
                # The spec that the API returns leaves out the passwords of the
                # database users, and an update may leave them out too, which
                # keeps them unchanged.
                original = call(client, "GET", f"/v1/databases/{DATABASE_ID}")["spec"]
    
                # Restore unless the server refused the request with a 4xx
                # status, which means that it changed nothing.
                print(f"Setting {SETTING} to {VALUE}")
                changed = True
                try:
                    task_id = update_database(client, changed_spec(original))
                except ControlPlaneError as e:
                    if e.status is not None and 400 <= e.status < 500:
                        changed = False
                    raise
                wait_for_task(client, task_id)
                print("Update completed")
    
                print(f"{SETTING} is now {show_setting(client)}")
            # httpx.HTTPError is the base class for failures to reach the
            # server, such as a refused connection or a timeout.
            except (httpx.HTTPError, ControlPlaneError, KeyError) as e:
                print(f"Control Plane error: {e}", file=sys.stderr)
                exit_code = 1
            # psycopg.Error is the base class for the driver's errors, including
            # a failure to connect.
            except psycopg.Error as e:
                print(f"Database error: {e}", file=sys.stderr)
                exit_code = 1
            except KeyboardInterrupt:
                print("Interrupted", file=sys.stderr)
                exit_code = 130
            finally:
                # Restore the original settings whether the example succeeded,
                # failed, or was interrupted. Ignore further interrupts, so
                # that they cannot cut the cleanup short.
                signal.signal(signal.SIGINT, signal.SIG_IGN)
                signal.signal(signal.SIGTERM, signal.SIG_IGN)
                if changed:
                    try:
                        restore(client, original)
                        print("Restored the original settings")
                    except (httpx.HTTPError, ControlPlaneError, KeyError) as e:
                        print(f"Control Plane error: {e}", file=sys.stderr)
                        print(f"Restore the settings of the database {DATABASE_ID} by hand",
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
     * Changing a Postgres setting of a pgEdge Control Plane database, checking
     * it from a connection, and putting the original settings back, using the
     * built-in fetch and node-postgres.
     *
     * These examples are for the Control Plane v0.11.0.
     *
     * The program restores the original settings on every path: after a
     * success, after a failure, and after Ctrl-C.
     *
     * Copyright (c) 2026, pgEdge, Inc.
     * This code is released under the PostgreSQL License.
     */
    
    // Node.js provides fetch and AbortSignal as globals; setTimeout from
    // timers/promises returns a promise, which suits a polling loop. pg is
    // node-postgres.
    import { setTimeout as sleep } from "node:timers/promises";
    import pg from "pg";
    
    // The || operator, unlike ??, also treats an empty variable as unset. The
    // password has no default; the Control Plane never returns it, so it
    // comes from whoever created the database user.
    const baseUrl = (process.env.CONTROL_PLANE_URL || "http://localhost:3000").replace(/\/+$/, "");
    const databaseId = process.env.CONTROL_PLANE_DATABASE_ID || "cookbook";
    const databaseUser = process.env.CONTROL_PLANE_DATABASE_USER || "cookbook";
    const databasePassword = process.env.CONTROL_PLANE_DATABASE_PASSWORD || undefined;
    
    const timeoutMs = 30_000;
    
    // The setting to change, and its new value.
    const setting = "work_mem";
    const value = "16MB";
    
    // How long to wait for an update to finish, and how often to check.
    const waitMs = 600_000;
    const pollMs = 5_000;
    
    // Ctrl-C and SIGTERM abort the signal below instead of ending the process,
    // which lets the program restore the settings before it exits. The
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
    
    // An error from the database connection or its query.
    class DatabaseError extends Error {}
    
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
    
    // The spec is kept as plain JSON, so that the update sends back every
    // field that the server returned, including any that this program does
    // not know about.
    type Spec = Record<string, unknown> & { postgresql_conf?: Record<string, unknown> };
    
    // Sends a whole database spec as an update, and returns the ID of the
    // task that applies it. The Control Plane compares the spec with the
    // current one and changes only what differs; the work happens in the task
    // after the reply.
    async function updateDatabase(spec: Spec, signal?: AbortSignal): Promise<string> {
      const reply = await call<{ task: { task_id: string } }>(
        "POST",
        `/v1/databases/${databaseId}`,
        { spec },
        signal,
      );
      return reply.task.task_id;
    }
    
    // Returns a copy of the spec with the setting changed. postgresql_conf
    // holds the Postgres settings that the Control Plane manages, and may be
    // missing.
    function changedSpec(spec: Spec): Spec {
      return { ...spec, postgresql_conf: { ...spec.postgresql_conf, [setting]: value } };
    }
    
    // Reports whether a failed request is worth repeating: no reply arrived,
    // the server failed, or it answered 409, which the Control Plane does
    // whilst another task, such as the update, is still running on the
    // database.
    function isTransient(err: unknown): boolean {
      if (!(err instanceof ControlPlaneError)) {
        return true;
      }
      return err.status !== undefined && (err.status === 409 || err.status >= 500);
    }
    
    // Polls a task until it finishes, and throws an error unless it
    // completed. A failed poll is repeated if it is worth repeating. The
    // cleanup passes a signal that never aborts.
    async function waitForTask(taskId: string, signal: AbortSignal = interrupt.signal): Promise<void> {
      const deadline = Date.now() + waitMs;
      while (Date.now() < deadline) {
        let task: { status?: string } = {};
        try {
          task = await call<{ status?: string }>(
            "GET",
            `/v1/databases/${databaseId}/tasks/${taskId}`,
            undefined,
            signal,
          );
        } catch (err) {
          if (signal.aborted || !isTransient(err)) {
            throw err;
          }
        }
        if (task.status === "completed") {
          return;
        }
        if (task.status === "failed" || task.status === "canceled") {
          throw new ControlPlaneError(`the task finished with the status ${task.status}`);
        }
        await sleep(pollMs, undefined, { signal });
      }
      throw new ControlPlaneError(`the task was still running after ${waitMs / 1000} seconds`);
    }
    
    interface Database {
      spec: { database_name: string };
      instances?: {
        state?: string;
        connection_info?: { addresses?: string[]; port?: number };
      }[];
    }
    
    // Connects to the first available instance and returns the current value
    // of the setting. Each instance runs one node, and its connection_info
    // holds the address and port that clients use.
    async function showSetting(): Promise<string> {
      const database = await call<Database>("GET", `/v1/databases/${databaseId}`);
      const info = database.instances?.find(
        (i) => i.state === "available" && i.connection_info?.addresses?.length,
      )?.connection_info;
      if (!info) {
        throw new ControlPlaneError(`no available instance of ${databaseId}`);
      }
    
      const client = new pg.Client({
        host: info.addresses![0],
        port: info.port,
        database: database.spec.database_name,
        user: databaseUser,
        password: databasePassword,
        connectionTimeoutMillis: timeoutMs,
      });
      try {
        await client.connect();
      } catch (err) {
        throw new DatabaseError(describe(err));
      }
      try {
        const result = await client.query<{ current_setting: string }>(
          "SELECT current_setting($1)",
          [setting],
        );
        return result.rows[0].current_setting;
      } catch (err) {
        throw new DatabaseError(describe(err));
      } finally {
        // Close the connection whether or not the query failed.
        await client.end();
      }
    }
    
    // Sends the original spec back and waits for the task. The Control Plane
    // answers 409 whilst another task, such as the update, is still running on
    // the database, so the program repeats the request, as it does when no
    // reply arrived or the server failed. The cleanup runs after Ctrl-C, so
    // its requests and waits use a signal that never aborts.
    async function restore(spec: Spec): Promise<void> {
      const never = new AbortController().signal;
      const deadline = Date.now() + waitMs;
      let taskId: string;
      for (;;) {
        try {
          taskId = await updateDatabase(spec, never);
          break;
        } catch (err) {
          if (!isTransient(err) || Date.now() >= deadline) {
            throw err;
          }
          await sleep(pollMs);
        }
      }
      await waitForTask(taskId, never);
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
      if (databasePassword === undefined) {
        console.error("CONTROL_PLANE_DATABASE_PASSWORD must be set");
        return 1;
      }
    
      let exitCode = 0;
      let changed = false;
      let original: Spec | undefined;
      try {
        // The spec that the API returns leaves out the passwords of the
        // database users, and an update may leave them out too, which keeps
        // them unchanged.
        original = (await call<{ spec: Spec }>("GET", `/v1/databases/${databaseId}`)).spec;
    
        // Restore unless the server refused the request with a 4xx status,
        // which means that it changed nothing.
        console.log(`Setting ${setting} to ${value}`);
        changed = true;
        let taskId: string;
        try {
          taskId = await updateDatabase(changedSpec(original));
        } catch (err) {
          if (err instanceof ControlPlaneError && err.status && err.status < 500) {
            changed = false;
          }
          throw err;
        }
        await waitForTask(taskId);
        console.log("Update completed");
    
        console.log(`${setting} is now ${await showSetting()}`);
        // The database connection does not stop for Ctrl-C, so check whether
        // a signal arrived whilst it was open.
        if (interrupt.signal.aborted) {
          throw new Error("Interrupted");
        }
      } catch (err) {
        if (interrupt.signal.aborted) {
          console.error("Interrupted");
          exitCode = 130;
        } else if (err instanceof DatabaseError) {
          console.error(`Database error: ${err.message}`);
          exitCode = 1;
        } else {
          console.error(`Control Plane error: ${describe(err)}`);
          exitCode = 1;
        }
      } finally {
        // Restore the original settings whether the example succeeded,
        // failed, or was interrupted.
        if (changed && original) {
          try {
            await restore(original);
            console.log("Restored the original settings");
          } catch (err) {
            console.error(`Control Plane error: ${describe(err)}`);
            console.error(`Restore the settings of the database ${databaseId} by hand`);
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
     * Changing a Postgres setting of a pgEdge Control Plane database, checking
     * it from a connection, and putting the original settings back, using
     * java.net.http, Jackson and pgJDBC.
     *
     * These examples are for the Control Plane v0.11.0.
     *
     * The program restores the original settings on every path: after a
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
    import java.sql.Connection;
    import java.sql.DriverManager;
    import java.sql.PreparedStatement;
    import java.sql.ResultSet;
    import java.sql.SQLException;
    import java.time.Duration;
    import java.util.Map;
    import java.util.Properties;
    import java.util.concurrent.CompletableFuture;
    import java.util.concurrent.CountDownLatch;
    import java.util.concurrent.ExecutionException;
    import java.util.concurrent.TimeUnit;
    import java.util.concurrent.TimeoutException;
    
    import tools.jackson.core.JacksonException;
    import tools.jackson.databind.JsonNode;
    import tools.jackson.databind.ObjectMapper;
    import tools.jackson.databind.json.JsonMapper;
    import tools.jackson.databind.node.ObjectNode;
    
    public class Main {
    
        /** Returns the value of an environment variable, or a fallback. */
        static String envOr(String name, String fallback) {
            String value = System.getenv(name);
            return (value != null && !value.isEmpty()) ? value : fallback;
        }
    
        // The password has no default; the Control Plane never returns it, so
        // it comes from whoever created the database user.
        static final String BASE_URL =
                envOr("CONTROL_PLANE_URL", "http://localhost:3000")
                        .replaceAll("/+$", "");
        static final String DATABASE_ID = envOr("CONTROL_PLANE_DATABASE_ID", "cookbook");
        static final String DATABASE_USER = envOr("CONTROL_PLANE_DATABASE_USER", "cookbook");
        static final String DATABASE_PASSWORD = envOr("CONTROL_PLANE_DATABASE_PASSWORD", null);
    
        static final Duration TIMEOUT = Duration.ofSeconds(30);
    
        // The setting to change, and its new value.
        static final String SETTING = "work_mem";
        static final String VALUE = "16MB";
    
        // How long to wait for an update to finish, and how often to check.
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
         * Sends a whole database spec as an update, and returns the ID of the
         * task that applies it. The Control Plane compares the spec with the
         * current one and changes only what differs; the work happens in the
         * task after the reply. The spec is kept as a JSON tree, so that the
         * update sends back every field that the server returned.
         */
        static String updateDatabase(JsonNode spec)
                throws IOException, InterruptedException, ControlPlaneException {
            JsonNode reply = call("POST", "/v1/databases/" + DATABASE_ID, Map.of("spec", spec));
            String taskId = reply.path("task").path("task_id").asString("");
            if (taskId.isEmpty()) {
                throw new ControlPlaneException("Unexpected response: missing task_id");
            }
            return taskId;
        }
    
        /**
         * Returns a copy of the spec with the setting changed. postgresql_conf
         * holds the Postgres settings that the Control Plane manages, and may
         * be missing.
         */
        static JsonNode changedSpec(JsonNode spec) {
            ObjectNode changed = (ObjectNode) spec.deepCopy();
            if (!changed.path("postgresql_conf").isObject()) {
                changed.putObject("postgresql_conf");
            }
            ((ObjectNode) changed.get("postgresql_conf")).put(SETTING, VALUE);
            return changed;
        }
    
        /**
         * Reports whether a failed request is worth repeating: no reply
         * arrived, the server failed, or it answered 409, which the Control
         * Plane does whilst another task, such as the update, is still running
         * on the database.
         */
        static boolean isTransient(Exception e) {
            if (e instanceof ControlPlaneException cpe) {
                return cpe.status == 409 || cpe.status >= 500;
            }
            return e instanceof IOException;
        }
    
        /**
         * Polls a task until it finishes, and throws unless it completed. A
         * failed poll is repeated if it is worth repeating.
         */
        static void waitForTask(String taskId)
                throws IOException, InterruptedException, ControlPlaneException {
            String path = "/v1/databases/" + DATABASE_ID + "/tasks/" + taskId;
            long deadline = System.nanoTime() + WAIT_FOR.toNanos();
            while (System.nanoTime() < deadline) {
                String status = "";
                try {
                    status = call("GET", path, null).path("status").asString("");
                } catch (IOException | ControlPlaneException e) {
                    if (!isTransient(e)) {
                        throw e;
                    }
                }
                if (status.equals("completed")) {
                    return;
                }
                if (status.equals("failed") || status.equals("canceled")) {
                    throw new ControlPlaneException(
                            "the task finished with the status " + status);
                }
                Thread.sleep(POLL_INTERVAL.toMillis());
            }
            throw new ControlPlaneException("the task was still running after "
                    + WAIT_FOR.toSeconds() + " seconds");
        }
    
        /**
         * Connects to the first available instance and returns the current
         * value of the setting. Each instance runs one node, and its
         * connection_info holds the address and port that clients use.
         */
        static String showSetting()
                throws IOException, InterruptedException, ControlPlaneException, SQLException {
            JsonNode database = call("GET", "/v1/databases/" + DATABASE_ID, null);
            JsonNode info = null;
            for (JsonNode instance : database.path("instances")) {
                JsonNode candidate = instance.path("connection_info");
                if (instance.path("state").asString("").equals("available")
                        && !candidate.path("addresses").isEmpty()) {
                    info = candidate;
                    break;
                }
            }
            if (info == null) {
                throw new ControlPlaneException("no available instance of " + DATABASE_ID);
            }
    
            Properties props = new Properties();
            props.setProperty("user", DATABASE_USER);
            props.setProperty("password", DATABASE_PASSWORD);
            props.setProperty("connectTimeout", String.valueOf(TIMEOUT.toSeconds()));
            props.setProperty("loginTimeout", String.valueOf(TIMEOUT.toSeconds()));
            String url = "jdbc:postgresql://" + info.path("addresses").get(0).asString()
                    + ":" + info.path("port").asInt() + "/"
                    + database.path("spec").path("database_name").asString();
    
            // try-with-resources closes the connection and statement when the
            // block exits, whether or not the query failed.
            try (Connection conn = DriverManager.getConnection(url, props);
                 PreparedStatement stmt = conn.prepareStatement("SELECT current_setting(?)")) {
                stmt.setString(1, SETTING);
                try (ResultSet rs = stmt.executeQuery()) {
                    rs.next();
                    return rs.getString(1);
                }
            }
        }
    
        /**
         * Sends the original spec back and waits for the task. The Control
         * Plane answers 409 whilst another task, such as the update, is still
         * running on the database, so the program repeats the request, as it
         * does when no reply arrived or the server failed.
         */
        static void restore(JsonNode original)
                throws IOException, InterruptedException, ControlPlaneException {
            long deadline = System.nanoTime() + WAIT_FOR.toNanos();
            String taskId;
            while (true) {
                try {
                    taskId = updateDatabase(original);
                    break;
                } catch (IOException | ControlPlaneException e) {
                    if (!isTransient(e) || System.nanoTime() >= deadline) {
                        throw e;
                    }
                }
                Thread.sleep(POLL_INTERVAL.toMillis());
            }
            waitForTask(taskId);
        }
    
        // Ctrl-C and SIGTERM start the JVM's shutdown, which runs the hook
        // below and then ends the process. The hook interrupts the main thread
        // and waits until it has restored the settings. The lock and the
        // cleaning flag stop the hook from interrupting the cleanup itself.
        static final Object LOCK = new Object();
        static final CountDownLatch FINISHED = new CountDownLatch(1);
        static boolean cleaning = false;
        static volatile boolean shuttingDown = false;
    
        public static void main(String[] args) {
            if (DATABASE_PASSWORD == null) {
                System.err.println("CONTROL_PLANE_DATABASE_PASSWORD must be set");
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
            boolean changed = false;
            JsonNode original = null;
            try {
                // The spec that the API returns leaves out the passwords of the
                // database users, and an update may leave them out too, which
                // keeps them unchanged.
                original = call("GET", "/v1/databases/" + DATABASE_ID, null).path("spec");
    
                // Restore unless the server refused the request with a 4xx
                // status, which means that it changed nothing.
                System.out.println("Setting " + SETTING + " to " + VALUE);
                changed = true;
                String taskId;
                try {
                    taskId = updateDatabase(changedSpec(original));
                } catch (ControlPlaneException e) {
                    if (e.status >= 400 && e.status < 500) {
                        changed = false;
                    }
                    throw e;
                }
                waitForTask(taskId);
                System.out.println("Update completed");
    
                System.out.println(SETTING + " is now " + showSetting());
            } catch (InterruptedException e) {
                System.err.println("Interrupted");
                exitCode = 130;
            // SQLException covers the driver's errors, including a failure to
            // connect.
            } catch (SQLException e) {
                System.err.println("Database error: " + e.getMessage());
                exitCode = 1;
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
                    // The database connection does not stop for a signal, so
                    // check whether one arrived whilst it was open.
                    if (Thread.interrupted() && exitCode == 0) {
                        System.err.println("Interrupted");
                        exitCode = 130;
                    }
                }
                // Restore the original settings whether the example succeeded,
                // failed, or was interrupted.
                if (changed) {
                    try {
                        restore(original);
                        System.out.println("Restored the original settings");
                    } catch (IOException | InterruptedException | ControlPlaneException e) {
                        System.err.println("Control Plane error: " + e);
                        System.err.println("Restore the settings of the database "
                                + DATABASE_ID + " by hand");
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
     * Changing a Postgres setting of a pgEdge Control Plane database, checking
     * it from a connection, and putting the original settings back, using
     * HttpClient, System.Text.Json and Npgsql.
     *
     * These examples are for the Control Plane v0.11.0.
     *
     * The program restores the original settings on every path: after a
     * success, after a failure, and after Ctrl-C.
     *
     * Copyright (c) 2026, pgEdge, Inc.
     * This code is released under the PostgreSQL License.
     */
    
    using System.Diagnostics;
    using System.Net.Http.Json;
    using System.Runtime.InteropServices;
    using System.Text.Json;
    using System.Text.Json.Nodes;
    using Npgsql;
    
    // Returns the value of an environment variable, or a fallback if the
    // variable is unset or empty.
    static string? EnvOr(string name, string? fallback) =>
        Environment.GetEnvironmentVariable(name) is { Length: > 0 } value
            ? value
            : fallback;
    
    static string BaseUrl() =>
        EnvOr("CONTROL_PLANE_URL", "http://localhost:3000")!.TrimEnd('/');
    
    static string DatabaseId() => EnvOr("CONTROL_PLANE_DATABASE_ID", "cookbook")!;
    
    // The password has no default; the Control Plane never returns it, so it
    // comes from whoever created the database user.
    static string DatabaseUser() => EnvOr("CONTROL_PLANE_DATABASE_USER", "cookbook")!;
    static string? DatabasePassword() => EnvOr("CONTROL_PLANE_DATABASE_PASSWORD", null);
    
    const int TimeoutSeconds = 30;
    
    // The setting to change, and its new value.
    const string Setting = "work_mem";
    const string Value = "16MB";
    
    // How long to wait for an update to finish, and how often to check.
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
    
    // Sends a whole database spec as an update, and returns the ID of the task
    // that applies it. The Control Plane compares the spec with the current
    // one and changes only what differs; the work happens in the task after
    // the reply. The spec is kept as a JSON tree, so that the update sends back
    // every field that the server returned.
    static async Task<string> UpdateDatabaseAsync(
        HttpClient client, JsonObject spec, CancellationToken token)
    {
        var body = new JsonObject { ["spec"] = spec.DeepClone() };
        var reply = await CallAsync(
            client, HttpMethod.Post, $"/v1/databases/{DatabaseId()}", body, token);
        return reply["task"]?["task_id"]?.ToString()
            ?? throw new ControlPlaneException("Unexpected response: missing task_id");
    }
    
    // Returns a copy of the spec with the setting changed. postgresql_conf
    // holds the Postgres settings that the Control Plane manages, and may be
    // missing.
    static JsonObject ChangedSpec(JsonObject spec)
    {
        var changed = spec.DeepClone().AsObject();
        if (changed["postgresql_conf"] is not JsonObject conf)
        {
            conf = new JsonObject();
            changed["postgresql_conf"] = conf;
        }
        conf[Setting] = Value;
        return changed;
    }
    
    // Reports whether a failed request is worth repeating: no reply arrived,
    // the server failed, or it answered 409, which the Control Plane does
    // whilst another task, such as the update, is still running on the
    // database. TaskCanceledException is a timeout unless the caller's token
    // was cancelled, which the caller checks.
    static bool IsTransient(Exception e) => e switch
    {
        ControlPlaneException cpe => cpe.Status is 409 or >= 500,
        HttpRequestException or TaskCanceledException => true,
        _ => false,
    };
    
    // Polls a task until it finishes, and throws an exception unless it
    // completed. A failed poll is repeated if it is worth repeating.
    static async Task WaitForTaskAsync(HttpClient client, string taskId, CancellationToken token)
    {
        var clock = Stopwatch.StartNew();
        while (clock.Elapsed.TotalSeconds < WaitSeconds)
        {
            string? status = null;
            try
            {
                var task = await CallAsync(
                    client, HttpMethod.Get, $"/v1/databases/{DatabaseId()}/tasks/{taskId}", null, token);
                status = task["status"]?.ToString();
            }
            catch (Exception e) when (IsTransient(e) && !token.IsCancellationRequested)
            {
                // Check again after the pause.
            }
            if (status == "completed")
            {
                return;
            }
            if (status is "failed" or "canceled")
            {
                throw new ControlPlaneException($"the task finished with the status {status}");
            }
            await Task.Delay(TimeSpan.FromSeconds(PollSeconds), token);
        }
        throw new ControlPlaneException($"the task was still running after {WaitSeconds} seconds");
    }
    
    // Connects to the first available instance and returns the current value
    // of the setting. Each instance runs one node, and its connection_info
    // holds the address and port that clients use.
    static async Task<string> ShowSettingAsync(HttpClient client, CancellationToken token)
    {
        var database = await CallAsync(
            client, HttpMethod.Get, $"/v1/databases/{DatabaseId()}", null, token);
        var info = (database["instances"] as JsonArray ?? [])
            .FirstOrDefault(i => i?["state"]?.ToString() == "available"
                && i["connection_info"]?["addresses"] is JsonArray { Count: > 0 })
            ?["connection_info"]
            ?? throw new ControlPlaneException($"no available instance of {DatabaseId()}");
    
        // The builder takes care of quoting any special characters.
        var connectionString = new NpgsqlConnectionStringBuilder
        {
            Host = info["addresses"]![0]!.ToString(),
            Port = info["port"]!.GetValue<int>(),
            Database = database["spec"]?["database_name"]?.ToString(),
            Username = DatabaseUser(),
            Password = DatabasePassword(),
            Timeout = TimeoutSeconds,
        }.ConnectionString;
    
        // await using closes the connection and command when the block exits,
        // whether or not the query failed.
        await using var conn = new NpgsqlConnection(connectionString);
        await conn.OpenAsync(token);
        await using var cmd = new NpgsqlCommand("SELECT current_setting($1)", conn);
        cmd.Parameters.Add(new NpgsqlParameter { Value = Setting });
        return (string)(await cmd.ExecuteScalarAsync(token))!;
    }
    
    // Sends the original spec back and waits for the task. The Control Plane
    // answers 409 whilst another task, such as the update, is still running on
    // the database, so the program repeats the request, as it does when no
    // reply arrived or the server failed. TaskCanceledException is a timeout
    // here, because the cleanup runs after Ctrl-C and so passes no token that
    // can be cancelled.
    static async Task RestoreAsync(HttpClient client, JsonObject original)
    {
        var clock = Stopwatch.StartNew();
        string taskId;
        while (true)
        {
            try
            {
                taskId = await UpdateDatabaseAsync(client, original, CancellationToken.None);
                break;
            }
            catch (Exception e) when (IsTransient(e) && clock.Elapsed.TotalSeconds < WaitSeconds)
            {
                await Task.Delay(TimeSpan.FromSeconds(PollSeconds));
            }
        }
        await WaitForTaskAsync(client, taskId, CancellationToken.None);
    }
    
    if (DatabasePassword() is null)
    {
        Console.Error.WriteLine("CONTROL_PLANE_DATABASE_PASSWORD must be set");
        return 1;
    }
    
    // Ctrl-C and SIGTERM cancel the token below instead of ending the process,
    // which lets the program restore the settings before it exits. The
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
    var changed = false;
    JsonObject original = [];
    try
    {
        // The spec that the API returns leaves out the passwords of the
        // database users, and an update may leave them out too, which keeps
        // them unchanged.
        var database = await CallAsync(
            client, HttpMethod.Get, $"/v1/databases/{DatabaseId()}", null, interrupt.Token);
        original = database["spec"] as JsonObject
            ?? throw new ControlPlaneException("Unexpected response: missing spec");
    
        // Restore unless the server refused the request with a 4xx status,
        // which means that it changed nothing.
        Console.WriteLine($"Setting {Setting} to {Value}");
        changed = true;
        string taskId;
        try
        {
            taskId = await UpdateDatabaseAsync(client, ChangedSpec(original), interrupt.Token);
        }
        catch (ControlPlaneException e) when (e.Status is >= 400 and < 500)
        {
            changed = false;
            throw;
        }
        await WaitForTaskAsync(client, taskId, interrupt.Token);
        Console.WriteLine("Update completed");
    
        Console.WriteLine($"{Setting} is now {await ShowSettingAsync(client, interrupt.Token)}");
        // A signal that arrives after the last request still counts.
        interrupt.Token.ThrowIfCancellationRequested();
    }
    catch (OperationCanceledException) when (interrupt.IsCancellationRequested)
    {
        Console.Error.WriteLine("Interrupted");
        exitCode = 130;
    }
    // NpgsqlException is the base class for the driver's errors, including a
    // failure to connect.
    catch (NpgsqlException e)
    {
        Console.Error.WriteLine($"Database error: {e.Message}");
        exitCode = 1;
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
        // Restore the original settings whether the example succeeded, failed,
        // or was interrupted.
        if (changed)
        {
            try
            {
                await RestoreAsync(client, original);
                Console.WriteLine("Restored the original settings");
            }
            catch (Exception e) when (
                e is HttpRequestException or TaskCanceledException or ControlPlaneException)
            {
                Console.Error.WriteLine($"Control Plane error: {e.Message}");
                Console.Error.WriteLine($"Restore the settings of the database {DatabaseId()} by hand");
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
    // Changing a Postgres setting of a pgEdge Control Plane database, checking
    // it from a connection, and putting the original settings back, using
    // net/http and pgx.
    //
    // These examples are for the Control Plane v0.11.0.
    //
    // The program restores the original settings on every path: after a
    // success, after a failure, and after Ctrl-C.
    //
    // Copyright (c) 2026, pgEdge, Inc.
    // This code is released under the PostgreSQL License.
    
    package main
    
    import (
    	"bytes"
    	"context"
    	"encoding/json"
    	"errors"
    	"fmt"
    	"io"
    	"maps"
    	"net"
    	"net/http"
    	"net/url"
    	"os"
    	"os/signal"
    	"strconv"
    	"strings"
    	"syscall"
    	"time"
    
    	"github.com/jackc/pgx/v5"
    )
    
    
    // envOr returns the value of an environment variable, or a fallback if
    // the variable is unset or empty.
    func envOr(name, fallback string) string {
    	if value := os.Getenv(name); value != "" {
    		return value
    	}
    	return fallback
    }
    
    // The password has no default; the Control Plane never returns it, so it
    // comes from whoever created the database user.
    var (
    	baseURL          = strings.TrimRight(envOr("CONTROL_PLANE_URL", "http://localhost:3000"), "/")
    	databaseID       = envOr("CONTROL_PLANE_DATABASE_ID", "cookbook")
    	databaseUser     = envOr("CONTROL_PLANE_DATABASE_USER", "cookbook")
    	databasePassword = os.Getenv("CONTROL_PLANE_DATABASE_PASSWORD")
    )
    
    const timeout = 30 * time.Second
    
    // The setting to change, and its new value.
    const (
    	setting = "work_mem"
    	value   = "16MB"
    )
    
    // How long to wait for an update to finish, and how often to check.
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
    
    // dbError marks an error from the database connection or its query.
    type dbError struct{ err error }
    
    func (e *dbError) Error() string { return e.err.Error() }
    
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
    
    
    // spec is kept as plain JSON, so that the update sends back every field
    // that the server returned, including any that this program does not
    // know about.
    type spec = map[string]any
    
    // updateDatabase sends a whole database spec as an update, and returns
    // the ID of the task that applies it. The Control Plane compares the spec
    // with the current one and changes only what differs; the work happens in
    // the task after the reply.
    func updateDatabase(ctx context.Context, s spec) (string, error) {
    	var reply struct {
    		Task struct {
    			TaskID string `json:"task_id"`
    		} `json:"task"`
    	}
    	err := call(ctx, http.MethodPost, "/v1/databases/"+databaseID, map[string]any{"spec": s}, &reply)
    	return reply.Task.TaskID, err
    }
    
    // changedSpec returns a copy of the spec with the setting changed.
    // postgresql_conf holds the Postgres settings that the Control Plane
    // manages, and may be missing.
    func changedSpec(s spec) spec {
    	conf := map[string]any{}
    	if current, ok := s["postgresql_conf"].(map[string]any); ok {
    		maps.Copy(conf, current)
    	}
    	conf[setting] = value
    	changed := maps.Clone(s)
    	changed["postgresql_conf"] = conf
    	return changed
    }
    
    
    // isTransient reports whether a failed request is worth repeating: no
    // reply arrived, the server failed, or it answered 409, which the Control
    // Plane does whilst another task is still running on the database.
    func isTransient(err error) bool {
    	status := statusOf(err)
    	return status == 0 || status == http.StatusConflict || status >= 500
    }
    
    // waitForTask polls a task until it finishes, and returns an error unless
    // it completed. A failed poll is repeated if it is worth repeating.
    func waitForTask(ctx context.Context, taskID string) error {
    	deadline := time.Now().Add(waitFor)
    	for time.Now().Before(deadline) {
    		var task struct {
    			Status string `json:"status"`
    		}
    		err := call(ctx, http.MethodGet, "/v1/databases/"+databaseID+"/tasks/"+taskID, nil, &task)
    		if err != nil && (ctx.Err() != nil || !isTransient(err)) {
    			return err
    		}
    		switch {
    		case err != nil:
    		case task.Status == "completed":
    			return nil
    		case task.Status == "failed" || task.Status == "canceled":
    			return fmt.Errorf("the task finished with the status %s", task.Status)
    		}
    		if err := sleep(ctx); err != nil {
    			return err
    		}
    	}
    	return fmt.Errorf("the task was still running after %d seconds", int(waitFor.Seconds()))
    }
    
    
    // showSetting connects to the first available instance and returns the
    // current value of the setting. Each instance runs one node, and its
    // connection_info holds the address and port that clients use.
    func showSetting(ctx context.Context) (string, error) {
    	var database struct {
    		Spec struct {
    			DatabaseName string `json:"database_name"`
    		} `json:"spec"`
    		Instances []struct {
    			State          string `json:"state"`
    			ConnectionInfo struct {
    				Addresses []string `json:"addresses"`
    				Port      int      `json:"port"`
    			} `json:"connection_info"`
    		} `json:"instances"`
    	}
    	if err := call(ctx, http.MethodGet, "/v1/databases/"+databaseID, nil, &database); err != nil {
    		return "", err
    	}
    	host, port := "", 0
    	for _, i := range database.Instances {
    		if i.State == "available" && len(i.ConnectionInfo.Addresses) > 0 {
    			host, port = i.ConnectionInfo.Addresses[0], i.ConnectionInfo.Port
    			break
    		}
    	}
    	if host == "" {
    		return "", fmt.Errorf("no available instance of %s", databaseID)
    	}
    
    	// net/url takes care of escaping any special characters in the user
    	// name, password, or database name.
    	u := url.URL{
    		Scheme:   "postgres",
    		User:     url.UserPassword(databaseUser, databasePassword),
    		Host:     net.JoinHostPort(host, strconv.Itoa(port)),
    		Path:     "/" + database.Spec.DatabaseName,
    		RawQuery: "connect_timeout=30",
    	}
    	conn, err := pgx.Connect(ctx, u.String())
    	if err != nil {
    		return "", &dbError{err}
    	}
    	// Close the connection when the function returns, whether or not the
    	// query failed.
    	defer conn.Close(ctx)
    
    	var current string
    	if err := conn.QueryRow(ctx, "SELECT current_setting($1)", setting).Scan(&current); err != nil {
    		return "", &dbError{err}
    	}
    	return current, nil
    }
    
    
    // restore sends the original spec back and waits for the task. The
    // Control Plane answers 409 whilst another task, such as the update, is
    // still running on the database, so the program repeats the request, as
    // it does when no reply arrived or the server failed. The cleanup runs
    // after Ctrl-C, so it uses a context that never ends.
    func restore(original spec) error {
    	ctx := context.Background()
    	deadline := time.Now().Add(waitFor)
    	for {
    		taskID, err := updateDatabase(ctx, original)
    		if err == nil {
    			return waitForTask(ctx, taskID)
    		}
    		if !isTransient(err) || time.Now().After(deadline) {
    			return err
    		}
    		sleep(ctx)
    	}
    }
    
    
    // run changes the setting and checks it, and returns any error to the
    // caller. It fills in original, and sets changed once the settings may
    // have changed, so that the caller knows whether to restore them.
    func run(ctx context.Context, original *spec, changed *bool) error {
    	// The spec that the API returns leaves out the passwords of the
    	// database users, and an update may leave them out too, which keeps
    	// them unchanged.
    	var database struct {
    		Spec spec `json:"spec"`
    	}
    	if err := call(ctx, http.MethodGet, "/v1/databases/"+databaseID, nil, &database); err != nil {
    		return err
    	}
    	*original = database.Spec
    
    	// Restore unless the server refused the request with a 4xx status,
    	// which means that it changed nothing.
    	fmt.Printf("Setting %s to %s\n", setting, value)
    	*changed = true
    	taskID, err := updateDatabase(ctx, changedSpec(*original))
    	if err != nil {
    		if status := statusOf(err); status >= 400 && status < 500 {
    			*changed = false
    		}
    		return err
    	}
    	if err := waitForTask(ctx, taskID); err != nil {
    		return err
    	}
    	fmt.Println("Update completed")
    
    	current, err := showSetting(ctx)
    	if err != nil {
    		return err
    	}
    	fmt.Printf("%s is now %s\n", setting, current)
    	return nil
    }
    
    // main restores the original settings whether the example succeeded,
    // failed, or was interrupted, and exits with a non-zero status after a
    // failure.
    func main() {
    	if databasePassword == "" {
    		fmt.Fprintln(os.Stderr, "CONTROL_PLANE_DATABASE_PASSWORD must be set")
    		os.Exit(1)
    	}
    
    	// Ctrl-C and SIGTERM end the context instead of the process, which
    	// lets the program restore the settings before it exits. The handlers
    	// stay in place, so a further Ctrl-C does not end the process during
    	// the cleanup either.
    	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
    
    	exitCode := 0
    	changed := false
    	var original spec
    	if err := run(ctx, &original, &changed); err != nil {
    		var dbErr *dbError
    		switch {
    		case ctx.Err() != nil:
    			fmt.Fprintln(os.Stderr, "Interrupted")
    			exitCode = 130
    		case errors.As(err, &dbErr):
    			fmt.Fprintf(os.Stderr, "Database error: %v\n", err)
    			exitCode = 1
    		default:
    			fmt.Fprintf(os.Stderr, "Control Plane error: %v\n", err)
    			exitCode = 1
    		}
    	}
    
    	if changed {
    		if err := restore(original); err != nil {
    			fmt.Fprintf(os.Stderr, "Control Plane error: %v\n", err)
    			fmt.Fprintf(os.Stderr, "Restore the settings of the database %s by hand\n", databaseID)
    			exitCode = 1
    		} else {
    			fmt.Println("Restored the original settings")
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
    // Changing a Postgres setting of a pgEdge Control Plane database, checking
    // it from a connection, and putting the original settings back, using
    // reqwest, serde_json and the postgres crate.
    //
    // These examples are for the Control Plane v0.11.0.
    //
    // The program restores the original settings on every path: after a
    // success, after a failure, and after Ctrl-C.
    //
    // Copyright (c) 2026, pgEdge, Inc.
    // This code is released under the PostgreSQL License.
    
    use std::env;
    use std::error::Error;
    use std::fmt;
    use std::process::ExitCode;
    use std::sync::atomic::{AtomicBool, Ordering};
    use std::thread;
    use std::time::{Duration, Instant};
    
    use postgres::{Config, NoTls};
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
    
    fn database_id() -> String {
        env_or("CONTROL_PLANE_DATABASE_ID", "cookbook")
    }
    
    const TIMEOUT: Duration = Duration::from_secs(30);
    
    // The setting to change, and its new value.
    const SETTING: &str = "work_mem";
    const VALUE: &str = "16MB";
    
    // How long to wait for an update to finish, and how often to check.
    const WAIT_FOR: Duration = Duration::from_secs(600);
    const POLL_INTERVAL: Duration = Duration::from_secs(5);
    
    /// Set by Ctrl-C or SIGTERM. The handler sets this flag instead of ending
    /// the process, which lets the program restore the settings before it
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
    
    /// Fails if check is true and the user has pressed Ctrl-C. A request does
    /// not stop for Ctrl-C, so the program checks the flag after each one; the
    /// cleanup passes false, so that it carries on.
    fn check_interrupted(check: bool) -> Result<(), BoxError> {
        if check && INTERRUPTED.load(Ordering::SeqCst) {
            return Err("interrupted".into());
        }
        Ok(())
    }
    
    /// Waits for the poll interval, checking for Ctrl-C as above.
    fn pause(check: bool) -> Result<(), BoxError> {
        let end = Instant::now() + POLL_INTERVAL;
        while Instant::now() < end {
            check_interrupted(check)?;
            thread::sleep(Duration::from_millis(100));
        }
        Ok(())
    }
    
    /// Sends a whole database spec as an update, and returns the ID of the
    /// task that applies it. The Control Plane compares the spec with the
    /// current one and changes only what differs; the work happens in the
    /// task after the reply.
    fn update_database(client: &Client, spec: &Value) -> Result<String, BoxError> {
        let reply = call(
            client,
            Method::POST,
            &format!("/v1/databases/{}", database_id()),
            Some(&json!({ "spec": spec })),
        )?;
        reply["task"]["task_id"]
            .as_str()
            .map(str::to_string)
            .ok_or_else(|| "Unexpected response: missing task_id".into())
    }
    
    /// Returns a copy of the spec with the setting changed. postgresql_conf
    /// holds the Postgres settings that the Control Plane manages, and may be
    /// missing.
    fn changed_spec(spec: &Value) -> Value {
        let mut changed = spec.clone();
        if !changed["postgresql_conf"].is_object() {
            changed["postgresql_conf"] = json!({});
        }
        changed["postgresql_conf"][SETTING] = json!(VALUE);
        changed
    }
    
    /// Reports whether a failed request is worth repeating: no reply arrived,
    /// the server failed, or it answered 409, which the Control Plane does
    /// whilst another task, such as the update, is still running on the
    /// database.
    fn is_transient(error: &BoxError) -> bool {
        match status_of(error) {
            Some(status) => status == 409 || status >= 500,
            None => error.is::<reqwest::Error>(),
        }
    }
    
    /// Polls a task until it finishes, and fails unless it completed. A failed
    /// poll is repeated if it is worth repeating. When check is true, Ctrl-C
    /// ends the wait.
    fn wait_for_task(client: &Client, task_id: &str, check: bool) -> Result<(), BoxError> {
        let path = format!("/v1/databases/{}/tasks/{task_id}", database_id());
        let deadline = Instant::now() + WAIT_FOR;
        while Instant::now() < deadline {
            let task = call(client, Method::GET, &path, None);
            check_interrupted(check)?;
            match task {
                Ok(task) => match task["status"].as_str() {
                    Some("completed") => return Ok(()),
                    Some(status @ ("failed" | "canceled")) => {
                        return Err(format!("the task finished with the status {status}").into())
                    }
                    _ => {}
                },
                Err(e) if !is_transient(&e) => return Err(e),
                Err(_) => {}
            }
            pause(check)?;
        }
        Err(format!("the task was still running after {} seconds", WAIT_FOR.as_secs()).into())
    }
    
    /// The result of show_setting: a database error is reported differently
    /// from a Control Plane one.
    enum ShowError {
        ControlPlane(BoxError),
        Database(postgres::Error),
    }
    
    impl From<BoxError> for ShowError {
        fn from(e: BoxError) -> Self {
            ShowError::ControlPlane(e)
        }
    }
    
    impl From<postgres::Error> for ShowError {
        fn from(e: postgres::Error) -> Self {
            ShowError::Database(e)
        }
    }
    
    /// Connects to the first available instance and returns the current
    /// value of the setting. Each instance runs one node, and its
    /// connection_info holds the address and port that clients use. NoTls
    /// disables TLS, which keeps this example free of certificate set-up;
    /// connections over an untrusted network should use TLS.
    fn show_setting(client: &Client, password: &str) -> Result<String, ShowError> {
        let database = call(client, Method::GET, &format!("/v1/databases/{}", database_id()), None)?;
        let info = database["instances"]
            .as_array()
            .into_iter()
            .flatten()
            .find(|i| i["state"] == "available" && i["connection_info"]["addresses"][0].is_string())
            .map(|i| &i["connection_info"])
            .ok_or_else(|| BoxError::from(format!("no available instance of {}", database_id())))?;
        let port = info["port"]
            .as_u64()
            .and_then(|p| u16::try_from(p).ok())
            .ok_or_else(|| BoxError::from("Unexpected response: missing port"))?;
    
        let mut db = Config::new()
            .host(info["addresses"][0].as_str().unwrap_or_default())
            .port(port)
            .dbname(database["spec"]["database_name"].as_str().unwrap_or_default())
            .user(&env_or("CONTROL_PLANE_DATABASE_USER", "cookbook"))
            .password(password)
            .connect_timeout(TIMEOUT)
            .connect(NoTls)?;
        let current: String = db.query_one("SELECT current_setting($1)", &[&SETTING])?.get(0);
        // The client closes its connection when it goes out of scope.
        Ok(current)
    }
    
    /// Sends the original spec back and waits for the task. The Control Plane
    /// answers 409 whilst another task, such as the update, is still running
    /// on the database, so the program repeats the request, as it does when
    /// no reply arrived or the server failed. The cleanup runs after Ctrl-C,
    /// so its waits do not check the flag.
    fn restore(client: &Client, original: &Value) -> Result<(), BoxError> {
        let deadline = Instant::now() + WAIT_FOR;
        let task_id = loop {
            match update_database(client, original) {
                Ok(task_id) => break task_id,
                Err(e) => {
                    if !is_transient(&e) || Instant::now() >= deadline {
                        return Err(e);
                    }
                    thread::sleep(POLL_INTERVAL);
                }
            }
        };
        wait_for_task(client, &task_id, false)
    }
    
    /// Prints an error and the chain of its underlying causes, because the
    /// top-level error is often generic ("error sending request").
    fn report(prefix: &str, e: &dyn Error) {
        eprintln!("{prefix}: {e}");
        let mut cause = e.source();
        while let Some(c) = cause {
            eprintln!("  caused by: {c}");
            cause = c.source();
        }
    }
    
    /// Changes the setting and checks it. It fills in original, and sets
    /// changed once the settings may have changed, so that the caller knows
    /// whether to restore them.
    fn run(client: &Client, password: &str, original: &mut Value, changed: &mut bool) -> Result<(), ShowError> {
        // The spec that the API returns leaves out the passwords of the
        // database users, and an update may leave them out too, which keeps
        // them unchanged.
        let database = call(client, Method::GET, &format!("/v1/databases/{}", database_id()), None)?;
        check_interrupted(true)?;
        *original = database["spec"].clone();
    
        // Restore unless the server refused the request with a 4xx status,
        // which means that it changed nothing.
        println!("Setting {SETTING} to {VALUE}");
        *changed = true;
        let task_id = match update_database(client, &changed_spec(original)) {
            Ok(task_id) => task_id,
            Err(e) => {
                if matches!(status_of(&e), Some(400..=499)) {
                    *changed = false;
                }
                return Err(e.into());
            }
        };
        check_interrupted(true)?;
        wait_for_task(client, &task_id, true)?;
        println!("Update completed");
    
        println!("{SETTING} is now {}", show_setting(client, password)?);
        Ok(())
    }
    
    /// Restores the original settings whether the example succeeded, failed,
    /// or was interrupted, and exits with a failure status after a failure.
    fn main() -> ExitCode {
        let password = env_or("CONTROL_PLANE_DATABASE_PASSWORD", "");
        if password.is_empty() {
            eprintln!("CONTROL_PLANE_DATABASE_PASSWORD must be set");
            return ExitCode::FAILURE;
        }
    
        // The handler stays in place, so a further Ctrl-C does not end the
        // process during the cleanup either. The termination feature of the
        // ctrlc crate makes it handle SIGTERM too.
        if let Err(e) = ctrlc::set_handler(|| INTERRUPTED.store(true, Ordering::SeqCst)) {
            report("Control Plane error", &e);
            return ExitCode::FAILURE;
        }
    
        let client = match Client::builder().timeout(TIMEOUT).build() {
            Ok(client) => client,
            Err(e) => {
                report("Control Plane error", &e);
                return ExitCode::FAILURE;
            }
        };
    
        let mut original = Value::Null;
        let mut changed = false;
        let mut exit_code = ExitCode::SUCCESS;
        // A signal that arrives after the last request, or whilst the program
        // is connected to the database, still counts.
        let result = run(&client, &password, &mut original, &mut changed);
        if INTERRUPTED.load(Ordering::SeqCst) {
            eprintln!("Interrupted");
            exit_code = ExitCode::from(130);
        } else if let Err(e) = result {
            exit_code = ExitCode::FAILURE;
            match e {
                ShowError::ControlPlane(e) => report("Control Plane error", e.as_ref()),
                ShowError::Database(e) => report("Database error", &e),
            }
        }
    
        if changed {
            match restore(&client, &original) {
                Ok(()) => println!("Restored the original settings"),
                Err(e) => {
                    report("Control Plane error", e.as_ref());
                    eprintln!("Restore the settings of the database {} by hand", database_id());
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
    # Changing a Postgres setting of a pgEdge Control Plane database, checking
    # it from a connection, and putting the original settings back, using
    # Net::HTTP and the pg gem.
    #
    # These examples are for the Control Plane v0.11.0.
    #
    # The program restores the original settings on every path: after a
    # success, after a failure, and after Ctrl-C.
    #
    # Copyright (c) 2026, pgEdge, Inc.
    # This code is released under the PostgreSQL License.
    
    require "json"
    require "net/http"
    require "pg"
    require "uri"
    
    # Returns the value of an environment variable, or a fallback if the
    # variable is unset or empty.
    def env_or(name, fallback)
      value = ENV[name]
      value.nil? || value.empty? ? fallback : value
    end
    
    # The password has no default; the Control Plane never returns it, so it
    # comes from whoever created the database user.
    BASE_URL = env_or("CONTROL_PLANE_URL", "http://localhost:3000").sub(%r{/+\z}, "")
    DATABASE_ID = env_or("CONTROL_PLANE_DATABASE_ID", "cookbook")
    DATABASE_USER = env_or("CONTROL_PLANE_DATABASE_USER", "cookbook")
    DATABASE_PASSWORD = env_or("CONTROL_PLANE_DATABASE_PASSWORD", nil)
    
    TIMEOUT_SECONDS = 30
    
    # The setting to change, and its new value.
    SETTING = "work_mem"
    VALUE = "16MB"
    
    # How long to wait for an update to finish, and how often to check.
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
    
    # Sends a whole database spec as an update, and returns the ID of the task
    # that applies it. The Control Plane compares the spec with the current
    # one and changes only what differs; the work happens in the task after
    # the reply.
    def update_database(spec)
      reply = call("POST", "/v1/databases/#{DATABASE_ID}", { "spec" => spec })
      reply.dig("task", "task_id") or
        raise ControlPlaneError, "Unexpected response: missing task_id"
    end
    
    # Returns a copy of the spec with the setting changed. postgresql_conf
    # holds the Postgres settings that the Control Plane manages, and may be
    # missing.
    def changed_spec(spec)
      spec.merge("postgresql_conf" => (spec["postgresql_conf"] || {}).merge(SETTING => VALUE))
    end
    
    # Reports whether a failed request is worth repeating: no reply arrived,
    # the server failed, or it answered 409, which the Control Plane does
    # whilst another task is still running on the database.
    def transient?(error)
      return true unless error.is_a?(ControlPlaneError)
    
      !error.status.nil? && (error.status == 409 || error.status >= 500)
    end
    
    # Polls a task until it finishes, and raises an error unless it completed.
    # A failed poll is repeated if it is worth repeating.
    def wait_for_task(task_id)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + WAIT_SECONDS
      while Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
        begin
          status = call("GET", "/v1/databases/#{DATABASE_ID}/tasks/#{task_id}")["status"]
        rescue ControlPlaneError, *NETWORK_ERRORS => e
          raise unless transient?(e)
    
          sleep POLL_SECONDS
          next
        end
        return if status == "completed"
        if %w[failed canceled].include?(status)
          raise ControlPlaneError, "the task finished with the status #{status}"
        end
    
        sleep POLL_SECONDS
      end
      raise ControlPlaneError, "the task was still running after #{WAIT_SECONDS} seconds"
    end
    
    # Connects to the first available instance and returns the current value
    # of the setting. Each instance runs one node, and its connection_info
    # holds the address and port that clients use.
    def show_setting
      database = call("GET", "/v1/databases/#{DATABASE_ID}")
      instance = (database["instances"] || []).find do |i|
        i["state"] == "available" && !Array(i.dig("connection_info", "addresses")).empty?
      end
      raise ControlPlaneError, "no available instance of #{DATABASE_ID}" unless instance
    
      info = instance["connection_info"]
      conn = PG.connect(
        host: info["addresses"][0], port: info["port"],
        dbname: database.dig("spec", "database_name"),
        user: DATABASE_USER, password: DATABASE_PASSWORD,
        connect_timeout: TIMEOUT_SECONDS
      )
      begin
        conn.exec_params("SELECT current_setting($1)", [SETTING]).getvalue(0, 0)
      ensure
        # Close the connection whether or not the query failed.
        conn.close
      end
    end
    
    # Sends the original spec back and waits for the task. The Control Plane
    # answers 409 whilst another task, such as the update, is still running on
    # the database, so the program repeats the request, as it does when no
    # reply arrived or the server failed.
    def restore(spec)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + WAIT_SECONDS
      begin
        task_id = update_database(spec)
      rescue ControlPlaneError, *NETWORK_ERRORS => e
        raise if !transient?(e) || Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
    
        sleep POLL_SECONDS
        retry
      end
      wait_for_task(task_id)
    end
    
    if DATABASE_PASSWORD.nil?
      warn "CONTROL_PLANE_DATABASE_PASSWORD must be set"
      exit 1
    end
    
    exit_code = 0
    changed = false
    original = nil
    begin
      # The spec that the API returns leaves out the passwords of the database
      # users, and an update may leave them out too, which keeps them
      # unchanged.
      original = call("GET", "/v1/databases/#{DATABASE_ID}")["spec"]
    
      # Restore unless the server refused the request with a 4xx status, which
      # means that it changed nothing.
      puts "Setting #{SETTING} to #{VALUE}"
      changed = true
      begin
        task_id = update_database(changed_spec(original))
      rescue ControlPlaneError => e
        changed = false if e.status&.between?(400, 499)
        raise
      end
      wait_for_task(task_id)
      puts "Update completed"
    
      puts "#{SETTING} is now #{show_setting}"
    rescue ControlPlaneError, *NETWORK_ERRORS => e
      warn "Control Plane error: #{e.message}"
      exit_code = 1
    # PG::Error is the base class for the gem's errors, including a failure to
    # connect.
    rescue PG::Error => e
      warn "Database error: #{e.message}"
      exit_code = 1
    # Ctrl-C raises Interrupt, and SIGTERM raises SignalException.
    rescue SignalException
      warn "Interrupted"
      exit_code = 130
    ensure
      # Restore the original settings whether the example succeeded, failed,
      # or was interrupted. Ignore further interrupts, so that they cannot cut
      # the cleanup short.
      trap("INT", "IGNORE")
      trap("TERM", "IGNORE")
      if changed
        begin
          restore(original)
          puts "Restored the original settings"
        rescue ControlPlaneError, *NETWORK_ERRORS => e
          warn "Control Plane error: #{e.message}"
          warn "Restore the settings of the database #{DATABASE_ID} by hand"
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
    # Changing a Postgres setting of a pgEdge Control Plane database, checking
    # it from a connection, and putting the original settings back, using
    # curl, jq and psql.
    #
    # These examples are for the Control Plane v0.11.0.
    #
    # The script restores the original settings on every path: after a
    # success, after a failure, and after Ctrl-C.
    #
    # Copyright (c) 2026, pgEdge, Inc.
    # This code is released under the PostgreSQL License.
    
    # Stop at the first failed command or unset variable, and make a failure
    # anywhere in a pipeline fail the whole pipeline.
    set -euo pipefail
    
    # The script needs curl to call the API, jq to read and build the JSON,
    # and psql to connect to the database.
    for tool in curl jq psql; do
        command -v "$tool" >/dev/null || { echo "Control Plane error: $tool is required" >&2; exit 1; }
    done
    
    # The :- expansion treats an empty variable as unset. The password has no
    # default; the Control Plane never returns it, so it comes from whoever
    # created the database user.
    base_url="${CONTROL_PLANE_URL:-http://localhost:3000}"
    base_url="${base_url%/}"
    database_id="${CONTROL_PLANE_DATABASE_ID:-cookbook}"
    database_user="${CONTROL_PLANE_DATABASE_USER:-cookbook}"
    database_password="${CONTROL_PLANE_DATABASE_PASSWORD:-}"
    
    timeout_seconds=30
    
    # The setting to change, and its new value.
    setting=work_mem
    value=16MB
    
    # How long to wait for an update to finish, and how often to check.
    wait_seconds=600
    poll_seconds=5
    
    # Sends a request and prints the reply, followed by the HTTP status on a
    # line of its own; the status is 000 if no reply arrived. Any further
    # arguments go to curl, such as --data @- to send standard input as the
    # body.
    request() {
        local method="$1" path="$2"
        shift 2
        curl --silent --show-error --max-time "$timeout_seconds" --request "$method" \
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
    
    # Sends a whole database spec as an update, and prints the reply followed
    # by the HTTP status, as request() does. The Control Plane compares the
    # spec with the current one and changes only what differs; the work
    # happens in a task after the reply.
    update_database() {
        jq '{spec: .}' <<<"$1" |
            request POST "/v1/databases/$database_id" \
                --header "Content-Type: application/json" --data @-
    }
    
    # Prints the spec with the setting changed. postgresql_conf holds the
    # Postgres settings that the Control Plane manages, and may be missing.
    changed_spec() {
        jq --arg name "$setting" --arg value "$value" \
            '.postgresql_conf = ((.postgresql_conf // {}) + {($name): $value})' <<<"$1"
    }
    
    # Polls a task until it finishes, and fails unless it completed. A poll
    # that gets no reply, a 409 or a server failure is repeated. The function
    # returns on every error itself, because the restore runs it where errexit
    # does not apply.
    wait_for_task() {
        local task_id="$1" deadline=$((SECONDS + wait_seconds)) reply code status
        while ((SECONDS < deadline)); do
            reply="$(request GET "/v1/databases/$database_id/tasks/$task_id")"
            code="${reply##*$'\n'}"
            case "$code" in
                200) status="$(jq -er '.status | strings' <<<"${reply%$'\n'*}")" || {
                         echo "Control Plane error: Unexpected response: ${reply%$'\n'*}" >&2
                         return 1
                     }
                     case "$status" in
                         completed) return 0 ;;
                         failed|canceled)
                             echo "Control Plane error: the task finished with the status $status" >&2
                             return 1 ;;
                     esac ;;
                000|409|5??) ;;
                *) echo "Control Plane error: HTTP $code, ${reply%$'\n'*}" >&2
                   return 1 ;;
            esac
            sleep "$poll_seconds"
        done
        echo "Control Plane error: the task was still running after $wait_seconds seconds" >&2
        return 1
    }
    
    # Connects to the first available instance with psql and prints the
    # current value of the setting. Each instance runs one node, and its
    # connection_info holds the address and port that clients use. PGPASSWORD
    # passes the password through the environment, so it never appears in the
    # process list.
    show_setting() {
        local database name address port
        database="$(get "/v1/databases/$database_id")"
        read -r name address port < <(jq -er '
            .spec.database_name as $name
            | first(.instances[]?
                    | select(.state == "available"
                             and (.connection_info.addresses | length) > 0))
            | "\($name) \(.connection_info.addresses[0]) \(.connection_info.port)"
            ' <<<"$database") || {
            echo "Control Plane error: no available instance of $database_id" >&2
            return 1
        }
        PGPASSWORD="$database_password" PGCONNECT_TIMEOUT="$timeout_seconds" \
            psql -X -A -t -v ON_ERROR_STOP=1 \
            --host "$address" --port "$port" \
            --username "$database_user" --dbname "$name" \
            -c "SHOW $setting" || {
            echo "Database error: could not query $name" >&2
            return 1
        }
    }
    
    # Sends the original spec back and waits for the task. The Control Plane
    # answers 409 whilst another task, such as the update, is still running on
    # the database, so the script repeats the request, as it does when no
    # reply arrived or the server failed. The cleanup runs this function where
    # errexit does not apply, so it checks every step itself.
    restore() {
        local deadline=$((SECONDS + wait_seconds)) reply status task_id
        while true; do
            reply="$(update_database "$original")"
            status="${reply##*$'\n'}"
            case "$status" in
                200) break ;;
                000|409|5??) ;;
                *) echo "Control Plane error: HTTP $status, ${reply%$'\n'*}" >&2
                   return 1 ;;
            esac
            if ((SECONDS >= deadline)); then
                echo "Control Plane error: the restore was still failing after $wait_seconds seconds" >&2
                return 1
            fi
            sleep "$poll_seconds"
        done
        task_id="$(jq -er '.task.task_id | strings' <<<"${reply%$'\n'*}")" || {
            echo "Control Plane error: Unexpected response: ${reply%$'\n'*}" >&2
            return 1
        }
        wait_for_task "$task_id"
    }
    
    # Restores the original settings, if the script may have changed them. The
    # EXIT trap runs this function when the script finishes, whether the
    # example succeeded, failed, or was interrupted.
    cleanup() {
        local status=$?
        # Ignore further interrupts, so that they cannot cut the cleanup short.
        trap '' INT TERM
        if [[ "$changed" == 1 ]]; then
            if restore; then
                echo "Restored the original settings"
            else
                echo "Restore the settings of the database $database_id by hand" >&2
                status=1
            fi
        fi
        exit "$status"
    }
    
    main() {
        original="" changed=0
        trap cleanup EXIT
        # Turn Ctrl-C and SIGTERM into a normal exit, so that cleanup runs.
        trap 'echo "Interrupted" >&2; exit 130' INT TERM
    
        if [[ -z "$database_password" ]]; then
            echo "CONTROL_PLANE_DATABASE_PASSWORD must be set" >&2
            return 1
        fi
    
        # The spec that the API returns leaves out the passwords of the
        # database users, and an update may leave them out too, which keeps
        # them unchanged.
        local reply status task_id current
        original="$(get "/v1/databases/$database_id" | jq -e '.spec')"
    
        # Restore unless the server refused the request with a 4xx status,
        # which means that it changed nothing.
        echo "Setting $setting to $value"
        changed=1
        reply="$(update_database "$(changed_spec "$original")")"
        status="${reply##*$'\n'}"
        if [[ "$status" != 200 ]]; then
            [[ "$status" =~ ^4[0-9][0-9]$ ]] && changed=0
            echo "Control Plane error: HTTP $status, ${reply%$'\n'*}" >&2
            return 1
        fi
        task_id="$(jq -er '.task.task_id | strings' <<<"${reply%$'\n'*}")" || {
            echo "Control Plane error: Unexpected response: ${reply%$'\n'*}" >&2
            return 1
        }
        wait_for_task "$task_id"
        echo "Update completed"
    
        current="$(show_setting)"
        echo "$setting is now $current"
    }
    
    main
    
    ```

## Next Steps

The following resources provide more information about the topics in this
recipe:

- The [Following a Task](track_tasks.md) recipe shows how to read the log of a
  task, which explains why an update failed.
- The [Connecting to a Database](connect_database.md) recipe explains how to
  find the address of each instance.
- The
  [pgEdge Control Plane documentation](https://docs.pgedge.com/control-plane/v0-11/)
  describes every endpoint and setting.
- The [Contributing a Recipe](../contributing.md) page explains how to add a
  recipe or a language to the cookbook.
