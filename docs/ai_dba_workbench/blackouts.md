# Scheduling a Maintenance Blackout with the AI DBA Workbench API

This recipe shows how a program schedules a maintenance blackout for a
monitored server with the pgEdge AI DBA Workbench API, reads it back, stops it,
and deletes it. These examples are for AI DBA Workbench 1.0.0. Each step shows
the code in every supported language; selecting a language tab switches every
tab on the site to that language.

A blackout suppresses alert notifications for a server, a cluster, a group of
servers, or the whole estate while planned maintenance takes place. The example
program creates a blackout for one server that started a minute ago and ends in
an hour, reads it back, stops it early, and then deletes it. The program
deletes the blackout even when a step in the middle fails, so a failed run does
not leave alerts suppressed. The output has the following form:

```text
Created a blackout for the server (active: true)
Read the blackout back (active: true)
Stopped the blackout (active: false)
Deleted the blackout
```

## Preparing the Ingredients

The `scripts/start_workbench.sh` script in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook)
starts a test Workbench in Docker. The script creates a `cookbook` user and an
API token, registers a test PostgreSQL server as a monitored connection, and
prints the `WORKBENCH_URL`, `WORKBENCH_TOKEN`, `WORKBENCH_USERNAME`,
`WORKBENCH_PASSWORD`, and `WORKBENCH_CONNECTION_ID` values that the examples
read from the environment.

The examples need a running Workbench server that monitors at least one
PostgreSQL server, and an API token for a user that may manage blackouts. The
following table lists the HTTP client and the JSON library that each example
uses:

