# Listing and Acknowledging Alerts with the AI DBA Workbench API

This recipe shows how a program makes a Workbench alert fire on demand, finds
the alert in the list of active alerts, acknowledges it, and then undoes its
changes. These examples are for AI DBA Workbench 1.0.0. Each step shows the
code in every supported language; selecting a language tab switches every tab
on the site to that language.

!!! warning

    The example raises a real alert. A Workbench that has notification
    channels configured (email, Slack, or webhooks, for example) sends a
    notification when the alert fires and another when it clears, and those
    messages reach real people. Run the example against a test Workbench,
    or against a server that has no notification channels or that is in a
    blackout.

An alert normally fires only when something goes wrong with a monitored server,
so the example forces one. The `metric_staleness` rule raises an alert when a
probe's data is out of date, and a threshold override for one server lowers the
threshold of that rule to -1, which no value can satisfy. The alerter then
raises the alert the next time it evaluates its rules. The program waits for
the alert, acknowledges it, confirms that the alert is acknowledged, and then
undoes its changes. The output has the following form:

```text
Found the rule 'metric_staleness'
Set an override that makes the rule fire
Waiting for the alerter to raise an alert
An alert is active (severity: info)
Acknowledged the alert
The alert is now acknowledged
Returned the alert to the active state
Removed the override
```

The alerter evaluates its rules once a minute, so the example normally takes
between a few seconds and a minute and a half to run, and gives up after 150
seconds. When the program finishes, the alert stays active for up to 30 seconds
more, until the alerter's clean-up pass clears it, and the cleared alert
remains in the alert history afterwards. The program waits for a previous alert
from the same rule to clear before it starts, so running the example twice in
succession is safe, but it can add up to 30 seconds to the second run.

## Preparing the Ingredients

The `scripts/start_workbench.sh` script in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook)
starts a test Workbench in Docker. The script creates a `cookbook` user and an
API token, registers a test PostgreSQL server as a monitored connection, and
prints the `WORKBENCH_URL`, `WORKBENCH_TOKEN`, `WORKBENCH_USERNAME`,
`WORKBENCH_PASSWORD`, and `WORKBENCH_CONNECTION_ID` values that the examples
read from the environment.

The examples need a running Workbench server that monitors at least one
PostgreSQL server, and an API token for a user that can change alert overrides
and acknowledge alerts. The following table lists the HTTP client and the JSON
library that each example uses:

