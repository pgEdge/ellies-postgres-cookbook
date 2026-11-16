# Querying Metrics with the AI DBA Workbench API

This recipe shows how a program reads time-series metrics and the most
expensive queries for a monitored server from the pgEdge AI DBA Workbench API.
These examples are for AI DBA Workbench 1.0.0. Each step shows the code in
every supported language; selecting a language tab switches every tab on the
site to that language.

The example program asks for two metrics from the `pg_stat_database` probe over
the last hour, and prints the number of points and the latest value of each. It
then asks for the five queries that have used the most execution time, and
prints each one with its number of calls and its mean execution time. The
values change from run to run, so the output has the following form:

```text
numbackends: 5 points, latest 3
xact_commit: 5 points, latest 1138
Top queries by total execution time:
1. 1 calls, 6.97 ms mean: CREATE EXTENSION IF NOT EXISTS pg_stat_statements
2. 26 calls, 0.01 ms mean: SELECT datname FROM pg_database WHERE datallowconn
3. 28 calls, 0.01 ms mean: SELECT EXISTS( SELECT $2 FROM pg_extension WHERE e
```

The second part of the output depends on the monitored server. The Workbench
builds the list of top queries from the `pg_stat_statements` extension, so a
server without the extension returns an empty list, and the program then prints
a line that starts with "No statements recorded" instead of the list. The
program stops with an error when the Workbench returns no series at all, which
happens before the collector has stored any data for the server.

## Preparing the Ingredients

The `scripts/start_workbench.sh` script in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook)
starts a test Workbench in Docker. The script creates a `cookbook` user and an
API token, registers a test PostgreSQL server as a monitored connection, and
prints the `WORKBENCH_URL`, `WORKBENCH_TOKEN`, `WORKBENCH_USERNAME`,
`WORKBENCH_PASSWORD`, and `WORKBENCH_CONNECTION_ID` values that the examples
read from the environment.

The examples need a running Workbench server that monitors at least one
PostgreSQL server, and an API token for a user that can read its metrics. The
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
      "name": "metrics",
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

To see the top queries, install the extension on the monitored server. Add
`pg_stat_statements` to `shared_preload_libraries` in `postgresql.conf`,
restart the server, and then run `CREATE EXTENSION pg_stat_statements` in the
monitored database. The collector collects the statements every five minutes,
so the first queries appear after the next collection.

## Importing the Libraries

Each program begins by importing the modules that it uses. The following tabs
show the imports for each language:

=== "Python"

    ```python
    import os
    import sys
    
    import httpx
    ```

=== "TypeScript"

    ```typescript
    // The program needs no imports: fetch and process are built in to Node.js.
    ```

=== "Java"

    ```java
    import java.io.IOException;
    import java.math.BigDecimal;
    import java.net.URI;
    import java.net.URLEncoder;
    import java.net.http.HttpClient;
    import java.net.http.HttpRequest;
    import java.net.http.HttpResponse;
    import java.net.http.HttpTimeoutException;
    import java.nio.charset.StandardCharsets;
    import java.time.Duration;
    import java.util.LinkedHashMap;
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
    using System.Globalization;
    using System.Net.Http.Headers;
    using System.Text.Json;
    using System.Text.Json.Nodes;
    using System.Text.RegularExpressions;
    ```

=== "Go"

    ```go
    import (
    	"encoding/json"
    	"errors"
    	"fmt"
    	"io"
    	"math"
    	"net/http"
    	"net/url"
    	"os"
    	"strconv"
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
    use std::time::Duration;
    
    use reqwest::blocking::Client;
    use reqwest::Url;
    use serde_json::Value;
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
| `WORKBENCH_CONNECTION_ID` | The ID of the server to query.                |

The Authenticating recipe shows how to create an API token. The following tabs
show how each program reads the settings and stops with an error when the token
or the connection ID is missing:

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
    ```

## Sending Requests

Every call to the API goes through one helper function. The function adds the
`/api/v1` prefix to the path, adds the query parameters, sends the token as a
`Bearer` credential in the `Authorization` header, and sets a timeout so that a
stalled server cannot hang the program. When the server rejects a request, the
function raises an error that includes the status code and the message from the
server, for example when a request names a metric that the probe does not
collect. The following tabs show the helper function from each program:

=== "Python"

    ```python
    def api(cfg: dict, path: str, params: dict) -> list:
        """Sends a GET request to the API and returns the decoded reply.
    
        A request that the server rejects raises an error that includes the
        message from the server, which raise_for_status alone would leave out.
        """
        response = httpx.get(
            f"{cfg['base_url']}/api/v1{path}", params=params, timeout=30,
            headers={"Authorization": f"Bearer {cfg['token']}"},
        )
        if response.is_error:
            raise RuntimeError(
                f"GET {path} failed with status {response.status_code}: "
                f"{response.text.strip()}"
            )
        return response.json()
    ```

=== "TypeScript"

    ```typescript
    // Sends a GET request to the API and returns the decoded reply. A request
    // that the server rejects throws an error that includes the message from the
    // server.
    async function api<T>(
      cfg: Settings,
      path: string,
      params: Record<string, string>,
    ): Promise<T> {
      const response = await fetch(
        `${cfg.baseUrl}/api/v1${path}?${new URLSearchParams(params)}`,
        {
          headers: { Authorization: `Bearer ${cfg.token}` },
          signal: AbortSignal.timeout(30_000),
        },
      );
      if (!response.ok) {
        const text = (await response.text()).trim();
        throw new Error(
          `GET ${path} failed with status ${response.status}: ${text}`,
        );
      }
      return (await response.json()) as T;
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
     * Sends a GET request to the API, with the parameters in the query
     * string, and returns the JSON reply. A request that the server
     * rejects throws an error that includes the message from the server.
     */
    static JsonNode api(Settings cfg, String path, Map<String, String> params)
            throws IOException, InterruptedException {
        String query = params.entrySet().stream()
                .map(p -> URLEncoder.encode(p.getKey(), StandardCharsets.UTF_8)
                        + "=" + URLEncoder.encode(p.getValue(),
                                StandardCharsets.UTF_8))
                .collect(Collectors.joining("&"));
        HttpRequest request = HttpRequest
                .newBuilder(URI.create(
                        cfg.baseUrl() + "/api/v1" + path + "?" + query))
                .timeout(Duration.ofSeconds(30))
                .header("Authorization", "Bearer " + cfg.token())
                .GET()
                .build();
    
        HttpResponse<String> response = send(request);
        if (response.statusCode() >= 400) {
            throw new IOException("GET " + path + " failed with status "
                    + response.statusCode() + ": " + response.body().strip());
        }
        return JSON.readTree(response.body());
    }
    ```

=== "C#"

    ```csharp
    // One client serves every request, with a timeout for each.
    var http = new HttpClient { Timeout = TimeSpan.FromSeconds(30) };
    
    // Sends a GET request to the API, with the parameters in the query string,
    // and returns the JSON reply. A request that the server rejects throws an
    // error that includes the message from the server.
    async Task<JsonArray> Api(string baseUrl, string token, string path,
        Dictionary<string, string> parameters)
    {
        var query = string.Join("&", parameters.Select(p =>
            $"{Uri.EscapeDataString(p.Key)}={Uri.EscapeDataString(p.Value)}"));
        using var request = new HttpRequestMessage(HttpMethod.Get,
            $"{baseUrl}/api/v1{path}?{query}");
        request.Headers.Authorization =
            new AuthenticationHeaderValue("Bearer", token);
    
        using var response = await http.SendAsync(request);
        var text = await response.Content.ReadAsStringAsync();
        if ((int)response.StatusCode >= 400)
        {
            throw new HttpRequestException(
                $"GET {path} failed with status {(int)response.StatusCode}: "
                + text.Trim());
        }
        return JsonNode.Parse(text)?.AsArray()
            ?? throw new InvalidOperationException($"GET {path} returned no JSON");
    }
    ```

