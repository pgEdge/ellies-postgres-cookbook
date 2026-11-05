# Exploring a Schema

This recipe uses the tools of a pgEdge Postgres MCP Server to find out what a
database holds: it lists the tables in a schema with their comments, lists the
columns of one table with their types, and counts the rows that match a
condition. These are the tools that an AI assistant uses to learn about a
database before it writes a query. Each step shows the code in every supported
language; selecting a language tab switches every tab on the site to that
language.

These examples are for pgEdge Postgres MCP Server 1.1.0.

The program prints the following output:

```text
Tables in cookbook_mcp:
- products: Made-up products for the pgEdge Postgres MCP Server recipes
Columns of cookbook_mcp.products:
- category: text
- description: text
- description_embedding: vector(768)
- id: integer (primary key)
- in_stock: boolean
- name: text
- price: numeric(8,2)
Products in stock: 4
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
      "name": "explore-schema",
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
    import re
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
    import java.util.HashMap;
    import java.util.List;
    import java.util.Map;
    import java.util.concurrent.CompletableFuture;
    import java.util.concurrent.ExecutionException;
    import java.util.concurrent.TimeUnit;
    import java.util.concurrent.TimeoutException;
    import java.util.regex.Matcher;
    import java.util.regex.Pattern;
    
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
    	"strings"
    	"time"
    )
    
    ```