| Language   | HTTP client and JSON library                                   |
|------------|----------------------------------------------------------------|
| Python     | [httpx](https://www.python-httpx.org/) and the `json` module   |
| TypeScript | The `fetch` function that Node.js provides                     |
| Java       | The `java.net.http` client and [Jackson](https://github.com/FasterXML/jackson) |
| C#         | `HttpClient` and `System.Text.Json`, which are part of .NET    |
| Go         | The `net/http` and `encoding/json` standard library packages   |
| Rust       | [reqwest](https://docs.rs/reqwest) and [serde_json](https://docs.rs/serde_json) |
| Ruby       | `Net::HTTP` and `json`, which come with Ruby                   |

The curl example is a bash script that uses [jq](https://jqlang.org/) to build
the requests and read the JSON replies. The Rust example also uses
[humantime](https://docs.rs/humantime) to write the start and end times, and
[signal-hook](https://docs.rs/signal-hook) to catch signals. The following tabs
show the dependency declaration from each example project:

=== "Python"

    ```text
    # httpx, an HTTP client with a requests-like interface.
    httpx>=0.28,<1
    ```

=== "TypeScript"

    ```json
    {
      "name": "blackouts",
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
    // The program uses only the Go standard library, so it needs no modules.
    go 1.25.0
    
    ```

=== "Rust"

    ```toml
    [dependencies]
    # The blocking client of reqwest, with rustls for TLS and JSON bodies.
    reqwest = { version = "0.13", default-features = false, features = ["blocking", "json", "rustls"] }
    serde_json = "1"
    # The standard library can neither format a time in RFC 3339 nor catch a
    # signal, so these two small crates do it.
    humantime = "2.4"
    signal-hook = "0.4"
    ```

=== "Ruby"

    ```ruby
    source "https://rubygems.org"
    
    # The program uses only Net::HTTP and JSON, which come with Ruby, so it
    # needs no gems.
    ```

## Importing the Libraries

Each program begins by importing the modules that it uses. The following tabs
show the imports for each language:

=== "Python"

    ```python
    import os
    import signal
    import sys
    from datetime import datetime, timedelta, timezone
    
    import httpx
    ```

=== "TypeScript"

    ```typescript
    // The program needs no imports: fetch and process are built in to Node.js.
    ```

=== "Java"

    ```java
    import java.io.IOException;
    import java.net.URI;
    import java.net.http.HttpClient;
    import java.net.http.HttpRequest;
    import java.net.http.HttpResponse;
    import java.net.http.HttpTimeoutException;
    import java.time.Duration;
    import java.time.Instant;
    import java.time.temporal.ChronoUnit;
    import java.util.Map;
    import java.util.Objects;
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
    using System.Net.Http.Headers;
    using System.Net.Http.Json;
    using System.Runtime.InteropServices;
    using System.Text.Json;
    using System.Text.Json.Nodes;
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
    use std::process::ExitCode;
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::sync::LazyLock;
    use std::time::{Duration, SystemTime};
    
    use humantime::format_rfc3339_seconds;
    use reqwest::blocking::Client;
    use reqwest::Method;
    use serde_json::{json, Value};
    use signal_hook::consts::{SIGINT, SIGTERM};
    ```

=== "Ruby"

    ```ruby
    require "json"
    require "net/http"
    require "time"
    ```

=== "curl"

    ```bash
    # Stop at the first failing command, treat an unset variable as an error,
    # and fail a pipeline when any command in it fails.
    set -euo pipefail
    
    # The script needs curl to make the requests and jq to build the request and
    # read the replies.
    for tool in curl jq; do
        command -v "$tool" >/dev/null || { echo "$tool is required" >&2; exit 1; }
    done
    ```

## Configuring the Connection

The examples read their settings from environment variables, and treat an empty
variable as unset. The following table describes the variables that the
examples read:

| Variable                  | Description                                   |
|---------------------------|-----------------------------------------------|
| `WORKBENCH_URL`           | The base URL; default `http://localhost:8080` |
| `WORKBENCH_TOKEN`         | An API token for the Workbench.               |
| `WORKBENCH_CONNECTION_ID` | The ID of the server to put in a blackout.    |

The [Authenticating with the AI DBA Workbench API](authenticate.md) recipe
shows how to create an API token. The user that owns the token needs the
`manage_blackouts` administrative permission, which a superuser has; a token
with a restricted scope must include that permission too. The Workbench accepts
an API token for the blackout endpoints, so unlike the connection endpoints,
they need no login. The following tabs show how each program reads the settings
and stops with an error when the token or the connection ID is missing:

=== "Python"

    ```python
    def settings() -> dict:
        """Reads the settings from the environment.
    
        The or operator treats an empty variable as unset.
        """
        token = os.environ.get("WORKBENCH_TOKEN") or ""
        connection_id = os.environ.get("WORKBENCH_CONNECTION_ID") or ""
        if not (token and connection_id):
            raise RuntimeError(
                "WORKBENCH_TOKEN and WORKBENCH_CONNECTION_ID must be set"
            )
        if not connection_id.isdigit():
            raise RuntimeError("WORKBENCH_CONNECTION_ID must be a number")
        return {
            "base_url": (
                os.environ.get("WORKBENCH_URL") or "http://localhost:8080"
            ).rstrip("/"),
            "token": token,
            "connection_id": int(connection_id),
        }
    ```

=== "TypeScript"

    ```typescript
    interface Settings {
      baseUrl: string;
      token: string;
      connectionId: number;
    }
    
    // Read the settings from the environment. The || operator, unlike ??, also
    // treats an empty variable as unset.
    function settings(): Settings {
      const token = process.env.WORKBENCH_TOKEN || "";
      const connectionId = process.env.WORKBENCH_CONNECTION_ID || "";
      if (!token || !connectionId) {
        throw new Error("WORKBENCH_TOKEN and WORKBENCH_CONNECTION_ID must be set");
      }
      if (!/^\d+$/.test(connectionId)) {
        throw new Error("WORKBENCH_CONNECTION_ID must be a number");
      }
      const baseUrl = process.env.WORKBENCH_URL || "http://localhost:8080";
      return {
        baseUrl: baseUrl.replace(/\/+$/, ""),
        token,
        connectionId: Number(connectionId),
      };
    }
    ```

=== "Java"

    ```java
    /** The settings that the program reads from the environment. */
    record Settings(String baseUrl, String token, long connectionId) {}
    
    /**
     * Returns the value of an environment variable, or the fallback if the
     * variable is unset or empty, as an unset variable would be.
     */
    static String envOr(String name, String fallback) {
        String value = System.getenv(name);
        return (value != null && !value.isEmpty()) ? value : fallback;
    }
    
    /** Reads the settings from the environment. */
    static Settings settings() throws IOException {
        String token = envOr("WORKBENCH_TOKEN", "");
        String connectionId = envOr("WORKBENCH_CONNECTION_ID", "");
        if (token.isEmpty() || connectionId.isEmpty()) {
            throw new IOException(
                    "WORKBENCH_TOKEN and WORKBENCH_CONNECTION_ID must be set");
        }
        if (!connectionId.matches("[0-9]+")) {
            throw new IOException("WORKBENCH_CONNECTION_ID must be a number");
        }
        String baseUrl = envOr("WORKBENCH_URL", "http://localhost:8080")
                .replaceAll("/+$", "");
        return new Settings(baseUrl, token, Long.parseLong(connectionId));
    }
    ```

=== "C#"

    ```csharp
    // Returns the value of an environment variable, or null if the variable
    // is unset or empty, as an unset variable would be.
    static string? EnvValue(string name) =>
        Environment.GetEnvironmentVariable(name) is { Length: > 0 } value
            ? value
            : null;
    
    // Reads the settings from the environment.
    static (string BaseUrl, string Token, long ConnectionId) Settings()
    {
        var token = EnvValue("WORKBENCH_TOKEN");
        var connectionId = EnvValue("WORKBENCH_CONNECTION_ID");
        if (token is null || connectionId is null)
        {
            throw new InvalidOperationException(
                "WORKBENCH_TOKEN and WORKBENCH_CONNECTION_ID must be set");
        }
        if (!connectionId.All(char.IsAsciiDigit))
        {
            throw new InvalidOperationException(
                "WORKBENCH_CONNECTION_ID must be a number");
        }
        var baseUrl = EnvValue("WORKBENCH_URL") ?? "http://localhost:8080";
        return (baseUrl.TrimEnd('/'), token, long.Parse(connectionId));
    }
    ```

=== "Go"

    ```go
    // settings holds the values that the program reads from the environment.
    type settings struct {
    	baseURL      string
    	token        string
    	connectionID int
    }
    
    // envOr returns the value of an environment variable, or the fallback if
    // the variable is unset or empty, as an unset variable would be.
    func envOr(name, fallback string) string {
    	if value := os.Getenv(name); value != "" {
    		return value
    	}
    	return fallback
    }
    
    // loadSettings reads the settings from the environment.
    func loadSettings() (settings, error) {
    	s := settings{
    		baseURL: strings.TrimRight(envOr("WORKBENCH_URL", "http://localhost:8080"), "/"),
    		token:   os.Getenv("WORKBENCH_TOKEN"),
    	}
    	id := os.Getenv("WORKBENCH_CONNECTION_ID")
    	if s.token == "" || id == "" {
    		return s, errors.New("WORKBENCH_TOKEN and WORKBENCH_CONNECTION_ID must be set")
    	}
    	var err error
    	if s.connectionID, err = strconv.Atoi(id); err != nil {
    		return s, fmt.Errorf("WORKBENCH_CONNECTION_ID must be a number: %w", err)
    	}
    	return s, nil
    }
    
    ```

=== "Rust"

    ```rust
    /// Any error, boxed, so that a function can return errors of several types
    /// with the ? operator.
    type Result<T> = std::result::Result<T, Box<dyn Error>>;
    
    /// The settings that the program reads from the environment.
    struct Settings {
        base_url: String,
        token: String,
        connection_id: u64,
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
        // parse() alone would also accept a leading plus sign.
        if !connection_id.bytes().all(|b| b.is_ascii_digit()) {
            return Err("WORKBENCH_CONNECTION_ID must be a number".into());
        }
        let connection_id = connection_id.parse()?;
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
    ```

=== "Ruby"

    ```ruby
    # Returns the value of an environment variable, or a fallback if the
    # variable is unset or empty, as an unset variable would be.
    def env_or(name, fallback)
      value = ENV[name]
      value.nil? || value.empty? ? fallback : value
    end
    
    # Reads the settings from the environment.
    def settings
      token = env_or("WORKBENCH_TOKEN", nil)
      connection_id = env_or("WORKBENCH_CONNECTION_ID", nil)
      raise "WORKBENCH_TOKEN and WORKBENCH_CONNECTION_ID must be set" unless token && connection_id
      raise "WORKBENCH_CONNECTION_ID must be a number" unless connection_id.match?(/\A\d+\z/)
    
      {
        base_url: env_or("WORKBENCH_URL", "http://localhost:8080").sub(%r{/+\z}, ""),
        token: token,
        connection_id: Integer(connection_id, 10)
      }
    end
    ```

=== "curl"

    ```bash
    # Read the settings from the environment. The :- and :? forms, unlike - and
    # ?, treat an empty variable as unset.
    WORKBENCH_URL="${WORKBENCH_URL:-http://localhost:8080}"
    WORKBENCH_URL="${WORKBENCH_URL%/}"
    : "${WORKBENCH_TOKEN:?WORKBENCH_TOKEN must be set}"
    : "${WORKBENCH_CONNECTION_ID:?WORKBENCH_CONNECTION_ID must be set}"
    ```

## Sending Requests

Every call to the API goes through one helper function. The function adds the
`/api/v1` prefix to the path, sends the token as a `Bearer` credential in the
`Authorization` header, and sets a timeout so that a stalled server cannot hang
the program. When the server rejects a request, the function raises an error
that includes the status code and the message from the server. The following
tabs show the helper function from each program:

=== "Python"

    ```python
    interrupted = None
    
    
    def on_signal(signum, frame) -> None:
        """Records that the program received SIGINT or SIGTERM. The handler
        replaces the default action, which would end the program before it could
        delete the blackout, and a second signal does nothing more."""
        global interrupted
        interrupted = signal.Signals(signum).name
    
    
    def api(cfg: dict, method: str, path: str, interruptible: bool = True,
            **kwargs) -> httpx.Response:
        """Sends a request to the API and returns the response.
    
        A request that the server rejects raises an error that includes the
        message from the server, which raise_for_status alone would leave out.
        After a signal, every request that is interruptible fails at once; the
        cleanup and the create call, whose result the program must not lose,
        pass False.
        """
        if interruptible and interrupted:
            raise RuntimeError(f"Interrupted by {interrupted}")
        response = httpx.request(
            method, f"{cfg['base_url']}/api/v1{path}", timeout=30,
            headers={"Authorization": f"Bearer {cfg['token']}"}, **kwargs,
        )
        if response.is_error:
            raise RuntimeError(
                f"{method} {path} failed with status {response.status_code}: "
                f"{response.text.strip()}"
            )
        return response
    ```

=== "TypeScript"

    ```typescript
    interface Blackout {
      id: number;
      is_active: boolean;
    }
    
    // Aborts the request in progress, and every later one that can be
    // interrupted, when the program receives SIGINT or SIGTERM. The handlers also
    // stop Node.js from exiting on those signals, which lets the cleanup run, and
    // a second signal during the cleanup does nothing.
    const interrupted = new AbortController();
    for (const name of ["SIGINT", "SIGTERM"] as const) {
      process.on(name, () => interrupted.abort(new Error(`Interrupted by ${name}`)));
    }
    
    // Sends a request to the API and returns the response. A request that the
    // server rejects throws an error that includes the message from the server.
    // The cleanup passes interruptible as false, so that a signal cannot cancel
    // it.
    async function api(
      s: Settings,
      method: string,
      path: string,
      body?: unknown,
      interruptible = true,
    ): Promise<Response> {
      const headers: Record<string, string> = {
        Authorization: `Bearer ${s.token}`,
      };
      if (body !== undefined) headers["Content-Type"] = "application/json";
    
      const response = await fetch(`${s.baseUrl}/api/v1${path}`, {
        method,
        headers,
        body: body === undefined ? undefined : JSON.stringify(body),
        signal: interruptible
          ? AbortSignal.any([AbortSignal.timeout(30_000), interrupted.signal])
          : AbortSignal.timeout(30_000),
      });
      if (!response.ok) {
        const text = (await response.text()).trim();
        throw new Error(
          `${method} ${path} failed with status ${response.status}: ${text}`,
        );
      }
      return response;
    }
    ```

=== "Java"

    ```java
    /** One client serves every request; it is safe to share. */
    static final HttpClient CLIENT = HttpClient.newBuilder()
            .connectTimeout(Duration.ofSeconds(30))
            .build();
    
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
    
    /** Converts between JSON text and Java objects. */
    static final ObjectMapper JSON = new ObjectMapper();
    
    /**
     * Sends a request to the API and returns the JSON reply, or null if the
     * reply has no body. The body may be null. A request that the server
     * rejects throws an error that includes the message from the server.
     */
    static JsonNode api(Settings cfg, String method, String path,
            Object body) throws IOException, InterruptedException {
        HttpRequest.Builder request = HttpRequest
                .newBuilder(URI.create(cfg.baseUrl() + "/api/v1" + path))
                .timeout(Duration.ofSeconds(30))
                .header("Authorization", "Bearer " + cfg.token());
        HttpRequest.BodyPublisher content = HttpRequest.BodyPublishers.noBody();
        if (body != null) {
            request.header("Content-Type", "application/json");
            content = HttpRequest.BodyPublishers.ofString(
                    JSON.writeValueAsString(body));
        }
    
        HttpResponse<String> response = send(request.method(method, content).build());
        if (response.statusCode() >= 400) {
            throw new IOException(method + " " + path
                    + " failed with status " + response.statusCode() + ": "
                    + response.body().strip());
        }
        String text = response.body();
        return text.isEmpty() ? null : JSON.readTree(text);
    }
    ```

=== "C#"

    ```csharp
    // The name of the signal that the program received, if any, and a token
    // that the signal cancels, which abandons the request in progress.
    string? interrupted = null;
    using var signalled = new CancellationTokenSource();
    
    // Catches SIGINT and SIGTERM. Setting Cancel stops the default action,
    // which would end the program before it could delete the blackout, and a
    // second signal does nothing more.
    void OnSignal(PosixSignalContext context)
    {
        context.Cancel = true;
        interrupted ??= context.Signal.ToString();
        signalled.Cancel();
    }
    using var onInt = PosixSignalRegistration.Create(PosixSignal.SIGINT, OnSignal);
    using var onTerm = PosixSignalRegistration.Create(PosixSignal.SIGTERM, OnSignal);
    
    // One client serves every request, with a timeout for each.
    var http = new HttpClient { Timeout = TimeSpan.FromSeconds(30) };
    var cfg = (BaseUrl: "", Token: "", ConnectionId: 0L);
    
    // Sends a request to the API and returns the JSON reply, or null if the
    // reply has no body. A request that the server rejects throws an error
    // that includes the message from the server. After a signal, every
    // request that is interruptible fails at once, and a signal abandons one
    // in progress; the cleanup and the create call, whose result the program
    // must not lose, pass false.
    async Task<JsonNode?> Api(string method, string path, bool interruptible,
        object? body = null)
    {
        var cancel = interruptible ? signalled.Token : CancellationToken.None;
        try
        {
            cancel.ThrowIfCancellationRequested();
            using var request = new HttpRequestMessage(
                new HttpMethod(method), $"{cfg.BaseUrl}/api/v1{path}");
            request.Headers.Authorization =
                new AuthenticationHeaderValue("Bearer", cfg.Token);
            if (body is not null)
            {
                request.Content = JsonContent.Create(body);
            }
    
            using var response = await http.SendAsync(request, cancel);
            var text = await response.Content.ReadAsStringAsync(cancel);
            if ((int)response.StatusCode >= 400)
            {
                throw new HttpRequestException(
                    $"{method} {path} failed with status {(int)response.StatusCode}: "
                    + text.Trim());
            }
            return text.Length == 0 ? null : JsonNode.Parse(text);
        }
        catch (OperationCanceledException) when (cancel.IsCancellationRequested)
        {
            throw new InvalidOperationException($"Interrupted by {interrupted}");
        }
    }
    ```

=== "Go"

    ```go
    // client gives every request a timeout; the default client has none.
    var client = &http.Client{Timeout: 30 * time.Second}
    
    // blackout is the part of a blackout that the program needs.
    type blackout struct {
    	ID       int64 `json:"id"`
    	IsActive bool  `json:"is_active"`
    }
    
    // api sends a request to the API and decodes the JSON reply into out, if
    // given. A request that the server rejects returns an error that includes
    // the message from the server. Cancelling ctx, which the program does when it
    // receives SIGINT or SIGTERM, abandons the request.
    func api(ctx context.Context, s settings, method, path string, body, out any) error {
    	var reader io.Reader
    	if body != nil {
    		encoded, err := json.Marshal(body)
    		if err != nil {
    			return err
    		}
    		reader = bytes.NewReader(encoded)
    	}
    
    	req, err := http.NewRequestWithContext(ctx, method, s.baseURL+"/api/v1"+path, reader)
    	if err != nil {
    		return err
    	}
    	req.Header.Set("Authorization", "Bearer "+s.token)
    	if body != nil {
    		req.Header.Set("Content-Type", "application/json")
    	}
    
    	resp, err := client.Do(req)
    	if err != nil {
    		return err
    	}
    	defer resp.Body.Close()
    	if resp.StatusCode >= 400 {
    		text, _ := io.ReadAll(resp.Body)
    		return fmt.Errorf("%s %s failed with status %d: %s",
    			method, path, resp.StatusCode, strings.TrimSpace(string(text)))
    	}
    	if out == nil {
    		return nil
    	}
    	return json.NewDecoder(resp.Body).Decode(out)
    }
    
    ```

=== "Rust"

    ```rust
    /// The number of the SIGINT or SIGTERM signal that the program received,
    /// or 0 if it has received neither.
    static INTERRUPTED: AtomicUsize = AtomicUsize::new(0);
    
    /// Catches SIGINT and SIGTERM. The handler records the signal in
    /// INTERRUPTED and replaces the default action, which would end the
    /// program before it could delete the blackout, so a second signal does
    /// nothing more.
    fn catch_signals() -> Result<()> {
        for signal in [SIGINT, SIGTERM] {
            signal_hook::flag::register_usize(signal, &INTERRUPTED, signal as usize)?;
        }
        Ok(())
    }
    
    /// One client serves every request, with a timeout for each; the client
    /// has none by default.
    static CLIENT: LazyLock<Client> = LazyLock::new(|| {
        Client::builder()
            .timeout(Duration::from_secs(30))
            .build()
            .expect("could not create the HTTP client")
    });
    
    /// Sends a request to the API and returns the JSON reply, or null if the
    /// reply has no body. A request that the server rejects returns an error
    /// that includes the message from the server. After a signal, every
    /// request that is interruptible fails at once; the cleanup and the create
    /// call, whose result the program must not lose, pass false.
    fn api(
        cfg: &Settings,
        method: Method,
        path: &str,
        interruptible: bool,
        body: Option<&Value>,
    ) -> Result<Value> {
        if interruptible {
            match INTERRUPTED.load(Ordering::SeqCst) {
                0 => {}
                signal if signal == SIGINT as usize => return Err("interrupted by SIGINT".into()),
                _ => return Err("interrupted by SIGTERM".into()),
            }
        }
        let mut request = CLIENT
            .request(method.clone(), format!("{}/api/v1{path}", cfg.base_url))
            .bearer_auth(&cfg.token);
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
    ```

=== "Ruby"

    ```ruby
    # The name of the signal that the program received, if any.
    $interrupted = nil
    
    # Records that the program received SIGINT or SIGTERM. The handler replaces
    # the default action, which would end the program before it could delete
    # the blackout, and a second signal does nothing more.
    def catch_signals
      %w[INT TERM].each do |name|
        Signal.trap(name) { $interrupted = "SIG#{name}" }
      end
    end
    
    # Sends a request to the API and returns the decoded reply, or nil if the
    # reply has no body. A request that the server rejects raises an error that
    # includes the message from the server. After a signal, every request that
    # is interruptible fails at once; the cleanup and the create call, whose
    # result the program must not lose, pass false.
    def api(method, cfg, path, interruptible: true, body: nil)
      raise "Interrupted by #{$interrupted}" if interruptible && $interrupted
    
      uri = URI("#{cfg[:base_url]}/api/v1#{path}")
      headers = { "Authorization" => "Bearer #{cfg[:token]}" }
      headers["Content-Type"] = "application/json" if body
    
      # Net::HTTP has no overall timeout, so limit both the connection and
      # each read.
      response = Net::HTTP.start(uri.host, uri.port,
                                 use_ssl: uri.scheme == "https",
                                 open_timeout: 30, read_timeout: 30) do |http|
        http.send_request(method, uri.request_uri, body&.to_json, headers)
      end
      if response.code.to_i >= 400
        raise "#{method} #{path} failed with status #{response.code}: " \
              "#{response.body.to_s.strip}"
      end
      text = response.body.to_s
      text.empty? ? nil : JSON.parse(text)
    end
    ```

=== "curl"

    ```bash
    # Sends an authenticated request and prints the JSON reply:
    # api METHOD PATH [curl options]. With --fail-with-body, a request that the
    # server rejects leaves the server's error message in the reply, and the
    # function prints it to standard error. A caller can set allow_status to an
    # HTTP status that the function should treat as success.
    # The token goes to curl in a header file that bash supplies through a pipe,
    # so that it never appears in the arguments of the curl process, which other
    # users can read in the process list.
    api() {
        local method="$1" path="$2"
        shift 2
        local output status response
        # With allow_status, curl stays quiet about the status that is allowed.
        local show_error=--show-error
        [[ -z "${allow_status:-}" ]] || show_error=--silent
        # The --write-out option appends the HTTP status on a line of its own.
        output=$(curl --silent "$show_error" --fail-with-body \
            --connect-timeout 10 --max-time 30 \
            --write-out '\n%{http_code}' \
            --request "$method" \
            --header @<(printf 'Authorization: Bearer %s\n' "$WORKBENCH_TOKEN") \
            "$@" "$WORKBENCH_URL/api/v1$path") && status=0 || status=$?
        response="${output%$'\n'*}"
        if [[ "$status" -ne 0 ]]; then
            if [[ -n "${allow_status:-}" && "${output##*$'\n'}" == "$allow_status" ]]
            then
                return 0
            fi
            echo "$method $path failed: ${response:-no reply (curl $status)}" >&2
            return 1
        fi
        printf '%s' "$response"
    }
    ```

## Creating the Blackout

The program creates the blackout with `POST /api/v1/blackouts`. The `scope`
field is `estate`, `group`, `cluster`, or `server`, and a `server` blackout
also needs the `connection_id` of the server. The `start_time` and `end_time`
fields are timestamps in RFC 3339 format, and the end must come after the
start. The program starts the blackout a minute in the past, so that a small
difference between the clocks of the two machines cannot leave it inactive. The
reply is the new blackout, including its `id` and an `is_active` flag. The
following tabs show how each program creates the blackout:

=== "Python"

    ```python
    def create_blackout(cfg: dict) -> dict:
        """Creates a blackout for one monitored server and returns it.
    
        The blackout starts a minute ago, so that a small difference between
        the clocks of this machine and the server cannot leave it inactive,
        and it ends in one hour. The times are in RFC 3339 format.
        """
        now = datetime.now(timezone.utc)
        return api(cfg, "POST", "/blackouts", interruptible=False, json={
            "scope": "server",
            "connection_id": cfg["connection_id"],
            "reason": "Cookbook maintenance window",
            "start_time": (now - timedelta(minutes=1)).isoformat(),
            "end_time": (now + timedelta(hours=1)).isoformat(),
        }).json()
    ```

=== "TypeScript"

    ```typescript
    // Creates a blackout for one monitored server and returns it. The blackout
    // starts a minute ago, so that a small difference between the clocks of this
    // machine and the server cannot leave it inactive, and it ends in one hour.
    // The toISOString method writes the times in RFC 3339 format.
    async function createBlackout(s: Settings): Promise<Blackout> {
      const now = Date.now();
      // A signal cannot interrupt this request either, because the program
      // would not know the ID of a blackout that the server created after the
      // interruption. The next request notices the signal instead.
      const response = await api(
        s,
        "POST",
        "/blackouts",
        {
          scope: "server",
          connection_id: s.connectionId,
          reason: "Cookbook maintenance window",
          start_time: new Date(now - 60_000).toISOString(),
          end_time: new Date(now + 3_600_000).toISOString(),
        },
        false,
      );
      return (await response.json()) as Blackout;
    }
    ```

=== "Java"

    ```java
    /**
     * Creates a blackout for one monitored server and returns it. The
     * blackout starts a minute ago, so that a small difference between the
     * clocks of this machine and the server cannot leave it inactive, and
     * it ends in one hour. Instant.toString() writes the times in RFC 3339
     * format.
     */
    static JsonNode createBlackout(Settings cfg)
            throws IOException, InterruptedException {
        Instant now = Instant.now().truncatedTo(ChronoUnit.SECONDS);
        return api(cfg, "POST", "/blackouts", Map.of(
                "scope", "server",
                "connection_id", cfg.connectionId(),
                "reason", "Cookbook maintenance window",
                "start_time", now.minus(Duration.ofMinutes(1)).toString(),
                "end_time", now.plus(Duration.ofHours(1)).toString()));
    }
    ```

=== "C#"

    ```csharp
    // Creates a blackout for one monitored server and returns it. The blackout
    // starts a minute ago, so that a small difference between the clocks of
    // this machine and the server cannot leave it inactive, and it ends in one
    // hour. The "O" format writes the times in RFC 3339 format.
    async Task<JsonNode> CreateBlackout()
    {
        var now = DateTimeOffset.UtcNow;
        return await Api("POST", "/blackouts", false, new
        {
            scope = "server",
            connection_id = cfg.ConnectionId,
            reason = "Cookbook maintenance window",
            start_time = now.AddMinutes(-1).ToString("O"),
            end_time = now.AddHours(1).ToString("O"),
        }) ?? throw new InvalidOperationException("The reply had no blackout");
    }
    ```

=== "Go"

    ```go
    // createBlackout creates a blackout for one monitored server and returns
    // it. The blackout starts a minute ago, so that a small difference between
    // the clocks of this machine and the server cannot leave it inactive, and
    // it ends in one hour. The times are in RFC 3339 format.
    //
    // A signal cannot interrupt this request, because the program would not
    // know the ID of a blackout that the server created after the interruption.
    func createBlackout(s settings) (blackout, error) {
    	now := time.Now().UTC()
    	var b blackout
    	err := api(context.Background(), s, "POST", "/blackouts", map[string]any{
    		"scope":         "server",
    		"connection_id": s.connectionID,
    		"reason":        "Cookbook maintenance window",
    		"start_time":    now.Add(-time.Minute).Format(time.RFC3339),
    		"end_time":      now.Add(time.Hour).Format(time.RFC3339),
    	}, &b)
    	return b, err
    }
    
    ```

=== "Rust"

    ```rust
    /// Creates a blackout for one monitored server and returns it. The
    /// blackout starts a minute ago, so that a small difference between the
    /// clocks of this machine and the server cannot leave it inactive, and it
    /// ends in one hour. The times are in RFC 3339 format.
    fn create_blackout(cfg: &Settings) -> Result<Value> {
        let now = SystemTime::now();
        let body = json!({
            "scope": "server",
            "connection_id": cfg.connection_id,
            "reason": "Cookbook maintenance window",
            "start_time": format_rfc3339_seconds(now - Duration::from_secs(60)).to_string(),
            "end_time": format_rfc3339_seconds(now + Duration::from_secs(3600)).to_string(),
        });
        api(cfg, Method::POST, "/blackouts", false, Some(&body))
    }
    ```

=== "Ruby"

    ```ruby
    # Creates a blackout for one monitored server and returns it. The blackout
    # starts a minute ago, so that a small difference between the clocks of
    # this machine and the server cannot leave it inactive, and it ends in one
    # hour. The times are in RFC 3339 format.
    def create_blackout(cfg)
      now = Time.now.utc
      api("POST", cfg, "/blackouts", interruptible: false, body: {
            scope: "server",
            connection_id: cfg[:connection_id],
            reason: "Cookbook maintenance window",
            start_time: (now - 60).iso8601,
            end_time: (now + 3600).iso8601
          })
    end
    ```

=== "curl"

    ```bash
    # Creates a blackout for one monitored server and prints the reply. The
    # reason ends with the unique marker, so that the cleanup can find the
    # blackout even if this script never sees the reply. The blackout starts a
    # minute ago, so that a small difference between the clocks of this machine and
    # the server cannot leave it inactive, and it ends in one hour. The times are
    # in RFC 3339 format, which jq builds from the current time.
    create_blackout() {
        local connection_id="$1" marker="$2"
        jq -n --argjson connection_id "$connection_id" --arg marker "$marker" \
            '{scope: "server", connection_id: $connection_id,
              reason: ("Cookbook maintenance window " + $marker),
              start_time: (now - 60 | todate),
              end_time: (now + 3600 | todate)}' |
            api POST /blackouts \
                --header 'Content-Type: application/json' --data @-
    }
    ```

## Reading the Blackout

The program reads the blackout back with `GET /api/v1/blackouts/{id}`. The
reply has the same fields as the reply to the create call, and `is_active` is
`true` while the current time lies between the start and the end. The following
tabs show how each program reads the blackout:

=== "Python"

    ```python
    def get_blackout(cfg: dict, blackout_id: int) -> dict:
        """Returns the blackout with the given ID."""
        return api(cfg, "GET", f"/blackouts/{blackout_id}").json()
    ```

=== "TypeScript"

    ```typescript
    // Returns the blackout with the given ID.
    async function getBlackout(s: Settings, id: number): Promise<Blackout> {
      const response = await api(s, "GET", `/blackouts/${id}`);
      return (await response.json()) as Blackout;
    }
    ```

=== "Java"

    ```java
    /** Returns the blackout with the given ID. */
    static JsonNode getBlackout(Settings cfg, long blackoutId)
            throws IOException, InterruptedException {
        return api(cfg, "GET", "/blackouts/" + blackoutId, null);
    }
    ```

=== "C#"

    ```csharp
    // Returns the blackout with the given ID.
    async Task<JsonNode> GetBlackout(long blackoutId) =>
        await Api("GET", $"/blackouts/{blackoutId}", true)
            ?? throw new InvalidOperationException("The reply had no blackout");
    ```

=== "Go"

    ```go
    // getBlackout returns the blackout with the given ID.
    func getBlackout(ctx context.Context, s settings, id int64) (blackout, error) {
    	var b blackout
    	err := api(ctx, s, "GET", fmt.Sprintf("/blackouts/%d", id), nil, &b)
    	return b, err
    }
    
    ```

=== "Rust"

    ```rust
    /// Returns the blackout with the given ID.
    fn get_blackout(cfg: &Settings, blackout_id: i64) -> Result<Value> {
        api(
            cfg,
            Method::GET,
            &format!("/blackouts/{blackout_id}"),
            true,
            None,
        )
    }
    ```

=== "Ruby"

    ```ruby
    # Returns the blackout with the given ID.
    def get_blackout(cfg, blackout_id)
      api("GET", cfg, "/blackouts/#{blackout_id}")
    end
    ```

=== "curl"

    ```bash
    # Prints the blackout with the given ID.
    get_blackout() {
        api GET "/blackouts/$1"
    }
    ```

## Stopping the Blackout

The program ends the blackout early with `POST /api/v1/blackouts/{id}/stop`,
which sets the end time to the current time. The reply is the stopped blackout,
and `is_active` is now `false`. The Workbench keeps a stopped blackout as a
record, and a second stop request fails with a 404 status because the blackout
is no longer in progress. The following tabs show how each program stops the
blackout:

=== "Python"

    ```python
    def stop_blackout(cfg: dict, blackout_id: int) -> dict:
        """Stops a blackout that is in progress, which sets its end time to
        now, and returns the stopped blackout."""
        return api(cfg, "POST", f"/blackouts/{blackout_id}/stop").json()
    ```

=== "TypeScript"

    ```typescript
    // Stops a blackout that is in progress, which sets its end time to now, and
    // returns the stopped blackout.
    async function stopBlackout(s: Settings, id: number): Promise<Blackout> {
      const response = await api(s, "POST", `/blackouts/${id}/stop`);
      return (await response.json()) as Blackout;
    }
    ```

=== "Java"

    ```java
    /**
     * Stops a blackout that is in progress, which sets its end time to now,
     * and returns the stopped blackout.
     */
    static JsonNode stopBlackout(Settings cfg, long blackoutId)
            throws IOException, InterruptedException {
        return api(cfg, "POST", "/blackouts/" + blackoutId + "/stop", null);
    }
    ```

=== "C#"

    ```csharp
    // Stops a blackout that is in progress, which sets its end time to now,
    // and returns the stopped blackout.
    async Task<JsonNode> StopBlackout(long blackoutId) =>
        await Api("POST", $"/blackouts/{blackoutId}/stop", true)
            ?? throw new InvalidOperationException("The reply had no blackout");
    ```

=== "Go"

    ```go
    // stopBlackout stops a blackout that is in progress, which sets its end
    // time to now, and returns the stopped blackout.
    func stopBlackout(ctx context.Context, s settings, id int64) (blackout, error) {
    	var b blackout
    	err := api(ctx, s, "POST", fmt.Sprintf("/blackouts/%d/stop", id), nil, &b)
    	return b, err
    }
    
    ```

=== "Rust"

    ```rust
    /// Stops a blackout that is in progress, which sets its end time to now,
    /// and returns the stopped blackout.
    fn stop_blackout(cfg: &Settings, blackout_id: i64) -> Result<Value> {
        let path = format!("/blackouts/{blackout_id}/stop");
        api(cfg, Method::POST, &path, true, None)
    }
    ```

=== "Ruby"

    ```ruby
    # Stops a blackout that is in progress, which sets its end time to now, and
    # returns the stopped blackout.
    def stop_blackout(cfg, blackout_id)
      api("POST", cfg, "/blackouts/#{blackout_id}/stop")
    end
    ```

=== "curl"

    ```bash
    # Stops a blackout that is in progress, which sets its end time to now, and
    # prints the stopped blackout.
    stop_blackout() {
        api POST "/blackouts/$1/stop"
    }
    ```

## Deleting the Blackout

The program removes the record with `DELETE /api/v1/blackouts/{id}`. The reply
is a short status message. The following tabs show how each program deletes the
blackout:

=== "Python"

    ```python
    def delete_blackout(cfg: dict, blackout_id: int) -> None:
        """Deletes a blackout by its ID."""
        api(cfg, "DELETE", f"/blackouts/{blackout_id}", interruptible=False)
    ```

=== "TypeScript"

    ```typescript
    // Deletes a blackout by its ID. A signal cannot interrupt this request,
    // because it is the cleanup.
    async function deleteBlackout(s: Settings, id: number): Promise<void> {
      await api(s, "DELETE", `/blackouts/${id}`, undefined, false);
    }
    ```

=== "Java"

    ```java
    /** Deletes a blackout by its ID. */
    static void deleteBlackout(Settings cfg, long blackoutId)
            throws IOException, InterruptedException {
        api(cfg, "DELETE", "/blackouts/" + blackoutId, null);
    }
    ```

=== "C#"

    ```csharp
    // Deletes a blackout by its ID.
    async Task DeleteBlackout(long blackoutId) =>
        await Api("DELETE", $"/blackouts/{blackoutId}", false);
    ```

=== "Go"

    ```go
    // deleteBlackout deletes a blackout by its ID. A signal cannot interrupt this
    // request, because it is the cleanup.
    func deleteBlackout(s settings, id int64) error {
    	return api(context.Background(), s, "DELETE", fmt.Sprintf("/blackouts/%d", id), nil, nil)
    }
    
    ```

=== "Rust"

    ```rust
    /// Deletes a blackout by its ID.
    fn delete_blackout(cfg: &Settings, blackout_id: i64) -> Result<()> {
        let path = format!("/blackouts/{blackout_id}");
        api(cfg, Method::DELETE, &path, false, None)?;
        Ok(())
    }
    ```

=== "Ruby"

    ```ruby
    # Deletes a blackout by its ID.
    def delete_blackout(cfg, blackout_id)
      api("DELETE", cfg, "/blackouts/#{blackout_id}", interruptible: false)
    end
    ```

=== "curl"

    ```bash
    # Deletes a blackout by its ID. A 404 status means that the blackout is
    # already gone, which is what the caller wanted, so it counts as success.
    delete_blackout() {
        allow_status=404 api DELETE "/blackouts/$1" >/dev/null
    }
    ```

## Cleaning Up After a Failure

The main part of each program deletes the blackout on every path, so that a
failure after the create call does not leave alerts suppressed for the next
hour. This includes SIGINT (Ctrl+C) and SIGTERM: each program catches both
signals, so that the default action of ending the program does not skip the
cleanup. In every program except the Java one, a signal makes the next request
that the program would send fail with an `Interrupted` error, or abandons the
request in progress (in the TypeScript, C# and Go programs), and the cleanup
then deletes the blackout. In these programs the create call and the delete
call ignore signals, so that the program never loses the ID of a blackout that
the server created, and a second signal during the cleanup does nothing. The
Python program uses a `finally` block and a signal handler, the TypeScript
program keeps the delete step in a variable that runs after the `try` block,
and the Go program returns the delete step from its `run()` function to
`main()`, which uses `signal.NotifyContext`. The C# program registers a
`PosixSignalRegistration` handler that cancels the requests in progress, the
Rust program sets a flag with signal-hook, and the Ruby program sets one with
`Signal.trap` and deletes the blackout in an `ensure` block.

Java's supported API cannot catch a signal, so the Java program registers a
shutdown hook, which the JVM runs when SIGINT or SIGTERM ends the program. The
hook deletes the blackout if the program has not already done so, and the JVM
then exits with a non-zero status. The hook and the create call share a lock,
so a signal during the create call makes the hook wait until the program has
recorded the ID of the new blackout.

The curl script cannot ignore signals during the create call, because
Ctrl+C in a terminal sends SIGINT to every process in the foreground group,
including the `curl` process that is making the request. The script instead
puts a random marker in the reason of the blackout, and sets it before the
create call. If the script ends without having read the ID from the reply, its
`EXIT` trap lists the blackouts and deletes the one whose reason contains the
marker, looking up to three times in case the server is still handling the
request. The trap ignores further signals, and treats a 404 status from the
delete call as success, because that means the blackout is already gone. Each
program reports a failure on `stderr` and exits with a non-zero status. The
following tabs show the main part of each program:

=== "Python"

    ```python
    def main() -> int:
        cfg = None
        blackout_id = None
        status = 0
        signal.signal(signal.SIGINT, on_signal)
        signal.signal(signal.SIGTERM, on_signal)
        try:
            cfg = settings()
    
            created = create_blackout(cfg)
            blackout_id = created["id"]
            print("Created a blackout for the server "
                  f"(active: {str(created['is_active']).lower()})")
    
            blackout = get_blackout(cfg, blackout_id)
            print("Read the blackout back "
                  f"(active: {str(blackout['is_active']).lower()})")
    
            stopped = stop_blackout(cfg, blackout_id)
            print("Stopped the blackout "
                  f"(active: {str(stopped['is_active']).lower()})")
            if stopped["is_active"]:
                raise RuntimeError("The blackout is still active")
    
            delete_blackout(cfg, blackout_id)
            blackout_id = None
            print("Deleted the blackout")
        # httpx.HTTPError covers failures to connect, and RuntimeError covers
        # replies that the server rejected or that lacked what we need.
        except (httpx.HTTPError, RuntimeError) as e:
            print(f"Error: {e}", file=sys.stderr)
            status = 1
        finally:
            # Delete the blackout whether or not a later step failed, so that
            # a failed run does not leave alerts suppressed. A return statement
            # in a finally block would hide an exception that is still in
            # flight, so this block sets the exit status instead.
            if blackout_id is not None:
                try:
                    delete_blackout(cfg, blackout_id)
                except (httpx.HTTPError, RuntimeError) as e:
                    print(f"Error: could not delete the blackout: {e}",
                          file=sys.stderr)
                    status = 1
    
        return status
    
    
    if __name__ == "__main__":
        sys.exit(main())
    ```

=== "TypeScript"

    ```typescript
    async function main(): Promise<number> {
      let exitCode = 0;
      let cleanup: (() => Promise<void>) | undefined;
      try {
        const s = settings();
    
        const created = await createBlackout(s);
        // Delete the blackout whether or not a later step fails, so that a
        // failed run does not leave alerts suppressed.
        cleanup = () => deleteBlackout(s, created.id);
        console.log(
          `Created a blackout for the server (active: ${created.is_active})`,
        );
    
        const blackout = await getBlackout(s, created.id);
        console.log(`Read the blackout back (active: ${blackout.is_active})`);
    
        const stopped = await stopBlackout(s, created.id);
        console.log(`Stopped the blackout (active: ${stopped.is_active})`);
        if (stopped.is_active) throw new Error("The blackout is still active");
    
        await cleanup();
        cleanup = undefined;
        console.log("Deleted the blackout");
      } catch (err) {
        console.error(`Error: ${err instanceof Error ? err.message : err}`);
        exitCode = 1;
      }
    
      if (cleanup) {
        try {
          await cleanup();
        } catch (err) {
          console.error(
            `Error: could not delete the blackout: ${
              err instanceof Error ? err.message : err
            }`,
          );
          exitCode = 1;
        }
      }
      return exitCode;
    }
    
    process.exitCode = await main();
    ```

=== "Java"

    ```java
    /**
     * Guards the blackout that is still to be deleted, which the main
     * thread and the shutdown hook share.
     */
    static final Object LOCK = new Object();
    static Settings pendingCfg;
    static Long pendingId;
    
    /**
     * Returns the message of an error. Some errors, such as a refused
     * connection, have no message, so their type stands in for one.
     */
    static String describe(Exception e) {
        return Objects.requireNonNullElse(e.getMessage(), e.toString());
    }
    
    /**
     * Deletes the blackout if one is still pending, and returns false if
     * that fails. The main thread calls this after a failed step, and the
     * shutdown hook calls it when SIGINT or SIGTERM ends the program first.
     */
    static boolean cleanUp() {
        synchronized (LOCK) {
            if (pendingId == null) {
                return true;
            }
            try {
                deleteBlackout(pendingCfg, pendingId);
                return true;
            } catch (IOException | InterruptedException | JacksonException e) {
                System.err.println("Error: could not delete the blackout: "
                        + describe(e));
                return false;
            } finally {
                pendingId = null;
            }
        }
    }
    
    public static void main(String[] args) {
        // Java cannot catch a signal with its supported API, but SIGINT and
        // SIGTERM start an orderly shutdown that runs this hook, which
        // deletes the blackout before the program ends.
        Runtime.getRuntime().addShutdownHook(new Thread(Main::cleanUp));
    
        int status = 0;
        try {
            Settings cfg = settings();
    
            // Hold the lock until the ID is recorded, so that a signal
            // during the create call cannot leave the blackout behind.
            JsonNode created;
            long blackoutId;
            synchronized (LOCK) {
                created = createBlackout(cfg);
                blackoutId = created.get("id").asLong();
                pendingCfg = cfg;
                pendingId = blackoutId;
            }
            System.out.println("Created a blackout for the server (active: "
                    + created.get("is_active").asBoolean() + ")");
    
            JsonNode blackout = getBlackout(cfg, blackoutId);
            System.out.println("Read the blackout back (active: "
                    + blackout.get("is_active").asBoolean() + ")");
    
            JsonNode stopped = stopBlackout(cfg, blackoutId);
            boolean active = stopped.get("is_active").asBoolean();
            System.out.println("Stopped the blackout (active: " + active + ")");
            if (active) {
                throw new IOException("The blackout is still active");
            }
    
            synchronized (LOCK) {
                deleteBlackout(cfg, blackoutId);
                pendingId = null;
            }
            System.out.println("Deleted the blackout");
        // IOException covers failures to connect, replies that the server
        // rejected, and replies that lacked what we need; the client
        // throws InterruptedException if the thread is interrupted, and
        // Jackson throws JacksonException for a reply that is not JSON.
        } catch (IOException | InterruptedException | JacksonException e) {
            System.err.println("Error: " + describe(e));
            status = 1;
        }
    
        // Delete the blackout whether or not a later step failed, so that a
        // failed run does not leave alerts suppressed.
        if (!cleanUp()) {
            status = 1;
        }
        System.exit(status);
    }
    ```

=== "C#"

    ```csharp
    // Reports whether an error is one that the program expects: a failure to
    // connect, a reply that the server rejected, a request that timed out or
    // was interrupted, or a reply that lacked what we need.
    static bool Expected(Exception e) => e is HttpRequestException
        or TaskCanceledException or InvalidOperationException or JsonException;
    
    // Returns the is_active flag of a blackout, as the other languages print
    // it; C# would print True or False.
    static string Active(JsonNode blackout) =>
        blackout["is_active"]!.GetValue<bool>() ? "true" : "false";
    
    long? blackoutId = null;
    var status = 0;
    try
    {
        cfg = Settings();
    
        var created = await CreateBlackout();
        blackoutId = created["id"]!.GetValue<long>();
        Console.WriteLine(
            $"Created a blackout for the server (active: {Active(created)})");
    
        var blackout = await GetBlackout(blackoutId.Value);
        Console.WriteLine($"Read the blackout back (active: {Active(blackout)})");
    
        var stopped = await StopBlackout(blackoutId.Value);
        Console.WriteLine($"Stopped the blackout (active: {Active(stopped)})");
        if (stopped["is_active"]!.GetValue<bool>())
        {
            throw new InvalidOperationException("The blackout is still active");
        }
    
        await DeleteBlackout(blackoutId.Value);
        blackoutId = null;
        Console.WriteLine("Deleted the blackout");
    }
    catch (Exception e) when (Expected(e))
    {
        Console.Error.WriteLine($"Error: {e.Message}");
        status = 1;
    }
    finally
    {
        // Delete the blackout whether or not a later step failed, so that a failed
        // run does not leave alerts suppressed. The finally block also runs for an
        // error that the catch does not handle.
        if (blackoutId is long pending)
        {
            try
            {
                await DeleteBlackout(pending);
            }
            catch (Exception e) when (Expected(e))
            {
                Console.Error.WriteLine(
                    $"Error: could not delete the blackout: {e.Message}");
                status = 1;
            }
        }
    }
    
    return status;
    ```

=== "Go"

    ```go
    // run does the work. It returns the cleanup that the caller must run if the
    // program has created a blackout and not yet deleted it.
    func run(ctx context.Context, s settings) (cleanup func() error, err error) {
    	created, err := createBlackout(s)
    	if err != nil {
    		return nil, err
    	}
    	// Return the cleanup before any later step can fail, so that a failed
    	// run does not leave alerts suppressed.
    	cleanup = func() error { return deleteBlackout(s, created.ID) }
    	fmt.Printf("Created a blackout for the server (active: %t)\n", created.IsActive)
    
    	current, err := getBlackout(ctx, s, created.ID)
    	if err != nil {
    		return cleanup, err
    	}
    	fmt.Printf("Read the blackout back (active: %t)\n", current.IsActive)
    
    	stopped, err := stopBlackout(ctx, s, created.ID)
    	if err != nil {
    		return cleanup, err
    	}
    	fmt.Printf("Stopped the blackout (active: %t)\n", stopped.IsActive)
    	if stopped.IsActive {
    		return cleanup, errors.New("the blackout is still active")
    	}
    
    	// Report a failed delete here and clear the cleanup, so that main does not
    	// try again and print a second error.
    	if err := cleanup(); err != nil {
    		return nil, fmt.Errorf("could not delete the blackout: %w", err)
    	}
    	fmt.Println("Deleted the blackout")
    	return nil, nil
    }
    
    func main() {
    	s, err := loadSettings()
    	if err != nil {
    		fmt.Fprintln(os.Stderr, "Error:", err)
    		os.Exit(1)
    	}
    
    	// The handler replaces the default action for these signals, which would
    	// end the program before it could delete the blackout. It cancels ctx,
    	// which abandons the request in progress, and a second signal does
    	// nothing more.
    	ctx, stop := signal.NotifyContext(context.Background(),
    		os.Interrupt, syscall.SIGTERM)
    
    	failed := false
    	cleanup, err := run(ctx, s)
    	if err != nil {
    		fmt.Fprintln(os.Stderr, "Error:", err)
    		failed = true
    	}
    	if cleanup != nil {
    		if err := cleanup(); err != nil {
    			fmt.Fprintln(os.Stderr, "Error: could not delete the blackout:", err)
    			failed = true
    		}
    	}
    	stop()
    	if failed {
    		os.Exit(1)
    	}
    }
    
    ```

=== "Rust"

    ```rust
    /// Returns the is_active flag of a blackout.
    fn is_active(blackout: &Value) -> Result<bool> {
        Ok(blackout["is_active"]
            .as_bool()
            .ok_or("the blackout had no active flag")?)
    }
    
    /// Does the work. Once it has created a blackout, it records the ID in
    /// cleanup, so that main deletes the blackout even if a later step fails.
    fn run(cfg: &Settings, cleanup: &mut Option<i64>) -> Result<()> {
        let created = create_blackout(cfg)?;
        let blackout_id = created["id"]
            .as_i64()
            .ok_or("the reply had no blackout ID")?;
        *cleanup = Some(blackout_id);
        println!(
            "Created a blackout for the server (active: {})",
            is_active(&created)?
        );
    
        let blackout = get_blackout(cfg, blackout_id)?;
        println!("Read the blackout back (active: {})", is_active(&blackout)?);
    
        let stopped = stop_blackout(cfg, blackout_id)?;
        let active = is_active(&stopped)?;
        println!("Stopped the blackout (active: {active})");
        if active {
            return Err("the blackout is still active".into());
        }
    
        delete_blackout(cfg, blackout_id)?;
        *cleanup = None;
        println!("Deleted the blackout");
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
        let cfg = match catch_signals().and_then(|()| settings()) {
            Ok(cfg) => cfg,
            Err(e) => {
                report("Error: ", e.as_ref());
                return ExitCode::FAILURE;
            }
        };
    
        let mut status = ExitCode::SUCCESS;
        let mut cleanup = None;
        if let Err(e) = run(&cfg, &mut cleanup) {
            report("Error: ", e.as_ref());
            status = ExitCode::FAILURE;
        }
    
        // Delete the blackout whether or not a later step failed, so that a
        // failed run does not leave alerts suppressed.
        if let Some(blackout_id) = cleanup {
            if let Err(e) = delete_blackout(&cfg, blackout_id) {
                report("Error: could not delete the blackout: ", e.as_ref());
                status = ExitCode::FAILURE;
            }
        }
        status
    }
    ```

=== "Ruby"

    ```ruby
    def main
      cfg = nil
      blackout_id = nil
      status = 0
      catch_signals
      begin
        cfg = settings
    
        created = create_blackout(cfg)
        blackout_id = created.fetch("id")
        puts "Created a blackout for the server (active: #{created.fetch('is_active')})"
    
        blackout = get_blackout(cfg, blackout_id)
        puts "Read the blackout back (active: #{blackout.fetch('is_active')})"
    
        stopped = stop_blackout(cfg, blackout_id)
        puts "Stopped the blackout (active: #{stopped.fetch('is_active')})"
        raise "The blackout is still active" if stopped["is_active"]
    
        delete_blackout(cfg, blackout_id)
        blackout_id = nil
        puts "Deleted the blackout"
      # Net::HTTP raises errors of many classes, such as SystemCallError for a
      # refused connection and Net::OpenTimeout for a timeout, and the program
      # raises RuntimeError for replies that the server rejected or that lacked
      # what we need, so this catches StandardError, their common ancestor.
      rescue StandardError => e
        warn "Error: #{e.message}"
        status = 1
      ensure
        # Delete the blackout whether or not a later step failed, so that a
        # failed run does not leave alerts suppressed.
        if blackout_id
          begin
            delete_blackout(cfg, blackout_id)
          rescue StandardError => e
            warn "Error: could not delete the blackout: #{e.message}"
            status = 1
          end
        end
      end
      status
    end
    
    exit main
    ```

=== "curl"

    ```bash
    # Prints the IDs of the blackouts whose reason contains the marker.
    find_blackouts() {
        api GET /blackouts |
            jq -r --arg marker "$1" \
                '.blackouts[] | select(.reason | contains($marker)) | .id'
    }
    
    # These variables are global, because the EXIT trap runs after main returns.
    # The marker is set before the create call and cleared once the blackout is
    # deleted, so a non-empty marker means that the outcome of the create call is
    # unknown, or that its blackout still exists. The created variable holds the
    # reply to the create call, which bash assigns before it runs a signal
    # handler, whereas it would not yet have extracted the ID from the reply.
    marker=""
    created=""
    
    cleanup() {
        local status=$?
        # Ignore further signals, so that a second one cannot abort the delete.
        trap '' INT TERM
        # Delete the blackout when the script ends, even if a later step failed,
        # so that a failed run does not leave alerts suppressed. Report a delete
        # that fails, and make the exit status non-zero.
        local id ids=""
        if [[ -n "$created" ]]; then
            ids=$(jq -er '.id' <<<"$created") || ids=""
        fi
        if [[ -z "$ids" && -n "$marker" ]]; then
            # Ctrl+C in a terminal sends SIGINT to every process in the
            # foreground group, which includes curl, so the create call can end
            # without a reply even though the server created the blackout. Look
            # for the blackout by its marker. The server may still be handling
            # the request, so look up to three times, a second apart.
            local attempt
            for attempt in 1 2 3; do
                ids=$(find_blackouts "$marker") || {
                    echo "Error: could not look up the blackout" >&2
                    status=1
                    break
                }
                if [[ -n "$ids" ]]; then
                    break
                fi
                if [[ "$attempt" -lt 3 ]]; then
                    sleep 1
                fi
            done
        fi
        for id in $ids; do
            delete_blackout "$id" || {
                echo "Error: could not delete the blackout $id" >&2
                status=1
            }
        done
        exit "$status"
    }
    
    main() {
        local blackout_id blackout stopped active
        marker="cookbook-$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')"
        created=$(create_blackout "$WORKBENCH_CONNECTION_ID" "$marker")
        blackout_id=$(jq -er '.id' <<<"$created")
        active=$(jq -r '.is_active' <<<"$created")
        echo "Created a blackout for the server (active: $active)"
    
        blackout=$(get_blackout "$blackout_id")
        active=$(jq -r '.is_active' <<<"$blackout")
        echo "Read the blackout back (active: $active)"
    
        stopped=$(stop_blackout "$blackout_id")
        active=$(jq -r '.is_active' <<<"$stopped")
        echo "Stopped the blackout (active: $active)"
        if [[ "$active" != "false" ]]; then
            echo "The blackout is still active" >&2
            return 1
        fi
    
        delete_blackout "$blackout_id"
        created=""
        marker=""
        echo "Deleted the blackout"
    }
    
    # Without handlers for the signals, a second signal that arrives before bash
    # has run the EXIT trap would end the script before the delete. The handlers
    # exit with the usual status for a signal (128 plus the signal number), which
    # runs the EXIT trap.
    trap cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    main
    ```

If a run is killed without a chance to clean up (with `kill -9`, for example),
the blackout stays in place until its end time. To end it sooner, send a `POST`
request to the `stop` path of the blackout.

## Running the Example

The complete project for each language is available in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/ai_dba_workbench/blackouts).
Set `WORKBENCH_URL`, `WORKBENCH_TOKEN`, and `WORKBENCH_CONNECTION_ID` for your
server, and then run the command for your language from the corresponding
project directory. The following tabs show the commands that build and run each
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
    Scheduling a maintenance blackout with the AI DBA Workbench API, using httpx.
    
    Copyright (c) 2026, pgEdge, Inc.
    This code is released under the PostgreSQL License.
    """
    
    import os
    import signal
    import sys
    from datetime import datetime, timedelta, timezone
    
    import httpx
    
    
    def settings() -> dict:
        """Reads the settings from the environment.
    
        The or operator treats an empty variable as unset.
        """
        token = os.environ.get("WORKBENCH_TOKEN") or ""
        connection_id = os.environ.get("WORKBENCH_CONNECTION_ID") or ""
        if not (token and connection_id):
            raise RuntimeError(
                "WORKBENCH_TOKEN and WORKBENCH_CONNECTION_ID must be set"
            )
        if not connection_id.isdigit():
            raise RuntimeError("WORKBENCH_CONNECTION_ID must be a number")
        return {
            "base_url": (
                os.environ.get("WORKBENCH_URL") or "http://localhost:8080"
            ).rstrip("/"),
            "token": token,
            "connection_id": int(connection_id),
        }
    
    
    interrupted = None
    
    
    def on_signal(signum, frame) -> None:
        """Records that the program received SIGINT or SIGTERM. The handler
        replaces the default action, which would end the program before it could
        delete the blackout, and a second signal does nothing more."""
        global interrupted
        interrupted = signal.Signals(signum).name
    
    
    def api(cfg: dict, method: str, path: str, interruptible: bool = True,
            **kwargs) -> httpx.Response:
        """Sends a request to the API and returns the response.
    
        A request that the server rejects raises an error that includes the
        message from the server, which raise_for_status alone would leave out.
        After a signal, every request that is interruptible fails at once; the
        cleanup and the create call, whose result the program must not lose,
        pass False.
        """
        if interruptible and interrupted:
            raise RuntimeError(f"Interrupted by {interrupted}")
        response = httpx.request(
            method, f"{cfg['base_url']}/api/v1{path}", timeout=30,
            headers={"Authorization": f"Bearer {cfg['token']}"}, **kwargs,
        )
        if response.is_error:
            raise RuntimeError(
                f"{method} {path} failed with status {response.status_code}: "
                f"{response.text.strip()}"
            )
        return response
    
    
    def create_blackout(cfg: dict) -> dict:
        """Creates a blackout for one monitored server and returns it.
    
        The blackout starts a minute ago, so that a small difference between
        the clocks of this machine and the server cannot leave it inactive,
        and it ends in one hour. The times are in RFC 3339 format.
        """
        now = datetime.now(timezone.utc)
        return api(cfg, "POST", "/blackouts", interruptible=False, json={
            "scope": "server",
            "connection_id": cfg["connection_id"],
            "reason": "Cookbook maintenance window",
            "start_time": (now - timedelta(minutes=1)).isoformat(),
            "end_time": (now + timedelta(hours=1)).isoformat(),
        }).json()
    
    
    def get_blackout(cfg: dict, blackout_id: int) -> dict:
        """Returns the blackout with the given ID."""
        return api(cfg, "GET", f"/blackouts/{blackout_id}").json()
    
    
    def stop_blackout(cfg: dict, blackout_id: int) -> dict:
        """Stops a blackout that is in progress, which sets its end time to
        now, and returns the stopped blackout."""
        return api(cfg, "POST", f"/blackouts/{blackout_id}/stop").json()
    
    
    def delete_blackout(cfg: dict, blackout_id: int) -> None:
        """Deletes a blackout by its ID."""
        api(cfg, "DELETE", f"/blackouts/{blackout_id}", interruptible=False)
    
    
    def main() -> int:
        cfg = None
        blackout_id = None
        status = 0
        signal.signal(signal.SIGINT, on_signal)
        signal.signal(signal.SIGTERM, on_signal)
        try:
            cfg = settings()
    
            created = create_blackout(cfg)
            blackout_id = created["id"]
            print("Created a blackout for the server "
                  f"(active: {str(created['is_active']).lower()})")
    
            blackout = get_blackout(cfg, blackout_id)
            print("Read the blackout back "
                  f"(active: {str(blackout['is_active']).lower()})")
    
            stopped = stop_blackout(cfg, blackout_id)
            print("Stopped the blackout "
                  f"(active: {str(stopped['is_active']).lower()})")
            if stopped["is_active"]:
                raise RuntimeError("The blackout is still active")
    
            delete_blackout(cfg, blackout_id)
            blackout_id = None
            print("Deleted the blackout")
        # httpx.HTTPError covers failures to connect, and RuntimeError covers
        # replies that the server rejected or that lacked what we need.
        except (httpx.HTTPError, RuntimeError) as e:
            print(f"Error: {e}", file=sys.stderr)
            status = 1
        finally:
            # Delete the blackout whether or not a later step failed, so that
            # a failed run does not leave alerts suppressed. A return statement
            # in a finally block would hide an exception that is still in
            # flight, so this block sets the exit status instead.
            if blackout_id is not None:
                try:
                    delete_blackout(cfg, blackout_id)
                except (httpx.HTTPError, RuntimeError) as e:
                    print(f"Error: could not delete the blackout: {e}",
                          file=sys.stderr)
                    status = 1
    
        return status
    
    
    if __name__ == "__main__":
        sys.exit(main())
    
    ```

=== "TypeScript"

    ```typescript
    /*
     * Ellie's Postgres Cookbook
     * Scheduling a maintenance blackout with the AI DBA Workbench API, using the
     * built-in fetch.
     *
     * Copyright (c) 2026, pgEdge, Inc.
     * This code is released under the PostgreSQL License.
     */
    
    // The program needs no imports: fetch and process are built in to Node.js.
    
    interface Settings {
      baseUrl: string;
      token: string;
      connectionId: number;
    }
    
    // Read the settings from the environment. The || operator, unlike ??, also
    // treats an empty variable as unset.
    function settings(): Settings {
      const token = process.env.WORKBENCH_TOKEN || "";
      const connectionId = process.env.WORKBENCH_CONNECTION_ID || "";
      if (!token || !connectionId) {
        throw new Error("WORKBENCH_TOKEN and WORKBENCH_CONNECTION_ID must be set");
      }
      if (!/^\d+$/.test(connectionId)) {
        throw new Error("WORKBENCH_CONNECTION_ID must be a number");
      }
      const baseUrl = process.env.WORKBENCH_URL || "http://localhost:8080";
      return {
        baseUrl: baseUrl.replace(/\/+$/, ""),
        token,
        connectionId: Number(connectionId),
      };
    }
    
    interface Blackout {
      id: number;
      is_active: boolean;
    }
    
    // Aborts the request in progress, and every later one that can be
    // interrupted, when the program receives SIGINT or SIGTERM. The handlers also
    // stop Node.js from exiting on those signals, which lets the cleanup run, and
    // a second signal during the cleanup does nothing.
    const interrupted = new AbortController();
    for (const name of ["SIGINT", "SIGTERM"] as const) {
      process.on(name, () => interrupted.abort(new Error(`Interrupted by ${name}`)));
    }
    
    // Sends a request to the API and returns the response. A request that the
    // server rejects throws an error that includes the message from the server.
    // The cleanup passes interruptible as false, so that a signal cannot cancel
    // it.
    async function api(
      s: Settings,
      method: string,
      path: string,
      body?: unknown,
      interruptible = true,
    ): Promise<Response> {
      const headers: Record<string, string> = {
        Authorization: `Bearer ${s.token}`,
      };
      if (body !== undefined) headers["Content-Type"] = "application/json";
    
      const response = await fetch(`${s.baseUrl}/api/v1${path}`, {
        method,
        headers,
        body: body === undefined ? undefined : JSON.stringify(body),
        signal: interruptible
          ? AbortSignal.any([AbortSignal.timeout(30_000), interrupted.signal])
          : AbortSignal.timeout(30_000),
      });
      if (!response.ok) {
        const text = (await response.text()).trim();
        throw new Error(
          `${method} ${path} failed with status ${response.status}: ${text}`,
        );
      }
      return response;
    }
    
    // Creates a blackout for one monitored server and returns it. The blackout
    // starts a minute ago, so that a small difference between the clocks of this
    // machine and the server cannot leave it inactive, and it ends in one hour.
    // The toISOString method writes the times in RFC 3339 format.
    async function createBlackout(s: Settings): Promise<Blackout> {
      const now = Date.now();
      // A signal cannot interrupt this request either, because the program
      // would not know the ID of a blackout that the server created after the
      // interruption. The next request notices the signal instead.
      const response = await api(
        s,
        "POST",
        "/blackouts",
        {
          scope: "server",
          connection_id: s.connectionId,
          reason: "Cookbook maintenance window",
          start_time: new Date(now - 60_000).toISOString(),
          end_time: new Date(now + 3_600_000).toISOString(),
        },
        false,
      );
      return (await response.json()) as Blackout;
    }
    
    // Returns the blackout with the given ID.
    async function getBlackout(s: Settings, id: number): Promise<Blackout> {
      const response = await api(s, "GET", `/blackouts/${id}`);
      return (await response.json()) as Blackout;
    }
    
    // Stops a blackout that is in progress, which sets its end time to now, and
    // returns the stopped blackout.
    async function stopBlackout(s: Settings, id: number): Promise<Blackout> {
      const response = await api(s, "POST", `/blackouts/${id}/stop`);
      return (await response.json()) as Blackout;
    }
    
    // Deletes a blackout by its ID. A signal cannot interrupt this request,
    // because it is the cleanup.
    async function deleteBlackout(s: Settings, id: number): Promise<void> {
      await api(s, "DELETE", `/blackouts/${id}`, undefined, false);
    }
    
    async function main(): Promise<number> {
      let exitCode = 0;
      let cleanup: (() => Promise<void>) | undefined;
      try {
        const s = settings();
    
        const created = await createBlackout(s);
        // Delete the blackout whether or not a later step fails, so that a
        // failed run does not leave alerts suppressed.
        cleanup = () => deleteBlackout(s, created.id);
        console.log(
          `Created a blackout for the server (active: ${created.is_active})`,
        );
    
        const blackout = await getBlackout(s, created.id);
        console.log(`Read the blackout back (active: ${blackout.is_active})`);
    
        const stopped = await stopBlackout(s, created.id);
        console.log(`Stopped the blackout (active: ${stopped.is_active})`);
        if (stopped.is_active) throw new Error("The blackout is still active");
    
        await cleanup();
        cleanup = undefined;
        console.log("Deleted the blackout");
      } catch (err) {
        console.error(`Error: ${err instanceof Error ? err.message : err}`);
        exitCode = 1;
      }
    
      if (cleanup) {
        try {
          await cleanup();
        } catch (err) {
          console.error(
            `Error: could not delete the blackout: ${
              err instanceof Error ? err.message : err
            }`,
          );
          exitCode = 1;
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
     * Scheduling a maintenance blackout with the AI DBA Workbench API, using
     * java.net.http and Jackson.
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
    import java.time.Duration;
    import java.time.Instant;
    import java.time.temporal.ChronoUnit;
    import java.util.Map;
    import java.util.Objects;
    import java.util.concurrent.CompletableFuture;
    import java.util.concurrent.ExecutionException;
    import java.util.concurrent.TimeUnit;
    import java.util.concurrent.TimeoutException;
    import tools.jackson.core.JacksonException;
    import tools.jackson.databind.JsonNode;
    import tools.jackson.databind.ObjectMapper;
    
    public class Main {
    
        /** The settings that the program reads from the environment. */
        record Settings(String baseUrl, String token, long connectionId) {}
    
        /**
         * Returns the value of an environment variable, or the fallback if the
         * variable is unset or empty, as an unset variable would be.
         */
        static String envOr(String name, String fallback) {
            String value = System.getenv(name);
            return (value != null && !value.isEmpty()) ? value : fallback;
        }
    
        /** Reads the settings from the environment. */
        static Settings settings() throws IOException {
            String token = envOr("WORKBENCH_TOKEN", "");
            String connectionId = envOr("WORKBENCH_CONNECTION_ID", "");
            if (token.isEmpty() || connectionId.isEmpty()) {
                throw new IOException(
                        "WORKBENCH_TOKEN and WORKBENCH_CONNECTION_ID must be set");
            }
            if (!connectionId.matches("[0-9]+")) {
                throw new IOException("WORKBENCH_CONNECTION_ID must be a number");
            }
            String baseUrl = envOr("WORKBENCH_URL", "http://localhost:8080")
                    .replaceAll("/+$", "");
            return new Settings(baseUrl, token, Long.parseLong(connectionId));
        }
    
        /** One client serves every request; it is safe to share. */
        static final HttpClient CLIENT = HttpClient.newBuilder()
                .connectTimeout(Duration.ofSeconds(30))
                .build();
    
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
    
        /** Converts between JSON text and Java objects. */
        static final ObjectMapper JSON = new ObjectMapper();
    
        /**
         * Sends a request to the API and returns the JSON reply, or null if the
         * reply has no body. The body may be null. A request that the server
         * rejects throws an error that includes the message from the server.
         */
        static JsonNode api(Settings cfg, String method, String path,
                Object body) throws IOException, InterruptedException {
            HttpRequest.Builder request = HttpRequest
                    .newBuilder(URI.create(cfg.baseUrl() + "/api/v1" + path))
                    .timeout(Duration.ofSeconds(30))
                    .header("Authorization", "Bearer " + cfg.token());
            HttpRequest.BodyPublisher content = HttpRequest.BodyPublishers.noBody();
            if (body != null) {
                request.header("Content-Type", "application/json");
                content = HttpRequest.BodyPublishers.ofString(
                        JSON.writeValueAsString(body));
            }
    
            HttpResponse<String> response = send(request.method(method, content).build());
            if (response.statusCode() >= 400) {
                throw new IOException(method + " " + path
                        + " failed with status " + response.statusCode() + ": "
                        + response.body().strip());
            }
            String text = response.body();
            return text.isEmpty() ? null : JSON.readTree(text);
        }
    
        /**
         * Creates a blackout for one monitored server and returns it. The
         * blackout starts a minute ago, so that a small difference between the
         * clocks of this machine and the server cannot leave it inactive, and
         * it ends in one hour. Instant.toString() writes the times in RFC 3339
         * format.
         */
        static JsonNode createBlackout(Settings cfg)
                throws IOException, InterruptedException {
            Instant now = Instant.now().truncatedTo(ChronoUnit.SECONDS);
            return api(cfg, "POST", "/blackouts", Map.of(
                    "scope", "server",
                    "connection_id", cfg.connectionId(),
                    "reason", "Cookbook maintenance window",
                    "start_time", now.minus(Duration.ofMinutes(1)).toString(),
                    "end_time", now.plus(Duration.ofHours(1)).toString()));
        }
    
        /** Returns the blackout with the given ID. */
        static JsonNode getBlackout(Settings cfg, long blackoutId)
                throws IOException, InterruptedException {
            return api(cfg, "GET", "/blackouts/" + blackoutId, null);
        }
    
        /**
         * Stops a blackout that is in progress, which sets its end time to now,
         * and returns the stopped blackout.
         */
        static JsonNode stopBlackout(Settings cfg, long blackoutId)
                throws IOException, InterruptedException {
            return api(cfg, "POST", "/blackouts/" + blackoutId + "/stop", null);
        }
    
        /** Deletes a blackout by its ID. */
        static void deleteBlackout(Settings cfg, long blackoutId)
                throws IOException, InterruptedException {
            api(cfg, "DELETE", "/blackouts/" + blackoutId, null);
        }
    
        /**
         * Guards the blackout that is still to be deleted, which the main
         * thread and the shutdown hook share.
         */
        static final Object LOCK = new Object();
        static Settings pendingCfg;
        static Long pendingId;
    
        /**
         * Returns the message of an error. Some errors, such as a refused
         * connection, have no message, so their type stands in for one.
         */
        static String describe(Exception e) {
            return Objects.requireNonNullElse(e.getMessage(), e.toString());
        }
    
        /**
         * Deletes the blackout if one is still pending, and returns false if
         * that fails. The main thread calls this after a failed step, and the
         * shutdown hook calls it when SIGINT or SIGTERM ends the program first.
         */
        static boolean cleanUp() {
            synchronized (LOCK) {
                if (pendingId == null) {
                    return true;
                }
                try {
                    deleteBlackout(pendingCfg, pendingId);
                    return true;
                } catch (IOException | InterruptedException | JacksonException e) {
                    System.err.println("Error: could not delete the blackout: "
                            + describe(e));
                    return false;
                } finally {
                    pendingId = null;
                }
            }
        }
    
        public static void main(String[] args) {
            // Java cannot catch a signal with its supported API, but SIGINT and
            // SIGTERM start an orderly shutdown that runs this hook, which
            // deletes the blackout before the program ends.
            Runtime.getRuntime().addShutdownHook(new Thread(Main::cleanUp));
    
            int status = 0;
            try {
                Settings cfg = settings();
    
                // Hold the lock until the ID is recorded, so that a signal
                // during the create call cannot leave the blackout behind.
                JsonNode created;
                long blackoutId;
                synchronized (LOCK) {
                    created = createBlackout(cfg);
                    blackoutId = created.get("id").asLong();
                    pendingCfg = cfg;
                    pendingId = blackoutId;
                }
                System.out.println("Created a blackout for the server (active: "
                        + created.get("is_active").asBoolean() + ")");
    
                JsonNode blackout = getBlackout(cfg, blackoutId);
                System.out.println("Read the blackout back (active: "
                        + blackout.get("is_active").asBoolean() + ")");
    
                JsonNode stopped = stopBlackout(cfg, blackoutId);
                boolean active = stopped.get("is_active").asBoolean();
                System.out.println("Stopped the blackout (active: " + active + ")");
                if (active) {
                    throw new IOException("The blackout is still active");
                }
    
                synchronized (LOCK) {
                    deleteBlackout(cfg, blackoutId);
                    pendingId = null;
                }
                System.out.println("Deleted the blackout");
            // IOException covers failures to connect, replies that the server
            // rejected, and replies that lacked what we need; the client
            // throws InterruptedException if the thread is interrupted, and
            // Jackson throws JacksonException for a reply that is not JSON.
            } catch (IOException | InterruptedException | JacksonException e) {
                System.err.println("Error: " + describe(e));
                status = 1;
            }
    
            // Delete the blackout whether or not a later step failed, so that a
            // failed run does not leave alerts suppressed.
            if (!cleanUp()) {
                status = 1;
            }
            System.exit(status);
        }
    }
    
    ```

=== "C#"

    ```csharp
    /*
     * Ellie's Postgres Cookbook
     * Scheduling a maintenance blackout with the AI DBA Workbench API, using
     * HttpClient and System.Text.Json.
     *
     * Copyright (c) 2026, pgEdge, Inc.
     * This code is released under the PostgreSQL License.
     */
    
    using System.Net.Http.Headers;
    using System.Net.Http.Json;
    using System.Runtime.InteropServices;
    using System.Text.Json;
    using System.Text.Json.Nodes;
    
    // Returns the value of an environment variable, or null if the variable
    // is unset or empty, as an unset variable would be.
    static string? EnvValue(string name) =>
        Environment.GetEnvironmentVariable(name) is { Length: > 0 } value
            ? value
            : null;
    
    // Reads the settings from the environment.
    static (string BaseUrl, string Token, long ConnectionId) Settings()
    {
        var token = EnvValue("WORKBENCH_TOKEN");
        var connectionId = EnvValue("WORKBENCH_CONNECTION_ID");
        if (token is null || connectionId is null)
        {
            throw new InvalidOperationException(
                "WORKBENCH_TOKEN and WORKBENCH_CONNECTION_ID must be set");
        }
        if (!connectionId.All(char.IsAsciiDigit))
        {
            throw new InvalidOperationException(
                "WORKBENCH_CONNECTION_ID must be a number");
        }
        var baseUrl = EnvValue("WORKBENCH_URL") ?? "http://localhost:8080";
        return (baseUrl.TrimEnd('/'), token, long.Parse(connectionId));
    }
    
    // The name of the signal that the program received, if any, and a token
    // that the signal cancels, which abandons the request in progress.
    string? interrupted = null;
    using var signalled = new CancellationTokenSource();
    
    // Catches SIGINT and SIGTERM. Setting Cancel stops the default action,
    // which would end the program before it could delete the blackout, and a
    // second signal does nothing more.
    void OnSignal(PosixSignalContext context)
    {
        context.Cancel = true;
        interrupted ??= context.Signal.ToString();
        signalled.Cancel();
    }
    using var onInt = PosixSignalRegistration.Create(PosixSignal.SIGINT, OnSignal);
    using var onTerm = PosixSignalRegistration.Create(PosixSignal.SIGTERM, OnSignal);
    
    // One client serves every request, with a timeout for each.
    var http = new HttpClient { Timeout = TimeSpan.FromSeconds(30) };
    var cfg = (BaseUrl: "", Token: "", ConnectionId: 0L);
    
    // Sends a request to the API and returns the JSON reply, or null if the
    // reply has no body. A request that the server rejects throws an error
    // that includes the message from the server. After a signal, every
    // request that is interruptible fails at once, and a signal abandons one
    // in progress; the cleanup and the create call, whose result the program
    // must not lose, pass false.
    async Task<JsonNode?> Api(string method, string path, bool interruptible,
        object? body = null)
    {
        var cancel = interruptible ? signalled.Token : CancellationToken.None;
        try
        {
            cancel.ThrowIfCancellationRequested();
            using var request = new HttpRequestMessage(
                new HttpMethod(method), $"{cfg.BaseUrl}/api/v1{path}");
            request.Headers.Authorization =
                new AuthenticationHeaderValue("Bearer", cfg.Token);
            if (body is not null)
            {
                request.Content = JsonContent.Create(body);
            }
    
            using var response = await http.SendAsync(request, cancel);
            var text = await response.Content.ReadAsStringAsync(cancel);
            if ((int)response.StatusCode >= 400)
            {
                throw new HttpRequestException(
                    $"{method} {path} failed with status {(int)response.StatusCode}: "
                    + text.Trim());
            }
            return text.Length == 0 ? null : JsonNode.Parse(text);
        }
        catch (OperationCanceledException) when (cancel.IsCancellationRequested)
        {
            throw new InvalidOperationException($"Interrupted by {interrupted}");
        }
    }
    
    // Creates a blackout for one monitored server and returns it. The blackout
    // starts a minute ago, so that a small difference between the clocks of
    // this machine and the server cannot leave it inactive, and it ends in one
    // hour. The "O" format writes the times in RFC 3339 format.
    async Task<JsonNode> CreateBlackout()
    {
        var now = DateTimeOffset.UtcNow;
        return await Api("POST", "/blackouts", false, new
        {
            scope = "server",
            connection_id = cfg.ConnectionId,
            reason = "Cookbook maintenance window",
            start_time = now.AddMinutes(-1).ToString("O"),
            end_time = now.AddHours(1).ToString("O"),
        }) ?? throw new InvalidOperationException("The reply had no blackout");
    }
    
    // Returns the blackout with the given ID.
    async Task<JsonNode> GetBlackout(long blackoutId) =>
        await Api("GET", $"/blackouts/{blackoutId}", true)
            ?? throw new InvalidOperationException("The reply had no blackout");
    
    // Stops a blackout that is in progress, which sets its end time to now,
    // and returns the stopped blackout.
    async Task<JsonNode> StopBlackout(long blackoutId) =>
        await Api("POST", $"/blackouts/{blackoutId}/stop", true)
            ?? throw new InvalidOperationException("The reply had no blackout");
    
    // Deletes a blackout by its ID.
    async Task DeleteBlackout(long blackoutId) =>
        await Api("DELETE", $"/blackouts/{blackoutId}", false);
    
    // Reports whether an error is one that the program expects: a failure to
    // connect, a reply that the server rejected, a request that timed out or
    // was interrupted, or a reply that lacked what we need.
    static bool Expected(Exception e) => e is HttpRequestException
        or TaskCanceledException or InvalidOperationException or JsonException;
    
    // Returns the is_active flag of a blackout, as the other languages print
    // it; C# would print True or False.
    static string Active(JsonNode blackout) =>
        blackout["is_active"]!.GetValue<bool>() ? "true" : "false";
    
    long? blackoutId = null;
    var status = 0;
    try
    {
        cfg = Settings();
    
        var created = await CreateBlackout();
        blackoutId = created["id"]!.GetValue<long>();
        Console.WriteLine(
            $"Created a blackout for the server (active: {Active(created)})");
    
        var blackout = await GetBlackout(blackoutId.Value);
        Console.WriteLine($"Read the blackout back (active: {Active(blackout)})");
    
        var stopped = await StopBlackout(blackoutId.Value);
        Console.WriteLine($"Stopped the blackout (active: {Active(stopped)})");
        if (stopped["is_active"]!.GetValue<bool>())
        {
            throw new InvalidOperationException("The blackout is still active");
        }
    
        await DeleteBlackout(blackoutId.Value);
        blackoutId = null;
        Console.WriteLine("Deleted the blackout");
    }
    catch (Exception e) when (Expected(e))
    {
        Console.Error.WriteLine($"Error: {e.Message}");
        status = 1;
    }
    finally
    {
        // Delete the blackout whether or not a later step failed, so that a failed
        // run does not leave alerts suppressed. The finally block also runs for an
        // error that the catch does not handle.
        if (blackoutId is long pending)
        {
            try
            {
                await DeleteBlackout(pending);
            }
            catch (Exception e) when (Expected(e))
            {
                Console.Error.WriteLine(
                    $"Error: could not delete the blackout: {e.Message}");
                status = 1;
            }
        }
    }
    
    return status;
    
    ```

=== "Go"

    ```go
    /*
     * Ellie's Postgres Cookbook
     * Scheduling a maintenance blackout with the AI DBA Workbench API, using
     * net/http.
     *
     * Copyright (c) 2026, pgEdge, Inc.
     * This code is released under the PostgreSQL License.
     */
    
    package main
    
    import (
    	"bytes"
    	"context"
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
    
    
    // settings holds the values that the program reads from the environment.
    type settings struct {
    	baseURL      string
    	token        string
    	connectionID int
    }
    
    // envOr returns the value of an environment variable, or the fallback if
    // the variable is unset or empty, as an unset variable would be.
    func envOr(name, fallback string) string {
    	if value := os.Getenv(name); value != "" {
    		return value
    	}
    	return fallback
    }
    
    // loadSettings reads the settings from the environment.
    func loadSettings() (settings, error) {
    	s := settings{
    		baseURL: strings.TrimRight(envOr("WORKBENCH_URL", "http://localhost:8080"), "/"),
    		token:   os.Getenv("WORKBENCH_TOKEN"),
    	}
    	id := os.Getenv("WORKBENCH_CONNECTION_ID")
    	if s.token == "" || id == "" {
    		return s, errors.New("WORKBENCH_TOKEN and WORKBENCH_CONNECTION_ID must be set")
    	}
    	var err error
    	if s.connectionID, err = strconv.Atoi(id); err != nil {
    		return s, fmt.Errorf("WORKBENCH_CONNECTION_ID must be a number: %w", err)
    	}
    	return s, nil
    }
    
    
    // client gives every request a timeout; the default client has none.
    var client = &http.Client{Timeout: 30 * time.Second}
    
    // blackout is the part of a blackout that the program needs.
    type blackout struct {
    	ID       int64 `json:"id"`
    	IsActive bool  `json:"is_active"`
    }
    
    // api sends a request to the API and decodes the JSON reply into out, if
    // given. A request that the server rejects returns an error that includes
    // the message from the server. Cancelling ctx, which the program does when it
    // receives SIGINT or SIGTERM, abandons the request.
    func api(ctx context.Context, s settings, method, path string, body, out any) error {
    	var reader io.Reader
    	if body != nil {
    		encoded, err := json.Marshal(body)
    		if err != nil {
    			return err
    		}
    		reader = bytes.NewReader(encoded)
    	}
    
    	req, err := http.NewRequestWithContext(ctx, method, s.baseURL+"/api/v1"+path, reader)
    	if err != nil {
    		return err
    	}
    	req.Header.Set("Authorization", "Bearer "+s.token)
    	if body != nil {
    		req.Header.Set("Content-Type", "application/json")
    	}
    
    	resp, err := client.Do(req)
    	if err != nil {
    		return err
    	}
    	defer resp.Body.Close()
    	if resp.StatusCode >= 400 {
    		text, _ := io.ReadAll(resp.Body)
    		return fmt.Errorf("%s %s failed with status %d: %s",
    			method, path, resp.StatusCode, strings.TrimSpace(string(text)))
    	}
    	if out == nil {
    		return nil
    	}
    	return json.NewDecoder(resp.Body).Decode(out)
    }
    
    
    // createBlackout creates a blackout for one monitored server and returns
    // it. The blackout starts a minute ago, so that a small difference between
    // the clocks of this machine and the server cannot leave it inactive, and
    // it ends in one hour. The times are in RFC 3339 format.
    //
    // A signal cannot interrupt this request, because the program would not
    // know the ID of a blackout that the server created after the interruption.
    func createBlackout(s settings) (blackout, error) {
    	now := time.Now().UTC()
    	var b blackout
    	err := api(context.Background(), s, "POST", "/blackouts", map[string]any{
    		"scope":         "server",
    		"connection_id": s.connectionID,
    		"reason":        "Cookbook maintenance window",
    		"start_time":    now.Add(-time.Minute).Format(time.RFC3339),
    		"end_time":      now.Add(time.Hour).Format(time.RFC3339),
    	}, &b)
    	return b, err
    }
    
    
    // getBlackout returns the blackout with the given ID.
    func getBlackout(ctx context.Context, s settings, id int64) (blackout, error) {
    	var b blackout
    	err := api(ctx, s, "GET", fmt.Sprintf("/blackouts/%d", id), nil, &b)
    	return b, err
    }
    
    
    // stopBlackout stops a blackout that is in progress, which sets its end
    // time to now, and returns the stopped blackout.
    func stopBlackout(ctx context.Context, s settings, id int64) (blackout, error) {
    	var b blackout
    	err := api(ctx, s, "POST", fmt.Sprintf("/blackouts/%d/stop", id), nil, &b)
    	return b, err
    }
    
    
    // deleteBlackout deletes a blackout by its ID. A signal cannot interrupt this
    // request, because it is the cleanup.
    func deleteBlackout(s settings, id int64) error {
    	return api(context.Background(), s, "DELETE", fmt.Sprintf("/blackouts/%d", id), nil, nil)
    }
    
    
    // run does the work. It returns the cleanup that the caller must run if the
    // program has created a blackout and not yet deleted it.
    func run(ctx context.Context, s settings) (cleanup func() error, err error) {
    	created, err := createBlackout(s)
    	if err != nil {
    		return nil, err
    	}
    	// Return the cleanup before any later step can fail, so that a failed
    	// run does not leave alerts suppressed.
    	cleanup = func() error { return deleteBlackout(s, created.ID) }
    	fmt.Printf("Created a blackout for the server (active: %t)\n", created.IsActive)
    
    	current, err := getBlackout(ctx, s, created.ID)
    	if err != nil {
    		return cleanup, err
    	}
    	fmt.Printf("Read the blackout back (active: %t)\n", current.IsActive)
    
    	stopped, err := stopBlackout(ctx, s, created.ID)
    	if err != nil {
    		return cleanup, err
    	}
    	fmt.Printf("Stopped the blackout (active: %t)\n", stopped.IsActive)
    	if stopped.IsActive {
    		return cleanup, errors.New("the blackout is still active")
    	}
    
    	// Report a failed delete here and clear the cleanup, so that main does not
    	// try again and print a second error.
    	if err := cleanup(); err != nil {
    		return nil, fmt.Errorf("could not delete the blackout: %w", err)
    	}
    	fmt.Println("Deleted the blackout")
    	return nil, nil
    }
    
    func main() {
    	s, err := loadSettings()
    	if err != nil {
    		fmt.Fprintln(os.Stderr, "Error:", err)
    		os.Exit(1)
    	}
    
    	// The handler replaces the default action for these signals, which would
    	// end the program before it could delete the blackout. It cancels ctx,
    	// which abandons the request in progress, and a second signal does
    	// nothing more.
    	ctx, stop := signal.NotifyContext(context.Background(),
    		os.Interrupt, syscall.SIGTERM)
    
    	failed := false
    	cleanup, err := run(ctx, s)
    	if err != nil {
    		fmt.Fprintln(os.Stderr, "Error:", err)
    		failed = true
    	}
    	if cleanup != nil {
    		if err := cleanup(); err != nil {
    			fmt.Fprintln(os.Stderr, "Error: could not delete the blackout:", err)
    			failed = true
    		}
    	}
    	stop()
    	if failed {
    		os.Exit(1)
    	}
    }
    
    
    ```

=== "Rust"

    ```rust
    // Ellie's Postgres Cookbook
    // Scheduling a maintenance blackout with the AI DBA Workbench API, using
    // reqwest and serde_json.
    //
    // Copyright (c) 2026, pgEdge, Inc.
    // This code is released under the PostgreSQL License.
    
    use std::env;
    use std::error::Error;
    use std::process::ExitCode;
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::sync::LazyLock;
    use std::time::{Duration, SystemTime};
    
    use humantime::format_rfc3339_seconds;
    use reqwest::blocking::Client;
    use reqwest::Method;
    use serde_json::{json, Value};
    use signal_hook::consts::{SIGINT, SIGTERM};
    
    /// Any error, boxed, so that a function can return errors of several types
    /// with the ? operator.
    type Result<T> = std::result::Result<T, Box<dyn Error>>;
    
    /// The settings that the program reads from the environment.
    struct Settings {
        base_url: String,
        token: String,
        connection_id: u64,
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
        // parse() alone would also accept a leading plus sign.
        if !connection_id.bytes().all(|b| b.is_ascii_digit()) {
            return Err("WORKBENCH_CONNECTION_ID must be a number".into());
        }
        let connection_id = connection_id.parse()?;
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
    
    /// The number of the SIGINT or SIGTERM signal that the program received,
    /// or 0 if it has received neither.
    static INTERRUPTED: AtomicUsize = AtomicUsize::new(0);
    
    /// Catches SIGINT and SIGTERM. The handler records the signal in
    /// INTERRUPTED and replaces the default action, which would end the
    /// program before it could delete the blackout, so a second signal does
    /// nothing more.
    fn catch_signals() -> Result<()> {
        for signal in [SIGINT, SIGTERM] {
            signal_hook::flag::register_usize(signal, &INTERRUPTED, signal as usize)?;
        }
        Ok(())
    }
    
    /// One client serves every request, with a timeout for each; the client
    /// has none by default.
    static CLIENT: LazyLock<Client> = LazyLock::new(|| {
        Client::builder()
            .timeout(Duration::from_secs(30))
            .build()
            .expect("could not create the HTTP client")
    });
    
    /// Sends a request to the API and returns the JSON reply, or null if the
    /// reply has no body. A request that the server rejects returns an error
    /// that includes the message from the server. After a signal, every
    /// request that is interruptible fails at once; the cleanup and the create
    /// call, whose result the program must not lose, pass false.
    fn api(
        cfg: &Settings,
        method: Method,
        path: &str,
        interruptible: bool,
        body: Option<&Value>,
    ) -> Result<Value> {
        if interruptible {
            match INTERRUPTED.load(Ordering::SeqCst) {
                0 => {}
                signal if signal == SIGINT as usize => return Err("interrupted by SIGINT".into()),
                _ => return Err("interrupted by SIGTERM".into()),
            }
        }
        let mut request = CLIENT
            .request(method.clone(), format!("{}/api/v1{path}", cfg.base_url))
            .bearer_auth(&cfg.token);
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
    
    /// Creates a blackout for one monitored server and returns it. The
    /// blackout starts a minute ago, so that a small difference between the
    /// clocks of this machine and the server cannot leave it inactive, and it
    /// ends in one hour. The times are in RFC 3339 format.
    fn create_blackout(cfg: &Settings) -> Result<Value> {
        let now = SystemTime::now();
        let body = json!({
            "scope": "server",
            "connection_id": cfg.connection_id,
            "reason": "Cookbook maintenance window",
            "start_time": format_rfc3339_seconds(now - Duration::from_secs(60)).to_string(),
            "end_time": format_rfc3339_seconds(now + Duration::from_secs(3600)).to_string(),
        });
        api(cfg, Method::POST, "/blackouts", false, Some(&body))
    }
    
    /// Returns the blackout with the given ID.
    fn get_blackout(cfg: &Settings, blackout_id: i64) -> Result<Value> {
        api(
            cfg,
            Method::GET,
            &format!("/blackouts/{blackout_id}"),
            true,
            None,
        )
    }
    
    /// Stops a blackout that is in progress, which sets its end time to now,
    /// and returns the stopped blackout.
    fn stop_blackout(cfg: &Settings, blackout_id: i64) -> Result<Value> {
        let path = format!("/blackouts/{blackout_id}/stop");
        api(cfg, Method::POST, &path, true, None)
    }
    
    /// Deletes a blackout by its ID.
    fn delete_blackout(cfg: &Settings, blackout_id: i64) -> Result<()> {
        let path = format!("/blackouts/{blackout_id}");
        api(cfg, Method::DELETE, &path, false, None)?;
        Ok(())
    }
    
    /// Returns the is_active flag of a blackout.
    fn is_active(blackout: &Value) -> Result<bool> {
        Ok(blackout["is_active"]
            .as_bool()
            .ok_or("the blackout had no active flag")?)
    }
    
    /// Does the work. Once it has created a blackout, it records the ID in
    /// cleanup, so that main deletes the blackout even if a later step fails.
    fn run(cfg: &Settings, cleanup: &mut Option<i64>) -> Result<()> {
        let created = create_blackout(cfg)?;
        let blackout_id = created["id"]
            .as_i64()
            .ok_or("the reply had no blackout ID")?;
        *cleanup = Some(blackout_id);
        println!(
            "Created a blackout for the server (active: {})",
            is_active(&created)?
        );
    
        let blackout = get_blackout(cfg, blackout_id)?;
        println!("Read the blackout back (active: {})", is_active(&blackout)?);
    
        let stopped = stop_blackout(cfg, blackout_id)?;
        let active = is_active(&stopped)?;
        println!("Stopped the blackout (active: {active})");
        if active {
            return Err("the blackout is still active".into());
        }
    
        delete_blackout(cfg, blackout_id)?;
        *cleanup = None;
        println!("Deleted the blackout");
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
        let cfg = match catch_signals().and_then(|()| settings()) {
            Ok(cfg) => cfg,
            Err(e) => {
                report("Error: ", e.as_ref());
                return ExitCode::FAILURE;
            }
        };
    
        let mut status = ExitCode::SUCCESS;
        let mut cleanup = None;
        if let Err(e) = run(&cfg, &mut cleanup) {
            report("Error: ", e.as_ref());
            status = ExitCode::FAILURE;
        }
    
        // Delete the blackout whether or not a later step failed, so that a
        // failed run does not leave alerts suppressed.
        if let Some(blackout_id) = cleanup {
            if let Err(e) = delete_blackout(&cfg, blackout_id) {
                report("Error: could not delete the blackout: ", e.as_ref());
                status = ExitCode::FAILURE;
            }
        }
        status
    }
    
    ```

=== "Ruby"

    ```ruby
    # Ellie's Postgres Cookbook
    # Scheduling a maintenance blackout with the AI DBA Workbench API, using
    # Net::HTTP.
    #
    # Copyright (c) 2026, pgEdge, Inc.
    # This code is released under the PostgreSQL License.
    
    require "json"
    require "net/http"
    require "time"
    
    # Returns the value of an environment variable, or a fallback if the
    # variable is unset or empty, as an unset variable would be.
    def env_or(name, fallback)
      value = ENV[name]
      value.nil? || value.empty? ? fallback : value
    end
    
    # Reads the settings from the environment.
    def settings
      token = env_or("WORKBENCH_TOKEN", nil)
      connection_id = env_or("WORKBENCH_CONNECTION_ID", nil)
      raise "WORKBENCH_TOKEN and WORKBENCH_CONNECTION_ID must be set" unless token && connection_id
      raise "WORKBENCH_CONNECTION_ID must be a number" unless connection_id.match?(/\A\d+\z/)
    
      {
        base_url: env_or("WORKBENCH_URL", "http://localhost:8080").sub(%r{/+\z}, ""),
        token: token,
        connection_id: Integer(connection_id, 10)
      }
    end
    
    # The name of the signal that the program received, if any.
    $interrupted = nil
    
    # Records that the program received SIGINT or SIGTERM. The handler replaces
    # the default action, which would end the program before it could delete
    # the blackout, and a second signal does nothing more.
    def catch_signals
      %w[INT TERM].each do |name|
        Signal.trap(name) { $interrupted = "SIG#{name}" }
      end
    end
    
    # Sends a request to the API and returns the decoded reply, or nil if the
    # reply has no body. A request that the server rejects raises an error that
    # includes the message from the server. After a signal, every request that
    # is interruptible fails at once; the cleanup and the create call, whose
    # result the program must not lose, pass false.
    def api(method, cfg, path, interruptible: true, body: nil)
      raise "Interrupted by #{$interrupted}" if interruptible && $interrupted
    
      uri = URI("#{cfg[:base_url]}/api/v1#{path}")
      headers = { "Authorization" => "Bearer #{cfg[:token]}" }
      headers["Content-Type"] = "application/json" if body
    
      # Net::HTTP has no overall timeout, so limit both the connection and
      # each read.
      response = Net::HTTP.start(uri.host, uri.port,
                                 use_ssl: uri.scheme == "https",
                                 open_timeout: 30, read_timeout: 30) do |http|
        http.send_request(method, uri.request_uri, body&.to_json, headers)
      end
      if response.code.to_i >= 400
        raise "#{method} #{path} failed with status #{response.code}: " \
              "#{response.body.to_s.strip}"
      end
      text = response.body.to_s
      text.empty? ? nil : JSON.parse(text)
    end
    
    # Creates a blackout for one monitored server and returns it. The blackout
    # starts a minute ago, so that a small difference between the clocks of
    # this machine and the server cannot leave it inactive, and it ends in one
    # hour. The times are in RFC 3339 format.
    def create_blackout(cfg)
      now = Time.now.utc
      api("POST", cfg, "/blackouts", interruptible: false, body: {
            scope: "server",
            connection_id: cfg[:connection_id],
            reason: "Cookbook maintenance window",
            start_time: (now - 60).iso8601,
            end_time: (now + 3600).iso8601
          })
    end
    
    # Returns the blackout with the given ID.
    def get_blackout(cfg, blackout_id)
      api("GET", cfg, "/blackouts/#{blackout_id}")
    end
    
    # Stops a blackout that is in progress, which sets its end time to now, and
    # returns the stopped blackout.
    def stop_blackout(cfg, blackout_id)
      api("POST", cfg, "/blackouts/#{blackout_id}/stop")
    end
    
    # Deletes a blackout by its ID.
    def delete_blackout(cfg, blackout_id)
      api("DELETE", cfg, "/blackouts/#{blackout_id}", interruptible: false)
    end
    
    def main
      cfg = nil
      blackout_id = nil
      status = 0
      catch_signals
      begin
        cfg = settings
    
        created = create_blackout(cfg)
        blackout_id = created.fetch("id")
        puts "Created a blackout for the server (active: #{created.fetch('is_active')})"
    
        blackout = get_blackout(cfg, blackout_id)
        puts "Read the blackout back (active: #{blackout.fetch('is_active')})"
    
        stopped = stop_blackout(cfg, blackout_id)
        puts "Stopped the blackout (active: #{stopped.fetch('is_active')})"
        raise "The blackout is still active" if stopped["is_active"]
    
        delete_blackout(cfg, blackout_id)
        blackout_id = nil
        puts "Deleted the blackout"
      # Net::HTTP raises errors of many classes, such as SystemCallError for a
      # refused connection and Net::OpenTimeout for a timeout, and the program
      # raises RuntimeError for replies that the server rejected or that lacked
      # what we need, so this catches StandardError, their common ancestor.
      rescue StandardError => e
        warn "Error: #{e.message}"
        status = 1
      ensure
        # Delete the blackout whether or not a later step failed, so that a
        # failed run does not leave alerts suppressed.
        if blackout_id
          begin
            delete_blackout(cfg, blackout_id)
          rescue StandardError => e
            warn "Error: could not delete the blackout: #{e.message}"
            status = 1
          end
        end
      end
      status
    end
    
    exit main
    
    ```

=== "curl"

    ```bash
    #!/usr/bin/env bash
    #
    # Ellie's Postgres Cookbook
    # Scheduling a maintenance blackout with the AI DBA Workbench API, using curl
    # and jq.
    #
    # Copyright (c) 2026, pgEdge, Inc.
    # This code is released under the PostgreSQL License.
    
    # Stop at the first failing command, treat an unset variable as an error,
    # and fail a pipeline when any command in it fails.
    set -euo pipefail
    
    # The script needs curl to make the requests and jq to build the request and
    # read the replies.
    for tool in curl jq; do
        command -v "$tool" >/dev/null || { echo "$tool is required" >&2; exit 1; }
    done
    
    # Read the settings from the environment. The :- and :? forms, unlike - and
    # ?, treat an empty variable as unset.
    WORKBENCH_URL="${WORKBENCH_URL:-http://localhost:8080}"
    WORKBENCH_URL="${WORKBENCH_URL%/}"
    : "${WORKBENCH_TOKEN:?WORKBENCH_TOKEN must be set}"
    : "${WORKBENCH_CONNECTION_ID:?WORKBENCH_CONNECTION_ID must be set}"
    
    # Sends an authenticated request and prints the JSON reply:
    # api METHOD PATH [curl options]. With --fail-with-body, a request that the
    # server rejects leaves the server's error message in the reply, and the
    # function prints it to standard error. A caller can set allow_status to an
    # HTTP status that the function should treat as success.
    # The token goes to curl in a header file that bash supplies through a pipe,
    # so that it never appears in the arguments of the curl process, which other
    # users can read in the process list.
    api() {
        local method="$1" path="$2"
        shift 2
        local output status response
        # With allow_status, curl stays quiet about the status that is allowed.
        local show_error=--show-error
        [[ -z "${allow_status:-}" ]] || show_error=--silent
        # The --write-out option appends the HTTP status on a line of its own.
        output=$(curl --silent "$show_error" --fail-with-body \
            --connect-timeout 10 --max-time 30 \
            --write-out '\n%{http_code}' \
            --request "$method" \
            --header @<(printf 'Authorization: Bearer %s\n' "$WORKBENCH_TOKEN") \
            "$@" "$WORKBENCH_URL/api/v1$path") && status=0 || status=$?
        response="${output%$'\n'*}"
        if [[ "$status" -ne 0 ]]; then
            if [[ -n "${allow_status:-}" && "${output##*$'\n'}" == "$allow_status" ]]
            then
                return 0
            fi
            echo "$method $path failed: ${response:-no reply (curl $status)}" >&2
            return 1
        fi
        printf '%s' "$response"
    }
    
    # Creates a blackout for one monitored server and prints the reply. The
    # reason ends with the unique marker, so that the cleanup can find the
    # blackout even if this script never sees the reply. The blackout starts a
    # minute ago, so that a small difference between the clocks of this machine and
    # the server cannot leave it inactive, and it ends in one hour. The times are
    # in RFC 3339 format, which jq builds from the current time.
    create_blackout() {
        local connection_id="$1" marker="$2"
        jq -n --argjson connection_id "$connection_id" --arg marker "$marker" \
            '{scope: "server", connection_id: $connection_id,
              reason: ("Cookbook maintenance window " + $marker),
              start_time: (now - 60 | todate),
              end_time: (now + 3600 | todate)}' |
            api POST /blackouts \
                --header 'Content-Type: application/json' --data @-
    }
    
    # Prints the blackout with the given ID.
    get_blackout() {
        api GET "/blackouts/$1"
    }
    
    # Stops a blackout that is in progress, which sets its end time to now, and
    # prints the stopped blackout.
    stop_blackout() {
        api POST "/blackouts/$1/stop"
    }
    
    # Deletes a blackout by its ID. A 404 status means that the blackout is
    # already gone, which is what the caller wanted, so it counts as success.
    delete_blackout() {
        allow_status=404 api DELETE "/blackouts/$1" >/dev/null
    }
    
    # Prints the IDs of the blackouts whose reason contains the marker.
    find_blackouts() {
        api GET /blackouts |
            jq -r --arg marker "$1" \
                '.blackouts[] | select(.reason | contains($marker)) | .id'
    }
    
    # These variables are global, because the EXIT trap runs after main returns.
    # The marker is set before the create call and cleared once the blackout is
    # deleted, so a non-empty marker means that the outcome of the create call is
    # unknown, or that its blackout still exists. The created variable holds the
    # reply to the create call, which bash assigns before it runs a signal
    # handler, whereas it would not yet have extracted the ID from the reply.
    marker=""
    created=""
    
    cleanup() {
        local status=$?
        # Ignore further signals, so that a second one cannot abort the delete.
        trap '' INT TERM
        # Delete the blackout when the script ends, even if a later step failed,
        # so that a failed run does not leave alerts suppressed. Report a delete
        # that fails, and make the exit status non-zero.
        local id ids=""
        if [[ -n "$created" ]]; then
            ids=$(jq -er '.id' <<<"$created") || ids=""
        fi
        if [[ -z "$ids" && -n "$marker" ]]; then
            # Ctrl+C in a terminal sends SIGINT to every process in the
            # foreground group, which includes curl, so the create call can end
            # without a reply even though the server created the blackout. Look
            # for the blackout by its marker. The server may still be handling
            # the request, so look up to three times, a second apart.
            local attempt
            for attempt in 1 2 3; do
                ids=$(find_blackouts "$marker") || {
                    echo "Error: could not look up the blackout" >&2
                    status=1
                    break
                }
                if [[ -n "$ids" ]]; then
                    break
                fi
                if [[ "$attempt" -lt 3 ]]; then
                    sleep 1
                fi
            done
        fi
        for id in $ids; do
            delete_blackout "$id" || {
                echo "Error: could not delete the blackout $id" >&2
                status=1
            }
        done
        exit "$status"
    }
    
    main() {
        local blackout_id blackout stopped active
        marker="cookbook-$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')"
        created=$(create_blackout "$WORKBENCH_CONNECTION_ID" "$marker")
        blackout_id=$(jq -er '.id' <<<"$created")
        active=$(jq -r '.is_active' <<<"$created")
        echo "Created a blackout for the server (active: $active)"
    
        blackout=$(get_blackout "$blackout_id")
        active=$(jq -r '.is_active' <<<"$blackout")
        echo "Read the blackout back (active: $active)"
    
        stopped=$(stop_blackout "$blackout_id")
        active=$(jq -r '.is_active' <<<"$stopped")
        echo "Stopped the blackout (active: $active)"
        if [[ "$active" != "false" ]]; then
            echo "The blackout is still active" >&2
            return 1
        fi
    
        delete_blackout "$blackout_id"
        created=""
        marker=""
        echo "Deleted the blackout"
    }
    
    # Without handlers for the signals, a second signal that arrives before bash
    # has run the EXIT trap would end the script before the delete. The handlers
    # exit with the usual status for a signal (128 plus the signal number), which
    # runs the EXIT trap.
    trap cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    main
    
    ```

## Next Steps

The following resources provide more information about the topics in this
recipe:

- The [Authenticating with the AI DBA Workbench API](authenticate.md) recipe
  explains how to create the API token that these examples use.
- The
  [Listing and Acknowledging Alerts with the AI DBA Workbench API](alerts.md)
  recipe shows the alerts that a blackout suppresses.
- The AI DBA Workbench
  [blackouts guide](https://github.com/pgEdge/ai-dba-workbench/blob/v1.0.0/docs/user-guide/blackouts.md)
  describes how blackouts affect alerting.
- The AI DBA Workbench
  [API reference](https://github.com/pgEdge/ai-dba-workbench/blob/v1.0.0/docs/admin-guide/api/reference.md)
  describes every endpoint.