=== "Go"

    ```go
    // client gives every request a timeout; the default client has none.
    var client = &http.Client{Timeout: 30 * time.Second}
    
    // get sends a GET request to the API and decodes the JSON reply into out. A
    // request that the server rejects returns an error that includes the
    // message from the server.
    func get(s settings, path string, params url.Values, out any) error {
    	req, err := http.NewRequest("GET", s.baseURL+"/api/v1"+path+"?"+params.Encode(), nil)
    	if err != nil {
    		return err
    	}
    	req.Header.Set("Authorization", "Bearer "+s.token)
    
    	resp, err := client.Do(req)
    	if err != nil {
    		return err
    	}
    	defer resp.Body.Close()
    	if resp.StatusCode >= 400 {
    		text, _ := io.ReadAll(resp.Body)
    		return fmt.Errorf("GET %s failed with status %d: %s",
    			path, resp.StatusCode, strings.TrimSpace(string(text)))
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
    ```

=== "Ruby"

    ```ruby
    # Sends a GET request to the API, with the parameters in the query string,
    # and returns the decoded reply. A request that the server rejects raises
    # an error that includes the message from the server.
    def api(cfg, path, params)
      uri = URI("#{cfg[:base_url]}/api/v1#{path}")
      uri.query = URI.encode_www_form(params)
    
      # Net::HTTP has no overall timeout, so limit both the connection and
      # each read.
      response = Net::HTTP.start(uri.host, uri.port,
                                 use_ssl: uri.scheme == "https",
                                 open_timeout: 30, read_timeout: 30) do |http|
        http.get(uri.request_uri, "Authorization" => "Bearer #{cfg[:token]}")
      end
      if response.code.to_i >= 400
        raise "GET #{path} failed with status #{response.code}: " \
              "#{response.body.to_s.strip}"
      end
      JSON.parse(response.body)
    end
    ```

=== "curl"

    ```bash
    # Sends an authenticated GET request and prints the JSON reply:
    # api PATH [curl options]. With --fail-with-body, a request that the server
    # rejects leaves the server's error message in the reply, and the function
    # prints it to standard error.
    # The token goes to curl in a header file that bash supplies through a pipe,
    # so that it never appears in the arguments of the curl process, which other
    # users can read in the process list.
    api() {
        local path="$1"
        shift
        local response
        response=$(curl --silent --show-error --fail-with-body --get \
            --connect-timeout 10 --max-time 30 \
            --header @<(printf 'Authorization: Bearer %s\n' "$WORKBENCH_TOKEN") \
            "$@" "$WORKBENCH_URL/api/v1$path") || {
            echo "GET $path failed: $response" >&2
            return 1
        }
        printf '%s' "$response"
    }
    ```

## Querying Metrics

The program asks `GET /api/v1/metrics/query` for the `numbackends` and
`xact_commit` metrics of the `pg_stat_database` probe over the last hour. The
parameters `connection_id`, `probe_name`, and `time_range` choose the server,
the probe, and the period; the `time_range` parameter accepts `1h`, `6h`,
`24h`, `7d`, and `30d`. The `buckets` parameter divides the period into six
buckets, and the `metrics` parameter lists the metrics to return. The reply is
a list of series, each with a `name`, a `unit`, and a `data` list of points
with a `time` and a `value`. The number of points depends on how much data
exists for the period. The following tabs show how each program queries the
metrics:

=== "Python"

    ```python
    def query_metrics(cfg: dict) -> None:
        """Prints one line for each series that the pg_stat_database probe
        collected over the last hour, in six buckets: the metric, the number
        of points, and the latest value."""
        series = api(cfg, "/metrics/query", {
            "connection_id": cfg["connection_id"],
            "probe_name": "pg_stat_database",
            "time_range": "1h",
            "buckets": 6,
            "metrics": "numbackends,xact_commit",
        })
        if not series:
            raise RuntimeError(
                "The Workbench returned no series; has the collector run yet?"
            )
        for s in series:
            points = s["data"]
            if not points:
                print(f"{s['name']}: no data")
                continue
            print(f"{s['name']}: {len(points)} points, "
                  f"latest {points[-1]['value']}")
    ```

=== "TypeScript"

    ```typescript
    interface Series {
      name: string;
      data: Array<{ time: string; value: number }>;
    }
    
    // Prints one line for each series that the pg_stat_database probe collected
    // over the last hour, in six buckets: the metric, the number of points, and
    // the latest value.
    async function queryMetrics(cfg: Settings): Promise<void> {
      const series = await api<Series[]>(cfg, "/metrics/query", {
        connection_id: cfg.connectionId,
        probe_name: "pg_stat_database",
        time_range: "1h",
        buckets: "6",
        metrics: "numbackends,xact_commit",
      });
      if (series.length === 0) {
        throw new Error("The Workbench returned no series; has the collector run yet?");
      }
      for (const s of series) {
        if (s.data.length === 0) {
          console.log(`${s.name}: no data`);
          continue;
        }
        const latest = s.data[s.data.length - 1].value;
        console.log(`${s.name}: ${s.data.length} points, latest ${latest}`);
      }
    }
    ```

=== "Java"

    ```java
    /**
     * Returns a number as plain decimal text, without an exponent or
     * trailing zeros, as the other languages print it.
     */
    static String plain(double value) {
        return BigDecimal.valueOf(value).stripTrailingZeros().toPlainString();
    }
    
    /**
     * Prints one line for each series that the pg_stat_database probe
     * collected over the last hour, in six buckets: the metric, the number
     * of points, and the latest value.
     */
    static void queryMetrics(Settings cfg)
            throws IOException, InterruptedException {
        // A LinkedHashMap keeps the parameters in the order given.
        Map<String, String> params = new LinkedHashMap<>();
        params.put("connection_id", cfg.connectionId());
        params.put("probe_name", "pg_stat_database");
        params.put("time_range", "1h");
        params.put("buckets", "6");
        params.put("metrics", "numbackends,xact_commit");
    
        JsonNode series = api(cfg, "/metrics/query", params);
        if (series.isEmpty()) {
            throw new IOException(
                    "The Workbench returned no series; has the collector run yet?");
        }
        for (JsonNode s : series) {
            JsonNode points = s.path("data");
            String name = s.get("name").asString();
            if (points.isEmpty()) {
                System.out.println(name + ": no data");
                continue;
            }
            double latest = points.get(points.size() - 1).get("value")
                    .asDouble();
            System.out.println(name + ": " + points.size()
                    + " points, latest " + plain(latest));
        }
    }
    ```