=== "Rust"

    ```rust
    use std::collections::HashMap;
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
so the helper checks that too.

The program also names the schema and the table that it explores.

The following tabs show how each program reads its settings, and how it calls a
tool:

=== "Python"

    ```python
    # The or operator treats an empty variable as unset.
    BASE_URL = (os.environ.get("MCP_URL") or "http://localhost:8080").rstrip("/")
    TOKEN = os.environ.get("MCP_TOKEN") or ""
    
    TIMEOUT_SECONDS = 30
    
    # The schema and table that scripts/start_postgres_mcp.sh creates.
    SCHEMA = "cookbook_mcp"
    TABLE = "products"
    
    
    class McpError(Exception):
        """Raised when the MCP Server rejects a request or replies oddly."""
    
    
    def call_tool(client: httpx.Client, name: str, arguments: dict) -> str:
        """Calls a tool with tools/call and returns the text of its reply.
    
        The server answers a JSON-RPC error with HTTP status 200, and a tool
        that fails returns a normal result with isError set, so the function
        checks for both as well as the HTTP status.
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
        text = result["content"][0]["text"]
        if result.get("isError"):
            raise McpError(f"{name} failed: {text}")
        return text
    ```

=== "TypeScript"

    ```typescript
    // The || operator, unlike ??, also treats an empty variable as unset.
    const baseUrl = (process.env.MCP_URL || "http://localhost:8080").replace(/\/+$/, "");
    const token = process.env.MCP_TOKEN || "";
    
    const timeoutMs = 30_000;
    
    // The schema and table that scripts/start_postgres_mcp.sh creates.
    const schema = "cookbook_mcp";
    const table = "products";
    
    // Calls a tool with tools/call and returns the text of its reply. The
    // server answers a JSON-RPC error with HTTP status 200, and a tool that
    // fails returns a normal result with isError set, so the function checks
    // for both as well as the HTTP status.
    async function callTool(name: string, args: object): Promise<string> {
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
      const text = await response.text();
      if (response.status !== 200) {
        throw new Error(`${name} failed with HTTP ${response.status}: ${text.slice(0, 200)}`);
      }
      let reply: any;
      try {
        reply = JSON.parse(text);
      } catch {
        reply = undefined;
      }
      if (typeof reply !== "object" || reply === null || !("result" in reply || "error" in reply)) {
        throw new Error(`${name} failed: unexpected response: ${text.slice(0, 200)}`);
      }
      if ("error" in reply) {
        throw new Error(`${name} failed: ${reply.error?.message}`);
      }
      const content = reply.result?.content?.[0]?.text;
      if (typeof content !== "string") {
        throw new Error(`${name} failed: unexpected result: ${text.slice(0, 200)}`);
      }
      if (reply.result.isError) {
        throw new Error(`${name} failed: ${content}`);
      }
      return content;
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
    
    // The schema and table that scripts/start_postgres_mcp.sh creates.
    static final String SCHEMA = "cookbook_mcp";
    static final String TABLE = "products";
    
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
     * Calls a tool with tools/call and returns the text of its reply. The
     * server answers a JSON-RPC error with HTTP status 200, and a tool that
     * fails returns a normal result with isError set, so the method checks
     * for both as well as the HTTP status.
     */
    static String callTool(String name, Map<String, Object> arguments)
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
        if (result.path("isError").asBoolean(false)) {
            throw new McpException(name + " failed: " + text.stringValue());
        }
        return text.stringValue();
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
    
    // The schema and table that scripts/start_postgres_mcp.sh creates.
    const string Schema = "cookbook_mcp";
    const string Table = "products";
    
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
    
    // Calls a tool with tools/call and returns the text of its reply. The
    // server answers a JSON-RPC error with HTTP status 200, and a tool that
    // fails returns a normal result with isError set, so the function checks
    // for both as well as the HTTP status.
    static async Task<string> CallToolAsync(HttpClient client, string name, JsonObject arguments)
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
        if (result["isError"] is JsonValue isError &&
            isError.TryGetValue(out bool failed) && failed)
        {
            throw new McpException($"{name} failed: {text}");
        }
        return text;
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
    
    // The schema and table that scripts/start_postgres_mcp.sh creates.
    const (
    	schema = "cookbook_mcp"
    	table  = "products"
    )
    
    // shorten returns at most the first 200 bytes of a reply.
    func shorten(body []byte) string {
    	if len(body) > 200 {
    		body = body[:200]
    	}
    	return string(body)
    }
    
    // callTool calls a tool with tools/call and returns the text of its
    // reply. The server answers a JSON-RPC error with HTTP status 200, and a
    // tool that fails returns a normal result with isError set, so the
    // function checks for both as well as the HTTP status.
    func callTool(client *http.Client, name string, arguments map[string]any) (string, error) {
    	payload, err := json.Marshal(map[string]any{
    		"jsonrpc": "2.0", "id": 1, "method": "tools/call",
    		"params": map[string]any{"name": name, "arguments": arguments},
    	})
    	if err != nil {
    		return "", err
    	}
    	request, err := http.NewRequest(http.MethodPost, baseURL+"/mcp/v1", bytes.NewReader(payload))
    	if err != nil {
    		return "", err
    	}
    	request.Header.Set("Authorization", "Bearer "+token)
    	request.Header.Set("Content-Type", "application/json")
    
    	response, err := client.Do(request)
    	if err != nil {
    		return "", err
    	}
    	defer response.Body.Close()
    	body, err := io.ReadAll(response.Body)
    	if err != nil {
    		return "", err
    	}
    	if response.StatusCode != http.StatusOK {
    		return "", fmt.Errorf("%s failed with HTTP %d: %s", name, response.StatusCode, shorten(body))
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
    		return "", fmt.Errorf("%s failed: unexpected response: %s", name, shorten(body))
    	}
    	if reply.Error != nil {
    		return "", fmt.Errorf("%s failed: %s", name, reply.Error.Message)
    	}
    	if len(reply.Result.Content) == 0 {
    		return "", fmt.Errorf("%s failed: unexpected result: %s", name, shorten(body))
    	}
    	text := reply.Result.Content[0].Text
    	if reply.Result.IsError {
    		return "", fmt.Errorf("%s failed: %s", name, text)
    	}
    	return text, nil
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
    
    // The schema and table that scripts/start_postgres_mcp.sh creates.
    const SCHEMA: &str = "cookbook_mcp";
    const TABLE: &str = "products";
    
    /// The errors that the functions below return; a string converts into one
    /// with the ? operator or into().
    type BoxError = Box<dyn Error>;
    
    /// Returns at most the first 200 characters of a reply.
    fn shorten(text: &str) -> String {
        text.chars().take(200).collect()
    }
    
    /// Calls a tool with tools/call and returns the text of its reply. The
    /// server answers a JSON-RPC error with HTTP status 200, and a tool that
    /// fails returns a normal result with isError set, so the function checks
    /// for both as well as the HTTP status.
    fn call_tool(client: &Client, name: &str, arguments: Value) -> Result<String, BoxError> {
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
        if result["isError"].as_bool() == Some(true) {
            return Err(format!("{name} failed: {text}").into());
        }
        Ok(text.to_string())
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
    
    # The schema and table that scripts/start_postgres_mcp.sh creates.
    SCHEMA = "cookbook_mcp"
    TABLE = "products"
    
    # Raised when the MCP Server rejects a request or replies oddly.
    class McpError < StandardError; end
    
    # Parses a reply as a JSON object, or returns nil if it is not one.
    def parse_object(text)
      body = JSON.parse(text.to_s)
      body.is_a?(Hash) ? body : nil
    rescue JSON::ParserError
      nil
    end
    
    # Calls a tool with tools/call and returns the text of its reply. The
    # server answers a JSON-RPC error with HTTP status 200, and a tool that
    # fails returns a normal result with isError set, so the method checks for
    # both as well as the HTTP status.
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
      raise McpError, "#{name} failed: #{text}" if result["isError"]
    
      text
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
    
    # The schema and table that scripts/start_postgres_mcp.sh creates.
    SCHEMA=cookbook_mcp
    TABLE=products
    
    # Calls a tool with tools/call and prints the text of its reply:
    # call_tool NAME ARGUMENTS_JSON. The server answers a JSON-RPC error with
    # HTTP status 200, and a tool that fails returns a normal result with
    # isError set, so the function checks for both as well as the HTTP status.
    # The token goes to curl in a header file that bash supplies through a
    # pipe, so that it never appears in the arguments of the curl process,
    # which other users can read in the process list.
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
        if ! jq -e 'has("result") or has("error")' >/dev/null 2>&1 <<<"$body"; then
            echo "$name failed: unexpected response: ${body:0:200}" >&2
            return 1
        fi
        if jq -e 'has("error")' >/dev/null <<<"$body"; then
            echo "$name failed: $(jq -r '.error.message' <<<"$body")" >&2
            return 1
        fi
        if jq -e '.result.isError == true' >/dev/null <<<"$body"; then
            echo "$name failed: $(jq -r '.result.content[0].text' <<<"$body")" >&2
            return 1
        fi
        jq -r '.result.content[0].text' <<<"$body"
    }
    ```

## Reading the Tool Replies

The `get_schema_info` tool replies with a table as text: a line or two about
the database, then a header line and one line for each row, with the values
separated by tabs. The server writes a tab or a newline inside a value as `\t`
or `\n`, so splitting the text on them is safe. The parsing depends on the
layout of the text in version 1.1.0, so check it again after an upgrade. The
following tabs show how each program reads the table into rows:

=== "Python"

    ```python
    def parse_tsv(text: str) -> list[dict]:
        """Reads the table in a tool's reply into a list of rows, each a
        dictionary keyed by column name.
    
        The reply starts with a line or two about the database, and then has
        a header line and one line for each row, with the values separated by
        tabs. The server writes a tab or a newline inside a value as \\t or
        \\n, so splitting on them is safe. The header is the first line that
        starts with "schema", the first column of every table that
        get_schema_info returns.
        """
        lines = text.split("\n")
        start = next((i for i, line in enumerate(lines)
                      if line.startswith("schema\t")), None)
        if start is None:
            raise McpError(f"The reply had no table: {text[:200]}")
        header = lines[start].split("\t")
        return [dict(zip(header, line.split("\t")))
                for line in lines[start + 1:] if line]
    ```

=== "TypeScript"

    ```typescript
    // Reads the table in a tool's reply into a list of rows, each an object
    // keyed by column name. The reply starts with a line or two about the
    // database, and then has a header line and one line for each row, with
    // the values separated by tabs. The server writes a tab or a newline
    // inside a value as \t or \n, so splitting on them is safe. The header is
    // the first line that starts with "schema", the first column of every
    // table that get_schema_info returns.
    function parseTsv(text: string): Record<string, string>[] {
      const lines = text.split("\n");
      const start = lines.findIndex((line) => line.startsWith("schema\t"));
      if (start < 0) {
        throw new Error(`The reply had no table: ${text.slice(0, 200)}`);
      }
      const header = lines[start].split("\t");
      return lines
        .slice(start + 1)
        .filter((line) => line !== "")
        .map((line) => {
          const values = line.split("\t");
          return Object.fromEntries(header.map((name, i) => [name, values[i] ?? ""]));
        });
    }
    ```

=== "Java"

    ```java
    /**
     * Reads the table in a tool's reply into a list of rows, each a map
     * keyed by column name. The reply starts with a line or two about the
     * database, and then has a header line and one line for each row, with
     * the values separated by tabs. The server writes a tab or a newline
     * inside a value as \t or \n, so splitting on them is safe. The header
     * is the first line that starts with "schema", the first column of
     * every table that get_schema_info returns.
     */
    static List<Map<String, String>> parseTsv(String text) throws McpException {
        // A limit of -1 keeps empty strings at the end, such as an empty
        // last column.
        String[] lines = text.split("\n", -1);
        int start = -1;
        for (int i = 0; i < lines.length; i++) {
            if (lines[i].startsWith("schema\t")) {
                start = i;
                break;
            }
        }
        if (start < 0) {
            throw new McpException("The reply had no table: " + shorten(text));
        }
        String[] header = lines[start].split("\t", -1);
        List<Map<String, String>> rows = new ArrayList<>();
        for (int i = start + 1; i < lines.length; i++) {
            if (lines[i].isEmpty()) {
                continue;
            }
            String[] values = lines[i].split("\t", -1);
            Map<String, String> row = new HashMap<>();
            for (int j = 0; j < header.length && j < values.length; j++) {
                row.put(header[j], values[j]);
            }
            rows.add(row);
        }
        return rows;
    }
    ```

=== "C#"

    ```csharp
    // Reads the table in a tool's reply into a list of rows, each a dictionary
    // keyed by column name. The reply starts with a line or two about the
    // database, and then has a header line and one line for each row, with the
    // values separated by tabs. The server writes a tab or a newline inside a
    // value as \t or \n, so splitting on them is safe. The header is the first
    // line that starts with "schema", the first column of every table that
    // get_schema_info returns.
    static List<Dictionary<string, string>> ParseTsv(string text)
    {
        var lines = text.Split('\n');
        var start = Array.FindIndex(lines, line => line.StartsWith("schema\t"));
        if (start < 0)
        {
            throw new McpException($"The reply had no table: {Shorten(text)}");
        }
        var header = lines[start].Split('\t');
        var rows = new List<Dictionary<string, string>>();
        foreach (var line in lines.Skip(start + 1).Where(line => line.Length > 0))
        {
            var values = line.Split('\t');
            rows.Add(header.Zip(values).ToDictionary(pair => pair.First, pair => pair.Second));
        }
        return rows;
    }
    ```

=== "Go"

    ```go
    // parseTsv reads the table in a tool's reply into a list of rows, each a
    // map keyed by column name. The reply starts with a line or two about the
    // database, and then has a header line and one line for each row, with
    // the values separated by tabs. The server writes a tab or a newline
    // inside a value as \t or \n, so splitting on them is safe. The header is
    // the first line that starts with "schema", the first column of every
    // table that get_schema_info returns.
    func parseTsv(text string) ([]map[string]string, error) {
    	lines := strings.Split(text, "\n")
    	start := -1
    	for i, line := range lines {
    		if strings.HasPrefix(line, "schema\t") {
    			start = i
    			break
    		}
    	}
    	if start < 0 {
    		return nil, fmt.Errorf("the reply had no table: %s", shorten([]byte(text)))
    	}
    	header := strings.Split(lines[start], "\t")
    	var rows []map[string]string
    	for _, line := range lines[start+1:] {
    		if line == "" {
    			continue
    		}
    		values := strings.Split(line, "\t")
    		row := make(map[string]string, len(header))
    		for i, name := range header {
    			if i < len(values) {
    				row[name] = values[i]
    			}
    		}
    		rows = append(rows, row)
    	}
    	return rows, nil
    }
    
    ```

=== "Rust"

    ```rust
    /// Reads the table in a tool's reply into a list of rows, each a map keyed
    /// by column name. The reply starts with a line or two about the database,
    /// and then has a header line and one line for each row, with the values
    /// separated by tabs. The server writes a tab or a newline inside a value
    /// as \t or \n, so splitting on them is safe. The header is the first line
    /// that starts with "schema", the first column of every table that
    /// get_schema_info returns.
    fn parse_tsv(text: &str) -> Result<Vec<HashMap<String, String>>, BoxError> {
        let mut lines = text.split('\n').skip_while(|line| !line.starts_with("schema\t"));
        let Some(header) = lines.next() else {
            return Err(format!("The reply had no table: {}", shorten(text)).into());
        };
        let header: Vec<&str> = header.split('\t').collect();
        Ok(lines
            .filter(|line| !line.is_empty())
            .map(|line| {
                header
                    .iter()
                    .zip(line.split('\t'))
                    .map(|(name, value)| (name.to_string(), value.to_string()))
                    .collect()
            })
            .collect())
    }
    
    /// Returns a column of a row, or an empty string if the row lacks it.
    fn column<'a>(row: &'a HashMap<String, String>, name: &str) -> &'a str {
        row.get(name).map(String::as_str).unwrap_or("")
    }
    ```

=== "Ruby"

    ```ruby
    # Reads the table in a tool's reply into a list of rows, each a hash keyed
    # by column name. The reply starts with a line or two about the database,
    # and then has a header line and one line for each row, with the values
    # separated by tabs. The server writes a tab or a newline inside a value as
    # \t or \n, so splitting on them is safe. The header is the first line that
    # starts with "schema", the first column of every table that
    # get_schema_info returns.
    def parse_tsv(text)
      lines = text.split("\n")
      start = lines.index { |line| line.start_with?("schema\t") }
      raise McpError, "The reply had no table: #{text[0, 200]}" if start.nil?
    
      # A limit of -1 keeps empty strings at the end, such as an empty last
      # column.
      header = lines[start].split("\t", -1)
      lines[(start + 1)..].reject(&:empty?).map do |line|
        header.zip(line.split("\t", -1)).to_h
      end
    end
    ```

=== "curl"

    ```bash
    # Reads the table in a tool's reply from standard input, and prints each
    # row as a JSON object keyed by column name. The reply starts with a line
    # or two about the database, and then has a header line and one line for
    # each row, with the values separated by tabs. The server writes a tab or a
    # newline inside a value as \t or \n, so splitting on them is safe. The
    # header is the first line that starts with "schema", the first column of
    # every table that get_schema_info returns.
    parse_tsv() {
        jq -Rsc '
            split("\n") as $lines
            | ($lines | map(startswith("schema\t")) | index(true)) as $start
            | if $start == null then error("The reply had no table") else . end
            | ($lines[$start] | split("\t")) as $header
            | $lines[$start + 1:][]
            | select(. != "")
            | [$header, split("\t")] | transpose
            | map({key: .[0], value: .[1]}) | from_entries'
    }
    ```

## Listing the Tables

With `compact` set to `true`, `get_schema_info` returns one line for each table
in the schema named by `schema_name`, with its type and its comment but without
its columns, which suits a first look at a large database. The following tabs
show how each program lists the tables:

=== "Python"

    ```python
    def list_tables(client: httpx.Client) -> None:
        """Lists the tables in the schema with their comments. With compact set
        to true, get_schema_info returns one line for each table, without its
        columns, which suits a first look at a large database."""
        text = call_tool(client, "get_schema_info",
                         {"schema_name": SCHEMA, "compact": True})
        print(f"Tables in {SCHEMA}:")
        for row in parse_tsv(text):
            print(f"- {row['table']}: {row.get('table_desc') or '(no comment)'}")
    ```

=== "TypeScript"

    ```typescript
    // Lists the tables in the schema with their comments. With compact set to
    // true, get_schema_info returns one line for each table, without its
    // columns, which suits a first look at a large database.
    async function listTables(): Promise<void> {
      const text = await callTool("get_schema_info", { schema_name: schema, compact: true });
      console.log(`Tables in ${schema}:`);
      for (const row of parseTsv(text)) {
        console.log(`- ${row.table}: ${row.table_desc || "(no comment)"}`);
      }
    }
    ```

=== "Java"

    ```java
    /**
     * Lists the tables in the schema with their comments. With compact set
     * to true, get_schema_info returns one line for each table, without its
     * columns, which suits a first look at a large database.
     */
    static void listTables() throws IOException, InterruptedException, McpException {
        String text = callTool("get_schema_info",
                Map.of("schema_name", SCHEMA, "compact", true));
        System.out.println("Tables in " + SCHEMA + ":");
        for (Map<String, String> row : parseTsv(text)) {
            String comment = row.getOrDefault("table_desc", "");
            System.out.println("- " + row.get("table") + ": "
                    + (comment.isEmpty() ? "(no comment)" : comment));
        }
    }
    ```

=== "C#"

    ```csharp
    // Lists the tables in the schema with their comments. With compact set to
    // true, get_schema_info returns one line for each table, without its
    // columns, which suits a first look at a large database.
    static async Task ListTablesAsync(HttpClient client)
    {
        var text = await CallToolAsync(client, "get_schema_info", new JsonObject
        {
            ["schema_name"] = Schema,
            ["compact"] = true,
        });
        Console.WriteLine($"Tables in {Schema}:");
        foreach (var row in ParseTsv(text))
        {
            var comment = row.GetValueOrDefault("table_desc");
            Console.WriteLine(
                $"- {row["table"]}: {(string.IsNullOrEmpty(comment) ? "(no comment)" : comment)}");
        }
    }
    ```

=== "Go"

    ```go
    // listTables lists the tables in the schema with their comments. With
    // compact set to true, get_schema_info returns one line for each table,
    // without its columns, which suits a first look at a large database.
    func listTables(client *http.Client) error {
    	text, err := callTool(client, "get_schema_info",
    		map[string]any{"schema_name": schema, "compact": true})
    	if err != nil {
    		return err
    	}
    	fmt.Printf("Tables in %s:\n", schema)
    	rows, err := parseTsv(text)
    	if err != nil {
    		return err
    	}
    	for _, row := range rows {
    		comment := row["table_desc"]
    		if comment == "" {
    			comment = "(no comment)"
    		}
    		fmt.Printf("- %s: %s\n", row["table"], comment)
    	}
    	return nil
    }
    
    ```

=== "Rust"

    ```rust
    /// Lists the tables in the schema with their comments. With compact set to
    /// true, get_schema_info returns one line for each table, without its
    /// columns, which suits a first look at a large database.
    fn list_tables(client: &Client) -> Result<(), BoxError> {
        let text = call_tool(
            client,
            "get_schema_info",
            json!({"schema_name": SCHEMA, "compact": true}),
        )?;
        println!("Tables in {SCHEMA}:");
        for row in parse_tsv(&text)? {
            let comment = match column(&row, "table_desc") {
                "" => "(no comment)",
                comment => comment,
            };
            println!("- {}: {comment}", column(&row, "table"));
        }
        Ok(())
    }
    ```

=== "Ruby"

    ```ruby
    # Lists the tables in the schema with their comments. With compact set to
    # true, get_schema_info returns one line for each table, without its
    # columns, which suits a first look at a large database.
    def list_tables(http)
      text = call_tool(http, "get_schema_info", { schema_name: SCHEMA, compact: true })
      puts "Tables in #{SCHEMA}:"
      parse_tsv(text).each do |row|
        comment = row["table_desc"].to_s
        puts "- #{row["table"]}: #{comment.empty? ? "(no comment)" : comment}"
      end
    end
    ```

=== "curl"

    ```bash
    # Lists the tables in the schema with their comments. With compact set to
    # true, get_schema_info returns one line for each table, without its
    # columns, which suits a first look at a large database.
    list_tables() {
        local text rows
        text=$(call_tool get_schema_info \
            "{\"schema_name\": \"$SCHEMA\", \"compact\": true}") || return 1
        echo "Tables in $SCHEMA:"
        rows=$(parse_tsv <<<"$text") || return 1
        jq -r '"- \(.table): \(if (.table_desc // "") == "" then "(no comment)"
                              else .table_desc end)"' <<<"$rows"
    }
    ```

## Describing a Table

Given a `table_name` as well, `get_schema_info` returns one line for each
column of that table, in alphabetical order, with its data type and whether it
is part of the primary key. The following tabs show how each program lists the
columns:

=== "Python"

    ```python
    def describe_table(client: httpx.Client) -> None:
        """Lists the columns of one table with their types. Given a table_name,
        get_schema_info returns one line for each column, which also carries
        the table's details."""
        text = call_tool(client, "get_schema_info",
                         {"schema_name": SCHEMA, "table_name": TABLE})
        rows = parse_tsv(text)
        if not rows:
            raise McpError(f"{SCHEMA}.{TABLE} has no columns")
        print(f"Columns of {SCHEMA}.{TABLE}:")
        for row in rows:
            key = " (primary key)" if row.get("is_pk") == "true" else ""
            print(f"- {row['column']}: {row['data_type']}{key}")
    ```

=== "TypeScript"

    ```typescript
    // Lists the columns of one table with their types. Given a table_name,
    // get_schema_info returns one line for each column, which also carries
    // the table's details.
    async function describeTable(): Promise<void> {
      const text = await callTool("get_schema_info", { schema_name: schema, table_name: table });
      const rows = parseTsv(text);
      if (rows.length === 0) {
        throw new Error(`${schema}.${table} has no columns`);
      }
      console.log(`Columns of ${schema}.${table}:`);
      for (const row of rows) {
        const key = row.is_pk === "true" ? " (primary key)" : "";
        console.log(`- ${row.column}: ${row.data_type}${key}`);
      }
    }
    ```

=== "Java"

    ```java
    /**
     * Lists the columns of one table with their types. Given a table_name,
     * get_schema_info returns one line for each column, which also carries
     * the table's details.
     */
    static void describeTable() throws IOException, InterruptedException, McpException {
        String text = callTool("get_schema_info",
                Map.of("schema_name", SCHEMA, "table_name", TABLE));
        List<Map<String, String>> rows = parseTsv(text);
        if (rows.isEmpty()) {
            throw new McpException(SCHEMA + "." + TABLE + " has no columns");
        }
        System.out.println("Columns of " + SCHEMA + "." + TABLE + ":");
        for (Map<String, String> row : rows) {
            String key = "true".equals(row.get("is_pk")) ? " (primary key)" : "";
            System.out.println("- " + row.get("column") + ": " + row.get("data_type") + key);
        }
    }
    ```

=== "C#"

    ```csharp
    // Lists the columns of one table with their types. Given a table_name,
    // get_schema_info returns one line for each column, which also carries the
    // table's details.
    static async Task DescribeTableAsync(HttpClient client)
    {
        var text = await CallToolAsync(client, "get_schema_info", new JsonObject
        {
            ["schema_name"] = Schema,
            ["table_name"] = Table,
        });
        var rows = ParseTsv(text);
        if (rows.Count == 0)
        {
            throw new McpException($"{Schema}.{Table} has no columns");
        }
        Console.WriteLine($"Columns of {Schema}.{Table}:");
        foreach (var row in rows)
        {
            var key = row.GetValueOrDefault("is_pk") == "true" ? " (primary key)" : "";
            Console.WriteLine($"- {row["column"]}: {row["data_type"]}{key}");
        }
    }
    ```

=== "Go"

    ```go
    // describeTable lists the columns of one table with their types. Given a
    // table_name, get_schema_info returns one line for each column, which also
    // carries the table's details.
    func describeTable(client *http.Client) error {
    	text, err := callTool(client, "get_schema_info",
    		map[string]any{"schema_name": schema, "table_name": table})
    	if err != nil {
    		return err
    	}
    	rows, err := parseTsv(text)
    	if err != nil {
    		return err
    	}
    	if len(rows) == 0 {
    		return fmt.Errorf("%s.%s has no columns", schema, table)
    	}
    	fmt.Printf("Columns of %s.%s:\n", schema, table)
    	for _, row := range rows {
    		key := ""
    		if row["is_pk"] == "true" {
    			key = " (primary key)"
    		}
    		fmt.Printf("- %s: %s%s\n", row["column"], row["data_type"], key)
    	}
    	return nil
    }
    
    ```

=== "Rust"

    ```rust
    /// Lists the columns of one table with their types. Given a table_name,
    /// get_schema_info returns one line for each column, which also carries
    /// the table's details.
    fn describe_table(client: &Client) -> Result<(), BoxError> {
        let text = call_tool(
            client,
            "get_schema_info",
            json!({"schema_name": SCHEMA, "table_name": TABLE}),
        )?;
        let rows = parse_tsv(&text)?;
        if rows.is_empty() {
            return Err(format!("{SCHEMA}.{TABLE} has no columns").into());
        }
        println!("Columns of {SCHEMA}.{TABLE}:");
        for row in &rows {
            let key = if column(row, "is_pk") == "true" { " (primary key)" } else { "" };
            println!("- {}: {}{key}", column(row, "column"), column(row, "data_type"));
        }
        Ok(())
    }
    ```

=== "Ruby"

    ```ruby
    # Lists the columns of one table with their types. Given a table_name,
    # get_schema_info returns one line for each column, which also carries the
    # table's details.
    def describe_table(http)
      text = call_tool(http, "get_schema_info", { schema_name: SCHEMA, table_name: TABLE })
      rows = parse_tsv(text)
      raise McpError, "#{SCHEMA}.#{TABLE} has no columns" if rows.empty?
    
      puts "Columns of #{SCHEMA}.#{TABLE}:"
      rows.each do |row|
        key = row["is_pk"] == "true" ? " (primary key)" : ""
        puts "- #{row["column"]}: #{row["data_type"]}#{key}"
      end
    end
    ```

=== "curl"

    ```bash
    # Lists the columns of one table with their types. Given a table_name,
    # get_schema_info returns one line for each column, which also carries the
    # table's details.
    describe_table() {
        local text rows
        text=$(call_tool get_schema_info \
            "{\"schema_name\": \"$SCHEMA\", \"table_name\": \"$TABLE\"}") \
            || return 1
        rows=$(parse_tsv <<<"$text") || return 1
        if [[ -z "$rows" ]]; then
            echo "$SCHEMA.$TABLE has no columns" >&2
            return 1
        fi
        echo "Columns of $SCHEMA.$TABLE:"
        jq -r '"- \(.column): \(.data_type)\(if .is_pk == "true"
                                              then " (primary key)" else "" end)"' \
            <<<"$rows"
    }
    ```

## Counting Rows

The `count_rows` tool counts the rows of a table, and its optional `where`
argument is a condition without the `WHERE` keyword; the server rejects a
condition that contains a subquery. The reply ends with a line such as
`Count: 4`. The following tabs show how each program counts the products in
stock:

=== "Python"

    ```python
    def count_in_stock(client: httpx.Client) -> None:
        """Counts the products in stock with count_rows. The where argument is
        a condition without the WHERE keyword; the server rejects one that
        contains a subquery."""
        text = call_tool(client, "count_rows",
                         {"schema": SCHEMA, "table": TABLE, "where": "in_stock"})
        # The reply ends with a line such as "Count: 4".
        match = re.search(r"^Count: (\d+)$", text, re.MULTILINE)
        if not match:
            raise McpError(f"The reply had no count: {text[:200]}")
        print(f"Products in stock: {match.group(1)}")
    ```

=== "TypeScript"

    ```typescript
    // Counts the products in stock with count_rows. The where argument is a
    // condition without the WHERE keyword; the server rejects one that
    // contains a subquery.
    async function countInStock(): Promise<void> {
      const text = await callTool("count_rows", { schema, table, where: "in_stock" });
      // The reply ends with a line such as "Count: 4".
      const match = text.match(/^Count: (\d+)$/m);
      if (!match) {
        throw new Error(`The reply had no count: ${text.slice(0, 200)}`);
      }
      console.log(`Products in stock: ${match[1]}`);
    }
    ```

=== "Java"

    ```java
    /** Matches the line at the end of a count_rows reply, such as "Count: 4". */
    static final Pattern COUNT_LINE = Pattern.compile("^Count: (\\d+)$", Pattern.MULTILINE);
    
    /**
     * Counts the products in stock with count_rows. The where argument is a
     * condition without the WHERE keyword; the server rejects one that
     * contains a subquery.
     */
    static void countInStock() throws IOException, InterruptedException, McpException {
        String text = callTool("count_rows",
                Map.of("schema", SCHEMA, "table", TABLE, "where", "in_stock"));
        Matcher match = COUNT_LINE.matcher(text);
        if (!match.find()) {
            throw new McpException("The reply had no count: " + shorten(text));
        }
        System.out.println("Products in stock: " + match.group(1));
    }
    ```

=== "C#"

    ```csharp
    // Counts the products in stock with count_rows. The where argument is a
    // condition without the WHERE keyword; the server rejects one that
    // contains a subquery.
    static async Task CountInStockAsync(HttpClient client)
    {
        var text = await CallToolAsync(client, "count_rows", new JsonObject
        {
            ["schema"] = Schema,
            ["table"] = Table,
            ["where"] = "in_stock",
        });
        // The reply ends with a line such as "Count: 4".
        var match = Regex.Match(text, @"^Count: (\d+)$", RegexOptions.Multiline);
        if (!match.Success)
        {
            throw new McpException($"The reply had no count: {Shorten(text)}");
        }
        Console.WriteLine($"Products in stock: {match.Groups[1].Value}");
    }
    ```

=== "Go"

    ```go
    // countLine matches the line at the end of a count_rows reply, such as
    // "Count: 4".
    var countLine = regexp.MustCompile(`(?m)^Count: (\d+)$`)
    
    // countInStock counts the products in stock with count_rows. The where
    // argument is a condition without the WHERE keyword; the server rejects
    // one that contains a subquery.
    func countInStock(client *http.Client) error {
    	text, err := callTool(client, "count_rows",
    		map[string]any{"schema": schema, "table": table, "where": "in_stock"})
    	if err != nil {
    		return err
    	}
    	match := countLine.FindStringSubmatch(text)
    	if match == nil {
    		return fmt.Errorf("the reply had no count: %s", shorten([]byte(text)))
    	}
    	fmt.Printf("Products in stock: %s\n", match[1])
    	return nil
    }
    
    ```

=== "Rust"

    ```rust
    /// Counts the products in stock with count_rows. The where argument is a
    /// condition without the WHERE keyword; the server rejects one that
    /// contains a subquery.
    fn count_in_stock(client: &Client) -> Result<(), BoxError> {
        let text = call_tool(
            client,
            "count_rows",
            json!({"schema": SCHEMA, "table": TABLE, "where": "in_stock"}),
        )?;
        // The reply ends with a line such as "Count: 4".
        let count = text
            .lines()
            .filter_map(|line| line.strip_prefix("Count: "))
            .find(|count| !count.is_empty() && count.chars().all(|c| c.is_ascii_digit()));
        let Some(count) = count else {
            return Err(format!("The reply had no count: {}", shorten(&text)).into());
        };
        println!("Products in stock: {count}");
        Ok(())
    }
    ```

=== "Ruby"

    ```ruby
    # Counts the products in stock with count_rows. The where argument is a
    # condition without the WHERE keyword; the server rejects one that
    # contains a subquery.
    def count_in_stock(http)
      text = call_tool(http, "count_rows", { schema: SCHEMA, table: TABLE, where: "in_stock" })
      # The reply ends with a line such as "Count: 4".
      match = text.match(/^Count: (\d+)$/)
      raise McpError, "The reply had no count: #{text[0, 200]}" if match.nil?
    
      puts "Products in stock: #{match[1]}"
    end
    ```

=== "curl"

    ```bash
    # Counts the products in stock with count_rows. The where argument is a
    # condition without the WHERE keyword; the server rejects one that
    # contains a subquery.
    count_in_stock() {
        local text count
        text=$(call_tool count_rows \
            "{\"schema\": \"$SCHEMA\", \"table\": \"$TABLE\", \"where\": \"in_stock\"}") \
            || return 1
        # The reply ends with a line such as "Count: 4".
        count=$(sed -n 's/^Count: \([0-9][0-9]*\)$/\1/p' <<<"$text")
        if [[ -z "$count" ]]; then
            echo "The reply had no count: ${text:0:200}" >&2
            return 1
        fi
        echo "Products in stock: $count"
    }
    ```

## Handling Errors

The main part of each program checks that a token is set, runs the three steps,
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
                list_tables(client)
                describe_table(client)
                count_in_stock(client)
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
        await listTables();
        await describeTable();
        await countInStock();
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
            listTables();
            describeTable();
            countInStock();
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
        await ListTablesAsync(client);
        await DescribeTableAsync(client);
        await CountInStockAsync(client);
    }
    // HttpRequestException covers failures to reach the server, such as a
    // refused connection, and TaskCanceledException covers a timeout.
    // KeyNotFoundException covers a row that lacks a column the program reads.
    catch (Exception e) when (
        e is HttpRequestException or TaskCanceledException or McpException
            or KeyNotFoundException)
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
    // run makes the three calls and returns any error to the caller.
    func run() error {
    	if token == "" {
    		return errors.New("MCP_TOKEN must be set")
    	}
    	client := &http.Client{Timeout: timeout}
    	if err := listTables(client); err != nil {
    		return err
    	}
    	if err := describeTable(client); err != nil {
    		return err
    	}
    	return countInStock(client)
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
    /// Makes the three calls. The ? operator returns any error to the caller.
    fn run() -> Result<(), BoxError> {
        if token().is_empty() {
            return Err("MCP_TOKEN must be set".into());
        }
        let client = Client::builder().timeout(TIMEOUT).build()?;
        list_tables(&client)?;
        describe_table(&client)?;
        count_in_stock(&client)
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
        list_tables(http)
        describe_table(http)
        count_in_stock(http)
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
        list_tables
        describe_table
        count_in_stock
    }
    
    main
    ```