| Language   | HTTP client and JSON library                                   |
|------------|----------------------------------------------------------------|
| Python     | [httpx](https://www.python-httpx.org/) and the `json` module   |
| TypeScript | The `fetch` function that Node.js provides                     |
| Java       | The `java.net.http` client and [Jackson](https://github.com/FasterXML/jackson) |
| C#         | `HttpClient` and `System.Text.Json`, which are part of .NET    |
| Go         | The `net/http` and `encoding/json` standard library packages   |
| Rust       | [reqwest](https://docs.rs/reqwest) and [serde_json](https://docs.rs/serde_json) |
| Ruby       | `Net::HTTP` and `json`, which come with Ruby                   |

The curl example is a bash script that uses [jq](https://jqlang.org/) to read
the JSON replies. The following tabs show the dependency declaration from each
example project:

=== "Python"

    ```text
    # httpx, an HTTP client with a requests-like interface.
    httpx>=0.28,<1
    ```

=== "TypeScript"

    ```json
    {
      "name": "alerts",
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
    import sys
    import time
    
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
    import java.net.URLEncoder;
    import java.net.http.HttpClient;
    import java.net.http.HttpRequest;
    import java.net.http.HttpResponse;
    import java.net.http.HttpTimeoutException;
    import java.nio.charset.StandardCharsets;
    import java.time.Duration;
    import java.util.ArrayList;
    import java.util.LinkedHashMap;
    import java.util.List;
    import java.util.Map;
    import java.util.Objects;
    import java.util.concurrent.CompletableFuture;
    import java.util.concurrent.ExecutionException;
    import java.util.concurrent.TimeUnit;
    import java.util.concurrent.TimeoutException;
    import java.util.stream.Collectors;
    import tools.jackson.core.JacksonException;
    import tools.jackson.databind.JsonNode;
    import tools.jackson.databind.ObjectMapper;
    ```

=== "C#"

    ```csharp
    using System.Diagnostics;
    using System.Net.Http.Headers;
    using System.Net.Http.Json;
    using System.Text.Json;
    using System.Text.Json.Nodes;
    ```

=== "Go"

    ```go
    import (
    	"bytes"
    	"encoding/json"
    	"errors"
    	"fmt"
    	"io"
    	"net/http"
    	"net/url"
    	"os"
    	"strings"
    	"time"
    )
    
    ```

=== "Rust"

    ```rust
    use std::env;
    use std::error::Error;
    use std::process::ExitCode;
    use std::sync::LazyLock;
    use std::thread;
    use std::time::{Duration, Instant};
    
    use reqwest::blocking::Client;
    use reqwest::{Method, Url};
    use serde_json::{json, Value};
    ```

=== "Ruby"

    ```ruby
    require "json"
    require "net/http"
    ```

=== "curl"

    ```bash
    # Stop at the first failing command, treat an unset variable as an error,
    # and fail a pipeline when any command in it fails.
    set -euo pipefail
    
    # The script needs curl to make the requests and jq to read the replies.
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
| `WORKBENCH_CONNECTION_ID` | The ID of the server to raise the alert on.   |

The Authenticating recipe shows how to create an API token. The examples also
set the name of the rule and the longest time to wait for the alert. The
following tabs show how each program reads the settings and stops with an error
when the token or the connection ID is missing:

=== "Python"

    ```python
    # The rule that the program makes fire. The metric_staleness rule alerts when
    # a probe's data is out of date, and the alerter checks it every minute.
    RULE_NAME = "metric_staleness"
    
    # The longest the whole run waits for alerts, in seconds. The alerter
    # evaluates its rules once a minute and clears an alert up to 30 seconds
    # after it fires, so this allows for waiting out the alert from an earlier
    # run, one alert that clears before the program can acknowledge it, and a
    # second evaluation.
    WAIT_SECONDS = 150
    
    # How often the program polls the alerts, in seconds.
    POLL_SECONDS = 0.5
    
    
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
        return {
            "base_url": (
                os.environ.get("WORKBENCH_URL") or "http://localhost:8080"
            ).rstrip("/"),
            "token": token,
            "connection_id": connection_id,
        }
    ```

=== "TypeScript"

    ```typescript
    // The rule that the program makes fire. The metric_staleness rule alerts when
    // a probe's data is out of date, and the alerter checks it every minute.
    const RULE_NAME = "metric_staleness";
    
    // The longest the whole run waits for alerts, in milliseconds. The alerter
    // evaluates its rules once a minute and clears an alert up to 30 seconds
    // after it fires, so this allows for waiting out the alert from an earlier
    // run, one alert that clears before the program can acknowledge it, and a
    // second evaluation.
    const WAIT_MS = 150_000;
    
    // How often the program polls the alerts, in milliseconds.
    const POLL_MS = 500;
    
    interface Settings {
      baseUrl: string;
      token: string;
      connectionId: string;
    }
    
    // Read the settings from the environment. The || operator, unlike ??, also
    // treats an empty variable as unset.
    function settings(): Settings {
      const token = process.env.WORKBENCH_TOKEN || "";
      const connectionId = process.env.WORKBENCH_CONNECTION_ID || "";
      if (!token || !connectionId) {
        throw new Error("WORKBENCH_TOKEN and WORKBENCH_CONNECTION_ID must be set");
      }
      const baseUrl = process.env.WORKBENCH_URL || "http://localhost:8080";
      return { baseUrl: baseUrl.replace(/\/+$/, ""), token, connectionId };
    }
    ```

=== "Java"

    ```java
    /**
     * The rule that the program makes fire. The metric_staleness rule
     * alerts when a probe's data is out of date, and the alerter checks it
     * every minute.
     */
    static final String RULE_NAME = "metric_staleness";
    
    /**
     * The longest the whole run waits for alerts. The alerter evaluates its
     * rules once a minute and clears an alert up to 30 seconds after it
     * fires, so this allows for waiting out the alert from an earlier run,
     * one alert that clears before the program can acknowledge it, and a
     * second evaluation.
     */
    static final Duration WAIT_TIME = Duration.ofSeconds(150);
    
    /** How often the program polls the alerts. */
    static final Duration POLL_INTERVAL = Duration.ofMillis(500);
    
    /** The settings that the program reads from the environment. */
    record Settings(String baseUrl, String token, String connectionId) {}
    
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
        String baseUrl = envOr("WORKBENCH_URL", "http://localhost:8080")
                .replaceAll("/+$", "");
        return new Settings(baseUrl, token, connectionId);
    }
    ```

=== "C#"

    ```csharp
    // The rule that the program makes fire. The metric_staleness rule alerts
    // when a probe's data is out of date, and the alerter checks it every
    // minute.
    const string RuleName = "metric_staleness";
    
    // The longest the whole run waits for alerts. The alerter evaluates its
    // rules once a minute and clears an alert up to 30 seconds after it fires,
    // so this allows for waiting out the alert from an earlier run, one alert
    // that clears before the program can acknowledge it, and a second
    // evaluation.
    var waitTime = TimeSpan.FromSeconds(150);
    
    // How often the program polls the alerts.
    var pollInterval = TimeSpan.FromMilliseconds(500);
    
    // Returns the value of an environment variable, or null if the variable
    // is unset or empty, as an unset variable would be.
    static string? EnvValue(string name) =>
        Environment.GetEnvironmentVariable(name) is { Length: > 0 } value
            ? value
            : null;
    
    // Reads the settings from the environment.
    static (string BaseUrl, string Token, string ConnectionId) Settings()
    {
        var token = EnvValue("WORKBENCH_TOKEN");
        var connectionId = EnvValue("WORKBENCH_CONNECTION_ID");
        if (token is null || connectionId is null)
        {
            throw new InvalidOperationException(
                "WORKBENCH_TOKEN and WORKBENCH_CONNECTION_ID must be set");
        }
        var baseUrl = EnvValue("WORKBENCH_URL") ?? "http://localhost:8080";
        return (baseUrl.TrimEnd('/'), token, connectionId);
    }
    ```

=== "Go"

    ```go
    // ruleName is the rule that the program makes fire. The metric_staleness
    // rule alerts when a probe's data is out of date, and the alerter checks it
    // every minute.
    const ruleName = "metric_staleness"
    
    // waitTime is the longest the whole run waits for alerts. The alerter
    // evaluates its rules once a minute and clears an alert up to 30 seconds
    // after it fires, so this allows for waiting out the alert from an earlier
    // run, one alert that clears before the program can acknowledge it, and a
    // second evaluation.
    const waitTime = 150 * time.Second
    
    // pollTime is how often the program polls the alerts.
    const pollTime = 500 * time.Millisecond
    
    // settings holds the values that the program reads from the environment.
    type settings struct {
    	baseURL      string
    	token        string
    	connectionID string
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
    		baseURL:      strings.TrimRight(envOr("WORKBENCH_URL", "http://localhost:8080"), "/"),
    		token:        os.Getenv("WORKBENCH_TOKEN"),
    		connectionID: os.Getenv("WORKBENCH_CONNECTION_ID"),
    	}
    	if s.token == "" || s.connectionID == "" {
    		return s, errors.New("WORKBENCH_TOKEN and WORKBENCH_CONNECTION_ID must be set")
    	}
    	return s, nil
    }
    
    ```

=== "Rust"

    ```rust
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
    ```

=== "Ruby"

    ```ruby
    # The rule that the program makes fire. The metric_staleness rule alerts
    # when a probe's data is out of date, and the alerter checks it every
    # minute.
    RULE_NAME = "metric_staleness"
    
    # The longest the whole run waits for alerts, in seconds. The alerter
    # evaluates its rules once a minute and clears an alert up to 30 seconds
    # after it fires, so this allows for waiting out the alert from an earlier
    # run, one alert that clears before the program can acknowledge it, and a
    # second evaluation.
    WAIT_SECONDS = 150
    
    # How often the program polls the alerts, in seconds.
    POLL_SECONDS = 0.5
    
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
    
      {
        base_url: env_or("WORKBENCH_URL", "http://localhost:8080").sub(%r{/+\z}, ""),
        token: token,
        connection_id: connection_id
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
    
    # The rule that the script makes fire. The metric_staleness rule alerts when
    # a probe's data is out of date, and the alerter checks it every minute.
    RULE_NAME="metric_staleness"
    # The longest the whole run waits for alerts, in seconds. The alerter
    # evaluates its rules once a minute and clears an alert up to 30 seconds
    # after it fires, so this allows for waiting out the alert from an earlier
    # run, one alert that clears before the script can acknowledge it, and a
    # second evaluation.
    WAIT_SECONDS=150
    # How often the script polls the alerts, in seconds.
    POLL_SECONDS=0.5
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
    def api(method: str, cfg: dict, path: str, **kwargs) -> httpx.Response:
        """Sends a request to the API and returns the response.
    
        A request that the server rejects raises an error that includes the
        message from the server, which raise_for_status alone would leave out.
        """
        response = httpx.request(
            method, f"{cfg['base_url']}/api/v1{path}",
            headers={"Authorization": f"Bearer {cfg['token']}"}, timeout=30,
            **kwargs,
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
    // Sends a request to the API and returns the response. A request that the
    // server rejects throws an error that includes the message from the server.
    async function api(
      method: string,
      cfg: Settings,
      path: string,
      body?: unknown,
    ): Promise<Response> {
      const headers: Record<string, string> = {
        Authorization: `Bearer ${cfg.token}`,
      };
      if (body !== undefined) headers["Content-Type"] = "application/json";
    
      const response = await fetch(`${cfg.baseUrl}/api/v1${path}`, {
        method,
        headers,
        body: body === undefined ? undefined : JSON.stringify(body),
        signal: AbortSignal.timeout(30_000),
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
     * Sends a request to the API and returns the JSON reply. The query
     * parameters and the body may be null. A request that the server
     * rejects throws an error that includes the message from the server.
     */
    static JsonNode api(String method, Settings cfg, String path,
            Map<String, String> params, Object body)
            throws IOException, InterruptedException {
        String url = cfg.baseUrl() + "/api/v1" + path;
        if (params != null) {
            url += "?" + params.entrySet().stream()
                    .map(p -> URLEncoder.encode(p.getKey(),
                            StandardCharsets.UTF_8) + "="
                            + URLEncoder.encode(p.getValue(),
                                    StandardCharsets.UTF_8))
                    .collect(Collectors.joining("&"));
        }
        HttpRequest.Builder request = HttpRequest.newBuilder(URI.create(url))
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
        // Some replies have no body, which reads as a missing node.
        return JSON.readTree(response.body());
    }
    ```

=== "C#"

    ```csharp
    // One client serves every request, with a timeout for each.
    var http = new HttpClient { Timeout = TimeSpan.FromSeconds(30) };
    var cfg = (BaseUrl: "", Token: "", ConnectionId: "");
    
    // Sends a request to the API and returns the JSON reply, or null if the
    // reply has no body. The path may include a query string. A request that
    // the server rejects throws an error that includes the message from the
    // server.
    async Task<JsonNode?> Api(string method, string path, object? body = null)
    {
        using var request = new HttpRequestMessage(
            new HttpMethod(method), $"{cfg.BaseUrl}/api/v1{path}");
        request.Headers.Authorization =
            new AuthenticationHeaderValue("Bearer", cfg.Token);
        if (body is not null)
        {
            request.Content = JsonContent.Create(body);
        }
    
        using var response = await http.SendAsync(request);
        var text = await response.Content.ReadAsStringAsync();
        if ((int)response.StatusCode >= 400)
        {
            throw new HttpRequestException(
                $"{method} {path} failed with status {(int)response.StatusCode}: "
                + text.Trim());
        }
        return text.Length == 0 ? null : JsonNode.Parse(text);
    }
    ```

=== "Go"

    ```go
    // client gives every request a timeout; the default client has none.
    var client = &http.Client{Timeout: 30 * time.Second}
    
    // api sends a request to the API and decodes the JSON reply into out, if
    // given. A request that the server rejects returns an error that includes
    // the message from the server.
    func api(s settings, method, path string, body, out any) error {
    	var reader io.Reader
    	if body != nil {
    		encoded, err := json.Marshal(body)
    		if err != nil {
    			return err
    		}
    		reader = bytes.NewReader(encoded)
    	}
    
    	req, err := http.NewRequest(method, s.baseURL+"/api/v1"+path, reader)
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
    ```

=== "Ruby"

    ```ruby
    # Sends a request to the API and returns the decoded reply, or nil if the
    # reply has no body. The query parameters and the body are optional. A
    # request that the server rejects raises an error that includes the
    # message from the server.
    def api(method, cfg, path, params: nil, body: nil)
      uri = URI("#{cfg[:base_url]}/api/v1#{path}")
      uri.query = URI.encode_www_form(params) if params
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
    # function prints it to standard error. The token goes to curl in a header
    # file that bash supplies through a pipe, so that it never appears in the
    # arguments of the curl process, which other users can read in the process
    # list.
    api() {
        local method="$1" path="$2"
        shift 2
        local response
        response=$(curl --silent --show-error --fail-with-body \
            --connect-timeout 10 --max-time 30 \
            --request "$method" \
            --header @<(printf 'Authorization: Bearer %s\n' "$WORKBENCH_TOKEN") \
            "$@" "$WORKBENCH_URL/api/v1$path") || {
            echo "$method $path failed: $response" >&2
            return 1
        }
        printf '%s' "$response"
    }
    ```

## Finding the Rule

Each alert rule has a numeric ID, which the override calls need. The program
lists the rules with `GET /api/v1/alert-rules`, and picks the one whose name is
`metric_staleness`. By default this rule fires when the staleness ratio of a
probe, which is the age of its newest data divided by its collection interval,
exceeds 3. The following tabs show how each program finds the rule:

=== "Python"

    ```python
    def find_rule(cfg: dict, name: str) -> int:
        """Returns the ID of an alert rule, given its name."""
        for rule in api("GET", cfg, "/alert-rules").json():
            if rule["name"] == name:
                return rule["id"]
        raise RuntimeError(f"There is no alert rule named '{name}'")
    ```

=== "TypeScript"

    ```typescript
    interface Rule {
      id: number;
      name: string;
    }
    
    // Returns the ID of an alert rule, given its name.
    async function findRule(cfg: Settings, name: string): Promise<number> {
      const rules = (await (await api("GET", cfg, "/alert-rules")).json()) as Rule[];
      const rule = rules.find((r) => r.name === name);
      if (!rule) throw new Error(`There is no alert rule named '${name}'`);
      return rule.id;
    }
    ```

=== "Java"

    ```java
    /** Returns the ID of an alert rule, given its name. */
    static long findRule(Settings cfg, String name)
            throws IOException, InterruptedException {
        for (JsonNode rule : api("GET", cfg, "/alert-rules", null, null)) {
            if (name.equals(rule.path("name").asString())) {
                return rule.get("id").asLong();
            }
        }
        throw new IOException("There is no alert rule named '" + name + "'");
    }
    ```

=== "C#"

    ```csharp
    // Returns the ID of an alert rule, given its name.
    async Task<long> FindRule(string name)
    {
        var rules = (await Api("GET", "/alert-rules"))?.AsArray()
            ?? throw new InvalidOperationException("The reply had no rules");
        var rule = rules.FirstOrDefault(
            r => r?["name"]?.GetValue<string>() == name)
            ?? throw new InvalidOperationException(
                $"There is no alert rule named '{name}'");
        return rule["id"]!.GetValue<long>();
    }
    ```

=== "Go"

    ```go
    // findRule returns the ID of an alert rule, given its name.
    func findRule(s settings, name string) (int64, error) {
    	var rules []struct {
    		ID   int64  `json:"id"`
    		Name string `json:"name"`
    	}
    	if err := api(s, "GET", "/alert-rules", nil, &rules); err != nil {
    		return 0, err
    	}
    	for _, rule := range rules {
    		if rule.Name == name {
    			return rule.ID, nil
    		}
    	}
    	return 0, fmt.Errorf("there is no alert rule named '%s'", name)
    }
    
    ```

=== "Rust"

    ```rust
    /// Returns the ID of an alert rule, given its name.
    fn find_rule(cfg: &Settings, name: &str) -> Result<i64> {
        let rules = api(Method::GET, cfg, "/alert-rules", &[], None)?;
        rules
            .as_array()
            .and_then(|rules| rules.iter().find(|r| r["name"] == name))
            .and_then(|rule| rule["id"].as_i64())
            .ok_or_else(|| format!("there is no alert rule named '{name}'").into())
    }
    ```

=== "Ruby"

    ```ruby
    # Returns the ID of an alert rule, given its name.
    def find_rule(cfg, name)
      rule = api("GET", cfg, "/alert-rules").find { |r| r["name"] == name }
      raise "There is no alert rule named '#{name}'" if rule.nil?
    
      rule.fetch("id")
    end
    ```

=== "curl"

    ```bash
    # Prints the ID of an alert rule, given its name. The function fails when
    # there is no such rule, because jq prints nothing for it.
    find_rule() {
        local name="$1" id
        id=$(api GET /alert-rules |
            jq -r --arg name "$name" 'first(.[] | select(.name == $name)) | .id')
        if [[ -z "$id" ]]; then
            echo "There is no alert rule named '$name'" >&2
            return 1
        fi
        printf '%s' "$id"
    }
    ```

## Setting an Override

An override changes the threshold of a rule for one scope. The program sends
`PUT /api/v1/alert-overrides/server/{connection_id}/{rule_id}` with the
operator, the threshold, the severity, and whether the rule is enabled. A
threshold of -1 with the `>` operator is true for every ratio, because the
ratio is never negative, so the rule fires on the next evaluation. The
following tabs show how each program sets the override:

=== "Python"

    ```python
    def set_override(cfg: dict, rule_id: int) -> None:
        """Overrides the threshold of a rule for one server.
    
        A threshold of -1 is below any value that the staleness ratio can
        take, so the rule is violated on the next evaluation.
        """
        api("PUT", cfg,
            f"/alert-overrides/server/{cfg['connection_id']}/{rule_id}",
            json={"operator": ">", "threshold": -1, "severity": "info",
                  "enabled": True})
    ```

=== "TypeScript"

    ```typescript
    // Overrides the threshold of a rule for one server. A threshold of -1 is
    // below any value that the staleness ratio can take, so the rule is violated
    // on the next evaluation.
    async function setOverride(cfg: Settings, ruleId: number): Promise<void> {
      await api(
        "PUT",
        cfg,
        `/alert-overrides/server/${cfg.connectionId}/${ruleId}`,
        { operator: ">", threshold: -1, severity: "info", enabled: true },
      );
    }
    ```

=== "Java"

    ```java
    /**
     * Overrides the threshold of a rule for one server. A threshold of -1
     * is below any value that the staleness ratio can take, so the rule is
     * violated on the next evaluation.
     */
    static void setOverride(Settings cfg, long ruleId)
            throws IOException, InterruptedException {
        api("PUT", cfg, "/alert-overrides/server/" + cfg.connectionId()
                + "/" + ruleId, null, Map.of(
                        "operator", ">",
                        "threshold", -1,
                        "severity", "info",
                        "enabled", true));
    }
    ```

=== "C#"

    ```csharp
    // Overrides the threshold of a rule for one server. A threshold of -1 is
    // below any value that the staleness ratio can take, so the rule is
    // violated on the next evaluation.
    async Task SetOverride(long ruleId) =>
        await Api("PUT", $"/alert-overrides/server/{cfg.ConnectionId}/{ruleId}",
            new { @operator = ">", threshold = -1, severity = "info",
                enabled = true });
    ```

=== "Go"

    ```go
    // setOverride overrides the threshold of a rule for one server. A threshold
    // of -1 is below any value that the staleness ratio can take, so the rule is
    // violated on the next evaluation.
    func setOverride(s settings, ruleID int64) error {
    	path := fmt.Sprintf("/alert-overrides/server/%s/%d", s.connectionID, ruleID)
    	return api(s, "PUT", path, map[string]any{
    		"operator": ">", "threshold": -1, "severity": "info", "enabled": true,
    	}, nil)
    }
    
    ```

=== "Rust"

    ```rust
    /// Overrides the threshold of a rule for one server. A threshold of -1 is
    /// below any value that the staleness ratio can take, so the rule is
    /// violated on the next evaluation.
    fn set_override(cfg: &Settings, rule_id: i64) -> Result<()> {
        let path = format!("/alert-overrides/server/{}/{rule_id}", cfg.connection_id);
        let body = json!({ "operator": ">", "threshold": -1, "severity": "info", "enabled": true });
        api(Method::PUT, cfg, &path, &[], Some(&body))?;
        Ok(())
    }
    ```

=== "Ruby"

    ```ruby
    # Overrides the threshold of a rule for one server. A threshold of -1 is
    # below any value that the staleness ratio can take, so the rule is
    # violated on the next evaluation.
    def set_override(cfg, rule_id)
      api("PUT", cfg, "/alert-overrides/server/#{cfg[:connection_id]}/#{rule_id}",
          body: { operator: ">", threshold: -1, severity: "info", enabled: true })
    end
    ```

=== "curl"

    ```bash
    # Overrides the threshold of a rule for one server. A threshold of -1 is
    # below any value that the staleness ratio can take, so the rule is
    # violated on the next evaluation.
    set_override() {
        local rule_id="$1"
        api PUT "/alert-overrides/server/$WORKBENCH_CONNECTION_ID/$rule_id" \
            --header 'Content-Type: application/json' \
            --data '{"operator": ">", "threshold": -1, "severity": "info", "enabled": true}' \
            >/dev/null
    }
    ```

## Waiting for the Alert

Before it sets the override, the program waits until the rule has no active
alert, because the alerter raises no new alert for a rule while one is active,
and an alert left by an earlier run would otherwise stand in for the new one.
The program then polls `GET /api/v1/alerts` with the connection ID, the status
`active`, the type `threshold`, and the largest `limit` that the API allows,
until the list contains an alert from the rule. The API cannot filter by rule,
so the program does that part itself. The alerter evaluates its rules every 60
seconds, so the alert appears within a minute of the override. This particular
alert clears itself between 0 and 30 seconds after it fires, because the
alerter's clean-up pass finds no current value for the staleness metric; the
program therefore polls twice a second. If the alert clears before the program
can acknowledge it, the program waits for the rule to fire again, which takes
up to another minute, within its overall limit of 150 seconds. The following
tabs show how each program waits:

=== "Python"

    ```python
    def active_alerts(cfg: dict, rule_id: int) -> list:
        """Returns the active alerts that the given rule raised for the server.
    
        The request filters by server, status, and type, and asks for the most
        alerts that the API returns at once, so that the result does not depend
        on the first 100 alerts of a busy Workbench.
        """
        alerts = api("GET", cfg, "/alerts", params={
            "connection_id": cfg["connection_id"], "status": "active",
            "alert_type": "threshold", "limit": 1000,
        }).json()["alerts"]
        return [alert for alert in alerts if alert["rule_id"] == rule_id]
    
    
    def wait_until_quiet(cfg: dict, rule_id: int, deadline: float) -> None:
        """Waits until the rule has no active alert.
    
        The alerter raises no new alert for a rule while one is active, so an
        alert left by an earlier run, which clears within 30 seconds, would
        otherwise stand in for the one that this run causes.
        """
        while active_alerts(cfg, rule_id):
            if time.monotonic() >= deadline:
                raise RuntimeError("An earlier alert did not clear in time")
            time.sleep(POLL_SECONDS)
    
    
    def wait_for_alert(cfg: dict, rule_id: int, deadline: float) -> dict:
        """Polls until the given rule raises an alert, and returns it.
    
        The alert clears itself within 30 seconds of firing, so the program
        polls twice a second.
        """
        while True:
            alerts = active_alerts(cfg, rule_id)
            if alerts:
                return alerts[0]
            if time.monotonic() >= deadline:
                raise RuntimeError(
                    f"No alert was raised within {WAIT_SECONDS} seconds"
                )
            time.sleep(POLL_SECONDS)
    ```

=== "TypeScript"

    ```typescript
    interface Alert {
      id: number;
      rule_id: number;
      severity: string;
      status: string;
    }
    
    // Returns the threshold alerts for a server that have the given status. The
    // request filters by server, status, and type, and asks for the most alerts
    // that the API returns at once, so that the result does not depend on the
    // first 100 alerts of a busy Workbench.
    async function listAlerts(cfg: Settings, status: string): Promise<Alert[]> {
      const query = new URLSearchParams({
        connection_id: cfg.connectionId,
        status,
        alert_type: "threshold",
        limit: "1000",
      });
      const response = await api("GET", cfg, `/alerts?${query}`);
      return ((await response.json()) as { alerts: Alert[] }).alerts;
    }
    
    // Returns the active alerts that the given rule raised.
    async function activeAlerts(cfg: Settings, ruleId: number): Promise<Alert[]> {
      return (await listAlerts(cfg, "active")).filter((a) => a.rule_id === ruleId);
    }
    
    const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));
    
    // Waits until the rule has no active alert. The alerter raises no new alert
    // for a rule while one is active, so an alert left by an earlier run, which
    // clears within 30 seconds, would otherwise stand in for the one that this
    // run causes.
    async function waitUntilQuiet(
      cfg: Settings,
      ruleId: number,
      deadline: number,
    ): Promise<void> {
      while ((await activeAlerts(cfg, ruleId)).length > 0) {
        if (Date.now() >= deadline) {
          throw new Error("An earlier alert did not clear in time");
        }
        await sleep(POLL_MS);
      }
    }
    
    // Polls until the given rule raises an alert, and returns it. The alert
    // clears itself within 30 seconds of firing, so the program polls twice a
    // second.
    async function waitForAlert(
      cfg: Settings,
      ruleId: number,
      deadline: number,
    ): Promise<Alert> {
      for (;;) {
        const [alert] = await activeAlerts(cfg, ruleId);
        if (alert) return alert;
        if (Date.now() >= deadline) {
          throw new Error(`No alert was raised within ${WAIT_MS / 1000} seconds`);
        }
        await sleep(POLL_MS);
      }
    }
    ```

=== "Java"

    ```java
    /**
     * Returns the threshold alerts for the server that have the given
     * status. The request asks for the most alerts that the API returns at
     * once, so that the result does not depend on the first 100 alerts of
     * a busy Workbench.
     */
    static List<JsonNode> listAlerts(Settings cfg, String status)
            throws IOException, InterruptedException {
        Map<String, String> params = new LinkedHashMap<>();
        params.put("connection_id", cfg.connectionId());
        params.put("status", status);
        params.put("alert_type", "threshold");
        params.put("limit", "1000");
        List<JsonNode> alerts = new ArrayList<>();
        api("GET", cfg, "/alerts", params, null).path("alerts")
                .forEach(alerts::add);
        return alerts;
    }
    
    /** Returns the active alerts that the given rule raised for the server. */
    static List<JsonNode> activeAlerts(Settings cfg, long ruleId)
            throws IOException, InterruptedException {
        List<JsonNode> alerts = listAlerts(cfg, "active");
        alerts.removeIf(alert -> alert.path("rule_id").asLong() != ruleId);
        return alerts;
    }
    
    /**
     * Waits until the rule has no active alert. The alerter raises no new
     * alert for a rule while one is active, so an alert left by an earlier
     * run, which clears within 30 seconds, would otherwise stand in for the
     * one that this run causes.
     */
    static void waitUntilQuiet(Settings cfg, long ruleId, long deadline)
            throws IOException, InterruptedException {
        while (!activeAlerts(cfg, ruleId).isEmpty()) {
            if (System.nanoTime() - deadline >= 0) {
                throw new IOException("An earlier alert did not clear in time");
            }
            Thread.sleep(POLL_INTERVAL.toMillis());
        }
    }
    
    /**
     * Polls until the given rule raises an alert, and returns it. The alert
     * clears itself within 30 seconds of firing, so the program polls twice
     * a second.
     */
    static JsonNode waitForAlert(Settings cfg, long ruleId, long deadline)
            throws IOException, InterruptedException {
        while (true) {
            List<JsonNode> alerts = activeAlerts(cfg, ruleId);
            if (!alerts.isEmpty()) {
                return alerts.get(0);
            }
            if (System.nanoTime() - deadline >= 0) {
                throw new IOException("No alert was raised within "
                        + WAIT_TIME.toSeconds() + " seconds");
            }
            Thread.sleep(POLL_INTERVAL.toMillis());
        }
    }
    ```

=== "C#"

    ```csharp
    // Returns the threshold alerts for the server that have the given status.
    // The request asks for the most alerts that the API returns at once, so
    // that the result does not depend on the first 100 alerts of a busy
    // Workbench.
    async Task<List<JsonNode>> ListAlerts(string status)
    {
        var query = $"connection_id={Uri.EscapeDataString(cfg.ConnectionId)}"
            + $"&status={status}&alert_type=threshold&limit=1000";
        var reply = await Api("GET", $"/alerts?{query}");
        return reply?["alerts"]?.AsArray().OfType<JsonNode>().ToList()
            ?? throw new InvalidOperationException("The reply had no alerts");
    }
    
    // Returns the active alerts that the given rule raised for the server.
    async Task<List<JsonNode>> ActiveAlerts(long ruleId) =>
        (await ListAlerts("active"))
            .Where(a => a["rule_id"]?.GetValue<long>() == ruleId)
            .ToList();
    
    // Waits until the rule has no active alert. The alerter raises no new
    // alert for a rule while one is active, so an alert left by an earlier
    // run, which clears within 30 seconds, would otherwise stand in for the
    // one that this run causes.
    async Task WaitUntilQuiet(long ruleId, Stopwatch clock)
    {
        while ((await ActiveAlerts(ruleId)).Count > 0)
        {
            if (clock.Elapsed >= waitTime)
            {
                throw new InvalidOperationException(
                    "An earlier alert did not clear in time");
            }
            await Task.Delay(pollInterval);
        }
    }
    
    // Polls until the given rule raises an alert, and returns it. The alert
    // clears itself within 30 seconds of firing, so the program polls twice a
    // second.
    async Task<JsonNode> WaitForAlert(long ruleId, Stopwatch clock)
    {
        while (true)
        {
            var alerts = await ActiveAlerts(ruleId);
            if (alerts.Count > 0)
            {
                return alerts[0];
            }
            if (clock.Elapsed >= waitTime)
            {
                throw new InvalidOperationException(
                    $"No alert was raised within {waitTime.TotalSeconds} seconds");
            }
            await Task.Delay(pollInterval);
        }
    }
    ```

=== "Go"

    ```go
    // alert is the part of an alert that the program needs.
    type alert struct {
    	ID       int64  `json:"id"`
    	RuleID   int64  `json:"rule_id"`
    	Severity string `json:"severity"`
    	Status   string `json:"status"`
    }
    
    // listAlerts returns the threshold alerts for a server that have the given
    // status. The request filters by server, status, and type, and asks for the
    // most alerts that the API returns at once, so that the result does not
    // depend on the first 100 alerts of a busy Workbench.
    func listAlerts(s settings, status string) ([]alert, error) {
    	query := url.Values{
    		"connection_id": {s.connectionID},
    		"status":        {status},
    		"alert_type":    {"threshold"},
    		"limit":         {"1000"},
    	}
    	var result struct {
    		Alerts []alert `json:"alerts"`
    	}
    	err := api(s, "GET", "/alerts?"+query.Encode(), nil, &result)
    	return result.Alerts, err
    }
    
    // activeAlerts returns the active alerts that the given rule raised.
    func activeAlerts(s settings, ruleID int64) ([]alert, error) {
    	alerts, err := listAlerts(s, "active")
    	var raised []alert
    	for _, a := range alerts {
    		if a.RuleID == ruleID {
    			raised = append(raised, a)
    		}
    	}
    	return raised, err
    }
    
    // waitUntilQuiet waits until the rule has no active alert. The alerter
    // raises no new alert for a rule while one is active, so an alert left by an
    // earlier run, which clears within 30 seconds, would otherwise stand in for
    // the one that this run causes.
    func waitUntilQuiet(s settings, ruleID int64, deadline time.Time) error {
    	for {
    		raised, err := activeAlerts(s, ruleID)
    		if err != nil {
    			return err
    		}
    		if len(raised) == 0 {
    			return nil
    		}
    		if time.Now().After(deadline) {
    			return errors.New("an earlier alert did not clear in time")
    		}
    		time.Sleep(pollTime)
    	}
    }
    
    // waitForAlert polls until the given rule raises an alert, and returns it.
    // The alert clears itself within 30 seconds of firing, so the program polls
    // twice a second.
    func waitForAlert(s settings, ruleID int64, deadline time.Time) (alert, error) {
    	for {
    		raised, err := activeAlerts(s, ruleID)
    		if err != nil {
    			return alert{}, err
    		}
    		if len(raised) > 0 {
    			return raised[0], nil
    		}
    		if time.Now().After(deadline) {
    			return alert{}, fmt.Errorf("no alert was raised within %s", waitTime)
    		}
    		time.Sleep(pollTime)
    	}
    }
    
    ```

=== "Rust"

    ```rust
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
    ```

=== "Ruby"

    ```ruby
    # Returns the threshold alerts for the server that have the given status.
    # The request asks for the most alerts that the API returns at once, so
    # that the result does not depend on the first 100 alerts of a busy
    # Workbench.
    def list_alerts(cfg, status)
      api("GET", cfg, "/alerts", params: {
            connection_id: cfg[:connection_id], status: status,
            alert_type: "threshold", limit: 1000
          }).fetch("alerts")
    end
    
    # Returns the active alerts that the given rule raised for the server.
    def active_alerts(cfg, rule_id)
      list_alerts(cfg, "active").select { |alert| alert["rule_id"] == rule_id }
    end
    
    # Returns the seconds on a clock that only moves forwards, for deadlines.
    def now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
    
    # Waits until the rule has no active alert. The alerter raises no new alert
    # for a rule while one is active, so an alert left by an earlier run, which
    # clears within 30 seconds, would otherwise stand in for the one that this
    # run causes.
    def wait_until_quiet(cfg, rule_id, deadline)
      until active_alerts(cfg, rule_id).empty?
        raise "An earlier alert did not clear in time" if now >= deadline
    
        sleep POLL_SECONDS
      end
    end
    
    # Polls until the given rule raises an alert, and returns it. The alert
    # clears itself within 30 seconds of firing, so the program polls twice a
    # second.
    def wait_for_alert(cfg, rule_id, deadline)
      loop do
        alert = active_alerts(cfg, rule_id).first
        return alert if alert
        raise "No alert was raised within #{WAIT_SECONDS} seconds" if now >= deadline
    
        sleep POLL_SECONDS
      end
    end
    ```

=== "curl"

    ```bash
    # Prints the active alerts that a rule raised for the server, one per line,
    # as an ID and a severity. The request filters by server, status, and type,
    # and asks for the most alerts that the API returns at once, so that the
    # result does not depend on the first 100 alerts of a busy Workbench.
    active_alerts() {
        local rule_id="$1"
        api GET "/alerts?connection_id=$WORKBENCH_CONNECTION_ID&status=active&alert_type=threshold&limit=1000" |
            jq -r --argjson rule "$rule_id" \
               '.alerts[] | select(.rule_id == $rule) | "\(.id) \(.severity)"'
    }
    
    # Waits until the rule has no active alert. The alerter raises no new alert
    # for a rule while one is active, so an alert left by an earlier run, which
    # clears within 30 seconds, would otherwise stand in for the one that this
    # run causes.
    wait_until_quiet() {
        local rule_id="$1" deadline="$2" active
        while true; do
            active=$(active_alerts "$rule_id")
            [[ -z "$active" ]] && return 0
            if ((SECONDS >= deadline)); then
                echo "An earlier alert did not clear in time" >&2
                return 1
            fi
            sleep "$POLL_SECONDS"
        done
    }
    
    # Polls until the rule raises an alert, and sets ALERT_ID and ALERT_SEVERITY
    # to its ID and severity. The alert clears itself within 30 seconds of
    # firing, so the script polls twice a second. The caller must not run this
    # function inside $(...), where errexit is off, because an error from the API
    # would then go unnoticed until the deadline.
    wait_for_alert() {
        local rule_id="$1" deadline="$2" active
        while true; do
            active=$(active_alerts "$rule_id")
            if [[ -n "$active" ]]; then
                read -r ALERT_ID ALERT_SEVERITY <<<"${active%%$'\n'*}"
                return 0
            fi
            if ((SECONDS >= deadline)); then
                echo "No alert was raised within $WAIT_SECONDS seconds" >&2
                return 1
            fi
            sleep "$POLL_SECONDS"
        done
    }
    ```

## Acknowledging the Alert

The program acknowledges the alert with `POST /api/v1/alerts/acknowledge`,
sending the alert ID and a message. The request can also set `false_positive`
to record that the alert was a mistake. The following tabs show how each
program acknowledges the alert:

=== "Python"

    ```python
    def acknowledge_alert(cfg: dict, alert_id: int) -> None:
        """Acknowledges an alert, with a message that the interface shows."""
        api("POST", cfg, "/alerts/acknowledge", json={
            "alert_id": alert_id, "message": "Acknowledged by the cookbook",
        })
    ```

=== "TypeScript"

    ```typescript
    // Acknowledges an alert, with a message that the interface shows.
    async function acknowledgeAlert(cfg: Settings, alertId: number): Promise<void> {
      await api("POST", cfg, "/alerts/acknowledge", {
        alert_id: alertId,
        message: "Acknowledged by the cookbook",
      });
    }
    ```

=== "Java"

    ```java
    /** Acknowledges an alert, with a message that the interface shows. */
    static void acknowledgeAlert(Settings cfg, long alertId)
            throws IOException, InterruptedException {
        api("POST", cfg, "/alerts/acknowledge", null, Map.of(
                "alert_id", alertId,
                "message", "Acknowledged by the cookbook"));
    }
    ```

=== "C#"

    ```csharp
    // Acknowledges an alert, with a message that the interface shows.
    async Task AcknowledgeAlert(long alertId) =>
        await Api("POST", "/alerts/acknowledge",
            new { alert_id = alertId, message = "Acknowledged by the cookbook" });
    ```

=== "Go"

    ```go
    // acknowledgeAlert acknowledges an alert, with a message that the interface
    // shows.
    func acknowledgeAlert(s settings, alertID int64) error {
    	return api(s, "POST", "/alerts/acknowledge", map[string]any{
    		"alert_id": alertID,
    		"message":  "Acknowledged by the cookbook",
    	}, nil)
    }
    
    ```

=== "Rust"

    ```rust
    /// Acknowledges an alert, with a message that the interface shows.
    fn acknowledge_alert(cfg: &Settings, alert_id: i64) -> Result<()> {
        let body = json!({ "alert_id": alert_id, "message": "Acknowledged by the cookbook" });
        api(Method::POST, cfg, "/alerts/acknowledge", &[], Some(&body))?;
        Ok(())
    }
    ```

=== "Ruby"

    ```ruby
    # Acknowledges an alert, with a message that the interface shows.
    def acknowledge_alert(cfg, alert_id)
      api("POST", cfg, "/alerts/acknowledge",
          body: { alert_id: alert_id, message: "Acknowledged by the cookbook" })
    end
    ```

=== "curl"

    ```bash
    # Acknowledges an alert, with a message that the interface shows.
    acknowledge_alert() {
        local alert_id="$1"
        jq -n --argjson id "$alert_id" \
           '{alert_id: $id, message: "Acknowledged by the cookbook"}' |
            api POST /alerts/acknowledge \
                --header 'Content-Type: application/json' --data @- >/dev/null
    }
    ```

## Checking the Status

The program confirms the acknowledgement by listing the alerts with the status
`acknowledged`, and looking for the alert by its ID. The following tabs show
how each program checks the status:

=== "Python"

    ```python
    def acknowledged_alerts(cfg: dict) -> list:
        """Returns the acknowledged threshold alerts for the server."""
        return api("GET", cfg, "/alerts", params={
            "connection_id": cfg["connection_id"], "status": "acknowledged",
            "alert_type": "threshold", "limit": 1000,
        }).json()["alerts"]
    
    
    def alert_status(cfg: dict, alert_id: int) -> str:
        """Returns the status of an alert, found by its ID in the list of
        acknowledged alerts."""
        for alert in acknowledged_alerts(cfg):
            if alert["id"] == alert_id:
                return alert["status"]
        raise RuntimeError("The alert is missing from the acknowledged alerts")
    ```

=== "TypeScript"

    ```typescript
    // Returns the status of an alert, found by its ID in the list of
    // acknowledged alerts.
    async function alertStatus(cfg: Settings, alertId: number): Promise<string> {
      const alert = (await listAlerts(cfg, "acknowledged")).find(
        (a) => a.id === alertId,
      );
      if (!alert) {
        throw new Error("The alert is missing from the acknowledged alerts");
      }
      return alert.status;
    }
    ```

=== "Java"

    ```java
    /**
     * Returns the status of an alert, found by its ID in the list of
     * acknowledged alerts.
     */
    static String alertStatus(Settings cfg, long alertId)
            throws IOException, InterruptedException {
        for (JsonNode alert : listAlerts(cfg, "acknowledged")) {
            if (alert.path("id").asLong() == alertId) {
                return alert.get("status").asString();
            }
        }
        throw new IOException(
                "The alert is missing from the acknowledged alerts");
    }
    ```

=== "C#"

    ```csharp
    // Returns the status of an alert, found by its ID in the list of
    // acknowledged alerts.
    async Task<string> AlertStatus(long alertId)
    {
        var alert = (await ListAlerts("acknowledged"))
            .FirstOrDefault(a => a["id"]?.GetValue<long>() == alertId)
            ?? throw new InvalidOperationException(
                "The alert is missing from the acknowledged alerts");
        return alert["status"]!.GetValue<string>();
    }
    ```

=== "Go"

    ```go
    // alertStatus returns the status of an alert, found by its ID in the list of
    // acknowledged alerts.
    func alertStatus(s settings, alertID int64) (string, error) {
    	alerts, err := listAlerts(s, "acknowledged")
    	if err != nil {
    		return "", err
    	}
    	for _, a := range alerts {
    		if a.ID == alertID {
    			return a.Status, nil
    		}
    	}
    	return "", errors.New("the alert is missing from the acknowledged alerts")
    }
    
    ```

=== "Rust"

    ```rust
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
    ```

=== "Ruby"

    ```ruby
    # Returns the status of an alert, found by its ID in the list of
    # acknowledged alerts.
    def alert_status(cfg, alert_id)
      alert = list_alerts(cfg, "acknowledged").find { |a| a["id"] == alert_id }
      raise "The alert is missing from the acknowledged alerts" if alert.nil?
    
      alert.fetch("status")
    end
    ```

=== "curl"

    ```bash
    # Prints the acknowledged threshold alerts for the server, as JSON.
    list_acknowledged() {
        api GET "/alerts?connection_id=$WORKBENCH_CONNECTION_ID&status=acknowledged&alert_type=threshold&limit=1000"
    }
    
    # Prints the status of an alert, found by its ID in the list of acknowledged
    # alerts. The function fails when the alert is not in the list, because jq
    # prints nothing for it.
    alert_status() {
        local alert_id="$1" status
        status=$(list_acknowledged |
            jq -r --argjson id "$alert_id" \
               'first(.alerts[] | select(.id == $id)) | .status')
        if [[ -z "$status" ]]; then
            echo "The alert is missing from the acknowledged alerts" >&2
            return 1
        fi
        printf '%s' "$status"
    }
    ```

## Returning the Alert to the Active State

The alerter's clean-up pass looks only at active alerts, and its rule
evaluation treats an acknowledged alert as the current alert for the rule, so
it raises no new one. An acknowledged alert left behind by the example would
therefore stop the example from working the next time. The program calls
`DELETE /api/v1/alerts/acknowledge` with the alert ID, which returns the alert
to the active state, and the alerter then clears it within about half a minute.
The following tabs show how each program removes the acknowledgement:

=== "Python"

    ```python
    def unacknowledge_alert(cfg: dict, alert_id: int) -> None:
        """Returns an acknowledged alert to the active state.
    
        The alerter clears only active alerts, so an alert that stays
        acknowledged also stops the rule from raising a new one.
        """
        api("DELETE", cfg, "/alerts/acknowledge", params={"alert_id": alert_id})
    ```

=== "TypeScript"

    ```typescript
    // Returns an acknowledged alert to the active state. The alerter clears only
    // active alerts, so an alert that stays acknowledged also stops the rule from
    // raising a new one.
    async function unacknowledgeAlert(
      cfg: Settings,
      alertId: number,
    ): Promise<void> {
      await api("DELETE", cfg, `/alerts/acknowledge?alert_id=${alertId}`);
    }
    ```

=== "Java"

    ```java
    /**
     * Returns an acknowledged alert to the active state. The alerter clears
     * only active alerts, so an alert that stays acknowledged also stops
     * the rule from raising a new one.
     */
    static void unacknowledgeAlert(Settings cfg, long alertId)
            throws IOException, InterruptedException {
        api("DELETE", cfg, "/alerts/acknowledge",
                Map.of("alert_id", Long.toString(alertId)), null);
    }
    ```

=== "C#"

    ```csharp
    // Returns an acknowledged alert to the active state. The alerter clears
    // only active alerts, so an alert that stays acknowledged also stops the
    // rule from raising a new one.
    async Task UnacknowledgeAlert(long alertId) =>
        await Api("DELETE", $"/alerts/acknowledge?alert_id={alertId}");
    ```

=== "Go"

    ```go
    // unacknowledgeAlert returns an acknowledged alert to the active state. The
    // alerter clears only active alerts, so an alert that stays acknowledged
    // also stops the rule from raising a new one.
    func unacknowledgeAlert(s settings, alertID int64) error {
    	return api(s, "DELETE", fmt.Sprintf("/alerts/acknowledge?alert_id=%d", alertID), nil, nil)
    }
    
    ```

=== "Rust"

    ```rust
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
    ```

=== "Ruby"

    ```ruby
    # Returns an acknowledged alert to the active state. The alerter clears
    # only active alerts, so an alert that stays acknowledged also stops the
    # rule from raising a new one.
    def unacknowledge_alert(cfg, alert_id)
      api("DELETE", cfg, "/alerts/acknowledge", params: { alert_id: alert_id })
    end
    ```

=== "curl"

    ```bash
    # Returns an acknowledged alert to the active state. The alerter clears only
    # active alerts, so an alert that stays acknowledged also stops the rule from
    # raising a new one.
    unacknowledge_alert() {
        local alert_id="$1"
        api DELETE "/alerts/acknowledge?alert_id=$alert_id" >/dev/null
    }
    ```

## Removing the Override

The program removes the override with `DELETE
/api/v1/alert-overrides/server/{connection_id}/{rule_id}`, and the rule reverts
to its default threshold. The following tabs show how each program removes the
override:

=== "Python"

    ```python
    def remove_override(cfg: dict, rule_id: int) -> None:
        """Removes the override, so that the rule reverts to its default
        threshold."""
        api("DELETE", cfg,
            f"/alert-overrides/server/{cfg['connection_id']}/{rule_id}")
    ```

=== "TypeScript"

    ```typescript
    // Removes the override, so that the rule reverts to its default threshold.
    async function removeOverride(cfg: Settings, ruleId: number): Promise<void> {
      await api(
        "DELETE",
        cfg,
        `/alert-overrides/server/${cfg.connectionId}/${ruleId}`,
      );
    }
    ```

=== "Java"

    ```java
    /**
     * Removes the override, so that the rule reverts to its default
     * threshold.
     */
    static void removeOverride(Settings cfg, long ruleId)
            throws IOException, InterruptedException {
        api("DELETE", cfg, "/alert-overrides/server/" + cfg.connectionId()
                + "/" + ruleId, null, null);
    }
    ```

=== "C#"

    ```csharp
    // Removes the override, so that the rule reverts to its default threshold.
    async Task RemoveOverride(long ruleId) =>
        await Api("DELETE",
            $"/alert-overrides/server/{cfg.ConnectionId}/{ruleId}");
    ```

=== "Go"

    ```go
    // removeOverride removes the override, so that the rule reverts to its
    // default threshold.
    func removeOverride(s settings, ruleID int64) error {
    	path := fmt.Sprintf("/alert-overrides/server/%s/%d", s.connectionID, ruleID)
    	return api(s, "DELETE", path, nil, nil)
    }
    
    ```

=== "Rust"

    ```rust
    /// Removes the override, so that the rule reverts to its default
    /// threshold.
    fn remove_override(cfg: &Settings, rule_id: i64) -> Result<()> {
        let path = format!("/alert-overrides/server/{}/{rule_id}", cfg.connection_id);
        api(Method::DELETE, cfg, &path, &[], None)?;
        Ok(())
    }
    ```

=== "Ruby"

    ```ruby
    # Removes the override, so that the rule reverts to its default threshold.
    def remove_override(cfg, rule_id)
      api("DELETE", cfg, "/alert-overrides/server/#{cfg[:connection_id]}/#{rule_id}")
    end
    ```

=== "curl"

    ```bash
    # Removes the override, so that the rule reverts to its default threshold.
    remove_override() {
        local rule_id="$1"
        api DELETE "/alert-overrides/server/$WORKBENCH_CONNECTION_ID/$rule_id" \
            >/dev/null
    }
    ```

## Cleaning Up After a Failure

Each program records an undo step as soon as it makes a change, and runs the
steps that remain when it finishes or fails, so that a failed run does not
leave the server raising alerts. The program records the step that returns the
alert to the active state before it sends the acknowledgement, so that a
request which times out after the server has acted on it is still reversed.
When the acknowledgement fails and the alert is still active, the server did
not acknowledge it, so the program drops that step and reports the error; when
the alert is no longer active, the program removes the acknowledgement only if
the list of acknowledged alerts contains the alert, and keeps the step for the
clean-up to retry if that fails. The Python program uses a `finally` block and
the Ruby program an `ensure` block, and the TypeScript and Go programs keep a
list of undo steps. The Java, C# and Rust programs record the ID of the rule
and of the alert, and undo each change whose ID is still recorded once the
work finishes or fails; the curl script uses an `EXIT` trap. Each program
reports a failure on `stderr` and exits with a non-zero status. The following
tabs show the main part of each program:

=== "Python"

    ```python
    def main() -> int:
        cfg = None
        override_rule = None
        acknowledged_alert = None
        status = 0
        try:
            cfg = settings()
            deadline = time.monotonic() + WAIT_SECONDS
    
            rule_id = find_rule(cfg, RULE_NAME)
            print(f"Found the rule '{RULE_NAME}'")
    
            # An alert from an earlier run may still be active.
            wait_until_quiet(cfg, rule_id, deadline)
    
            # Set the override first and remove it in the finally block, so
            # that a failed run does not leave the server raising alerts.
            override_rule = rule_id
            set_override(cfg, rule_id)
            print("Set an override that makes the rule fire")
    
            print("Waiting for the alerter to raise an alert")
            while True:
                alert = wait_for_alert(cfg, rule_id, deadline)
    
                # Record the alert before acknowledging it, so that the
                # finally block returns it to the active state even if the
                # request times out after the server has acted on it.
                acknowledged_alert = alert["id"]
                try:
                    acknowledge_alert(cfg, alert["id"])
                    break
                except (httpx.HTTPError, RuntimeError):
                    # The alerter may have cleared the alert since the poll.
                    # The override is still in place, so the rule fires again
                    # at the next evaluation; any other failure is real.
                    if any(a["id"] == alert["id"]
                           for a in active_alerts(cfg, rule_id)):
                        # The server did not acknowledge it, so there is
                        # nothing to undo.
                        acknowledged_alert = None
                        raise
                    # If the server acted on a request that timed out, the
                    # alert is acknowledged and must go back to active. When
                    # that fails, the error propagates and the finally block
                    # tries again, because acknowledged_alert is still set.
                    if any(a["id"] == alert["id"]
                           for a in acknowledged_alerts(cfg)):
                        unacknowledge_alert(cfg, alert["id"])
                    acknowledged_alert = None
                    print("The alert cleared first; waiting for the next one",
                          file=sys.stderr)
            print(f"An alert is active (severity: {alert['severity']})")
            print("Acknowledged the alert")
    
            print(f"The alert is now {alert_status(cfg, alert['id'])}")
    
            unacknowledge_alert(cfg, alert["id"])
            acknowledged_alert = None
            print("Returned the alert to the active state")
    
            remove_override(cfg, rule_id)
            override_rule = None
            print("Removed the override")
        # httpx.HTTPError covers failures to connect, and RuntimeError covers
        # replies that the server rejected or that lacked what we need.
        except (httpx.HTTPError, RuntimeError) as e:
            print(f"Error: {e}", file=sys.stderr)
            status = 1
        finally:
            # Undo the changes whether or not a step failed, so that the server
            # does not keep raising alerts or hold an acknowledged one.
            for undo, value in ((unacknowledge_alert, acknowledged_alert),
                                (remove_override, override_rule)):
                if value is None:
                    continue
                try:
                    undo(cfg, value)
                except (httpx.HTTPError, RuntimeError) as e:
                    print(f"Error: could not undo a change: {e}",
                          file=sys.stderr)
                    status = 1
    
        return status
    
    
    if __name__ == "__main__":
        sys.exit(main())
    ```

=== "TypeScript"

    ```typescript
    const message = (err: unknown) => (err instanceof Error ? err.message : err);
    
    async function main(): Promise<number> {
      let exitCode = 0;
      // Each undo step is added when its change is made, and runs whether or not
      // a later step fails, so that the server does not keep raising alerts or
      // hold an acknowledged one.
      const undo: Array<() => Promise<void>> = [];
      try {
        const cfg = settings();
        const deadline = Date.now() + WAIT_MS;
    
        const ruleId = await findRule(cfg, RULE_NAME);
        console.log(`Found the rule '${RULE_NAME}'`);
    
        // An alert from an earlier run may still be active.
        await waitUntilQuiet(cfg, ruleId, deadline);
    
        undo.push(() => removeOverride(cfg, ruleId));
        await setOverride(cfg, ruleId);
        console.log("Set an override that makes the rule fire");
    
        console.log("Waiting for the alerter to raise an alert");
        let alert: Alert;
        for (;;) {
          alert = await waitForAlert(cfg, ruleId, deadline);
    
          // Add the undo step before acknowledging the alert, so that a request
          // that times out after the server has acted on it is still reversed.
          const alertId = alert.id;
          undo.push(() => unacknowledgeAlert(cfg, alertId));
          try {
            await acknowledgeAlert(cfg, alertId);
            break;
          } catch (err) {
            // The alerter may have cleared the alert since the poll. The
            // override is still in place, so the rule fires again at the next
            // evaluation; any other failure is real.
            if ((await activeAlerts(cfg, ruleId)).some((a) => a.id === alertId)) {
              // The server did not acknowledge it, so there is nothing to undo.
              undo.pop();
              throw err;
            }
            // If the server acted on a request that timed out, the alert is
            // acknowledged and must go back to active. When that fails, the
            // error propagates with the undo step still in place, so the
            // clean-up tries again.
            if (
              (await listAlerts(cfg, "acknowledged")).some((a) => a.id === alertId)
            ) {
              await undo[undo.length - 1]();
            }
            undo.pop();
            console.error("The alert cleared first; waiting for the next one");
          }
        }
        console.log(`An alert is active (severity: ${alert.severity})`);
        console.log("Acknowledged the alert");
    
        console.log(`The alert is now ${await alertStatus(cfg, alert.id)}`);
    
        // Run each step before removing it, so that a step which fails is still
        // there for the clean-up below to try again.
        await undo[undo.length - 1]();
        undo.pop();
        console.log("Returned the alert to the active state");
    
        await undo[undo.length - 1]();
        undo.pop();
        console.log("Removed the override");
      } catch (err) {
        console.error(`Error: ${message(err)}`);
        exitCode = 1;
      }
    
      // Run the steps that are left, most recent first.
      for (const step of undo.reverse()) {
        try {
          await step();
        } catch (err) {
          console.error(`Error: could not undo a change: ${message(err)}`);
          exitCode = 1;
        }
      }
      return exitCode;
    }
    
    process.exitCode = await main();
    ```

=== "Java"

    ```java
    /** Reports whether a list of alerts includes the one with an ID. */
    static boolean contains(List<JsonNode> alerts, long alertId) {
        return alerts.stream()
                .anyMatch(a -> a.path("id").asLong() == alertId);
    }
    
    /**
     * Returns the message of an error. Some errors, such as a refused
     * connection, have no message, so their type stands in for one.
     */
    static String describe(Exception e) {
        return Objects.requireNonNullElse(e.getMessage(), e.toString());
    }
    
    public static void main(String[] args) {
        Settings cfg = null;
        Long overrideRule = null;
        Long acknowledgedAlert = null;
        int status = 0;
        try {
            cfg = settings();
            long deadline = System.nanoTime() + WAIT_TIME.toNanos();
    
            long ruleId = findRule(cfg, RULE_NAME);
            System.out.println("Found the rule '" + RULE_NAME + "'");
    
            // An alert from an earlier run may still be active.
            waitUntilQuiet(cfg, ruleId, deadline);
    
            // Record the override first and remove it at the end, so that
            // a failed run does not leave the server raising alerts.
            overrideRule = ruleId;
            setOverride(cfg, ruleId);
            System.out.println("Set an override that makes the rule fire");
    
            System.out.println("Waiting for the alerter to raise an alert");
            JsonNode alert;
            while (true) {
                alert = waitForAlert(cfg, ruleId, deadline);
                long alertId = alert.get("id").asLong();
    
                // Record the alert before acknowledging it, so that the
                // clean-up returns it to the active state even if the
                // request times out after the server has acted on it.
                acknowledgedAlert = alertId;
                try {
                    acknowledgeAlert(cfg, alertId);
                    break;
                } catch (IOException e) {
                    // The alerter may have cleared the alert since the
                    // poll. The override is still in place, so the rule
                    // fires again at the next evaluation; any other
                    // failure is real.
                    if (contains(activeAlerts(cfg, ruleId), alertId)) {
                        // The server did not acknowledge it, so there is
                        // nothing to undo.
                        acknowledgedAlert = null;
                        throw e;
                    }
                    // If the server acted on a request that timed out, the
                    // alert is acknowledged and must go back to active.
                    // When that fails, the error propagates and the
                    // clean-up tries again, because acknowledgedAlert is
                    // still set.
                    if (contains(listAlerts(cfg, "acknowledged"), alertId)) {
                        unacknowledgeAlert(cfg, alertId);
                    }
                    acknowledgedAlert = null;
                    System.err.println(
                            "The alert cleared first; waiting for the next one");
                }
            }
            long alertId = alert.get("id").asLong();
            System.out.println("An alert is active (severity: "
                    + alert.get("severity").asString() + ")");
            System.out.println("Acknowledged the alert");
    
            System.out.println("The alert is now "
                    + alertStatus(cfg, alertId));
    
            unacknowledgeAlert(cfg, alertId);
            acknowledgedAlert = null;
            System.out.println("Returned the alert to the active state");
    
            removeOverride(cfg, ruleId);
            overrideRule = null;
            System.out.println("Removed the override");
        // IOException covers failures to connect, replies that the server
        // rejected, and replies that lacked what we need; the client
        // throws InterruptedException if the thread is interrupted, and
        // Jackson throws JacksonException for a reply that is not JSON.
        } catch (IOException | InterruptedException | JacksonException e) {
            System.err.println("Error: " + describe(e));
            status = 1;
        } finally {
            // Undo the changes whether or not a step failed, so that the
            // server does not keep raising alerts or hold an acknowledged one.
            // The finally block also runs for an error that the catch does not
            // handle.
            if (acknowledgedAlert != null) {
                try {
                    unacknowledgeAlert(cfg, acknowledgedAlert);
                } catch (IOException | InterruptedException
                        | JacksonException e) {
                    System.err.println("Error: could not undo a change: "
                            + describe(e));
                    status = 1;
                }
            }
            if (overrideRule != null) {
                try {
                    removeOverride(cfg, overrideRule);
                } catch (IOException | InterruptedException
                        | JacksonException e) {
                    System.err.println("Error: could not undo a change: "
                            + describe(e));
                    status = 1;
                }
            }
        }
        System.exit(status);
    }
    ```

=== "C#"

    ```csharp
    // Reports whether an error is one that the program expects: a failure to
    // connect, a reply that the server rejected, a request that timed out, or
    // a reply that lacked what we need.
    static bool Expected(Exception e) => e is HttpRequestException
        or TaskCanceledException or InvalidOperationException or JsonException;
    
    // Reports whether a list of alerts includes the one with an ID.
    static bool Contains(List<JsonNode> alerts, long alertId) =>
        alerts.Any(a => a["id"]?.GetValue<long>() == alertId);
    
    long? overrideRule = null;
    long? acknowledgedAlert = null;
    var status = 0;
    try
    {
        cfg = Settings();
        var clock = Stopwatch.StartNew();
    
        var ruleId = await FindRule(RuleName);
        Console.WriteLine($"Found the rule '{RuleName}'");
    
        // An alert from an earlier run may still be active.
        await WaitUntilQuiet(ruleId, clock);
    
        // Record the override first and remove it at the end, so that a
        // failed run does not leave the server raising alerts.
        overrideRule = ruleId;
        await SetOverride(ruleId);
        Console.WriteLine("Set an override that makes the rule fire");
    
        Console.WriteLine("Waiting for the alerter to raise an alert");
        JsonNode alert;
        while (true)
        {
            alert = await WaitForAlert(ruleId, clock);
            var raisedId = alert["id"]!.GetValue<long>();
    
            // Record the alert before acknowledging it, so that the clean-up
            // returns it to the active state even if the request times out
            // after the server has acted on it.
            acknowledgedAlert = raisedId;
            try
            {
                await AcknowledgeAlert(raisedId);
                break;
            }
            catch (Exception e) when (Expected(e))
            {
                // The alerter may have cleared the alert since the poll. The
                // override is still in place, so the rule fires again at the
                // next evaluation; any other failure is real.
                if (Contains(await ActiveAlerts(ruleId), raisedId))
                {
                    // The server did not acknowledge it, so there is nothing
                    // to undo.
                    acknowledgedAlert = null;
                    throw;
                }
                // If the server acted on a request that timed out, the alert
                // is acknowledged and must go back to active. When that fails,
                // the error propagates and the clean-up tries again, because
                // acknowledgedAlert is still set.
                if (Contains(await ListAlerts("acknowledged"), raisedId))
                {
                    await UnacknowledgeAlert(raisedId);
                }
                acknowledgedAlert = null;
                Console.Error.WriteLine(
                    "The alert cleared first; waiting for the next one");
            }
        }
        var alertId = alert["id"]!.GetValue<long>();
        Console.WriteLine(
            $"An alert is active (severity: {alert["severity"]})");
        Console.WriteLine("Acknowledged the alert");
    
        Console.WriteLine($"The alert is now {await AlertStatus(alertId)}");
    
        await UnacknowledgeAlert(alertId);
        acknowledgedAlert = null;
        Console.WriteLine("Returned the alert to the active state");
    
        await RemoveOverride(ruleId);
        overrideRule = null;
        Console.WriteLine("Removed the override");
    }
    catch (Exception e) when (Expected(e))
    {
        Console.Error.WriteLine($"Error: {e.Message}");
        status = 1;
    }
    finally
    {
        // Undo the changes whether or not a step failed, so that the server does
        // not keep raising alerts or hold an acknowledged one. The finally block
        // also runs for an error that the catch does not handle.
        var undo = new List<Func<Task>>();
        if (acknowledgedAlert is long pendingAlert)
        {
            undo.Add(() => UnacknowledgeAlert(pendingAlert));
        }
        if (overrideRule is long pendingRule)
        {
            undo.Add(() => RemoveOverride(pendingRule));
        }
        foreach (var step in undo)
        {
            try
            {
                await step();
            }
            catch (Exception e) when (Expected(e))
            {
                Console.Error.WriteLine(
                    $"Error: could not undo a change: {e.Message}");
                status = 1;
            }
        }
    }
    
    return status;
    ```

=== "Go"

    ```go
    // run does the work. Each time it makes a change it adds a step to undo, and
    // removes the step again once the program has reversed the change itself.
    func run(s settings, undo *[]func() error) error {
    	deadline := time.Now().Add(waitTime)
    
    	ruleID, err := findRule(s, ruleName)
    	if err != nil {
    		return err
    	}
    	fmt.Printf("Found the rule '%s'\n", ruleName)
    
    	// An alert from an earlier run may still be active.
    	if err := waitUntilQuiet(s, ruleID, deadline); err != nil {
    		return err
    	}
    
    	*undo = append(*undo, func() error { return removeOverride(s, ruleID) })
    	if err := setOverride(s, ruleID); err != nil {
    		return err
    	}
    	fmt.Println("Set an override that makes the rule fire")
    
    	fmt.Println("Waiting for the alerter to raise an alert")
    	var raised alert
    	for {
    		raised, err = waitForAlert(s, ruleID, deadline)
    		if err != nil {
    			return err
    		}
    
    		// Add the undo step before acknowledging the alert, so that a
    		// request that times out after the server has acted on it is still
    		// reversed.
    		*undo = append(*undo, func() error { return unacknowledgeAlert(s, raised.ID) })
    		err = acknowledgeAlert(s, raised.ID)
    		if err == nil {
    			break
    		}
    
    		// The alerter may have cleared the alert since the poll. The
    		// override is still in place, so the rule fires again at the next
    		// evaluation; any other failure is real.
    		stillActive, listErr := activeAlerts(s, ruleID)
    		for _, a := range stillActive {
    			if a.ID == raised.ID {
    				// The server did not acknowledge it, so there is nothing
    				// to undo.
    				*undo = (*undo)[:len(*undo)-1]
    				return err
    			}
    		}
    		if listErr != nil {
    			return listErr
    		}
    		// If the server acted on a request that timed out, the alert is
    		// acknowledged and must go back to active. When that fails, the
    		// undo step stays in place, so the clean-up tries again.
    		acknowledged, listErr := listAlerts(s, "acknowledged")
    		if listErr != nil {
    			return listErr
    		}
    		for _, a := range acknowledged {
    			if a.ID == raised.ID {
    				if err := unacknowledgeAlert(s, raised.ID); err != nil {
    					return err
    				}
    				break
    			}
    		}
    		*undo = (*undo)[:len(*undo)-1]
    		fmt.Fprintln(os.Stderr, "The alert cleared first; waiting for the next one")
    	}
    	fmt.Printf("An alert is active (severity: %s)\n", raised.Severity)
    	fmt.Println("Acknowledged the alert")
    
    	status, err := alertStatus(s, raised.ID)
    	if err != nil {
    		return err
    	}
    	fmt.Println("The alert is now", status)
    
    	if err := unacknowledgeAlert(s, raised.ID); err != nil {
    		return err
    	}
    	*undo = (*undo)[:len(*undo)-1]
    	fmt.Println("Returned the alert to the active state")
    
    	if err := removeOverride(s, ruleID); err != nil {
    		return err
    	}
    	*undo = (*undo)[:len(*undo)-1]
    	fmt.Println("Removed the override")
    	return nil
    }
    
    func main() {
    	s, err := loadSettings()
    	if err != nil {
    		fmt.Fprintln(os.Stderr, "Error:", err)
    		os.Exit(1)
    	}
    
    	// Undo the changes whether or not a step failed, so that the server does
    	// not keep raising alerts or hold an acknowledged one.
    	var undo []func() error
    	failed := false
    	if err := run(s, &undo); err != nil {
    		fmt.Fprintln(os.Stderr, "Error:", err)
    		failed = true
    	}
    	for i := len(undo) - 1; i >= 0; i-- {
    		if err := undo[i](); err != nil {
    			fmt.Fprintln(os.Stderr, "Error: could not undo a change:", err)
    			failed = true
    		}
    	}
    	if failed {
    		os.Exit(1)
    	}
    }
    
    ```

=== "Rust"

    ```rust
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
    ```

=== "Ruby"

    ```ruby
    # Reports whether a list of alerts includes the one with an ID.
    def includes_alert?(alerts, alert_id)
      alerts.any? { |a| a["id"] == alert_id }
    end
    
    def main
      cfg = nil
      override_rule = nil
      acknowledged_alert = nil
      status = 0
      begin
        cfg = settings
        deadline = now + WAIT_SECONDS
    
        rule_id = find_rule(cfg, RULE_NAME)
        puts "Found the rule '#{RULE_NAME}'"
    
        # An alert from an earlier run may still be active.
        wait_until_quiet(cfg, rule_id, deadline)
    
        # Record the override first and remove it in the ensure block, so that
        # a failed run does not leave the server raising alerts.
        override_rule = rule_id
        set_override(cfg, rule_id)
        puts "Set an override that makes the rule fire"
    
        puts "Waiting for the alerter to raise an alert"
        alert = nil
        loop do
          alert = wait_for_alert(cfg, rule_id, deadline)
    
          # Record the alert before acknowledging it, so that the ensure block
          # returns it to the active state even if the request times out after
          # the server has acted on it.
          acknowledged_alert = alert["id"]
          begin
            acknowledge_alert(cfg, alert["id"])
            break
          rescue StandardError
            # The alerter may have cleared the alert since the poll. The
            # override is still in place, so the rule fires again at the next
            # evaluation; any other failure is real.
            if includes_alert?(active_alerts(cfg, rule_id), alert["id"])
              # The server did not acknowledge it, so there is nothing to undo.
              acknowledged_alert = nil
              raise
            end
            # If the server acted on a request that timed out, the alert is
            # acknowledged and must go back to active. When that fails, the
            # error propagates and the ensure block tries again, because
            # acknowledged_alert is still set.
            if includes_alert?(list_alerts(cfg, "acknowledged"), alert["id"])
              unacknowledge_alert(cfg, alert["id"])
            end
            acknowledged_alert = nil
            warn "The alert cleared first; waiting for the next one"
          end
        end
        puts "An alert is active (severity: #{alert.fetch('severity')})"
        puts "Acknowledged the alert"
    
        puts "The alert is now #{alert_status(cfg, alert['id'])}"
    
        unacknowledge_alert(cfg, alert["id"])
        acknowledged_alert = nil
        puts "Returned the alert to the active state"
    
        remove_override(cfg, rule_id)
        override_rule = nil
        puts "Removed the override"
      # Net::HTTP raises errors of many classes, such as SystemCallError for a
      # refused connection and Net::OpenTimeout for a timeout, and the program
      # raises RuntimeError for replies that the server rejected or that lacked
      # what we need, so this catches StandardError, their common ancestor.
      rescue StandardError => e
        warn "Error: #{e.message}"
        status = 1
      ensure
        # Undo the changes whether or not a step failed, so that the server
        # does not keep raising alerts or hold an acknowledged one.
        undo = []
        undo << -> { unacknowledge_alert(cfg, acknowledged_alert) } if acknowledged_alert
        undo << -> { remove_override(cfg, override_rule) } if override_rule
        undo.each do |step|
          step.call
        rescue StandardError => e
          warn "Error: could not undo a change: #{e.message}"
          status = 1
        end
      end
      status
    end
    
    exit main
    ```

=== "curl"

    ```bash
    # These variables are global, because the EXIT trap runs after main returns.
    override_rule=""
    acknowledged_alert=""
    
    cleanup() {
        local status=$?
        # Undo the changes when the script ends, even if a step failed, so that
        # the server does not keep raising alerts or hold an acknowledged one.
        # Report a step that fails, and make the exit status non-zero.
        if [[ -n "$acknowledged_alert" ]]; then
            unacknowledge_alert "$acknowledged_alert" || {
                echo "Error: could not undo a change" >&2
                status=1
            }
        fi
        if [[ -n "$override_rule" ]]; then
            remove_override "$override_rule" || {
                echo "Error: could not undo a change" >&2
                status=1
            }
        fi
        exit "$status"
    }
    
    main() {
        local rule_id alert_id severity status still_active acknowledged
        local deadline=$((SECONDS + WAIT_SECONDS))
    
        rule_id=$(find_rule "$RULE_NAME")
        echo "Found the rule '$RULE_NAME'"
    
        # An alert from an earlier run may still be active.
        wait_until_quiet "$rule_id" "$deadline"
    
        override_rule="$rule_id"
        set_override "$rule_id"
        echo "Set an override that makes the rule fire"
    
        echo "Waiting for the alerter to raise an alert"
        while true; do
            wait_for_alert "$rule_id" "$deadline"
            alert_id="$ALERT_ID"
            severity="$ALERT_SEVERITY"
    
            # Record the alert before acknowledging it, so that the EXIT trap
            # returns it to the active state even if the request times out
            # after the server has acted on it.
            acknowledged_alert="$alert_id"
            acknowledge_alert "$alert_id" && break
    
            # The alerter may have cleared the alert since the poll. The
            # override is still in place, so the rule fires again at the next
            # evaluation; any other failure is real.
            still_active=$(active_alerts "$rule_id")
            if [[ $'\n'"$still_active" == *$'\n'"$alert_id "* ]]; then
                # The server did not acknowledge it, so there is nothing to
                # undo.
                acknowledged_alert=""
                return 1
            fi
            # If the server acted on a request that timed out, the alert is
            # acknowledged and must go back to active. When that fails, the
            # script stops with the alert still recorded, so that the EXIT trap
            # tries again.
            acknowledged=$(list_acknowledged)
            if jq -e --argjson id "$alert_id" 'any(.alerts[]; .id == $id)' \
                <<<"$acknowledged" >/dev/null; then
                unacknowledge_alert "$alert_id"
            fi
            acknowledged_alert=""
            echo "The alert cleared first; waiting for the next one" >&2
        done
        echo "An alert is active (severity: $severity)"
        echo "Acknowledged the alert"
    
        status=$(alert_status "$alert_id")
        echo "The alert is now $status"
    
        unacknowledge_alert "$alert_id"
        acknowledged_alert=""
        echo "Returned the alert to the active state"
    
        remove_override "$rule_id"
        override_rule=""
        echo "Removed the override"
    }
    
    trap cleanup EXIT
    main
    ```

## Running the Example

The complete project for each language is available in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/ai_dba_workbench/alerts).
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
    Listing and acknowledging alerts with the AI DBA Workbench API, using httpx.
    
    Copyright (c) 2026, pgEdge, Inc.
    This code is released under the PostgreSQL License.
    """
    
    import os
    import sys
    import time
    
    import httpx
    
    
    # The rule that the program makes fire. The metric_staleness rule alerts when
    # a probe's data is out of date, and the alerter checks it every minute.
    RULE_NAME = "metric_staleness"
    
    # The longest the whole run waits for alerts, in seconds. The alerter
    # evaluates its rules once a minute and clears an alert up to 30 seconds
    # after it fires, so this allows for waiting out the alert from an earlier
    # run, one alert that clears before the program can acknowledge it, and a
    # second evaluation.
    WAIT_SECONDS = 150
    
    # How often the program polls the alerts, in seconds.
    POLL_SECONDS = 0.5
    
    
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
        return {
            "base_url": (
                os.environ.get("WORKBENCH_URL") or "http://localhost:8080"
            ).rstrip("/"),
            "token": token,
            "connection_id": connection_id,
        }
    
    
    def api(method: str, cfg: dict, path: str, **kwargs) -> httpx.Response:
        """Sends a request to the API and returns the response.
    
        A request that the server rejects raises an error that includes the
        message from the server, which raise_for_status alone would leave out.
        """
        response = httpx.request(
            method, f"{cfg['base_url']}/api/v1{path}",
            headers={"Authorization": f"Bearer {cfg['token']}"}, timeout=30,
            **kwargs,
        )
        if response.is_error:
            raise RuntimeError(
                f"{method} {path} failed with status {response.status_code}: "
                f"{response.text.strip()}"
            )
        return response
    
    
    def find_rule(cfg: dict, name: str) -> int:
        """Returns the ID of an alert rule, given its name."""
        for rule in api("GET", cfg, "/alert-rules").json():
            if rule["name"] == name:
                return rule["id"]
        raise RuntimeError(f"There is no alert rule named '{name}'")
    
    
    def set_override(cfg: dict, rule_id: int) -> None:
        """Overrides the threshold of a rule for one server.
    
        A threshold of -1 is below any value that the staleness ratio can
        take, so the rule is violated on the next evaluation.
        """
        api("PUT", cfg,
            f"/alert-overrides/server/{cfg['connection_id']}/{rule_id}",
            json={"operator": ">", "threshold": -1, "severity": "info",
                  "enabled": True})
    
    
    def active_alerts(cfg: dict, rule_id: int) -> list:
        """Returns the active alerts that the given rule raised for the server.
    
        The request filters by server, status, and type, and asks for the most
        alerts that the API returns at once, so that the result does not depend
        on the first 100 alerts of a busy Workbench.
        """
        alerts = api("GET", cfg, "/alerts", params={
            "connection_id": cfg["connection_id"], "status": "active",
            "alert_type": "threshold", "limit": 1000,
        }).json()["alerts"]
        return [alert for alert in alerts if alert["rule_id"] == rule_id]
    
    
    def wait_until_quiet(cfg: dict, rule_id: int, deadline: float) -> None:
        """Waits until the rule has no active alert.
    
        The alerter raises no new alert for a rule while one is active, so an
        alert left by an earlier run, which clears within 30 seconds, would
        otherwise stand in for the one that this run causes.
        """
        while active_alerts(cfg, rule_id):
            if time.monotonic() >= deadline:
                raise RuntimeError("An earlier alert did not clear in time")
            time.sleep(POLL_SECONDS)
    
    
    def wait_for_alert(cfg: dict, rule_id: int, deadline: float) -> dict:
        """Polls until the given rule raises an alert, and returns it.
    
        The alert clears itself within 30 seconds of firing, so the program
        polls twice a second.
        """
        while True:
            alerts = active_alerts(cfg, rule_id)
            if alerts:
                return alerts[0]
            if time.monotonic() >= deadline:
                raise RuntimeError(
                    f"No alert was raised within {WAIT_SECONDS} seconds"
                )
            time.sleep(POLL_SECONDS)
    
    
    def acknowledge_alert(cfg: dict, alert_id: int) -> None:
        """Acknowledges an alert, with a message that the interface shows."""
        api("POST", cfg, "/alerts/acknowledge", json={
            "alert_id": alert_id, "message": "Acknowledged by the cookbook",
        })
    
    
    def acknowledged_alerts(cfg: dict) -> list:
        """Returns the acknowledged threshold alerts for the server."""
        return api("GET", cfg, "/alerts", params={
            "connection_id": cfg["connection_id"], "status": "acknowledged",
            "alert_type": "threshold", "limit": 1000,
        }).json()["alerts"]
    
    
    def alert_status(cfg: dict, alert_id: int) -> str:
        """Returns the status of an alert, found by its ID in the list of
        acknowledged alerts."""
        for alert in acknowledged_alerts(cfg):
            if alert["id"] == alert_id:
                return alert["status"]
        raise RuntimeError("The alert is missing from the acknowledged alerts")
    
    
    def unacknowledge_alert(cfg: dict, alert_id: int) -> None:
        """Returns an acknowledged alert to the active state.
    
        The alerter clears only active alerts, so an alert that stays
        acknowledged also stops the rule from raising a new one.
        """
        api("DELETE", cfg, "/alerts/acknowledge", params={"alert_id": alert_id})
    
    
    def remove_override(cfg: dict, rule_id: int) -> None:
        """Removes the override, so that the rule reverts to its default
        threshold."""
        api("DELETE", cfg,
            f"/alert-overrides/server/{cfg['connection_id']}/{rule_id}")
    
    
    def main() -> int:
        cfg = None
        override_rule = None
        acknowledged_alert = None
        status = 0
        try:
            cfg = settings()
            deadline = time.monotonic() + WAIT_SECONDS
    
            rule_id = find_rule(cfg, RULE_NAME)
            print(f"Found the rule '{RULE_NAME}'")
    
            # An alert from an earlier run may still be active.
            wait_until_quiet(cfg, rule_id, deadline)
    
            # Set the override first and remove it in the finally block, so
            # that a failed run does not leave the server raising alerts.
            override_rule = rule_id
            set_override(cfg, rule_id)
            print("Set an override that makes the rule fire")
    
            print("Waiting for the alerter to raise an alert")
            while True:
                alert = wait_for_alert(cfg, rule_id, deadline)
    
                # Record the alert before acknowledging it, so that the
                # finally block returns it to the active state even if the
                # request times out after the server has acted on it.
                acknowledged_alert = alert["id"]
                try:
                    acknowledge_alert(cfg, alert["id"])
                    break
                except (httpx.HTTPError, RuntimeError):
                    # The alerter may have cleared the alert since the poll.
                    # The override is still in place, so the rule fires again
                    # at the next evaluation; any other failure is real.
                    if any(a["id"] == alert["id"]
                           for a in active_alerts(cfg, rule_id)):
                        # The server did not acknowledge it, so there is
                        # nothing to undo.
                        acknowledged_alert = None
                        raise
                    # If the server acted on a request that timed out, the
                    # alert is acknowledged and must go back to active. When
                    # that fails, the error propagates and the finally block
                    # tries again, because acknowledged_alert is still set.
                    if any(a["id"] == alert["id"]
                           for a in acknowledged_alerts(cfg)):
                        unacknowledge_alert(cfg, alert["id"])
                    acknowledged_alert = None
                    print("The alert cleared first; waiting for the next one",
                          file=sys.stderr)
            print(f"An alert is active (severity: {alert['severity']})")
            print("Acknowledged the alert")
    
            print(f"The alert is now {alert_status(cfg, alert['id'])}")
    
            unacknowledge_alert(cfg, alert["id"])
            acknowledged_alert = None
            print("Returned the alert to the active state")
    
            remove_override(cfg, rule_id)
            override_rule = None
            print("Removed the override")
        # httpx.HTTPError covers failures to connect, and RuntimeError covers
        # replies that the server rejected or that lacked what we need.
        except (httpx.HTTPError, RuntimeError) as e:
            print(f"Error: {e}", file=sys.stderr)
            status = 1
        finally:
            # Undo the changes whether or not a step failed, so that the server
            # does not keep raising alerts or hold an acknowledged one.
            for undo, value in ((unacknowledge_alert, acknowledged_alert),
                                (remove_override, override_rule)):
                if value is None:
                    continue
                try:
                    undo(cfg, value)
                except (httpx.HTTPError, RuntimeError) as e:
                    print(f"Error: could not undo a change: {e}",
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
     * Listing and acknowledging alerts with the AI DBA Workbench API, using the
     * built-in fetch.
     *
     * Copyright (c) 2026, pgEdge, Inc.
     * This code is released under the PostgreSQL License.
     */
    
    // The program needs no imports: fetch and process are built in to Node.js.
    
    // The rule that the program makes fire. The metric_staleness rule alerts when
    // a probe's data is out of date, and the alerter checks it every minute.
    const RULE_NAME = "metric_staleness";
    
    // The longest the whole run waits for alerts, in milliseconds. The alerter
    // evaluates its rules once a minute and clears an alert up to 30 seconds
    // after it fires, so this allows for waiting out the alert from an earlier
    // run, one alert that clears before the program can acknowledge it, and a
    // second evaluation.
    const WAIT_MS = 150_000;
    
    // How often the program polls the alerts, in milliseconds.
    const POLL_MS = 500;
    
    interface Settings {
      baseUrl: string;
      token: string;
      connectionId: string;
    }
    
    // Read the settings from the environment. The || operator, unlike ??, also
    // treats an empty variable as unset.
    function settings(): Settings {
      const token = process.env.WORKBENCH_TOKEN || "";
      const connectionId = process.env.WORKBENCH_CONNECTION_ID || "";
      if (!token || !connectionId) {
        throw new Error("WORKBENCH_TOKEN and WORKBENCH_CONNECTION_ID must be set");
      }
      const baseUrl = process.env.WORKBENCH_URL || "http://localhost:8080";
      return { baseUrl: baseUrl.replace(/\/+$/, ""), token, connectionId };
    }
    
    // Sends a request to the API and returns the response. A request that the
    // server rejects throws an error that includes the message from the server.
    async function api(
      method: string,
      cfg: Settings,
      path: string,
      body?: unknown,
    ): Promise<Response> {
      const headers: Record<string, string> = {
        Authorization: `Bearer ${cfg.token}`,
      };
      if (body !== undefined) headers["Content-Type"] = "application/json";
    
      const response = await fetch(`${cfg.baseUrl}/api/v1${path}`, {
        method,
        headers,
        body: body === undefined ? undefined : JSON.stringify(body),
        signal: AbortSignal.timeout(30_000),
      });
      if (!response.ok) {
        const text = (await response.text()).trim();
        throw new Error(
          `${method} ${path} failed with status ${response.status}: ${text}`,
        );
      }
      return response;
    }
    
    interface Rule {
      id: number;
      name: string;
    }
    
    // Returns the ID of an alert rule, given its name.
    async function findRule(cfg: Settings, name: string): Promise<number> {
      const rules = (await (await api("GET", cfg, "/alert-rules")).json()) as Rule[];
      const rule = rules.find((r) => r.name === name);
      if (!rule) throw new Error(`There is no alert rule named '${name}'`);
      return rule.id;
    }
    
    // Overrides the threshold of a rule for one server. A threshold of -1 is
    // below any value that the staleness ratio can take, so the rule is violated
    // on the next evaluation.
    async function setOverride(cfg: Settings, ruleId: number): Promise<void> {
      await api(
        "PUT",
        cfg,
        `/alert-overrides/server/${cfg.connectionId}/${ruleId}`,
        { operator: ">", threshold: -1, severity: "info", enabled: true },
      );
    }
    
    interface Alert {
      id: number;
      rule_id: number;
      severity: string;
      status: string;
    }
    
    // Returns the threshold alerts for a server that have the given status. The
    // request filters by server, status, and type, and asks for the most alerts
    // that the API returns at once, so that the result does not depend on the
    // first 100 alerts of a busy Workbench.
    async function listAlerts(cfg: Settings, status: string): Promise<Alert[]> {
      const query = new URLSearchParams({
        connection_id: cfg.connectionId,
        status,
        alert_type: "threshold",
        limit: "1000",
      });
      const response = await api("GET", cfg, `/alerts?${query}`);
      return ((await response.json()) as { alerts: Alert[] }).alerts;
    }
    
    // Returns the active alerts that the given rule raised.
    async function activeAlerts(cfg: Settings, ruleId: number): Promise<Alert[]> {
      return (await listAlerts(cfg, "active")).filter((a) => a.rule_id === ruleId);
    }
    
    const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));
    
    // Waits until the rule has no active alert. The alerter raises no new alert
    // for a rule while one is active, so an alert left by an earlier run, which
    // clears within 30 seconds, would otherwise stand in for the one that this
    // run causes.
    async function waitUntilQuiet(
      cfg: Settings,
      ruleId: number,
      deadline: number,
    ): Promise<void> {
      while ((await activeAlerts(cfg, ruleId)).length > 0) {
        if (Date.now() >= deadline) {
          throw new Error("An earlier alert did not clear in time");
        }
        await sleep(POLL_MS);
      }
    }
    
    // Polls until the given rule raises an alert, and returns it. The alert
    // clears itself within 30 seconds of firing, so the program polls twice a
    // second.
    async function waitForAlert(
      cfg: Settings,
      ruleId: number,
      deadline: number,
    ): Promise<Alert> {
      for (;;) {
        const [alert] = await activeAlerts(cfg, ruleId);
        if (alert) return alert;
        if (Date.now() >= deadline) {
          throw new Error(`No alert was raised within ${WAIT_MS / 1000} seconds`);
        }
        await sleep(POLL_MS);
      }
    }
    
    // Acknowledges an alert, with a message that the interface shows.
    async function acknowledgeAlert(cfg: Settings, alertId: number): Promise<void> {
      await api("POST", cfg, "/alerts/acknowledge", {
        alert_id: alertId,
        message: "Acknowledged by the cookbook",
      });
    }
    
    // Returns the status of an alert, found by its ID in the list of
    // acknowledged alerts.
    async function alertStatus(cfg: Settings, alertId: number): Promise<string> {
      const alert = (await listAlerts(cfg, "acknowledged")).find(
        (a) => a.id === alertId,
      );
      if (!alert) {
        throw new Error("The alert is missing from the acknowledged alerts");
      }
      return alert.status;
    }
    
    // Returns an acknowledged alert to the active state. The alerter clears only
    // active alerts, so an alert that stays acknowledged also stops the rule from
    // raising a new one.
    async function unacknowledgeAlert(
      cfg: Settings,
      alertId: number,
    ): Promise<void> {
      await api("DELETE", cfg, `/alerts/acknowledge?alert_id=${alertId}`);
    }
    
    // Removes the override, so that the rule reverts to its default threshold.
    async function removeOverride(cfg: Settings, ruleId: number): Promise<void> {
      await api(
        "DELETE",
        cfg,
        `/alert-overrides/server/${cfg.connectionId}/${ruleId}`,
      );
    }
    
    const message = (err: unknown) => (err instanceof Error ? err.message : err);
    
    async function main(): Promise<number> {
      let exitCode = 0;
      // Each undo step is added when its change is made, and runs whether or not
      // a later step fails, so that the server does not keep raising alerts or
      // hold an acknowledged one.
      const undo: Array<() => Promise<void>> = [];
      try {
        const cfg = settings();
        const deadline = Date.now() + WAIT_MS;
    
        const ruleId = await findRule(cfg, RULE_NAME);
        console.log(`Found the rule '${RULE_NAME}'`);
    
        // An alert from an earlier run may still be active.
        await waitUntilQuiet(cfg, ruleId, deadline);
    
        undo.push(() => removeOverride(cfg, ruleId));
        await setOverride(cfg, ruleId);
        console.log("Set an override that makes the rule fire");
    
        console.log("Waiting for the alerter to raise an alert");
        let alert: Alert;
        for (;;) {
          alert = await waitForAlert(cfg, ruleId, deadline);
    
          // Add the undo step before acknowledging the alert, so that a request
          // that times out after the server has acted on it is still reversed.
          const alertId = alert.id;
          undo.push(() => unacknowledgeAlert(cfg, alertId));
          try {
            await acknowledgeAlert(cfg, alertId);
            break;
          } catch (err) {
            // The alerter may have cleared the alert since the poll. The
            // override is still in place, so the rule fires again at the next
            // evaluation; any other failure is real.
            if ((await activeAlerts(cfg, ruleId)).some((a) => a.id === alertId)) {
              // The server did not acknowledge it, so there is nothing to undo.
              undo.pop();
              throw err;
            }
            // If the server acted on a request that timed out, the alert is
            // acknowledged and must go back to active. When that fails, the
            // error propagates with the undo step still in place, so the
            // clean-up tries again.
            if (
              (await listAlerts(cfg, "acknowledged")).some((a) => a.id === alertId)
            ) {
              await undo[undo.length - 1]();
            }
            undo.pop();
            console.error("The alert cleared first; waiting for the next one");
          }
        }
        console.log(`An alert is active (severity: ${alert.severity})`);
        console.log("Acknowledged the alert");
    
        console.log(`The alert is now ${await alertStatus(cfg, alert.id)}`);
    
        // Run each step before removing it, so that a step which fails is still
        // there for the clean-up below to try again.
        await undo[undo.length - 1]();
        undo.pop();
        console.log("Returned the alert to the active state");
    
        await undo[undo.length - 1]();
        undo.pop();
        console.log("Removed the override");
      } catch (err) {
        console.error(`Error: ${message(err)}`);
        exitCode = 1;
      }
    
      // Run the steps that are left, most recent first.
      for (const step of undo.reverse()) {
        try {
          await step();
        } catch (err) {
          console.error(`Error: could not undo a change: ${message(err)}`);
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
     * Listing and acknowledging alerts with the AI DBA Workbench API, using
     * java.net.http and Jackson.
     *
     * Copyright (c) 2026, pgEdge, Inc.
     * This code is released under the PostgreSQL License.
     */
    
    import java.io.IOException;
    import java.net.URI;
    import java.net.URLEncoder;
    import java.net.http.HttpClient;
    import java.net.http.HttpRequest;
    import java.net.http.HttpResponse;
    import java.net.http.HttpTimeoutException;
    import java.nio.charset.StandardCharsets;
    import java.time.Duration;
    import java.util.ArrayList;
    import java.util.LinkedHashMap;
    import java.util.List;
    import java.util.Map;
    import java.util.Objects;
    import java.util.concurrent.CompletableFuture;
    import java.util.concurrent.ExecutionException;
    import java.util.concurrent.TimeUnit;
    import java.util.concurrent.TimeoutException;
    import java.util.stream.Collectors;
    import tools.jackson.core.JacksonException;
    import tools.jackson.databind.JsonNode;
    import tools.jackson.databind.ObjectMapper;
    
    public class Main {
    
        /**
         * The rule that the program makes fire. The metric_staleness rule
         * alerts when a probe's data is out of date, and the alerter checks it
         * every minute.
         */
        static final String RULE_NAME = "metric_staleness";
    
        /**
         * The longest the whole run waits for alerts. The alerter evaluates its
         * rules once a minute and clears an alert up to 30 seconds after it
         * fires, so this allows for waiting out the alert from an earlier run,
         * one alert that clears before the program can acknowledge it, and a
         * second evaluation.
         */
        static final Duration WAIT_TIME = Duration.ofSeconds(150);
    
        /** How often the program polls the alerts. */
        static final Duration POLL_INTERVAL = Duration.ofMillis(500);
    
        /** The settings that the program reads from the environment. */
        record Settings(String baseUrl, String token, String connectionId) {}
    
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
            String baseUrl = envOr("WORKBENCH_URL", "http://localhost:8080")
                    .replaceAll("/+$", "");
            return new Settings(baseUrl, token, connectionId);
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
         * Sends a request to the API and returns the JSON reply. The query
         * parameters and the body may be null. A request that the server
         * rejects throws an error that includes the message from the server.
         */
        static JsonNode api(String method, Settings cfg, String path,
                Map<String, String> params, Object body)
                throws IOException, InterruptedException {
            String url = cfg.baseUrl() + "/api/v1" + path;
            if (params != null) {
                url += "?" + params.entrySet().stream()
                        .map(p -> URLEncoder.encode(p.getKey(),
                                StandardCharsets.UTF_8) + "="
                                + URLEncoder.encode(p.getValue(),
                                        StandardCharsets.UTF_8))
                        .collect(Collectors.joining("&"));
            }
            HttpRequest.Builder request = HttpRequest.newBuilder(URI.create(url))
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
            // Some replies have no body, which reads as a missing node.
            return JSON.readTree(response.body());
        }
    
        /** Returns the ID of an alert rule, given its name. */
        static long findRule(Settings cfg, String name)
                throws IOException, InterruptedException {
            for (JsonNode rule : api("GET", cfg, "/alert-rules", null, null)) {
                if (name.equals(rule.path("name").asString())) {
                    return rule.get("id").asLong();
                }
            }
            throw new IOException("There is no alert rule named '" + name + "'");
        }
    
        /**
         * Overrides the threshold of a rule for one server. A threshold of -1
         * is below any value that the staleness ratio can take, so the rule is
         * violated on the next evaluation.
         */
        static void setOverride(Settings cfg, long ruleId)
                throws IOException, InterruptedException {
            api("PUT", cfg, "/alert-overrides/server/" + cfg.connectionId()
                    + "/" + ruleId, null, Map.of(
                            "operator", ">",
                            "threshold", -1,
                            "severity", "info",
                            "enabled", true));
        }
    
        /**
         * Returns the threshold alerts for the server that have the given
         * status. The request asks for the most alerts that the API returns at
         * once, so that the result does not depend on the first 100 alerts of
         * a busy Workbench.
         */
        static List<JsonNode> listAlerts(Settings cfg, String status)
                throws IOException, InterruptedException {
            Map<String, String> params = new LinkedHashMap<>();
            params.put("connection_id", cfg.connectionId());
            params.put("status", status);
            params.put("alert_type", "threshold");
            params.put("limit", "1000");
            List<JsonNode> alerts = new ArrayList<>();
            api("GET", cfg, "/alerts", params, null).path("alerts")
                    .forEach(alerts::add);
            return alerts;
        }
    
        /** Returns the active alerts that the given rule raised for the server. */
        static List<JsonNode> activeAlerts(Settings cfg, long ruleId)
                throws IOException, InterruptedException {
            List<JsonNode> alerts = listAlerts(cfg, "active");
            alerts.removeIf(alert -> alert.path("rule_id").asLong() != ruleId);
            return alerts;
        }
    
        /**
         * Waits until the rule has no active alert. The alerter raises no new
         * alert for a rule while one is active, so an alert left by an earlier
         * run, which clears within 30 seconds, would otherwise stand in for the
         * one that this run causes.
         */
        static void waitUntilQuiet(Settings cfg, long ruleId, long deadline)
                throws IOException, InterruptedException {
            while (!activeAlerts(cfg, ruleId).isEmpty()) {
                if (System.nanoTime() - deadline >= 0) {
                    throw new IOException("An earlier alert did not clear in time");
                }
                Thread.sleep(POLL_INTERVAL.toMillis());
            }
        }
    
        /**
         * Polls until the given rule raises an alert, and returns it. The alert
         * clears itself within 30 seconds of firing, so the program polls twice
         * a second.
         */
        static JsonNode waitForAlert(Settings cfg, long ruleId, long deadline)
                throws IOException, InterruptedException {
            while (true) {
                List<JsonNode> alerts = activeAlerts(cfg, ruleId);
                if (!alerts.isEmpty()) {
                    return alerts.get(0);
                }
                if (System.nanoTime() - deadline >= 0) {
                    throw new IOException("No alert was raised within "
                            + WAIT_TIME.toSeconds() + " seconds");
                }
                Thread.sleep(POLL_INTERVAL.toMillis());
            }
        }
    
        /** Acknowledges an alert, with a message that the interface shows. */
        static void acknowledgeAlert(Settings cfg, long alertId)
                throws IOException, InterruptedException {
            api("POST", cfg, "/alerts/acknowledge", null, Map.of(
                    "alert_id", alertId,
                    "message", "Acknowledged by the cookbook"));
        }
    
        /**
         * Returns the status of an alert, found by its ID in the list of
         * acknowledged alerts.
         */
        static String alertStatus(Settings cfg, long alertId)
                throws IOException, InterruptedException {
            for (JsonNode alert : listAlerts(cfg, "acknowledged")) {
                if (alert.path("id").asLong() == alertId) {
                    return alert.get("status").asString();
                }
            }
            throw new IOException(
                    "The alert is missing from the acknowledged alerts");
        }
    
        /**
         * Returns an acknowledged alert to the active state. The alerter clears
         * only active alerts, so an alert that stays acknowledged also stops
         * the rule from raising a new one.
         */
        static void unacknowledgeAlert(Settings cfg, long alertId)
                throws IOException, InterruptedException {
            api("DELETE", cfg, "/alerts/acknowledge",
                    Map.of("alert_id", Long.toString(alertId)), null);
        }
    
        /**
         * Removes the override, so that the rule reverts to its default
         * threshold.
         */
        static void removeOverride(Settings cfg, long ruleId)
                throws IOException, InterruptedException {
            api("DELETE", cfg, "/alert-overrides/server/" + cfg.connectionId()
                    + "/" + ruleId, null, null);
        }
    
        /** Reports whether a list of alerts includes the one with an ID. */
        static boolean contains(List<JsonNode> alerts, long alertId) {
            return alerts.stream()
                    .anyMatch(a -> a.path("id").asLong() == alertId);
        }
    
        /**
         * Returns the message of an error. Some errors, such as a refused
         * connection, have no message, so their type stands in for one.
         */
        static String describe(Exception e) {
            return Objects.requireNonNullElse(e.getMessage(), e.toString());
        }
    
        public static void main(String[] args) {
            Settings cfg = null;
            Long overrideRule = null;
            Long acknowledgedAlert = null;
            int status = 0;
            try {
                cfg = settings();
                long deadline = System.nanoTime() + WAIT_TIME.toNanos();
    
                long ruleId = findRule(cfg, RULE_NAME);
                System.out.println("Found the rule '" + RULE_NAME + "'");
    
                // An alert from an earlier run may still be active.
                waitUntilQuiet(cfg, ruleId, deadline);
    
                // Record the override first and remove it at the end, so that
                // a failed run does not leave the server raising alerts.
                overrideRule = ruleId;
                setOverride(cfg, ruleId);
                System.out.println("Set an override that makes the rule fire");
    
                System.out.println("Waiting for the alerter to raise an alert");
                JsonNode alert;
                while (true) {
                    alert = waitForAlert(cfg, ruleId, deadline);
                    long alertId = alert.get("id").asLong();
    
                    // Record the alert before acknowledging it, so that the
                    // clean-up returns it to the active state even if the
                    // request times out after the server has acted on it.
                    acknowledgedAlert = alertId;
                    try {
                        acknowledgeAlert(cfg, alertId);
                        break;
                    } catch (IOException e) {
                        // The alerter may have cleared the alert since the
                        // poll. The override is still in place, so the rule
                        // fires again at the next evaluation; any other
                        // failure is real.
                        if (contains(activeAlerts(cfg, ruleId), alertId)) {
                            // The server did not acknowledge it, so there is
                            // nothing to undo.
                            acknowledgedAlert = null;
                            throw e;
                        }
                        // If the server acted on a request that timed out, the
                        // alert is acknowledged and must go back to active.
                        // When that fails, the error propagates and the
                        // clean-up tries again, because acknowledgedAlert is
                        // still set.
                        if (contains(listAlerts(cfg, "acknowledged"), alertId)) {
                            unacknowledgeAlert(cfg, alertId);
                        }
                        acknowledgedAlert = null;
                        System.err.println(
                                "The alert cleared first; waiting for the next one");
                    }
                }
                long alertId = alert.get("id").asLong();
                System.out.println("An alert is active (severity: "
                        + alert.get("severity").asString() + ")");
                System.out.println("Acknowledged the alert");
    
                System.out.println("The alert is now "
                        + alertStatus(cfg, alertId));
    
                unacknowledgeAlert(cfg, alertId);
                acknowledgedAlert = null;
                System.out.println("Returned the alert to the active state");
    
                removeOverride(cfg, ruleId);
                overrideRule = null;
                System.out.println("Removed the override");
            // IOException covers failures to connect, replies that the server
            // rejected, and replies that lacked what we need; the client
            // throws InterruptedException if the thread is interrupted, and
            // Jackson throws JacksonException for a reply that is not JSON.
            } catch (IOException | InterruptedException | JacksonException e) {
                System.err.println("Error: " + describe(e));
                status = 1;
            } finally {
                // Undo the changes whether or not a step failed, so that the
                // server does not keep raising alerts or hold an acknowledged one.
                // The finally block also runs for an error that the catch does not
                // handle.
                if (acknowledgedAlert != null) {
                    try {
                        unacknowledgeAlert(cfg, acknowledgedAlert);
                    } catch (IOException | InterruptedException
                            | JacksonException e) {
                        System.err.println("Error: could not undo a change: "
                                + describe(e));
                        status = 1;
                    }
                }
                if (overrideRule != null) {
                    try {
                        removeOverride(cfg, overrideRule);
                    } catch (IOException | InterruptedException
                            | JacksonException e) {
                        System.err.println("Error: could not undo a change: "
                                + describe(e));
                        status = 1;
                    }
                }
            }
            System.exit(status);
        }
    }
    
    ```

=== "C#"

    ```csharp
    /*
     * Ellie's Postgres Cookbook
     * Listing and acknowledging alerts with the AI DBA Workbench API, using
     * HttpClient and System.Text.Json.
     *
     * Copyright (c) 2026, pgEdge, Inc.
     * This code is released under the PostgreSQL License.
     */
    
    using System.Diagnostics;
    using System.Net.Http.Headers;
    using System.Net.Http.Json;
    using System.Text.Json;
    using System.Text.Json.Nodes;
    
    // The rule that the program makes fire. The metric_staleness rule alerts
    // when a probe's data is out of date, and the alerter checks it every
    // minute.
    const string RuleName = "metric_staleness";
    
    // The longest the whole run waits for alerts. The alerter evaluates its
    // rules once a minute and clears an alert up to 30 seconds after it fires,
    // so this allows for waiting out the alert from an earlier run, one alert
    // that clears before the program can acknowledge it, and a second
    // evaluation.
    var waitTime = TimeSpan.FromSeconds(150);
    
    // How often the program polls the alerts.
    var pollInterval = TimeSpan.FromMilliseconds(500);
    
    // Returns the value of an environment variable, or null if the variable
    // is unset or empty, as an unset variable would be.
    static string? EnvValue(string name) =>
        Environment.GetEnvironmentVariable(name) is { Length: > 0 } value
            ? value
            : null;
    
    // Reads the settings from the environment.
    static (string BaseUrl, string Token, string ConnectionId) Settings()
    {
        var token = EnvValue("WORKBENCH_TOKEN");
        var connectionId = EnvValue("WORKBENCH_CONNECTION_ID");
        if (token is null || connectionId is null)
        {
            throw new InvalidOperationException(
                "WORKBENCH_TOKEN and WORKBENCH_CONNECTION_ID must be set");
        }
        var baseUrl = EnvValue("WORKBENCH_URL") ?? "http://localhost:8080";
        return (baseUrl.TrimEnd('/'), token, connectionId);
    }
    
    // One client serves every request, with a timeout for each.
    var http = new HttpClient { Timeout = TimeSpan.FromSeconds(30) };
    var cfg = (BaseUrl: "", Token: "", ConnectionId: "");
    
    // Sends a request to the API and returns the JSON reply, or null if the
    // reply has no body. The path may include a query string. A request that
    // the server rejects throws an error that includes the message from the
    // server.
    async Task<JsonNode?> Api(string method, string path, object? body = null)
    {
        using var request = new HttpRequestMessage(
            new HttpMethod(method), $"{cfg.BaseUrl}/api/v1{path}");
        request.Headers.Authorization =
            new AuthenticationHeaderValue("Bearer", cfg.Token);
        if (body is not null)
        {
            request.Content = JsonContent.Create(body);
        }
    
        using var response = await http.SendAsync(request);
        var text = await response.Content.ReadAsStringAsync();
        if ((int)response.StatusCode >= 400)
        {
            throw new HttpRequestException(
                $"{method} {path} failed with status {(int)response.StatusCode}: "
                + text.Trim());
        }
        return text.Length == 0 ? null : JsonNode.Parse(text);
    }
    
    // Returns the ID of an alert rule, given its name.
    async Task<long> FindRule(string name)
    {
        var rules = (await Api("GET", "/alert-rules"))?.AsArray()
            ?? throw new InvalidOperationException("The reply had no rules");
        var rule = rules.FirstOrDefault(
            r => r?["name"]?.GetValue<string>() == name)
            ?? throw new InvalidOperationException(
                $"There is no alert rule named '{name}'");
        return rule["id"]!.GetValue<long>();
    }
    
    // Overrides the threshold of a rule for one server. A threshold of -1 is
    // below any value that the staleness ratio can take, so the rule is
    // violated on the next evaluation.
    async Task SetOverride(long ruleId) =>
        await Api("PUT", $"/alert-overrides/server/{cfg.ConnectionId}/{ruleId}",
            new { @operator = ">", threshold = -1, severity = "info",
                enabled = true });
    
    // Returns the threshold alerts for the server that have the given status.
    // The request asks for the most alerts that the API returns at once, so
    // that the result does not depend on the first 100 alerts of a busy
    // Workbench.
    async Task<List<JsonNode>> ListAlerts(string status)
    {
        var query = $"connection_id={Uri.EscapeDataString(cfg.ConnectionId)}"
            + $"&status={status}&alert_type=threshold&limit=1000";
        var reply = await Api("GET", $"/alerts?{query}");
        return reply?["alerts"]?.AsArray().OfType<JsonNode>().ToList()
            ?? throw new InvalidOperationException("The reply had no alerts");
    }
    
    // Returns the active alerts that the given rule raised for the server.
    async Task<List<JsonNode>> ActiveAlerts(long ruleId) =>
        (await ListAlerts("active"))
            .Where(a => a["rule_id"]?.GetValue<long>() == ruleId)
            .ToList();
    
    // Waits until the rule has no active alert. The alerter raises no new
    // alert for a rule while one is active, so an alert left by an earlier
    // run, which clears within 30 seconds, would otherwise stand in for the
    // one that this run causes.
    async Task WaitUntilQuiet(long ruleId, Stopwatch clock)
    {
        while ((await ActiveAlerts(ruleId)).Count > 0)
        {
            if (clock.Elapsed >= waitTime)
            {
                throw new InvalidOperationException(
                    "An earlier alert did not clear in time");
            }
            await Task.Delay(pollInterval);
        }
    }
    
    // Polls until the given rule raises an alert, and returns it. The alert
    // clears itself within 30 seconds of firing, so the program polls twice a
    // second.
    async Task<JsonNode> WaitForAlert(long ruleId, Stopwatch clock)
    {
        while (true)
        {
            var alerts = await ActiveAlerts(ruleId);
            if (alerts.Count > 0)
            {
                return alerts[0];
            }
            if (clock.Elapsed >= waitTime)
            {
                throw new InvalidOperationException(
                    $"No alert was raised within {waitTime.TotalSeconds} seconds");
            }
            await Task.Delay(pollInterval);
        }
    }
    
    // Acknowledges an alert, with a message that the interface shows.
    async Task AcknowledgeAlert(long alertId) =>
        await Api("POST", "/alerts/acknowledge",
            new { alert_id = alertId, message = "Acknowledged by the cookbook" });
    
    // Returns the status of an alert, found by its ID in the list of
    // acknowledged alerts.
    async Task<string> AlertStatus(long alertId)
    {
        var alert = (await ListAlerts("acknowledged"))
            .FirstOrDefault(a => a["id"]?.GetValue<long>() == alertId)
            ?? throw new InvalidOperationException(
                "The alert is missing from the acknowledged alerts");
        return alert["status"]!.GetValue<string>();
    }
    
    // Returns an acknowledged alert to the active state. The alerter clears
    // only active alerts, so an alert that stays acknowledged also stops the
    // rule from raising a new one.
    async Task UnacknowledgeAlert(long alertId) =>
        await Api("DELETE", $"/alerts/acknowledge?alert_id={alertId}");
    
    // Removes the override, so that the rule reverts to its default threshold.
    async Task RemoveOverride(long ruleId) =>
        await Api("DELETE",
            $"/alert-overrides/server/{cfg.ConnectionId}/{ruleId}");
    
    // Reports whether an error is one that the program expects: a failure to
    // connect, a reply that the server rejected, a request that timed out, or
    // a reply that lacked what we need.
    static bool Expected(Exception e) => e is HttpRequestException
        or TaskCanceledException or InvalidOperationException or JsonException;
    
    // Reports whether a list of alerts includes the one with an ID.
    static bool Contains(List<JsonNode> alerts, long alertId) =>
        alerts.Any(a => a["id"]?.GetValue<long>() == alertId);
    
    long? overrideRule = null;
    long? acknowledgedAlert = null;
    var status = 0;
    try
    {
        cfg = Settings();
        var clock = Stopwatch.StartNew();
    
        var ruleId = await FindRule(RuleName);
        Console.WriteLine($"Found the rule '{RuleName}'");
    
        // An alert from an earlier run may still be active.
        await WaitUntilQuiet(ruleId, clock);
    
        // Record the override first and remove it at the end, so that a
        // failed run does not leave the server raising alerts.
        overrideRule = ruleId;
        await SetOverride(ruleId);
        Console.WriteLine("Set an override that makes the rule fire");
    
        Console.WriteLine("Waiting for the alerter to raise an alert");
        JsonNode alert;
        while (true)
        {
            alert = await WaitForAlert(ruleId, clock);
            var raisedId = alert["id"]!.GetValue<long>();
    
            // Record the alert before acknowledging it, so that the clean-up
            // returns it to the active state even if the request times out
            // after the server has acted on it.
            acknowledgedAlert = raisedId;
            try
            {
                await AcknowledgeAlert(raisedId);
                break;
            }
            catch (Exception e) when (Expected(e))
            {
                // The alerter may have cleared the alert since the poll. The
                // override is still in place, so the rule fires again at the
                // next evaluation; any other failure is real.
                if (Contains(await ActiveAlerts(ruleId), raisedId))
                {
                    // The server did not acknowledge it, so there is nothing
                    // to undo.
                    acknowledgedAlert = null;
                    throw;
                }
                // If the server acted on a request that timed out, the alert
                // is acknowledged and must go back to active. When that fails,
                // the error propagates and the clean-up tries again, because
                // acknowledgedAlert is still set.
                if (Contains(await ListAlerts("acknowledged"), raisedId))
                {
                    await UnacknowledgeAlert(raisedId);
                }
                acknowledgedAlert = null;
                Console.Error.WriteLine(
                    "The alert cleared first; waiting for the next one");
            }
        }
        var alertId = alert["id"]!.GetValue<long>();
        Console.WriteLine(
            $"An alert is active (severity: {alert["severity"]})");
        Console.WriteLine("Acknowledged the alert");
    
        Console.WriteLine($"The alert is now {await AlertStatus(alertId)}");
    
        await UnacknowledgeAlert(alertId);
        acknowledgedAlert = null;
        Console.WriteLine("Returned the alert to the active state");
    
        await RemoveOverride(ruleId);
        overrideRule = null;
        Console.WriteLine("Removed the override");
    }
    catch (Exception e) when (Expected(e))
    {
        Console.Error.WriteLine($"Error: {e.Message}");
        status = 1;
    }
    finally
    {
        // Undo the changes whether or not a step failed, so that the server does
        // not keep raising alerts or hold an acknowledged one. The finally block
        // also runs for an error that the catch does not handle.
        var undo = new List<Func<Task>>();
        if (acknowledgedAlert is long pendingAlert)
        {
            undo.Add(() => UnacknowledgeAlert(pendingAlert));
        }
        if (overrideRule is long pendingRule)
        {
            undo.Add(() => RemoveOverride(pendingRule));
        }
        foreach (var step in undo)
        {
            try
            {
                await step();
            }
            catch (Exception e) when (Expected(e))
            {
                Console.Error.WriteLine(
                    $"Error: could not undo a change: {e.Message}");
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
     * Listing and acknowledging alerts with the AI DBA Workbench API, using
     * net/http.
     *
     * Copyright (c) 2026, pgEdge, Inc.
     * This code is released under the PostgreSQL License.
     */
    
    package main
    
    import (
    	"bytes"
    	"encoding/json"
    	"errors"
    	"fmt"
    	"io"
    	"net/http"
    	"net/url"
    	"os"
    	"strings"
    	"time"
    )
    
    
    // ruleName is the rule that the program makes fire. The metric_staleness
    // rule alerts when a probe's data is out of date, and the alerter checks it
    // every minute.
    const ruleName = "metric_staleness"
    
    // waitTime is the longest the whole run waits for alerts. The alerter
    // evaluates its rules once a minute and clears an alert up to 30 seconds
    // after it fires, so this allows for waiting out the alert from an earlier
    // run, one alert that clears before the program can acknowledge it, and a
    // second evaluation.
    const waitTime = 150 * time.Second
    
    // pollTime is how often the program polls the alerts.
    const pollTime = 500 * time.Millisecond
    
    // settings holds the values that the program reads from the environment.
    type settings struct {
    	baseURL      string
    	token        string
    	connectionID string
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
    		baseURL:      strings.TrimRight(envOr("WORKBENCH_URL", "http://localhost:8080"), "/"),
    		token:        os.Getenv("WORKBENCH_TOKEN"),
    		connectionID: os.Getenv("WORKBENCH_CONNECTION_ID"),
    	}
    	if s.token == "" || s.connectionID == "" {
    		return s, errors.New("WORKBENCH_TOKEN and WORKBENCH_CONNECTION_ID must be set")
    	}
    	return s, nil
    }
    
    
    // client gives every request a timeout; the default client has none.
    var client = &http.Client{Timeout: 30 * time.Second}
    
    // api sends a request to the API and decodes the JSON reply into out, if
    // given. A request that the server rejects returns an error that includes
    // the message from the server.
    func api(s settings, method, path string, body, out any) error {
    	var reader io.Reader
    	if body != nil {
    		encoded, err := json.Marshal(body)
    		if err != nil {
    			return err
    		}
    		reader = bytes.NewReader(encoded)
    	}
    
    	req, err := http.NewRequest(method, s.baseURL+"/api/v1"+path, reader)
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
    
    
    // findRule returns the ID of an alert rule, given its name.
    func findRule(s settings, name string) (int64, error) {
    	var rules []struct {
    		ID   int64  `json:"id"`
    		Name string `json:"name"`
    	}
    	if err := api(s, "GET", "/alert-rules", nil, &rules); err != nil {
    		return 0, err
    	}
    	for _, rule := range rules {
    		if rule.Name == name {
    			return rule.ID, nil
    		}
    	}
    	return 0, fmt.Errorf("there is no alert rule named '%s'", name)
    }
    
    
    // setOverride overrides the threshold of a rule for one server. A threshold
    // of -1 is below any value that the staleness ratio can take, so the rule is
    // violated on the next evaluation.
    func setOverride(s settings, ruleID int64) error {
    	path := fmt.Sprintf("/alert-overrides/server/%s/%d", s.connectionID, ruleID)
    	return api(s, "PUT", path, map[string]any{
    		"operator": ">", "threshold": -1, "severity": "info", "enabled": true,
    	}, nil)
    }
    
    
    // alert is the part of an alert that the program needs.
    type alert struct {
    	ID       int64  `json:"id"`
    	RuleID   int64  `json:"rule_id"`
    	Severity string `json:"severity"`
    	Status   string `json:"status"`
    }
    
    // listAlerts returns the threshold alerts for a server that have the given
    // status. The request filters by server, status, and type, and asks for the
    // most alerts that the API returns at once, so that the result does not
    // depend on the first 100 alerts of a busy Workbench.
    func listAlerts(s settings, status string) ([]alert, error) {
    	query := url.Values{
    		"connection_id": {s.connectionID},
    		"status":        {status},
    		"alert_type":    {"threshold"},
    		"limit":         {"1000"},
    	}
    	var result struct {
    		Alerts []alert `json:"alerts"`
    	}
    	err := api(s, "GET", "/alerts?"+query.Encode(), nil, &result)
    	return result.Alerts, err
    }
    
    // activeAlerts returns the active alerts that the given rule raised.
    func activeAlerts(s settings, ruleID int64) ([]alert, error) {
    	alerts, err := listAlerts(s, "active")
    	var raised []alert
    	for _, a := range alerts {
    		if a.RuleID == ruleID {
    			raised = append(raised, a)
    		}
    	}
    	return raised, err
    }
    
    // waitUntilQuiet waits until the rule has no active alert. The alerter
    // raises no new alert for a rule while one is active, so an alert left by an
    // earlier run, which clears within 30 seconds, would otherwise stand in for
    // the one that this run causes.
    func waitUntilQuiet(s settings, ruleID int64, deadline time.Time) error {
    	for {
    		raised, err := activeAlerts(s, ruleID)
    		if err != nil {
    			return err
    		}
    		if len(raised) == 0 {
    			return nil
    		}
    		if time.Now().After(deadline) {
    			return errors.New("an earlier alert did not clear in time")
    		}
    		time.Sleep(pollTime)
    	}
    }
    
    // waitForAlert polls until the given rule raises an alert, and returns it.
    // The alert clears itself within 30 seconds of firing, so the program polls
    // twice a second.
    func waitForAlert(s settings, ruleID int64, deadline time.Time) (alert, error) {
    	for {
    		raised, err := activeAlerts(s, ruleID)
    		if err != nil {
    			return alert{}, err
    		}
    		if len(raised) > 0 {
    			return raised[0], nil
    		}
    		if time.Now().After(deadline) {
    			return alert{}, fmt.Errorf("no alert was raised within %s", waitTime)
    		}
    		time.Sleep(pollTime)
    	}
    }
    
    
    // acknowledgeAlert acknowledges an alert, with a message that the interface
    // shows.
    func acknowledgeAlert(s settings, alertID int64) error {
    	return api(s, "POST", "/alerts/acknowledge", map[string]any{
    		"alert_id": alertID,
    		"message":  "Acknowledged by the cookbook",
    	}, nil)
    }
    
    
    // alertStatus returns the status of an alert, found by its ID in the list of
    // acknowledged alerts.
    func alertStatus(s settings, alertID int64) (string, error) {
    	alerts, err := listAlerts(s, "acknowledged")
    	if err != nil {
    		return "", err
    	}
    	for _, a := range alerts {
    		if a.ID == alertID {
    			return a.Status, nil
    		}
    	}
    	return "", errors.New("the alert is missing from the acknowledged alerts")
    }
    
    
    // unacknowledgeAlert returns an acknowledged alert to the active state. The
    // alerter clears only active alerts, so an alert that stays acknowledged
    // also stops the rule from raising a new one.
    func unacknowledgeAlert(s settings, alertID int64) error {
    	return api(s, "DELETE", fmt.Sprintf("/alerts/acknowledge?alert_id=%d", alertID), nil, nil)
    }
    
    
    // removeOverride removes the override, so that the rule reverts to its
    // default threshold.
    func removeOverride(s settings, ruleID int64) error {
    	path := fmt.Sprintf("/alert-overrides/server/%s/%d", s.connectionID, ruleID)
    	return api(s, "DELETE", path, nil, nil)
    }
    
    
    // run does the work. Each time it makes a change it adds a step to undo, and
    // removes the step again once the program has reversed the change itself.
    func run(s settings, undo *[]func() error) error {
    	deadline := time.Now().Add(waitTime)
    
    	ruleID, err := findRule(s, ruleName)
    	if err != nil {
    		return err
    	}
    	fmt.Printf("Found the rule '%s'\n", ruleName)
    
    	// An alert from an earlier run may still be active.
    	if err := waitUntilQuiet(s, ruleID, deadline); err != nil {
    		return err
    	}
    
    	*undo = append(*undo, func() error { return removeOverride(s, ruleID) })
    	if err := setOverride(s, ruleID); err != nil {
    		return err
    	}
    	fmt.Println("Set an override that makes the rule fire")
    
    	fmt.Println("Waiting for the alerter to raise an alert")
    	var raised alert
    	for {
    		raised, err = waitForAlert(s, ruleID, deadline)
    		if err != nil {
    			return err
    		}
    
    		// Add the undo step before acknowledging the alert, so that a
    		// request that times out after the server has acted on it is still
    		// reversed.
    		*undo = append(*undo, func() error { return unacknowledgeAlert(s, raised.ID) })
    		err = acknowledgeAlert(s, raised.ID)
    		if err == nil {
    			break
    		}
    
    		// The alerter may have cleared the alert since the poll. The
    		// override is still in place, so the rule fires again at the next
    		// evaluation; any other failure is real.
    		stillActive, listErr := activeAlerts(s, ruleID)
    		for _, a := range stillActive {
    			if a.ID == raised.ID {
    				// The server did not acknowledge it, so there is nothing
    				// to undo.
    				*undo = (*undo)[:len(*undo)-1]
    				return err
    			}
    		}
    		if listErr != nil {
    			return listErr
    		}
    		// If the server acted on a request that timed out, the alert is
    		// acknowledged and must go back to active. When that fails, the
    		// undo step stays in place, so the clean-up tries again.
    		acknowledged, listErr := listAlerts(s, "acknowledged")
    		if listErr != nil {
    			return listErr
    		}
    		for _, a := range acknowledged {
    			if a.ID == raised.ID {
    				if err := unacknowledgeAlert(s, raised.ID); err != nil {
    					return err
    				}
    				break
    			}
    		}
    		*undo = (*undo)[:len(*undo)-1]
    		fmt.Fprintln(os.Stderr, "The alert cleared first; waiting for the next one")
    	}
    	fmt.Printf("An alert is active (severity: %s)\n", raised.Severity)
    	fmt.Println("Acknowledged the alert")
    
    	status, err := alertStatus(s, raised.ID)
    	if err != nil {
    		return err
    	}
    	fmt.Println("The alert is now", status)
    
    	if err := unacknowledgeAlert(s, raised.ID); err != nil {
    		return err
    	}
    	*undo = (*undo)[:len(*undo)-1]
    	fmt.Println("Returned the alert to the active state")
    
    	if err := removeOverride(s, ruleID); err != nil {
    		return err
    	}
    	*undo = (*undo)[:len(*undo)-1]
    	fmt.Println("Removed the override")
    	return nil
    }
    
    func main() {
    	s, err := loadSettings()
    	if err != nil {
    		fmt.Fprintln(os.Stderr, "Error:", err)
    		os.Exit(1)
    	}
    
    	// Undo the changes whether or not a step failed, so that the server does
    	// not keep raising alerts or hold an acknowledged one.
    	var undo []func() error
    	failed := false
    	if err := run(s, &undo); err != nil {
    		fmt.Fprintln(os.Stderr, "Error:", err)
    		failed = true
    	}
    	for i := len(undo) - 1; i >= 0; i-- {
    		if err := undo[i](); err != nil {
    			fmt.Fprintln(os.Stderr, "Error: could not undo a change:", err)
    			failed = true
    		}
    	}
    	if failed {
    		os.Exit(1)
    	}
    }
    
    
    ```

=== "Rust"

    ```rust
    // Ellie's Postgres Cookbook
    // Listing and acknowledging alerts with the AI DBA Workbench API, using
    // reqwest and serde_json.
    //
    // Copyright (c) 2026, pgEdge, Inc.
    // This code is released under the PostgreSQL License.
    
    use std::env;
    use std::error::Error;
    use std::process::ExitCode;
    use std::sync::LazyLock;
    use std::thread;
    use std::time::{Duration, Instant};
    
    use reqwest::blocking::Client;
    use reqwest::{Method, Url};
    use serde_json::{json, Value};
    
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
    
    /// Returns the ID of an alert rule, given its name.
    fn find_rule(cfg: &Settings, name: &str) -> Result<i64> {
        let rules = api(Method::GET, cfg, "/alert-rules", &[], None)?;
        rules
            .as_array()
            .and_then(|rules| rules.iter().find(|r| r["name"] == name))
            .and_then(|rule| rule["id"].as_i64())
            .ok_or_else(|| format!("there is no alert rule named '{name}'").into())
    }
    
    /// Overrides the threshold of a rule for one server. A threshold of -1 is
    /// below any value that the staleness ratio can take, so the rule is
    /// violated on the next evaluation.
    fn set_override(cfg: &Settings, rule_id: i64) -> Result<()> {
        let path = format!("/alert-overrides/server/{}/{rule_id}", cfg.connection_id);
        let body = json!({ "operator": ">", "threshold": -1, "severity": "info", "enabled": true });
        api(Method::PUT, cfg, &path, &[], Some(&body))?;
        Ok(())
    }
    
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
    
    /// Acknowledges an alert, with a message that the interface shows.
    fn acknowledge_alert(cfg: &Settings, alert_id: i64) -> Result<()> {
        let body = json!({ "alert_id": alert_id, "message": "Acknowledged by the cookbook" });
        api(Method::POST, cfg, "/alerts/acknowledge", &[], Some(&body))?;
        Ok(())
    }
    
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
    
    /// Removes the override, so that the rule reverts to its default
    /// threshold.
    fn remove_override(cfg: &Settings, rule_id: i64) -> Result<()> {
        let path = format!("/alert-overrides/server/{}/{rule_id}", cfg.connection_id);
        api(Method::DELETE, cfg, &path, &[], None)?;
        Ok(())
    }
    
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
    
    ```

=== "Ruby"

    ```ruby
    # Ellie's Postgres Cookbook
    # Listing and acknowledging alerts with the AI DBA Workbench API, using
    # Net::HTTP.
    #
    # Copyright (c) 2026, pgEdge, Inc.
    # This code is released under the PostgreSQL License.
    
    require "json"
    require "net/http"
    
    # The rule that the program makes fire. The metric_staleness rule alerts
    # when a probe's data is out of date, and the alerter checks it every
    # minute.
    RULE_NAME = "metric_staleness"
    
    # The longest the whole run waits for alerts, in seconds. The alerter
    # evaluates its rules once a minute and clears an alert up to 30 seconds
    # after it fires, so this allows for waiting out the alert from an earlier
    # run, one alert that clears before the program can acknowledge it, and a
    # second evaluation.
    WAIT_SECONDS = 150
    
    # How often the program polls the alerts, in seconds.
    POLL_SECONDS = 0.5
    
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
    
      {
        base_url: env_or("WORKBENCH_URL", "http://localhost:8080").sub(%r{/+\z}, ""),
        token: token,
        connection_id: connection_id
      }
    end
    
    # Sends a request to the API and returns the decoded reply, or nil if the
    # reply has no body. The query parameters and the body are optional. A
    # request that the server rejects raises an error that includes the
    # message from the server.
    def api(method, cfg, path, params: nil, body: nil)
      uri = URI("#{cfg[:base_url]}/api/v1#{path}")
      uri.query = URI.encode_www_form(params) if params
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
    
    # Returns the ID of an alert rule, given its name.
    def find_rule(cfg, name)
      rule = api("GET", cfg, "/alert-rules").find { |r| r["name"] == name }
      raise "There is no alert rule named '#{name}'" if rule.nil?
    
      rule.fetch("id")
    end
    
    # Overrides the threshold of a rule for one server. A threshold of -1 is
    # below any value that the staleness ratio can take, so the rule is
    # violated on the next evaluation.
    def set_override(cfg, rule_id)
      api("PUT", cfg, "/alert-overrides/server/#{cfg[:connection_id]}/#{rule_id}",
          body: { operator: ">", threshold: -1, severity: "info", enabled: true })
    end
    
    # Returns the threshold alerts for the server that have the given status.
    # The request asks for the most alerts that the API returns at once, so
    # that the result does not depend on the first 100 alerts of a busy
    # Workbench.
    def list_alerts(cfg, status)
      api("GET", cfg, "/alerts", params: {
            connection_id: cfg[:connection_id], status: status,
            alert_type: "threshold", limit: 1000
          }).fetch("alerts")
    end
    
    # Returns the active alerts that the given rule raised for the server.
    def active_alerts(cfg, rule_id)
      list_alerts(cfg, "active").select { |alert| alert["rule_id"] == rule_id }
    end
    
    # Returns the seconds on a clock that only moves forwards, for deadlines.
    def now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
    
    # Waits until the rule has no active alert. The alerter raises no new alert
    # for a rule while one is active, so an alert left by an earlier run, which
    # clears within 30 seconds, would otherwise stand in for the one that this
    # run causes.
    def wait_until_quiet(cfg, rule_id, deadline)
      until active_alerts(cfg, rule_id).empty?
        raise "An earlier alert did not clear in time" if now >= deadline
    
        sleep POLL_SECONDS
      end
    end
    
    # Polls until the given rule raises an alert, and returns it. The alert
    # clears itself within 30 seconds of firing, so the program polls twice a
    # second.
    def wait_for_alert(cfg, rule_id, deadline)
      loop do
        alert = active_alerts(cfg, rule_id).first
        return alert if alert
        raise "No alert was raised within #{WAIT_SECONDS} seconds" if now >= deadline
    
        sleep POLL_SECONDS
      end
    end
    
    # Acknowledges an alert, with a message that the interface shows.
    def acknowledge_alert(cfg, alert_id)
      api("POST", cfg, "/alerts/acknowledge",
          body: { alert_id: alert_id, message: "Acknowledged by the cookbook" })
    end
    
    # Returns the status of an alert, found by its ID in the list of
    # acknowledged alerts.
    def alert_status(cfg, alert_id)
      alert = list_alerts(cfg, "acknowledged").find { |a| a["id"] == alert_id }
      raise "The alert is missing from the acknowledged alerts" if alert.nil?
    
      alert.fetch("status")
    end
    
    # Returns an acknowledged alert to the active state. The alerter clears
    # only active alerts, so an alert that stays acknowledged also stops the
    # rule from raising a new one.
    def unacknowledge_alert(cfg, alert_id)
      api("DELETE", cfg, "/alerts/acknowledge", params: { alert_id: alert_id })
    end
    
    # Removes the override, so that the rule reverts to its default threshold.
    def remove_override(cfg, rule_id)
      api("DELETE", cfg, "/alert-overrides/server/#{cfg[:connection_id]}/#{rule_id}")
    end
    
    # Reports whether a list of alerts includes the one with an ID.
    def includes_alert?(alerts, alert_id)
      alerts.any? { |a| a["id"] == alert_id }
    end
    
    def main
      cfg = nil
      override_rule = nil
      acknowledged_alert = nil
      status = 0
      begin
        cfg = settings
        deadline = now + WAIT_SECONDS
    
        rule_id = find_rule(cfg, RULE_NAME)
        puts "Found the rule '#{RULE_NAME}'"
    
        # An alert from an earlier run may still be active.
        wait_until_quiet(cfg, rule_id, deadline)
    
        # Record the override first and remove it in the ensure block, so that
        # a failed run does not leave the server raising alerts.
        override_rule = rule_id
        set_override(cfg, rule_id)
        puts "Set an override that makes the rule fire"
    
        puts "Waiting for the alerter to raise an alert"
        alert = nil
        loop do
          alert = wait_for_alert(cfg, rule_id, deadline)
    
          # Record the alert before acknowledging it, so that the ensure block
          # returns it to the active state even if the request times out after
          # the server has acted on it.
          acknowledged_alert = alert["id"]
          begin
            acknowledge_alert(cfg, alert["id"])
            break
          rescue StandardError
            # The alerter may have cleared the alert since the poll. The
            # override is still in place, so the rule fires again at the next
            # evaluation; any other failure is real.
            if includes_alert?(active_alerts(cfg, rule_id), alert["id"])
              # The server did not acknowledge it, so there is nothing to undo.
              acknowledged_alert = nil
              raise
            end
            # If the server acted on a request that timed out, the alert is
            # acknowledged and must go back to active. When that fails, the
            # error propagates and the ensure block tries again, because
            # acknowledged_alert is still set.
            if includes_alert?(list_alerts(cfg, "acknowledged"), alert["id"])
              unacknowledge_alert(cfg, alert["id"])
            end
            acknowledged_alert = nil
            warn "The alert cleared first; waiting for the next one"
          end
        end
        puts "An alert is active (severity: #{alert.fetch('severity')})"
        puts "Acknowledged the alert"
    
        puts "The alert is now #{alert_status(cfg, alert['id'])}"
    
        unacknowledge_alert(cfg, alert["id"])
        acknowledged_alert = nil
        puts "Returned the alert to the active state"
    
        remove_override(cfg, rule_id)
        override_rule = nil
        puts "Removed the override"
      # Net::HTTP raises errors of many classes, such as SystemCallError for a
      # refused connection and Net::OpenTimeout for a timeout, and the program
      # raises RuntimeError for replies that the server rejected or that lacked
      # what we need, so this catches StandardError, their common ancestor.
      rescue StandardError => e
        warn "Error: #{e.message}"
        status = 1
      ensure
        # Undo the changes whether or not a step failed, so that the server
        # does not keep raising alerts or hold an acknowledged one.
        undo = []
        undo << -> { unacknowledge_alert(cfg, acknowledged_alert) } if acknowledged_alert
        undo << -> { remove_override(cfg, override_rule) } if override_rule
        undo.each do |step|
          step.call
        rescue StandardError => e
          warn "Error: could not undo a change: #{e.message}"
          status = 1
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
    # Listing and acknowledging alerts with the AI DBA Workbench API, using curl
    # and jq.
    #
    # Copyright (c) 2026, pgEdge, Inc.
    # This code is released under the PostgreSQL License.
    
    # Stop at the first failing command, treat an unset variable as an error,
    # and fail a pipeline when any command in it fails.
    set -euo pipefail
    
    # The script needs curl to make the requests and jq to read the replies.
    for tool in curl jq; do
        command -v "$tool" >/dev/null || { echo "$tool is required" >&2; exit 1; }
    done
    
    # Read the settings from the environment. The :- and :? forms, unlike - and
    # ?, treat an empty variable as unset.
    WORKBENCH_URL="${WORKBENCH_URL:-http://localhost:8080}"
    WORKBENCH_URL="${WORKBENCH_URL%/}"
    : "${WORKBENCH_TOKEN:?WORKBENCH_TOKEN must be set}"
    : "${WORKBENCH_CONNECTION_ID:?WORKBENCH_CONNECTION_ID must be set}"
    
    # The rule that the script makes fire. The metric_staleness rule alerts when
    # a probe's data is out of date, and the alerter checks it every minute.
    RULE_NAME="metric_staleness"
    # The longest the whole run waits for alerts, in seconds. The alerter
    # evaluates its rules once a minute and clears an alert up to 30 seconds
    # after it fires, so this allows for waiting out the alert from an earlier
    # run, one alert that clears before the script can acknowledge it, and a
    # second evaluation.
    WAIT_SECONDS=150
    # How often the script polls the alerts, in seconds.
    POLL_SECONDS=0.5
    
    # Sends an authenticated request and prints the JSON reply:
    # api METHOD PATH [curl options]. With --fail-with-body, a request that the
    # server rejects leaves the server's error message in the reply, and the
    # function prints it to standard error. The token goes to curl in a header
    # file that bash supplies through a pipe, so that it never appears in the
    # arguments of the curl process, which other users can read in the process
    # list.
    api() {
        local method="$1" path="$2"
        shift 2
        local response
        response=$(curl --silent --show-error --fail-with-body \
            --connect-timeout 10 --max-time 30 \
            --request "$method" \
            --header @<(printf 'Authorization: Bearer %s\n' "$WORKBENCH_TOKEN") \
            "$@" "$WORKBENCH_URL/api/v1$path") || {
            echo "$method $path failed: $response" >&2
            return 1
        }
        printf '%s' "$response"
    }
    
    # Prints the ID of an alert rule, given its name. The function fails when
    # there is no such rule, because jq prints nothing for it.
    find_rule() {
        local name="$1" id
        id=$(api GET /alert-rules |
            jq -r --arg name "$name" 'first(.[] | select(.name == $name)) | .id')
        if [[ -z "$id" ]]; then
            echo "There is no alert rule named '$name'" >&2
            return 1
        fi
        printf '%s' "$id"
    }
    
    # Overrides the threshold of a rule for one server. A threshold of -1 is
    # below any value that the staleness ratio can take, so the rule is
    # violated on the next evaluation.
    set_override() {
        local rule_id="$1"
        api PUT "/alert-overrides/server/$WORKBENCH_CONNECTION_ID/$rule_id" \
            --header 'Content-Type: application/json' \
            --data '{"operator": ">", "threshold": -1, "severity": "info", "enabled": true}' \
            >/dev/null
    }
    
    # Prints the active alerts that a rule raised for the server, one per line,
    # as an ID and a severity. The request filters by server, status, and type,
    # and asks for the most alerts that the API returns at once, so that the
    # result does not depend on the first 100 alerts of a busy Workbench.
    active_alerts() {
        local rule_id="$1"
        api GET "/alerts?connection_id=$WORKBENCH_CONNECTION_ID&status=active&alert_type=threshold&limit=1000" |
            jq -r --argjson rule "$rule_id" \
               '.alerts[] | select(.rule_id == $rule) | "\(.id) \(.severity)"'
    }
    
    # Waits until the rule has no active alert. The alerter raises no new alert
    # for a rule while one is active, so an alert left by an earlier run, which
    # clears within 30 seconds, would otherwise stand in for the one that this
    # run causes.
    wait_until_quiet() {
        local rule_id="$1" deadline="$2" active
        while true; do
            active=$(active_alerts "$rule_id")
            [[ -z "$active" ]] && return 0
            if ((SECONDS >= deadline)); then
                echo "An earlier alert did not clear in time" >&2
                return 1
            fi
            sleep "$POLL_SECONDS"
        done
    }
    
    # Polls until the rule raises an alert, and sets ALERT_ID and ALERT_SEVERITY
    # to its ID and severity. The alert clears itself within 30 seconds of
    # firing, so the script polls twice a second. The caller must not run this
    # function inside $(...), where errexit is off, because an error from the API
    # would then go unnoticed until the deadline.
    wait_for_alert() {
        local rule_id="$1" deadline="$2" active
        while true; do
            active=$(active_alerts "$rule_id")
            if [[ -n "$active" ]]; then
                read -r ALERT_ID ALERT_SEVERITY <<<"${active%%$'\n'*}"
                return 0
            fi
            if ((SECONDS >= deadline)); then
                echo "No alert was raised within $WAIT_SECONDS seconds" >&2
                return 1
            fi
            sleep "$POLL_SECONDS"
        done
    }
    
    # Acknowledges an alert, with a message that the interface shows.
    acknowledge_alert() {
        local alert_id="$1"
        jq -n --argjson id "$alert_id" \
           '{alert_id: $id, message: "Acknowledged by the cookbook"}' |
            api POST /alerts/acknowledge \
                --header 'Content-Type: application/json' --data @- >/dev/null
    }
    
    # Prints the acknowledged threshold alerts for the server, as JSON.
    list_acknowledged() {
        api GET "/alerts?connection_id=$WORKBENCH_CONNECTION_ID&status=acknowledged&alert_type=threshold&limit=1000"
    }
    
    # Prints the status of an alert, found by its ID in the list of acknowledged
    # alerts. The function fails when the alert is not in the list, because jq
    # prints nothing for it.
    alert_status() {
        local alert_id="$1" status
        status=$(list_acknowledged |
            jq -r --argjson id "$alert_id" \
               'first(.alerts[] | select(.id == $id)) | .status')
        if [[ -z "$status" ]]; then
            echo "The alert is missing from the acknowledged alerts" >&2
            return 1
        fi
        printf '%s' "$status"
    }
    
    # Returns an acknowledged alert to the active state. The alerter clears only
    # active alerts, so an alert that stays acknowledged also stops the rule from
    # raising a new one.
    unacknowledge_alert() {
        local alert_id="$1"
        api DELETE "/alerts/acknowledge?alert_id=$alert_id" >/dev/null
    }
    
    # Removes the override, so that the rule reverts to its default threshold.
    remove_override() {
        local rule_id="$1"
        api DELETE "/alert-overrides/server/$WORKBENCH_CONNECTION_ID/$rule_id" \
            >/dev/null
    }
    
    # These variables are global, because the EXIT trap runs after main returns.
    override_rule=""
    acknowledged_alert=""
    
    cleanup() {
        local status=$?
        # Undo the changes when the script ends, even if a step failed, so that
        # the server does not keep raising alerts or hold an acknowledged one.
        # Report a step that fails, and make the exit status non-zero.
        if [[ -n "$acknowledged_alert" ]]; then
            unacknowledge_alert "$acknowledged_alert" || {
                echo "Error: could not undo a change" >&2
                status=1
            }
        fi
        if [[ -n "$override_rule" ]]; then
            remove_override "$override_rule" || {
                echo "Error: could not undo a change" >&2
                status=1
            }
        fi
        exit "$status"
    }
    
    main() {
        local rule_id alert_id severity status still_active acknowledged
        local deadline=$((SECONDS + WAIT_SECONDS))
    
        rule_id=$(find_rule "$RULE_NAME")
        echo "Found the rule '$RULE_NAME'"
    
        # An alert from an earlier run may still be active.
        wait_until_quiet "$rule_id" "$deadline"
    
        override_rule="$rule_id"
        set_override "$rule_id"
        echo "Set an override that makes the rule fire"
    
        echo "Waiting for the alerter to raise an alert"
        while true; do
            wait_for_alert "$rule_id" "$deadline"
            alert_id="$ALERT_ID"
            severity="$ALERT_SEVERITY"
    
            # Record the alert before acknowledging it, so that the EXIT trap
            # returns it to the active state even if the request times out
            # after the server has acted on it.
            acknowledged_alert="$alert_id"
            acknowledge_alert "$alert_id" && break
    
            # The alerter may have cleared the alert since the poll. The
            # override is still in place, so the rule fires again at the next
            # evaluation; any other failure is real.
            still_active=$(active_alerts "$rule_id")
            if [[ $'\n'"$still_active" == *$'\n'"$alert_id "* ]]; then
                # The server did not acknowledge it, so there is nothing to
                # undo.
                acknowledged_alert=""
                return 1
            fi
            # If the server acted on a request that timed out, the alert is
            # acknowledged and must go back to active. When that fails, the
            # script stops with the alert still recorded, so that the EXIT trap
            # tries again.
            acknowledged=$(list_acknowledged)
            if jq -e --argjson id "$alert_id" 'any(.alerts[]; .id == $id)' \
                <<<"$acknowledged" >/dev/null; then
                unacknowledge_alert "$alert_id"
            fi
            acknowledged_alert=""
            echo "The alert cleared first; waiting for the next one" >&2
        done
        echo "An alert is active (severity: $severity)"
        echo "Acknowledged the alert"
    
        status=$(alert_status "$alert_id")
        echo "The alert is now $status"
    
        unacknowledge_alert "$alert_id"
        acknowledged_alert=""
        echo "Returned the alert to the active state"
    
        remove_override "$rule_id"
        override_rule=""
        echo "Removed the override"
    }
    
    trap cleanup EXIT
    main
    
    ```

## Next Steps

The following resources provide more information about the topics in this
recipe:

- The [Authenticating](authenticate.md) recipe shows how to create the API
  token that this recipe needs.
- The [Querying Metrics](metrics.md) recipe reads the data that the alerter
  evaluates.
- The AI DBA Workbench
  [API reference](https://github.com/pgEdge/ai-dba-workbench/blob/v1.0.0/docs/admin-guide/api/reference.md)
  describes every endpoint.