=== "C#"

    ```csharp
    // Returns a number as plain decimal text, without an exponent or trailing
    // zeros, and with a full stop whatever the locale.
    static string Plain(double value) =>
        value.ToString("0.###############", CultureInfo.InvariantCulture);
    
    // Prints one line for each series that the pg_stat_database probe
    // collected over the last hour, in six buckets: the metric, the number of
    // points, and the latest value.
    async Task QueryMetrics(string baseUrl, string token, string connectionId)
    {
        var series = await Api(baseUrl, token, "/metrics/query", new()
        {
            ["connection_id"] = connectionId,
            ["probe_name"] = "pg_stat_database",
            ["time_range"] = "1h",
            ["buckets"] = "6",
            ["metrics"] = "numbackends,xact_commit",
        });
        if (series.Count == 0)
        {
            throw new InvalidOperationException(
                "The Workbench returned no series; has the collector run yet?");
        }
        foreach (var s in series)
        {
            var name = s!["name"]!.GetValue<string>();
            var points = s["data"]?.AsArray();
            if (points is null || points.Count == 0)
            {
                Console.WriteLine($"{name}: no data");
                continue;
            }
            var latest = points[^1]!["value"]!.GetValue<double>();
            Console.WriteLine(
                $"{name}: {points.Count} points, latest {Plain(latest)}");
        }
    }
    ```

=== "Go"

    ```go
    // series is one metric, with its points over time.
    type series struct {
    	Name string `json:"name"`
    	Data []struct {
    		Time  string  `json:"time"`
    		Value float64 `json:"value"`
    	} `json:"data"`
    }
    
    // queryMetrics prints one line for each series that the pg_stat_database
    // probe collected over the last hour, in six buckets: the metric, the number
    // of points, and the latest value.
    func queryMetrics(s settings) error {
    	var result []series
    	err := get(s, "/metrics/query", url.Values{
    		"connection_id": {s.connectionID},
    		"probe_name":    {"pg_stat_database"},
    		"time_range":    {"1h"},
    		"buckets":       {"6"},
    		"metrics":       {"numbackends,xact_commit"},
    	}, &result)
    	if err != nil {
    		return err
    	}
    	if len(result) == 0 {
    		return errors.New("the Workbench returned no series; has the collector run yet?")
    	}
    	for _, m := range result {
    		if len(m.Data) == 0 {
    			fmt.Printf("%s: no data\n", m.Name)
    			continue
    		}
    		latest := m.Data[len(m.Data)-1].Value
    		fmt.Printf("%s: %d points, latest %s\n", m.Name, len(m.Data),
    			strconv.FormatFloat(latest, 'f', -1, 64))
    	}
    	return nil
    }
    
    ```

=== "Rust"

    ```rust
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
    ```

=== "Ruby"

    ```ruby
    # Prints one line for each series that the pg_stat_database probe collected
    # over the last hour, in six buckets: the metric, the number of points, and
    # the latest value.
    def query_metrics(cfg)
      series = api(cfg, "/metrics/query", {
                     connection_id: cfg[:connection_id],
                     probe_name: "pg_stat_database",
                     time_range: "1h",
                     buckets: 6,
                     metrics: "numbackends,xact_commit"
                   })
      raise "The Workbench returned no series; has the collector run yet?" if series.empty?
    
      series.each do |s|
        points = s["data"] || []
        if points.empty?
          puts "#{s.fetch('name')}: no data"
          next
        end
        puts "#{s.fetch('name')}: #{points.length} points, " \
             "latest #{points.last.fetch('value')}"
      end
    end
    ```

=== "curl"

    ```bash
    # Prints one line for each series that the pg_stat_database probe collected
    # over the last hour, in six buckets: the metric, the number of points, and
    # the latest value. The --data-urlencode options build the query string.
    query_metrics() {
        local series
        series=$(api /metrics/query \
            --data-urlencode "connection_id=$WORKBENCH_CONNECTION_ID" \
            --data-urlencode "probe_name=pg_stat_database" \
            --data-urlencode "time_range=1h" \
            --data-urlencode "buckets=6" \
            --data-urlencode "metrics=numbackends,xact_commit")
    
        if [[ "$(jq length <<<"$series")" -eq 0 ]]; then
            echo "The Workbench returned no series; has the collector run yet?" >&2
            return 1
        fi
        jq -r <<<"$series" '.[] | if .data == [] then "\(.name): no data"
                         else "\(.name): \(.data | length) points, latest \(.data | last | .value)"
                         end'
    }
    ```

## Reading the Top Queries

The program asks `GET /api/v1/metrics/top-queries` for the five queries with
the largest total execution time. The `order_by` parameter accepts
`total_exec_time`, `calls`, `mean_exec_time`, `rows`, `shared_blks_hit`, and
`shared_blks_read`, and the `order` parameter chooses between `asc` and `desc`
(the default is `desc`). Setting `exclude_collector` to `true` hides the
queries that the Workbench's own probes run, so the list shows the queries of
the applications. The `limit` parameter accepts up to 100. The program cuts
each query to 50 characters on one line, because a statement can run to many
lines. The following tabs show how each program reads the top queries:

=== "Python"

    ```python
    def top_queries(cfg: dict) -> None:
        """Prints the queries that have used the most execution time, as the
        pg_stat_statements extension on the monitored server recorded them.
    
        The query text is cut to 50 characters on one line.
        """
        queries = api(cfg, "/metrics/top-queries", {
            "connection_id": cfg["connection_id"],
            "limit": 5,
            "order_by": "total_exec_time",
            "exclude_collector": "true",
        })
        if not queries:
            print("No statements recorded (is pg_stat_statements installed?)")
            return
    
        print("Top queries by total execution time:")
        for rank, q in enumerate(queries, start=1):
            text = " ".join(q["query"].split())[:50]
            print(f"{rank}. {q['calls']} calls, "
                  f"{round(q['mean_exec_time'], 2)} ms mean: {text}")
    ```

=== "TypeScript"

    ```typescript
    interface TopQuery {
      query: string;
      calls: number;
      mean_exec_time: number;
    }
    
    // Prints the queries that have used the most execution time, as the
    // pg_stat_statements extension on the monitored server recorded them. The
    // query text is cut to 50 characters on one line.
    async function topQueries(cfg: Settings): Promise<void> {
      const queries = await api<TopQuery[]>(cfg, "/metrics/top-queries", {
        connection_id: cfg.connectionId,
        limit: "5",
        order_by: "total_exec_time",
        exclude_collector: "true",
      });
      if (queries.length === 0) {
        console.log("No statements recorded (is pg_stat_statements installed?)");
        return;
      }
    
      console.log("Top queries by total execution time:");
      queries.forEach((q, i) => {
        const text = q.query.split(/\s+/).filter(Boolean).join(" ").slice(0, 50);
        const mean = Math.round(q.mean_exec_time * 100) / 100;
        console.log(`${i + 1}. ${q.calls} calls, ${mean} ms mean: ${text}`);
      });
    }
    ```

=== "Java"

    ```java
    /**
     * Prints the queries that have used the most execution time, as the
     * pg_stat_statements extension on the monitored server recorded them.
     * The query text is cut to 50 characters on one line.
     */
    static void topQueries(Settings cfg)
            throws IOException, InterruptedException {
        Map<String, String> params = new LinkedHashMap<>();
        params.put("connection_id", cfg.connectionId());
        params.put("limit", "5");
        params.put("order_by", "total_exec_time");
        params.put("exclude_collector", "true");
    
        JsonNode queries = api(cfg, "/metrics/top-queries", params);
        if (queries.isEmpty()) {
            System.out.println(
                    "No statements recorded (is pg_stat_statements installed?)");
            return;
        }
    
        System.out.println("Top queries by total execution time:");
        int rank = 1;
        for (JsonNode q : queries) {
            String text = q.get("query").asString().strip()
                    .replaceAll("\\s+", " ");
            // Count characters, not UTF-16 units, when cutting the text.
            if (text.codePointCount(0, text.length()) > 50) {
                text = text.substring(0, text.offsetByCodePoints(0, 50));
            }
            double mean = Math.round(
                    q.get("mean_exec_time").asDouble() * 100) / 100.0;
            System.out.println(rank + ". " + q.get("calls").asLong()
                    + " calls, " + plain(mean) + " ms mean: " + text);
            rank++;
        }
    }
    ```

