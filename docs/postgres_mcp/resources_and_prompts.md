# Reading Resources and Prompts

Besides tools, an MCP server can offer resources, which are documents that a
client reads by URI, and prompts, which are ready-made sets of messages that
guide a language model through a task with the server's tools. This recipe
lists both, reads the `pg://system_info` resource to find the PostgreSQL
version and whether the server allows writes, and fetches the
`explore-database` prompt. Each step shows the code in every supported
language; selecting a language tab switches every tab on the site to that
language.

These examples are for pgEdge Postgres MCP Server 1.1.0.

The program prints the following output when the server uses PostgreSQL 18:

```text
Resources: pg://system_info
PostgreSQL major version: 18
Writes allowed: false
Prompts: design-schema, diagnose-query-issue, explore-database, setup-semantic-search
explore-database: Systematic database exploration workflow
First message role: user
```

## Preparing the Ingredients

The examples need a running pgEdge Postgres MCP Server in HTTP mode with
authentication turned on, and an API token that it accepts. The
`scripts/start_postgres_mcp.sh` script in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook)
starts a test server in Docker. The script creates a `cookbook_mcp` schema in
the cookbook test PostgreSQL server (which `scripts/start_test_server.sh`
starts) holding a `products` table of made-up products, with an embedding of
each product's description made by Ollama with the `nomic-embed-text` model. It
then generates a token, starts the server, and prints the `MCP_URL` and
`MCP_TOKEN` values that the examples read from the environment.

The server speaks the Model Context Protocol (MCP), which is built on JSON-RPC
2.0. A client sends each request as a `POST` to `/mcp/v1` with the token in an
`Authorization: Bearer` header, and the server replies with a JSON object that
holds either a `result` or an `error`. The server replies with HTTP 200 to a
JSON-RPC error as well as to a success, so each program checks the reply for an
`error` member as well as the HTTP status. No program prints the token.

The following table lists the HTTP client that each example uses:

