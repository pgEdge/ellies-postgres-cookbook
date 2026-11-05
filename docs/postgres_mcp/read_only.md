# Running Read-Only Queries

This recipe runs SQL through the `query_database` tool of a pgEdge Postgres MCP
Server: it runs a `SELECT` and prints the rows, and then tries an `INSERT` to
show that the server refuses to change the data. The server runs every query in
a read-only transaction, so PostgreSQL itself rejects a write, whatever the SQL
looks like. Each step shows the code in every supported language; selecting a
language tab switches every tab on the site to that language.

These examples are for pgEdge Postgres MCP Server 1.1.0.

The program prints the following output:

```text
Columns: name, price
Row: Acme Seedling Kit, 19.95
Row: Acme Quiet Keys, 64.25
Row: Acme Trail Runner, 89.99
INSERT rejected: Error iterating rows: ERROR: cannot execute INSERT in a read-only transaction (SQLSTATE 25006)
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
      "name": "read-only",
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

A program calls a tool with the `tools/call` method, giving the tool's `name`
and its `arguments`, and the server needs no `initialize` handshake first. A
tool's reply is text, in the `text` member of the first item of the result's
`content` array. A tool that fails still returns a result rather than a
JSON-RPC error, with `isError` set to `true` and the error message as its text,
so the helper returns that flag with the text.

The following tabs show how each program reads its settings, and how it calls a
tool:

=== "Python"

    ```python
    # The or operator treats an empty variable as unset.
    BASE_URL = (os.environ.get("MCP_URL") or "http://localhost:8080").rstrip("/")
    TOKEN = os.environ.get("MCP_TOKEN") or ""
    
    TIMEOUT_SECONDS = 30
    
    
    class McpError(Exception):
        """Raised when the MCP Server rejects a request or replies oddly."""
    
    
    def call_tool(client: httpx.Client, name: str,
                  arguments: dict) -> tuple[str, bool]:
        """Calls a tool with tools/call and returns the text of its reply and
        whether the tool failed, which it reports by setting isError.
    
        The server answers a JSON-RPC error with HTTP status 200, so the
        function checks the reply for an error member as well as the HTTP
        status.
        """
        response = client.post(
            "/mcp/v1",
            headers={"Authorization": f"Bearer {TOKEN}"},
            json={"jsonrpc": "2.0", "id": 1, "method": "tools/call",
                  "params": {"name": name, "arguments": arguments}},
        )
        if response.status_code != 200:
            raise McpError(f"{name} failed with HTTP {response.status_code}: "
                           f"{response.text[:200]}")
        try:
            reply = response.json()
        except ValueError:
            reply = None
        if not isinstance(reply, dict) or not ("result" in reply or "error" in reply):
            raise McpError(f"{name} failed: unexpected response: "
                           f"{response.text[:200]}")
        if "error" in reply:
            raise McpError(f"{name} failed: {reply['error'].get('message')}")
        result = reply["result"]
        return result["content"][0]["text"], bool(result.get("isError"))
    ```

=== "TypeScript"

    ```typescript
    // The || operator, unlike ??, also treats an empty variable as unset.
    const baseUrl = (process.env.MCP_URL || "http://localhost:8080").replace(/\/+$/, "");
    const token = process.env.MCP_TOKEN || "";
    
    const timeoutMs = 30_000;
    
    // Calls a tool with tools/call and returns the text of its reply and
    // whether the tool failed, which it reports by setting isError. The server
    // answers a JSON-RPC error with HTTP status 200, so the function checks the
    // reply for an error member as well as the HTTP status.
    async function callTool(
      name: string,
      args: object,
    ): Promise<{ text: string; failed: boolean }> {
      const response = await fetch(`${baseUrl}/mcp/v1`, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${token}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          jsonrpc: "2.0",
          id: 1,
          method: "tools/call",
          params: { name, arguments: args },
        }),
        signal: AbortSignal.timeout(timeoutMs),
      });
      const body = await response.text();
      if (response.status !== 200) {
        throw new Error(`${name} failed with HTTP ${response.status}: ${body.slice(0, 200)}`);
      }
      let reply: any;
      try {
        reply = JSON.parse(body);
      } catch {
        reply = undefined;
      }
      if (typeof reply !== "object" || reply === null || !("result" in reply || "error" in reply)) {
        throw new Error(`${name} failed: unexpected response: ${body.slice(0, 200)}`);
      }
      if ("error" in reply) {
        throw new Error(`${name} failed: ${reply.error?.message}`);
      }
      const text = reply.result?.content?.[0]?.text;
      if (typeof text !== "string") {
        throw new Error(`${name} failed: unexpected result: ${body.slice(0, 200)}`);
      }
      return { text, failed: reply.result.isError === true };
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
    
    /** The text of a tool's reply, and whether the tool failed. */
    record ToolResult(String text, boolean failed) {
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
     * Calls a tool with tools/call and returns the text of its reply and
     * whether the tool failed, which it reports by setting isError. The
     * server answers a JSON-RPC error with HTTP status 200, so the method
     * checks the reply for an error member as well as the HTTP status.
     */
    static ToolResult callTool(String name, Map<String, Object> arguments)
            throws IOException, InterruptedException, McpException {
        String message = MAPPER.writeValueAsString(Map.of(
                "jsonrpc", "2.0", "id", 1, "method", "tools/call",
                "params", Map.of("name", name, "arguments", arguments)));
        HttpRequest request = HttpRequest.newBuilder(URI.create(BASE_URL + "/mcp/v1"))
                .timeout(TIMEOUT)
                .header("Authorization", "Bearer " + TOKEN)
                .header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString(message))
                .build();
        HttpResponse<String> response = send(request);
        if (response.statusCode() != 200) {
            throw new McpException(name + " failed with HTTP "
                    + response.statusCode() + ": " + shorten(response.body()));
        }
        JsonNode reply = parseObject(response.body());
        if (reply == null || !(reply.has("result") || reply.has("error"))) {
            throw new McpException(name + " failed: unexpected response: "
                    + shorten(response.body()));
        }
        if (reply.has("error")) {
            throw new McpException(name + " failed: "
                    + reply.path("error").path("message").asString());
        }
        JsonNode result = reply.path("result");
        JsonNode text = result.path("content").path(0).path("text");
        if (!text.isString()) {
            throw new McpException(name + " failed: unexpected result: "
                    + shorten(response.body()));
        }
        return new ToolResult(text.stringValue(), result.path("isError").asBoolean(false));
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
    
    // Calls a tool with tools/call and returns the text of its reply and
    // whether the tool failed, which it reports by setting isError. The server
    // answers a JSON-RPC error with HTTP status 200, so the function checks the
    // reply for an error member as well as the HTTP status.
    static async Task<(string Text, bool Failed)> CallToolAsync(
        HttpClient client, string name, JsonObject arguments)
    {
        var message = new JsonObject
        {
            ["jsonrpc"] = "2.0",
            ["id"] = 1,
            ["method"] = "tools/call",
            ["params"] = new JsonObject { ["name"] = name, ["arguments"] = arguments },
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
                $"{name} failed with HTTP {(int)response.StatusCode}: {Shorten(body)}");
        }
        var reply = ParseObject(body);
        if (reply is null || !(reply.ContainsKey("result") || reply.ContainsKey("error")))
        {
            throw new McpException($"{name} failed: unexpected response: {Shorten(body)}");
        }
        if (reply.ContainsKey("error"))
        {
            throw new McpException($"{name} failed: {reply["error"]?["message"]}");
        }
        var result = reply["result"];
        if (result?["content"]?[0]?["text"] is not JsonValue textValue ||
            !textValue.TryGetValue(out string? text))
        {
            throw new McpException($"{name} failed: unexpected result: {Shorten(body)}");
        }
        var failed = result["isError"] is JsonValue isError &&
            isError.TryGetValue(out bool flag) && flag;
        return (text, failed);
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
    
    // callTool calls a tool with tools/call and returns the text of its reply
    // and whether the tool failed, which it reports by setting isError. The
    // server answers a JSON-RPC error with HTTP status 200, so the function
    // checks the reply for an error member as well as the HTTP status.
    func callTool(client *http.Client, name string, arguments map[string]any) (string, bool, error) {
    	payload, err := json.Marshal(map[string]any{
    		"jsonrpc": "2.0", "id": 1, "method": "tools/call",
    		"params": map[string]any{"name": name, "arguments": arguments},
    	})
    	if err != nil {
    		return "", false, err
    	}
    	request, err := http.NewRequest(http.MethodPost, baseURL+"/mcp/v1", bytes.NewReader(payload))
    	if err != nil {
    		return "", false, err
    	}
    	request.Header.Set("Authorization", "Bearer "+token)
    	request.Header.Set("Content-Type", "application/json")
    
    	response, err := client.Do(request)
    	if err != nil {
    		return "", false, err
    	}
    	defer response.Body.Close()
    	body, err := io.ReadAll(response.Body)
    	if err != nil {
    		return "", false, err
    	}
    	if response.StatusCode != http.StatusOK {
    		return "", false, fmt.Errorf("%s failed with HTTP %d: %s", name, response.StatusCode, shorten(body))
    	}
    	var reply struct {
    		Result *struct {
    			Content []struct {
    				Text string `json:"text"`
    			} `json:"content"`
    			IsError bool `json:"isError"`
    		} `json:"result"`
    		Error *struct {
    			Message string `json:"message"`
    		} `json:"error"`
    	}
    	if err := json.Unmarshal(body, &reply); err != nil || (reply.Result == nil && reply.Error == nil) {
    		return "", false, fmt.Errorf("%s failed: unexpected response: %s", name, shorten(body))
    	}
    	if reply.Error != nil {
    		return "", false, fmt.Errorf("%s failed: %s", name, reply.Error.Message)
    	}
    	if len(reply.Result.Content) == 0 {
    		return "", false, fmt.Errorf("%s failed: unexpected result: %s", name, shorten(body))
    	}
    	return reply.Result.Content[0].Text, reply.Result.IsError, nil
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
    
    /// Calls a tool with tools/call and returns the text of its reply and
    /// whether the tool failed, which it reports by setting isError. The
    /// server answers a JSON-RPC error with HTTP status 200, so the function
    /// checks the reply for an error member as well as the HTTP status.
    fn call_tool(client: &Client, name: &str, arguments: Value) -> Result<(String, bool), BoxError> {
        let message = json!({
            "jsonrpc": "2.0", "id": 1, "method": "tools/call",
            "params": {"name": name, "arguments": arguments},
        });
        let response = client
            .post(format!("{}/mcp/v1", base_url()))
            .bearer_auth(token())
            .json(&message)
            .send()?;
        let status = response.status().as_u16();
        let body = response.text()?;
        if status != 200 {
            return Err(format!("{name} failed with HTTP {status}: {}", shorten(&body)).into());
        }
        let reply = match serde_json::from_str::<Value>(&body) {
            Ok(reply) if reply.get("result").is_some() || reply.get("error").is_some() => reply,
            _ => return Err(format!("{name} failed: unexpected response: {}", shorten(&body)).into()),
        };
        if let Some(error) = reply.get("error") {
            let message = error["message"].as_str().unwrap_or("unknown error");
            return Err(format!("{name} failed: {message}").into());
        }
        let result = &reply["result"];
        let Some(text) = result["content"][0]["text"].as_str() else {
            return Err(format!("{name} failed: unexpected result: {}", shorten(&body)).into());
        };
        Ok((text.to_string(), result["isError"].as_bool() == Some(true)))
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
    
    # Calls a tool with tools/call and returns the text of its reply and
    # whether the tool failed, which it reports by setting isError. The server
    # answers a JSON-RPC error with HTTP status 200, so the method checks the
    # reply for an error member as well as the HTTP status.
    def call_tool(http, name, arguments)
      request = Net::HTTP::Post.new(URI("#{BASE_URL}/mcp/v1"))
      request["Authorization"] = "Bearer #{TOKEN}"
      request["Content-Type"] = "application/json"
      request.body = JSON.generate({ jsonrpc: "2.0", id: 1, method: "tools/call",
                                     params: { name: name, arguments: arguments } })
      response = http.request(request)
      unless response.code == "200"
        raise McpError, "#{name} failed with HTTP #{response.code}: #{response.body.to_s[0, 200]}"
      end
    
      reply = parse_object(response.body)
      unless reply && (reply.key?("result") || reply.key?("error"))
        raise McpError, "#{name} failed: unexpected response: #{response.body.to_s[0, 200]}"
      end
      raise McpError, "#{name} failed: #{reply["error"]["message"]}" if reply.key?("error")
    
      result = reply["result"]
      text = result.is_a?(Hash) ? result.dig("content", 0, "text") : nil
      raise McpError, "#{name} failed: unexpected result: #{response.body.to_s[0, 200]}" unless text.is_a?(String)
    
      [text, result["isError"] == true]
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
    
    # Calls a tool with tools/call and prints its result, which holds the text
    # of the reply in content[0].text and, if the tool failed, isError set to
    # true: call_tool NAME ARGUMENTS_JSON. The server answers a JSON-RPC error
    # with HTTP status 200, so the function checks the reply for an error
    # member as well as the HTTP status. The token goes to curl in a header
    # file that bash supplies through a pipe, so that it never appears in the
    # arguments of the curl process, which other users can read in the process
    # list.
    call_tool() {
        local name="$1" request reply status body
        request=$(jq -nc --arg name "$name" --argjson arguments "$2" \
            '{jsonrpc: "2.0", id: 1, method: "tools/call",
              params: {name: $name, arguments: $arguments}}')
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
            echo "$name failed with HTTP $status: ${body:0:200}" >&2
            return 1
        fi
        if ! jq -e '.result.content[0].text or has("error")' >/dev/null 2>&1 \
            <<<"$body"; then
            echo "$name failed: unexpected response: ${body:0:200}" >&2
            return 1
        fi
        if jq -e 'has("error")' >/dev/null <<<"$body"; then
            echo "$name failed: $(jq -r '.error.message' <<<"$body")" >&2
            return 1
        fi
        jq -c '.result' <<<"$body"
    }
    ```

## Running a Query

The `query_database` tool takes the SQL in its `query` argument. Its reply is
text rather than JSON: it names the database, repeats the query with a `LIMIT`
that the server adds, and then has a line that starts with `Results`, a header
line of column names, and one line for each row, with the values separated by
tabs. A tab or a newline inside a value appears as `\t` or `\n`, and a NULL as
an empty string. The program prints the part after the `Results` line, with the
tabs replaced by commas. The parsing depends on the layout of the text in
version 1.1.0, so check it again after an upgrade. The following tabs show how
each program runs the query:

=== "Python"

    ```python
    def select_cheap_products(client: httpx.Client) -> None:
        """Runs a SELECT with query_database, and prints the column names and
        each row.
    
        The reply repeats the query, with the LIMIT that the server adds, and
        then has a line such as "Results (3 rows):", a header line, and one
        line for each row, with the values separated by tabs. The server
        writes a tab or a newline inside a value as \\t or \\n, and a NULL as
        an empty string.
        """
        text, failed = call_tool(client, "query_database", {
            "query": "SELECT name, price FROM cookbook_mcp.products "
                     "WHERE price < 100 ORDER BY price",
        })
        if failed:
            raise McpError(f"query_database failed: {text}")
        lines = text.split("\n")
        start = next((i for i, line in enumerate(lines)
                      if line.startswith("Results ")), None)
        if start is None or start + 1 >= len(lines):
            raise McpError(f"Unexpected reply: {text[:200]}")
        print("Columns: " + ", ".join(lines[start + 1].split("\t")))
        for line in lines[start + 2:]:
            if line:
                print("Row: " + ", ".join(line.split("\t")))
    ```

=== "TypeScript"

    ```typescript
    // Runs a SELECT with query_database, and prints the column names and each
    // row. The reply repeats the query, with the LIMIT that the server adds,
    // and then has a line such as "Results (3 rows):", a header line, and one
    // line for each row, with the values separated by tabs. The server writes
    // a tab or a newline inside a value as \t or \n, and a NULL as an empty
    // string.
    async function selectCheapProducts(): Promise<void> {
      const { text, failed } = await callTool("query_database", {
        query: "SELECT name, price FROM cookbook_mcp.products WHERE price < 100 ORDER BY price",
      });
      if (failed) {
        throw new Error(`query_database failed: ${text}`);
      }
      const lines = text.split("\n");
      const start = lines.findIndex((line) => line.startsWith("Results "));
      if (start < 0 || start + 1 >= lines.length) {
        throw new Error(`Unexpected reply: ${text.slice(0, 200)}`);
      }
      console.log(`Columns: ${lines[start + 1].split("\t").join(", ")}`);
      for (const line of lines.slice(start + 2)) {
        if (line !== "") {
          console.log(`Row: ${line.split("\t").join(", ")}`);
        }
      }
    }
    ```

=== "Java"

    ```java
    /**
     * Runs a SELECT with query_database, and prints the column names and
     * each row. The reply repeats the query, with the LIMIT that the server
     * adds, and then has a line such as "Results (3 rows):", a header line,
     * and one line for each row, with the values separated by tabs. The
     * server writes a tab or a newline inside a value as \t or \n, and a
     * NULL as an empty string.
     */
    static void selectCheapProducts() throws IOException, InterruptedException, McpException {
        ToolResult result = callTool("query_database", Map.of(
                "query", "SELECT name, price FROM cookbook_mcp.products "
                        + "WHERE price < 100 ORDER BY price"));
        if (result.failed()) {
            throw new McpException("query_database failed: " + result.text());
        }
        String[] lines = result.text().split("\n");
        int start = -1;
        for (int i = 0; i < lines.length; i++) {
            if (lines[i].startsWith("Results ")) {
                start = i;
                break;
            }
        }
        if (start < 0 || start + 1 >= lines.length) {
            throw new McpException("Unexpected reply: " + shorten(result.text()));
        }
        System.out.println("Columns: " + lines[start + 1].replace("\t", ", "));
        for (int i = start + 2; i < lines.length; i++) {
            if (!lines[i].isEmpty()) {
                System.out.println("Row: " + lines[i].replace("\t", ", "));
            }
        }
    }
    ```

=== "C#"

    ```csharp
    // Runs a SELECT with query_database, and prints the column names and each
    // row. The reply repeats the query, with the LIMIT that the server adds,
    // and then has a line such as "Results (3 rows):", a header line, and one
    // line for each row, with the values separated by tabs. The server writes
    // a tab or a newline inside a value as \t or \n, and a NULL as an empty
    // string.
    static async Task SelectCheapProductsAsync(HttpClient client)
    {
        var (text, failed) = await CallToolAsync(client, "query_database", new JsonObject
        {
            ["query"] = "SELECT name, price FROM cookbook_mcp.products "
                + "WHERE price < 100 ORDER BY price",
        });
        if (failed)
        {
            throw new McpException($"query_database failed: {text}");
        }
        var lines = text.Split('\n');
        var start = Array.FindIndex(lines, line => line.StartsWith("Results "));
        if (start < 0 || start + 1 >= lines.Length)
        {
            throw new McpException($"Unexpected reply: {Shorten(text)}");
        }
        Console.WriteLine($"Columns: {lines[start + 1].Replace("\t", ", ")}");
        foreach (var line in lines.Skip(start + 2).Where(line => line.Length > 0))
        {
            Console.WriteLine($"Row: {line.Replace("\t", ", ")}");
        }
    }
    ```

=== "Go"

    ```go
    // selectCheapProducts runs a SELECT with query_database, and prints the
    // column names and each row. The reply repeats the query, with the LIMIT
    // that the server adds, and then has a line such as "Results (3 rows):", a
    // header line, and one line for each row, with the values separated by
    // tabs. The server writes a tab or a newline inside a value as \t or \n,
    // and a NULL as an empty string.
    func selectCheapProducts(client *http.Client) error {
    	text, failed, err := callTool(client, "query_database", map[string]any{
    		"query": "SELECT name, price FROM cookbook_mcp.products WHERE price < 100 ORDER BY price",
    	})
    	if err != nil {
    		return err
    	}
    	if failed {
    		return fmt.Errorf("query_database failed: %s", text)
    	}
    	lines := strings.Split(text, "\n")
    	start := -1
    	for i, line := range lines {
    		if strings.HasPrefix(line, "Results ") {
    			start = i
    			break
    		}
    	}
    	if start < 0 || start+1 >= len(lines) {
    		return fmt.Errorf("unexpected reply: %s", shorten([]byte(text)))
    	}
    	fmt.Printf("Columns: %s\n", strings.ReplaceAll(lines[start+1], "\t", ", "))
    	for _, line := range lines[start+2:] {
    		if line != "" {
    			fmt.Printf("Row: %s\n", strings.ReplaceAll(line, "\t", ", "))
    		}
    	}
    	return nil
    }
    
    ```

=== "Rust"

    ```rust
    /// Runs a SELECT with query_database, and prints the column names and each
    /// row. The reply repeats the query, with the LIMIT that the server adds,
    /// and then has a line such as "Results (3 rows):", a header line, and one
    /// line for each row, with the values separated by tabs. The server writes
    /// a tab or a newline inside a value as \t or \n, and a NULL as an empty
    /// string.
    fn select_cheap_products(client: &Client) -> Result<(), BoxError> {
        let (text, failed) = call_tool(
            client,
            "query_database",
            json!({
                "query": "SELECT name, price FROM cookbook_mcp.products \
                          WHERE price < 100 ORDER BY price",
            }),
        )?;
        if failed {
            return Err(format!("query_database failed: {text}").into());
        }
        let mut lines = text.split('\n').skip_while(|line| !line.starts_with("Results "));
        let (Some(_), Some(header)) = (lines.next(), lines.next()) else {
            return Err(format!("Unexpected reply: {}", shorten(&text)).into());
        };
        println!("Columns: {}", header.replace('\t', ", "));
        for line in lines.filter(|line| !line.is_empty()) {
            println!("Row: {}", line.replace('\t', ", "));
        }
        Ok(())
    }
    ```

=== "Ruby"

    ```ruby
    # Runs a SELECT with query_database, and prints the column names and each
    # row. The reply repeats the query, with the LIMIT that the server adds,
    # and then has a line such as "Results (3 rows):", a header line, and one
    # line for each row, with the values separated by tabs. The server writes a
    # tab or a newline inside a value as \t or \n, and a NULL as an empty
    # string.
    def select_cheap_products(http)
      text, failed = call_tool(http, "query_database", {
                                 query: "SELECT name, price FROM cookbook_mcp.products " \
                                        "WHERE price < 100 ORDER BY price"
                               })
      raise McpError, "query_database failed: #{text}" if failed
    
      lines = text.split("\n")
      start = lines.index { |line| line.start_with?("Results ") }
      raise McpError, "Unexpected reply: #{text[0, 200]}" if start.nil? || start + 1 >= lines.length
    
      puts "Columns: #{lines[start + 1].gsub("\t", ", ")}"
      lines[(start + 2)..].reject(&:empty?).each do |line|
        puts "Row: #{line.gsub("\t", ", ")}"
      end
    end
    ```

=== "curl"

    ```bash
    # Runs a SELECT with query_database, and prints the column names and each
    # row. The reply repeats the query, with the LIMIT that the server adds,
    # and then has a line such as "Results (3 rows):", a header line, and one
    # line for each row, with the values separated by tabs. The server writes
    # a tab or a newline inside a value as \t or \n, and a NULL as an empty
    # string.
    select_cheap_products() {
        local query result
        query="SELECT name, price FROM cookbook_mcp.products
               WHERE price < 100 ORDER BY price"
        result=$(call_tool query_database \
            "$(jq -nc --arg query "$query" '{query: $query}')") || return 1
        if jq -e '.isError == true' >/dev/null <<<"$result"; then
            echo "query_database failed: $(jq -r '.content[0].text' <<<"$result")" >&2
            return 1
        fi
        jq -r '
            .content[0].text | split("\n") as $lines
            | ($lines | map(startswith("Results ")) | index(true)) as $start
            | if $start == null or $start + 1 >= ($lines | length)
              then error("The reply had no results") else . end
            | "Columns: \($lines[$start + 1] | split("\t") | join(", "))",
              ($lines[$start + 2:][] | select(. != "")
               | "Row: \(split("\t") | join(", "))")' <<<"$result" || {
            echo "Unexpected reply: $(jq -r '.content[0].text' <<<"$result" | head -c 200)" >&2
            return 1
        }
    }
    ```

## Trying to Write

The `INSERT` reaches PostgreSQL, which refuses it with SQLSTATE `25006` because
the transaction is read-only, and the tool returns the error with `isError` set
to `true`. The `INSERT` leaves out `id`, which the table requires, so that even
a server that allows writes would refuse it rather than save a row. For that
reason, each program checks for SQLSTATE `25006` itself rather than for any
error, and fails if the write succeeds or fails for another reason. Some errors
from the tool start with the query that failed, so each program prints only
the last line of the error, which holds the message from PostgreSQL. The
following tabs show the attempt:

=== "Python"

    ```python
    def try_insert(client: httpx.Client) -> None:
        """Tries to add a row. query_database runs every query in a read-only
        transaction, so PostgreSQL itself refuses the INSERT with SQLSTATE
        25006, and the tool returns the error with isError set to true. The
        INSERT leaves out id, which the table requires, so that even a server
        that allows writes would refuse it rather than save a row. That is
        why the function checks for the read-only error itself rather than
        for any error, and fails if the write succeeds or fails for another
        reason. It prints only the last line of the error, which holds
        PostgreSQL's message, because some errors start with the query."""
        text, failed = call_tool(client, "query_database", {
            "query": "INSERT INTO cookbook_mcp.products "
                     "(name, category, price, in_stock, description) "
                     "VALUES ('Acme Test Widget', 'Testing', 1.00, true, "
                     "'A made-up product that is never saved')",
        })
        error_line = text.strip().split("\n")[-1]
        if not failed:
            raise McpError("The server accepted a write")
        if "SQLSTATE 25006" not in text:
            raise McpError(f"The INSERT failed for another reason: {error_line}")
        print(f"INSERT rejected: {error_line}")
    ```

=== "TypeScript"

    ```typescript
    // Tries to add a row. query_database runs every query in a read-only
    // transaction, so PostgreSQL itself refuses the INSERT with SQLSTATE
    // 25006, and the tool returns the error with isError set to true. The
    // INSERT leaves out id, which the table requires, so that even a server
    // that allows writes would refuse it rather than save a row. That is
    // why the function checks for the read-only error itself rather than
    // for any error, and fails if the write succeeds or fails for another
    // reason. It prints only the last line of the error, which holds
    // PostgreSQL's message, because some errors start with the query.
    async function tryInsert(): Promise<void> {
      const { text, failed } = await callTool("query_database", {
        query:
          "INSERT INTO cookbook_mcp.products " +
          "(name, category, price, in_stock, description) " +
          "VALUES ('Acme Test Widget', 'Testing', 1.00, true, " +
          "'A made-up product that is never saved')",
      });
      const errorLine = text.trim().split("\n").pop() ?? "";
      if (!failed) {
        throw new Error("The server accepted a write");
      }
      if (!text.includes("SQLSTATE 25006")) {
        throw new Error(`The INSERT failed for another reason: ${errorLine}`);
      }
      console.log(`INSERT rejected: ${errorLine}`);
    }
    ```

=== "Java"

    ```java
    /**
     * Tries to add a row. query_database runs every query in a read-only
     * transaction, so PostgreSQL itself refuses the INSERT with SQLSTATE
     * 25006, and the tool returns the error with isError set to true. The
     * INSERT leaves out id, which the table requires, so that even a server
     * that allows writes would refuse it rather than save a row. That is
     * why the method checks for the read-only error itself rather than
     * for any error, and fails if the write succeeds or fails for another
     * reason. It prints only the last line of the error, which holds
     * PostgreSQL's message, because some errors start with the query.
     */
    static void tryInsert() throws IOException, InterruptedException, McpException {
        ToolResult result = callTool("query_database", Map.of(
                "query", "INSERT INTO cookbook_mcp.products "
                        + "(name, category, price, in_stock, description) "
                        + "VALUES ('Acme Test Widget', 'Testing', 1.00, true, "
                        + "'A made-up product that is never saved')"));
        String[] lines = result.text().strip().split("\n");
        String errorLine = lines[lines.length - 1];
        if (!result.failed()) {
            throw new McpException("The server accepted a write");
        }
        if (!result.text().contains("SQLSTATE 25006")) {
            throw new McpException("The INSERT failed for another reason: " + errorLine);
        }
        System.out.println("INSERT rejected: " + errorLine);
    }
    ```

=== "C#"

    ```csharp
    // Tries to add a row. query_database runs every query in a read-only
    // transaction, so PostgreSQL itself refuses the INSERT with SQLSTATE
    // 25006, and the tool returns the error with isError set to true. The
    // INSERT leaves out id, which the table requires, so that even a server
    // that allows writes would refuse it rather than save a row. That is
    // why the function checks for the read-only error itself rather than
    // for any error, and fails if the write succeeds or fails for another
    // reason. It prints only the last line of the error, which holds
    // PostgreSQL's message, because some errors start with the query.
    static async Task TryInsertAsync(HttpClient client)
    {
        var (text, failed) = await CallToolAsync(client, "query_database", new JsonObject
        {
            ["query"] = "INSERT INTO cookbook_mcp.products "
                + "(name, category, price, in_stock, description) "
                + "VALUES ('Acme Test Widget', 'Testing', 1.00, true, "
                + "'A made-up product that is never saved')",
        });
        var errorLine = text.Trim().Split('\n')[^1];
        if (!failed)
        {
            throw new McpException("The server accepted a write");
        }
        if (!text.Contains("SQLSTATE 25006"))
        {
            throw new McpException($"The INSERT failed for another reason: {errorLine}");
        }
        Console.WriteLine($"INSERT rejected: {errorLine}");
    }
    ```

=== "Go"

    ```go
    // tryInsert tries to add a row. query_database runs every query in a
    // read-only transaction, so PostgreSQL itself refuses the INSERT with
    // SQLSTATE 25006, and the tool returns the error with isError set to true.
    // The INSERT leaves out id, which the table requires, so that even a server
    // that allows writes would refuse it rather than save a row. That is why
    // the function checks for the read-only error itself rather than for any
    // error, and fails if the write succeeds or fails for another reason. It
    // prints only the last line of the error, which holds PostgreSQL's
    // message, because some errors start with the query.
    func tryInsert(client *http.Client) error {
    	text, failed, err := callTool(client, "query_database", map[string]any{
    		"query": "INSERT INTO cookbook_mcp.products " +
    			"(name, category, price, in_stock, description) " +
    			"VALUES ('Acme Test Widget', 'Testing', 1.00, true, " +
    			"'A made-up product that is never saved')",
    	})
    	if err != nil {
    		return err
    	}
    	lines := strings.Split(strings.TrimSpace(text), "\n")
    	errorLine := lines[len(lines)-1]
    	if !failed {
    		return errors.New("the server accepted a write")
    	}
    	if !strings.Contains(text, "SQLSTATE 25006") {
    		return fmt.Errorf("the INSERT failed for another reason: %s", errorLine)
    	}
    	fmt.Printf("INSERT rejected: %s\n", errorLine)
    	return nil
    }
    
    ```

=== "Rust"

    ```rust
    /// Tries to add a row. query_database runs every query in a read-only
    /// transaction, so PostgreSQL itself refuses the INSERT with SQLSTATE
    /// 25006, and the tool returns the error with isError set to true. The
    /// INSERT leaves out id, which the table requires, so that even a server
    /// that allows writes would refuse it rather than save a row. That is
    /// why the function checks for the read-only error itself rather than
    /// for any error, and fails if the write succeeds or fails for another
    /// reason. It prints only the last line of the error, which holds
    /// PostgreSQL's message, because some errors start with the query.
    fn try_insert(client: &Client) -> Result<(), BoxError> {
        let (text, failed) = call_tool(
            client,
            "query_database",
            json!({
                "query": "INSERT INTO cookbook_mcp.products \
                          (name, category, price, in_stock, description) \
                          VALUES ('Acme Test Widget', 'Testing', 1.00, true, \
                          'A made-up product that is never saved')",
            }),
        )?;
        let error_line = text.trim().lines().last().unwrap_or("");
        if !failed {
            return Err("The server accepted a write".into());
        }
        if !text.contains("SQLSTATE 25006") {
            return Err(format!("The INSERT failed for another reason: {error_line}").into());
        }
        println!("INSERT rejected: {error_line}");
        Ok(())
    }
    ```

=== "Ruby"

    ```ruby
    # Tries to add a row. query_database runs every query in a read-only
    # transaction, so PostgreSQL itself refuses the INSERT with SQLSTATE
    # 25006, and the tool returns the error with isError set to true. The
    # INSERT leaves out id, which the table requires, so that even a server
    # that allows writes would refuse it rather than save a row. That is
    # why the method checks for the read-only error itself rather than
    # for any error, and fails if the write succeeds or fails for another
    # reason. It prints only the last line of the error, which holds
    # PostgreSQL's message, because some errors start with the query.
    def try_insert(http)
      text, failed = call_tool(http, "query_database", {
                                 query: "INSERT INTO cookbook_mcp.products " \
                                        "(name, category, price, in_stock, description) " \
                                        "VALUES ('Acme Test Widget', 'Testing', 1.00, true, " \
                                        "'A made-up product that is never saved')"
                               })
      error_line = text.strip.split("\n").last.to_s
      raise McpError, "The server accepted a write" unless failed
      unless text.include?("SQLSTATE 25006")
        raise McpError, "The INSERT failed for another reason: #{error_line}"
      end
    
      puts "INSERT rejected: #{error_line}"
    end
    ```

=== "curl"

    ```bash
    # Tries to add a row. query_database runs every query in a read-only
    # transaction, so PostgreSQL itself refuses the INSERT with SQLSTATE
    # 25006, and the tool returns the error with isError set to true. The
    # INSERT leaves out id, which the table requires, so that even a server
    # that allows writes would refuse it rather than save a row. That is
    # why the script checks for the read-only error itself rather than
    # for any error, and fails if the write succeeds or fails for another
    # reason. It prints only the last line of the error, which holds
    # PostgreSQL's message, because some errors start with the query.
    try_insert() {
        local query result text error_line
        query="INSERT INTO cookbook_mcp.products
                   (name, category, price, in_stock, description)
               VALUES ('Acme Test Widget', 'Testing', 1.00, true,
                       'A made-up product that is never saved')"
        result=$(call_tool query_database \
            "$(jq -nc --arg query "$query" '{query: $query}')") || return 1
        if ! jq -e '.isError == true' >/dev/null <<<"$result"; then
            echo "The server accepted a write" >&2
            return 1
        fi
        text=$(jq -r '.content[0].text' <<<"$result")
        error_line="${text##*$'\n'}"
        if [[ "$text" != *"SQLSTATE 25006"* ]]; then
            echo "The INSERT failed for another reason: $error_line" >&2
            return 1
        fi
        echo "INSERT rejected: $error_line"
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
                select_cheap_products(client)
                try_insert(client)
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
        await selectCheapProducts();
        await tryInsert();
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
            selectCheapProducts();
            tryInsert();
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
        await SelectCheapProductsAsync(client);
        await TryInsertAsync(client);
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
    // run makes the two calls and returns any error to the caller.
    func run() error {
    	if token == "" {
    		return errors.New("MCP_TOKEN must be set")
    	}
    	client := &http.Client{Timeout: timeout}
    	if err := selectCheapProducts(client); err != nil {
    		return err
    	}
    	return tryInsert(client)
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
    /// Makes the two calls. The ? operator returns any error to the caller.
    fn run() -> Result<(), BoxError> {
        if token().is_empty() {
            return Err("MCP_TOKEN must be set".into());
        }
        let client = Client::builder().timeout(TIMEOUT).build()?;
        select_cheap_products(&client)?;
        try_insert(&client)
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
        select_cheap_products(http)
        try_insert(http)
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
        select_cheap_products
        try_insert
    }
    
    main
    ```

## Running the Example

The complete project for each language is available in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/postgres_mcp/read_only).
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
    Running read-only queries through the pgEdge Postgres MCP Server, using
    httpx.
    
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
    
    
    def call_tool(client: httpx.Client, name: str,
                  arguments: dict) -> tuple[str, bool]:
        """Calls a tool with tools/call and returns the text of its reply and
        whether the tool failed, which it reports by setting isError.
    
        The server answers a JSON-RPC error with HTTP status 200, so the
        function checks the reply for an error member as well as the HTTP
        status.
        """
        response = client.post(
            "/mcp/v1",
            headers={"Authorization": f"Bearer {TOKEN}"},
            json={"jsonrpc": "2.0", "id": 1, "method": "tools/call",
                  "params": {"name": name, "arguments": arguments}},
        )
        if response.status_code != 200:
            raise McpError(f"{name} failed with HTTP {response.status_code}: "
                           f"{response.text[:200]}")
        try:
            reply = response.json()
        except ValueError:
            reply = None
        if not isinstance(reply, dict) or not ("result" in reply or "error" in reply):
            raise McpError(f"{name} failed: unexpected response: "
                           f"{response.text[:200]}")
        if "error" in reply:
            raise McpError(f"{name} failed: {reply['error'].get('message')}")
        result = reply["result"]
        return result["content"][0]["text"], bool(result.get("isError"))
    
    
    def select_cheap_products(client: httpx.Client) -> None:
        """Runs a SELECT with query_database, and prints the column names and
        each row.
    
        The reply repeats the query, with the LIMIT that the server adds, and
        then has a line such as "Results (3 rows):", a header line, and one
        line for each row, with the values separated by tabs. The server
        writes a tab or a newline inside a value as \\t or \\n, and a NULL as
        an empty string.
        """
        text, failed = call_tool(client, "query_database", {
            "query": "SELECT name, price FROM cookbook_mcp.products "
                     "WHERE price < 100 ORDER BY price",
        })
        if failed:
            raise McpError(f"query_database failed: {text}")
        lines = text.split("\n")
        start = next((i for i, line in enumerate(lines)
                      if line.startswith("Results ")), None)
        if start is None or start + 1 >= len(lines):
            raise McpError(f"Unexpected reply: {text[:200]}")
        print("Columns: " + ", ".join(lines[start + 1].split("\t")))
        for line in lines[start + 2:]:
            if line:
                print("Row: " + ", ".join(line.split("\t")))
    
    
    def try_insert(client: httpx.Client) -> None:
        """Tries to add a row. query_database runs every query in a read-only
        transaction, so PostgreSQL itself refuses the INSERT with SQLSTATE
        25006, and the tool returns the error with isError set to true. The
        INSERT leaves out id, which the table requires, so that even a server
        that allows writes would refuse it rather than save a row. That is
        why the function checks for the read-only error itself rather than
        for any error, and fails if the write succeeds or fails for another
        reason. It prints only the last line of the error, which holds
        PostgreSQL's message, because some errors start with the query."""
        text, failed = call_tool(client, "query_database", {
            "query": "INSERT INTO cookbook_mcp.products "
                     "(name, category, price, in_stock, description) "
                     "VALUES ('Acme Test Widget', 'Testing', 1.00, true, "
                     "'A made-up product that is never saved')",
        })
        error_line = text.strip().split("\n")[-1]
        if not failed:
            raise McpError("The server accepted a write")
        if "SQLSTATE 25006" not in text:
            raise McpError(f"The INSERT failed for another reason: {error_line}")
        print(f"INSERT rejected: {error_line}")
    
    
    def main() -> int:
        if not TOKEN:
            print("MCP_TOKEN must be set", file=sys.stderr)
            return 1
        try:
            with httpx.Client(base_url=BASE_URL, timeout=TIMEOUT_SECONDS) as client:
                select_cheap_products(client)
                try_insert(client)
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
     * Running read-only queries through the pgEdge Postgres MCP Server, using
     * the built-in fetch.
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
    
    // Calls a tool with tools/call and returns the text of its reply and
    // whether the tool failed, which it reports by setting isError. The server
    // answers a JSON-RPC error with HTTP status 200, so the function checks the
    // reply for an error member as well as the HTTP status.
    async function callTool(
      name: string,
      args: object,
    ): Promise<{ text: string; failed: boolean }> {
      const response = await fetch(`${baseUrl}/mcp/v1`, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${token}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          jsonrpc: "2.0",
          id: 1,
          method: "tools/call",
          params: { name, arguments: args },
        }),
        signal: AbortSignal.timeout(timeoutMs),
      });
      const body = await response.text();
      if (response.status !== 200) {
        throw new Error(`${name} failed with HTTP ${response.status}: ${body.slice(0, 200)}`);
      }
      let reply: any;
      try {
        reply = JSON.parse(body);
      } catch {
        reply = undefined;
      }
      if (typeof reply !== "object" || reply === null || !("result" in reply || "error" in reply)) {
        throw new Error(`${name} failed: unexpected response: ${body.slice(0, 200)}`);
      }
      if ("error" in reply) {
        throw new Error(`${name} failed: ${reply.error?.message}`);
      }
      const text = reply.result?.content?.[0]?.text;
      if (typeof text !== "string") {
        throw new Error(`${name} failed: unexpected result: ${body.slice(0, 200)}`);
      }
      return { text, failed: reply.result.isError === true };
    }
    
    // Runs a SELECT with query_database, and prints the column names and each
    // row. The reply repeats the query, with the LIMIT that the server adds,
    // and then has a line such as "Results (3 rows):", a header line, and one
    // line for each row, with the values separated by tabs. The server writes
    // a tab or a newline inside a value as \t or \n, and a NULL as an empty
    // string.
    async function selectCheapProducts(): Promise<void> {
      const { text, failed } = await callTool("query_database", {
        query: "SELECT name, price FROM cookbook_mcp.products WHERE price < 100 ORDER BY price",
      });
      if (failed) {
        throw new Error(`query_database failed: ${text}`);
      }
      const lines = text.split("\n");
      const start = lines.findIndex((line) => line.startsWith("Results "));
      if (start < 0 || start + 1 >= lines.length) {
        throw new Error(`Unexpected reply: ${text.slice(0, 200)}`);
      }
      console.log(`Columns: ${lines[start + 1].split("\t").join(", ")}`);
      for (const line of lines.slice(start + 2)) {
        if (line !== "") {
          console.log(`Row: ${line.split("\t").join(", ")}`);
        }
      }
    }
    
    // Tries to add a row. query_database runs every query in a read-only
    // transaction, so PostgreSQL itself refuses the INSERT with SQLSTATE
    // 25006, and the tool returns the error with isError set to true. The
    // INSERT leaves out id, which the table requires, so that even a server
    // that allows writes would refuse it rather than save a row. That is
    // why the function checks for the read-only error itself rather than
    // for any error, and fails if the write succeeds or fails for another
    // reason. It prints only the last line of the error, which holds
    // PostgreSQL's message, because some errors start with the query.
    async function tryInsert(): Promise<void> {
      const { text, failed } = await callTool("query_database", {
        query:
          "INSERT INTO cookbook_mcp.products " +
          "(name, category, price, in_stock, description) " +
          "VALUES ('Acme Test Widget', 'Testing', 1.00, true, " +
          "'A made-up product that is never saved')",
      });
      const errorLine = text.trim().split("\n").pop() ?? "";
      if (!failed) {
        throw new Error("The server accepted a write");
      }
      if (!text.includes("SQLSTATE 25006")) {
        throw new Error(`The INSERT failed for another reason: ${errorLine}`);
      }
      console.log(`INSERT rejected: ${errorLine}`);
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
        await selectCheapProducts();
        await tryInsert();
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
     * Running read-only queries through the pgEdge Postgres MCP Server, using
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
    
        /** The text of a tool's reply, and whether the tool failed. */
        record ToolResult(String text, boolean failed) {
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
         * Calls a tool with tools/call and returns the text of its reply and
         * whether the tool failed, which it reports by setting isError. The
         * server answers a JSON-RPC error with HTTP status 200, so the method
         * checks the reply for an error member as well as the HTTP status.
         */
        static ToolResult callTool(String name, Map<String, Object> arguments)
                throws IOException, InterruptedException, McpException {
            String message = MAPPER.writeValueAsString(Map.of(
                    "jsonrpc", "2.0", "id", 1, "method", "tools/call",
                    "params", Map.of("name", name, "arguments", arguments)));
            HttpRequest request = HttpRequest.newBuilder(URI.create(BASE_URL + "/mcp/v1"))
                    .timeout(TIMEOUT)
                    .header("Authorization", "Bearer " + TOKEN)
                    .header("Content-Type", "application/json")
                    .POST(HttpRequest.BodyPublishers.ofString(message))
                    .build();
            HttpResponse<String> response = send(request);
            if (response.statusCode() != 200) {
                throw new McpException(name + " failed with HTTP "
                        + response.statusCode() + ": " + shorten(response.body()));
            }
            JsonNode reply = parseObject(response.body());
            if (reply == null || !(reply.has("result") || reply.has("error"))) {
                throw new McpException(name + " failed: unexpected response: "
                        + shorten(response.body()));
            }
            if (reply.has("error")) {
                throw new McpException(name + " failed: "
                        + reply.path("error").path("message").asString());
            }
            JsonNode result = reply.path("result");
            JsonNode text = result.path("content").path(0).path("text");
            if (!text.isString()) {
                throw new McpException(name + " failed: unexpected result: "
                        + shorten(response.body()));
            }
            return new ToolResult(text.stringValue(), result.path("isError").asBoolean(false));
        }
    
        /**
         * Runs a SELECT with query_database, and prints the column names and
         * each row. The reply repeats the query, with the LIMIT that the server
         * adds, and then has a line such as "Results (3 rows):", a header line,
         * and one line for each row, with the values separated by tabs. The
         * server writes a tab or a newline inside a value as \t or \n, and a
         * NULL as an empty string.
         */
        static void selectCheapProducts() throws IOException, InterruptedException, McpException {
            ToolResult result = callTool("query_database", Map.of(
                    "query", "SELECT name, price FROM cookbook_mcp.products "
                            + "WHERE price < 100 ORDER BY price"));
            if (result.failed()) {
                throw new McpException("query_database failed: " + result.text());
            }
            String[] lines = result.text().split("\n");
            int start = -1;
            for (int i = 0; i < lines.length; i++) {
                if (lines[i].startsWith("Results ")) {
                    start = i;
                    break;
                }
            }
            if (start < 0 || start + 1 >= lines.length) {
                throw new McpException("Unexpected reply: " + shorten(result.text()));
            }
            System.out.println("Columns: " + lines[start + 1].replace("\t", ", "));
            for (int i = start + 2; i < lines.length; i++) {
                if (!lines[i].isEmpty()) {
                    System.out.println("Row: " + lines[i].replace("\t", ", "));
                }
            }
        }
    
        /**
         * Tries to add a row. query_database runs every query in a read-only
         * transaction, so PostgreSQL itself refuses the INSERT with SQLSTATE
         * 25006, and the tool returns the error with isError set to true. The
         * INSERT leaves out id, which the table requires, so that even a server
         * that allows writes would refuse it rather than save a row. That is
         * why the method checks for the read-only error itself rather than
         * for any error, and fails if the write succeeds or fails for another
         * reason. It prints only the last line of the error, which holds
         * PostgreSQL's message, because some errors start with the query.
         */
        static void tryInsert() throws IOException, InterruptedException, McpException {
            ToolResult result = callTool("query_database", Map.of(
                    "query", "INSERT INTO cookbook_mcp.products "
                            + "(name, category, price, in_stock, description) "
                            + "VALUES ('Acme Test Widget', 'Testing', 1.00, true, "
                            + "'A made-up product that is never saved')"));
            String[] lines = result.text().strip().split("\n");
            String errorLine = lines[lines.length - 1];
            if (!result.failed()) {
                throw new McpException("The server accepted a write");
            }
            if (!result.text().contains("SQLSTATE 25006")) {
                throw new McpException("The INSERT failed for another reason: " + errorLine);
            }
            System.out.println("INSERT rejected: " + errorLine);
        }
    
        public static void main(String[] args) {
            if (TOKEN.isEmpty()) {
                System.err.println("MCP_TOKEN must be set");
                System.exit(1);
            }
            try {
                selectCheapProducts();
                tryInsert();
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
     * Running read-only queries through the pgEdge Postgres MCP Server, using
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
    
    // Calls a tool with tools/call and returns the text of its reply and
    // whether the tool failed, which it reports by setting isError. The server
    // answers a JSON-RPC error with HTTP status 200, so the function checks the
    // reply for an error member as well as the HTTP status.
    static async Task<(string Text, bool Failed)> CallToolAsync(
        HttpClient client, string name, JsonObject arguments)
    {
        var message = new JsonObject
        {
            ["jsonrpc"] = "2.0",
            ["id"] = 1,
            ["method"] = "tools/call",
            ["params"] = new JsonObject { ["name"] = name, ["arguments"] = arguments },
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
                $"{name} failed with HTTP {(int)response.StatusCode}: {Shorten(body)}");
        }
        var reply = ParseObject(body);
        if (reply is null || !(reply.ContainsKey("result") || reply.ContainsKey("error")))
        {
            throw new McpException($"{name} failed: unexpected response: {Shorten(body)}");
        }
        if (reply.ContainsKey("error"))
        {
            throw new McpException($"{name} failed: {reply["error"]?["message"]}");
        }
        var result = reply["result"];
        if (result?["content"]?[0]?["text"] is not JsonValue textValue ||
            !textValue.TryGetValue(out string? text))
        {
            throw new McpException($"{name} failed: unexpected result: {Shorten(body)}");
        }
        var failed = result["isError"] is JsonValue isError &&
            isError.TryGetValue(out bool flag) && flag;
        return (text, failed);
    }
    
    // Runs a SELECT with query_database, and prints the column names and each
    // row. The reply repeats the query, with the LIMIT that the server adds,
    // and then has a line such as "Results (3 rows):", a header line, and one
    // line for each row, with the values separated by tabs. The server writes
    // a tab or a newline inside a value as \t or \n, and a NULL as an empty
    // string.
    static async Task SelectCheapProductsAsync(HttpClient client)
    {
        var (text, failed) = await CallToolAsync(client, "query_database", new JsonObject
        {
            ["query"] = "SELECT name, price FROM cookbook_mcp.products "
                + "WHERE price < 100 ORDER BY price",
        });
        if (failed)
        {
            throw new McpException($"query_database failed: {text}");
        }
        var lines = text.Split('\n');
        var start = Array.FindIndex(lines, line => line.StartsWith("Results "));
        if (start < 0 || start + 1 >= lines.Length)
        {
            throw new McpException($"Unexpected reply: {Shorten(text)}");
        }
        Console.WriteLine($"Columns: {lines[start + 1].Replace("\t", ", ")}");
        foreach (var line in lines.Skip(start + 2).Where(line => line.Length > 0))
        {
            Console.WriteLine($"Row: {line.Replace("\t", ", ")}");
        }
    }
    
    // Tries to add a row. query_database runs every query in a read-only
    // transaction, so PostgreSQL itself refuses the INSERT with SQLSTATE
    // 25006, and the tool returns the error with isError set to true. The
    // INSERT leaves out id, which the table requires, so that even a server
    // that allows writes would refuse it rather than save a row. That is
    // why the function checks for the read-only error itself rather than
    // for any error, and fails if the write succeeds or fails for another
    // reason. It prints only the last line of the error, which holds
    // PostgreSQL's message, because some errors start with the query.
    static async Task TryInsertAsync(HttpClient client)
    {
        var (text, failed) = await CallToolAsync(client, "query_database", new JsonObject
        {
            ["query"] = "INSERT INTO cookbook_mcp.products "
                + "(name, category, price, in_stock, description) "
                + "VALUES ('Acme Test Widget', 'Testing', 1.00, true, "
                + "'A made-up product that is never saved')",
        });
        var errorLine = text.Trim().Split('\n')[^1];
        if (!failed)
        {
            throw new McpException("The server accepted a write");
        }
        if (!text.Contains("SQLSTATE 25006"))
        {
            throw new McpException($"The INSERT failed for another reason: {errorLine}");
        }
        Console.WriteLine($"INSERT rejected: {errorLine}");
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
        await SelectCheapProductsAsync(client);
        await TryInsertAsync(client);
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
    // Running read-only queries through the pgEdge Postgres MCP Server, using
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
    
    // callTool calls a tool with tools/call and returns the text of its reply
    // and whether the tool failed, which it reports by setting isError. The
    // server answers a JSON-RPC error with HTTP status 200, so the function
    // checks the reply for an error member as well as the HTTP status.
    func callTool(client *http.Client, name string, arguments map[string]any) (string, bool, error) {
    	payload, err := json.Marshal(map[string]any{
    		"jsonrpc": "2.0", "id": 1, "method": "tools/call",
    		"params": map[string]any{"name": name, "arguments": arguments},
    	})
    	if err != nil {
    		return "", false, err
    	}
    	request, err := http.NewRequest(http.MethodPost, baseURL+"/mcp/v1", bytes.NewReader(payload))
    	if err != nil {
    		return "", false, err
    	}
    	request.Header.Set("Authorization", "Bearer "+token)
    	request.Header.Set("Content-Type", "application/json")
    
    	response, err := client.Do(request)
    	if err != nil {
    		return "", false, err
    	}
    	defer response.Body.Close()
    	body, err := io.ReadAll(response.Body)
    	if err != nil {
    		return "", false, err
    	}
    	if response.StatusCode != http.StatusOK {
    		return "", false, fmt.Errorf("%s failed with HTTP %d: %s", name, response.StatusCode, shorten(body))
    	}
    	var reply struct {
    		Result *struct {
    			Content []struct {
    				Text string `json:"text"`
    			} `json:"content"`
    			IsError bool `json:"isError"`
    		} `json:"result"`
    		Error *struct {
    			Message string `json:"message"`
    		} `json:"error"`
    	}
    	if err := json.Unmarshal(body, &reply); err != nil || (reply.Result == nil && reply.Error == nil) {
    		return "", false, fmt.Errorf("%s failed: unexpected response: %s", name, shorten(body))
    	}
    	if reply.Error != nil {
    		return "", false, fmt.Errorf("%s failed: %s", name, reply.Error.Message)
    	}
    	if len(reply.Result.Content) == 0 {
    		return "", false, fmt.Errorf("%s failed: unexpected result: %s", name, shorten(body))
    	}
    	return reply.Result.Content[0].Text, reply.Result.IsError, nil
    }
    
    
    // selectCheapProducts runs a SELECT with query_database, and prints the
    // column names and each row. The reply repeats the query, with the LIMIT
    // that the server adds, and then has a line such as "Results (3 rows):", a
    // header line, and one line for each row, with the values separated by
    // tabs. The server writes a tab or a newline inside a value as \t or \n,
    // and a NULL as an empty string.
    func selectCheapProducts(client *http.Client) error {
    	text, failed, err := callTool(client, "query_database", map[string]any{
    		"query": "SELECT name, price FROM cookbook_mcp.products WHERE price < 100 ORDER BY price",
    	})
    	if err != nil {
    		return err
    	}
    	if failed {
    		return fmt.Errorf("query_database failed: %s", text)
    	}
    	lines := strings.Split(text, "\n")
    	start := -1
    	for i, line := range lines {
    		if strings.HasPrefix(line, "Results ") {
    			start = i
    			break
    		}
    	}
    	if start < 0 || start+1 >= len(lines) {
    		return fmt.Errorf("unexpected reply: %s", shorten([]byte(text)))
    	}
    	fmt.Printf("Columns: %s\n", strings.ReplaceAll(lines[start+1], "\t", ", "))
    	for _, line := range lines[start+2:] {
    		if line != "" {
    			fmt.Printf("Row: %s\n", strings.ReplaceAll(line, "\t", ", "))
    		}
    	}
    	return nil
    }
    
    
    // tryInsert tries to add a row. query_database runs every query in a
    // read-only transaction, so PostgreSQL itself refuses the INSERT with
    // SQLSTATE 25006, and the tool returns the error with isError set to true.
    // The INSERT leaves out id, which the table requires, so that even a server
    // that allows writes would refuse it rather than save a row. That is why
    // the function checks for the read-only error itself rather than for any
    // error, and fails if the write succeeds or fails for another reason. It
    // prints only the last line of the error, which holds PostgreSQL's
    // message, because some errors start with the query.
    func tryInsert(client *http.Client) error {
    	text, failed, err := callTool(client, "query_database", map[string]any{
    		"query": "INSERT INTO cookbook_mcp.products " +
    			"(name, category, price, in_stock, description) " +
    			"VALUES ('Acme Test Widget', 'Testing', 1.00, true, " +
    			"'A made-up product that is never saved')",
    	})
    	if err != nil {
    		return err
    	}
    	lines := strings.Split(strings.TrimSpace(text), "\n")
    	errorLine := lines[len(lines)-1]
    	if !failed {
    		return errors.New("the server accepted a write")
    	}
    	if !strings.Contains(text, "SQLSTATE 25006") {
    		return fmt.Errorf("the INSERT failed for another reason: %s", errorLine)
    	}
    	fmt.Printf("INSERT rejected: %s\n", errorLine)
    	return nil
    }
    
    
    // run makes the two calls and returns any error to the caller.
    func run() error {
    	if token == "" {
    		return errors.New("MCP_TOKEN must be set")
    	}
    	client := &http.Client{Timeout: timeout}
    	if err := selectCheapProducts(client); err != nil {
    		return err
    	}
    	return tryInsert(client)
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
    // Running read-only queries through the pgEdge Postgres MCP Server, using
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
    
    /// Calls a tool with tools/call and returns the text of its reply and
    /// whether the tool failed, which it reports by setting isError. The
    /// server answers a JSON-RPC error with HTTP status 200, so the function
    /// checks the reply for an error member as well as the HTTP status.
    fn call_tool(client: &Client, name: &str, arguments: Value) -> Result<(String, bool), BoxError> {
        let message = json!({
            "jsonrpc": "2.0", "id": 1, "method": "tools/call",
            "params": {"name": name, "arguments": arguments},
        });
        let response = client
            .post(format!("{}/mcp/v1", base_url()))
            .bearer_auth(token())
            .json(&message)
            .send()?;
        let status = response.status().as_u16();
        let body = response.text()?;
        if status != 200 {
            return Err(format!("{name} failed with HTTP {status}: {}", shorten(&body)).into());
        }
        let reply = match serde_json::from_str::<Value>(&body) {
            Ok(reply) if reply.get("result").is_some() || reply.get("error").is_some() => reply,
            _ => return Err(format!("{name} failed: unexpected response: {}", shorten(&body)).into()),
        };
        if let Some(error) = reply.get("error") {
            let message = error["message"].as_str().unwrap_or("unknown error");
            return Err(format!("{name} failed: {message}").into());
        }
        let result = &reply["result"];
        let Some(text) = result["content"][0]["text"].as_str() else {
            return Err(format!("{name} failed: unexpected result: {}", shorten(&body)).into());
        };
        Ok((text.to_string(), result["isError"].as_bool() == Some(true)))
    }
    
    /// Runs a SELECT with query_database, and prints the column names and each
    /// row. The reply repeats the query, with the LIMIT that the server adds,
    /// and then has a line such as "Results (3 rows):", a header line, and one
    /// line for each row, with the values separated by tabs. The server writes
    /// a tab or a newline inside a value as \t or \n, and a NULL as an empty
    /// string.
    fn select_cheap_products(client: &Client) -> Result<(), BoxError> {
        let (text, failed) = call_tool(
            client,
            "query_database",
            json!({
                "query": "SELECT name, price FROM cookbook_mcp.products \
                          WHERE price < 100 ORDER BY price",
            }),
        )?;
        if failed {
            return Err(format!("query_database failed: {text}").into());
        }
        let mut lines = text.split('\n').skip_while(|line| !line.starts_with("Results "));
        let (Some(_), Some(header)) = (lines.next(), lines.next()) else {
            return Err(format!("Unexpected reply: {}", shorten(&text)).into());
        };
        println!("Columns: {}", header.replace('\t', ", "));
        for line in lines.filter(|line| !line.is_empty()) {
            println!("Row: {}", line.replace('\t', ", "));
        }
        Ok(())
    }
    
    /// Tries to add a row. query_database runs every query in a read-only
    /// transaction, so PostgreSQL itself refuses the INSERT with SQLSTATE
    /// 25006, and the tool returns the error with isError set to true. The
    /// INSERT leaves out id, which the table requires, so that even a server
    /// that allows writes would refuse it rather than save a row. That is
    /// why the function checks for the read-only error itself rather than
    /// for any error, and fails if the write succeeds or fails for another
    /// reason. It prints only the last line of the error, which holds
    /// PostgreSQL's message, because some errors start with the query.
    fn try_insert(client: &Client) -> Result<(), BoxError> {
        let (text, failed) = call_tool(
            client,
            "query_database",
            json!({
                "query": "INSERT INTO cookbook_mcp.products \
                          (name, category, price, in_stock, description) \
                          VALUES ('Acme Test Widget', 'Testing', 1.00, true, \
                          'A made-up product that is never saved')",
            }),
        )?;
        let error_line = text.trim().lines().last().unwrap_or("");
        if !failed {
            return Err("The server accepted a write".into());
        }
        if !text.contains("SQLSTATE 25006") {
            return Err(format!("The INSERT failed for another reason: {error_line}").into());
        }
        println!("INSERT rejected: {error_line}");
        Ok(())
    }
    
    /// Makes the two calls. The ? operator returns any error to the caller.
    fn run() -> Result<(), BoxError> {
        if token().is_empty() {
            return Err("MCP_TOKEN must be set".into());
        }
        let client = Client::builder().timeout(TIMEOUT).build()?;
        select_cheap_products(&client)?;
        try_insert(&client)
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
    # Running read-only queries through the pgEdge Postgres MCP Server, using
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
    
    # Calls a tool with tools/call and returns the text of its reply and
    # whether the tool failed, which it reports by setting isError. The server
    # answers a JSON-RPC error with HTTP status 200, so the method checks the
    # reply for an error member as well as the HTTP status.
    def call_tool(http, name, arguments)
      request = Net::HTTP::Post.new(URI("#{BASE_URL}/mcp/v1"))
      request["Authorization"] = "Bearer #{TOKEN}"
      request["Content-Type"] = "application/json"
      request.body = JSON.generate({ jsonrpc: "2.0", id: 1, method: "tools/call",
                                     params: { name: name, arguments: arguments } })
      response = http.request(request)
      unless response.code == "200"
        raise McpError, "#{name} failed with HTTP #{response.code}: #{response.body.to_s[0, 200]}"
      end
    
      reply = parse_object(response.body)
      unless reply && (reply.key?("result") || reply.key?("error"))
        raise McpError, "#{name} failed: unexpected response: #{response.body.to_s[0, 200]}"
      end
      raise McpError, "#{name} failed: #{reply["error"]["message"]}" if reply.key?("error")
    
      result = reply["result"]
      text = result.is_a?(Hash) ? result.dig("content", 0, "text") : nil
      raise McpError, "#{name} failed: unexpected result: #{response.body.to_s[0, 200]}" unless text.is_a?(String)
    
      [text, result["isError"] == true]
    end
    
    # Runs a SELECT with query_database, and prints the column names and each
    # row. The reply repeats the query, with the LIMIT that the server adds,
    # and then has a line such as "Results (3 rows):", a header line, and one
    # line for each row, with the values separated by tabs. The server writes a
    # tab or a newline inside a value as \t or \n, and a NULL as an empty
    # string.
    def select_cheap_products(http)
      text, failed = call_tool(http, "query_database", {
                                 query: "SELECT name, price FROM cookbook_mcp.products " \
                                        "WHERE price < 100 ORDER BY price"
                               })
      raise McpError, "query_database failed: #{text}" if failed
    
      lines = text.split("\n")
      start = lines.index { |line| line.start_with?("Results ") }
      raise McpError, "Unexpected reply: #{text[0, 200]}" if start.nil? || start + 1 >= lines.length
    
      puts "Columns: #{lines[start + 1].gsub("\t", ", ")}"
      lines[(start + 2)..].reject(&:empty?).each do |line|
        puts "Row: #{line.gsub("\t", ", ")}"
      end
    end
    
    # Tries to add a row. query_database runs every query in a read-only
    # transaction, so PostgreSQL itself refuses the INSERT with SQLSTATE
    # 25006, and the tool returns the error with isError set to true. The
    # INSERT leaves out id, which the table requires, so that even a server
    # that allows writes would refuse it rather than save a row. That is
    # why the method checks for the read-only error itself rather than
    # for any error, and fails if the write succeeds or fails for another
    # reason. It prints only the last line of the error, which holds
    # PostgreSQL's message, because some errors start with the query.
    def try_insert(http)
      text, failed = call_tool(http, "query_database", {
                                 query: "INSERT INTO cookbook_mcp.products " \
                                        "(name, category, price, in_stock, description) " \
                                        "VALUES ('Acme Test Widget', 'Testing', 1.00, true, " \
                                        "'A made-up product that is never saved')"
                               })
      error_line = text.strip.split("\n").last.to_s
      raise McpError, "The server accepted a write" unless failed
      unless text.include?("SQLSTATE 25006")
        raise McpError, "The INSERT failed for another reason: #{error_line}"
      end
    
      puts "INSERT rejected: #{error_line}"
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
        select_cheap_products(http)
        try_insert(http)
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
    # Running read-only queries through the pgEdge Postgres MCP Server, using
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
    
    # Calls a tool with tools/call and prints its result, which holds the text
    # of the reply in content[0].text and, if the tool failed, isError set to
    # true: call_tool NAME ARGUMENTS_JSON. The server answers a JSON-RPC error
    # with HTTP status 200, so the function checks the reply for an error
    # member as well as the HTTP status. The token goes to curl in a header
    # file that bash supplies through a pipe, so that it never appears in the
    # arguments of the curl process, which other users can read in the process
    # list.
    call_tool() {
        local name="$1" request reply status body
        request=$(jq -nc --arg name "$name" --argjson arguments "$2" \
            '{jsonrpc: "2.0", id: 1, method: "tools/call",
              params: {name: $name, arguments: $arguments}}')
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
            echo "$name failed with HTTP $status: ${body:0:200}" >&2
            return 1
        fi
        if ! jq -e '.result.content[0].text or has("error")' >/dev/null 2>&1 \
            <<<"$body"; then
            echo "$name failed: unexpected response: ${body:0:200}" >&2
            return 1
        fi
        if jq -e 'has("error")' >/dev/null <<<"$body"; then
            echo "$name failed: $(jq -r '.error.message' <<<"$body")" >&2
            return 1
        fi
        jq -c '.result' <<<"$body"
    }
    
    # Runs a SELECT with query_database, and prints the column names and each
    # row. The reply repeats the query, with the LIMIT that the server adds,
    # and then has a line such as "Results (3 rows):", a header line, and one
    # line for each row, with the values separated by tabs. The server writes
    # a tab or a newline inside a value as \t or \n, and a NULL as an empty
    # string.
    select_cheap_products() {
        local query result
        query="SELECT name, price FROM cookbook_mcp.products
               WHERE price < 100 ORDER BY price"
        result=$(call_tool query_database \
            "$(jq -nc --arg query "$query" '{query: $query}')") || return 1
        if jq -e '.isError == true' >/dev/null <<<"$result"; then
            echo "query_database failed: $(jq -r '.content[0].text' <<<"$result")" >&2
            return 1
        fi
        jq -r '
            .content[0].text | split("\n") as $lines
            | ($lines | map(startswith("Results ")) | index(true)) as $start
            | if $start == null or $start + 1 >= ($lines | length)
              then error("The reply had no results") else . end
            | "Columns: \($lines[$start + 1] | split("\t") | join(", "))",
              ($lines[$start + 2:][] | select(. != "")
               | "Row: \(split("\t") | join(", "))")' <<<"$result" || {
            echo "Unexpected reply: $(jq -r '.content[0].text' <<<"$result" | head -c 200)" >&2
            return 1
        }
    }
    
    # Tries to add a row. query_database runs every query in a read-only
    # transaction, so PostgreSQL itself refuses the INSERT with SQLSTATE
    # 25006, and the tool returns the error with isError set to true. The
    # INSERT leaves out id, which the table requires, so that even a server
    # that allows writes would refuse it rather than save a row. That is
    # why the script checks for the read-only error itself rather than
    # for any error, and fails if the write succeeds or fails for another
    # reason. It prints only the last line of the error, which holds
    # PostgreSQL's message, because some errors start with the query.
    try_insert() {
        local query result text error_line
        query="INSERT INTO cookbook_mcp.products
                   (name, category, price, in_stock, description)
               VALUES ('Acme Test Widget', 'Testing', 1.00, true,
                       'A made-up product that is never saved')"
        result=$(call_tool query_database \
            "$(jq -nc --arg query "$query" '{query: $query}')") || return 1
        if ! jq -e '.isError == true' >/dev/null <<<"$result"; then
            echo "The server accepted a write" >&2
            return 1
        fi
        text=$(jq -r '.content[0].text' <<<"$result")
        error_line="${text##*$'\n'}"
        if [[ "$text" != *"SQLSTATE 25006"* ]]; then
            echo "The INSERT failed for another reason: $error_line" >&2
            return 1
        fi
        echo "INSERT rejected: $error_line"
    }
    
    main() {
        select_cheap_products
        try_insert
    }
    
    main
    
    ```

## Next Steps

The following resources provide more information about the topics in this
recipe:

- The [Exploring a Schema](explore_schema.md) recipe lists the tables and
  columns of a schema.
- The [Searching by Meaning](similarity_search.md) recipe finds the rows whose
  text is closest in meaning to a question.
- The [Calling AI DBA Workbench MCP Tools](../ai_dba_workbench/mcp_tools.md)
  recipe calls the same kind of tools through the AI DBA Workbench.
- The
  [pgEdge Postgres MCP Server documentation](https://docs.pgedge.com/pgedge-postgres-mcp-server/)
  describes every tool, resource and setting.
- The [Contributing a Recipe](../contributing.md) page explains how to add a
  recipe or a language to the cookbook.