=== "C#"

    ```csharp
    // Prints the queries that have used the most execution time, as the
    // pg_stat_statements extension on the monitored server recorded them. The
    // query text is cut to 50 characters on one line.
    async Task TopQueries(string baseUrl, string token, string connectionId)
    {
        var queries = await Api(baseUrl, token, "/metrics/top-queries", new()
        {
            ["connection_id"] = connectionId,
            ["limit"] = "5",
            ["order_by"] = "total_exec_time",
            ["exclude_collector"] = "true",
        });
        if (queries.Count == 0)
        {
            Console.WriteLine(
                "No statements recorded (is pg_stat_statements installed?)");
            return;
        }
    
        Console.WriteLine("Top queries by total execution time:");
        var rank = 1;
        foreach (var q in queries)
        {
            var text = Regex.Replace(q!["query"]!.GetValue<string>().Trim(),
                @"\s+", " ");
            // Count characters, not UTF-16 units, when cutting the text.
            text = string.Concat(text.EnumerateRunes().Take(50));
            var mean = Math.Round(q["mean_exec_time"]!.GetValue<double>(), 2,
                MidpointRounding.AwayFromZero);
            Console.WriteLine($"{rank}. {q["calls"]!.GetValue<long>()} calls, "
                + $"{Plain(mean)} ms mean: {text}");
            rank++;
        }
    }
    ```

=== "Go"

    ```go
    // topQuery is the part of a top query that the program prints.
    type topQuery struct {
    	Query        string  `json:"query"`
    	Calls        int64   `json:"calls"`
    	MeanExecTime float64 `json:"mean_exec_time"`
    }
    
    // topQueries prints the queries that have used the most execution time, as
    // the pg_stat_statements extension on the monitored server recorded them.
    // The query text is cut to 50 characters on one line.
    func topQueries(s settings) error {
    	var queries []topQuery
    	err := get(s, "/metrics/top-queries", url.Values{
    		"connection_id":     {s.connectionID},
    		"limit":             {"5"},
    		"order_by":          {"total_exec_time"},
    		"exclude_collector": {"true"},
    	}, &queries)
    	if err != nil {
    		return err
    	}
    	if len(queries) == 0 {
    		fmt.Println("No statements recorded (is pg_stat_statements installed?)")
    		return nil
    	}
    
    	fmt.Println("Top queries by total execution time:")
    	for i, q := range queries {
    		text := []rune(strings.Join(strings.Fields(q.Query), " "))
    		if len(text) > 50 {
    			text = text[:50]
    		}
    		mean := math.Round(q.MeanExecTime*100) / 100
    		fmt.Printf("%d. %d calls, %s ms mean: %s\n", i+1, q.Calls,
    			strconv.FormatFloat(mean, 'f', -1, 64), string(text))
    	}
    	return nil
    }
    
    ```

=== "Rust"

    ```rust
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
    ```

=== "Ruby"

    ```ruby
    # Prints the queries that have used the most execution time, as the
    # pg_stat_statements extension on the monitored server recorded them. The
    # query text is cut to 50 characters on one line.
    def top_queries(cfg)
      queries = api(cfg, "/metrics/top-queries", {
                      connection_id: cfg[:connection_id],
                      limit: 5,
                      order_by: "total_exec_time",
                      exclude_collector: "true"
                    })
      if queries.empty?
        puts "No statements recorded (is pg_stat_statements installed?)"
        return
      end
    
      puts "Top queries by total execution time:"
      queries.each.with_index(1) do |q, rank|
        text = q.fetch("query").split.join(" ")[0, 50]
        puts "#{rank}. #{q.fetch('calls')} calls, " \
             "#{q.fetch('mean_exec_time').round(2)} ms mean: #{text}"
      end
    end
    ```

=== "curl"

    ```bash
    # Prints the queries that have used the most execution time, as the
    # pg_stat_statements extension on the monitored server recorded them.
    # The query text is cut to 50 characters on one line.
    top_queries() {
        local queries
        queries=$(api /metrics/top-queries \
            --data-urlencode "connection_id=$WORKBENCH_CONNECTION_ID" \
            --data-urlencode "limit=5" \
            --data-urlencode "order_by=total_exec_time" \
            --data-urlencode "exclude_collector=true")
    
        if [[ "$(jq length <<<"$queries")" -eq 0 ]]; then
            echo "No statements recorded (is pg_stat_statements installed?)"
            return
        fi
        echo "Top queries by total execution time:"
        jq -r 'to_entries[] | "\(.key + 1). \(.value.calls) calls, \(.value.mean_exec_time * 100 | round / 100) ms mean: \(.value.query | gsub("\\s+"; " ") | .[0:50])"' \
            <<<"$queries"
    }
    ```

## Putting It Together

The main part of each program reads the settings, queries the metrics, and then
reads the top queries. The program reports any failure on `stderr` and exits
with a non-zero status. The following tabs show the main part of each program:

=== "Python"

    ```python
    def main() -> int:
        try:
            cfg = settings()
            query_metrics(cfg)
            top_queries(cfg)
        # httpx.HTTPError covers failures to connect, and RuntimeError covers
        # replies that the server rejected or that lacked what we need.
        except (httpx.HTTPError, RuntimeError) as e:
            print(f"Error: {e}", file=sys.stderr)
            return 1
        return 0
    
    
    if __name__ == "__main__":
        sys.exit(main())
    ```

=== "TypeScript"

    ```typescript
    async function main(): Promise<number> {
      try {
        const cfg = settings();
        await queryMetrics(cfg);
        await topQueries(cfg);
      } catch (err) {
        console.error(`Error: ${err instanceof Error ? err.message : err}`);
        return 1;
      }
      return 0;
    }
    
    process.exitCode = await main();
    ```

=== "Java"

    ```java
    /**
     * Returns the message of an error. Some errors, such as a refused
     * connection, have no message, so their type stands in for one.
     */
    static String describe(Exception e) {
        return Objects.requireNonNullElse(e.getMessage(), e.toString());
    }
    
    public static void main(String[] args) {
        int status = 0;
        try {
            Settings cfg = settings();
            queryMetrics(cfg);
            topQueries(cfg);
        // IOException covers failures to connect, replies that the server
        // rejected, and replies that lacked what we need; the client
        // throws InterruptedException if the thread is interrupted, and
        // Jackson throws JacksonException for a reply that is not JSON.
        } catch (IOException | InterruptedException | JacksonException e) {
            System.err.println("Error: " + describe(e));
            status = 1;
        }
        System.exit(status);
    }
    ```