| Language   | HTTP client                                                                                  |
|------------|----------------------------------------------------------------------------------------------|
| Python     | [httpx](https://www.python-httpx.org/)                                                       |
| TypeScript | The `fetch` function that Node.js provides                                                   |
| Java       | The `java.net.http` package, with [Jackson](https://github.com/FasterXML/jackson) for JSON   |
| C#         | The `HttpClient` class and `System.Text.Json`, which .NET provides                           |
| Go         | The `net/http` package                                                                       |
| Rust       | [reqwest](https://docs.rs/reqwest/), with [serde_json](https://docs.rs/serde_json/) for JSON |
| Ruby       | `Net::HTTP` and `json` from the standard library                                             |
| curl       | [curl](https://curl.se/) and [jq](https://jqlang.org/)                                       |

The following tabs show the dependency declaration from each example project;
the TypeScript project needs only the compiler and the Node.js type
definitions, the Java project adds Jackson, the Rust project adds reqwest and
serde_json, and the C#, Go and Ruby projects need nothing beyond their standard
libraries:

=== "Python"

    ```text
    # httpx, an HTTP client with a requests-like API.
    httpx>=0.28,<1
    ```

=== "TypeScript"

    ```json
    {
      "name": "resources-and-prompts",
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
    ```

=== "Ruby"

    ```ruby
    source "https://rubygems.org"
    
    # The program uses only Net::HTTP and json from the standard library, so
    # there is no gem to add.
    ```

## Importing the Libraries

Each program begins by importing the HTTP client, along with any standard
library modules that it uses. The TypeScript program imports nothing, because
Node.js provides `fetch` as a global, and the curl script checks that `curl`
and `jq` are installed. The following tabs show the imports for each language:

=== "Python"

    ```python
    import json
    import os
    import sys
    
    import httpx
    ```

=== "TypeScript"

    ```typescript
    // Node.js provides fetch and AbortSignal as globals, so this program
    // imports nothing.
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
    import java.util.ArrayList;
    import java.util.List;
    import java.util.Map;
    import java.util.concurrent.CompletableFuture;
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
    using System.Net;
    using System.Text;
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
    use std::time::Duration;
    
    use reqwest::blocking::Client;
    use serde_json::{json, Value};
    ```

=== "Ruby"

    ```ruby
    require "json"
    require "net/http"
    require "uri"
    ```

=== "curl"

    ```bash
    # Stop at the first failed command or unset variable, and treat a failure
    # anywhere in a pipeline as a failure of the whole pipeline.
    set -euo pipefail
    
    # The script needs curl to make the requests and jq to build the requests
    # and read the replies.
    for tool in curl jq; do
        command -v "$tool" >/dev/null || { echo "$tool is required" >&2; exit 1; }
    done
    ```

## Configuring the Program

The examples read their settings from the following environment variables,
and treat an empty value as unset; each program allows 30 seconds for a
reply:

| Variable    | Default                 | Description                     |
|-------------|-------------------------|---------------------------------|
| `MCP_URL`   | `http://localhost:8080` | The base URL of the MCP Server. |
| `MCP_TOKEN` | None; it must be set    | An API token for the server.    |

The `rpc` helper sends a request and returns its result. Resources and prompts
need no `initialize` handshake first.

The following tabs show how each program reads its settings, and how it sends a
request to the server:

=== "Python"

    ```python
    # The or operator treats an empty variable as unset.
    BASE_URL = (os.environ.get("MCP_URL") or "http://localhost:8080").rstrip("/")
    TOKEN = os.environ.get("MCP_TOKEN") or ""
    
    TIMEOUT_SECONDS = 30
    
    
    class McpError(Exception):
        """Raised when the MCP Server rejects a request or replies oddly."""
    
    
    def rpc(client: httpx.Client, method: str, params: dict):
        """Sends a JSON-RPC request and returns its result.
    
        The server answers a JSON-RPC error with HTTP status 200, so the
        function checks the reply for an error member as well as the HTTP
        status.
        """
        response = client.post(
            "/mcp/v1",
            headers={"Authorization": f"Bearer {TOKEN}"},
            json={"jsonrpc": "2.0", "id": 1, "method": method, "params": params},
        )
        if response.status_code != 200:
            raise McpError(f"{method} failed with HTTP {response.status_code}: "
                           f"{response.text[:200]}")
        try:
            reply = response.json()
        except ValueError:
            reply = None
        if not isinstance(reply, dict) or not ("result" in reply or "error" in reply):
            raise McpError(f"{method} failed: unexpected response: "
                           f"{response.text[:200]}")
        if "error" in reply:
            raise McpError(f"{method} failed: {reply['error'].get('message')}")
        return reply["result"]
    ```

=== "TypeScript"

    ```typescript
    // The || operator, unlike ??, also treats an empty variable as unset.
    const baseUrl = (process.env.MCP_URL || "http://localhost:8080").replace(/\/+$/, "");
    const token = process.env.MCP_TOKEN || "";
    
    const timeoutMs = 30_000;
    
    // Sends a JSON-RPC request and returns its result. The server answers a
    // JSON-RPC error with HTTP status 200, so the function checks the reply
    // for an error member as well as the HTTP status.
    async function rpc(method: string, params: object): Promise<any> {
      const response = await fetch(`${baseUrl}/mcp/v1`, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${token}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ jsonrpc: "2.0", id: 1, method, params }),
        signal: AbortSignal.timeout(timeoutMs),
      });
      const text = await response.text();
      if (response.status !== 200) {
        throw new Error(`${method} failed with HTTP ${response.status}: ${text.slice(0, 200)}`);
      }
      let reply: any;
      try {
        reply = JSON.parse(text);
      } catch {
        reply = undefined;
      }
      if (typeof reply !== "object" || reply === null || !("result" in reply || "error" in reply)) {
        throw new Error(`${method} failed: unexpected response: ${text.slice(0, 200)}`);
      }
      if ("error" in reply) {
        throw new Error(`${method} failed: ${reply.error?.message}`);
      }
      return reply.result;
    }
    ```

=== "Java"

    ```java
    /** Returns the value of an environment variable, or a fallback. */
    static String envOr(String name, String fallback) {
        String value = System.getenv(name);
        return (value != null && !value.isEmpty()) ? value : fallback;
    }
    
    static final String BASE_URL =
            envOr("MCP_URL", "http://localhost:8080").replaceAll("/+$", "");
    static final String TOKEN = envOr("MCP_TOKEN", "");
    
    static final Duration TIMEOUT = Duration.ofSeconds(30);
    
    /** Thrown when the MCP Server rejects a request or replies oddly. */
    static class McpException extends Exception {
        McpException(String message) {
            super(message);
        }
    }
    
    // A client and a mapper are safe to share, so the program creates
    // only one of each.
    static final HttpClient CLIENT = HttpClient.newBuilder()
            .connectTimeout(TIMEOUT)
            .build();
    static final ObjectMapper MAPPER = JsonMapper.builder().build();
    
    /** Returns at most the first 200 characters of a reply. */
    static String shorten(String text) {
        return text.length() > 200 ? text.substring(0, 200) : text;
    }
    
    /**
     * Sends a request and returns the response with its whole body. The
     * request timeout stops applying once the headers arrive, so a server
     * that stalls part of the way through the body would hang send(); this
     * applies the timeout to the whole exchange instead.
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
    
    /** Parses a reply as a JSON object, or returns null if it is not one. */
    static JsonNode parseObject(String text) {
        try {
            JsonNode node = MAPPER.readTree(text);
            return node.isObject() ? node : null;
        } catch (JacksonException e) {
            return null;
        }
    }
    
    /**
     * Sends a JSON-RPC request and returns its result. The server answers a
     * JSON-RPC error with HTTP status 200, so the method checks the reply
     * for an error member as well as the HTTP status.
     */
    static JsonNode rpc(String method, Map<String, Object> params)
            throws IOException, InterruptedException, McpException {
        String message = MAPPER.writeValueAsString(Map.of(
                "jsonrpc", "2.0", "id", 1, "method", method, "params", params));
        HttpRequest request = HttpRequest.newBuilder(URI.create(BASE_URL + "/mcp/v1"))
                .timeout(TIMEOUT)
                .header("Authorization", "Bearer " + TOKEN)
                .header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString(message))
                .build();
        HttpResponse<String> response = send(request);
        if (response.statusCode() != 200) {
            throw new McpException(method + " failed with HTTP "
                    + response.statusCode() + ": " + shorten(response.body()));
        }
        JsonNode reply = parseObject(response.body());
        if (reply == null || !(reply.has("result") || reply.has("error"))) {
            throw new McpException(method + " failed: unexpected response: "
                    + shorten(response.body()));
        }
        if (reply.has("error")) {
            throw new McpException(method + " failed: "
                    + reply.path("error").path("message").asString());
        }
        return reply.get("result");
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
    
    static string BaseUrl() => EnvOr("MCP_URL", "http://localhost:8080").TrimEnd('/');
    static string Token() => EnvOr("MCP_TOKEN", "");
    
    const int TimeoutSeconds = 30;
    
    // Returns at most the first 200 characters of a reply.
    static string Shorten(string text) =>
        text.Length > 200 ? text[..200] : text;
    
    // Parses a reply as a JSON object, or returns null if it is not one.
    static JsonObject? ParseObject(string text)
    {
        try
        {
            return JsonNode.Parse(text) as JsonObject;
        }
        catch (JsonException)
        {
            return null;
        }
    }
    
    // Sends a JSON-RPC request and returns its result. The server answers a
    // JSON-RPC error with HTTP status 200, so the function checks the reply for
    // an error member as well as the HTTP status.
    static async Task<JsonNode> RpcAsync(HttpClient client, string method, JsonObject parameters)
    {
        var message = new JsonObject
        {
            ["jsonrpc"] = "2.0",
            ["id"] = 1,
            ["method"] = method,
            ["params"] = parameters,
        };
        using var request = new HttpRequestMessage(HttpMethod.Post, BaseUrl() + "/mcp/v1")
        {
            Content = new StringContent(
                message.ToJsonString(), Encoding.UTF8, "application/json"),
        };
        request.Headers.Add("Authorization", $"Bearer {Token()}");
        using var response = await client.SendAsync(request);
        var body = await response.Content.ReadAsStringAsync();
        if (response.StatusCode != HttpStatusCode.OK)
        {
            throw new McpException(
                $"{method} failed with HTTP {(int)response.StatusCode}: {Shorten(body)}");
        }
        var reply = ParseObject(body);
        if (reply is null || !(reply.ContainsKey("result") || reply.ContainsKey("error")))
        {
            throw new McpException($"{method} failed: unexpected response: {Shorten(body)}");
        }
        if (reply.ContainsKey("error"))
        {
            throw new McpException($"{method} failed: {reply["error"]?["message"]}");
        }
        return reply["result"] ?? throw new McpException($"{method} failed: no result");
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
    
    var (
    	baseURL = strings.TrimRight(envOr("MCP_URL", "http://localhost:8080"), "/")
    	token   = os.Getenv("MCP_TOKEN")
    )
    
    const timeout = 30 * time.Second
    
    // shorten returns at most the first 200 bytes of a reply.
    func shorten(body []byte) string {
    	if len(body) > 200 {
    		body = body[:200]
    	}
    	return string(body)
    }
    
    // rpc sends a JSON-RPC request and decodes its result into out. The
    // server answers a JSON-RPC error with HTTP status 200, so the function
    // checks the reply for an error member as well as the HTTP status.
    func rpc(client *http.Client, method string, params any, out any) error {
    	payload, err := json.Marshal(map[string]any{
    		"jsonrpc": "2.0", "id": 1, "method": method, "params": params,
    	})
    	if err != nil {
    		return err
    	}
    	request, err := http.NewRequest(http.MethodPost, baseURL+"/mcp/v1", bytes.NewReader(payload))
    	if err != nil {
    		return err
    	}
    	request.Header.Set("Authorization", "Bearer "+token)
    	request.Header.Set("Content-Type", "application/json")
    
    	response, err := client.Do(request)
    	if err != nil {
    		return err
    	}
    	defer response.Body.Close()
    	body, err := io.ReadAll(response.Body)
    	if err != nil {
    		return err
    	}
    	if response.StatusCode != http.StatusOK {
    		return fmt.Errorf("%s failed with HTTP %d: %s", method, response.StatusCode, shorten(body))
    	}
    	var reply struct {
    		Result json.RawMessage `json:"result"`
    		Error  *struct {
    			Message string `json:"message"`
    		} `json:"error"`
    	}
    	if err := json.Unmarshal(body, &reply); err != nil || (reply.Result == nil && reply.Error == nil) {
    		return fmt.Errorf("%s failed: unexpected response: %s", method, shorten(body))
    	}
    	if reply.Error != nil {
    		return fmt.Errorf("%s failed: %s", method, reply.Error.Message)
    	}
    	if err := json.Unmarshal(reply.Result, out); err != nil {
    		return fmt.Errorf("%s failed: unexpected result: %s", method, shorten(reply.Result))
    	}
    	return nil
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
        env_or("MCP_URL", "http://localhost:8080")
            .trim_end_matches('/')
            .to_string()
    }
    
    fn token() -> String {
        env_or("MCP_TOKEN", "")
    }
    
    const TIMEOUT: Duration = Duration::from_secs(30);
    
    /// The errors that the functions below return; a string converts into one
    /// with the ? operator or into().
    type BoxError = Box<dyn Error>;
    
    /// Returns at most the first 200 characters of a reply.
    fn shorten(text: &str) -> String {
        text.chars().take(200).collect()
    }
    
    /// Sends a JSON-RPC request and returns its result. The server answers a
    /// JSON-RPC error with HTTP status 200, so the function checks the reply
    /// for an error member as well as the HTTP status.
    fn rpc(client: &Client, method: &str, params: Value) -> Result<Value, BoxError> {
        let message = json!({"jsonrpc": "2.0", "id": 1, "method": method, "params": params});
        let response = client
            .post(format!("{}/mcp/v1", base_url()))
            .bearer_auth(token())
            .json(&message)
            .send()?;
        let status = response.status().as_u16();
        let body = response.text()?;
        if status != 200 {
            return Err(format!("{method} failed with HTTP {status}: {}", shorten(&body)).into());
        }
        let reply = match serde_json::from_str::<Value>(&body) {
            Ok(reply) if reply.get("result").is_some() || reply.get("error").is_some() => reply,
            _ => return Err(format!("{method} failed: unexpected response: {}", shorten(&body)).into()),
        };
        if let Some(error) = reply.get("error") {
            let message = error["message"].as_str().unwrap_or("unknown error");
            return Err(format!("{method} failed: {message}").into());
        }
        Ok(reply["result"].clone())
    }
    
    /// Returns the strings found under one key in each object of a list.
    fn strings(list: &Value, key: &str) -> Vec<String> {
        list.as_array()
            .map(|items| {
                items
                    .iter()
                    .filter_map(|item| item[key].as_str().map(String::from))
                    .collect()
            })
            .unwrap_or_default()
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
    
    BASE_URL = env_or("MCP_URL", "http://localhost:8080").sub(%r{/+\z}, "")
    TOKEN = env_or("MCP_TOKEN", "")
    
    TIMEOUT_SECONDS = 30
    
    # Raised when the MCP Server rejects a request or replies oddly.
    class McpError < StandardError; end
    
    # Parses a reply as a JSON object, or returns nil if it is not one.
    def parse_object(text)
      body = JSON.parse(text.to_s)
      body.is_a?(Hash) ? body : nil
    rescue JSON::ParserError
      nil
    end
    
    # Sends a JSON-RPC request and returns its result. The server answers a
    # JSON-RPC error with HTTP status 200, so the method checks the reply for
    # an error member as well as the HTTP status.
    def rpc(http, method, params)
      request = Net::HTTP::Post.new(URI("#{BASE_URL}/mcp/v1"))
      request["Authorization"] = "Bearer #{TOKEN}"
      request["Content-Type"] = "application/json"
      request.body = JSON.generate({ jsonrpc: "2.0", id: 1, method: method, params: params })
      response = http.request(request)
      unless response.code == "200"
        raise McpError, "#{method} failed with HTTP #{response.code}: #{response.body.to_s[0, 200]}"
      end
    
      reply = parse_object(response.body)
      unless reply && (reply.key?("result") || reply.key?("error"))
        raise McpError, "#{method} failed: unexpected response: #{response.body.to_s[0, 200]}"
      end
      raise McpError, "#{method} failed: #{reply["error"]["message"]}" if reply.key?("error")
    
      reply["result"]
    end
    ```

=== "curl"

    ```bash
    # Read the settings from the environment. The :- and :? forms, unlike - and
    # ?, treat an empty variable as unset.
    MCP_URL="${MCP_URL:-http://localhost:8080}"
    MCP_URL="${MCP_URL%/}"
    : "${MCP_TOKEN:?MCP_TOKEN must be set}"
    
    TIMEOUT_SECONDS=30
    
    # Sends a JSON-RPC request and prints its result: rpc METHOD PARAMS_JSON.
    # The server answers a JSON-RPC error with HTTP status 200, so the function
    # checks the reply for an error member as well as the HTTP status. The
    # token goes to curl in a header file that bash supplies through a pipe,
    # so that it never appears in the arguments of the curl process, which
    # other users can read in the process list.
    rpc() {
        local method="$1" request reply status body
        request=$(jq -nc --arg method "$method" --argjson params "$2" \
            '{jsonrpc: "2.0", id: 1, method: $method, params: $params}')
        reply=$(curl --silent --show-error \
            --connect-timeout 10 --max-time "$TIMEOUT_SECONDS" \
            --header @<(printf 'Authorization: Bearer %s\n' "$MCP_TOKEN") \
            --header 'Content-Type: application/json' \
            --write-out '\n%{http_code}' --data-binary "$request" \
            "$MCP_URL/mcp/v1") || return 1
        # --write-out puts the HTTP status on a line of its own at the end.
        status="${reply##*$'\n'}"
        body="${reply%$'\n'*}"
        if [[ "$status" != 200 ]]; then
            echo "$method failed with HTTP $status: ${body:0:200}" >&2
            return 1
        fi
        if ! jq -e 'has("result") or has("error")' >/dev/null 2>&1 <<<"$body"; then
            echo "$method failed: unexpected response: ${body:0:200}" >&2
            return 1
        fi
        if jq -e 'has("error")' >/dev/null <<<"$body"; then
            echo "$method failed: $(jq -r '.error.message' <<<"$body")" >&2
            return 1
        fi
        jq -c '.result' <<<"$body"
    }
    ```

## Reading a Resource

The `resources/list` method returns the URI, name, description and MIME type of
each resource, and the server sorts them by URI. The `resources/read` method
returns a resource's `contents`, whose first item holds the text;
`pg://system_info` has the MIME type `application/json`, so its text is itself
a JSON object, so each program parses it a second time. Its `version_number` is
a string such as `180006`, from which integer division by 10000 gives the major
version, and its `allow_writes` is a boolean. The following tabs show how each
program reads the resource:

=== "Python"

    ```python
    def read_system_info(client: httpx.Client) -> None:
        """Lists the resources that the server offers, and then reads
        pg://system_info, which describes the PostgreSQL server.
    
        The contents of a resource are text, which for this one holds a JSON
        object, so the function parses the text a second time. version_number
        is a string such as "180006", from which integer division by 10000
        gives the major version.
        """
        result = rpc(client, "resources/list", {})
        print("Resources: " + ", ".join(r["uri"] for r in result["resources"]))
    
        result = rpc(client, "resources/read", {"uri": "pg://system_info"})
        try:
            info = json.loads(result["contents"][0]["text"])
        except ValueError:
            raise McpError(f"Unexpected result: {str(result)[:200]}") from None
        print(f"PostgreSQL major version: {int(info['version_number']) // 10000}")
        print(f"Writes allowed: {str(info['allow_writes']).lower()}")
    ```

=== "TypeScript"

    ```typescript
    // Lists the resources that the server offers, and then reads
    // pg://system_info, which describes the PostgreSQL server. The contents of
    // a resource are text, which for this one holds a JSON object, so the
    // function parses the text a second time. version_number is a string such
    // as "180006", from which integer division by 10000 gives the major
    // version.
    async function readSystemInfo(): Promise<void> {
      const list = await rpc("resources/list", {});
      console.log(`Resources: ${list.resources.map((r: any) => r.uri).join(", ")}`);
    
      const result = await rpc("resources/read", { uri: "pg://system_info" });
      const info = JSON.parse(result.contents[0].text);
      const versionNumber = Number(info.version_number);
      if (!Number.isInteger(versionNumber) || typeof info.allow_writes !== "boolean") {
        throw new Error(`Unexpected result: ${JSON.stringify(result).slice(0, 200)}`);
      }
      console.log(`PostgreSQL major version: ${Math.floor(versionNumber / 10000)}`);
      console.log(`Writes allowed: ${info.allow_writes}`);
    }
    ```

=== "Java"

    ```java
    /**
     * Lists the resources that the server offers, and then reads
     * pg://system_info, which describes the PostgreSQL server. The contents
     * of a resource are text, which for this one holds a JSON object, so
     * the method parses the text a second time. version_number is a string
     * such as "180006", from which integer division by 10000 gives the
     * major version.
     */
    static void readSystemInfo() throws IOException, InterruptedException, McpException {
        List<String> uris = new ArrayList<>();
        for (JsonNode resource : rpc("resources/list", Map.of()).path("resources")) {
            uris.add(resource.path("uri").asString(""));
        }
        System.out.println("Resources: " + String.join(", ", uris));
    
        JsonNode result = rpc("resources/read", Map.of("uri", "pg://system_info"));
        JsonNode info = parseObject(
                result.path("contents").path(0).path("text").asString(""));
        if (info == null || !info.path("allow_writes").isBoolean()) {
            throw new McpException("Unexpected result: " + shorten(result.toString()));
        }
        int versionNumber;
        try {
            versionNumber = Integer.parseInt(info.path("version_number").asString(""));
        } catch (NumberFormatException e) {
            throw new McpException("Unexpected version number: " + info.path("version_number"));
        }
        System.out.println("PostgreSQL major version: " + versionNumber / 10000);
        System.out.println("Writes allowed: " + info.path("allow_writes").booleanValue());
    }
    ```

=== "C#"

    ```csharp
    // Lists the resources that the server offers, and then reads
    // pg://system_info, which describes the PostgreSQL server. The contents of
    // a resource are text, which for this one holds a JSON object, so the
    // function parses the text a second time. version_number is a string such
    // as "180006", from which integer division by 10000 gives the major
    // version.
    static async Task ReadSystemInfoAsync(HttpClient client)
    {
        var list = await RpcAsync(client, "resources/list", new JsonObject());
        var uris = list["resources"]?.AsArray().Select(r => r?["uri"]?.ToString()) ?? [];
        Console.WriteLine($"Resources: {string.Join(", ", uris)}");
    
        var result = await RpcAsync(client, "resources/read", new JsonObject
        {
            ["uri"] = "pg://system_info",
        });
        var info = ParseObject(result["contents"]?[0]?["text"]?.ToString() ?? "");
        if (info?["allow_writes"] is not JsonValue allowWrites ||
            !allowWrites.TryGetValue(out bool writes) ||
            !int.TryParse(info["version_number"]?.ToString(), out var versionNumber))
        {
            throw new McpException($"Unexpected result: {Shorten(result.ToJsonString())}");
        }
        Console.WriteLine($"PostgreSQL major version: {versionNumber / 10000}");
        // bool.ToString() gives "True" or "False", so the program writes the
        // JSON spelling instead.
        Console.WriteLine($"Writes allowed: {(writes ? "true" : "false")}");
    }
    ```

=== "Go"

    ```go
    // readSystemInfo lists the resources that the server offers, and then
    // reads pg://system_info, which describes the PostgreSQL server. The
    // contents of a resource are text, which for this one holds a JSON object,
    // so the function parses the text a second time. version_number is a
    // string such as "180006", from which integer division by 10000 gives the
    // major version.
    func readSystemInfo(client *http.Client) error {
    	var list struct {
    		Resources []struct {
    			URI string `json:"uri"`
    		} `json:"resources"`
    	}
    	if err := rpc(client, "resources/list", map[string]any{}, &list); err != nil {
    		return err
    	}
    	uris := make([]string, len(list.Resources))
    	for i, resource := range list.Resources {
    		uris[i] = resource.URI
    	}
    	fmt.Printf("Resources: %s\n", strings.Join(uris, ", "))
    
    	var result struct {
    		Contents []struct {
    			Text string `json:"text"`
    		} `json:"contents"`
    	}
    	if err := rpc(client, "resources/read", map[string]any{"uri": "pg://system_info"}, &result); err != nil {
    		return err
    	}
    	if len(result.Contents) == 0 {
    		return errors.New("resources/read failed: the result has no contents")
    	}
    	var info struct {
    		VersionNumber string `json:"version_number"`
    		AllowWrites   bool   `json:"allow_writes"`
    	}
    	if err := json.Unmarshal([]byte(result.Contents[0].Text), &info); err != nil {
    		return fmt.Errorf("unexpected result: %s", shorten([]byte(result.Contents[0].Text)))
    	}
    	versionNumber, err := strconv.Atoi(info.VersionNumber)
    	if err != nil {
    		return fmt.Errorf("unexpected version number: %q", info.VersionNumber)
    	}
    	fmt.Printf("PostgreSQL major version: %d\n", versionNumber/10000)
    	fmt.Printf("Writes allowed: %t\n", info.AllowWrites)
    	return nil
    }
    
    ```

=== "Rust"

    ```rust
    /// Lists the resources that the server offers, and then reads
    /// pg://system_info, which describes the PostgreSQL server. The contents
    /// of a resource are text, which for this one holds a JSON object, so the
    /// function parses the text a second time. version_number is a string such
    /// as "180006", from which integer division by 10000 gives the major
    /// version.
    fn read_system_info(client: &Client) -> Result<(), BoxError> {
        let list = rpc(client, "resources/list", json!({}))?;
        println!("Resources: {}", strings(&list["resources"], "uri").join(", "));
    
        let result = rpc(client, "resources/read", json!({"uri": "pg://system_info"}))?;
        let text = result["contents"][0]["text"].as_str().unwrap_or("");
        let info: Value = serde_json::from_str(text).unwrap_or(Value::Null);
        let version_number = info["version_number"]
            .as_str()
            .and_then(|number| number.parse::<u32>().ok());
        let (Some(version_number), Some(allow_writes)) =
            (version_number, info["allow_writes"].as_bool())
        else {
            return Err(format!("Unexpected result: {}", shorten(&result.to_string())).into());
        };
        println!("PostgreSQL major version: {}", version_number / 10000);
        println!("Writes allowed: {allow_writes}");
        Ok(())
    }
    ```

=== "Ruby"

    ```ruby
    # Lists the resources that the server offers, and then reads
    # pg://system_info, which describes the PostgreSQL server. The contents of
    # a resource are text, which for this one holds a JSON object, so the
    # method parses the text a second time. version_number is a string such as
    # "180006", from which integer division by 10000 gives the major version.
    def read_system_info(http)
      list = rpc(http, "resources/list", {})
      puts "Resources: #{Array(list["resources"]).map { |r| r["uri"] }.join(", ")}"
    
      result = rpc(http, "resources/read", { uri: "pg://system_info" })
      info = parse_object(result.dig("contents", 0, "text"))
      version_number = Integer(info["version_number"], exception: false) if info
      unless version_number && [true, false].include?(info["allow_writes"])
        raise McpError, "Unexpected result: #{result.to_s[0, 200]}"
      end
    
      puts "PostgreSQL major version: #{version_number / 10_000}"
      puts "Writes allowed: #{info["allow_writes"]}"
    end
    ```

=== "curl"

    ```bash
    # Lists the resources that the server offers, and then reads
    # pg://system_info, which describes the PostgreSQL server. The contents of
    # a resource are text, which for this one holds a JSON object, so the
    # script parses the text a second time. version_number is a string such as
    # "180006", from which integer division by 10000 gives the major version.
    read_system_info() {
        local result
        result=$(rpc resources/list '{}') || return 1
        echo "Resources: $(jq -r '[.resources[].uri] | join(", ")' <<<"$result")"
    
        result=$(rpc resources/read '{"uri": "pg://system_info"}') || return 1
        jq -r '.contents[0].text | fromjson
               | "PostgreSQL major version: \(.version_number | tonumber / 10000 | floor)",
                 "Writes allowed: \(.allow_writes)"' <<<"$result" 2>/dev/null || {
            echo "Unexpected result: ${result:0:200}" >&2
            return 1
        }
    }
    ```

## Fetching a Prompt

The `prompts/list` method returns the name, description and arguments of each
prompt, sorted by name, and the `prompts/get` method returns a prompt's
description and messages, filled in with the `arguments` that the client gives.
The `explore-database` prompt takes no arguments. The following tabs show how
each program lists the prompts and fetches one:

=== "Python"

    ```python
    def read_prompts(client: httpx.Client) -> None:
        """Lists the prompts that the server offers, and then fetches
        explore-database, which takes no arguments. A prompt is a set of
        messages, ready to hand to a language model, that guide it through a
        task with the server's tools."""
        result = rpc(client, "prompts/list", {})
        print("Prompts: " + ", ".join(p["name"] for p in result["prompts"]))
    
        result = rpc(client, "prompts/get",
                     {"name": "explore-database", "arguments": {}})
        print(f"explore-database: {result['description']}")
        print(f"First message role: {result['messages'][0]['role']}")
    ```

=== "TypeScript"

    ```typescript
    // Lists the prompts that the server offers, and then fetches
    // explore-database, which takes no arguments. A prompt is a set of
    // messages, ready to hand to a language model, that guide it through a
    // task with the server's tools.
    async function readPrompts(): Promise<void> {
      const list = await rpc("prompts/list", {});
      console.log(`Prompts: ${list.prompts.map((p: any) => p.name).join(", ")}`);
    
      const result = await rpc("prompts/get", { name: "explore-database", arguments: {} });
      console.log(`explore-database: ${result.description}`);
      console.log(`First message role: ${result.messages[0].role}`);
    }
    ```

=== "Java"

    ```java
    /**
     * Lists the prompts that the server offers, and then fetches
     * explore-database, which takes no arguments. A prompt is a set of
     * messages, ready to hand to a language model, that guide it through a
     * task with the server's tools.
     */
    static void readPrompts() throws IOException, InterruptedException, McpException {
        List<String> names = new ArrayList<>();
        for (JsonNode prompt : rpc("prompts/list", Map.of()).path("prompts")) {
            names.add(prompt.path("name").asString(""));
        }
        System.out.println("Prompts: " + String.join(", ", names));
    
        JsonNode prompt = rpc("prompts/get",
                Map.of("name", "explore-database", "arguments", Map.of()));
        JsonNode role = prompt.path("messages").path(0).path("role");
        if (!role.isString()) {
            throw new McpException("Unexpected result: " + shorten(prompt.toString()));
        }
        System.out.println("explore-database: " + prompt.path("description").asString(""));
        System.out.println("First message role: " + role.stringValue());
    }
    ```

=== "C#"

    ```csharp
    // Lists the prompts that the server offers, and then fetches
    // explore-database, which takes no arguments. A prompt is a set of
    // messages, ready to hand to a language model, that guide it through a
    // task with the server's tools.
    static async Task ReadPromptsAsync(HttpClient client)
    {
        var list = await RpcAsync(client, "prompts/list", new JsonObject());
        var names = list["prompts"]?.AsArray().Select(p => p?["name"]?.ToString()) ?? [];
        Console.WriteLine($"Prompts: {string.Join(", ", names)}");
    
        var prompt = await RpcAsync(client, "prompts/get", new JsonObject
        {
            ["name"] = "explore-database",
            ["arguments"] = new JsonObject(),
        });
        if (prompt["messages"]?[0]?["role"] is not JsonValue role)
        {
            throw new McpException($"Unexpected result: {Shorten(prompt.ToJsonString())}");
        }
        Console.WriteLine($"explore-database: {prompt["description"]}");
        Console.WriteLine($"First message role: {role}");
    }
    ```

=== "Go"

    ```go
    // readPrompts lists the prompts that the server offers, and then fetches
    // explore-database, which takes no arguments. A prompt is a set of
    // messages, ready to hand to a language model, that guide it through a
    // task with the server's tools.
    func readPrompts(client *http.Client) error {
    	var list struct {
    		Prompts []struct {
    			Name string `json:"name"`
    		} `json:"prompts"`
    	}
    	if err := rpc(client, "prompts/list", map[string]any{}, &list); err != nil {
    		return err
    	}
    	names := make([]string, len(list.Prompts))
    	for i, prompt := range list.Prompts {
    		names[i] = prompt.Name
    	}
    	fmt.Printf("Prompts: %s\n", strings.Join(names, ", "))
    
    	var prompt struct {
    		Description string `json:"description"`
    		Messages    []struct {
    			Role string `json:"role"`
    		} `json:"messages"`
    	}
    	err := rpc(client, "prompts/get",
    		map[string]any{"name": "explore-database", "arguments": map[string]any{}}, &prompt)
    	if err != nil {
    		return err
    	}
    	if len(prompt.Messages) == 0 {
    		return errors.New("prompts/get failed: the prompt has no messages")
    	}
    	fmt.Printf("explore-database: %s\n", prompt.Description)
    	fmt.Printf("First message role: %s\n", prompt.Messages[0].Role)
    	return nil
    }
    
    ```

=== "Rust"

    ```rust
    /// Lists the prompts that the server offers, and then fetches
    /// explore-database, which takes no arguments. A prompt is a set of
    /// messages, ready to hand to a language model, that guide it through a
    /// task with the server's tools.
    fn read_prompts(client: &Client) -> Result<(), BoxError> {
        let list = rpc(client, "prompts/list", json!({}))?;
        println!("Prompts: {}", strings(&list["prompts"], "name").join(", "));
    
        let prompt = rpc(
            client,
            "prompts/get",
            json!({"name": "explore-database", "arguments": {}}),
        )?;
        let (Some(description), Some(role)) = (
            prompt["description"].as_str(),
            prompt["messages"][0]["role"].as_str(),
        ) else {
            return Err(format!("Unexpected result: {}", shorten(&prompt.to_string())).into());
        };
        println!("explore-database: {description}");
        println!("First message role: {role}");
        Ok(())
    }
    ```

=== "Ruby"

    ```ruby
    # Lists the prompts that the server offers, and then fetches
    # explore-database, which takes no arguments. A prompt is a set of
    # messages, ready to hand to a language model, that guide it through a
    # task with the server's tools.
    def read_prompts(http)
      list = rpc(http, "prompts/list", {})
      puts "Prompts: #{Array(list["prompts"]).map { |p| p["name"] }.join(", ")}"
    
      prompt = rpc(http, "prompts/get", { name: "explore-database", arguments: {} })
      role = prompt.dig("messages", 0, "role")
      raise McpError, "Unexpected result: #{prompt.to_s[0, 200]}" unless role.is_a?(String)
    
      puts "explore-database: #{prompt["description"]}"
      puts "First message role: #{role}"
    end
    ```

=== "curl"

    ```bash
    # Lists the prompts that the server offers, and then fetches
    # explore-database, which takes no arguments. A prompt is a set of
    # messages, ready to hand to a language model, that guide it through a
    # task with the server's tools.
    read_prompts() {
        local result
        result=$(rpc prompts/list '{}') || return 1
        echo "Prompts: $(jq -r '[.prompts[].name] | join(", ")' <<<"$result")"
    
        result=$(rpc prompts/get '{"name": "explore-database", "arguments": {}}') \
            || return 1
        jq -r '"explore-database: \(.description)",
               "First message role: \(.messages[0].role)"' <<<"$result"
    }
    ```

## Handling Errors

The main part of each program checks that a token is set, runs both steps,
reports any failure on `stderr`, and exits with a non-zero status. The
following tabs show the main part of each program:

=== "Python"

    ```python
    def main() -> int:
        if not TOKEN:
            print("MCP_TOKEN must be set", file=sys.stderr)
            return 1
        try:
            with httpx.Client(base_url=BASE_URL, timeout=TIMEOUT_SECONDS) as client:
                read_system_info(client)
                read_prompts(client)
        # httpx.HTTPError is the base class for failures to reach the server,
        # such as a refused connection or a timeout. KeyError, IndexError,
        # TypeError, AttributeError and ValueError cover a reply that lacks the
        # members the program reads, or holds one of the wrong type or form.
        except (httpx.HTTPError, McpError, KeyError, IndexError, TypeError,
                AttributeError, ValueError) as e:
            print(f"MCP Server error: {e}", file=sys.stderr)
            return 1
        return 0
    
    
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
      if (!token) {
        console.error("MCP_TOKEN must be set");
        return 1;
      }
      try {
        await readSystemInfo();
        await readPrompts();
        return 0;
      } catch (err) {
        console.error(`MCP Server error: ${describe(err)}`);
        return 1;
      }
    }
    
    process.exitCode = await main();
    ```

=== "Java"

    ```java
    public static void main(String[] args) {
        if (TOKEN.isEmpty()) {
            System.err.println("MCP_TOKEN must be set");
            System.exit(1);
        }
        try {
            readSystemInfo();
            readPrompts();
        // IOException covers failures to reach the server, such as a
        // refused connection or a timeout. The message of a refused
        // connection can be empty, so print the exception itself, which
        // includes its type.
        } catch (IOException | InterruptedException e) {
            System.err.println("MCP Server error: " + e);
            System.exit(1);
        } catch (McpException e) {
            System.err.println("MCP Server error: " + e.getMessage());
            System.exit(1);
        }
    }
    ```

=== "C#"

    ```csharp
    if (Token().Length == 0)
    {
        Console.Error.WriteLine("MCP_TOKEN must be set");
        return 1;
    }
    try
    {
        // using disposes of the client, and closes its connections, when the
        // block exits, whether or not an error occurred.
        using var client = new HttpClient
        {
            Timeout = TimeSpan.FromSeconds(TimeoutSeconds),
        };
        await ReadSystemInfoAsync(client);
        await ReadPromptsAsync(client);
    }
    // HttpRequestException covers failures to reach the server, such as a
    // refused connection, and TaskCanceledException covers a timeout.
    // InvalidOperationException covers a member of the reply that has the
    // wrong type, such as a list that is not an array.
    catch (Exception e) when (
        e is HttpRequestException or TaskCanceledException or McpException
            or InvalidOperationException)
    {
        Console.Error.WriteLine($"MCP Server error: {e.Message}");
        return 1;
    }
    return 0;
    
    // C# requires type declarations to follow the top-level statements, so
    // the exception that the program throws for an error reply is declared
    // here, at the end.
    class McpException(string message) : Exception(message);
    ```

=== "Go"

    ```go
    // run makes the requests and returns any error to the caller.
    func run() error {
    	if token == "" {
    		return errors.New("MCP_TOKEN must be set")
    	}
    	client := &http.Client{Timeout: timeout}
    	if err := readSystemInfo(client); err != nil {
    		return err
    	}
    	return readPrompts(client)
    }
    
    // main reports any error returned by run() and exits with a non-zero
    // status.
    func main() {
    	if err := run(); err != nil {
    		fmt.Fprintf(os.Stderr, "MCP Server error: %v\n", err)
    		os.Exit(1)
    	}
    }
    
    ```

=== "Rust"

    ```rust
    /// Makes the requests. The ? operator returns any error to the caller.
    fn run() -> Result<(), BoxError> {
        if token().is_empty() {
            return Err("MCP_TOKEN must be set".into());
        }
        let client = Client::builder().timeout(TIMEOUT).build()?;
        read_system_info(&client)?;
        read_prompts(&client)
    }
    
    /// Reports any error returned by run() and exits with a failure status.
    /// The top-level error is often generic ("error sending request"), so the
    /// chain of underlying causes is printed too.
    fn main() -> ExitCode {
        match run() {
            Ok(()) => ExitCode::SUCCESS,
            Err(e) => {
                eprintln!("MCP Server error: {e}");
                let mut cause = e.source();
                while let Some(c) = cause {
                    eprintln!("  caused by: {c}");
                    cause = c.source();
                }
                ExitCode::FAILURE
            }
        }
    }
    ```

=== "Ruby"

    ```ruby
    if TOKEN.empty?
      warn "MCP_TOKEN must be set"
      exit 1
    end
    
    begin
      uri = URI(BASE_URL)
      # start opens a connection, and closes it when the block exits, whether
      # or not an error occurred.
      Net::HTTP.start(
        uri.host, uri.port,
        use_ssl: uri.scheme == "https",
        open_timeout: TIMEOUT_SECONDS, read_timeout: TIMEOUT_SECONDS
      ) do |http|
        read_system_info(http)
        read_prompts(http)
      end
    # SystemCallError covers a refused connection, Timeout::Error covers the
    # connection and read timeouts, and SocketError covers an unknown host.
    rescue McpError, SystemCallError, Timeout::Error, SocketError, IOError => e
      warn "MCP Server error: #{e.message}"
      exit 1
    end
    ```

=== "curl"

    ```bash
    main() {
        read_system_info
        read_prompts
    }
    
    main
    ```

## Running the Example

The complete project for each language is available in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/postgres_mcp/resources_and_prompts).
Set `MCP_URL` and `MCP_TOKEN` to the values that
`scripts/start_postgres_mcp.sh` prints, or to those of your own server, and
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
    Reading resources and prompts from the pgEdge Postgres MCP Server, using
    httpx.
    
    These examples are for pgEdge Postgres MCP Server 1.1.0.
    
    Copyright (c) 2026, pgEdge, Inc.
    This code is released under the PostgreSQL License.
    """
    
    import json
    import os
    import sys
    
    import httpx
    
    
    # The or operator treats an empty variable as unset.
    BASE_URL = (os.environ.get("MCP_URL") or "http://localhost:8080").rstrip("/")
    TOKEN = os.environ.get("MCP_TOKEN") or ""
    
    TIMEOUT_SECONDS = 30
    
    
    class McpError(Exception):
        """Raised when the MCP Server rejects a request or replies oddly."""
    
    
    def rpc(client: httpx.Client, method: str, params: dict):
        """Sends a JSON-RPC request and returns its result.
    
        The server answers a JSON-RPC error with HTTP status 200, so the
        function checks the reply for an error member as well as the HTTP
        status.
        """
        response = client.post(
            "/mcp/v1",
            headers={"Authorization": f"Bearer {TOKEN}"},
            json={"jsonrpc": "2.0", "id": 1, "method": method, "params": params},
        )
        if response.status_code != 200:
            raise McpError(f"{method} failed with HTTP {response.status_code}: "
                           f"{response.text[:200]}")
        try:
            reply = response.json()
        except ValueError:
            reply = None
        if not isinstance(reply, dict) or not ("result" in reply or "error" in reply):
            raise McpError(f"{method} failed: unexpected response: "
                           f"{response.text[:200]}")
        if "error" in reply:
            raise McpError(f"{method} failed: {reply['error'].get('message')}")
        return reply["result"]
    
    
    def read_system_info(client: httpx.Client) -> None:
        """Lists the resources that the server offers, and then reads
        pg://system_info, which describes the PostgreSQL server.
    
        The contents of a resource are text, which for this one holds a JSON
        object, so the function parses the text a second time. version_number
        is a string such as "180006", from which integer division by 10000
        gives the major version.
        """
        result = rpc(client, "resources/list", {})
        print("Resources: " + ", ".join(r["uri"] for r in result["resources"]))
    
        result = rpc(client, "resources/read", {"uri": "pg://system_info"})
        try:
            info = json.loads(result["contents"][0]["text"])
        except ValueError:
            raise McpError(f"Unexpected result: {str(result)[:200]}") from None
        print(f"PostgreSQL major version: {int(info['version_number']) // 10000}")
        print(f"Writes allowed: {str(info['allow_writes']).lower()}")
    
    
    def read_prompts(client: httpx.Client) -> None:
        """Lists the prompts that the server offers, and then fetches
        explore-database, which takes no arguments. A prompt is a set of
        messages, ready to hand to a language model, that guide it through a
        task with the server's tools."""
        result = rpc(client, "prompts/list", {})
        print("Prompts: " + ", ".join(p["name"] for p in result["prompts"]))
    
        result = rpc(client, "prompts/get",
                     {"name": "explore-database", "arguments": {}})
        print(f"explore-database: {result['description']}")
        print(f"First message role: {result['messages'][0]['role']}")
    
    
    def main() -> int:
        if not TOKEN:
            print("MCP_TOKEN must be set", file=sys.stderr)
            return 1
        try:
            with httpx.Client(base_url=BASE_URL, timeout=TIMEOUT_SECONDS) as client:
                read_system_info(client)
                read_prompts(client)
        # httpx.HTTPError is the base class for failures to reach the server,
        # such as a refused connection or a timeout. KeyError, IndexError,
        # TypeError, AttributeError and ValueError cover a reply that lacks the
        # members the program reads, or holds one of the wrong type or form.
        except (httpx.HTTPError, McpError, KeyError, IndexError, TypeError,
                AttributeError, ValueError) as e:
            print(f"MCP Server error: {e}", file=sys.stderr)
            return 1
        return 0
    
    
    if __name__ == "__main__":
        sys.exit(main())
    
    ```

=== "TypeScript"

    ```typescript
    /*
     * Ellie's Postgres Cookbook
     * Reading resources and prompts from the pgEdge Postgres MCP Server,
     * using the built-in fetch.
     *
     * These examples are for pgEdge Postgres MCP Server 1.1.0.
     *
     * Copyright (c) 2026, pgEdge, Inc.
     * This code is released under the PostgreSQL License.
     */
    
    // Node.js provides fetch and AbortSignal as globals, so this program
    // imports nothing.
    
    // The || operator, unlike ??, also treats an empty variable as unset.
    const baseUrl = (process.env.MCP_URL || "http://localhost:8080").replace(/\/+$/, "");
    const token = process.env.MCP_TOKEN || "";
    
    const timeoutMs = 30_000;
    
    // Sends a JSON-RPC request and returns its result. The server answers a
    // JSON-RPC error with HTTP status 200, so the function checks the reply
    // for an error member as well as the HTTP status.
    async function rpc(method: string, params: object): Promise<any> {
      const response = await fetch(`${baseUrl}/mcp/v1`, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${token}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ jsonrpc: "2.0", id: 1, method, params }),
        signal: AbortSignal.timeout(timeoutMs),
      });
      const text = await response.text();
      if (response.status !== 200) {
        throw new Error(`${method} failed with HTTP ${response.status}: ${text.slice(0, 200)}`);
      }
      let reply: any;
      try {
        reply = JSON.parse(text);
      } catch {
        reply = undefined;
      }
      if (typeof reply !== "object" || reply === null || !("result" in reply || "error" in reply)) {
        throw new Error(`${method} failed: unexpected response: ${text.slice(0, 200)}`);
      }
      if ("error" in reply) {
        throw new Error(`${method} failed: ${reply.error?.message}`);
      }
      return reply.result;
    }
    
    // Lists the resources that the server offers, and then reads
    // pg://system_info, which describes the PostgreSQL server. The contents of
    // a resource are text, which for this one holds a JSON object, so the
    // function parses the text a second time. version_number is a string such
    // as "180006", from which integer division by 10000 gives the major
    // version.
    async function readSystemInfo(): Promise<void> {
      const list = await rpc("resources/list", {});
      console.log(`Resources: ${list.resources.map((r: any) => r.uri).join(", ")}`);
    
      const result = await rpc("resources/read", { uri: "pg://system_info" });
      const info = JSON.parse(result.contents[0].text);
      const versionNumber = Number(info.version_number);
      if (!Number.isInteger(versionNumber) || typeof info.allow_writes !== "boolean") {
        throw new Error(`Unexpected result: ${JSON.stringify(result).slice(0, 200)}`);
      }
      console.log(`PostgreSQL major version: ${Math.floor(versionNumber / 10000)}`);
      console.log(`Writes allowed: ${info.allow_writes}`);
    }
    
    // Lists the prompts that the server offers, and then fetches
    // explore-database, which takes no arguments. A prompt is a set of
    // messages, ready to hand to a language model, that guide it through a
    // task with the server's tools.
    async function readPrompts(): Promise<void> {
      const list = await rpc("prompts/list", {});
      console.log(`Prompts: ${list.prompts.map((p: any) => p.name).join(", ")}`);
    
      const result = await rpc("prompts/get", { name: "explore-database", arguments: {} });
      console.log(`explore-database: ${result.description}`);
      console.log(`First message role: ${result.messages[0].role}`);
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
      if (!token) {
        console.error("MCP_TOKEN must be set");
        return 1;
      }
      try {
        await readSystemInfo();
        await readPrompts();
        return 0;
      } catch (err) {
        console.error(`MCP Server error: ${describe(err)}`);
        return 1;
      }
    }
    
    process.exitCode = await main();
    
    ```

=== "Java"

    ```java
    /*
     * Ellie's Postgres Cookbook
     * Reading resources and prompts from the pgEdge Postgres MCP Server, using
     * java.net.http and Jackson.
     *
     * These examples are for pgEdge Postgres MCP Server 1.1.0.
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
    import java.util.ArrayList;
    import java.util.List;
    import java.util.Map;
    import java.util.concurrent.CompletableFuture;
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
    
        static final String BASE_URL =
                envOr("MCP_URL", "http://localhost:8080").replaceAll("/+$", "");
        static final String TOKEN = envOr("MCP_TOKEN", "");
    
        static final Duration TIMEOUT = Duration.ofSeconds(30);
    
        /** Thrown when the MCP Server rejects a request or replies oddly. */
        static class McpException extends Exception {
            McpException(String message) {
                super(message);
            }
        }
    
        // A client and a mapper are safe to share, so the program creates
        // only one of each.
        static final HttpClient CLIENT = HttpClient.newBuilder()
                .connectTimeout(TIMEOUT)
                .build();
        static final ObjectMapper MAPPER = JsonMapper.builder().build();
    
        /** Returns at most the first 200 characters of a reply. */
        static String shorten(String text) {
            return text.length() > 200 ? text.substring(0, 200) : text;
        }
    
        /**
         * Sends a request and returns the response with its whole body. The
         * request timeout stops applying once the headers arrive, so a server
         * that stalls part of the way through the body would hang send(); this
         * applies the timeout to the whole exchange instead.
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
    
        /** Parses a reply as a JSON object, or returns null if it is not one. */
        static JsonNode parseObject(String text) {
            try {
                JsonNode node = MAPPER.readTree(text);
                return node.isObject() ? node : null;
            } catch (JacksonException e) {
                return null;
            }
        }
    
        /**
         * Sends a JSON-RPC request and returns its result. The server answers a
         * JSON-RPC error with HTTP status 200, so the method checks the reply
         * for an error member as well as the HTTP status.
         */
        static JsonNode rpc(String method, Map<String, Object> params)
                throws IOException, InterruptedException, McpException {
            String message = MAPPER.writeValueAsString(Map.of(
                    "jsonrpc", "2.0", "id", 1, "method", method, "params", params));
            HttpRequest request = HttpRequest.newBuilder(URI.create(BASE_URL + "/mcp/v1"))
                    .timeout(TIMEOUT)
                    .header("Authorization", "Bearer " + TOKEN)
                    .header("Content-Type", "application/json")
                    .POST(HttpRequest.BodyPublishers.ofString(message))
                    .build();
            HttpResponse<String> response = send(request);
            if (response.statusCode() != 200) {
                throw new McpException(method + " failed with HTTP "
                        + response.statusCode() + ": " + shorten(response.body()));
            }
            JsonNode reply = parseObject(response.body());
            if (reply == null || !(reply.has("result") || reply.has("error"))) {
                throw new McpException(method + " failed: unexpected response: "
                        + shorten(response.body()));
            }
            if (reply.has("error")) {
                throw new McpException(method + " failed: "
                        + reply.path("error").path("message").asString());
            }
            return reply.get("result");
        }
    
        /**
         * Lists the resources that the server offers, and then reads
         * pg://system_info, which describes the PostgreSQL server. The contents
         * of a resource are text, which for this one holds a JSON object, so
         * the method parses the text a second time. version_number is a string
         * such as "180006", from which integer division by 10000 gives the
         * major version.
         */
        static void readSystemInfo() throws IOException, InterruptedException, McpException {
            List<String> uris = new ArrayList<>();
            for (JsonNode resource : rpc("resources/list", Map.of()).path("resources")) {
                uris.add(resource.path("uri").asString(""));
            }
            System.out.println("Resources: " + String.join(", ", uris));
    
            JsonNode result = rpc("resources/read", Map.of("uri", "pg://system_info"));
            JsonNode info = parseObject(
                    result.path("contents").path(0).path("text").asString(""));
            if (info == null || !info.path("allow_writes").isBoolean()) {
                throw new McpException("Unexpected result: " + shorten(result.toString()));
            }
            int versionNumber;
            try {
                versionNumber = Integer.parseInt(info.path("version_number").asString(""));
            } catch (NumberFormatException e) {
                throw new McpException("Unexpected version number: " + info.path("version_number"));
            }
            System.out.println("PostgreSQL major version: " + versionNumber / 10000);
            System.out.println("Writes allowed: " + info.path("allow_writes").booleanValue());
        }
    
        /**
         * Lists the prompts that the server offers, and then fetches
         * explore-database, which takes no arguments. A prompt is a set of
         * messages, ready to hand to a language model, that guide it through a
         * task with the server's tools.
         */
        static void readPrompts() throws IOException, InterruptedException, McpException {
            List<String> names = new ArrayList<>();
            for (JsonNode prompt : rpc("prompts/list", Map.of()).path("prompts")) {
                names.add(prompt.path("name").asString(""));
            }
            System.out.println("Prompts: " + String.join(", ", names));
    
            JsonNode prompt = rpc("prompts/get",
                    Map.of("name", "explore-database", "arguments", Map.of()));
            JsonNode role = prompt.path("messages").path(0).path("role");
            if (!role.isString()) {
                throw new McpException("Unexpected result: " + shorten(prompt.toString()));
            }
            System.out.println("explore-database: " + prompt.path("description").asString(""));
            System.out.println("First message role: " + role.stringValue());
        }
    
        public static void main(String[] args) {
            if (TOKEN.isEmpty()) {
                System.err.println("MCP_TOKEN must be set");
                System.exit(1);
            }
            try {
                readSystemInfo();
                readPrompts();
            // IOException covers failures to reach the server, such as a
            // refused connection or a timeout. The message of a refused
            // connection can be empty, so print the exception itself, which
            // includes its type.
            } catch (IOException | InterruptedException e) {
                System.err.println("MCP Server error: " + e);
                System.exit(1);
            } catch (McpException e) {
                System.err.println("MCP Server error: " + e.getMessage());
                System.exit(1);
            }
        }
    }
    
    ```

=== "C#"

    ```csharp
    /*
     * Ellie's Postgres Cookbook
     * Reading resources and prompts from the pgEdge Postgres MCP Server, using
     * HttpClient and System.Text.Json.
     *
     * These examples are for pgEdge Postgres MCP Server 1.1.0.
     *
     * Copyright (c) 2026, pgEdge, Inc.
     * This code is released under the PostgreSQL License.
     */
    
    using System.Net;
    using System.Text;
    using System.Text.Json;
    using System.Text.Json.Nodes;
    
    // Returns the value of an environment variable, or a fallback if the
    // variable is unset or empty.
    static string EnvOr(string name, string fallback) =>
        Environment.GetEnvironmentVariable(name) is { Length: > 0 } value
            ? value
            : fallback;
    
    static string BaseUrl() => EnvOr("MCP_URL", "http://localhost:8080").TrimEnd('/');
    static string Token() => EnvOr("MCP_TOKEN", "");
    
    const int TimeoutSeconds = 30;
    
    // Returns at most the first 200 characters of a reply.
    static string Shorten(string text) =>
        text.Length > 200 ? text[..200] : text;
    
    // Parses a reply as a JSON object, or returns null if it is not one.
    static JsonObject? ParseObject(string text)
    {
        try
        {
            return JsonNode.Parse(text) as JsonObject;
        }
        catch (JsonException)
        {
            return null;
        }
    }
    
    // Sends a JSON-RPC request and returns its result. The server answers a
    // JSON-RPC error with HTTP status 200, so the function checks the reply for
    // an error member as well as the HTTP status.
    static async Task<JsonNode> RpcAsync(HttpClient client, string method, JsonObject parameters)
    {
        var message = new JsonObject
        {
            ["jsonrpc"] = "2.0",
            ["id"] = 1,
            ["method"] = method,
            ["params"] = parameters,
        };
        using var request = new HttpRequestMessage(HttpMethod.Post, BaseUrl() + "/mcp/v1")
        {
            Content = new StringContent(
                message.ToJsonString(), Encoding.UTF8, "application/json"),
        };
        request.Headers.Add("Authorization", $"Bearer {Token()}");
        using var response = await client.SendAsync(request);
        var body = await response.Content.ReadAsStringAsync();
        if (response.StatusCode != HttpStatusCode.OK)
        {
            throw new McpException(
                $"{method} failed with HTTP {(int)response.StatusCode}: {Shorten(body)}");
        }
        var reply = ParseObject(body);
        if (reply is null || !(reply.ContainsKey("result") || reply.ContainsKey("error")))
        {
            throw new McpException($"{method} failed: unexpected response: {Shorten(body)}");
        }
        if (reply.ContainsKey("error"))
        {
            throw new McpException($"{method} failed: {reply["error"]?["message"]}");
        }
        return reply["result"] ?? throw new McpException($"{method} failed: no result");
    }
    
    // Lists the resources that the server offers, and then reads
    // pg://system_info, which describes the PostgreSQL server. The contents of
    // a resource are text, which for this one holds a JSON object, so the
    // function parses the text a second time. version_number is a string such
    // as "180006", from which integer division by 10000 gives the major
    // version.
    static async Task ReadSystemInfoAsync(HttpClient client)
    {
        var list = await RpcAsync(client, "resources/list", new JsonObject());
        var uris = list["resources"]?.AsArray().Select(r => r?["uri"]?.ToString()) ?? [];
        Console.WriteLine($"Resources: {string.Join(", ", uris)}");
    
        var result = await RpcAsync(client, "resources/read", new JsonObject
        {
            ["uri"] = "pg://system_info",
        });
        var info = ParseObject(result["contents"]?[0]?["text"]?.ToString() ?? "");
        if (info?["allow_writes"] is not JsonValue allowWrites ||
            !allowWrites.TryGetValue(out bool writes) ||
            !int.TryParse(info["version_number"]?.ToString(), out var versionNumber))
        {
            throw new McpException($"Unexpected result: {Shorten(result.ToJsonString())}");
        }
        Console.WriteLine($"PostgreSQL major version: {versionNumber / 10000}");
        // bool.ToString() gives "True" or "False", so the program writes the
        // JSON spelling instead.
        Console.WriteLine($"Writes allowed: {(writes ? "true" : "false")}");
    }
    
    // Lists the prompts that the server offers, and then fetches
    // explore-database, which takes no arguments. A prompt is a set of
    // messages, ready to hand to a language model, that guide it through a
    // task with the server's tools.
    static async Task ReadPromptsAsync(HttpClient client)
    {
        var list = await RpcAsync(client, "prompts/list", new JsonObject());
        var names = list["prompts"]?.AsArray().Select(p => p?["name"]?.ToString()) ?? [];
        Console.WriteLine($"Prompts: {string.Join(", ", names)}");
    
        var prompt = await RpcAsync(client, "prompts/get", new JsonObject
        {
            ["name"] = "explore-database",
            ["arguments"] = new JsonObject(),
        });
        if (prompt["messages"]?[0]?["role"] is not JsonValue role)
        {
            throw new McpException($"Unexpected result: {Shorten(prompt.ToJsonString())}");
        }
        Console.WriteLine($"explore-database: {prompt["description"]}");
        Console.WriteLine($"First message role: {role}");
    }
    
    if (Token().Length == 0)
    {
        Console.Error.WriteLine("MCP_TOKEN must be set");
        return 1;
    }
    try
    {
        // using disposes of the client, and closes its connections, when the
        // block exits, whether or not an error occurred.
        using var client = new HttpClient
        {
            Timeout = TimeSpan.FromSeconds(TimeoutSeconds),
        };
        await ReadSystemInfoAsync(client);
        await ReadPromptsAsync(client);
    }
    // HttpRequestException covers failures to reach the server, such as a
    // refused connection, and TaskCanceledException covers a timeout.
    // InvalidOperationException covers a member of the reply that has the
    // wrong type, such as a list that is not an array.
    catch (Exception e) when (
        e is HttpRequestException or TaskCanceledException or McpException
            or InvalidOperationException)
    {
        Console.Error.WriteLine($"MCP Server error: {e.Message}");
        return 1;
    }
    return 0;
    
    // C# requires type declarations to follow the top-level statements, so
    // the exception that the program throws for an error reply is declared
    // here, at the end.
    class McpException(string message) : Exception(message);
    
    ```

=== "Go"

    ```go
    // Ellie's Postgres Cookbook
    // Reading resources and prompts from the pgEdge Postgres MCP Server, using
    // net/http.
    //
    // These examples are for pgEdge Postgres MCP Server 1.1.0.
    //
    // Copyright (c) 2026, pgEdge, Inc.
    // This code is released under the PostgreSQL License.
    
    package main
    
    import (
    	"bytes"
    	"encoding/json"
    	"errors"
    	"fmt"
    	"io"
    	"net/http"
    	"os"
    	"strconv"
    	"strings"
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
    
    var (
    	baseURL = strings.TrimRight(envOr("MCP_URL", "http://localhost:8080"), "/")
    	token   = os.Getenv("MCP_TOKEN")
    )
    
    const timeout = 30 * time.Second
    
    // shorten returns at most the first 200 bytes of a reply.
    func shorten(body []byte) string {
    	if len(body) > 200 {
    		body = body[:200]
    	}
    	return string(body)
    }
    
    // rpc sends a JSON-RPC request and decodes its result into out. The
    // server answers a JSON-RPC error with HTTP status 200, so the function
    // checks the reply for an error member as well as the HTTP status.
    func rpc(client *http.Client, method string, params any, out any) error {
    	payload, err := json.Marshal(map[string]any{
    		"jsonrpc": "2.0", "id": 1, "method": method, "params": params,
    	})
    	if err != nil {
    		return err
    	}
    	request, err := http.NewRequest(http.MethodPost, baseURL+"/mcp/v1", bytes.NewReader(payload))
    	if err != nil {
    		return err
    	}
    	request.Header.Set("Authorization", "Bearer "+token)
    	request.Header.Set("Content-Type", "application/json")
    
    	response, err := client.Do(request)
    	if err != nil {
    		return err
    	}
    	defer response.Body.Close()
    	body, err := io.ReadAll(response.Body)
    	if err != nil {
    		return err
    	}
    	if response.StatusCode != http.StatusOK {
    		return fmt.Errorf("%s failed with HTTP %d: %s", method, response.StatusCode, shorten(body))
    	}
    	var reply struct {
    		Result json.RawMessage `json:"result"`
    		Error  *struct {
    			Message string `json:"message"`
    		} `json:"error"`
    	}
    	if err := json.Unmarshal(body, &reply); err != nil || (reply.Result == nil && reply.Error == nil) {
    		return fmt.Errorf("%s failed: unexpected response: %s", method, shorten(body))
    	}
    	if reply.Error != nil {
    		return fmt.Errorf("%s failed: %s", method, reply.Error.Message)
    	}
    	if err := json.Unmarshal(reply.Result, out); err != nil {
    		return fmt.Errorf("%s failed: unexpected result: %s", method, shorten(reply.Result))
    	}
    	return nil
    }
    
    
    // readSystemInfo lists the resources that the server offers, and then
    // reads pg://system_info, which describes the PostgreSQL server. The
    // contents of a resource are text, which for this one holds a JSON object,
    // so the function parses the text a second time. version_number is a
    // string such as "180006", from which integer division by 10000 gives the
    // major version.
    func readSystemInfo(client *http.Client) error {
    	var list struct {
    		Resources []struct {
    			URI string `json:"uri"`
    		} `json:"resources"`
    	}
    	if err := rpc(client, "resources/list", map[string]any{}, &list); err != nil {
    		return err
    	}
    	uris := make([]string, len(list.Resources))
    	for i, resource := range list.Resources {
    		uris[i] = resource.URI
    	}
    	fmt.Printf("Resources: %s\n", strings.Join(uris, ", "))
    
    	var result struct {
    		Contents []struct {
    			Text string `json:"text"`
    		} `json:"contents"`
    	}
    	if err := rpc(client, "resources/read", map[string]any{"uri": "pg://system_info"}, &result); err != nil {
    		return err
    	}
    	if len(result.Contents) == 0 {
    		return errors.New("resources/read failed: the result has no contents")
    	}
    	var info struct {
    		VersionNumber string `json:"version_number"`
    		AllowWrites   bool   `json:"allow_writes"`
    	}
    	if err := json.Unmarshal([]byte(result.Contents[0].Text), &info); err != nil {
    		return fmt.Errorf("unexpected result: %s", shorten([]byte(result.Contents[0].Text)))
    	}
    	versionNumber, err := strconv.Atoi(info.VersionNumber)
    	if err != nil {
    		return fmt.Errorf("unexpected version number: %q", info.VersionNumber)
    	}
    	fmt.Printf("PostgreSQL major version: %d\n", versionNumber/10000)
    	fmt.Printf("Writes allowed: %t\n", info.AllowWrites)
    	return nil
    }
    
    
    // readPrompts lists the prompts that the server offers, and then fetches
    // explore-database, which takes no arguments. A prompt is a set of
    // messages, ready to hand to a language model, that guide it through a
    // task with the server's tools.
    func readPrompts(client *http.Client) error {
    	var list struct {
    		Prompts []struct {
    			Name string `json:"name"`
    		} `json:"prompts"`
    	}
    	if err := rpc(client, "prompts/list", map[string]any{}, &list); err != nil {
    		return err
    	}
    	names := make([]string, len(list.Prompts))
    	for i, prompt := range list.Prompts {
    		names[i] = prompt.Name
    	}
    	fmt.Printf("Prompts: %s\n", strings.Join(names, ", "))
    
    	var prompt struct {
    		Description string `json:"description"`
    		Messages    []struct {
    			Role string `json:"role"`
    		} `json:"messages"`
    	}
    	err := rpc(client, "prompts/get",
    		map[string]any{"name": "explore-database", "arguments": map[string]any{}}, &prompt)
    	if err != nil {
    		return err
    	}
    	if len(prompt.Messages) == 0 {
    		return errors.New("prompts/get failed: the prompt has no messages")
    	}
    	fmt.Printf("explore-database: %s\n", prompt.Description)
    	fmt.Printf("First message role: %s\n", prompt.Messages[0].Role)
    	return nil
    }
    
    
    // run makes the requests and returns any error to the caller.
    func run() error {
    	if token == "" {
    		return errors.New("MCP_TOKEN must be set")
    	}
    	client := &http.Client{Timeout: timeout}
    	if err := readSystemInfo(client); err != nil {
    		return err
    	}
    	return readPrompts(client)
    }
    
    // main reports any error returned by run() and exits with a non-zero
    // status.
    func main() {
    	if err := run(); err != nil {
    		fmt.Fprintf(os.Stderr, "MCP Server error: %v\n", err)
    		os.Exit(1)
    	}
    }
    
    
    ```

=== "Rust"

    ```rust
    // Ellie's Postgres Cookbook
    // Reading resources and prompts from the pgEdge Postgres MCP Server, using
    // reqwest and serde_json.
    //
    // These examples are for pgEdge Postgres MCP Server 1.1.0.
    //
    // Copyright (c) 2026, pgEdge, Inc.
    // This code is released under the PostgreSQL License.
    
    use std::env;
    use std::error::Error;
    use std::process::ExitCode;
    use std::time::Duration;
    
    use reqwest::blocking::Client;
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
        env_or("MCP_URL", "http://localhost:8080")
            .trim_end_matches('/')
            .to_string()
    }
    
    fn token() -> String {
        env_or("MCP_TOKEN", "")
    }
    
    const TIMEOUT: Duration = Duration::from_secs(30);
    
    /// The errors that the functions below return; a string converts into one
    /// with the ? operator or into().
    type BoxError = Box<dyn Error>;
    
    /// Returns at most the first 200 characters of a reply.
    fn shorten(text: &str) -> String {
        text.chars().take(200).collect()
    }
    
    /// Sends a JSON-RPC request and returns its result. The server answers a
    /// JSON-RPC error with HTTP status 200, so the function checks the reply
    /// for an error member as well as the HTTP status.
    fn rpc(client: &Client, method: &str, params: Value) -> Result<Value, BoxError> {
        let message = json!({"jsonrpc": "2.0", "id": 1, "method": method, "params": params});
        let response = client
            .post(format!("{}/mcp/v1", base_url()))
            .bearer_auth(token())
            .json(&message)
            .send()?;
        let status = response.status().as_u16();
        let body = response.text()?;
        if status != 200 {
            return Err(format!("{method} failed with HTTP {status}: {}", shorten(&body)).into());
        }
        let reply = match serde_json::from_str::<Value>(&body) {
            Ok(reply) if reply.get("result").is_some() || reply.get("error").is_some() => reply,
            _ => return Err(format!("{method} failed: unexpected response: {}", shorten(&body)).into()),
        };
        if let Some(error) = reply.get("error") {
            let message = error["message"].as_str().unwrap_or("unknown error");
            return Err(format!("{method} failed: {message}").into());
        }
        Ok(reply["result"].clone())
    }
    
    /// Returns the strings found under one key in each object of a list.
    fn strings(list: &Value, key: &str) -> Vec<String> {
        list.as_array()
            .map(|items| {
                items
                    .iter()
                    .filter_map(|item| item[key].as_str().map(String::from))
                    .collect()
            })
            .unwrap_or_default()
    }
    
    /// Lists the resources that the server offers, and then reads
    /// pg://system_info, which describes the PostgreSQL server. The contents
    /// of a resource are text, which for this one holds a JSON object, so the
    /// function parses the text a second time. version_number is a string such
    /// as "180006", from which integer division by 10000 gives the major
    /// version.
    fn read_system_info(client: &Client) -> Result<(), BoxError> {
        let list = rpc(client, "resources/list", json!({}))?;
        println!("Resources: {}", strings(&list["resources"], "uri").join(", "));
    
        let result = rpc(client, "resources/read", json!({"uri": "pg://system_info"}))?;
        let text = result["contents"][0]["text"].as_str().unwrap_or("");
        let info: Value = serde_json::from_str(text).unwrap_or(Value::Null);
        let version_number = info["version_number"]
            .as_str()
            .and_then(|number| number.parse::<u32>().ok());
        let (Some(version_number), Some(allow_writes)) =
            (version_number, info["allow_writes"].as_bool())
        else {
            return Err(format!("Unexpected result: {}", shorten(&result.to_string())).into());
        };
        println!("PostgreSQL major version: {}", version_number / 10000);
        println!("Writes allowed: {allow_writes}");
        Ok(())
    }
    
    /// Lists the prompts that the server offers, and then fetches
    /// explore-database, which takes no arguments. A prompt is a set of
    /// messages, ready to hand to a language model, that guide it through a
    /// task with the server's tools.
    fn read_prompts(client: &Client) -> Result<(), BoxError> {
        let list = rpc(client, "prompts/list", json!({}))?;
        println!("Prompts: {}", strings(&list["prompts"], "name").join(", "));
    
        let prompt = rpc(
            client,
            "prompts/get",
            json!({"name": "explore-database", "arguments": {}}),
        )?;
        let (Some(description), Some(role)) = (
            prompt["description"].as_str(),
            prompt["messages"][0]["role"].as_str(),
        ) else {
            return Err(format!("Unexpected result: {}", shorten(&prompt.to_string())).into());
        };
        println!("explore-database: {description}");
        println!("First message role: {role}");
        Ok(())
    }
    
    /// Makes the requests. The ? operator returns any error to the caller.
    fn run() -> Result<(), BoxError> {
        if token().is_empty() {
            return Err("MCP_TOKEN must be set".into());
        }
        let client = Client::builder().timeout(TIMEOUT).build()?;
        read_system_info(&client)?;
        read_prompts(&client)
    }
    
    /// Reports any error returned by run() and exits with a failure status.
    /// The top-level error is often generic ("error sending request"), so the
    /// chain of underlying causes is printed too.
    fn main() -> ExitCode {
        match run() {
            Ok(()) => ExitCode::SUCCESS,
            Err(e) => {
                eprintln!("MCP Server error: {e}");
                let mut cause = e.source();
                while let Some(c) = cause {
                    eprintln!("  caused by: {c}");
                    cause = c.source();
                }
                ExitCode::FAILURE
            }
        }
    }
    
    ```

=== "Ruby"

    ```ruby
    # Ellie's Postgres Cookbook
    # Reading resources and prompts from the pgEdge Postgres MCP Server, using
    # Net::HTTP.
    #
    # These examples are for pgEdge Postgres MCP Server 1.1.0.
    #
    # Copyright (c) 2026, pgEdge, Inc.
    # This code is released under the PostgreSQL License.
    
    require "json"
    require "net/http"
    require "uri"
    
    # Returns the value of an environment variable, or a fallback if the
    # variable is unset or empty.
    def env_or(name, fallback)
      value = ENV[name]
      value.nil? || value.empty? ? fallback : value
    end
    
    BASE_URL = env_or("MCP_URL", "http://localhost:8080").sub(%r{/+\z}, "")
    TOKEN = env_or("MCP_TOKEN", "")
    
    TIMEOUT_SECONDS = 30
    
    # Raised when the MCP Server rejects a request or replies oddly.
    class McpError < StandardError; end
    
    # Parses a reply as a JSON object, or returns nil if it is not one.
    def parse_object(text)
      body = JSON.parse(text.to_s)
      body.is_a?(Hash) ? body : nil
    rescue JSON::ParserError
      nil
    end
    
    # Sends a JSON-RPC request and returns its result. The server answers a
    # JSON-RPC error with HTTP status 200, so the method checks the reply for
    # an error member as well as the HTTP status.
    def rpc(http, method, params)
      request = Net::HTTP::Post.new(URI("#{BASE_URL}/mcp/v1"))
      request["Authorization"] = "Bearer #{TOKEN}"
      request["Content-Type"] = "application/json"
      request.body = JSON.generate({ jsonrpc: "2.0", id: 1, method: method, params: params })
      response = http.request(request)
      unless response.code == "200"
        raise McpError, "#{method} failed with HTTP #{response.code}: #{response.body.to_s[0, 200]}"
      end
    
      reply = parse_object(response.body)
      unless reply && (reply.key?("result") || reply.key?("error"))
        raise McpError, "#{method} failed: unexpected response: #{response.body.to_s[0, 200]}"
      end
      raise McpError, "#{method} failed: #{reply["error"]["message"]}" if reply.key?("error")
    
      reply["result"]
    end
    
    # Lists the resources that the server offers, and then reads
    # pg://system_info, which describes the PostgreSQL server. The contents of
    # a resource are text, which for this one holds a JSON object, so the
    # method parses the text a second time. version_number is a string such as
    # "180006", from which integer division by 10000 gives the major version.
    def read_system_info(http)
      list = rpc(http, "resources/list", {})
      puts "Resources: #{Array(list["resources"]).map { |r| r["uri"] }.join(", ")}"
    
      result = rpc(http, "resources/read", { uri: "pg://system_info" })
      info = parse_object(result.dig("contents", 0, "text"))
      version_number = Integer(info["version_number"], exception: false) if info
      unless version_number && [true, false].include?(info["allow_writes"])
        raise McpError, "Unexpected result: #{result.to_s[0, 200]}"
      end
    
      puts "PostgreSQL major version: #{version_number / 10_000}"
      puts "Writes allowed: #{info["allow_writes"]}"
    end
    
    # Lists the prompts that the server offers, and then fetches
    # explore-database, which takes no arguments. A prompt is a set of
    # messages, ready to hand to a language model, that guide it through a
    # task with the server's tools.
    def read_prompts(http)
      list = rpc(http, "prompts/list", {})
      puts "Prompts: #{Array(list["prompts"]).map { |p| p["name"] }.join(", ")}"
    
      prompt = rpc(http, "prompts/get", { name: "explore-database", arguments: {} })
      role = prompt.dig("messages", 0, "role")
      raise McpError, "Unexpected result: #{prompt.to_s[0, 200]}" unless role.is_a?(String)
    
      puts "explore-database: #{prompt["description"]}"
      puts "First message role: #{role}"
    end
    
    if TOKEN.empty?
      warn "MCP_TOKEN must be set"
      exit 1
    end
    
    begin
      uri = URI(BASE_URL)
      # start opens a connection, and closes it when the block exits, whether
      # or not an error occurred.
      Net::HTTP.start(
        uri.host, uri.port,
        use_ssl: uri.scheme == "https",
        open_timeout: TIMEOUT_SECONDS, read_timeout: TIMEOUT_SECONDS
      ) do |http|
        read_system_info(http)
        read_prompts(http)
      end
    # SystemCallError covers a refused connection, Timeout::Error covers the
    # connection and read timeouts, and SocketError covers an unknown host.
    rescue McpError, SystemCallError, Timeout::Error, SocketError, IOError => e
      warn "MCP Server error: #{e.message}"
      exit 1
    end
    
    ```

=== "curl"

    ```bash
    #!/usr/bin/env bash
    #
    # Ellie's Postgres Cookbook
    # Reading resources and prompts from the pgEdge Postgres MCP Server, using
    # curl and jq.
    #
    # These examples are for pgEdge Postgres MCP Server 1.1.0.
    #
    # Copyright (c) 2026, pgEdge, Inc.
    # This code is released under the PostgreSQL License.
    
    # Stop at the first failed command or unset variable, and treat a failure
    # anywhere in a pipeline as a failure of the whole pipeline.
    set -euo pipefail
    
    # The script needs curl to make the requests and jq to build the requests
    # and read the replies.
    for tool in curl jq; do
        command -v "$tool" >/dev/null || { echo "$tool is required" >&2; exit 1; }
    done
    
    # Read the settings from the environment. The :- and :? forms, unlike - and
    # ?, treat an empty variable as unset.
    MCP_URL="${MCP_URL:-http://localhost:8080}"
    MCP_URL="${MCP_URL%/}"
    : "${MCP_TOKEN:?MCP_TOKEN must be set}"
    
    TIMEOUT_SECONDS=30
    
    # Sends a JSON-RPC request and prints its result: rpc METHOD PARAMS_JSON.
    # The server answers a JSON-RPC error with HTTP status 200, so the function
    # checks the reply for an error member as well as the HTTP status. The
    # token goes to curl in a header file that bash supplies through a pipe,
    # so that it never appears in the arguments of the curl process, which
    # other users can read in the process list.
    rpc() {
        local method="$1" request reply status body
        request=$(jq -nc --arg method "$method" --argjson params "$2" \
            '{jsonrpc: "2.0", id: 1, method: $method, params: $params}')
        reply=$(curl --silent --show-error \
            --connect-timeout 10 --max-time "$TIMEOUT_SECONDS" \
            --header @<(printf 'Authorization: Bearer %s\n' "$MCP_TOKEN") \
            --header 'Content-Type: application/json' \
            --write-out '\n%{http_code}' --data-binary "$request" \
            "$MCP_URL/mcp/v1") || return 1
        # --write-out puts the HTTP status on a line of its own at the end.
        status="${reply##*$'\n'}"
        body="${reply%$'\n'*}"
        if [[ "$status" != 200 ]]; then
            echo "$method failed with HTTP $status: ${body:0:200}" >&2
            return 1
        fi
        if ! jq -e 'has("result") or has("error")' >/dev/null 2>&1 <<<"$body"; then
            echo "$method failed: unexpected response: ${body:0:200}" >&2
            return 1
        fi
        if jq -e 'has("error")' >/dev/null <<<"$body"; then
            echo "$method failed: $(jq -r '.error.message' <<<"$body")" >&2
            return 1
        fi
        jq -c '.result' <<<"$body"
    }
    
    # Lists the resources that the server offers, and then reads
    # pg://system_info, which describes the PostgreSQL server. The contents of
    # a resource are text, which for this one holds a JSON object, so the
    # script parses the text a second time. version_number is a string such as
    # "180006", from which integer division by 10000 gives the major version.
    read_system_info() {
        local result
        result=$(rpc resources/list '{}') || return 1
        echo "Resources: $(jq -r '[.resources[].uri] | join(", ")' <<<"$result")"
    
        result=$(rpc resources/read '{"uri": "pg://system_info"}') || return 1
        jq -r '.contents[0].text | fromjson
               | "PostgreSQL major version: \(.version_number | tonumber / 10000 | floor)",
                 "Writes allowed: \(.allow_writes)"' <<<"$result" 2>/dev/null || {
            echo "Unexpected result: ${result:0:200}" >&2
            return 1
        }
    }
    
    # Lists the prompts that the server offers, and then fetches
    # explore-database, which takes no arguments. A prompt is a set of
    # messages, ready to hand to a language model, that guide it through a
    # task with the server's tools.
    read_prompts() {
        local result
        result=$(rpc prompts/list '{}') || return 1
        echo "Prompts: $(jq -r '[.prompts[].name] | join(", ")' <<<"$result")"
    
        result=$(rpc prompts/get '{"name": "explore-database", "arguments": {}}') \
            || return 1
        jq -r '"explore-database: \(.description)",
               "First message role: \(.messages[0].role)"' <<<"$result"
    }
    
    main() {
        read_system_info
        read_prompts
    }
    
    main
    
    ```

## Next Steps

The following resources provide more information about the topics in this
recipe:

- The [Connecting to the MCP Server](connect.md) recipe shows the handshake
  that an MCP client performs, and what the server does with a wrong token.
- The [Exploring a Schema](explore_schema.md) recipe lists the tables and
  columns of a schema.
- The [Calling AI DBA Workbench MCP Tools](../ai_dba_workbench/mcp_tools.md)
  recipe calls the same kind of tools through the AI DBA Workbench.
- The
  [pgEdge Postgres MCP Server documentation](https://docs.pgedge.com/pgedge-postgres-mcp-server/)
  describes every tool, resource and setting.
- The [Contributing a Recipe](../contributing.md) page explains how to add a
  recipe or a language to the cookbook.
