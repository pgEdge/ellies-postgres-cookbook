# Calling AI DBA Workbench MCP Tools

This recipe shows how a program calls the tools that the pgEdge AI DBA
Workbench offers through its Model Context Protocol (MCP) endpoint. These
examples are for AI DBA Workbench 1.0.0. Each step shows the code in every
supported language; selecting a language tab switches every tab on the site to
that language.

MCP is a protocol in which a client lists the tools that a server offers and
then calls them, and it is built on JSON-RPC 2.0 over HTTP. The Workbench
serves it at `/mcp/v1`, and the same tools are available to any MCP client,
such as an AI assistant. The example program introduces itself to the server,
lists the tools, runs a read-only query with the `query_database` tool, and
plans another query with the `execute_explain` tool. The output has the
following form:

```text
Server: pgedge-postgres-mcp 1.0.0
query_database requires: query
execute_explain requires: query
Columns: greeting, answer
Row: Hello from the Workbench, 42
Plan starts with: Result
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
PostgreSQL server, and an API token for a user that may use the tools. The
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
the requests and read the JSON replies. The following tabs show the dependency
declaration from each example project:

=== "Python"

    ```text
    # httpx, an HTTP client with a requests-like interface.
    httpx>=0.28,<1
    ```

=== "TypeScript"

    ```json
    {
      "name": "mcp_tools",
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
    import re
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
    import java.net.URI;
    import java.net.http.HttpClient;
    import java.net.http.HttpRequest;
    import java.net.http.HttpResponse;
    import java.net.http.HttpTimeoutException;
    import java.time.Duration;
    import java.util.Arrays;
    import java.util.HashMap;
    import java.util.List;
    import java.util.Map;
    import java.util.Objects;
    import java.util.concurrent.CompletableFuture;
    import java.util.concurrent.ExecutionException;
    import java.util.concurrent.TimeUnit;
    import java.util.concurrent.TimeoutException;
    import java.util.regex.Matcher;
    import java.util.regex.Pattern;
    import tools.jackson.core.JacksonException;
    import tools.jackson.databind.JsonNode;
    import tools.jackson.databind.ObjectMapper;
    ```

=== "C#"

    ```csharp
    using System.Net.Http.Headers;
    using System.Net.Http.Json;
    using System.Text.Json;
    using System.Text.Json.Nodes;
    using System.Text.RegularExpressions;
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
    	"os"
    	"regexp"
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
    
    # The script needs curl to make the requests and jq to build the requests
    # and read the replies.
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

The [Authenticating with the AI DBA Workbench API](authenticate.md) recipe
shows how to create an API token. The MCP endpoint accepts the token as a
`Bearer` credential and answers a request without one with a 401 status. The
following tabs show how each program reads the settings and stops with an error
when the token or the connection ID is missing:

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
        if (!Regex.IsMatch(connectionId, "^[0-9]+$"))
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
        let connection_id = connection_id
            .parse()
            .map_err(|_| "WORKBENCH_CONNECTION_ID must be a number")?;
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
      raise "WORKBENCH_CONNECTION_ID must be a number" unless connection_id.match?(/\A[0-9]+\z/)
    
      {
        base_url: env_or("WORKBENCH_URL", "http://localhost:8080").sub(%r{/+\z}, ""),
        token: token,
        connection_id: connection_id.to_i
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

## Sending JSON-RPC Requests

Every MCP call is a `POST` request to `/mcp/v1` with a JSON-RPC body that holds
the `jsonrpc` version, an `id`, a `method`, and its `params`. The Workbench
keeps no session between requests, so the requests carry nothing but the token.
The server answers a JSON-RPC error with a 200 HTTP status and an `error`
member in the body, so the helper function checks for both kinds of failure
before it returns the `result` member. The following tabs show the helper
function from each program:

=== "Python"

    ```python
    def rpc(cfg: dict, method: str, params: dict) -> dict:
        """Sends a JSON-RPC request to the MCP endpoint and returns the result.
    
        The server answers a JSON-RPC error with HTTP status 200, so the
        function checks the reply for an error member as well as for an HTTP
        failure.
        """
        response = httpx.post(
            f"{cfg['base_url']}/mcp/v1", timeout=30,
            headers={"Authorization": f"Bearer {cfg['token']}"},
            json={"jsonrpc": "2.0", "id": 1, "method": method, "params": params},
        )
        if response.is_error:
            raise RuntimeError(
                f"{method} failed with status {response.status_code}: "
                f"{response.text.strip()}"
            )
        reply = response.json()
        if "error" in reply:
            raise RuntimeError(f"{method} failed: {reply['error']['message']}")
        return reply["result"]
    ```

=== "TypeScript"

    ```typescript
    // Sends a JSON-RPC request to the MCP endpoint and returns the result. The
    // server answers a JSON-RPC error with HTTP status 200, so the function
    // checks the reply for an error member as well as for an HTTP failure.
    async function rpc<T>(
      s: Settings,
      method: string,
      params: unknown,
    ): Promise<T> {
      const response = await fetch(`${s.baseUrl}/mcp/v1`, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${s.token}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ jsonrpc: "2.0", id: 1, method, params }),
        signal: AbortSignal.timeout(30_000),
      });
      if (!response.ok) {
        const text = (await response.text()).trim();
        throw new Error(`${method} failed with status ${response.status}: ${text}`);
      }
      const reply = (await response.json()) as {
        result?: T;
        error?: { message: string };
      };
      if (reply.error) throw new Error(`${method} failed: ${reply.error.message}`);
      return reply.result as T;
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
     * Sends a JSON-RPC request to the MCP endpoint and returns the result.
     * The server answers a JSON-RPC error with HTTP status 200, so the
     * method checks the reply for an error member as well as for an HTTP
     * failure.
     */
    static JsonNode rpc(Settings cfg, String method, Object params)
            throws IOException, InterruptedException {
        String body = JSON.writeValueAsString(Map.of(
                "jsonrpc", "2.0", "id", 1, "method", method,
                "params", params));
        HttpRequest request = HttpRequest
                .newBuilder(URI.create(cfg.baseUrl() + "/mcp/v1"))
                .timeout(Duration.ofSeconds(30))
                .header("Authorization", "Bearer " + cfg.token())
                .header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString(body))
                .build();
    
        HttpResponse<String> response = send(request);
        if (response.statusCode() >= 400) {
            throw new IOException(method + " failed with status "
                    + response.statusCode() + ": " + response.body().strip());
        }
        JsonNode reply = JSON.readTree(response.body());
        if (reply.has("error")) {
            throw new IOException(method + " failed: "
                    + reply.get("error").get("message").asString());
        }
        return reply.get("result");
    }
    ```

=== "C#"

    ```csharp
    // One client serves every request, with a timeout for each.
    var http = new HttpClient { Timeout = TimeSpan.FromSeconds(30) };
    
    // Sends a JSON-RPC request to the MCP endpoint and returns the result. The
    // server answers a JSON-RPC error with HTTP status 200, so the function
    // checks the reply for an error member as well as for an HTTP failure.
    async Task<JsonNode> Rpc(string baseUrl, string token, string method,
        object parameters)
    {
        using var request = new HttpRequestMessage(HttpMethod.Post,
            $"{baseUrl}/mcp/v1")
        {
            Content = JsonContent.Create(new
            {
                jsonrpc = "2.0",
                id = 1,
                method,
                @params = parameters,
            }),
        };
        request.Headers.Authorization =
            new AuthenticationHeaderValue("Bearer", token);
    
        using var response = await http.SendAsync(request);
        var text = await response.Content.ReadAsStringAsync();
        if ((int)response.StatusCode >= 400)
        {
            throw new HttpRequestException(
                $"{method} failed with status {(int)response.StatusCode}: "
                + text.Trim());
        }
        var reply = JsonNode.Parse(text)
            ?? throw new InvalidOperationException($"{method} returned no JSON");
        if (reply["error"] is JsonNode error)
        {
            throw new InvalidOperationException(
                $"{method} failed: {error["message"]}");
        }
        return reply["result"]
            ?? throw new InvalidOperationException($"{method} had no result");
    }
    ```

=== "Go"

    ```go
    // client gives every request a timeout; the default client has none.
    var client = &http.Client{Timeout: 30 * time.Second}
    
    // rpc sends a JSON-RPC request to the MCP endpoint and decodes the result
    // into out. The server answers a JSON-RPC error with HTTP status 200, so the
    // function checks the reply for an error member as well as for an HTTP
    // failure.
    func rpc(s settings, method string, params, out any) error {
    	body, err := json.Marshal(map[string]any{
    		"jsonrpc": "2.0", "id": 1, "method": method, "params": params,
    	})
    	if err != nil {
    		return err
    	}
    	req, err := http.NewRequest("POST", s.baseURL+"/mcp/v1", bytes.NewReader(body))
    	if err != nil {
    		return err
    	}
    	req.Header.Set("Authorization", "Bearer "+s.token)
    	req.Header.Set("Content-Type", "application/json")
    
    	resp, err := client.Do(req)
    	if err != nil {
    		return err
    	}
    	defer resp.Body.Close()
    	if resp.StatusCode >= 400 {
    		text, _ := io.ReadAll(resp.Body)
    		return fmt.Errorf("%s failed with status %d: %s",
    			method, resp.StatusCode, strings.TrimSpace(string(text)))
    	}
    
    	var reply struct {
    		Result json.RawMessage `json:"result"`
    		Error  *struct {
    			Message string `json:"message"`
    		} `json:"error"`
    	}
    	if err := json.NewDecoder(resp.Body).Decode(&reply); err != nil {
    		return err
    	}
    	if reply.Error != nil {
    		return fmt.Errorf("%s failed: %s", method, reply.Error.Message)
    	}
    	return json.Unmarshal(reply.Result, out)
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
    
    /// Sends a JSON-RPC request to the MCP endpoint and returns the result.
    /// The server answers a JSON-RPC error with HTTP status 200, so the
    /// function checks the reply for an error member as well as for an HTTP
    /// failure.
    fn rpc(cfg: &Settings, method: &str, params: Value) -> Result<Value> {
        let response = CLIENT
            .post(format!("{}/mcp/v1", cfg.base_url))
            .bearer_auth(&cfg.token)
            .json(&json!({ "jsonrpc": "2.0", "id": 1, "method": method, "params": params }))
            .send()?;
        let status = response.status().as_u16();
        if status >= 400 {
            let text = response.text()?;
            return Err(format!("{method} failed with status {status}: {}", text.trim()).into());
        }
        let mut reply: Value = response.json()?;
        if let Some(error) = reply.get("error") {
            let message = error["message"].as_str().unwrap_or_default();
            return Err(format!("{method} failed: {message}").into());
        }
        match reply.get_mut("result") {
            Some(result) => Ok(result.take()),
            None => Err(format!("{method} had no result").into()),
        }
    }
    ```

=== "Ruby"

    ```ruby
    # Sends a JSON-RPC request to the MCP endpoint and returns the result. The
    # server answers a JSON-RPC error with HTTP status 200, so the method
    # checks the reply for an error member as well as for an HTTP failure.
    def rpc(cfg, method, params)
      uri = URI("#{cfg[:base_url]}/mcp/v1")
      headers = {
        "Authorization" => "Bearer #{cfg[:token]}",
        "Content-Type" => "application/json"
      }
      body = { jsonrpc: "2.0", id: 1, method: method, params: params }.to_json
    
      # Net::HTTP has no overall timeout, so limit both the connection and
      # each read.
      response = Net::HTTP.start(uri.host, uri.port,
                                 use_ssl: uri.scheme == "https",
                                 open_timeout: 30, read_timeout: 30) do |http|
        http.post(uri.request_uri, body, headers)
      end
      if response.code.to_i >= 400
        raise "#{method} failed with status #{response.code}: " \
              "#{response.body.to_s.strip}"
      end
      reply = JSON.parse(response.body)
      raise "#{method} failed: #{reply['error']['message']}" if reply.key?("error")
    
      reply.fetch("result")
    end
    ```

=== "curl"

    ```bash
    # Sends a JSON-RPC request to the MCP endpoint and prints the result:
    # rpc METHOD PARAMS_JSON. The server answers a JSON-RPC error with HTTP
    # status 200, so the function checks the reply for an error member as well as
    # for an HTTP failure.
    # The token goes to curl in a header file that bash supplies through a pipe,
    # so that it never appears in the arguments of the curl process, which other
    # users can read in the process list.
    rpc() {
        local method="$1" params="$2"
        local response
        response=$(jq -n --arg method "$method" --argjson params "$params" \
            '{jsonrpc: "2.0", id: 1, method: $method, params: $params}' |
            curl --silent --show-error --fail-with-body \
                --connect-timeout 10 --max-time 30 \
                --header @<(printf 'Authorization: Bearer %s\n' "$WORKBENCH_TOKEN") \
                --header 'Content-Type: application/json' \
                --data @- "$WORKBENCH_URL/mcp/v1") || {
            echo "$method failed: $response" >&2
            return 1
        }
        if jq -e '.error' >/dev/null 2>&1 <<<"$response"; then
            echo "$method failed: $(jq -r '.error.message' <<<"$response")" >&2
            return 1
        fi
        jq -c '.result' <<<"$response"
    }
    ```

## Introducing the Client

The `initialize` method tells the server which protocol version the client
speaks, and the reply names the server and its version. The Workbench does not
require this step, because it keeps no session, but a well-behaved MCP client
sends it first. The following tabs show how each program calls the method and
prints the name and version of the server:

=== "Python"

    ```python
    def initialize(cfg: dict) -> None:
        """Introduces the client to the server and prints the server's name and
        version. The Workbench keeps no session, so a client can skip this
        step."""
        result = rpc(cfg, "initialize", {
            "protocolVersion": "2024-11-05",
            "capabilities": {},
            "clientInfo": {"name": "cookbook", "version": "1.0.0"},
        })
        info = result["serverInfo"]
        print(f"Server: {info['name']} {info['version']}")
    ```

=== "TypeScript"

    ```typescript
    // Introduces the client to the server and prints the server's name and
    // version. The Workbench keeps no session, so a client can skip this step.
    async function initialize(s: Settings): Promise<void> {
      const result = await rpc<{ serverInfo: { name: string; version: string } }>(
        s,
        "initialize",
        {
          protocolVersion: "2024-11-05",
          capabilities: {},
          clientInfo: { name: "cookbook", version: "1.0.0" },
        },
      );
      console.log(`Server: ${result.serverInfo.name} ${result.serverInfo.version}`);
    }
    ```

=== "Java"

    ```java
    /**
     * Introduces the client to the server and prints the server's name and
     * version. The Workbench keeps no session, so a client can skip this
     * step.
     */
    static void initialize(Settings cfg)
            throws IOException, InterruptedException {
        JsonNode result = rpc(cfg, "initialize", Map.of(
                "protocolVersion", "2024-11-05",
                "capabilities", Map.of(),
                "clientInfo", Map.of("name", "cookbook", "version", "1.0.0")));
        JsonNode info = result.get("serverInfo");
        System.out.println("Server: " + info.get("name").asString() + " "
                + info.get("version").asString());
    }
    ```

=== "C#"

    ```csharp
    // Introduces the client to the server and prints the server's name and
    // version. The Workbench keeps no session, so a client can skip this step.
    async Task Initialize(string baseUrl, string token)
    {
        var result = await Rpc(baseUrl, token, "initialize", new
        {
            protocolVersion = "2024-11-05",
            capabilities = new { },
            clientInfo = new { name = "cookbook", version = "1.0.0" },
        });
        var info = result["serverInfo"]!;
        Console.WriteLine($"Server: {info["name"]} {info["version"]}");
    }
    ```

=== "Go"

    ```go
    // initialize introduces the client to the server and prints the server's
    // name and version. The Workbench keeps no session, so a client can skip
    // this step.
    func initialize(s settings) error {
    	var result struct {
    		ServerInfo struct {
    			Name    string `json:"name"`
    			Version string `json:"version"`
    		} `json:"serverInfo"`
    	}
    	err := rpc(s, "initialize", map[string]any{
    		"protocolVersion": "2024-11-05",
    		"capabilities":    map[string]any{},
    		"clientInfo":      map[string]any{"name": "cookbook", "version": "1.0.0"},
    	}, &result)
    	if err != nil {
    		return err
    	}
    	fmt.Printf("Server: %s %s\n", result.ServerInfo.Name, result.ServerInfo.Version)
    	return nil
    }
    
    ```

=== "Rust"

    ```rust
    /// Introduces the client to the server and prints the server's name and
    /// version. The Workbench keeps no session, so a client can skip this
    /// step.
    fn initialize(cfg: &Settings) -> Result<()> {
        let result = rpc(
            cfg,
            "initialize",
            json!({
                "protocolVersion": "2024-11-05",
                "capabilities": {},
                "clientInfo": { "name": "cookbook", "version": "1.0.0" },
            }),
        )?;
        let info = &result["serverInfo"];
        let name = info["name"]
            .as_str()
            .ok_or("the reply had no server name")?;
        let version = info["version"]
            .as_str()
            .ok_or("the reply had no server version")?;
        println!("Server: {name} {version}");
        Ok(())
    }
    ```

=== "Ruby"

    ```ruby
    # Introduces the client to the server and prints the server's name and
    # version. The Workbench keeps no session, so a client can skip this step.
    # Ruby uses the name initialize for constructors, so the method has another.
    def initialize_session(cfg)
      result = rpc(cfg, "initialize", {
                     protocolVersion: "2024-11-05",
                     capabilities: {},
                     clientInfo: { name: "cookbook", version: "1.0.0" }
                   })
      info = result.fetch("serverInfo")
      puts "Server: #{info.fetch('name')} #{info.fetch('version')}"
    end
    ```

=== "curl"

    ```bash
    # Introduces the client to the server and prints the server's name and
    # version. The Workbench keeps no session, so a client can skip this step.
    initialize() {
        local result
        result=$(rpc initialize '{
            "protocolVersion": "2024-11-05",
            "capabilities": {},
            "clientInfo": {"name": "cookbook", "version": "1.0.0"}
        }') || return 1
        jq -r '"Server: \(.serverInfo.name) \(.serverInfo.version)"' <<<"$result"
    }
    ```

## Listing the Tools

The `tools/list` method returns every tool that the server offers, and each
tool has a `name`, a `description`, and an `inputSchema` in JSON Schema form.
The Workbench lists its tools in no fixed order, so the program looks the two
tools that it needs up by name, stops with an error if either is missing, and
prints the arguments that each one requires from the `required` member of its
schema. The following tabs show how each program lists the tools:

=== "Python"

    ```python
    def list_tools(cfg: dict) -> None:
        """Lists the tools, checks that the two that the program calls are
        present, and prints the arguments that each one requires."""
        tools = {t["name"]: t for t in rpc(cfg, "tools/list", {})["tools"]}
        # The server lists its tools in no fixed order, so look the two tools
        # up by name.
        for name in ("query_database", "execute_explain"):
            if name not in tools:
                raise RuntimeError(f"The server does not offer {name}")
            required = ", ".join(tools[name]["inputSchema"]["required"])
            print(f"{name} requires: {required}")
    ```

=== "TypeScript"

    ```typescript
    interface Tool {
      name: string;
      inputSchema: { required: string[] };
    }
    
    // Lists the tools, checks that the two that the program calls are present,
    // and prints the arguments that each one requires.
    async function listTools(s: Settings): Promise<void> {
      const result = await rpc<{ tools: Tool[] }>(s, "tools/list", {});
      // The server lists its tools in no fixed order, so look the two tools up
      // by name.
      for (const name of ["query_database", "execute_explain"]) {
        const tool = result.tools.find((t) => t.name === name);
        if (!tool) throw new Error(`The server does not offer ${name}`);
        console.log(`${name} requires: ${tool.inputSchema.required.join(", ")}`);
      }
    }
    ```

=== "Java"

    ```java
    /**
     * Lists the tools, checks that the two that the program calls are
     * present, and prints the arguments that each one requires.
     */
    static void listTools(Settings cfg)
            throws IOException, InterruptedException {
        // The server lists its tools in no fixed order, so look the two
        // tools up by name.
        Map<String, JsonNode> tools = new HashMap<>();
        for (JsonNode tool : rpc(cfg, "tools/list", Map.of()).get("tools")) {
            tools.put(tool.get("name").asString(), tool);
        }
        for (String name : List.of("query_database", "execute_explain")) {
            JsonNode tool = tools.get(name);
            if (tool == null) {
                throw new IOException("The server does not offer " + name);
            }
            List<String> required = JSON.convertValue(
                    tool.get("inputSchema").get("required"),
                    JSON.getTypeFactory().constructCollectionType(
                            List.class, String.class));
            System.out.println(name + " requires: "
                    + String.join(", ", required));
        }
    }
    ```

=== "C#"

    ```csharp
    // Lists the tools, checks that the two that the program calls are present,
    // and prints the arguments that each one requires.
    async Task ListTools(string baseUrl, string token)
    {
        var result = await Rpc(baseUrl, token, "tools/list", new { });
        // The server lists its tools in no fixed order, so look the two tools
        // up by name.
        var tools = result["tools"]!.AsArray()
            .ToDictionary(t => t!["name"]!.GetValue<string>(), t => t!);
        foreach (var name in new[] { "query_database", "execute_explain" })
        {
            if (!tools.TryGetValue(name, out var tool))
            {
                throw new InvalidOperationException(
                    $"The server does not offer {name}");
            }
            var required = tool["inputSchema"]!["required"]!.AsArray()
                .Select(r => r!.GetValue<string>());
            Console.WriteLine($"{name} requires: {string.Join(", ", required)}");
        }
    }
    ```

=== "Go"

    ```go
    // listTools lists the tools, checks that the two that the program calls are
    // present, and prints the arguments that each one requires.
    func listTools(s settings) error {
    	var result struct {
    		Tools []struct {
    			Name        string `json:"name"`
    			InputSchema struct {
    				Required []string `json:"required"`
    			} `json:"inputSchema"`
    		} `json:"tools"`
    	}
    	if err := rpc(s, "tools/list", map[string]any{}, &result); err != nil {
    		return err
    	}
    	// The server lists its tools in no fixed order, so look the two tools up
    	// by name.
    	for _, name := range []string{"query_database", "execute_explain"} {
    		found := false
    		for _, tool := range result.Tools {
    			if tool.Name == name {
    				fmt.Printf("%s requires: %s\n", name, strings.Join(tool.InputSchema.Required, ", "))
    				found = true
    			}
    		}
    		if !found {
    			return fmt.Errorf("the server does not offer %s", name)
    		}
    	}
    	return nil
    }
    
    ```

=== "Rust"

    ```rust
    /// Lists the tools, checks that the two that the program calls are
    /// present, and prints the arguments that each one requires.
    fn list_tools(cfg: &Settings) -> Result<()> {
        let result = rpc(cfg, "tools/list", json!({}))?;
        let tools = result["tools"].as_array().ok_or("the reply had no tools")?;
        // The server lists its tools in no fixed order, so look the two tools
        // up by name.
        for name in ["query_database", "execute_explain"] {
            let tool = tools
                .iter()
                .find(|t| t["name"] == name)
                .ok_or(format!("the server does not offer {name}"))?;
            let required: Vec<&str> = tool["inputSchema"]["required"]
                .as_array()
                .ok_or("the tool lists no required arguments")?
                .iter()
                .filter_map(Value::as_str)
                .collect();
            println!("{name} requires: {}", required.join(", "));
        }
        Ok(())
    }
    ```

=== "Ruby"

    ```ruby
    # Lists the tools, checks that the two that the program calls are present,
    # and prints the arguments that each one requires.
    def list_tools(cfg)
      tools = rpc(cfg, "tools/list", {}).fetch("tools").to_h { |t| [t["name"], t] }
      # The server lists its tools in no fixed order, so look the two tools up
      # by name.
      %w[query_database execute_explain].each do |name|
        raise "The server does not offer #{name}" unless tools.key?(name)
    
        required = tools[name].fetch("inputSchema").fetch("required").join(", ")
        puts "#{name} requires: #{required}"
      end
    end
    ```

=== "curl"

    ```bash
    # Lists the tools, checks that the two that the script calls are present, and
    # prints the arguments that each one requires.
    list_tools() {
        local result
        result=$(rpc tools/list '{}') || return 1
        # The server lists its tools in no fixed order, so the filter looks up the
        # two tools by name, in the order that it names them.
        jq -r '.tools as $tools | ("query_database", "execute_explain") as $name |
               $tools[] | select(.name == $name) |
               "\(.name) requires: \(.inputSchema.required | join(", "))"' \
            <<<"$result"
        if [[ "$(jq '[.tools[].name | select(. == "query_database" or
                      . == "execute_explain")] | length' <<<"$result")" -ne 2 ]]; then
            echo "The server does not offer both tools" >&2
            return 1
        fi
    }
    ```

## Calling a Tool

The `tools/call` method runs a tool, and its `params` hold the `name` of the
tool and its `arguments`. The reply holds a `content` list, and the text of the
tool's output is in the first item. A tool that fails returns an ordinary
result with `isError` set to `true`, so the helper function checks that flag
and raises an error with the text of the reply. The following tabs show the
helper function from each program:

=== "Python"

    ```python
    def call_tool(cfg: dict, name: str, arguments: dict) -> str:
        """Calls a tool and returns the text of its reply.
    
        A tool that fails returns a normal result with isError set, so the
        function checks that flag too.
        """
        result = rpc(cfg, "tools/call", {"name": name, "arguments": arguments})
        text = result["content"][0]["text"]
        if result.get("isError"):
            raise RuntimeError(f"{name} failed: {text}")
        return text
    ```

=== "TypeScript"

    ```typescript
    // Calls a tool and returns the text of its reply. A tool that fails returns a
    // normal result with isError set, so the function checks that flag too.
    async function callTool(
      s: Settings,
      name: string,
      args: Record<string, unknown>,
    ): Promise<string> {
      const result = await rpc<{
        content: { text: string }[];
        isError?: boolean;
      }>(s, "tools/call", { name, arguments: args });
      const text = result.content[0].text;
      if (result.isError) throw new Error(`${name} failed: ${text}`);
      return text;
    }
    ```

=== "Java"

    ```java
    /**
     * Calls a tool and returns the text of its reply. A tool that fails
     * returns a normal result with isError set, so the method checks that
     * flag too.
     */
    static String callTool(Settings cfg, String name,
            Map<String, Object> arguments)
            throws IOException, InterruptedException {
        JsonNode result = rpc(cfg, "tools/call",
                Map.of("name", name, "arguments", arguments));
        String text = result.get("content").get(0).get("text").asString();
        if (result.path("isError").asBoolean(false)) {
            throw new IOException(name + " failed: " + text);
        }
        return text;
    }
    ```

=== "C#"

    ```csharp
    // Calls a tool and returns the text of its reply. A tool that fails
    // returns a normal result with isError set, so the function checks that
    // flag too.
    async Task<string> CallTool(string baseUrl, string token, string name,
        object arguments)
    {
        var result = await Rpc(baseUrl, token, "tools/call",
            new { name, arguments });
        var text = result["content"]![0]!["text"]!.GetValue<string>();
        if (result["isError"]?.GetValue<bool>() == true)
        {
            throw new InvalidOperationException($"{name} failed: {text}");
        }
        return text;
    }
    ```

=== "Go"

    ```go
    // callTool calls a tool and returns the text of its reply. A tool that fails
    // returns a normal result with isError set, so the function checks that flag
    // too.
    func callTool(s settings, name string, arguments map[string]any) (string, error) {
    	var result struct {
    		Content []struct {
    			Text string `json:"text"`
    		} `json:"content"`
    		IsError bool `json:"isError"`
    	}
    	err := rpc(s, "tools/call", map[string]any{"name": name, "arguments": arguments}, &result)
    	if err != nil {
    		return "", err
    	}
    	if len(result.Content) == 0 {
    		return "", fmt.Errorf("%s returned no content", name)
    	}
    	text := result.Content[0].Text
    	if result.IsError {
    		return "", fmt.Errorf("%s failed: %s", name, text)
    	}
    	return text, nil
    }
    
    ```

=== "Rust"

    ```rust
    /// Calls a tool and returns the text of its reply. A tool that fails
    /// returns a normal result with isError set, so the function checks that
    /// flag too.
    fn call_tool(cfg: &Settings, name: &str, arguments: Value) -> Result<String> {
        let result = rpc(
            cfg,
            "tools/call",
            json!({ "name": name, "arguments": arguments }),
        )?;
        let text = result["content"][0]["text"]
            .as_str()
            .ok_or("the reply had no text")?;
        if result["isError"].as_bool().unwrap_or(false) {
            return Err(format!("{name} failed: {text}").into());
        }
        Ok(text.to_string())
    }
    ```

=== "Ruby"

    ```ruby
    # Calls a tool and returns the text of its reply. A tool that fails returns
    # a normal result with isError set, so the method checks that flag too.
    def call_tool(cfg, name, arguments)
      result = rpc(cfg, "tools/call", { name: name, arguments: arguments })
      text = result.fetch("content").fetch(0).fetch("text")
      raise "#{name} failed: #{text}" if result["isError"]
    
      text
    end
    ```

=== "curl"

    ```bash
    # Calls a tool and prints the text of its reply: call_tool NAME ARGUMENTS_JSON.
    # A tool that fails returns a normal result with isError set, so the function
    # checks that flag too.
    call_tool() {
        local name="$1" arguments="$2"
        local result
        result=$(rpc tools/call \
            "$(jq -nc --arg name "$name" --argjson arguments "$arguments" \
                '{name: $name, arguments: $arguments}')") || return 1
        if [[ "$(jq -r '.isError // false' <<<"$result")" == "true" ]]; then
            echo "$name failed: $(jq -r '.content[0].text' <<<"$result")" >&2
            return 1
        fi
        jq -r '.content[0].text' <<<"$result"
    }
    ```

## Running a Query

The `query_database` tool runs a read-only query against a monitored server,
and it takes the `connection_id` of the server and the `query` to run. The
reply is text rather than JSON: it names the database, repeats the query, and
then has a line that starts with `Results` followed by a row of tab-separated
column names and the rows of data. The program prints only the part after the
`Results` line, with the tabs replaced by commas. The parsing of the text
depends on the layout of the output in Workbench 1.0.0, so check it again after
an upgrade. The following tabs show how each program runs the query:

=== "Python"

    ```python
    def query_database(cfg: dict) -> None:
        """Runs a harmless read-only query with query_database and prints the
        column names and the rows.
    
        The reply is text that starts with the connection and the query, and
        then has a "Results" line followed by the rows in tab-separated form,
        so the function prints only what follows that line.
        """
        text = call_tool(cfg, "query_database", {
            "connection_id": cfg["connection_id"],
            "query": "SELECT 'Hello from the Workbench' AS greeting, "
                     "6 * 7 AS answer",
        })
        _, found, results = text.partition("\nResults")
        if not found:
            raise RuntimeError("The reply had no results")
        # Skip the rest of the Results line, then turn the tabs into commas.
        lines = results.split("\n")[1:]
        for number, line in enumerate(l for l in lines if l):
            label = "Columns" if number == 0 else "Row"
            values = ", ".join(line.split("\t"))
            print(f"{label}: {values}")
    ```

=== "TypeScript"

    ```typescript
    // Runs a harmless read-only query with query_database and prints the column
    // names and the rows. The reply is text that starts with the connection and
    // the query, and then has a "Results" line followed by the rows in
    // tab-separated form, so the function prints only what follows that line.
    async function queryDatabase(s: Settings): Promise<void> {
      const text = await callTool(s, "query_database", {
        connection_id: s.connectionId,
        query: "SELECT 'Hello from the Workbench' AS greeting, 6 * 7 AS answer",
      });
      const start = text.indexOf("\nResults");
      if (start < 0) throw new Error("The reply had no results");
      // Skip the rest of the Results line, then turn the tabs into commas.
      const lines = text
        .slice(start + 1)
        .split("\n")
        .slice(1)
        .filter((line) => line !== "");
      lines.forEach((line, number) => {
        const label = number === 0 ? "Columns" : "Row";
        console.log(`${label}: ${line.split("\t").join(", ")}`);
      });
    }
    ```

=== "Java"

    ```java
    /**
     * Runs a harmless read-only query with query_database and prints the
     * column names and the rows. The reply is text that starts with the
     * connection and the query, and then has a "Results" line followed by
     * the rows in tab-separated form, so the method prints only what
     * follows that line.
     */
    static void queryDatabase(Settings cfg)
            throws IOException, InterruptedException {
        String text = callTool(cfg, "query_database", Map.of(
                "connection_id", cfg.connectionId(),
                "query", "SELECT 'Hello from the Workbench' AS greeting, "
                        + "6 * 7 AS answer"));
        int start = text.indexOf("\nResults");
        if (start < 0) {
            throw new IOException("The reply had no results");
        }
        // Skip the rest of the Results line, then turn the tabs into
        // commas.
        String[] lines = text.substring(start + "\nResults".length())
                .split("\n", -1);
        int number = 0;
        for (String line : Arrays.asList(lines).subList(1, lines.length)) {
            if (line.isEmpty()) {
                continue;
            }
            String label = number == 0 ? "Columns" : "Row";
            System.out.println(label + ": "
                    + String.join(", ", line.split("\t", -1)));
            number++;
        }
    }
    ```

=== "C#"

    ```csharp
    // Runs a harmless read-only query with query_database and prints the
    // column names and the rows. The reply is text that starts with the
    // connection and the query, and then has a "Results" line followed by the
    // rows in tab-separated form, so the function prints only what follows
    // that line.
    async Task QueryDatabase(string baseUrl, string token, long connectionId)
    {
        var text = await CallTool(baseUrl, token, "query_database", new
        {
            connection_id = connectionId,
            query = "SELECT 'Hello from the Workbench' AS greeting, "
                + "6 * 7 AS answer",
        });
        var start = text.IndexOf("\nResults", StringComparison.Ordinal);
        if (start < 0)
        {
            throw new InvalidOperationException("The reply had no results");
        }
        // Skip the rest of the Results line, then turn the tabs into commas.
        var lines = text[(start + "\nResults".Length)..].Split('\n')
            .Skip(1)
            .Where(line => line.Length > 0);
        var number = 0;
        foreach (var line in lines)
        {
            var label = number == 0 ? "Columns" : "Row";
            Console.WriteLine($"{label}: {string.Join(", ", line.Split('\t'))}");
            number++;
        }
    }
    ```

=== "Go"

    ```go
    // queryDatabase runs a harmless read-only query with query_database and
    // prints the column names and the rows. The reply is text that starts with
    // the connection and the query, and then has a "Results" line followed by
    // the rows in tab-separated form, so the function prints only what follows
    // that line.
    func queryDatabase(s settings) error {
    	text, err := callTool(s, "query_database", map[string]any{
    		"connection_id": s.connectionID,
    		"query":         "SELECT 'Hello from the Workbench' AS greeting, 6 * 7 AS answer",
    	})
    	if err != nil {
    		return err
    	}
    	_, results, found := strings.Cut(text, "\nResults")
    	if !found {
    		return errors.New("the reply had no results")
    	}
    	// Skip the rest of the Results line, then turn the tabs into commas.
    	number := 0
    	for _, line := range strings.Split(results, "\n")[1:] {
    		if line == "" {
    			continue
    		}
    		label := "Row"
    		if number == 0 {
    			label = "Columns"
    		}
    		fmt.Printf("%s: %s\n", label, strings.Join(strings.Split(line, "\t"), ", "))
    		number++
    	}
    	return nil
    }
    
    ```

=== "Rust"

    ```rust
    /// Runs a harmless read-only query with query_database and prints the
    /// column names and the rows. The reply is text that starts with the
    /// connection and the query, and then has a "Results" line followed by the
    /// rows in tab-separated form, so the function prints only what follows
    /// that line.
    fn query_database(cfg: &Settings) -> Result<()> {
        let text = call_tool(
            cfg,
            "query_database",
            json!({
                "connection_id": cfg.connection_id,
                "query": "SELECT 'Hello from the Workbench' AS greeting, 6 * 7 AS answer",
            }),
        )?;
        let (_, results) = text
            .split_once("\nResults")
            .ok_or("the reply had no results")?;
        // Skip the rest of the Results line, then turn the tabs into commas.
        let lines = results.split('\n').skip(1).filter(|line| !line.is_empty());
        for (number, line) in lines.enumerate() {
            let label = if number == 0 { "Columns" } else { "Row" };
            let values: Vec<&str> = line.split('\t').collect();
            println!("{label}: {}", values.join(", "));
        }
        Ok(())
    }
    ```

=== "Ruby"

    ```ruby
    # Runs a harmless read-only query with query_database and prints the column
    # names and the rows. The reply is text that starts with the connection and
    # the query, and then has a "Results" line followed by the rows in
    # tab-separated form, so the method prints only what follows that line.
    def query_database(cfg)
      text = call_tool(cfg, "query_database", {
                         connection_id: cfg[:connection_id],
                         query: "SELECT 'Hello from the Workbench' AS greeting, " \
                                "6 * 7 AS answer"
                       })
      _, found, results = text.partition("\nResults")
      raise "The reply had no results" if found.empty?
    
      # Skip the rest of the Results line, then turn the tabs into commas.
      lines = results.split("\n", -1).drop(1).reject(&:empty?)
      lines.each_with_index do |line, number|
        label = number.zero? ? "Columns" : "Row"
        puts "#{label}: #{line.split("\t", -1).join(', ')}"
      end
    end
    ```

=== "curl"

    ```bash
    # Runs a harmless read-only query with query_database and prints the column
    # names and the rows. The reply is text that starts with the connection and
    # the query, and then has a "Results" line followed by the rows in
    # tab-separated form, so the function prints only what follows that line.
    query_database() {
        local text query rows
        query="SELECT 'Hello from the Workbench' AS greeting, 6 * 7 AS answer"
        text=$(call_tool query_database "$(jq -nc \
            --argjson connection_id "$WORKBENCH_CONNECTION_ID" \
            --arg query "$query" \
            '{connection_id: $connection_id, query: $query}')")
        # Drop everything up to the Results line, then turn the tabs into commas.
        rows=$(sed -n '/^Results (/,$p' <<<"$text" | tail -n +2 |
            awk -F'\t' 'BEGIN { OFS = ", " }
                        { $1 = $1; print (NR == 1 ? "Columns: " : "Row: ") $0 }')
        if [[ -z "$rows" ]]; then
            echo "The reply had no results" >&2
            return 1
        fi
        echo "$rows"
    }
    ```

## Planning a Query

The `execute_explain` tool returns the execution plan for a query. Setting
`analyze` to `false` plans the query without running it, whereas `true` runs
the query to measure it. Do not also set `buffers` to `false`, because the
Workbench 1.0.0 then sends `EXPLAIN ()` to PostgreSQL, which is a syntax error;
the example leaves `buffers` at its default. The plan follows a line of equals
signs in the reply, and the program prints the type of the first plan node. The
following tabs show how each program plans the query:

=== "Python"

    ```python
    def execute_explain(cfg: dict) -> None:
        """Plans a query with execute_explain, without running it, and prints
        the type of the first node of the plan. Setting analyze to true would
        run the query."""
        text = call_tool(cfg, "execute_explain", {
            "connection_id": cfg["connection_id"],
            "query": "SELECT 1 + 1",
            "analyze": False,
        })
        # The plan follows a line of equals signs.
        match = re.search(r"Execution Plan:\n=+\n(\S+)", text)
        if not match:
            raise RuntimeError("The reply had no execution plan")
        print(f"Plan starts with: {match.group(1)}")
    ```

=== "TypeScript"

    ```typescript
    // Plans a query with execute_explain, without running it, and prints the type
    // of the first node of the plan. Setting analyze to true would run the query.
    async function executeExplain(s: Settings): Promise<void> {
      const text = await callTool(s, "execute_explain", {
        connection_id: s.connectionId,
        query: "SELECT 1 + 1",
        analyze: false,
      });
      // The plan follows a line of equals signs.
      const match = /Execution Plan:\n=+\n(\S+)/.exec(text);
      if (!match) throw new Error("The reply had no execution plan");
      console.log(`Plan starts with: ${match[1]}`);
    }
    ```

=== "Java"

    ```java
    /** Matches the first node of the plan, after a line of equals signs. */
    static final Pattern PLAN = Pattern.compile("Execution Plan:\n=+\n(\\S+)");
    
    /**
     * Plans a query with execute_explain, without running it, and prints
     * the type of the first node of the plan. Setting analyze to true would
     * run the query.
     */
    static void executeExplain(Settings cfg)
            throws IOException, InterruptedException {
        String text = callTool(cfg, "execute_explain", Map.of(
                "connection_id", cfg.connectionId(),
                "query", "SELECT 1 + 1",
                "analyze", false));
        Matcher match = PLAN.matcher(text);
        if (!match.find()) {
            throw new IOException("The reply had no execution plan");
        }
        System.out.println("Plan starts with: " + match.group(1));
    }
    ```

=== "C#"

    ```csharp
    // Plans a query with execute_explain, without running it, and prints the
    // type of the first node of the plan. Setting analyze to true would run
    // the query.
    async Task ExecuteExplain(string baseUrl, string token, long connectionId)
    {
        var text = await CallTool(baseUrl, token, "execute_explain", new
        {
            connection_id = connectionId,
            query = "SELECT 1 + 1",
            analyze = false,
        });
        // The plan follows a line of equals signs.
        var match = Regex.Match(text, @"Execution Plan:\n=+\n(\S+)");
        if (!match.Success)
        {
            throw new InvalidOperationException(
                "The reply had no execution plan");
        }
        Console.WriteLine($"Plan starts with: {match.Groups[1].Value}");
    }
    ```

=== "Go"

    ```go
    // planStart finds the first word of the plan, which follows a line of equals
    // signs.
    var planStart = regexp.MustCompile(`Execution Plan:\n=+\n(\S+)`)
    
    // executeExplain plans a query with execute_explain, without running it, and
    // prints the type of the first node of the plan. Setting analyze to true
    // would run the query.
    func executeExplain(s settings) error {
    	text, err := callTool(s, "execute_explain", map[string]any{
    		"connection_id": s.connectionID,
    		"query":         "SELECT 1 + 1",
    		"analyze":       false,
    	})
    	if err != nil {
    		return err
    	}
    	match := planStart.FindStringSubmatch(text)
    	if match == nil {
    		return errors.New("the reply had no execution plan")
    	}
    	fmt.Printf("Plan starts with: %s\n", match[1])
    	return nil
    }
    
    ```

=== "Rust"

    ```rust
    /// Plans a query with execute_explain, without running it, and prints the
    /// type of the first node of the plan. Setting analyze to true would run
    /// the query.
    fn execute_explain(cfg: &Settings) -> Result<()> {
        let text = call_tool(
            cfg,
            "execute_explain",
            json!({
                "connection_id": cfg.connection_id,
                "query": "SELECT 1 + 1",
                "analyze": false,
            }),
        )?;
        // The plan follows a line of equals signs. The standard library has no
        // regular expressions, so find the line after it by hand.
        let mut lines = text
            .split_once("Execution Plan:\n")
            .ok_or("the reply had no execution plan")?
            .1
            .split('\n');
        let rule = lines.next().unwrap_or_default();
        if rule.is_empty() || !rule.chars().all(|c| c == '=') {
            return Err("the reply had no execution plan".into());
        }
        let node = lines
            .next()
            .and_then(|line| line.split(char::is_whitespace).next())
            .filter(|node| !node.is_empty())
            .ok_or("the reply had no execution plan")?;
        println!("Plan starts with: {node}");
        Ok(())
    }
    ```

=== "Ruby"

    ```ruby
    # Plans a query with execute_explain, without running it, and prints the
    # type of the first node of the plan. Setting analyze to true would run the
    # query.
    def execute_explain(cfg)
      text = call_tool(cfg, "execute_explain", {
                         connection_id: cfg[:connection_id],
                         query: "SELECT 1 + 1",
                         analyze: false
                       })
      # The plan follows a line of equals signs.
      match = /Execution Plan:\n=+\n(\S+)/.match(text)
      raise "The reply had no execution plan" unless match
    
      puts "Plan starts with: #{match[1]}"
    end
    ```

=== "curl"

    ```bash
    # Plans a query with execute_explain, without running it, and prints the type
    # of the first node of the plan. Setting analyze to true would run the query.
    execute_explain() {
        local text
        text=$(call_tool execute_explain "$(jq -nc \
            --argjson connection_id "$WORKBENCH_CONNECTION_ID" \
            '{connection_id: $connection_id, query: "SELECT 1 + 1",
              analyze: false}')")
        # The plan follows a line of equals signs.
        local node
        node=$(sed -n '/^=\{10,\}$/{n;p;q;}' <<<"$text" | awk '{ print $1 }')
        if [[ -z "$node" ]]; then
            echo "The reply had no execution plan" >&2
            return 1
        fi
        echo "Plan starts with: $node"
    }
    ```

## Putting It Together

The main part of each program reads the settings and calls the four steps in
order. It reports a failure on `stderr` and exits with a non-zero status. The
following tabs show the main part of each program:

=== "Python"

    ```python
    def main() -> int:
        try:
            cfg = settings()
            initialize(cfg)
            list_tools(cfg)
            query_database(cfg)
            execute_explain(cfg)
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
        const s = settings();
        await initialize(s);
        await listTools(s);
        await queryDatabase(s);
        await executeExplain(s);
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
            initialize(cfg);
            listTools(cfg);
            queryDatabase(cfg);
            executeExplain(cfg);
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
        await Initialize(baseUrl, token);
        await ListTools(baseUrl, token);
        await QueryDatabase(baseUrl, token, connectionId);
        await ExecuteExplain(baseUrl, token, connectionId);
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
    func run() error {
    	s, err := loadSettings()
    	if err != nil {
    		return err
    	}
    	for _, step := range []func(settings) error{
    		initialize, listTools, queryDatabase, executeExplain,
    	} {
    		if err := step(s); err != nil {
    			return err
    		}
    	}
    	return nil
    }
    
    func main() {
    	if err := run(); err != nil {
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
        initialize(&cfg)?;
        list_tools(&cfg)?;
        query_database(&cfg)?;
        execute_explain(&cfg)?;
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
      initialize_session(cfg)
      list_tools(cfg)
      query_database(cfg)
      execute_explain(cfg)
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
        initialize
        list_tools
        query_database
        execute_explain
    }
    
    main
    ```

## Running the Example

The complete project for each language is available in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/ai_dba_workbench/mcp_tools).
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
    Calling AI DBA Workbench MCP tools, using httpx.
    
    Copyright (c) 2026, pgEdge, Inc.
    This code is released under the PostgreSQL License.
    """
    
    import os
    import re
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
        if not connection_id.isdigit():
            raise RuntimeError("WORKBENCH_CONNECTION_ID must be a number")
        return {
            "base_url": (
                os.environ.get("WORKBENCH_URL") or "http://localhost:8080"
            ).rstrip("/"),
            "token": token,
            "connection_id": int(connection_id),
        }
    
    
    def rpc(cfg: dict, method: str, params: dict) -> dict:
        """Sends a JSON-RPC request to the MCP endpoint and returns the result.
    
        The server answers a JSON-RPC error with HTTP status 200, so the
        function checks the reply for an error member as well as for an HTTP
        failure.
        """
        response = httpx.post(
            f"{cfg['base_url']}/mcp/v1", timeout=30,
            headers={"Authorization": f"Bearer {cfg['token']}"},
            json={"jsonrpc": "2.0", "id": 1, "method": method, "params": params},
        )
        if response.is_error:
            raise RuntimeError(
                f"{method} failed with status {response.status_code}: "
                f"{response.text.strip()}"
            )
        reply = response.json()
        if "error" in reply:
            raise RuntimeError(f"{method} failed: {reply['error']['message']}")
        return reply["result"]
    
    
    def initialize(cfg: dict) -> None:
        """Introduces the client to the server and prints the server's name and
        version. The Workbench keeps no session, so a client can skip this
        step."""
        result = rpc(cfg, "initialize", {
            "protocolVersion": "2024-11-05",
            "capabilities": {},
            "clientInfo": {"name": "cookbook", "version": "1.0.0"},
        })
        info = result["serverInfo"]
        print(f"Server: {info['name']} {info['version']}")
    
    
    def list_tools(cfg: dict) -> None:
        """Lists the tools, checks that the two that the program calls are
        present, and prints the arguments that each one requires."""
        tools = {t["name"]: t for t in rpc(cfg, "tools/list", {})["tools"]}
        # The server lists its tools in no fixed order, so look the two tools
        # up by name.
        for name in ("query_database", "execute_explain"):
            if name not in tools:
                raise RuntimeError(f"The server does not offer {name}")
            required = ", ".join(tools[name]["inputSchema"]["required"])
            print(f"{name} requires: {required}")
    
    
    def call_tool(cfg: dict, name: str, arguments: dict) -> str:
        """Calls a tool and returns the text of its reply.
    
        A tool that fails returns a normal result with isError set, so the
        function checks that flag too.
        """
        result = rpc(cfg, "tools/call", {"name": name, "arguments": arguments})
        text = result["content"][0]["text"]
        if result.get("isError"):
            raise RuntimeError(f"{name} failed: {text}")
        return text
    
    
    def query_database(cfg: dict) -> None:
        """Runs a harmless read-only query with query_database and prints the
        column names and the rows.
    
        The reply is text that starts with the connection and the query, and
        then has a "Results" line followed by the rows in tab-separated form,
        so the function prints only what follows that line.
        """
        text = call_tool(cfg, "query_database", {
            "connection_id": cfg["connection_id"],
            "query": "SELECT 'Hello from the Workbench' AS greeting, "
                     "6 * 7 AS answer",
        })
        _, found, results = text.partition("\nResults")
        if not found:
            raise RuntimeError("The reply had no results")
        # Skip the rest of the Results line, then turn the tabs into commas.
        lines = results.split("\n")[1:]
        for number, line in enumerate(l for l in lines if l):
            label = "Columns" if number == 0 else "Row"
            values = ", ".join(line.split("\t"))
            print(f"{label}: {values}")
    
    
    def execute_explain(cfg: dict) -> None:
        """Plans a query with execute_explain, without running it, and prints
        the type of the first node of the plan. Setting analyze to true would
        run the query."""
        text = call_tool(cfg, "execute_explain", {
            "connection_id": cfg["connection_id"],
            "query": "SELECT 1 + 1",
            "analyze": False,
        })
        # The plan follows a line of equals signs.
        match = re.search(r"Execution Plan:\n=+\n(\S+)", text)
        if not match:
            raise RuntimeError("The reply had no execution plan")
        print(f"Plan starts with: {match.group(1)}")
    
    
    def main() -> int:
        try:
            cfg = settings()
            initialize(cfg)
            list_tools(cfg)
            query_database(cfg)
            execute_explain(cfg)
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
     * Calling AI DBA Workbench MCP tools, using the built-in fetch.
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
    
    // Sends a JSON-RPC request to the MCP endpoint and returns the result. The
    // server answers a JSON-RPC error with HTTP status 200, so the function
    // checks the reply for an error member as well as for an HTTP failure.
    async function rpc<T>(
      s: Settings,
      method: string,
      params: unknown,
    ): Promise<T> {
      const response = await fetch(`${s.baseUrl}/mcp/v1`, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${s.token}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ jsonrpc: "2.0", id: 1, method, params }),
        signal: AbortSignal.timeout(30_000),
      });
      if (!response.ok) {
        const text = (await response.text()).trim();
        throw new Error(`${method} failed with status ${response.status}: ${text}`);
      }
      const reply = (await response.json()) as {
        result?: T;
        error?: { message: string };
      };
      if (reply.error) throw new Error(`${method} failed: ${reply.error.message}`);
      return reply.result as T;
    }
    
    // Introduces the client to the server and prints the server's name and
    // version. The Workbench keeps no session, so a client can skip this step.
    async function initialize(s: Settings): Promise<void> {
      const result = await rpc<{ serverInfo: { name: string; version: string } }>(
        s,
        "initialize",
        {
          protocolVersion: "2024-11-05",
          capabilities: {},
          clientInfo: { name: "cookbook", version: "1.0.0" },
        },
      );
      console.log(`Server: ${result.serverInfo.name} ${result.serverInfo.version}`);
    }
    
    interface Tool {
      name: string;
      inputSchema: { required: string[] };
    }
    
    // Lists the tools, checks that the two that the program calls are present,
    // and prints the arguments that each one requires.
    async function listTools(s: Settings): Promise<void> {
      const result = await rpc<{ tools: Tool[] }>(s, "tools/list", {});
      // The server lists its tools in no fixed order, so look the two tools up
      // by name.
      for (const name of ["query_database", "execute_explain"]) {
        const tool = result.tools.find((t) => t.name === name);
        if (!tool) throw new Error(`The server does not offer ${name}`);
        console.log(`${name} requires: ${tool.inputSchema.required.join(", ")}`);
      }
    }
    
    // Calls a tool and returns the text of its reply. A tool that fails returns a
    // normal result with isError set, so the function checks that flag too.
    async function callTool(
      s: Settings,
      name: string,
      args: Record<string, unknown>,
    ): Promise<string> {
      const result = await rpc<{
        content: { text: string }[];
        isError?: boolean;
      }>(s, "tools/call", { name, arguments: args });
      const text = result.content[0].text;
      if (result.isError) throw new Error(`${name} failed: ${text}`);
      return text;
    }
    
    // Runs a harmless read-only query with query_database and prints the column
    // names and the rows. The reply is text that starts with the connection and
    // the query, and then has a "Results" line followed by the rows in
    // tab-separated form, so the function prints only what follows that line.
    async function queryDatabase(s: Settings): Promise<void> {
      const text = await callTool(s, "query_database", {
        connection_id: s.connectionId,
        query: "SELECT 'Hello from the Workbench' AS greeting, 6 * 7 AS answer",
      });
      const start = text.indexOf("\nResults");
      if (start < 0) throw new Error("The reply had no results");
      // Skip the rest of the Results line, then turn the tabs into commas.
      const lines = text
        .slice(start + 1)
        .split("\n")
        .slice(1)
        .filter((line) => line !== "");
      lines.forEach((line, number) => {
        const label = number === 0 ? "Columns" : "Row";
        console.log(`${label}: ${line.split("\t").join(", ")}`);
      });
    }
    
    // Plans a query with execute_explain, without running it, and prints the type
    // of the first node of the plan. Setting analyze to true would run the query.
    async function executeExplain(s: Settings): Promise<void> {
      const text = await callTool(s, "execute_explain", {
        connection_id: s.connectionId,
        query: "SELECT 1 + 1",
        analyze: false,
      });
      // The plan follows a line of equals signs.
      const match = /Execution Plan:\n=+\n(\S+)/.exec(text);
      if (!match) throw new Error("The reply had no execution plan");
      console.log(`Plan starts with: ${match[1]}`);
    }
    
    async function main(): Promise<number> {
      try {
        const s = settings();
        await initialize(s);
        await listTools(s);
        await queryDatabase(s);
        await executeExplain(s);
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
     * Calling AI DBA Workbench MCP tools, using java.net.http and Jackson.
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
    import java.util.Arrays;
    import java.util.HashMap;
    import java.util.List;
    import java.util.Map;
    import java.util.Objects;
    import java.util.concurrent.CompletableFuture;
    import java.util.concurrent.ExecutionException;
    import java.util.concurrent.TimeUnit;
    import java.util.concurrent.TimeoutException;
    import java.util.regex.Matcher;
    import java.util.regex.Pattern;
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
         * Sends a JSON-RPC request to the MCP endpoint and returns the result.
         * The server answers a JSON-RPC error with HTTP status 200, so the
         * method checks the reply for an error member as well as for an HTTP
         * failure.
         */
        static JsonNode rpc(Settings cfg, String method, Object params)
                throws IOException, InterruptedException {
            String body = JSON.writeValueAsString(Map.of(
                    "jsonrpc", "2.0", "id", 1, "method", method,
                    "params", params));
            HttpRequest request = HttpRequest
                    .newBuilder(URI.create(cfg.baseUrl() + "/mcp/v1"))
                    .timeout(Duration.ofSeconds(30))
                    .header("Authorization", "Bearer " + cfg.token())
                    .header("Content-Type", "application/json")
                    .POST(HttpRequest.BodyPublishers.ofString(body))
                    .build();
    
            HttpResponse<String> response = send(request);
            if (response.statusCode() >= 400) {
                throw new IOException(method + " failed with status "
                        + response.statusCode() + ": " + response.body().strip());
            }
            JsonNode reply = JSON.readTree(response.body());
            if (reply.has("error")) {
                throw new IOException(method + " failed: "
                        + reply.get("error").get("message").asString());
            }
            return reply.get("result");
        }
    
        /**
         * Introduces the client to the server and prints the server's name and
         * version. The Workbench keeps no session, so a client can skip this
         * step.
         */
        static void initialize(Settings cfg)
                throws IOException, InterruptedException {
            JsonNode result = rpc(cfg, "initialize", Map.of(
                    "protocolVersion", "2024-11-05",
                    "capabilities", Map.of(),
                    "clientInfo", Map.of("name", "cookbook", "version", "1.0.0")));
            JsonNode info = result.get("serverInfo");
            System.out.println("Server: " + info.get("name").asString() + " "
                    + info.get("version").asString());
        }
    
        /**
         * Lists the tools, checks that the two that the program calls are
         * present, and prints the arguments that each one requires.
         */
        static void listTools(Settings cfg)
                throws IOException, InterruptedException {
            // The server lists its tools in no fixed order, so look the two
            // tools up by name.
            Map<String, JsonNode> tools = new HashMap<>();
            for (JsonNode tool : rpc(cfg, "tools/list", Map.of()).get("tools")) {
                tools.put(tool.get("name").asString(), tool);
            }
            for (String name : List.of("query_database", "execute_explain")) {
                JsonNode tool = tools.get(name);
                if (tool == null) {
                    throw new IOException("The server does not offer " + name);
                }
                List<String> required = JSON.convertValue(
                        tool.get("inputSchema").get("required"),
                        JSON.getTypeFactory().constructCollectionType(
                                List.class, String.class));
                System.out.println(name + " requires: "
                        + String.join(", ", required));
            }
        }
    
        /**
         * Calls a tool and returns the text of its reply. A tool that fails
         * returns a normal result with isError set, so the method checks that
         * flag too.
         */
        static String callTool(Settings cfg, String name,
                Map<String, Object> arguments)
                throws IOException, InterruptedException {
            JsonNode result = rpc(cfg, "tools/call",
                    Map.of("name", name, "arguments", arguments));
            String text = result.get("content").get(0).get("text").asString();
            if (result.path("isError").asBoolean(false)) {
                throw new IOException(name + " failed: " + text);
            }
            return text;
        }
    
        /**
         * Runs a harmless read-only query with query_database and prints the
         * column names and the rows. The reply is text that starts with the
         * connection and the query, and then has a "Results" line followed by
         * the rows in tab-separated form, so the method prints only what
         * follows that line.
         */
        static void queryDatabase(Settings cfg)
                throws IOException, InterruptedException {
            String text = callTool(cfg, "query_database", Map.of(
                    "connection_id", cfg.connectionId(),
                    "query", "SELECT 'Hello from the Workbench' AS greeting, "
                            + "6 * 7 AS answer"));
            int start = text.indexOf("\nResults");
            if (start < 0) {
                throw new IOException("The reply had no results");
            }
            // Skip the rest of the Results line, then turn the tabs into
            // commas.
            String[] lines = text.substring(start + "\nResults".length())
                    .split("\n", -1);
            int number = 0;
            for (String line : Arrays.asList(lines).subList(1, lines.length)) {
                if (line.isEmpty()) {
                    continue;
                }
                String label = number == 0 ? "Columns" : "Row";
                System.out.println(label + ": "
                        + String.join(", ", line.split("\t", -1)));
                number++;
            }
        }
    
        /** Matches the first node of the plan, after a line of equals signs. */
        static final Pattern PLAN = Pattern.compile("Execution Plan:\n=+\n(\\S+)");
    
        /**
         * Plans a query with execute_explain, without running it, and prints
         * the type of the first node of the plan. Setting analyze to true would
         * run the query.
         */
        static void executeExplain(Settings cfg)
                throws IOException, InterruptedException {
            String text = callTool(cfg, "execute_explain", Map.of(
                    "connection_id", cfg.connectionId(),
                    "query", "SELECT 1 + 1",
                    "analyze", false));
            Matcher match = PLAN.matcher(text);
            if (!match.find()) {
                throw new IOException("The reply had no execution plan");
            }
            System.out.println("Plan starts with: " + match.group(1));
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
                initialize(cfg);
                listTools(cfg);
                queryDatabase(cfg);
                executeExplain(cfg);
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
     * Calling AI DBA Workbench MCP tools, using HttpClient and
     * System.Text.Json.
     *
     * Copyright (c) 2026, pgEdge, Inc.
     * This code is released under the PostgreSQL License.
     */
    
    using System.Net.Http.Headers;
    using System.Net.Http.Json;
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
    static (string BaseUrl, string Token, long ConnectionId) Settings()
    {
        var token = EnvValue("WORKBENCH_TOKEN");
        var connectionId = EnvValue("WORKBENCH_CONNECTION_ID");
        if (token is null || connectionId is null)
        {
            throw new InvalidOperationException(
                "WORKBENCH_TOKEN and WORKBENCH_CONNECTION_ID must be set");
        }
        if (!Regex.IsMatch(connectionId, "^[0-9]+$"))
        {
            throw new InvalidOperationException(
                "WORKBENCH_CONNECTION_ID must be a number");
        }
        var baseUrl = EnvValue("WORKBENCH_URL") ?? "http://localhost:8080";
        return (baseUrl.TrimEnd('/'), token, long.Parse(connectionId));
    }
    
    // One client serves every request, with a timeout for each.
    var http = new HttpClient { Timeout = TimeSpan.FromSeconds(30) };
    
    // Sends a JSON-RPC request to the MCP endpoint and returns the result. The
    // server answers a JSON-RPC error with HTTP status 200, so the function
    // checks the reply for an error member as well as for an HTTP failure.
    async Task<JsonNode> Rpc(string baseUrl, string token, string method,
        object parameters)
    {
        using var request = new HttpRequestMessage(HttpMethod.Post,
            $"{baseUrl}/mcp/v1")
        {
            Content = JsonContent.Create(new
            {
                jsonrpc = "2.0",
                id = 1,
                method,
                @params = parameters,
            }),
        };
        request.Headers.Authorization =
            new AuthenticationHeaderValue("Bearer", token);
    
        using var response = await http.SendAsync(request);
        var text = await response.Content.ReadAsStringAsync();
        if ((int)response.StatusCode >= 400)
        {
            throw new HttpRequestException(
                $"{method} failed with status {(int)response.StatusCode}: "
                + text.Trim());
        }
        var reply = JsonNode.Parse(text)
            ?? throw new InvalidOperationException($"{method} returned no JSON");
        if (reply["error"] is JsonNode error)
        {
            throw new InvalidOperationException(
                $"{method} failed: {error["message"]}");
        }
        return reply["result"]
            ?? throw new InvalidOperationException($"{method} had no result");
    }
    
    // Introduces the client to the server and prints the server's name and
    // version. The Workbench keeps no session, so a client can skip this step.
    async Task Initialize(string baseUrl, string token)
    {
        var result = await Rpc(baseUrl, token, "initialize", new
        {
            protocolVersion = "2024-11-05",
            capabilities = new { },
            clientInfo = new { name = "cookbook", version = "1.0.0" },
        });
        var info = result["serverInfo"]!;
        Console.WriteLine($"Server: {info["name"]} {info["version"]}");
    }
    
    // Lists the tools, checks that the two that the program calls are present,
    // and prints the arguments that each one requires.
    async Task ListTools(string baseUrl, string token)
    {
        var result = await Rpc(baseUrl, token, "tools/list", new { });
        // The server lists its tools in no fixed order, so look the two tools
        // up by name.
        var tools = result["tools"]!.AsArray()
            .ToDictionary(t => t!["name"]!.GetValue<string>(), t => t!);
        foreach (var name in new[] { "query_database", "execute_explain" })
        {
            if (!tools.TryGetValue(name, out var tool))
            {
                throw new InvalidOperationException(
                    $"The server does not offer {name}");
            }
            var required = tool["inputSchema"]!["required"]!.AsArray()
                .Select(r => r!.GetValue<string>());
            Console.WriteLine($"{name} requires: {string.Join(", ", required)}");
        }
    }
    
    // Calls a tool and returns the text of its reply. A tool that fails
    // returns a normal result with isError set, so the function checks that
    // flag too.
    async Task<string> CallTool(string baseUrl, string token, string name,
        object arguments)
    {
        var result = await Rpc(baseUrl, token, "tools/call",
            new { name, arguments });
        var text = result["content"]![0]!["text"]!.GetValue<string>();
        if (result["isError"]?.GetValue<bool>() == true)
        {
            throw new InvalidOperationException($"{name} failed: {text}");
        }
        return text;
    }
    
    // Runs a harmless read-only query with query_database and prints the
    // column names and the rows. The reply is text that starts with the
    // connection and the query, and then has a "Results" line followed by the
    // rows in tab-separated form, so the function prints only what follows
    // that line.
    async Task QueryDatabase(string baseUrl, string token, long connectionId)
    {
        var text = await CallTool(baseUrl, token, "query_database", new
        {
            connection_id = connectionId,
            query = "SELECT 'Hello from the Workbench' AS greeting, "
                + "6 * 7 AS answer",
        });
        var start = text.IndexOf("\nResults", StringComparison.Ordinal);
        if (start < 0)
        {
            throw new InvalidOperationException("The reply had no results");
        }
        // Skip the rest of the Results line, then turn the tabs into commas.
        var lines = text[(start + "\nResults".Length)..].Split('\n')
            .Skip(1)
            .Where(line => line.Length > 0);
        var number = 0;
        foreach (var line in lines)
        {
            var label = number == 0 ? "Columns" : "Row";
            Console.WriteLine($"{label}: {string.Join(", ", line.Split('\t'))}");
            number++;
        }
    }
    
    // Plans a query with execute_explain, without running it, and prints the
    // type of the first node of the plan. Setting analyze to true would run
    // the query.
    async Task ExecuteExplain(string baseUrl, string token, long connectionId)
    {
        var text = await CallTool(baseUrl, token, "execute_explain", new
        {
            connection_id = connectionId,
            query = "SELECT 1 + 1",
            analyze = false,
        });
        // The plan follows a line of equals signs.
        var match = Regex.Match(text, @"Execution Plan:\n=+\n(\S+)");
        if (!match.Success)
        {
            throw new InvalidOperationException(
                "The reply had no execution plan");
        }
        Console.WriteLine($"Plan starts with: {match.Groups[1].Value}");
    }
    
    try
    {
        var (baseUrl, token, connectionId) = Settings();
        await Initialize(baseUrl, token);
        await ListTools(baseUrl, token);
        await QueryDatabase(baseUrl, token, connectionId);
        await ExecuteExplain(baseUrl, token, connectionId);
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
     * Calling AI DBA Workbench MCP tools, using net/http.
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
    	"os"
    	"regexp"
    	"strconv"
    	"strings"
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
    
    // rpc sends a JSON-RPC request to the MCP endpoint and decodes the result
    // into out. The server answers a JSON-RPC error with HTTP status 200, so the
    // function checks the reply for an error member as well as for an HTTP
    // failure.
    func rpc(s settings, method string, params, out any) error {
    	body, err := json.Marshal(map[string]any{
    		"jsonrpc": "2.0", "id": 1, "method": method, "params": params,
    	})
    	if err != nil {
    		return err
    	}
    	req, err := http.NewRequest("POST", s.baseURL+"/mcp/v1", bytes.NewReader(body))
    	if err != nil {
    		return err
    	}
    	req.Header.Set("Authorization", "Bearer "+s.token)
    	req.Header.Set("Content-Type", "application/json")
    
    	resp, err := client.Do(req)
    	if err != nil {
    		return err
    	}
    	defer resp.Body.Close()
    	if resp.StatusCode >= 400 {
    		text, _ := io.ReadAll(resp.Body)
    		return fmt.Errorf("%s failed with status %d: %s",
    			method, resp.StatusCode, strings.TrimSpace(string(text)))
    	}
    
    	var reply struct {
    		Result json.RawMessage `json:"result"`
    		Error  *struct {
    			Message string `json:"message"`
    		} `json:"error"`
    	}
    	if err := json.NewDecoder(resp.Body).Decode(&reply); err != nil {
    		return err
    	}
    	if reply.Error != nil {
    		return fmt.Errorf("%s failed: %s", method, reply.Error.Message)
    	}
    	return json.Unmarshal(reply.Result, out)
    }
    
    
    // initialize introduces the client to the server and prints the server's
    // name and version. The Workbench keeps no session, so a client can skip
    // this step.
    func initialize(s settings) error {
    	var result struct {
    		ServerInfo struct {
    			Name    string `json:"name"`
    			Version string `json:"version"`
    		} `json:"serverInfo"`
    	}
    	err := rpc(s, "initialize", map[string]any{
    		"protocolVersion": "2024-11-05",
    		"capabilities":    map[string]any{},
    		"clientInfo":      map[string]any{"name": "cookbook", "version": "1.0.0"},
    	}, &result)
    	if err != nil {
    		return err
    	}
    	fmt.Printf("Server: %s %s\n", result.ServerInfo.Name, result.ServerInfo.Version)
    	return nil
    }
    
    
    // listTools lists the tools, checks that the two that the program calls are
    // present, and prints the arguments that each one requires.
    func listTools(s settings) error {
    	var result struct {
    		Tools []struct {
    			Name        string `json:"name"`
    			InputSchema struct {
    				Required []string `json:"required"`
    			} `json:"inputSchema"`
    		} `json:"tools"`
    	}
    	if err := rpc(s, "tools/list", map[string]any{}, &result); err != nil {
    		return err
    	}
    	// The server lists its tools in no fixed order, so look the two tools up
    	// by name.
    	for _, name := range []string{"query_database", "execute_explain"} {
    		found := false
    		for _, tool := range result.Tools {
    			if tool.Name == name {
    				fmt.Printf("%s requires: %s\n", name, strings.Join(tool.InputSchema.Required, ", "))
    				found = true
    			}
    		}
    		if !found {
    			return fmt.Errorf("the server does not offer %s", name)
    		}
    	}
    	return nil
    }
    
    
    // callTool calls a tool and returns the text of its reply. A tool that fails
    // returns a normal result with isError set, so the function checks that flag
    // too.
    func callTool(s settings, name string, arguments map[string]any) (string, error) {
    	var result struct {
    		Content []struct {
    			Text string `json:"text"`
    		} `json:"content"`
    		IsError bool `json:"isError"`
    	}
    	err := rpc(s, "tools/call", map[string]any{"name": name, "arguments": arguments}, &result)
    	if err != nil {
    		return "", err
    	}
    	if len(result.Content) == 0 {
    		return "", fmt.Errorf("%s returned no content", name)
    	}
    	text := result.Content[0].Text
    	if result.IsError {
    		return "", fmt.Errorf("%s failed: %s", name, text)
    	}
    	return text, nil
    }
    
    
    // queryDatabase runs a harmless read-only query with query_database and
    // prints the column names and the rows. The reply is text that starts with
    // the connection and the query, and then has a "Results" line followed by
    // the rows in tab-separated form, so the function prints only what follows
    // that line.
    func queryDatabase(s settings) error {
    	text, err := callTool(s, "query_database", map[string]any{
    		"connection_id": s.connectionID,
    		"query":         "SELECT 'Hello from the Workbench' AS greeting, 6 * 7 AS answer",
    	})
    	if err != nil {
    		return err
    	}
    	_, results, found := strings.Cut(text, "\nResults")
    	if !found {
    		return errors.New("the reply had no results")
    	}
    	// Skip the rest of the Results line, then turn the tabs into commas.
    	number := 0
    	for _, line := range strings.Split(results, "\n")[1:] {
    		if line == "" {
    			continue
    		}
    		label := "Row"
    		if number == 0 {
    			label = "Columns"
    		}
    		fmt.Printf("%s: %s\n", label, strings.Join(strings.Split(line, "\t"), ", "))
    		number++
    	}
    	return nil
    }
    
    
    // planStart finds the first word of the plan, which follows a line of equals
    // signs.
    var planStart = regexp.MustCompile(`Execution Plan:\n=+\n(\S+)`)
    
    // executeExplain plans a query with execute_explain, without running it, and
    // prints the type of the first node of the plan. Setting analyze to true
    // would run the query.
    func executeExplain(s settings) error {
    	text, err := callTool(s, "execute_explain", map[string]any{
    		"connection_id": s.connectionID,
    		"query":         "SELECT 1 + 1",
    		"analyze":       false,
    	})
    	if err != nil {
    		return err
    	}
    	match := planStart.FindStringSubmatch(text)
    	if match == nil {
    		return errors.New("the reply had no execution plan")
    	}
    	fmt.Printf("Plan starts with: %s\n", match[1])
    	return nil
    }
    
    
    func run() error {
    	s, err := loadSettings()
    	if err != nil {
    		return err
    	}
    	for _, step := range []func(settings) error{
    		initialize, listTools, queryDatabase, executeExplain,
    	} {
    		if err := step(s); err != nil {
    			return err
    		}
    	}
    	return nil
    }
    
    func main() {
    	if err := run(); err != nil {
    		fmt.Fprintln(os.Stderr, "Error:", err)
    		os.Exit(1)
    	}
    }
    
    
    ```

=== "Rust"

    ```rust
    // Ellie's Postgres Cookbook
    // Calling AI DBA Workbench MCP tools, using reqwest and serde_json.
    //
    // Copyright (c) 2026, pgEdge, Inc.
    // This code is released under the PostgreSQL License.
    
    use std::env;
    use std::error::Error;
    use std::process::ExitCode;
    use std::sync::LazyLock;
    use std::time::Duration;
    
    use reqwest::blocking::Client;
    use serde_json::{json, Value};
    
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
        let connection_id = connection_id
            .parse()
            .map_err(|_| "WORKBENCH_CONNECTION_ID must be a number")?;
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
    
    /// Sends a JSON-RPC request to the MCP endpoint and returns the result.
    /// The server answers a JSON-RPC error with HTTP status 200, so the
    /// function checks the reply for an error member as well as for an HTTP
    /// failure.
    fn rpc(cfg: &Settings, method: &str, params: Value) -> Result<Value> {
        let response = CLIENT
            .post(format!("{}/mcp/v1", cfg.base_url))
            .bearer_auth(&cfg.token)
            .json(&json!({ "jsonrpc": "2.0", "id": 1, "method": method, "params": params }))
            .send()?;
        let status = response.status().as_u16();
        if status >= 400 {
            let text = response.text()?;
            return Err(format!("{method} failed with status {status}: {}", text.trim()).into());
        }
        let mut reply: Value = response.json()?;
        if let Some(error) = reply.get("error") {
            let message = error["message"].as_str().unwrap_or_default();
            return Err(format!("{method} failed: {message}").into());
        }
        match reply.get_mut("result") {
            Some(result) => Ok(result.take()),
            None => Err(format!("{method} had no result").into()),
        }
    }
    
    /// Introduces the client to the server and prints the server's name and
    /// version. The Workbench keeps no session, so a client can skip this
    /// step.
    fn initialize(cfg: &Settings) -> Result<()> {
        let result = rpc(
            cfg,
            "initialize",
            json!({
                "protocolVersion": "2024-11-05",
                "capabilities": {},
                "clientInfo": { "name": "cookbook", "version": "1.0.0" },
            }),
        )?;
        let info = &result["serverInfo"];
        let name = info["name"]
            .as_str()
            .ok_or("the reply had no server name")?;
        let version = info["version"]
            .as_str()
            .ok_or("the reply had no server version")?;
        println!("Server: {name} {version}");
        Ok(())
    }
    
    /// Lists the tools, checks that the two that the program calls are
    /// present, and prints the arguments that each one requires.
    fn list_tools(cfg: &Settings) -> Result<()> {
        let result = rpc(cfg, "tools/list", json!({}))?;
        let tools = result["tools"].as_array().ok_or("the reply had no tools")?;
        // The server lists its tools in no fixed order, so look the two tools
        // up by name.
        for name in ["query_database", "execute_explain"] {
            let tool = tools
                .iter()
                .find(|t| t["name"] == name)
                .ok_or(format!("the server does not offer {name}"))?;
            let required: Vec<&str> = tool["inputSchema"]["required"]
                .as_array()
                .ok_or("the tool lists no required arguments")?
                .iter()
                .filter_map(Value::as_str)
                .collect();
            println!("{name} requires: {}", required.join(", "));
        }
        Ok(())
    }
    
    /// Calls a tool and returns the text of its reply. A tool that fails
    /// returns a normal result with isError set, so the function checks that
    /// flag too.
    fn call_tool(cfg: &Settings, name: &str, arguments: Value) -> Result<String> {
        let result = rpc(
            cfg,
            "tools/call",
            json!({ "name": name, "arguments": arguments }),
        )?;
        let text = result["content"][0]["text"]
            .as_str()
            .ok_or("the reply had no text")?;
        if result["isError"].as_bool().unwrap_or(false) {
            return Err(format!("{name} failed: {text}").into());
        }
        Ok(text.to_string())
    }
    
    /// Runs a harmless read-only query with query_database and prints the
    /// column names and the rows. The reply is text that starts with the
    /// connection and the query, and then has a "Results" line followed by the
    /// rows in tab-separated form, so the function prints only what follows
    /// that line.
    fn query_database(cfg: &Settings) -> Result<()> {
        let text = call_tool(
            cfg,
            "query_database",
            json!({
                "connection_id": cfg.connection_id,
                "query": "SELECT 'Hello from the Workbench' AS greeting, 6 * 7 AS answer",
            }),
        )?;
        let (_, results) = text
            .split_once("\nResults")
            .ok_or("the reply had no results")?;
        // Skip the rest of the Results line, then turn the tabs into commas.
        let lines = results.split('\n').skip(1).filter(|line| !line.is_empty());
        for (number, line) in lines.enumerate() {
            let label = if number == 0 { "Columns" } else { "Row" };
            let values: Vec<&str> = line.split('\t').collect();
            println!("{label}: {}", values.join(", "));
        }
        Ok(())
    }
    
    /// Plans a query with execute_explain, without running it, and prints the
    /// type of the first node of the plan. Setting analyze to true would run
    /// the query.
    fn execute_explain(cfg: &Settings) -> Result<()> {
        let text = call_tool(
            cfg,
            "execute_explain",
            json!({
                "connection_id": cfg.connection_id,
                "query": "SELECT 1 + 1",
                "analyze": false,
            }),
        )?;
        // The plan follows a line of equals signs. The standard library has no
        // regular expressions, so find the line after it by hand.
        let mut lines = text
            .split_once("Execution Plan:\n")
            .ok_or("the reply had no execution plan")?
            .1
            .split('\n');
        let rule = lines.next().unwrap_or_default();
        if rule.is_empty() || !rule.chars().all(|c| c == '=') {
            return Err("the reply had no execution plan".into());
        }
        let node = lines
            .next()
            .and_then(|line| line.split(char::is_whitespace).next())
            .filter(|node| !node.is_empty())
            .ok_or("the reply had no execution plan")?;
        println!("Plan starts with: {node}");
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
        initialize(&cfg)?;
        list_tools(&cfg)?;
        query_database(&cfg)?;
        execute_explain(&cfg)?;
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
    # Calling AI DBA Workbench MCP tools, using Net::HTTP.
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
      raise "WORKBENCH_CONNECTION_ID must be a number" unless connection_id.match?(/\A[0-9]+\z/)
    
      {
        base_url: env_or("WORKBENCH_URL", "http://localhost:8080").sub(%r{/+\z}, ""),
        token: token,
        connection_id: connection_id.to_i
      }
    end
    
    # Sends a JSON-RPC request to the MCP endpoint and returns the result. The
    # server answers a JSON-RPC error with HTTP status 200, so the method
    # checks the reply for an error member as well as for an HTTP failure.
    def rpc(cfg, method, params)
      uri = URI("#{cfg[:base_url]}/mcp/v1")
      headers = {
        "Authorization" => "Bearer #{cfg[:token]}",
        "Content-Type" => "application/json"
      }
      body = { jsonrpc: "2.0", id: 1, method: method, params: params }.to_json
    
      # Net::HTTP has no overall timeout, so limit both the connection and
      # each read.
      response = Net::HTTP.start(uri.host, uri.port,
                                 use_ssl: uri.scheme == "https",
                                 open_timeout: 30, read_timeout: 30) do |http|
        http.post(uri.request_uri, body, headers)
      end
      if response.code.to_i >= 400
        raise "#{method} failed with status #{response.code}: " \
              "#{response.body.to_s.strip}"
      end
      reply = JSON.parse(response.body)
      raise "#{method} failed: #{reply['error']['message']}" if reply.key?("error")
    
      reply.fetch("result")
    end
    
    # Introduces the client to the server and prints the server's name and
    # version. The Workbench keeps no session, so a client can skip this step.
    # Ruby uses the name initialize for constructors, so the method has another.
    def initialize_session(cfg)
      result = rpc(cfg, "initialize", {
                     protocolVersion: "2024-11-05",
                     capabilities: {},
                     clientInfo: { name: "cookbook", version: "1.0.0" }
                   })
      info = result.fetch("serverInfo")
      puts "Server: #{info.fetch('name')} #{info.fetch('version')}"
    end
    
    # Lists the tools, checks that the two that the program calls are present,
    # and prints the arguments that each one requires.
    def list_tools(cfg)
      tools = rpc(cfg, "tools/list", {}).fetch("tools").to_h { |t| [t["name"], t] }
      # The server lists its tools in no fixed order, so look the two tools up
      # by name.
      %w[query_database execute_explain].each do |name|
        raise "The server does not offer #{name}" unless tools.key?(name)
    
        required = tools[name].fetch("inputSchema").fetch("required").join(", ")
        puts "#{name} requires: #{required}"
      end
    end
    
    # Calls a tool and returns the text of its reply. A tool that fails returns
    # a normal result with isError set, so the method checks that flag too.
    def call_tool(cfg, name, arguments)
      result = rpc(cfg, "tools/call", { name: name, arguments: arguments })
      text = result.fetch("content").fetch(0).fetch("text")
      raise "#{name} failed: #{text}" if result["isError"]
    
      text
    end
    
    # Runs a harmless read-only query with query_database and prints the column
    # names and the rows. The reply is text that starts with the connection and
    # the query, and then has a "Results" line followed by the rows in
    # tab-separated form, so the method prints only what follows that line.
    def query_database(cfg)
      text = call_tool(cfg, "query_database", {
                         connection_id: cfg[:connection_id],
                         query: "SELECT 'Hello from the Workbench' AS greeting, " \
                                "6 * 7 AS answer"
                       })
      _, found, results = text.partition("\nResults")
      raise "The reply had no results" if found.empty?
    
      # Skip the rest of the Results line, then turn the tabs into commas.
      lines = results.split("\n", -1).drop(1).reject(&:empty?)
      lines.each_with_index do |line, number|
        label = number.zero? ? "Columns" : "Row"
        puts "#{label}: #{line.split("\t", -1).join(', ')}"
      end
    end
    
    # Plans a query with execute_explain, without running it, and prints the
    # type of the first node of the plan. Setting analyze to true would run the
    # query.
    def execute_explain(cfg)
      text = call_tool(cfg, "execute_explain", {
                         connection_id: cfg[:connection_id],
                         query: "SELECT 1 + 1",
                         analyze: false
                       })
      # The plan follows a line of equals signs.
      match = /Execution Plan:\n=+\n(\S+)/.match(text)
      raise "The reply had no execution plan" unless match
    
      puts "Plan starts with: #{match[1]}"
    end
    
    def main
      cfg = settings
      initialize_session(cfg)
      list_tools(cfg)
      query_database(cfg)
      execute_explain(cfg)
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
    # Calling AI DBA Workbench MCP tools with curl and jq.
    #
    # Copyright (c) 2026, pgEdge, Inc.
    # This code is released under the PostgreSQL License.
    
    # Stop at the first failing command, treat an unset variable as an error,
    # and fail a pipeline when any command in it fails.
    set -euo pipefail
    
    # The script needs curl to make the requests and jq to build the requests
    # and read the replies.
    for tool in curl jq; do
        command -v "$tool" >/dev/null || { echo "$tool is required" >&2; exit 1; }
    done
    
    # Read the settings from the environment. The :- and :? forms, unlike - and
    # ?, treat an empty variable as unset.
    WORKBENCH_URL="${WORKBENCH_URL:-http://localhost:8080}"
    WORKBENCH_URL="${WORKBENCH_URL%/}"
    : "${WORKBENCH_TOKEN:?WORKBENCH_TOKEN must be set}"
    : "${WORKBENCH_CONNECTION_ID:?WORKBENCH_CONNECTION_ID must be set}"
    
    # Sends a JSON-RPC request to the MCP endpoint and prints the result:
    # rpc METHOD PARAMS_JSON. The server answers a JSON-RPC error with HTTP
    # status 200, so the function checks the reply for an error member as well as
    # for an HTTP failure.
    # The token goes to curl in a header file that bash supplies through a pipe,
    # so that it never appears in the arguments of the curl process, which other
    # users can read in the process list.
    rpc() {
        local method="$1" params="$2"
        local response
        response=$(jq -n --arg method "$method" --argjson params "$params" \
            '{jsonrpc: "2.0", id: 1, method: $method, params: $params}' |
            curl --silent --show-error --fail-with-body \
                --connect-timeout 10 --max-time 30 \
                --header @<(printf 'Authorization: Bearer %s\n' "$WORKBENCH_TOKEN") \
                --header 'Content-Type: application/json' \
                --data @- "$WORKBENCH_URL/mcp/v1") || {
            echo "$method failed: $response" >&2
            return 1
        }
        if jq -e '.error' >/dev/null 2>&1 <<<"$response"; then
            echo "$method failed: $(jq -r '.error.message' <<<"$response")" >&2
            return 1
        fi
        jq -c '.result' <<<"$response"
    }
    
    # Introduces the client to the server and prints the server's name and
    # version. The Workbench keeps no session, so a client can skip this step.
    initialize() {
        local result
        result=$(rpc initialize '{
            "protocolVersion": "2024-11-05",
            "capabilities": {},
            "clientInfo": {"name": "cookbook", "version": "1.0.0"}
        }') || return 1
        jq -r '"Server: \(.serverInfo.name) \(.serverInfo.version)"' <<<"$result"
    }
    
    # Lists the tools, checks that the two that the script calls are present, and
    # prints the arguments that each one requires.
    list_tools() {
        local result
        result=$(rpc tools/list '{}') || return 1
        # The server lists its tools in no fixed order, so the filter looks up the
        # two tools by name, in the order that it names them.
        jq -r '.tools as $tools | ("query_database", "execute_explain") as $name |
               $tools[] | select(.name == $name) |
               "\(.name) requires: \(.inputSchema.required | join(", "))"' \
            <<<"$result"
        if [[ "$(jq '[.tools[].name | select(. == "query_database" or
                      . == "execute_explain")] | length' <<<"$result")" -ne 2 ]]; then
            echo "The server does not offer both tools" >&2
            return 1
        fi
    }
    
    # Calls a tool and prints the text of its reply: call_tool NAME ARGUMENTS_JSON.
    # A tool that fails returns a normal result with isError set, so the function
    # checks that flag too.
    call_tool() {
        local name="$1" arguments="$2"
        local result
        result=$(rpc tools/call \
            "$(jq -nc --arg name "$name" --argjson arguments "$arguments" \
                '{name: $name, arguments: $arguments}')") || return 1
        if [[ "$(jq -r '.isError // false' <<<"$result")" == "true" ]]; then
            echo "$name failed: $(jq -r '.content[0].text' <<<"$result")" >&2
            return 1
        fi
        jq -r '.content[0].text' <<<"$result"
    }
    
    # Runs a harmless read-only query with query_database and prints the column
    # names and the rows. The reply is text that starts with the connection and
    # the query, and then has a "Results" line followed by the rows in
    # tab-separated form, so the function prints only what follows that line.
    query_database() {
        local text query rows
        query="SELECT 'Hello from the Workbench' AS greeting, 6 * 7 AS answer"
        text=$(call_tool query_database "$(jq -nc \
            --argjson connection_id "$WORKBENCH_CONNECTION_ID" \
            --arg query "$query" \
            '{connection_id: $connection_id, query: $query}')")
        # Drop everything up to the Results line, then turn the tabs into commas.
        rows=$(sed -n '/^Results (/,$p' <<<"$text" | tail -n +2 |
            awk -F'\t' 'BEGIN { OFS = ", " }
                        { $1 = $1; print (NR == 1 ? "Columns: " : "Row: ") $0 }')
        if [[ -z "$rows" ]]; then
            echo "The reply had no results" >&2
            return 1
        fi
        echo "$rows"
    }
    
    # Plans a query with execute_explain, without running it, and prints the type
    # of the first node of the plan. Setting analyze to true would run the query.
    execute_explain() {
        local text
        text=$(call_tool execute_explain "$(jq -nc \
            --argjson connection_id "$WORKBENCH_CONNECTION_ID" \
            '{connection_id: $connection_id, query: "SELECT 1 + 1",
              analyze: false}')")
        # The plan follows a line of equals signs.
        local node
        node=$(sed -n '/^=\{10,\}$/{n;p;q;}' <<<"$text" | awk '{ print $1 }')
        if [[ -z "$node" ]]; then
            echo "The reply had no execution plan" >&2
            return 1
        fi
        echo "Plan starts with: $node"
    }
    
    main() {
        initialize
        list_tools
        query_database
        execute_explain
    }
    
    main
    
    ```

## Next Steps

The following resources provide more information about the topics in this
recipe:

- The [Authenticating with the AI DBA Workbench API](authenticate.md) recipe
  explains how to create the API token that these examples use.
- The [Registering a Server with the AI DBA Workbench API](register_server.md)
  recipe shows how to add the server that the tools query.
- The AI DBA Workbench
  [documentation](https://github.com/pgEdge/ai-dba-workbench/tree/v1.0.0/docs)
  describes the full set of tools.