=== "C#"

    ```csharp
    try
    {
        var (baseUrl, token, connectionId) = Settings();
        await QueryMetrics(baseUrl, token, connectionId);
        await TopQueries(baseUrl, token, connectionId);
    }
    // HttpRequestException covers failures to connect and replies that the
    // server rejected, TaskCanceledException covers a request that timed out,
    // and the others cover replies that lacked what we need.
    catch (Exception e) when (e is HttpRequestException
        or TaskCanceledException or InvalidOperationException or JsonException)
    {
        Console.Error.WriteLine($"Error: {e.Message}");
        return 1;
    }
    return 0;
    ```

=== "Go"

    ```go
    func main() {
    	s, err := loadSettings()
    	if err == nil {
    		err = queryMetrics(s)
    	}
    	if err == nil {
    		err = topQueries(s)
    	}
    	if err != nil {
    		fmt.Fprintln(os.Stderr, "Error:", err)
    		os.Exit(1)
    	}
    }
    
    ```

=== "Rust"

    ```rust
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
    ```

=== "Ruby"

    ```ruby
    def main
      cfg = settings
      query_metrics(cfg)
      top_queries(cfg)
      0
    # Net::HTTP raises errors of many classes, such as SystemCallError for a
    # refused connection and Net::OpenTimeout for a timeout, and the program
    # raises RuntimeError for replies that the server rejected or that lacked
    # what we need, so this catches StandardError, their common ancestor.
    rescue StandardError => e
      warn "Error: #{e.message}"
      1
    end
    
    exit main
    ```

=== "curl"

    ```bash
    main() {
        query_metrics
        top_queries
    }
    
    main
    ```

## Running the Example

