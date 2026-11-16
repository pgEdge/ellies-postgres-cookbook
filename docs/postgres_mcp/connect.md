# Connecting to the MCP Server

This recipe connects to a pgEdge Postgres MCP Server in the way that any MCP
client does: it checks that the server is running, introduces itself with the
`initialize` handshake, and shows what the server does with a token that it
does not know. The checks suit a deployment script, or a first test of a new
server and token. Each step shows the code in every supported language;
selecting a language tab switches every tab on the site to that language.

These examples are for pgEdge Postgres MCP Server 1.1.0.

The program prints the following output:

```text
Health: ok
Server: pgedge-postgres-mcp 1.1.0
Protocol version: 2025-06-18
Wrong token: HTTP 401, Invalid or unknown token
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
      "name": "connect",
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

The `post` helper sends any JSON-RPC message with a given token, which lets the
program send a wrong token later, and the `rpc` helper sends a request with the
configured token and returns its result.

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
    
    
    def post(client: httpx.Client, token: str, message: dict) -> httpx.Response:
        """Posts a JSON-RPC message to the MCP endpoint with a token."""
        return client.post(
            "/mcp/v1", json=message,
            headers={"Authorization": f"Bearer {token}"},
        )
    
    
    def rpc(client: httpx.Client, method: str, params: dict) -> dict:
        """Sends a JSON-RPC request and returns its result.
    
        The server answers a JSON-RPC error with HTTP status 200, so the
        function checks the reply for an error member as well as the HTTP
        status.
        """
        response = post(client, TOKEN, {
            "jsonrpc": "2.0", "id": 1, "method": method, "params": params,
        })
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
    
    // Posts a JSON-RPC message to the MCP endpoint with a token.
    async function post(withToken: string, message: object): Promise<Response> {
      return fetch(`${baseUrl}/mcp/v1`, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${withToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify(message),
        signal: AbortSignal.timeout(timeoutMs),
      });
    }
    
    // Sends a JSON-RPC request and returns its result. The server answers a
    // JSON-RPC error with HTTP status 200, so the function checks the reply
    // for an error member as well as the HTTP status.
    async function rpc(method: string, params: object): Promise<any> {
      const response = await post(token, { jsonrpc: "2.0", id: 1, method, params });
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
    
    /** Posts a JSON-RPC message to the MCP endpoint with a token. */
    static HttpResponse<String> post(String token, Map<String, Object> message)
            throws IOException, InterruptedException {
        HttpRequest request = HttpRequest.newBuilder(URI.create(BASE_URL + "/mcp/v1"))
                .timeout(TIMEOUT)
                .header("Authorization", "Bearer " + token)
                .header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString(
                        MAPPER.writeValueAsString(message)))
                .build();
        return send(request);
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
        HttpResponse<String> response = post(TOKEN, Map.of(
                "jsonrpc", "2.0", "id", 1, "method", method, "params", params));
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
    
    // Posts a JSON-RPC message to the MCP endpoint with a token, and returns
    // the HTTP status and the body of the reply.
    static async Task<(HttpStatusCode Status, string Body)> PostAsync(
        HttpClient client, string token, JsonObject message)
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, BaseUrl() + "/mcp/v1")
        {
            Content = new StringContent(
                message.ToJsonString(), Encoding.UTF8, "application/json"),
        };
        request.Headers.Add("Authorization", $"Bearer {token}");
        using var response = await client.SendAsync(request);
        return (response.StatusCode, await response.Content.ReadAsStringAsync());
    }
    
    // Sends a JSON-RPC request and returns its result. The server answers a
    // JSON-RPC error with HTTP status 200, so the function checks the reply for
    // an error member as well as the HTTP status.
    static async Task<JsonNode> RpcAsync(HttpClient client, string method, JsonObject parameters)
    {
        var (status, body) = await PostAsync(client, Token(), new JsonObject
        {
            ["jsonrpc"] = "2.0",
            ["id"] = 1,
            ["method"] = method,
            ["params"] = parameters,
        });
        if (status != HttpStatusCode.OK)
        {
            throw new McpException(
                $"{method} failed with HTTP {(int)status}: {Shorten(body)}");
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
    
    // post sends a JSON-RPC message to the MCP endpoint with a token, and
    // returns the HTTP status and the body of the reply.
    func post(client *http.Client, withToken string, message any) (int, []byte, error) {
    	payload, err := json.Marshal(message)
    	if err != nil {
    		return 0, nil, err
    	}
    	request, err := http.NewRequest(http.MethodPost, baseURL+"/mcp/v1", bytes.NewReader(payload))
    	if err != nil {
    		return 0, nil, err
    	}
    	request.Header.Set("Authorization", "Bearer "+withToken)
    	request.Header.Set("Content-Type", "application/json")
    
    	response, err := client.Do(request)
    	if err != nil {
    		return 0, nil, err
    	}
    	defer response.Body.Close()
    	body, err := io.ReadAll(response.Body)
    	return response.StatusCode, body, err
    }
    
    // rpc sends a JSON-RPC request and decodes its result into out. The
    // server answers a JSON-RPC error with HTTP status 200, so the function
    // checks the reply for an error member as well as the HTTP status.
    func rpc(client *http.Client, method string, params any, out any) error {
    	status, body, err := post(client, token, map[string]any{
    		"jsonrpc": "2.0", "id": 1, "method": method, "params": params,
    	})
    	if err != nil {
    		return err
    	}
    	if status != http.StatusOK {
    		return fmt.Errorf("%s failed with HTTP %d: %s", method, status, shorten(body))
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
    
    /// Posts a JSON-RPC message to the MCP endpoint with a token, and returns
    /// the HTTP status and the body of the reply.
    fn post(client: &Client, with_token: &str, message: &Value) -> Result<(u16, String), BoxError> {
        let response = client
            .post(format!("{}/mcp/v1", base_url()))
            .bearer_auth(with_token)
            .json(message)
            .send()?;
        let status = response.status().as_u16();
        Ok((status, response.text()?))
    }
    
    /// Sends a JSON-RPC request and returns its result. The server answers a
    /// JSON-RPC error with HTTP status 200, so the function checks the reply
    /// for an error member as well as the HTTP status.
    fn rpc(client: &Client, method: &str, params: Value) -> Result<Value, BoxError> {
        let message = json!({"jsonrpc": "2.0", "id": 1, "method": method, "params": params});
        let (status, body) = post(client, &token(), &message)?;
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
    
    # Posts a JSON-RPC message to the MCP endpoint with a token, and returns
    # the response.
    def post(http, token, message)
      request = Net::HTTP::Post.new(URI("#{BASE_URL}/mcp/v1"))
      request["Authorization"] = "Bearer #{token}"
      request["Content-Type"] = "application/json"
      request.body = JSON.generate(message)
      http.request(request)
    end
    
    # Sends a JSON-RPC request and returns its result. The server answers a
    # JSON-RPC error with HTTP status 200, so the method checks the reply for
    # an error member as well as the HTTP status.
    def rpc(http, method, params)
      response = post(http, TOKEN, { jsonrpc: "2.0", id: 1, method: method, params: params })
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
    
    # Posts a JSON-RPC message to the MCP endpoint with a token, and prints the
    # reply followed by the HTTP status on a line of its own: post TOKEN BODY.
    # The token goes to curl in a header file that bash supplies through a
    # pipe, so that it never appears in the arguments of the curl process, which
    # other users can read in the process list.
    post() {
        curl --silent --show-error \
            --connect-timeout 10 --max-time "$TIMEOUT_SECONDS" \
            --header @<(printf 'Authorization: Bearer %s\n' "$1") \
            --header 'Content-Type: application/json' \
            --write-out '\n%{http_code}' --data-binary "$2" "$MCP_URL/mcp/v1"
    }
    
    # Sends a JSON-RPC request and prints its result: rpc METHOD PARAMS_JSON.
    # The server answers a JSON-RPC error with HTTP status 200, so the function
    # checks the reply for an error member as well as the HTTP status.
    rpc() {
        local method="$1" request reply status body
        request=$(jq -nc --arg method "$method" --argjson params "$2" \
            '{jsonrpc: "2.0", id: 1, method: $method, params: $params}')
        reply=$(post "$MCP_TOKEN" "$request") || return 1
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

## Checking That the Server Is Running

The `/health` endpoint takes a `GET` request without a token, and replies with
a JSON object whose `status` is `ok` whilst the server runs. Each program
stops if the server does not answer, because the other steps cannot succeed
without it. The following tabs show the health check:

=== "Python"

    ```python
    def check_health(client: httpx.Client) -> None:
        """Checks that the server is running. The /health endpoint needs no
        token."""
        response = client.get("/health")
        if response.status_code != 200:
            raise McpError(f"Health check failed with HTTP "
                           f"{response.status_code}: {response.text[:200]}")
        try:
            status = response.json().get("status")
        except (ValueError, AttributeError):
            status = None
        if status != "ok":
            raise McpError(f"Unexpected response: {response.text[:200]}")
        print("Health: ok")
    ```

=== "TypeScript"

    ```typescript
    // Checks that the server is running. The /health endpoint needs no token.
    async function checkHealth(): Promise<void> {
      const response = await fetch(`${baseUrl}/health`, {
        signal: AbortSignal.timeout(timeoutMs),
      });
      const text = await response.text();
      if (response.status !== 200) {
        throw new Error(`Health check failed with HTTP ${response.status}: ${text.slice(0, 200)}`);
      }
      let status: unknown;
      try {
        status = JSON.parse(text)?.status;
      } catch {
        status = undefined;
      }
      if (status !== "ok") {
        throw new Error(`Unexpected response: ${text.slice(0, 200)}`);
      }
      console.log("Health: ok");
    }
    ```

=== "Java"

    ```java
    /** Checks that the server is running. The /health endpoint needs no token. */
    static void checkHealth() throws IOException, InterruptedException, McpException {
        HttpRequest request = HttpRequest.newBuilder(URI.create(BASE_URL + "/health"))
                .timeout(TIMEOUT)
                .GET()
                .build();
        HttpResponse<String> response = send(request);
        if (response.statusCode() != 200) {
            throw new McpException("Health check failed with HTTP "
                    + response.statusCode() + ": " + shorten(response.body()));
        }
        JsonNode body = parseObject(response.body());
        if (body == null || !"ok".equals(body.path("status").asString(""))) {
            throw new McpException("Unexpected response: " + shorten(response.body()));
        }
        System.out.println("Health: ok");
    }
    ```

=== "C#"

    ```csharp
    // Checks that the server is running. The /health endpoint needs no token.
    static async Task CheckHealthAsync(HttpClient client)
    {
        using var response = await client.GetAsync(BaseUrl() + "/health");
        var body = await response.Content.ReadAsStringAsync();
        if (response.StatusCode != HttpStatusCode.OK)
        {
            throw new McpException(
                $"Health check failed with HTTP {(int)response.StatusCode}: {Shorten(body)}");
        }
        if (ParseObject(body)?["status"] is not JsonValue status ||
            status.ToString() != "ok")
        {
            throw new McpException($"Unexpected response: {Shorten(body)}");
        }
        Console.WriteLine("Health: ok");
    }
    ```

=== "Go"

    ```go
    // checkHealth checks that the server is running. The /health endpoint
    // needs no token.
    func checkHealth(client *http.Client) error {
    	response, err := client.Get(baseURL + "/health")
    	if err != nil {
    		return err
    	}
    	defer response.Body.Close()
    	body, err := io.ReadAll(response.Body)
    	if err != nil {
    		return err
    	}
    	if response.StatusCode != http.StatusOK {
    		return fmt.Errorf("health check failed with HTTP %d: %s", response.StatusCode, shorten(body))
    	}
    	var health struct {
    		Status string `json:"status"`
    	}
    	if err := json.Unmarshal(body, &health); err != nil || health.Status != "ok" {
    		return fmt.Errorf("unexpected response: %s", shorten(body))
    	}
    	fmt.Println("Health: ok")
    	return nil
    }
    
    ```

=== "Rust"

    ```rust
    /// Checks that the server is running. The /health endpoint needs no token.
    fn check_health(client: &Client) -> Result<(), BoxError> {
        let response = client.get(format!("{}/health", base_url())).send()?;
        let status = response.status().as_u16();
        let body = response.text()?;
        if status != 200 {
            return Err(format!("Health check failed with HTTP {status}: {}", shorten(&body)).into());
        }
        let health: Value = serde_json::from_str(&body).unwrap_or(Value::Null);
        if health["status"].as_str() != Some("ok") {
            return Err(format!("Unexpected response: {}", shorten(&body)).into());
        }
        println!("Health: ok");
        Ok(())
    }
    ```

=== "Ruby"

    ```ruby
    # Checks that the server is running. The /health endpoint needs no token.
    def check_health(http)
      response = http.request(Net::HTTP::Get.new(URI("#{BASE_URL}/health")))
      unless response.code == "200"
        raise McpError, "Health check failed with HTTP #{response.code}: #{response.body.to_s[0, 200]}"
      end
      unless parse_object(response.body)&.fetch("status", nil) == "ok"
        raise McpError, "Unexpected response: #{response.body.to_s[0, 200]}"
      end
    
      puts "Health: ok"
    end
    ```

=== "curl"

    ```bash
    # Checks that the server is running. The /health endpoint needs no token.
    check_health() {
        local body
        body=$(curl --silent --show-error --fail-with-body \
            --connect-timeout 10 --max-time "$TIMEOUT_SECONDS" \
            "$MCP_URL/health") || {
            echo "Health check failed: $body" >&2
            return 1
        }
        jq -er 'if .status == "ok" then "Health: ok"
                else error("status is not ok") end' <<<"$body" 2>/dev/null || {
            echo "Unexpected response: ${body:0:200}" >&2
            return 1
        }
    }
    ```

## Introducing the Client

An MCP client starts a session with the `initialize` method, which gives the
protocol revision that the client wants, the client's capabilities, and its
name and version. The server replies with its own name and version and the
revision that it has chosen; version 1.1.0 supports the revisions `2024-11-05`,
`2025-03-26`, `2025-06-18` and `2025-11-25`, and answers a revision that it
does not know with one that it does, so a client must check the answer. The
client then sends the `notifications/initialized` notification, which has no
`id`, and the server replies with HTTP 202 and no body. The following tabs show
the handshake:

=== "Python"

    ```python
    def initialize(client: httpx.Client) -> None:
        """Introduces the client to the server, and prints the server's name and
        version and the protocol revision that the server chose.
    
        The server accepts 2024-11-05, 2025-03-26, 2025-06-18 and 2025-11-25,
        and answers a revision it does not know with one that it does, so the
        client checks the answer. The notifications/initialized message then
        completes the handshake; it is a notification, with no id, so the
        server replies with HTTP 202 and no body.
        """
        result = rpc(client, "initialize", {
            "protocolVersion": "2025-06-18",
            "capabilities": {},
            "clientInfo": {"name": "cookbook", "version": "1.0.0"},
        })
        info = result["serverInfo"]
        print(f"Server: {info['name']} {info['version']}")
        protocol = result.get("protocolVersion")
        if protocol != "2025-06-18":
            raise McpError(f"The server chose protocol version {protocol}")
        print(f"Protocol version: {protocol}")
    
        response = post(client, TOKEN, {
            "jsonrpc": "2.0", "method": "notifications/initialized",
        })
        if response.status_code != 202:
            raise McpError(f"notifications/initialized failed with HTTP "
                           f"{response.status_code}: {response.text[:200]}")
    ```

=== "TypeScript"

    ```typescript
    // Introduces the client to the server, and prints the server's name and
    // version and the protocol revision that the server chose. The server
    // accepts 2024-11-05, 2025-03-26, 2025-06-18 and 2025-11-25, and answers a
    // revision it does not know with one that it does, so the client checks
    // the answer. The notifications/initialized message then completes the
    // handshake; it is a notification, with no id, so the server replies with
    // HTTP 202 and no body.
    async function initialize(): Promise<void> {
      const result = await rpc("initialize", {
        protocolVersion: "2025-06-18",
        capabilities: {},
        clientInfo: { name: "cookbook", version: "1.0.0" },
      });
      const info = result?.serverInfo;
      if (typeof info?.name !== "string" || typeof info?.version !== "string") {
        throw new Error(`Unexpected result: ${JSON.stringify(result)}`);
      }
      console.log(`Server: ${info.name} ${info.version}`);
      const protocol = result.protocolVersion;
      if (protocol !== "2025-06-18") {
        throw new Error(`The server chose protocol version ${protocol}`);
      }
      console.log(`Protocol version: ${protocol}`);
    
      const response = await post(token, {
        jsonrpc: "2.0",
        method: "notifications/initialized",
      });
      const text = await response.text();
      if (response.status !== 202) {
        throw new Error(
          `notifications/initialized failed with HTTP ${response.status}: ${text.slice(0, 200)}`,
        );
      }
    }
    ```

=== "Java"

    ```java
    /**
     * Introduces the client to the server, and prints the server's name and
     * version and the protocol revision that the server chose. The server
     * accepts 2024-11-05, 2025-03-26, 2025-06-18 and 2025-11-25, and answers
     * a revision it does not know with one that it does, so the client
     * checks the answer. The notifications/initialized message then
     * completes the handshake; it is a notification, with no id, so the
     * server replies with HTTP 202 and no body.
     */
    static void initialize() throws IOException, InterruptedException, McpException {
        JsonNode result = rpc("initialize", Map.of(
                "protocolVersion", "2025-06-18",
                "capabilities", Map.of(),
                "clientInfo", Map.of("name", "cookbook", "version", "1.0.0")));
        JsonNode info = result.path("serverInfo");
        if (!info.path("name").isString() || !info.path("version").isString()) {
            throw new McpException("Unexpected result: " + result);
        }
        System.out.println("Server: " + info.path("name").stringValue()
                + " " + info.path("version").stringValue());
        String protocol = result.path("protocolVersion").asString("");
        if (!protocol.equals("2025-06-18")) {
            throw new McpException("The server chose protocol version " + protocol);
        }
        System.out.println("Protocol version: " + protocol);
    
        HttpResponse<String> response = post(TOKEN, Map.of(
                "jsonrpc", "2.0", "method", "notifications/initialized"));
        if (response.statusCode() != 202) {
            throw new McpException("notifications/initialized failed with HTTP "
                    + response.statusCode() + ": " + shorten(response.body()));
        }
    }
    ```

=== "C#"

    ```csharp
    // Introduces the client to the server, and prints the server's name and
    // version and the protocol revision that the server chose. The server
    // accepts 2024-11-05, 2025-03-26, 2025-06-18 and 2025-11-25, and answers a
    // revision it does not know with one that it does, so the client checks
    // the answer. The notifications/initialized message then completes the
    // handshake; it is a notification, with no id, so the server replies with
    // HTTP 202 and no body.
    static async Task InitializeAsync(HttpClient client)
    {
        var result = await RpcAsync(client, "initialize", new JsonObject
        {
            ["protocolVersion"] = "2025-06-18",
            ["capabilities"] = new JsonObject(),
            ["clientInfo"] = new JsonObject { ["name"] = "cookbook", ["version"] = "1.0.0" },
        });
        if (result["serverInfo"]?["name"] is not JsonValue name ||
            result["serverInfo"]?["version"] is not JsonValue version)
        {
            throw new McpException($"Unexpected result: {result.ToJsonString()}");
        }
        Console.WriteLine($"Server: {name} {version}");
        var protocol = result["protocolVersion"]?.ToString();
        if (protocol != "2025-06-18")
        {
            throw new McpException($"The server chose protocol version {protocol}");
        }
        Console.WriteLine($"Protocol version: {protocol}");
    
        var (status, body) = await PostAsync(client, Token(), new JsonObject
        {
            ["jsonrpc"] = "2.0",
            ["method"] = "notifications/initialized",
        });
        if (status != HttpStatusCode.Accepted)
        {
            throw new McpException(
                $"notifications/initialized failed with HTTP {(int)status}: {Shorten(body)}");
        }
    }
    ```

=== "Go"

    ```go
    // initialize introduces the client to the server, and prints the server's
    // name and version and the protocol revision that the server chose. The
    // server accepts 2024-11-05, 2025-03-26, 2025-06-18 and 2025-11-25, and
    // answers a revision it does not know with one that it does, so the client
    // checks the answer. The notifications/initialized message then completes
    // the handshake; it is a notification, with no id, so the server replies
    // with HTTP 202 and no body.
    func initialize(client *http.Client) error {
    	var result struct {
    		ProtocolVersion string `json:"protocolVersion"`
    		ServerInfo      *struct {
    			Name    string `json:"name"`
    			Version string `json:"version"`
    		} `json:"serverInfo"`
    	}
    	err := rpc(client, "initialize", map[string]any{
    		"protocolVersion": "2025-06-18",
    		"capabilities":    map[string]any{},
    		"clientInfo":      map[string]string{"name": "cookbook", "version": "1.0.0"},
    	}, &result)
    	if err != nil {
    		return err
    	}
    	if result.ServerInfo == nil {
    		return errors.New("initialize failed: the result has no serverInfo")
    	}
    	fmt.Printf("Server: %s %s\n", result.ServerInfo.Name, result.ServerInfo.Version)
    	if result.ProtocolVersion != "2025-06-18" {
    		return fmt.Errorf("the server chose protocol version %s", result.ProtocolVersion)
    	}
    	fmt.Printf("Protocol version: %s\n", result.ProtocolVersion)
    
    	status, body, err := post(client, token, map[string]any{
    		"jsonrpc": "2.0", "method": "notifications/initialized",
    	})
    	if err != nil {
    		return err
    	}
    	if status != http.StatusAccepted {
    		return fmt.Errorf("notifications/initialized failed with HTTP %d: %s", status, shorten(body))
    	}
    	return nil
    }
    
    ```

=== "Rust"

    ```rust
    /// Introduces the client to the server, and prints the server's name and
    /// version and the protocol revision that the server chose. The server
    /// accepts 2024-11-05, 2025-03-26, 2025-06-18 and 2025-11-25, and answers a
    /// revision it does not know with one that it does, so the client checks
    /// the answer. The notifications/initialized message then completes the
    /// handshake; it is a notification, with no id, so the server replies with
    /// HTTP 202 and no body.
    fn initialize(client: &Client) -> Result<(), BoxError> {
        let result = rpc(
            client,
            "initialize",
            json!({
                "protocolVersion": "2025-06-18",
                "capabilities": {},
                "clientInfo": {"name": "cookbook", "version": "1.0.0"},
            }),
        )?;
        let info = &result["serverInfo"];
        let (Some(name), Some(version)) = (info["name"].as_str(), info["version"].as_str()) else {
            return Err(format!("Unexpected result: {result}").into());
        };
        println!("Server: {name} {version}");
        let protocol = result["protocolVersion"].as_str().unwrap_or("");
        if protocol != "2025-06-18" {
            return Err(format!("The server chose protocol version {protocol}").into());
        }
        println!("Protocol version: {protocol}");
    
        let message = json!({"jsonrpc": "2.0", "method": "notifications/initialized"});
        let (status, body) = post(client, &token(), &message)?;
        if status != 202 {
            return Err(format!(
                "notifications/initialized failed with HTTP {status}: {}",
                shorten(&body)
            )
            .into());
        }
        Ok(())
    }
    ```

=== "Ruby"

    ```ruby
    # Introduces the client to the server, and prints the server's name and
    # version and the protocol revision that the server chose. The server
    # accepts 2024-11-05, 2025-03-26, 2025-06-18 and 2025-11-25, and answers a
    # revision it does not know with one that it does, so the client checks
    # the answer. The notifications/initialized message then completes the
    # handshake; it is a notification, with no id, so the server replies with
    # HTTP 202 and no body.
    def initialize_session(http)
      result = rpc(http, "initialize", {
                     protocolVersion: "2025-06-18",
                     capabilities: {},
                     clientInfo: { name: "cookbook", version: "1.0.0" }
                   })
      info = result.is_a?(Hash) ? result["serverInfo"] : nil
      unless info.is_a?(Hash) && info["name"].is_a?(String) && info["version"].is_a?(String)
        raise McpError, "Unexpected result: #{result}"
      end
    
      puts "Server: #{info["name"]} #{info["version"]}"
      protocol = result["protocolVersion"]
      raise McpError, "The server chose protocol version #{protocol}" unless protocol == "2025-06-18"
    
      puts "Protocol version: #{protocol}"
    
      response = post(http, TOKEN, { jsonrpc: "2.0", method: "notifications/initialized" })
      return if response.code == "202"
    
      raise McpError, "notifications/initialized failed with HTTP #{response.code}: " \
                      "#{response.body.to_s[0, 200]}"
    end
    ```

=== "curl"

    ```bash
    # Introduces the client to the server, and prints the server's name and
    # version and the protocol revision that the server chose. The server
    # accepts 2024-11-05, 2025-03-26, 2025-06-18 and 2025-11-25, and answers a
    # revision it does not know with one that it does, so the client checks
    # the answer. The notifications/initialized message then completes the
    # handshake; it is a notification, with no id, so the server replies with
    # HTTP 202 and no body.
    initialize() {
        local result protocol reply
        result=$(rpc initialize '{
            "protocolVersion": "2025-06-18",
            "capabilities": {},
            "clientInfo": {"name": "cookbook", "version": "1.0.0"}
        }') || return 1
        jq -r '"Server: \(.serverInfo.name) \(.serverInfo.version)"' <<<"$result"
        protocol=$(jq -r '.protocolVersion' <<<"$result")
        if [[ "$protocol" != "2025-06-18" ]]; then
            echo "The server chose protocol version $protocol" >&2
            return 1
        fi
        echo "Protocol version: $protocol"
    
        reply=$(post "$MCP_TOKEN" \
            '{"jsonrpc": "2.0", "method": "notifications/initialized"}') || return 1
        if [[ "${reply##*$'\n'}" != 202 ]]; then
            echo "notifications/initialized failed: ${reply:0:200}" >&2
            return 1
        fi
    }
    ```

## Sending a Wrong Token

The server rejects a token that it does not know with HTTP 401 and a JSON
object with an `error` member, which is not a JSON-RPC reply. Each program
sends a made-up token, and stops if the server does not reject it. The
following tabs show the request:

=== "Python"

    ```python
    def wrong_token(client: httpx.Client) -> None:
        """Sends a request with a token that the server does not know, and
        prints the HTTP status and the server's message, which is a JSON object
        with an error member rather than a JSON-RPC reply."""
        response = post(client, "not-a-real-token", {
            "jsonrpc": "2.0", "id": 1, "method": "tools/list", "params": {},
        })
        if response.status_code != 401:
            raise McpError(f"Expected HTTP 401 for a wrong token, but got "
                           f"{response.status_code}")
        try:
            message = response.json().get("error") or "no message"
        except (ValueError, AttributeError):
            message = "no message"
        print(f"Wrong token: HTTP {response.status_code}, {message}")
    ```

=== "TypeScript"

    ```typescript
    // Sends a request with a token that the server does not know, and prints
    // the HTTP status and the server's message, which is a JSON object with an
    // error member rather than a JSON-RPC reply.
    async function wrongToken(): Promise<void> {
      const response = await post("not-a-real-token", {
        jsonrpc: "2.0",
        id: 1,
        method: "tools/list",
        params: {},
      });
      const text = await response.text();
      if (response.status !== 401) {
        throw new Error(`Expected HTTP 401 for a wrong token, but got ${response.status}`);
      }
      let message = "no message";
      try {
        message = JSON.parse(text)?.error || message;
      } catch {
        // The body is not JSON; keep the default message.
      }
      console.log(`Wrong token: HTTP ${response.status}, ${message}`);
    }
    ```

=== "Java"

    ```java
    /**
     * Sends a request with a token that the server does not know, and
     * prints the HTTP status and the server's message, which is a JSON
     * object with an error member rather than a JSON-RPC reply.
     */
    static void wrongToken() throws IOException, InterruptedException, McpException {
        HttpResponse<String> response = post("not-a-real-token", Map.of(
                "jsonrpc", "2.0", "id", 1, "method", "tools/list",
                "params", Map.of()));
        if (response.statusCode() != 401) {
            throw new McpException("Expected HTTP 401 for a wrong token, but got "
                    + response.statusCode());
        }
        JsonNode body = parseObject(response.body());
        String message = body == null ? "" : body.path("error").asString("");
        if (message.isEmpty()) {
            message = "no message";
        }
        System.out.println("Wrong token: HTTP " + response.statusCode() + ", " + message);
    }
    ```

=== "C#"

    ```csharp
    // Sends a request with a token that the server does not know, and prints
    // the HTTP status and the server's message, which is a JSON object with an
    // error member rather than a JSON-RPC reply.
    static async Task WrongTokenAsync(HttpClient client)
    {
        var (status, body) = await PostAsync(client, "not-a-real-token", new JsonObject
        {
            ["jsonrpc"] = "2.0",
            ["id"] = 1,
            ["method"] = "tools/list",
            ["params"] = new JsonObject(),
        });
        if (status != HttpStatusCode.Unauthorized)
        {
            throw new McpException(
                $"Expected HTTP 401 for a wrong token, but got {(int)status}");
        }
        var message = ParseObject(body)?["error"]?.ToString();
        if (string.IsNullOrEmpty(message))
        {
            message = "no message";
        }
        Console.WriteLine($"Wrong token: HTTP {(int)status}, {message}");
    }
    ```

=== "Go"

    ```go
    // wrongToken sends a request with a token that the server does not know,
    // and prints the HTTP status and the server's message, which is a JSON
    // object with an error member rather than a JSON-RPC reply.
    func wrongToken(client *http.Client) error {
    	status, body, err := post(client, "not-a-real-token", map[string]any{
    		"jsonrpc": "2.0", "id": 1, "method": "tools/list", "params": map[string]any{},
    	})
    	if err != nil {
    		return err
    	}
    	if status != http.StatusUnauthorized {
    		return fmt.Errorf("expected HTTP 401 for a wrong token, but got %d", status)
    	}
    	var reply struct {
    		Error string `json:"error"`
    	}
    	message := "no message"
    	if json.Unmarshal(body, &reply) == nil && reply.Error != "" {
    		message = reply.Error
    	}
    	fmt.Printf("Wrong token: HTTP %d, %s\n", status, message)
    	return nil
    }
    
    ```

=== "Rust"

    ```rust
    /// Sends a request with a token that the server does not know, and prints
    /// the HTTP status and the server's message, which is a JSON object with
    /// an error member rather than a JSON-RPC reply.
    fn wrong_token(client: &Client) -> Result<(), BoxError> {
        let message = json!({"jsonrpc": "2.0", "id": 1, "method": "tools/list", "params": {}});
        let (status, body) = post(client, "not-a-real-token", &message)?;
        if status != 401 {
            return Err(format!("Expected HTTP 401 for a wrong token, but got {status}").into());
        }
        let reply: Value = serde_json::from_str(&body).unwrap_or(Value::Null);
        let message = match reply["error"].as_str() {
            Some(text) if !text.is_empty() => text,
            _ => "no message",
        };
        println!("Wrong token: HTTP {status}, {message}");
        Ok(())
    }
    ```

=== "Ruby"

    ```ruby
    # Sends a request with a token that the server does not know, and prints
    # the HTTP status and the server's message, which is a JSON object with an
    # error member rather than a JSON-RPC reply.
    def wrong_token(http)
      response = post(http, "not-a-real-token",
                      { jsonrpc: "2.0", id: 1, method: "tools/list", params: {} })
      unless response.code == "401"
        raise McpError, "Expected HTTP 401 for a wrong token, but got #{response.code}"
      end
    
      message = parse_object(response.body)&.fetch("error", nil)
      message = "no message" if message.nil? || message.to_s.empty?
      puts "Wrong token: HTTP #{response.code}, #{message}"
    end
    ```

=== "curl"

    ```bash
    # Sends a request with a token that the server does not know, and prints
    # the HTTP status and the server's message, which is a JSON object with an
    # error member rather than a JSON-RPC reply.
    wrong_token() {
        local reply status body
        reply=$(post "not-a-real-token" \
            '{"jsonrpc": "2.0", "id": 1, "method": "tools/list", "params": {}}') \
            || return 1
        status="${reply##*$'\n'}"
        body="${reply%$'\n'*}"
        if [[ "$status" != 401 ]]; then
            echo "Expected HTTP 401 for a wrong token, but got $status" >&2
            return 1
        fi
        echo "Wrong token: HTTP $status, $(jq -r '.error // "no message"' <<<"$body")"
    }
    ```

## Handling Errors

The main part of each program checks that a token is set, runs the three steps,
reports any failure on `stderr`, and exits with a non-zero status, so that a
script can act on the result. The following tabs show the main part of each
program:

=== "Python"

    ```python
    def main() -> int:
        if not TOKEN:
            print("MCP_TOKEN must be set", file=sys.stderr)
            return 1
        try:
            with httpx.Client(base_url=BASE_URL, timeout=TIMEOUT_SECONDS) as client:
                check_health(client)
                initialize(client)
                wrong_token(client)
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
        await checkHealth();
        await initialize();
        await wrongToken();
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
            checkHealth();
            initialize();
            wrongToken();
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
        await CheckHealthAsync(client);
        await InitializeAsync(client);
        await WrongTokenAsync(client);
    }
    // HttpRequestException covers failures to reach the server, such as a
    // refused connection, and TaskCanceledException covers a timeout.
    catch (Exception e) when (
        e is HttpRequestException or TaskCanceledException or McpException)
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
    // run makes the three checks and returns any error to the caller.
    func run() error {
    	if token == "" {
    		return errors.New("MCP_TOKEN must be set")
    	}
    	client := &http.Client{Timeout: timeout}
    	if err := checkHealth(client); err != nil {
    		return err
    	}
    	if err := initialize(client); err != nil {
    		return err
    	}
    	return wrongToken(client)
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
    /// Makes the three checks. The ? operator returns any error to the
    /// caller.
    fn run() -> Result<(), BoxError> {
        if token().is_empty() {
            return Err("MCP_TOKEN must be set".into());
        }
        let client = Client::builder().timeout(TIMEOUT).build()?;
        check_health(&client)?;
        initialize(&client)?;
        wrong_token(&client)
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
        check_health(http)
        initialize_session(http)
        wrong_token(http)
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
        check_health
        initialize
        wrong_token
    }
    
    main
    ```

## Running the Example

The complete project for each language is available in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/postgres_mcp/connect).
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
    Connecting to the pgEdge Postgres MCP Server, using httpx.
    
    These examples are for pgEdge Postgres MCP Server 1.1.0.
    
    Copyright (c) 2026, pgEdge, Inc.
    This code is released under the PostgreSQL License.
    """
    
    import os
    import sys
    
    import httpx
    
    
    # The or operator treats an empty variable as unset.
    BASE_URL = (os.environ.get("MCP_URL") or "http://localhost:8080").rstrip("/")
    TOKEN = os.environ.get("MCP_TOKEN") or ""
    
    TIMEOUT_SECONDS = 30
    
    
    class McpError(Exception):
        """Raised when the MCP Server rejects a request or replies oddly."""
    
    
    def post(client: httpx.Client, token: str, message: dict) -> httpx.Response:
        """Posts a JSON-RPC message to the MCP endpoint with a token."""
        return client.post(
            "/mcp/v1", json=message,
            headers={"Authorization": f"Bearer {token}"},
        )
    
    
    def rpc(client: httpx.Client, method: str, params: dict) -> dict:
        """Sends a JSON-RPC request and returns its result.
    
        The server answers a JSON-RPC error with HTTP status 200, so the
        function checks the reply for an error member as well as the HTTP
        status.
        """
        response = post(client, TOKEN, {
            "jsonrpc": "2.0", "id": 1, "method": method, "params": params,
        })
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
    
    
    def check_health(client: httpx.Client) -> None:
        """Checks that the server is running. The /health endpoint needs no
        token."""
        response = client.get("/health")
        if response.status_code != 200:
            raise McpError(f"Health check failed with HTTP "
                           f"{response.status_code}: {response.text[:200]}")
        try:
            status = response.json().get("status")
        except (ValueError, AttributeError):
            status = None
        if status != "ok":
            raise McpError(f"Unexpected response: {response.text[:200]}")
        print("Health: ok")
    
    
    def initialize(client: httpx.Client) -> None:
        """Introduces the client to the server, and prints the server's name and
        version and the protocol revision that the server chose.
    
        The server accepts 2024-11-05, 2025-03-26, 2025-06-18 and 2025-11-25,
        and answers a revision it does not know with one that it does, so the
        client checks the answer. The notifications/initialized message then
        completes the handshake; it is a notification, with no id, so the
        server replies with HTTP 202 and no body.
        """
        result = rpc(client, "initialize", {
            "protocolVersion": "2025-06-18",
            "capabilities": {},
            "clientInfo": {"name": "cookbook", "version": "1.0.0"},
        })
        info = result["serverInfo"]
        print(f"Server: {info['name']} {info['version']}")
        protocol = result.get("protocolVersion")
        if protocol != "2025-06-18":
            raise McpError(f"The server chose protocol version {protocol}")
        print(f"Protocol version: {protocol}")
    
        response = post(client, TOKEN, {
            "jsonrpc": "2.0", "method": "notifications/initialized",
        })
        if response.status_code != 202:
            raise McpError(f"notifications/initialized failed with HTTP "
                           f"{response.status_code}: {response.text[:200]}")
    
    
    def wrong_token(client: httpx.Client) -> None:
        """Sends a request with a token that the server does not know, and
        prints the HTTP status and the server's message, which is a JSON object
        with an error member rather than a JSON-RPC reply."""
        response = post(client, "not-a-real-token", {
            "jsonrpc": "2.0", "id": 1, "method": "tools/list", "params": {},
        })
        if response.status_code != 401:
            raise McpError(f"Expected HTTP 401 for a wrong token, but got "
                           f"{response.status_code}")
        try:
            message = response.json().get("error") or "no message"
        except (ValueError, AttributeError):
            message = "no message"
        print(f"Wrong token: HTTP {response.status_code}, {message}")
    
    
    def main() -> int:
        if not TOKEN:
            print("MCP_TOKEN must be set", file=sys.stderr)
            return 1
        try:
            with httpx.Client(base_url=BASE_URL, timeout=TIMEOUT_SECONDS) as client:
                check_health(client)
                initialize(client)
                wrong_token(client)
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
     * Connecting to the pgEdge Postgres MCP Server, using the built-in fetch.
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
    
    // Posts a JSON-RPC message to the MCP endpoint with a token.
    async function post(withToken: string, message: object): Promise<Response> {
      return fetch(`${baseUrl}/mcp/v1`, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${withToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify(message),
        signal: AbortSignal.timeout(timeoutMs),
      });
    }
    
    // Sends a JSON-RPC request and returns its result. The server answers a
    // JSON-RPC error with HTTP status 200, so the function checks the reply
    // for an error member as well as the HTTP status.
    async function rpc(method: string, params: object): Promise<any> {
      const response = await post(token, { jsonrpc: "2.0", id: 1, method, params });
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
    
    // Checks that the server is running. The /health endpoint needs no token.
    async function checkHealth(): Promise<void> {
      const response = await fetch(`${baseUrl}/health`, {
        signal: AbortSignal.timeout(timeoutMs),
      });
      const text = await response.text();
      if (response.status !== 200) {
        throw new Error(`Health check failed with HTTP ${response.status}: ${text.slice(0, 200)}`);
      }
      let status: unknown;
      try {
        status = JSON.parse(text)?.status;
      } catch {
        status = undefined;
      }
      if (status !== "ok") {
        throw new Error(`Unexpected response: ${text.slice(0, 200)}`);
      }
      console.log("Health: ok");
    }
    
    // Introduces the client to the server, and prints the server's name and
    // version and the protocol revision that the server chose. The server
    // accepts 2024-11-05, 2025-03-26, 2025-06-18 and 2025-11-25, and answers a
    // revision it does not know with one that it does, so the client checks
    // the answer. The notifications/initialized message then completes the
    // handshake; it is a notification, with no id, so the server replies with
    // HTTP 202 and no body.
    async function initialize(): Promise<void> {
      const result = await rpc("initialize", {
        protocolVersion: "2025-06-18",
        capabilities: {},
        clientInfo: { name: "cookbook", version: "1.0.0" },
      });
      const info = result?.serverInfo;
      if (typeof info?.name !== "string" || typeof info?.version !== "string") {
        throw new Error(`Unexpected result: ${JSON.stringify(result)}`);
      }
      console.log(`Server: ${info.name} ${info.version}`);
      const protocol = result.protocolVersion;
      if (protocol !== "2025-06-18") {
        throw new Error(`The server chose protocol version ${protocol}`);
      }
      console.log(`Protocol version: ${protocol}`);
    
      const response = await post(token, {
        jsonrpc: "2.0",
        method: "notifications/initialized",
      });
      const text = await response.text();
      if (response.status !== 202) {
        throw new Error(
          `notifications/initialized failed with HTTP ${response.status}: ${text.slice(0, 200)}`,
        );
      }
    }
    
    // Sends a request with a token that the server does not know, and prints
    // the HTTP status and the server's message, which is a JSON object with an
    // error member rather than a JSON-RPC reply.
    async function wrongToken(): Promise<void> {
      const response = await post("not-a-real-token", {
        jsonrpc: "2.0",
        id: 1,
        method: "tools/list",
        params: {},
      });
      const text = await response.text();
      if (response.status !== 401) {
        throw new Error(`Expected HTTP 401 for a wrong token, but got ${response.status}`);
      }
      let message = "no message";
      try {
        message = JSON.parse(text)?.error || message;
      } catch {
        // The body is not JSON; keep the default message.
      }
      console.log(`Wrong token: HTTP ${response.status}, ${message}`);
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
        await checkHealth();
        await initialize();
        await wrongToken();
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
     * Connecting to the pgEdge Postgres MCP Server, using java.net.http and
     * Jackson.
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
    
        /** Posts a JSON-RPC message to the MCP endpoint with a token. */
        static HttpResponse<String> post(String token, Map<String, Object> message)
                throws IOException, InterruptedException {
            HttpRequest request = HttpRequest.newBuilder(URI.create(BASE_URL + "/mcp/v1"))
                    .timeout(TIMEOUT)
                    .header("Authorization", "Bearer " + token)
                    .header("Content-Type", "application/json")
                    .POST(HttpRequest.BodyPublishers.ofString(
                            MAPPER.writeValueAsString(message)))
                    .build();
            return send(request);
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
            HttpResponse<String> response = post(TOKEN, Map.of(
                    "jsonrpc", "2.0", "id", 1, "method", method, "params", params));
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
    
        /** Checks that the server is running. The /health endpoint needs no token. */
        static void checkHealth() throws IOException, InterruptedException, McpException {
            HttpRequest request = HttpRequest.newBuilder(URI.create(BASE_URL + "/health"))
                    .timeout(TIMEOUT)
                    .GET()
                    .build();
            HttpResponse<String> response = send(request);
            if (response.statusCode() != 200) {
                throw new McpException("Health check failed with HTTP "
                        + response.statusCode() + ": " + shorten(response.body()));
            }
            JsonNode body = parseObject(response.body());
            if (body == null || !"ok".equals(body.path("status").asString(""))) {
                throw new McpException("Unexpected response: " + shorten(response.body()));
            }
            System.out.println("Health: ok");
        }
    
        /**
         * Introduces the client to the server, and prints the server's name and
         * version and the protocol revision that the server chose. The server
         * accepts 2024-11-05, 2025-03-26, 2025-06-18 and 2025-11-25, and answers
         * a revision it does not know with one that it does, so the client
         * checks the answer. The notifications/initialized message then
         * completes the handshake; it is a notification, with no id, so the
         * server replies with HTTP 202 and no body.
         */
        static void initialize() throws IOException, InterruptedException, McpException {
            JsonNode result = rpc("initialize", Map.of(
                    "protocolVersion", "2025-06-18",
                    "capabilities", Map.of(),
                    "clientInfo", Map.of("name", "cookbook", "version", "1.0.0")));
            JsonNode info = result.path("serverInfo");
            if (!info.path("name").isString() || !info.path("version").isString()) {
                throw new McpException("Unexpected result: " + result);
            }
            System.out.println("Server: " + info.path("name").stringValue()
                    + " " + info.path("version").stringValue());
            String protocol = result.path("protocolVersion").asString("");
            if (!protocol.equals("2025-06-18")) {
                throw new McpException("The server chose protocol version " + protocol);
            }
            System.out.println("Protocol version: " + protocol);
    
            HttpResponse<String> response = post(TOKEN, Map.of(
                    "jsonrpc", "2.0", "method", "notifications/initialized"));
            if (response.statusCode() != 202) {
                throw new McpException("notifications/initialized failed with HTTP "
                        + response.statusCode() + ": " + shorten(response.body()));
            }
        }
    
        /**
         * Sends a request with a token that the server does not know, and
         * prints the HTTP status and the server's message, which is a JSON
         * object with an error member rather than a JSON-RPC reply.
         */
        static void wrongToken() throws IOException, InterruptedException, McpException {
            HttpResponse<String> response = post("not-a-real-token", Map.of(
                    "jsonrpc", "2.0", "id", 1, "method", "tools/list",
                    "params", Map.of()));
            if (response.statusCode() != 401) {
                throw new McpException("Expected HTTP 401 for a wrong token, but got "
                        + response.statusCode());
            }
            JsonNode body = parseObject(response.body());
            String message = body == null ? "" : body.path("error").asString("");
            if (message.isEmpty()) {
                message = "no message";
            }
            System.out.println("Wrong token: HTTP " + response.statusCode() + ", " + message);
        }
    
        public static void main(String[] args) {
            if (TOKEN.isEmpty()) {
                System.err.println("MCP_TOKEN must be set");
                System.exit(1);
            }
            try {
                checkHealth();
                initialize();
                wrongToken();
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
     * Connecting to the pgEdge Postgres MCP Server, using HttpClient and
     * System.Text.Json.
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
    
    // Posts a JSON-RPC message to the MCP endpoint with a token, and returns
    // the HTTP status and the body of the reply.
    static async Task<(HttpStatusCode Status, string Body)> PostAsync(
        HttpClient client, string token, JsonObject message)
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, BaseUrl() + "/mcp/v1")
        {
            Content = new StringContent(
                message.ToJsonString(), Encoding.UTF8, "application/json"),
        };
        request.Headers.Add("Authorization", $"Bearer {token}");
        using var response = await client.SendAsync(request);
        return (response.StatusCode, await response.Content.ReadAsStringAsync());
    }
    
    // Sends a JSON-RPC request and returns its result. The server answers a
    // JSON-RPC error with HTTP status 200, so the function checks the reply for
    // an error member as well as the HTTP status.
    static async Task<JsonNode> RpcAsync(HttpClient client, string method, JsonObject parameters)
    {
        var (status, body) = await PostAsync(client, Token(), new JsonObject
        {
            ["jsonrpc"] = "2.0",
            ["id"] = 1,
            ["method"] = method,
            ["params"] = parameters,
        });
        if (status != HttpStatusCode.OK)
        {
            throw new McpException(
                $"{method} failed with HTTP {(int)status}: {Shorten(body)}");
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
    
    // Checks that the server is running. The /health endpoint needs no token.
    static async Task CheckHealthAsync(HttpClient client)
    {
        using var response = await client.GetAsync(BaseUrl() + "/health");
        var body = await response.Content.ReadAsStringAsync();
        if (response.StatusCode != HttpStatusCode.OK)
        {
            throw new McpException(
                $"Health check failed with HTTP {(int)response.StatusCode}: {Shorten(body)}");
        }
        if (ParseObject(body)?["status"] is not JsonValue status ||
            status.ToString() != "ok")
        {
            throw new McpException($"Unexpected response: {Shorten(body)}");
        }
        Console.WriteLine("Health: ok");
    }
    
    // Introduces the client to the server, and prints the server's name and
    // version and the protocol revision that the server chose. The server
    // accepts 2024-11-05, 2025-03-26, 2025-06-18 and 2025-11-25, and answers a
    // revision it does not know with one that it does, so the client checks
    // the answer. The notifications/initialized message then completes the
    // handshake; it is a notification, with no id, so the server replies with
    // HTTP 202 and no body.
    static async Task InitializeAsync(HttpClient client)
    {
        var result = await RpcAsync(client, "initialize", new JsonObject
        {
            ["protocolVersion"] = "2025-06-18",
            ["capabilities"] = new JsonObject(),
            ["clientInfo"] = new JsonObject { ["name"] = "cookbook", ["version"] = "1.0.0" },
        });
        if (result["serverInfo"]?["name"] is not JsonValue name ||
            result["serverInfo"]?["version"] is not JsonValue version)
        {
            throw new McpException($"Unexpected result: {result.ToJsonString()}");
        }
        Console.WriteLine($"Server: {name} {version}");
        var protocol = result["protocolVersion"]?.ToString();
        if (protocol != "2025-06-18")
        {
            throw new McpException($"The server chose protocol version {protocol}");
        }
        Console.WriteLine($"Protocol version: {protocol}");
    
        var (status, body) = await PostAsync(client, Token(), new JsonObject
        {
            ["jsonrpc"] = "2.0",
            ["method"] = "notifications/initialized",
        });
        if (status != HttpStatusCode.Accepted)
        {
            throw new McpException(
                $"notifications/initialized failed with HTTP {(int)status}: {Shorten(body)}");
        }
    }
    
    // Sends a request with a token that the server does not know, and prints
    // the HTTP status and the server's message, which is a JSON object with an
    // error member rather than a JSON-RPC reply.
    static async Task WrongTokenAsync(HttpClient client)
    {
        var (status, body) = await PostAsync(client, "not-a-real-token", new JsonObject
        {
            ["jsonrpc"] = "2.0",
            ["id"] = 1,
            ["method"] = "tools/list",
            ["params"] = new JsonObject(),
        });
        if (status != HttpStatusCode.Unauthorized)
        {
            throw new McpException(
                $"Expected HTTP 401 for a wrong token, but got {(int)status}");
        }
        var message = ParseObject(body)?["error"]?.ToString();
        if (string.IsNullOrEmpty(message))
        {
            message = "no message";
        }
        Console.WriteLine($"Wrong token: HTTP {(int)status}, {message}");
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
        await CheckHealthAsync(client);
        await InitializeAsync(client);
        await WrongTokenAsync(client);
    }
    // HttpRequestException covers failures to reach the server, such as a
    // refused connection, and TaskCanceledException covers a timeout.
    catch (Exception e) when (
        e is HttpRequestException or TaskCanceledException or McpException)
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
    // Connecting to the pgEdge Postgres MCP Server, using net/http.
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
    
    // post sends a JSON-RPC message to the MCP endpoint with a token, and
    // returns the HTTP status and the body of the reply.
    func post(client *http.Client, withToken string, message any) (int, []byte, error) {
    	payload, err := json.Marshal(message)
    	if err != nil {
    		return 0, nil, err
    	}
    	request, err := http.NewRequest(http.MethodPost, baseURL+"/mcp/v1", bytes.NewReader(payload))
    	if err != nil {
    		return 0, nil, err
    	}
    	request.Header.Set("Authorization", "Bearer "+withToken)
    	request.Header.Set("Content-Type", "application/json")
    
    	response, err := client.Do(request)
    	if err != nil {
    		return 0, nil, err
    	}
    	defer response.Body.Close()
    	body, err := io.ReadAll(response.Body)
    	return response.StatusCode, body, err
    }
    
    // rpc sends a JSON-RPC request and decodes its result into out. The
    // server answers a JSON-RPC error with HTTP status 200, so the function
    // checks the reply for an error member as well as the HTTP status.
    func rpc(client *http.Client, method string, params any, out any) error {
    	status, body, err := post(client, token, map[string]any{
    		"jsonrpc": "2.0", "id": 1, "method": method, "params": params,
    	})
    	if err != nil {
    		return err
    	}
    	if status != http.StatusOK {
    		return fmt.Errorf("%s failed with HTTP %d: %s", method, status, shorten(body))
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
    
    
    // checkHealth checks that the server is running. The /health endpoint
    // needs no token.
    func checkHealth(client *http.Client) error {
    	response, err := client.Get(baseURL + "/health")
    	if err != nil {
    		return err
    	}
    	defer response.Body.Close()
    	body, err := io.ReadAll(response.Body)
    	if err != nil {
    		return err
    	}
    	if response.StatusCode != http.StatusOK {
    		return fmt.Errorf("health check failed with HTTP %d: %s", response.StatusCode, shorten(body))
    	}
    	var health struct {
    		Status string `json:"status"`
    	}
    	if err := json.Unmarshal(body, &health); err != nil || health.Status != "ok" {
    		return fmt.Errorf("unexpected response: %s", shorten(body))
    	}
    	fmt.Println("Health: ok")
    	return nil
    }
    
    
    // initialize introduces the client to the server, and prints the server's
    // name and version and the protocol revision that the server chose. The
    // server accepts 2024-11-05, 2025-03-26, 2025-06-18 and 2025-11-25, and
    // answers a revision it does not know with one that it does, so the client
    // checks the answer. The notifications/initialized message then completes
    // the handshake; it is a notification, with no id, so the server replies
    // with HTTP 202 and no body.
    func initialize(client *http.Client) error {
    	var result struct {
    		ProtocolVersion string `json:"protocolVersion"`
    		ServerInfo      *struct {
    			Name    string `json:"name"`
    			Version string `json:"version"`
    		} `json:"serverInfo"`
    	}
    	err := rpc(client, "initialize", map[string]any{
    		"protocolVersion": "2025-06-18",
    		"capabilities":    map[string]any{},
    		"clientInfo":      map[string]string{"name": "cookbook", "version": "1.0.0"},
    	}, &result)
    	if err != nil {
    		return err
    	}
    	if result.ServerInfo == nil {
    		return errors.New("initialize failed: the result has no serverInfo")
    	}
    	fmt.Printf("Server: %s %s\n", result.ServerInfo.Name, result.ServerInfo.Version)
    	if result.ProtocolVersion != "2025-06-18" {
    		return fmt.Errorf("the server chose protocol version %s", result.ProtocolVersion)
    	}
    	fmt.Printf("Protocol version: %s\n", result.ProtocolVersion)
    
    	status, body, err := post(client, token, map[string]any{
    		"jsonrpc": "2.0", "method": "notifications/initialized",
    	})
    	if err != nil {
    		return err
    	}
    	if status != http.StatusAccepted {
    		return fmt.Errorf("notifications/initialized failed with HTTP %d: %s", status, shorten(body))
    	}
    	return nil
    }
    
    
    // wrongToken sends a request with a token that the server does not know,
    // and prints the HTTP status and the server's message, which is a JSON
    // object with an error member rather than a JSON-RPC reply.
    func wrongToken(client *http.Client) error {
    	status, body, err := post(client, "not-a-real-token", map[string]any{
    		"jsonrpc": "2.0", "id": 1, "method": "tools/list", "params": map[string]any{},
    	})
    	if err != nil {
    		return err
    	}
    	if status != http.StatusUnauthorized {
    		return fmt.Errorf("expected HTTP 401 for a wrong token, but got %d", status)
    	}
    	var reply struct {
    		Error string `json:"error"`
    	}
    	message := "no message"
    	if json.Unmarshal(body, &reply) == nil && reply.Error != "" {
    		message = reply.Error
    	}
    	fmt.Printf("Wrong token: HTTP %d, %s\n", status, message)
    	return nil
    }
    
    
    // run makes the three checks and returns any error to the caller.
    func run() error {
    	if token == "" {
    		return errors.New("MCP_TOKEN must be set")
    	}
    	client := &http.Client{Timeout: timeout}
    	if err := checkHealth(client); err != nil {
    		return err
    	}
    	if err := initialize(client); err != nil {
    		return err
    	}
    	return wrongToken(client)
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
    // Connecting to the pgEdge Postgres MCP Server, using reqwest and
    // serde_json.
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
    
    /// Posts a JSON-RPC message to the MCP endpoint with a token, and returns
    /// the HTTP status and the body of the reply.
    fn post(client: &Client, with_token: &str, message: &Value) -> Result<(u16, String), BoxError> {
        let response = client
            .post(format!("{}/mcp/v1", base_url()))
            .bearer_auth(with_token)
            .json(message)
            .send()?;
        let status = response.status().as_u16();
        Ok((status, response.text()?))
    }
    
    /// Sends a JSON-RPC request and returns its result. The server answers a
    /// JSON-RPC error with HTTP status 200, so the function checks the reply
    /// for an error member as well as the HTTP status.
    fn rpc(client: &Client, method: &str, params: Value) -> Result<Value, BoxError> {
        let message = json!({"jsonrpc": "2.0", "id": 1, "method": method, "params": params});
        let (status, body) = post(client, &token(), &message)?;
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
    
    /// Checks that the server is running. The /health endpoint needs no token.
    fn check_health(client: &Client) -> Result<(), BoxError> {
        let response = client.get(format!("{}/health", base_url())).send()?;
        let status = response.status().as_u16();
        let body = response.text()?;
        if status != 200 {
            return Err(format!("Health check failed with HTTP {status}: {}", shorten(&body)).into());
        }
        let health: Value = serde_json::from_str(&body).unwrap_or(Value::Null);
        if health["status"].as_str() != Some("ok") {
            return Err(format!("Unexpected response: {}", shorten(&body)).into());
        }
        println!("Health: ok");
        Ok(())
    }
    
    /// Introduces the client to the server, and prints the server's name and
    /// version and the protocol revision that the server chose. The server
    /// accepts 2024-11-05, 2025-03-26, 2025-06-18 and 2025-11-25, and answers a
    /// revision it does not know with one that it does, so the client checks
    /// the answer. The notifications/initialized message then completes the
    /// handshake; it is a notification, with no id, so the server replies with
    /// HTTP 202 and no body.
    fn initialize(client: &Client) -> Result<(), BoxError> {
        let result = rpc(
            client,
            "initialize",
            json!({
                "protocolVersion": "2025-06-18",
                "capabilities": {},
                "clientInfo": {"name": "cookbook", "version": "1.0.0"},
            }),
        )?;
        let info = &result["serverInfo"];
        let (Some(name), Some(version)) = (info["name"].as_str(), info["version"].as_str()) else {
            return Err(format!("Unexpected result: {result}").into());
        };
        println!("Server: {name} {version}");
        let protocol = result["protocolVersion"].as_str().unwrap_or("");
        if protocol != "2025-06-18" {
            return Err(format!("The server chose protocol version {protocol}").into());
        }
        println!("Protocol version: {protocol}");
    
        let message = json!({"jsonrpc": "2.0", "method": "notifications/initialized"});
        let (status, body) = post(client, &token(), &message)?;
        if status != 202 {
            return Err(format!(
                "notifications/initialized failed with HTTP {status}: {}",
                shorten(&body)
            )
            .into());
        }
        Ok(())
    }
    
    /// Sends a request with a token that the server does not know, and prints
    /// the HTTP status and the server's message, which is a JSON object with
    /// an error member rather than a JSON-RPC reply.
    fn wrong_token(client: &Client) -> Result<(), BoxError> {
        let message = json!({"jsonrpc": "2.0", "id": 1, "method": "tools/list", "params": {}});
        let (status, body) = post(client, "not-a-real-token", &message)?;
        if status != 401 {
            return Err(format!("Expected HTTP 401 for a wrong token, but got {status}").into());
        }
        let reply: Value = serde_json::from_str(&body).unwrap_or(Value::Null);
        let message = match reply["error"].as_str() {
            Some(text) if !text.is_empty() => text,
            _ => "no message",
        };
        println!("Wrong token: HTTP {status}, {message}");
        Ok(())
    }
    
    /// Makes the three checks. The ? operator returns any error to the
    /// caller.
    fn run() -> Result<(), BoxError> {
        if token().is_empty() {
            return Err("MCP_TOKEN must be set".into());
        }
        let client = Client::builder().timeout(TIMEOUT).build()?;
        check_health(&client)?;
        initialize(&client)?;
        wrong_token(&client)
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
    # Connecting to the pgEdge Postgres MCP Server, using Net::HTTP.
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
    
    # Posts a JSON-RPC message to the MCP endpoint with a token, and returns
    # the response.
    def post(http, token, message)
      request = Net::HTTP::Post.new(URI("#{BASE_URL}/mcp/v1"))
      request["Authorization"] = "Bearer #{token}"
      request["Content-Type"] = "application/json"
      request.body = JSON.generate(message)
      http.request(request)
    end
    
    # Sends a JSON-RPC request and returns its result. The server answers a
    # JSON-RPC error with HTTP status 200, so the method checks the reply for
    # an error member as well as the HTTP status.
    def rpc(http, method, params)
      response = post(http, TOKEN, { jsonrpc: "2.0", id: 1, method: method, params: params })
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
    
    # Checks that the server is running. The /health endpoint needs no token.
    def check_health(http)
      response = http.request(Net::HTTP::Get.new(URI("#{BASE_URL}/health")))
      unless response.code == "200"
        raise McpError, "Health check failed with HTTP #{response.code}: #{response.body.to_s[0, 200]}"
      end
      unless parse_object(response.body)&.fetch("status", nil) == "ok"
        raise McpError, "Unexpected response: #{response.body.to_s[0, 200]}"
      end
    
      puts "Health: ok"
    end
    
    # Introduces the client to the server, and prints the server's name and
    # version and the protocol revision that the server chose. The server
    # accepts 2024-11-05, 2025-03-26, 2025-06-18 and 2025-11-25, and answers a
    # revision it does not know with one that it does, so the client checks
    # the answer. The notifications/initialized message then completes the
    # handshake; it is a notification, with no id, so the server replies with
    # HTTP 202 and no body.
    def initialize_session(http)
      result = rpc(http, "initialize", {
                     protocolVersion: "2025-06-18",
                     capabilities: {},
                     clientInfo: { name: "cookbook", version: "1.0.0" }
                   })
      info = result.is_a?(Hash) ? result["serverInfo"] : nil
      unless info.is_a?(Hash) && info["name"].is_a?(String) && info["version"].is_a?(String)
        raise McpError, "Unexpected result: #{result}"
      end
    
      puts "Server: #{info["name"]} #{info["version"]}"
      protocol = result["protocolVersion"]
      raise McpError, "The server chose protocol version #{protocol}" unless protocol == "2025-06-18"
    
      puts "Protocol version: #{protocol}"
    
      response = post(http, TOKEN, { jsonrpc: "2.0", method: "notifications/initialized" })
      return if response.code == "202"
    
      raise McpError, "notifications/initialized failed with HTTP #{response.code}: " \
                      "#{response.body.to_s[0, 200]}"
    end
    
    # Sends a request with a token that the server does not know, and prints
    # the HTTP status and the server's message, which is a JSON object with an
    # error member rather than a JSON-RPC reply.
    def wrong_token(http)
      response = post(http, "not-a-real-token",
                      { jsonrpc: "2.0", id: 1, method: "tools/list", params: {} })
      unless response.code == "401"
        raise McpError, "Expected HTTP 401 for a wrong token, but got #{response.code}"
      end
    
      message = parse_object(response.body)&.fetch("error", nil)
      message = "no message" if message.nil? || message.to_s.empty?
      puts "Wrong token: HTTP #{response.code}, #{message}"
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
        check_health(http)
        initialize_session(http)
        wrong_token(http)
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
    # Connecting to the pgEdge Postgres MCP Server, using curl and jq.
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
    
    # Posts a JSON-RPC message to the MCP endpoint with a token, and prints the
    # reply followed by the HTTP status on a line of its own: post TOKEN BODY.
    # The token goes to curl in a header file that bash supplies through a
    # pipe, so that it never appears in the arguments of the curl process, which
    # other users can read in the process list.
    post() {
        curl --silent --show-error \
            --connect-timeout 10 --max-time "$TIMEOUT_SECONDS" \
            --header @<(printf 'Authorization: Bearer %s\n' "$1") \
            --header 'Content-Type: application/json' \
            --write-out '\n%{http_code}' --data-binary "$2" "$MCP_URL/mcp/v1"
    }
    
    # Sends a JSON-RPC request and prints its result: rpc METHOD PARAMS_JSON.
    # The server answers a JSON-RPC error with HTTP status 200, so the function
    # checks the reply for an error member as well as the HTTP status.
    rpc() {
        local method="$1" request reply status body
        request=$(jq -nc --arg method "$method" --argjson params "$2" \
            '{jsonrpc: "2.0", id: 1, method: $method, params: $params}')
        reply=$(post "$MCP_TOKEN" "$request") || return 1
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
    
    # Checks that the server is running. The /health endpoint needs no token.
    check_health() {
        local body
        body=$(curl --silent --show-error --fail-with-body \
            --connect-timeout 10 --max-time "$TIMEOUT_SECONDS" \
            "$MCP_URL/health") || {
            echo "Health check failed: $body" >&2
            return 1
        }
        jq -er 'if .status == "ok" then "Health: ok"
                else error("status is not ok") end' <<<"$body" 2>/dev/null || {
            echo "Unexpected response: ${body:0:200}" >&2
            return 1
        }
    }
    
    # Introduces the client to the server, and prints the server's name and
    # version and the protocol revision that the server chose. The server
    # accepts 2024-11-05, 2025-03-26, 2025-06-18 and 2025-11-25, and answers a
    # revision it does not know with one that it does, so the client checks
    # the answer. The notifications/initialized message then completes the
    # handshake; it is a notification, with no id, so the server replies with
    # HTTP 202 and no body.
    initialize() {
        local result protocol reply
        result=$(rpc initialize '{
            "protocolVersion": "2025-06-18",
            "capabilities": {},
            "clientInfo": {"name": "cookbook", "version": "1.0.0"}
        }') || return 1
        jq -r '"Server: \(.serverInfo.name) \(.serverInfo.version)"' <<<"$result"
        protocol=$(jq -r '.protocolVersion' <<<"$result")
        if [[ "$protocol" != "2025-06-18" ]]; then
            echo "The server chose protocol version $protocol" >&2
            return 1
        fi
        echo "Protocol version: $protocol"
    
        reply=$(post "$MCP_TOKEN" \
            '{"jsonrpc": "2.0", "method": "notifications/initialized"}') || return 1
        if [[ "${reply##*$'\n'}" != 202 ]]; then
            echo "notifications/initialized failed: ${reply:0:200}" >&2
            return 1
        fi
    }
    
    # Sends a request with a token that the server does not know, and prints
    # the HTTP status and the server's message, which is a JSON object with an
    # error member rather than a JSON-RPC reply.
    wrong_token() {
        local reply status body
        reply=$(post "not-a-real-token" \
            '{"jsonrpc": "2.0", "id": 1, "method": "tools/list", "params": {}}') \
            || return 1
        status="${reply##*$'\n'}"
        body="${reply%$'\n'*}"
        if [[ "$status" != 401 ]]; then
            echo "Expected HTTP 401 for a wrong token, but got $status" >&2
            return 1
        fi
        echo "Wrong token: HTTP $status, $(jq -r '.error // "no message"' <<<"$body")"
    }
    
    main() {
        check_health
        initialize
        wrong_token
    }
    
    main
    
    ```

## Next Steps

The following resources provide more information about the topics in this
recipe:

- The [Exploring a Schema](explore_schema.md) recipe lists the tables and
  columns of a schema.
- The [Reading Resources and Prompts](resources_and_prompts.md) recipe reads
  the resources and prompts that the server offers.
- The [Calling AI DBA Workbench MCP Tools](../ai_dba_workbench/mcp_tools.md)
  recipe calls the same kind of tools through the AI DBA Workbench.
- The
  [pgEdge Postgres MCP Server documentation](https://docs.pgedge.com/pgedge-postgres-mcp-server/)
  describes every tool, resource and setting.
- The [Contributing a Recipe](../contributing.md) page explains how to add a
  recipe or a language to the cookbook.