## Running the Example

The complete project for each language is available in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/postgres_mcp/explore_schema).
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
    Exploring a schema through the pgEdge Postgres MCP Server, using httpx.
    
    These examples are for pgEdge Postgres MCP Server 1.1.0.
    
    Copyright (c) 2026, pgEdge, Inc.
    This code is released under the PostgreSQL License.
    """
    
    import os
    import re
    import sys
    
    import httpx
    
    
    # The or operator treats an empty variable as unset.
    BASE_URL = (os.environ.get("MCP_URL") or "http://localhost:8080").rstrip("/")
    TOKEN = os.environ.get("MCP_TOKEN") or ""
    
    TIMEOUT_SECONDS = 30
    
    # The schema and table that scripts/start_postgres_mcp.sh creates.
    SCHEMA = "cookbook_mcp"
    TABLE = "products"
    
    
    class McpError(Exception):
        """Raised when the MCP Server rejects a request or replies oddly."""
    
    
    def call_tool(client: httpx.Client, name: str, arguments: dict) -> str:
        """Calls a tool with tools/call and returns the text of its reply.
    
        The server answers a JSON-RPC error with HTTP status 200, and a tool
        that fails returns a normal result with isError set, so the function
        checks for both as well as the HTTP status.
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
        text = result["content"][0]["text"]
        if result.get("isError"):
            raise McpError(f"{name} failed: {text}")
        return text
    
    
    def parse_tsv(text: str) -> list[dict]:
        """Reads the table in a tool's reply into a list of rows, each a
        dictionary keyed by column name.
    
        The reply starts with a line or two about the database, and then has
        a header line and one line for each row, with the values separated by
        tabs. The server writes a tab or a newline inside a value as \\t or
        \\n, so splitting on them is safe. The header is the first line that
        starts with "schema", the first column of every table that
        get_schema_info returns.
        """
        lines = text.split("\n")
        start = next((i for i, line in enumerate(lines)
                      if line.startswith("schema\t")), None)
        if start is None:
            raise McpError(f"The reply had no table: {text[:200]}")
        header = lines[start].split("\t")
        return [dict(zip(header, line.split("\t")))
                for line in lines[start + 1:] if line]
    
    
    def list_tables(client: httpx.Client) -> None:
        """Lists the tables in the schema with their comments. With compact set
        to true, get_schema_info returns one line for each table, without its
        columns, which suits a first look at a large database."""
        text = call_tool(client, "get_schema_info",
                         {"schema_name": SCHEMA, "compact": True})
        print(f"Tables in {SCHEMA}:")
        for row in parse_tsv(text):
            print(f"- {row['table']}: {row.get('table_desc') or '(no comment)'}")
    
    
    def describe_table(client: httpx.Client) -> None:
        """Lists the columns of one table with their types. Given a table_name,
        get_schema_info returns one line for each column, which also carries
        the table's details."""
        text = call_tool(client, "get_schema_info",
                         {"schema_name": SCHEMA, "table_name": TABLE})
        rows = parse_tsv(text)
        if not rows:
            raise McpError(f"{SCHEMA}.{TABLE} has no columns")
        print(f"Columns of {SCHEMA}.{TABLE}:")
        for row in rows:
            key = " (primary key)" if row.get("is_pk") == "true" else ""
            print(f"- {row['column']}: {row['data_type']}{key}")
    
    
    def count_in_stock(client: httpx.Client) -> None:
        """Counts the products in stock with count_rows. The where argument is
        a condition without the WHERE keyword; the server rejects one that
        contains a subquery."""
        text = call_tool(client, "count_rows",
                         {"schema": SCHEMA, "table": TABLE, "where": "in_stock"})
        # The reply ends with a line such as "Count: 4".
        match = re.search(r"^Count: (\d+)$", text, re.MULTILINE)
        if not match:
            raise McpError(f"The reply had no count: {text[:200]}")
        print(f"Products in stock: {match.group(1)}")
    
    
    def main() -> int:
        if not TOKEN:
            print("MCP_TOKEN must be set", file=sys.stderr)
            return 1
        try:
            with httpx.Client(base_url=BASE_URL, timeout=TIMEOUT_SECONDS) as client:
                list_tables(client)
                describe_table(client)
                count_in_stock(client)
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
     * Exploring a schema through the pgEdge Postgres MCP Server, using the
     * built-in fetch.
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
    
    // The schema and table that scripts/start_postgres_mcp.sh creates.
    const schema = "cookbook_mcp";
    const table = "products";
    
    // Calls a tool with tools/call and returns the text of its reply. The
    // server answers a JSON-RPC error with HTTP status 200, and a tool that
    // fails returns a normal result with isError set, so the function checks
    // for both as well as the HTTP status.
    async function callTool(name: string, args: object): Promise<string> {
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
      const text = await response.text();
      if (response.status !== 200) {
        throw new Error(`${name} failed with HTTP ${response.status}: ${text.slice(0, 200)}`);
      }
      let reply: any;
      try {
        reply = JSON.parse(text);
      } catch {
        reply = undefined;
      }
      if (typeof reply !== "object" || reply === null || !("result" in reply || "error" in reply)) {
        throw new Error(`${name} failed: unexpected response: ${text.slice(0, 200)}`);
      }
      if ("error" in reply) {
        throw new Error(`${name} failed: ${reply.error?.message}`);
      }
      const content = reply.result?.content?.[0]?.text;
      if (typeof content !== "string") {
        throw new Error(`${name} failed: unexpected result: ${text.slice(0, 200)}`);
      }
      if (reply.result.isError) {
        throw new Error(`${name} failed: ${content}`);
      }
      return content;
    }
    
    // Reads the table in a tool's reply into a list of rows, each an object
    // keyed by column name. The reply starts with a line or two about the
    // database, and then has a header line and one line for each row, with
    // the values separated by tabs. The server writes a tab or a newline
    // inside a value as \t or \n, so splitting on them is safe. The header is
    // the first line that starts with "schema", the first column of every
    // table that get_schema_info returns.
    function parseTsv(text: string): Record<string, string>[] {
      const lines = text.split("\n");
      const start = lines.findIndex((line) => line.startsWith("schema\t"));
      if (start < 0) {
        throw new Error(`The reply had no table: ${text.slice(0, 200)}`);
      }
      const header = lines[start].split("\t");
      return lines
        .slice(start + 1)
        .filter((line) => line !== "")
        .map((line) => {
          const values = line.split("\t");
          return Object.fromEntries(header.map((name, i) => [name, values[i] ?? ""]));
        });
    }
    
    // Lists the tables in the schema with their comments. With compact set to
    // true, get_schema_info returns one line for each table, without its
    // columns, which suits a first look at a large database.
    async function listTables(): Promise<void> {
      const text = await callTool("get_schema_info", { schema_name: schema, compact: true });
      console.log(`Tables in ${schema}:`);
      for (const row of parseTsv(text)) {
        console.log(`- ${row.table}: ${row.table_desc || "(no comment)"}`);
      }
    }
    
    // Lists the columns of one table with their types. Given a table_name,
    // get_schema_info returns one line for each column, which also carries
    // the table's details.
    async function describeTable(): Promise<void> {
      const text = await callTool("get_schema_info", { schema_name: schema, table_name: table });
      const rows = parseTsv(text);
      if (rows.length === 0) {
        throw new Error(`${schema}.${table} has no columns`);
      }
      console.log(`Columns of ${schema}.${table}:`);
      for (const row of rows) {
        const key = row.is_pk === "true" ? " (primary key)" : "";
        console.log(`- ${row.column}: ${row.data_type}${key}`);
      }
    }
    
    // Counts the products in stock with count_rows. The where argument is a
    // condition without the WHERE keyword; the server rejects one that
    // contains a subquery.
    async function countInStock(): Promise<void> {
      const text = await callTool("count_rows", { schema, table, where: "in_stock" });
      // The reply ends with a line such as "Count: 4".
      const match = text.match(/^Count: (\d+)$/m);
      if (!match) {
        throw new Error(`The reply had no count: ${text.slice(0, 200)}`);
      }
      console.log(`Products in stock: ${match[1]}`);
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
        await listTables();
        await describeTable();
        await countInStock();
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
     * Exploring a schema through the pgEdge Postgres MCP Server, using
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
    import java.util.HashMap;
    import java.util.List;
    import java.util.Map;
    import java.util.concurrent.CompletableFuture;
    import java.util.concurrent.ExecutionException;
    import java.util.concurrent.TimeUnit;
    import java.util.concurrent.TimeoutException;
    import java.util.regex.Matcher;
    import java.util.regex.Pattern;
    
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
    
        // The schema and table that scripts/start_postgres_mcp.sh creates.
        static final String SCHEMA = "cookbook_mcp";
        static final String TABLE = "products";
    
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
         * Calls a tool with tools/call and returns the text of its reply. The
         * server answers a JSON-RPC error with HTTP status 200, and a tool that
         * fails returns a normal result with isError set, so the method checks
         * for both as well as the HTTP status.
         */
        static String callTool(String name, Map<String, Object> arguments)
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
            if (result.path("isError").asBoolean(false)) {
                throw new McpException(name + " failed: " + text.stringValue());
            }
            return text.stringValue();
        }
    
        /**
         * Reads the table in a tool's reply into a list of rows, each a map
         * keyed by column name. The reply starts with a line or two about the
         * database, and then has a header line and one line for each row, with
         * the values separated by tabs. The server writes a tab or a newline
         * inside a value as \t or \n, so splitting on them is safe. The header
         * is the first line that starts with "schema", the first column of
         * every table that get_schema_info returns.
         */
        static List<Map<String, String>> parseTsv(String text) throws McpException {
            // A limit of -1 keeps empty strings at the end, such as an empty
            // last column.
            String[] lines = text.split("\n", -1);
            int start = -1;
            for (int i = 0; i < lines.length; i++) {
                if (lines[i].startsWith("schema\t")) {
                    start = i;
                    break;
                }
            }
            if (start < 0) {
                throw new McpException("The reply had no table: " + shorten(text));
            }
            String[] header = lines[start].split("\t", -1);
            List<Map<String, String>> rows = new ArrayList<>();
            for (int i = start + 1; i < lines.length; i++) {
                if (lines[i].isEmpty()) {
                    continue;
                }
                String[] values = lines[i].split("\t", -1);
                Map<String, String> row = new HashMap<>();
                for (int j = 0; j < header.length && j < values.length; j++) {
                    row.put(header[j], values[j]);
                }
                rows.add(row);
            }
            return rows;
        }
    
        /**
         * Lists the tables in the schema with their comments. With compact set
         * to true, get_schema_info returns one line for each table, without its
         * columns, which suits a first look at a large database.
         */
        static void listTables() throws IOException, InterruptedException, McpException {
            String text = callTool("get_schema_info",
                    Map.of("schema_name", SCHEMA, "compact", true));
            System.out.println("Tables in " + SCHEMA + ":");
            for (Map<String, String> row : parseTsv(text)) {
                String comment = row.getOrDefault("table_desc", "");
                System.out.println("- " + row.get("table") + ": "
                        + (comment.isEmpty() ? "(no comment)" : comment));
            }
        }
    
        /**
         * Lists the columns of one table with their types. Given a table_name,
         * get_schema_info returns one line for each column, which also carries
         * the table's details.
         */
        static void describeTable() throws IOException, InterruptedException, McpException {
            String text = callTool("get_schema_info",
                    Map.of("schema_name", SCHEMA, "table_name", TABLE));
            List<Map<String, String>> rows = parseTsv(text);
            if (rows.isEmpty()) {
                throw new McpException(SCHEMA + "." + TABLE + " has no columns");
            }
            System.out.println("Columns of " + SCHEMA + "." + TABLE + ":");
            for (Map<String, String> row : rows) {
                String key = "true".equals(row.get("is_pk")) ? " (primary key)" : "";
                System.out.println("- " + row.get("column") + ": " + row.get("data_type") + key);
            }
        }
    
        /** Matches the line at the end of a count_rows reply, such as "Count: 4". */
        static final Pattern COUNT_LINE = Pattern.compile("^Count: (\\d+)$", Pattern.MULTILINE);
    
        /**
         * Counts the products in stock with count_rows. The where argument is a
         * condition without the WHERE keyword; the server rejects one that
         * contains a subquery.
         */
        static void countInStock() throws IOException, InterruptedException, McpException {
            String text = callTool("count_rows",
                    Map.of("schema", SCHEMA, "table", TABLE, "where", "in_stock"));
            Matcher match = COUNT_LINE.matcher(text);
            if (!match.find()) {
                throw new McpException("The reply had no count: " + shorten(text));
            }
            System.out.println("Products in stock: " + match.group(1));
        }
    
        public static void main(String[] args) {
            if (TOKEN.isEmpty()) {
                System.err.println("MCP_TOKEN must be set");
                System.exit(1);
            }
            try {
                listTables();
                describeTable();
                countInStock();
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
     * Exploring a schema through the pgEdge Postgres MCP Server, using
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
    using System.Text.RegularExpressions;
    
    // Returns the value of an environment variable, or a fallback if the
    // variable is unset or empty.
    static string EnvOr(string name, string fallback) =>
        Environment.GetEnvironmentVariable(name) is { Length: > 0 } value
            ? value
            : fallback;
    
    static string BaseUrl() => EnvOr("MCP_URL", "http://localhost:8080").TrimEnd('/');
    static string Token() => EnvOr("MCP_TOKEN", "");
    
    const int TimeoutSeconds = 30;
    
    // The schema and table that scripts/start_postgres_mcp.sh creates.
    const string Schema = "cookbook_mcp";
    const string Table = "products";
    
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
    
    // Calls a tool with tools/call and returns the text of its reply. The
    // server answers a JSON-RPC error with HTTP status 200, and a tool that
    // fails returns a normal result with isError set, so the function checks
    // for both as well as the HTTP status.
    static async Task<string> CallToolAsync(HttpClient client, string name, JsonObject arguments)
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
        if (result["isError"] is JsonValue isError &&
            isError.TryGetValue(out bool failed) && failed)
        {
            throw new McpException($"{name} failed: {text}");
        }
        return text;
    }
    
    // Reads the table in a tool's reply into a list of rows, each a dictionary
    // keyed by column name. The reply starts with a line or two about the
    // database, and then has a header line and one line for each row, with the
    // values separated by tabs. The server writes a tab or a newline inside a
    // value as \t or \n, so splitting on them is safe. The header is the first
    // line that starts with "schema", the first column of every table that
    // get_schema_info returns.
    static List<Dictionary<string, string>> ParseTsv(string text)
    {
        var lines = text.Split('\n');
        var start = Array.FindIndex(lines, line => line.StartsWith("schema\t"));
        if (start < 0)
        {
            throw new McpException($"The reply had no table: {Shorten(text)}");
        }
        var header = lines[start].Split('\t');
        var rows = new List<Dictionary<string, string>>();
        foreach (var line in lines.Skip(start + 1).Where(line => line.Length > 0))
        {
            var values = line.Split('\t');
            rows.Add(header.Zip(values).ToDictionary(pair => pair.First, pair => pair.Second));
        }
        return rows;
    }
    
    // Lists the tables in the schema with their comments. With compact set to
    // true, get_schema_info returns one line for each table, without its
    // columns, which suits a first look at a large database.
    static async Task ListTablesAsync(HttpClient client)
    {
        var text = await CallToolAsync(client, "get_schema_info", new JsonObject
        {
            ["schema_name"] = Schema,
            ["compact"] = true,
        });
        Console.WriteLine($"Tables in {Schema}:");
        foreach (var row in ParseTsv(text))
        {
            var comment = row.GetValueOrDefault("table_desc");
            Console.WriteLine(
                $"- {row["table"]}: {(string.IsNullOrEmpty(comment) ? "(no comment)" : comment)}");
        }
    }
    
    // Lists the columns of one table with their types. Given a table_name,
    // get_schema_info returns one line for each column, which also carries the
    // table's details.
    static async Task DescribeTableAsync(HttpClient client)
    {
        var text = await CallToolAsync(client, "get_schema_info", new JsonObject
        {
            ["schema_name"] = Schema,
            ["table_name"] = Table,
        });
        var rows = ParseTsv(text);
        if (rows.Count == 0)
        {
            throw new McpException($"{Schema}.{Table} has no columns");
        }
        Console.WriteLine($"Columns of {Schema}.{Table}:");
        foreach (var row in rows)
        {
            var key = row.GetValueOrDefault("is_pk") == "true" ? " (primary key)" : "";
            Console.WriteLine($"- {row["column"]}: {row["data_type"]}{key}");
        }
    }
    
    // Counts the products in stock with count_rows. The where argument is a
    // condition without the WHERE keyword; the server rejects one that
    // contains a subquery.
    static async Task CountInStockAsync(HttpClient client)
    {
        var text = await CallToolAsync(client, "count_rows", new JsonObject
        {
            ["schema"] = Schema,
            ["table"] = Table,
            ["where"] = "in_stock",
        });
        // The reply ends with a line such as "Count: 4".
        var match = Regex.Match(text, @"^Count: (\d+)$", RegexOptions.Multiline);
        if (!match.Success)
        {
            throw new McpException($"The reply had no count: {Shorten(text)}");
        }
        Console.WriteLine($"Products in stock: {match.Groups[1].Value}");
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
        await ListTablesAsync(client);
        await DescribeTableAsync(client);
        await CountInStockAsync(client);
    }
    // HttpRequestException covers failures to reach the server, such as a
    // refused connection, and TaskCanceledException covers a timeout.
    // KeyNotFoundException covers a row that lacks a column the program reads.
    catch (Exception e) when (
        e is HttpRequestException or TaskCanceledException or McpException
            or KeyNotFoundException)
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
    // Exploring a schema through the pgEdge Postgres MCP Server, using
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
    	"regexp"
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
    
    // The schema and table that scripts/start_postgres_mcp.sh creates.
    const (
    	schema = "cookbook_mcp"
    	table  = "products"
    )
    
    // shorten returns at most the first 200 bytes of a reply.
    func shorten(body []byte) string {
    	if len(body) > 200 {
    		body = body[:200]
    	}
    	return string(body)
    }
    
    // callTool calls a tool with tools/call and returns the text of its
    // reply. The server answers a JSON-RPC error with HTTP status 200, and a
    // tool that fails returns a normal result with isError set, so the
    // function checks for both as well as the HTTP status.
    func callTool(client *http.Client, name string, arguments map[string]any) (string, error) {
    	payload, err := json.Marshal(map[string]any{
    		"jsonrpc": "2.0", "id": 1, "method": "tools/call",
    		"params": map[string]any{"name": name, "arguments": arguments},
    	})
    	if err != nil {
    		return "", err
    	}
    	request, err := http.NewRequest(http.MethodPost, baseURL+"/mcp/v1", bytes.NewReader(payload))
    	if err != nil {
    		return "", err
    	}
    	request.Header.Set("Authorization", "Bearer "+token)
    	request.Header.Set("Content-Type", "application/json")
    
    	response, err := client.Do(request)
    	if err != nil {
    		return "", err
    	}
    	defer response.Body.Close()
    	body, err := io.ReadAll(response.Body)
    	if err != nil {
    		return "", err
    	}
    	if response.StatusCode != http.StatusOK {
    		return "", fmt.Errorf("%s failed with HTTP %d: %s", name, response.StatusCode, shorten(body))
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
    		return "", fmt.Errorf("%s failed: unexpected response: %s", name, shorten(body))
    	}
    	if reply.Error != nil {
    		return "", fmt.Errorf("%s failed: %s", name, reply.Error.Message)
    	}
    	if len(reply.Result.Content) == 0 {
    		return "", fmt.Errorf("%s failed: unexpected result: %s", name, shorten(body))
    	}
    	text := reply.Result.Content[0].Text
    	if reply.Result.IsError {
    		return "", fmt.Errorf("%s failed: %s", name, text)
    	}
    	return text, nil
    }
    
    
    // parseTsv reads the table in a tool's reply into a list of rows, each a
    // map keyed by column name. The reply starts with a line or two about the
    // database, and then has a header line and one line for each row, with
    // the values separated by tabs. The server writes a tab or a newline
    // inside a value as \t or \n, so splitting on them is safe. The header is
    // the first line that starts with "schema", the first column of every
    // table that get_schema_info returns.
    func parseTsv(text string) ([]map[string]string, error) {
    	lines := strings.Split(text, "\n")
    	start := -1
    	for i, line := range lines {
    		if strings.HasPrefix(line, "schema\t") {
    			start = i
    			break
    		}
    	}
    	if start < 0 {
    		return nil, fmt.Errorf("the reply had no table: %s", shorten([]byte(text)))
    	}
    	header := strings.Split(lines[start], "\t")
    	var rows []map[string]string
    	for _, line := range lines[start+1:] {
    		if line == "" {
    			continue
    		}
    		values := strings.Split(line, "\t")
    		row := make(map[string]string, len(header))
    		for i, name := range header {
    			if i < len(values) {
    				row[name] = values[i]
    			}
    		}
    		rows = append(rows, row)
    	}
    	return rows, nil
    }
    
    
    // listTables lists the tables in the schema with their comments. With
    // compact set to true, get_schema_info returns one line for each table,
    // without its columns, which suits a first look at a large database.
    func listTables(client *http.Client) error {
    	text, err := callTool(client, "get_schema_info",
    		map[string]any{"schema_name": schema, "compact": true})
    	if err != nil {
    		return err
    	}
    	fmt.Printf("Tables in %s:\n", schema)
    	rows, err := parseTsv(text)
    	if err != nil {
    		return err
    	}
    	for _, row := range rows {
    		comment := row["table_desc"]
    		if comment == "" {
    			comment = "(no comment)"
    		}
    		fmt.Printf("- %s: %s\n", row["table"], comment)
    	}
    	return nil
    }
    
    
    // describeTable lists the columns of one table with their types. Given a
    // table_name, get_schema_info returns one line for each column, which also
    // carries the table's details.
    func describeTable(client *http.Client) error {
    	text, err := callTool(client, "get_schema_info",
    		map[string]any{"schema_name": schema, "table_name": table})
    	if err != nil {
    		return err
    	}
    	rows, err := parseTsv(text)
    	if err != nil {
    		return err
    	}
    	if len(rows) == 0 {
    		return fmt.Errorf("%s.%s has no columns", schema, table)
    	}
    	fmt.Printf("Columns of %s.%s:\n", schema, table)
    	for _, row := range rows {
    		key := ""
    		if row["is_pk"] == "true" {
    			key = " (primary key)"
    		}
    		fmt.Printf("- %s: %s%s\n", row["column"], row["data_type"], key)
    	}
    	return nil
    }
    
    
    // countLine matches the line at the end of a count_rows reply, such as
    // "Count: 4".
    var countLine = regexp.MustCompile(`(?m)^Count: (\d+)$`)
    
    // countInStock counts the products in stock with count_rows. The where
    // argument is a condition without the WHERE keyword; the server rejects
    // one that contains a subquery.
    func countInStock(client *http.Client) error {
    	text, err := callTool(client, "count_rows",
    		map[string]any{"schema": schema, "table": table, "where": "in_stock"})
    	if err != nil {
    		return err
    	}
    	match := countLine.FindStringSubmatch(text)
    	if match == nil {
    		return fmt.Errorf("the reply had no count: %s", shorten([]byte(text)))
    	}
    	fmt.Printf("Products in stock: %s\n", match[1])
    	return nil
    }
    
    
    // run makes the three calls and returns any error to the caller.
    func run() error {
    	if token == "" {
    		return errors.New("MCP_TOKEN must be set")
    	}
    	client := &http.Client{Timeout: timeout}
    	if err := listTables(client); err != nil {
    		return err
    	}
    	if err := describeTable(client); err != nil {
    		return err
    	}
    	return countInStock(client)
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
    // Exploring a schema through the pgEdge Postgres MCP Server, using reqwest
    // and serde_json.
    //
    // These examples are for pgEdge Postgres MCP Server 1.1.0.
    //
    // Copyright (c) 2026, pgEdge, Inc.
    // This code is released under the PostgreSQL License.
    
    use std::collections::HashMap;
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
    
    // The schema and table that scripts/start_postgres_mcp.sh creates.
    const SCHEMA: &str = "cookbook_mcp";
    const TABLE: &str = "products";
    
    /// The errors that the functions below return; a string converts into one
    /// with the ? operator or into().
    type BoxError = Box<dyn Error>;
    
    /// Returns at most the first 200 characters of a reply.
    fn shorten(text: &str) -> String {
        text.chars().take(200).collect()
    }
    
    /// Calls a tool with tools/call and returns the text of its reply. The
    /// server answers a JSON-RPC error with HTTP status 200, and a tool that
    /// fails returns a normal result with isError set, so the function checks
    /// for both as well as the HTTP status.
    fn call_tool(client: &Client, name: &str, arguments: Value) -> Result<String, BoxError> {
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
        if result["isError"].as_bool() == Some(true) {
            return Err(format!("{name} failed: {text}").into());
        }
        Ok(text.to_string())
    }
    
    /// Reads the table in a tool's reply into a list of rows, each a map keyed
    /// by column name. The reply starts with a line or two about the database,
    /// and then has a header line and one line for each row, with the values
    /// separated by tabs. The server writes a tab or a newline inside a value
    /// as \t or \n, so splitting on them is safe. The header is the first line
    /// that starts with "schema", the first column of every table that
    /// get_schema_info returns.
    fn parse_tsv(text: &str) -> Result<Vec<HashMap<String, String>>, BoxError> {
        let mut lines = text.split('\n').skip_while(|line| !line.starts_with("schema\t"));
        let Some(header) = lines.next() else {
            return Err(format!("The reply had no table: {}", shorten(text)).into());
        };
        let header: Vec<&str> = header.split('\t').collect();
        Ok(lines
            .filter(|line| !line.is_empty())
            .map(|line| {
                header
                    .iter()
                    .zip(line.split('\t'))
                    .map(|(name, value)| (name.to_string(), value.to_string()))
                    .collect()
            })
            .collect())
    }
    
    /// Returns a column of a row, or an empty string if the row lacks it.
    fn column<'a>(row: &'a HashMap<String, String>, name: &str) -> &'a str {
        row.get(name).map(String::as_str).unwrap_or("")
    }
    
    /// Lists the tables in the schema with their comments. With compact set to
    /// true, get_schema_info returns one line for each table, without its
    /// columns, which suits a first look at a large database.
    fn list_tables(client: &Client) -> Result<(), BoxError> {
        let text = call_tool(
            client,
            "get_schema_info",
            json!({"schema_name": SCHEMA, "compact": true}),
        )?;
        println!("Tables in {SCHEMA}:");
        for row in parse_tsv(&text)? {
            let comment = match column(&row, "table_desc") {
                "" => "(no comment)",
                comment => comment,
            };
            println!("- {}: {comment}", column(&row, "table"));
        }
        Ok(())
    }
    
    /// Lists the columns of one table with their types. Given a table_name,
    /// get_schema_info returns one line for each column, which also carries
    /// the table's details.
    fn describe_table(client: &Client) -> Result<(), BoxError> {
        let text = call_tool(
            client,
            "get_schema_info",
            json!({"schema_name": SCHEMA, "table_name": TABLE}),
        )?;
        let rows = parse_tsv(&text)?;
        if rows.is_empty() {
            return Err(format!("{SCHEMA}.{TABLE} has no columns").into());
        }
        println!("Columns of {SCHEMA}.{TABLE}:");
        for row in &rows {
            let key = if column(row, "is_pk") == "true" { " (primary key)" } else { "" };
            println!("- {}: {}{key}", column(row, "column"), column(row, "data_type"));
        }
        Ok(())
    }
    
    /// Counts the products in stock with count_rows. The where argument is a
    /// condition without the WHERE keyword; the server rejects one that
    /// contains a subquery.
    fn count_in_stock(client: &Client) -> Result<(), BoxError> {
        let text = call_tool(
            client,
            "count_rows",
            json!({"schema": SCHEMA, "table": TABLE, "where": "in_stock"}),
        )?;
        // The reply ends with a line such as "Count: 4".
        let count = text
            .lines()
            .filter_map(|line| line.strip_prefix("Count: "))
            .find(|count| !count.is_empty() && count.chars().all(|c| c.is_ascii_digit()));
        let Some(count) = count else {
            return Err(format!("The reply had no count: {}", shorten(&text)).into());
        };
        println!("Products in stock: {count}");
        Ok(())
    }
    
    /// Makes the three calls. The ? operator returns any error to the caller.
    fn run() -> Result<(), BoxError> {
        if token().is_empty() {
            return Err("MCP_TOKEN must be set".into());
        }
        let client = Client::builder().timeout(TIMEOUT).build()?;
        list_tables(&client)?;
        describe_table(&client)?;
        count_in_stock(&client)
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
    # Exploring a schema through the pgEdge Postgres MCP Server, using
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
    
    # The schema and table that scripts/start_postgres_mcp.sh creates.
    SCHEMA = "cookbook_mcp"
    TABLE = "products"
    
    # Raised when the MCP Server rejects a request or replies oddly.
    class McpError < StandardError; end
    
    # Parses a reply as a JSON object, or returns nil if it is not one.
    def parse_object(text)
      body = JSON.parse(text.to_s)
      body.is_a?(Hash) ? body : nil
    rescue JSON::ParserError
      nil
    end
    
    # Calls a tool with tools/call and returns the text of its reply. The
    # server answers a JSON-RPC error with HTTP status 200, and a tool that
    # fails returns a normal result with isError set, so the method checks for
    # both as well as the HTTP status.
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
      raise McpError, "#{name} failed: #{text}" if result["isError"]
    
      text
    end
    
    # Reads the table in a tool's reply into a list of rows, each a hash keyed
    # by column name. The reply starts with a line or two about the database,
    # and then has a header line and one line for each row, with the values
    # separated by tabs. The server writes a tab or a newline inside a value as
    # \t or \n, so splitting on them is safe. The header is the first line that
    # starts with "schema", the first column of every table that
    # get_schema_info returns.
    def parse_tsv(text)
      lines = text.split("\n")
      start = lines.index { |line| line.start_with?("schema\t") }
      raise McpError, "The reply had no table: #{text[0, 200]}" if start.nil?
    
      # A limit of -1 keeps empty strings at the end, such as an empty last
      # column.
      header = lines[start].split("\t", -1)
      lines[(start + 1)..].reject(&:empty?).map do |line|
        header.zip(line.split("\t", -1)).to_h
      end
    end
    
    # Lists the tables in the schema with their comments. With compact set to
    # true, get_schema_info returns one line for each table, without its
    # columns, which suits a first look at a large database.
    def list_tables(http)
      text = call_tool(http, "get_schema_info", { schema_name: SCHEMA, compact: true })
      puts "Tables in #{SCHEMA}:"
      parse_tsv(text).each do |row|
        comment = row["table_desc"].to_s
        puts "- #{row["table"]}: #{comment.empty? ? "(no comment)" : comment}"
      end
    end
    
    # Lists the columns of one table with their types. Given a table_name,
    # get_schema_info returns one line for each column, which also carries the
    # table's details.
    def describe_table(http)
      text = call_tool(http, "get_schema_info", { schema_name: SCHEMA, table_name: TABLE })
      rows = parse_tsv(text)
      raise McpError, "#{SCHEMA}.#{TABLE} has no columns" if rows.empty?
    
      puts "Columns of #{SCHEMA}.#{TABLE}:"
      rows.each do |row|
        key = row["is_pk"] == "true" ? " (primary key)" : ""
        puts "- #{row["column"]}: #{row["data_type"]}#{key}"
      end
    end
    
    # Counts the products in stock with count_rows. The where argument is a
    # condition without the WHERE keyword; the server rejects one that
    # contains a subquery.
    def count_in_stock(http)
      text = call_tool(http, "count_rows", { schema: SCHEMA, table: TABLE, where: "in_stock" })
      # The reply ends with a line such as "Count: 4".
      match = text.match(/^Count: (\d+)$/)
      raise McpError, "The reply had no count: #{text[0, 200]}" if match.nil?
    
      puts "Products in stock: #{match[1]}"
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
        list_tables(http)
        describe_table(http)
        count_in_stock(http)
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
    # Exploring a schema through the pgEdge Postgres MCP Server, using curl and
    # jq.
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
    
    # The schema and table that scripts/start_postgres_mcp.sh creates.
    SCHEMA=cookbook_mcp
    TABLE=products
    
    # Calls a tool with tools/call and prints the text of its reply:
    # call_tool NAME ARGUMENTS_JSON. The server answers a JSON-RPC error with
    # HTTP status 200, and a tool that fails returns a normal result with
    # isError set, so the function checks for both as well as the HTTP status.
    # The token goes to curl in a header file that bash supplies through a
    # pipe, so that it never appears in the arguments of the curl process,
    # which other users can read in the process list.
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
        if ! jq -e 'has("result") or has("error")' >/dev/null 2>&1 <<<"$body"; then
            echo "$name failed: unexpected response: ${body:0:200}" >&2
            return 1
        fi
        if jq -e 'has("error")' >/dev/null <<<"$body"; then
            echo "$name failed: $(jq -r '.error.message' <<<"$body")" >&2
            return 1
        fi
        if jq -e '.result.isError == true' >/dev/null <<<"$body"; then
            echo "$name failed: $(jq -r '.result.content[0].text' <<<"$body")" >&2
            return 1
        fi
        jq -r '.result.content[0].text' <<<"$body"
    }
    
    # Reads the table in a tool's reply from standard input, and prints each
    # row as a JSON object keyed by column name. The reply starts with a line
    # or two about the database, and then has a header line and one line for
    # each row, with the values separated by tabs. The server writes a tab or a
    # newline inside a value as \t or \n, so splitting on them is safe. The
    # header is the first line that starts with "schema", the first column of
    # every table that get_schema_info returns.
    parse_tsv() {
        jq -Rsc '
            split("\n") as $lines
            | ($lines | map(startswith("schema\t")) | index(true)) as $start
            | if $start == null then error("The reply had no table") else . end
            | ($lines[$start] | split("\t")) as $header
            | $lines[$start + 1:][]
            | select(. != "")
            | [$header, split("\t")] | transpose
            | map({key: .[0], value: .[1]}) | from_entries'
    }
    
    # Lists the tables in the schema with their comments. With compact set to
    # true, get_schema_info returns one line for each table, without its
    # columns, which suits a first look at a large database.
    list_tables() {
        local text rows
        text=$(call_tool get_schema_info \
            "{\"schema_name\": \"$SCHEMA\", \"compact\": true}") || return 1
        echo "Tables in $SCHEMA:"
        rows=$(parse_tsv <<<"$text") || return 1
        jq -r '"- \(.table): \(if (.table_desc // "") == "" then "(no comment)"
                              else .table_desc end)"' <<<"$rows"
    }
    
    # Lists the columns of one table with their types. Given a table_name,
    # get_schema_info returns one line for each column, which also carries the
    # table's details.
    describe_table() {
        local text rows
        text=$(call_tool get_schema_info \
            "{\"schema_name\": \"$SCHEMA\", \"table_name\": \"$TABLE\"}") \
            || return 1
        rows=$(parse_tsv <<<"$text") || return 1
        if [[ -z "$rows" ]]; then
            echo "$SCHEMA.$TABLE has no columns" >&2
            return 1
        fi
        echo "Columns of $SCHEMA.$TABLE:"
        jq -r '"- \(.column): \(.data_type)\(if .is_pk == "true"
                                              then " (primary key)" else "" end)"' \
            <<<"$rows"
    }
    
    # Counts the products in stock with count_rows. The where argument is a
    # condition without the WHERE keyword; the server rejects one that
    # contains a subquery.
    count_in_stock() {
        local text count
        text=$(call_tool count_rows \
            "{\"schema\": \"$SCHEMA\", \"table\": \"$TABLE\", \"where\": \"in_stock\"}") \
            || return 1
        # The reply ends with a line such as "Count: 4".
        count=$(sed -n 's/^Count: \([0-9][0-9]*\)$/\1/p' <<<"$text")
        if [[ -z "$count" ]]; then
            echo "The reply had no count: ${text:0:200}" >&2
            return 1
        fi
        echo "Products in stock: $count"
    }
    
    main() {
        list_tables
        describe_table
        count_in_stock
    }
    
    main
    
    ```

## Next Steps

The following resources provide more information about the topics in this
recipe:

- The [Running Read-Only Queries](read_only.md) recipe runs a query, and shows
  that the server refuses to write.
- The [Searching by Meaning](similarity_search.md) recipe finds the rows whose
  text is closest in meaning to a question.
- The [Calling AI DBA Workbench MCP Tools](../ai_dba_workbench/mcp_tools.md)
  recipe calls the same kind of tools through the AI DBA Workbench.
- The
  [pgEdge Postgres MCP Server documentation](https://docs.pgedge.com/pgedge-postgres-mcp-server/)
  describes every tool, resource and setting.
- The [Contributing a Recipe](../contributing.md) page explains how to add a
  recipe or a language to the cookbook.