The complete project for each language is available in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/ai_dba_workbench/metrics).
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
    Querying metrics and top queries with the AI DBA Workbench API, using httpx.
    
    Copyright (c) 2026, pgEdge, Inc.
    This code is released under the PostgreSQL License.
    """
    
    import os
    import sys
    
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
        return {
            "base_url": (
                os.environ.get("WORKBENCH_URL") or "http://localhost:8080"
            ).rstrip("/"),
            "token": token,
            "connection_id": connection_id,
        }
    
    
    def api(cfg: dict, path: str, params: dict) -> list:
        """Sends a GET request to the API and returns the decoded reply.
    
        A request that the server rejects raises an error that includes the
        message from the server, which raise_for_status alone would leave out.
        """
        response = httpx.get(
            f"{cfg['base_url']}/api/v1{path}", params=params, timeout=30,
            headers={"Authorization": f"Bearer {cfg['token']}"},
        )
        if response.is_error:
            raise RuntimeError(
                f"GET {path} failed with status {response.status_code}: "
                f"{response.text.strip()}"
            )
        return response.json()
    
    
    def query_metrics(cfg: dict) -> None:
        """Prints one line for each series that the pg_stat_database probe
        collected over the last hour, in six buckets: the metric, the number
        of points, and the latest value."""
        series = api(cfg, "/metrics/query", {
            "connection_id": cfg["connection_id"],
            "probe_name": "pg_stat_database",
            "time_range": "1h",
            "buckets": 6,
            "metrics": "numbackends,xact_commit",
        })
        if not series:
            raise RuntimeError(
                "The Workbench returned no series; has the collector run yet?"
            )
        for s in series:
            points = s["data"]
            if not points:
                print(f"{s['name']}: no data")
                continue
            print(f"{s['name']}: {len(points)} points, "
                  f"latest {points[-1]['value']}")
    
    
    def top_queries(cfg: dict) -> None:
        """Prints the queries that have used the most execution time, as the
        pg_stat_statements extension on the monitored server recorded them.
    
        The query text is cut to 50 characters on one line.
        """
        queries = api(cfg, "/metrics/top-queries", {
            "connection_id": cfg["connection_id"],
            "limit": 5,
            "order_by": "total_exec_time",
            "exclude_collector": "true",
        })
        if not queries:
            print("No statements recorded (is pg_stat_statements installed?)")
            return
    
        print("Top queries by total execution time:")
        for rank, q in enumerate(queries, start=1):
            text = " ".join(q["query"].split())[:50]
            print(f"{rank}. {q['calls']} calls, "
                  f"{round(q['mean_exec_time'], 2)} ms mean: {text}")
    
    
    def main() -> int:
        try:
            cfg = settings()
            query_metrics(cfg)
            top_queries(cfg)
        # httpx.HTTPError covers failures to connect, and RuntimeError covers
        # replies that the server rejected or that lacked what we need.
        except (httpx.HTTPError, RuntimeError) as e:
            print(f"Error: {e}", file=sys.stderr)
            return 1
        return 0
    
    
    if __name__ == "__main__":
        sys.exit(main())
    
    ```

=== "TypeScript"

    ```typescript
    /*
     * Ellie's Postgres Cookbook
     * Querying metrics and top queries with the AI DBA Workbench API, using the
     * built-in fetch.
     *
     * Copyright (c) 2026, pgEdge, Inc.
     * This code is released under the PostgreSQL License.
     */
    
    // The program needs no imports: fetch and process are built in to Node.js.
    
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
    
    // Sends a GET request to the API and returns the decoded reply. A request
    // that the server rejects throws an error that includes the message from the
    // server.
    async function api<T>(
      cfg: Settings,
      path: string,
      params: Record<string, string>,
    ): Promise<T> {
      const response = await fetch(
        `${cfg.baseUrl}/api/v1${path}?${new URLSearchParams(params)}`,
        {
          headers: { Authorization: `Bearer ${cfg.token}` },
          signal: AbortSignal.timeout(30_000),
        },
      );
      if (!response.ok) {
        const text = (await response.text()).trim();
        throw new Error(
          `GET ${path} failed with status ${response.status}: ${text}`,
        );
      }
      return (await response.json()) as T;
    }
    
    interface Series {
      name: string;
      data: Array<{ time: string; value: number }>;
    }
    
    // Prints one line for each series that the pg_stat_database probe collected
    // over the last hour, in six buckets: the metric, the number of points, and
    // the latest value.
    async function queryMetrics(cfg: Settings): Promise<void> {
      const series = await api<Series[]>(cfg, "/metrics/query", {
        connection_id: cfg.connectionId,
        probe_name: "pg_stat_database",
        time_range: "1h",
        buckets: "6",
        metrics: "numbackends,xact_commit",
      });
      if (series.length === 0) {
        throw new Error("The Workbench returned no series; has the collector run yet?");
      }
      for (const s of series) {
        if (s.data.length === 0) {
          console.log(`${s.name}: no data`);
          continue;
        }
        const latest = s.data[s.data.length - 1].value;
        console.log(`${s.name}: ${s.data.length} points, latest ${latest}`);
      }
    }
    
    interface TopQuery {
      query: string;
      calls: number;
      mean_exec_time: number;
    }
    
    // Prints the queries that have used the most execution time, as the
    // pg_stat_statements extension on the monitored server recorded them. The
    // query text is cut to 50 characters on one line.
    async function topQueries(cfg: Settings): Promise<void> {
      const queries = await api<TopQuery[]>(cfg, "/metrics/top-queries", {
        connection_id: cfg.connectionId,
        limit: "5",
        order_by: "total_exec_time",
        exclude_collector: "true",
      });
      if (queries.length === 0) {
        console.log("No statements recorded (is pg_stat_statements installed?)");
        return;
      }
    
      console.log("Top queries by total execution time:");
      queries.forEach((q, i) => {
        const text = q.query.split(/\s+/).filter(Boolean).join(" ").slice(0, 50);
        const mean = Math.round(q.mean_exec_time * 100) / 100;
        console.log(`${i + 1}. ${q.calls} calls, ${mean} ms mean: ${text}`);
      });
    }
    
    async function main(): Promise<number> {
      try {
        const cfg = settings();
        await queryMetrics(cfg);
        await topQueries(cfg);
      } catch (err) {
        console.error(`Error: ${err instanceof Error ? err.message : err}`);
        return 1;
      }
      return 0;
    }
    
    process.exitCode = await main();
    
    ```

=== "Java"

    ```java
    /*
     * Ellie's Postgres Cookbook
     * Querying metrics and top queries with the AI DBA Workbench API, using
     * java.net.http and Jackson.
     *
     * Copyright (c) 2026, pgEdge, Inc.
     * This code is released under the PostgreSQL License.
     */
    
    import java.io.IOException;
    import java.math.BigDecimal;
    import java.net.URI;
    import java.net.URLEncoder;
    import java.net.http.HttpClient;
    import java.net.http.HttpRequest;
    import java.net.http.HttpResponse;
    import java.net.http.HttpTimeoutException;
    import java.nio.charset.StandardCharsets;
    import java.time.Duration;
    import java.util.LinkedHashMap;
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
         * Sends a GET request to the API, with the parameters in the query
         * string, and returns the JSON reply. A request that the server
         * rejects throws an error that includes the message from the server.
         */
        static JsonNode api(Settings cfg, String path, Map<String, String> params)
                throws IOException, InterruptedException {
            String query = params.entrySet().stream()
                    .map(p -> URLEncoder.encode(p.getKey(), StandardCharsets.UTF_8)
                            + "=" + URLEncoder.encode(p.getValue(),
                                    StandardCharsets.UTF_8))
                    .collect(Collectors.joining("&"));
            HttpRequest request = HttpRequest
                    .newBuilder(URI.create(
                            cfg.baseUrl() + "/api/v1" + path + "?" + query))
                    .timeout(Duration.ofSeconds(30))
                    .header("Authorization", "Bearer " + cfg.token())
                    .GET()
                    .build();
    
            HttpResponse<String> response = send(request);
            if (response.statusCode() >= 400) {
                throw new IOException("GET " + path + " failed with status "
                        + response.statusCode() + ": " + response.body().strip());
            }
            return JSON.readTree(response.body());
        }
    
        /**
         * Returns a number as plain decimal text, without an exponent or
         * trailing zeros, as the other languages print it.
         */
        static String plain(double value) {
            return BigDecimal.valueOf(value).stripTrailingZeros().toPlainString();
        }
    
        /**
         * Prints one line for each series that the pg_stat_database probe
         * collected over the last hour, in six buckets: the metric, the number
         * of points, and the latest value.
         */
        static void queryMetrics(Settings cfg)
                throws IOException, InterruptedException {
            // A LinkedHashMap keeps the parameters in the order given.
            Map<String, String> params = new LinkedHashMap<>();
            params.put("connection_id", cfg.connectionId());
            params.put("probe_name", "pg_stat_database");
            params.put("time_range", "1h");
            params.put("buckets", "6");
            params.put("metrics", "numbackends,xact_commit");
    
            JsonNode series = api(cfg, "/metrics/query", params);
            if (series.isEmpty()) {
                throw new IOException(
                        "The Workbench returned no series; has the collector run yet?");
            }
            for (JsonNode s : series) {
                JsonNode points = s.path("data");
                String name = s.get("name").asString();
                if (points.isEmpty()) {
                    System.out.println(name + ": no data");
                    continue;
                }
                double latest = points.get(points.size() - 1).get("value")
                        .asDouble();
                System.out.println(name + ": " + points.size()
                        + " points, latest " + plain(latest));
            }
        }
    
        /**
         * Prints the queries that have used the most execution time, as the
         * pg_stat_statements extension on the monitored server recorded them.
         * The query text is cut to 50 characters on one line.
         */
        static void topQueries(Settings cfg)
                throws IOException, InterruptedException {
            Map<String, String> params = new LinkedHashMap<>();
            params.put("connection_id", cfg.connectionId());
            params.put("limit", "5");
            params.put("order_by", "total_exec_time");
            params.put("exclude_collector", "true");
    
            JsonNode queries = api(cfg, "/metrics/top-queries", params);
            if (queries.isEmpty()) {
                System.out.println(
                        "No statements recorded (is pg_stat_statements installed?)");
                return;
            }
    
            System.out.println("Top queries by total execution time:");
            int rank = 1;
            for (JsonNode q : queries) {
                String text = q.get("query").asString().strip()
                        .replaceAll("\\s+", " ");
                // Count characters, not UTF-16 units, when cutting the text.
                if (text.codePointCount(0, text.length()) > 50) {
                    text = text.substring(0, text.offsetByCodePoints(0, 50));
                }
                double mean = Math.round(
                        q.get("mean_exec_time").asDouble() * 100) / 100.0;
                System.out.println(rank + ". " + q.get("calls").asLong()
                        + " calls, " + plain(mean) + " ms mean: " + text);
                rank++;
            }
        }
    
        /**
         * Returns the message of an error. Some errors, such as a refused
         * connection, have no message, so their type stands in for one.
         */
        static String describe(Exception e) {
            return Objects.requireNonNullElse(e.getMessage(), e.toString());
        }
    
        public static void main(String[] args) {
            int status = 0;
            try {
                Settings cfg = settings();
                queryMetrics(cfg);
                topQueries(cfg);
            // IOException covers failures to connect, replies that the server
            // rejected, and replies that lacked what we need; the client
            // throws InterruptedException if the thread is interrupted, and
            // Jackson throws JacksonException for a reply that is not JSON.
            } catch (IOException | InterruptedException | JacksonException e) {
                System.err.println("Error: " + describe(e));
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
     * Querying metrics and top queries with the AI DBA Workbench API, using
     * HttpClient and System.Text.Json.
     *
     * Copyright (c) 2026, pgEdge, Inc.
     * This code is released under the PostgreSQL License.
     */
    
    using System.Globalization;
    using System.Net.Http.Headers;
    using System.Text.Json;
    using System.Text.Json.Nodes;
    using System.Text.RegularExpressions;
    
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
    
    // Sends a GET request to the API, with the parameters in the query string,
    // and returns the JSON reply. A request that the server rejects throws an
    // error that includes the message from the server.
    async Task<JsonArray> Api(string baseUrl, string token, string path,
        Dictionary<string, string> parameters)
    {
        var query = string.Join("&", parameters.Select(p =>
            $"{Uri.EscapeDataString(p.Key)}={Uri.EscapeDataString(p.Value)}"));
        using var request = new HttpRequestMessage(HttpMethod.Get,
            $"{baseUrl}/api/v1{path}?{query}");
        request.Headers.Authorization =
            new AuthenticationHeaderValue("Bearer", token);
    
        using var response = await http.SendAsync(request);
        var text = await response.Content.ReadAsStringAsync();
        if ((int)response.StatusCode >= 400)
        {
            throw new HttpRequestException(
                $"GET {path} failed with status {(int)response.StatusCode}: "
                + text.Trim());
        }
        return JsonNode.Parse(text)?.AsArray()
            ?? throw new InvalidOperationException($"GET {path} returned no JSON");
    }
    
    // Returns a number as plain decimal text, without an exponent or trailing
    // zeros, and with a full stop whatever the locale.
    static string Plain(double value) =>
        value.ToString("0.###############", CultureInfo.InvariantCulture);
    
    // Prints one line for each series that the pg_stat_database probe
    // collected over the last hour, in six buckets: the metric, the number of
    // points, and the latest value.
    async Task QueryMetrics(string baseUrl, string token, string connectionId)
    {
        var series = await Api(baseUrl, token, "/metrics/query", new()
        {
            ["connection_id"] = connectionId,
            ["probe_name"] = "pg_stat_database",
            ["time_range"] = "1h",
            ["buckets"] = "6",
            ["metrics"] = "numbackends,xact_commit",
        });
        if (series.Count == 0)
        {
            throw new InvalidOperationException(
                "The Workbench returned no series; has the collector run yet?");
        }
        foreach (var s in series)
        {
            var name = s!["name"]!.GetValue<string>();
            var points = s["data"]?.AsArray();
            if (points is null || points.Count == 0)
            {
                Console.WriteLine($"{name}: no data");
                continue;
            }
            var latest = points[^1]!["value"]!.GetValue<double>();
            Console.WriteLine(
                $"{name}: {points.Count} points, latest {Plain(latest)}");
        }
    }
    
    // Prints the queries that have used the most execution time, as the
    // pg_stat_statements extension on the monitored server recorded them. The
    // query text is cut to 50 characters on one line.
    async Task TopQueries(string baseUrl, string token, string connectionId)
    {
        var queries = await Api(baseUrl, token, "/metrics/top-queries", new()
        {
            ["connection_id"] = connectionId,
            ["limit"] = "5",
            ["order_by"] = "total_exec_time",
            ["exclude_collector"] = "true",
        });
        if (queries.Count == 0)
        {
            Console.WriteLine(
                "No statements recorded (is pg_stat_statements installed?)");
            return;
        }
    
        Console.WriteLine("Top queries by total execution time:");
        var rank = 1;
        foreach (var q in queries)
        {
            var text = Regex.Replace(q!["query"]!.GetValue<string>().Trim(),
                @"\s+", " ");
            // Count characters, not UTF-16 units, when cutting the text.
            text = string.Concat(text.EnumerateRunes().Take(50));
            var mean = Math.Round(q["mean_exec_time"]!.GetValue<double>(), 2,
                MidpointRounding.AwayFromZero);
            Console.WriteLine($"{rank}. {q["calls"]!.GetValue<long>()} calls, "
                + $"{Plain(mean)} ms mean: {text}");
            rank++;
        }
    }
    
    try
    {
        var (baseUrl, token, connectionId) = Settings();
        await QueryMetrics(baseUrl, token, connectionId);
        await TopQueries(baseUrl, token, connectionId);
    }
    // HttpRequestException covers failures to connect and replies that the
    // server rejected, TaskCanceledException covers a request that timed out,
    // and the others cover replies that lacked what we need.
    catch (Exception e) when (e is HttpRequestException
        or TaskCanceledException or InvalidOperationException or JsonException)
    {
        Console.Error.WriteLine($"Error: {e.Message}");
        return 1;
    }
    return 0;
    
    ```

=== "Go"

    ```go
    /*
     * Ellie's Postgres Cookbook
     * Querying metrics and top queries with the AI DBA Workbench API, using
     * net/http.
     *
     * Copyright (c) 2026, pgEdge, Inc.
     * This code is released under the PostgreSQL License.
     */
    
    package main
    
    import (
    	"encoding/json"
    	"errors"
    	"fmt"
    	"io"
    	"math"
    	"net/http"
    	"net/url"
    	"os"
    	"strconv"
    	"strings"
    	"time"
    )
    
    
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
    
    // get sends a GET request to the API and decodes the JSON reply into out. A
    // request that the server rejects returns an error that includes the
    // message from the server.
    func get(s settings, path string, params url.Values, out any) error {
    	req, err := http.NewRequest("GET", s.baseURL+"/api/v1"+path+"?"+params.Encode(), nil)
    	if err != nil {
    		return err
    	}
    	req.Header.Set("Authorization", "Bearer "+s.token)
    
    	resp, err := client.Do(req)
    	if err != nil {
    		return err
    	}
    	defer resp.Body.Close()
    	if resp.StatusCode >= 400 {
    		text, _ := io.ReadAll(resp.Body)
    		return fmt.Errorf("GET %s failed with status %d: %s",
    			path, resp.StatusCode, strings.TrimSpace(string(text)))
    	}
    	return json.NewDecoder(resp.Body).Decode(out)
    }
    
    
    // series is one metric, with its points over time.
    type series struct {
    	Name string `json:"name"`
    	Data []struct {
    		Time  string  `json:"time"`
    		Value float64 `json:"value"`
    	} `json:"data"`
    }
    
    // queryMetrics prints one line for each series that the pg_stat_database
    // probe collected over the last hour, in six buckets: the metric, the number
    // of points, and the latest value.
    func queryMetrics(s settings) error {
    	var result []series
    	err := get(s, "/metrics/query", url.Values{
    		"connection_id": {s.connectionID},
    		"probe_name":    {"pg_stat_database"},
    		"time_range":    {"1h"},
    		"buckets":       {"6"},
    		"metrics":       {"numbackends,xact_commit"},
    	}, &result)
    	if err != nil {
    		return err
    	}
    	if len(result) == 0 {
    		return errors.New("the Workbench returned no series; has the collector run yet?")
    	}
    	for _, m := range result {
    		if len(m.Data) == 0 {
    			fmt.Printf("%s: no data\n", m.Name)
    			continue
    		}
    		latest := m.Data[len(m.Data)-1].Value
    		fmt.Printf("%s: %d points, latest %s\n", m.Name, len(m.Data),
    			strconv.FormatFloat(latest, 'f', -1, 64))
    	}
    	return nil
    }
    
    
    // topQuery is the part of a top query that the program prints.
    type topQuery struct {
    	Query        string  `json:"query"`
    	Calls        int64   `json:"calls"`
    	MeanExecTime float64 `json:"mean_exec_time"`
    }
    
    // topQueries prints the queries that have used the most execution time, as
    // the pg_stat_statements extension on the monitored server recorded them.
    // The query text is cut to 50 characters on one line.
    func topQueries(s settings) error {
    	var queries []topQuery
    	err := get(s, "/metrics/top-queries", url.Values{
    		"connection_id":     {s.connectionID},
    		"limit":             {"5"},
    		"order_by":          {"total_exec_time"},
    		"exclude_collector": {"true"},
    	}, &queries)
    	if err != nil {
    		return err
    	}
    	if len(queries) == 0 {
    		fmt.Println("No statements recorded (is pg_stat_statements installed?)")
    		return nil
    	}
    
    	fmt.Println("Top queries by total execution time:")
    	for i, q := range queries {
    		text := []rune(strings.Join(strings.Fields(q.Query), " "))
    		if len(text) > 50 {
    			text = text[:50]
    		}
    		mean := math.Round(q.MeanExecTime*100) / 100
    		fmt.Printf("%d. %d calls, %s ms mean: %s\n", i+1, q.Calls,
    			strconv.FormatFloat(mean, 'f', -1, 64), string(text))
    	}
    	return nil
    }
    
    
    func main() {
    	s, err := loadSettings()
    	if err == nil {
    		err = queryMetrics(s)
    	}
    	if err == nil {
    		err = topQueries(s)
    	}
    	if err != nil {
    		fmt.Fprintln(os.Stderr, "Error:", err)
    		os.Exit(1)
    	}
    }
    
    
    ```

=== "Rust"

    ```rust
    // Ellie's Postgres Cookbook
    // Querying metrics and top queries with the AI DBA Workbench API, using
    // reqwest and serde_json.
    //
    // Copyright (c) 2026, pgEdge, Inc.
    // This code is released under the PostgreSQL License.
    
    use std::env;
    use std::error::Error;
    use std::process::ExitCode;
    use std::sync::LazyLock;
    use std::time::Duration;
    
    use reqwest::blocking::Client;
    use reqwest::Url;
    use serde_json::Value;
    
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
    
    ```

=== "Ruby"

    ```ruby
    # Ellie's Postgres Cookbook
    # Querying metrics and top queries with the AI DBA Workbench API, using
    # Net::HTTP.
    #
    # Copyright (c) 2026, pgEdge, Inc.
    # This code is released under the PostgreSQL License.
    
    require "json"
    require "net/http"
    
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
    
    # Sends a GET request to the API, with the parameters in the query string,
    # and returns the decoded reply. A request that the server rejects raises
    # an error that includes the message from the server.
    def api(cfg, path, params)
      uri = URI("#{cfg[:base_url]}/api/v1#{path}")
      uri.query = URI.encode_www_form(params)
    
      # Net::HTTP has no overall timeout, so limit both the connection and
      # each read.
      response = Net::HTTP.start(uri.host, uri.port,
                                 use_ssl: uri.scheme == "https",
                                 open_timeout: 30, read_timeout: 30) do |http|
        http.get(uri.request_uri, "Authorization" => "Bearer #{cfg[:token]}")
      end
      if response.code.to_i >= 400
        raise "GET #{path} failed with status #{response.code}: " \
              "#{response.body.to_s.strip}"
      end
      JSON.parse(response.body)
    end
    
    # Prints one line for each series that the pg_stat_database probe collected
    # over the last hour, in six buckets: the metric, the number of points, and
    # the latest value.
    def query_metrics(cfg)
      series = api(cfg, "/metrics/query", {
                     connection_id: cfg[:connection_id],
                     probe_name: "pg_stat_database",
                     time_range: "1h",
                     buckets: 6,
                     metrics: "numbackends,xact_commit"
                   })
      raise "The Workbench returned no series; has the collector run yet?" if series.empty?
    
      series.each do |s|
        points = s["data"] || []
        if points.empty?
          puts "#{s.fetch('name')}: no data"
          next
        end
        puts "#{s.fetch('name')}: #{points.length} points, " \
             "latest #{points.last.fetch('value')}"
      end
    end
    
    # Prints the queries that have used the most execution time, as the
    # pg_stat_statements extension on the monitored server recorded them. The
    # query text is cut to 50 characters on one line.
    def top_queries(cfg)
      queries = api(cfg, "/metrics/top-queries", {
                      connection_id: cfg[:connection_id],
                      limit: 5,
                      order_by: "total_exec_time",
                      exclude_collector: "true"
                    })
      if queries.empty?
        puts "No statements recorded (is pg_stat_statements installed?)"
        return
      end
    
      puts "Top queries by total execution time:"
      queries.each.with_index(1) do |q, rank|
        text = q.fetch("query").split.join(" ")[0, 50]
        puts "#{rank}. #{q.fetch('calls')} calls, " \
             "#{q.fetch('mean_exec_time').round(2)} ms mean: #{text}"
      end
    end
    
    def main
      cfg = settings
      query_metrics(cfg)
      top_queries(cfg)
      0
    # Net::HTTP raises errors of many classes, such as SystemCallError for a
    # refused connection and Net::OpenTimeout for a timeout, and the program
    # raises RuntimeError for replies that the server rejected or that lacked
    # what we need, so this catches StandardError, their common ancestor.
    rescue StandardError => e
      warn "Error: #{e.message}"
      1
    end
    
    exit main
    
    ```

=== "curl"

    ```bash
    #!/usr/bin/env bash
    #
    # Ellie's Postgres Cookbook
    # Querying metrics and top queries with the AI DBA Workbench API, using curl
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
    
    # Sends an authenticated GET request and prints the JSON reply:
    # api PATH [curl options]. With --fail-with-body, a request that the server
    # rejects leaves the server's error message in the reply, and the function
    # prints it to standard error.
    # The token goes to curl in a header file that bash supplies through a pipe,
    # so that it never appears in the arguments of the curl process, which other
    # users can read in the process list.
    api() {
        local path="$1"
        shift
        local response
        response=$(curl --silent --show-error --fail-with-body --get \
            --connect-timeout 10 --max-time 30 \
            --header @<(printf 'Authorization: Bearer %s\n' "$WORKBENCH_TOKEN") \
            "$@" "$WORKBENCH_URL/api/v1$path") || {
            echo "GET $path failed: $response" >&2
            return 1
        }
        printf '%s' "$response"
    }
    
    # Prints one line for each series that the pg_stat_database probe collected
    # over the last hour, in six buckets: the metric, the number of points, and
    # the latest value. The --data-urlencode options build the query string.
    query_metrics() {
        local series
        series=$(api /metrics/query \
            --data-urlencode "connection_id=$WORKBENCH_CONNECTION_ID" \
            --data-urlencode "probe_name=pg_stat_database" \
            --data-urlencode "time_range=1h" \
            --data-urlencode "buckets=6" \
            --data-urlencode "metrics=numbackends,xact_commit")
    
        if [[ "$(jq length <<<"$series")" -eq 0 ]]; then
            echo "The Workbench returned no series; has the collector run yet?" >&2
            return 1
        fi
        jq -r <<<"$series" '.[] | if .data == [] then "\(.name): no data"
                         else "\(.name): \(.data | length) points, latest \(.data | last | .value)"
                         end'
    }
    
    # Prints the queries that have used the most execution time, as the
    # pg_stat_statements extension on the monitored server recorded them.
    # The query text is cut to 50 characters on one line.
    top_queries() {
        local queries
        queries=$(api /metrics/top-queries \
            --data-urlencode "connection_id=$WORKBENCH_CONNECTION_ID" \
            --data-urlencode "limit=5" \
            --data-urlencode "order_by=total_exec_time" \
            --data-urlencode "exclude_collector=true")
    
        if [[ "$(jq length <<<"$queries")" -eq 0 ]]; then
            echo "No statements recorded (is pg_stat_statements installed?)"
            return
        fi
        echo "Top queries by total execution time:"
        jq -r 'to_entries[] | "\(.key + 1). \(.value.calls) calls, \(.value.mean_exec_time * 100 | round / 100) ms mean: \(.value.query | gsub("\\s+"; " ") | .[0:50])"' \
            <<<"$queries"
    }
    
    main() {
        query_metrics
        top_queries
    }
    
    main
    
    ```

## Next Steps

The following resources provide more information about the topics in this
recipe:

- The [Listing and Acknowledging Alerts](alerts.md) recipe shows how the
  Workbench raises alerts from these metrics.
- The AI DBA Workbench
  [probes guide](https://github.com/pgEdge/ai-dba-workbench/blob/v1.0.0/docs/admin-guide/probes.md)
  describes the probes and their collection intervals.
- The AI DBA Workbench
  [API reference](https://github.com/pgEdge/ai-dba-workbench/blob/v1.0.0/docs/admin-guide/api/reference.md)
  describes every endpoint.
