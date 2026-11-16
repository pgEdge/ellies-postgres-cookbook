# Searching by Meaning

This recipe uses the `similarity_search` tool of a pgEdge Postgres MCP Server
to find the products whose descriptions are closest in meaning to a question,
even when they share no words with it. The server turns the question into an
embedding with the same model that made the embeddings in the table, and finds
the rows whose embeddings are nearest to it. Each step shows the code in every
supported language; selecting a language tab switches every tab on the site to
that language.

These examples are for pgEdge Postgres MCP Server 1.1.0.

The program prints the following output:

```text
Query: a gift for an amateur astronomer
Results: 3
Best match: Acme Night Sky Telescope
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

The tool searches a table that has a text column and a `vector` column of its
embeddings. The `products` table has a `description` column and a
`description_embedding` column, and the server pairs them by their names; the
server must use the same embedding model as the one that made the embeddings,
which the start script arranges.

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
      "name": "similarity-search",
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
and treat an empty value as unset; each program allows 90 seconds for a
reply:

| Variable    | Default                 | Description                     |
|-------------|-------------------------|---------------------------------|
| `MCP_URL`   | `http://localhost:8080` | The base URL of the MCP Server. |
| `MCP_TOKEN` | None; it must be set    | An API token for the server.    |

The server turns the question into an embedding before it searches, which can
take a while if the embedding model has to load first, so the timeout is longer
than in the other MCP Server recipes. A program calls a tool with the
`tools/call` method, giving the tool's `name` and its `arguments`, and the
server needs no `initialize` handshake first. A tool's reply is text, in the
`text` member of the first item of the result's `content` array. A tool that
fails still returns a result rather than a JSON-RPC error, with `isError` set
to `true` and the error message as its text, so the helper checks that too.

The following tabs show how each program reads its settings, and how it calls a
tool:

=== "Python"

    ```python
    # The or operator treats an empty variable as unset.
    BASE_URL = (os.environ.get("MCP_URL") or "http://localhost:8080").rstrip("/")
    TOKEN = os.environ.get("MCP_TOKEN") or ""
    
    # The server turns the query into an embedding before it searches, which
    # can take a while if the embedding model has to load first, so the
    # timeout is longer than in the other recipes.
    TIMEOUT_SECONDS = 90
    
    QUERY = "a gift for an amateur astronomer"
    
    
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
    
    // The server turns the query into an embedding before it searches, which
    // can take a while if the embedding model has to load first, so the
    // timeout is longer than in the other recipes.
    const timeoutMs = 90_000;
    
    const query = "a gift for an amateur astronomer";
    
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
    
    // The server turns the query into an embedding before it searches,
    // which can take a while if the embedding model has to load first, so
    // the timeout is longer than in the other recipes.
    static final Duration TIMEOUT = Duration.ofSeconds(90);
    
    static final String QUERY = "a gift for an amateur astronomer";
    
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
    
    // The server turns the query into an embedding before it searches, which
    // can take a while if the embedding model has to load first, so the
    // timeout is longer than in the other recipes.
    const int TimeoutSeconds = 90;
    
    const string Query = "a gift for an amateur astronomer";
    
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
    
    // The server turns the query into an embedding before it searches, which
    // can take a while if the embedding model has to load first, so the
    // timeout is longer than in the other recipes.
    const timeout = 90 * time.Second
    
    const query = "a gift for an amateur astronomer"
    
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
    
    /// The server turns the query into an embedding before it searches, which
    /// can take a while if the embedding model has to load first, so the
    /// timeout is longer than in the other recipes.
    const TIMEOUT: Duration = Duration::from_secs(90);
    
    const QUERY: &str = "a gift for an amateur astronomer";
    
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
    
    # The server turns the query into an embedding before it searches, which
    # can take a while if the embedding model has to load first, so the
    # timeout is longer than in the other recipes.
    TIMEOUT_SECONDS = 90
    
    QUERY = "a gift for an amateur astronomer"
    
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
    
    # The server turns the query into an embedding before it searches, which
    # can take a while if the embedding model has to load first, so the
    # timeout is longer than in the other recipes.
    TIMEOUT_SECONDS=90
    
    QUERY="a gift for an amateur astronomer"
    
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

## Searching

The tool takes the table in `table_name`, the question in `query_text`, and the
number of results in `top_n`. Its reply is text, with a block for each result
that starts with a line such as `Result 1/3`. The server finds the closest rows
by vector distance and then reorders them, mixing in a keyword score and
favouring variety, so the first block is not always the closest match. Each
block has a `Source` line that gives the rank from the vector search, such as
`(vector search rank: #1, chunk: 1)`, and the program picks the block ranked
first, whose text follows the next blank line. Every description starts with
the product's name and a colon. The parsing depends on the layout of the text
in version 1.1.0, so check it again after an upgrade. The match in the output
above comes from the embeddings that `nomic-embed-text` makes, and another
model, or another build of the same one, can rank the products differently.
The following tabs show the search:

=== "Python"

    ```python
    def search(client: httpx.Client) -> None:
        """Searches the product descriptions for the query, and prints the
        number of results and the name of the product that matches it most
        closely.
    
        similarity_search finds the closest rows by vector distance, and then
        reorders them, mixing in a keyword score and favouring variety, so the
        first result in the reply is not always the closest. Each result has a
        line such as "Source: cookbook_mcp.products.description (vector search
        rank: #1, chunk: 1)"; the function picks the result ranked first by
        the vector search, whose text follows the first blank line after it.
        Every description starts with the product's name and a colon.
        """
        text = call_tool(client, "similarity_search", {
            "table_name": "cookbook_mcp.products",
            "query_text": QUERY,
            "top_n": 3,
        })
        print(f"Query: {QUERY}")
        lines = text.split("\n")
        count = sum(1 for line in lines if re.fullmatch(r"Result \d+/\d+", line))
        print(f"Results: {count}")
    
        source = next((i for i, line in enumerate(lines)
                       if line.startswith("Source: ") and
                       line.endswith("(vector search rank: #1, chunk: 1)")), None)
        blank = None if source is None else next(
            (i for i in range(source + 1, len(lines)) if lines[i] == ""), None)
        if blank is None or blank + 1 >= len(lines) or ": " not in lines[blank + 1]:
            raise McpError(f"The reply had no closest match: {text[:200]}")
        print(f"Best match: {lines[blank + 1].split(': ')[0]}")
    ```

=== "TypeScript"

    ```typescript
    // Searches the product descriptions for the query, and prints the number
    // of results and the name of the product that matches it most closely.
    // similarity_search finds the closest rows by vector distance, and then
    // reorders them, mixing in a keyword score and favouring variety, so the
    // first result in the reply is not always the closest. Each result has a
    // line such as "Source: cookbook_mcp.products.description (vector search
    // rank: #1, chunk: 1)"; the function picks the result ranked first by the
    // vector search, whose text follows the first blank line after it. Every
    // description starts with the product's name and a colon.
    async function search(): Promise<void> {
      const text = await callTool("similarity_search", {
        table_name: "cookbook_mcp.products",
        query_text: query,
        top_n: 3,
      });
      console.log(`Query: ${query}`);
      const lines = text.split("\n");
      const count = lines.filter((line) => /^Result \d+\/\d+$/.test(line)).length;
      console.log(`Results: ${count}`);
    
      const source = lines.findIndex(
        (line) =>
          line.startsWith("Source: ") && line.endsWith("(vector search rank: #1, chunk: 1)"),
      );
      const blank = source < 0 ? -1 : lines.findIndex((line, i) => i > source && line === "");
      const best = blank < 0 ? undefined : lines[blank + 1];
      if (best === undefined || !best.includes(": ")) {
        throw new Error(`The reply had no closest match: ${text.slice(0, 200)}`);
      }
      console.log(`Best match: ${best.split(": ")[0]}`);
    }
    ```

=== "Java"

    ```java
    /**
     * Searches the product descriptions for the query, and prints the
     * number of results and the name of the product that matches it most
     * closely. similarity_search finds the closest rows by vector distance,
     * and then reorders them, mixing in a keyword score and favouring
     * variety, so the first result in the reply is not always the closest.
     * Each result has a line such as "Source:
     * cookbook_mcp.products.description (vector search rank: #1, chunk:
     * 1)"; the method picks the result ranked first by the vector search,
     * whose text follows the first blank line after it. Every description
     * starts with the product's name and a colon.
     */
    static void search() throws IOException, InterruptedException, McpException {
        String text = callTool("similarity_search", Map.of(
                "table_name", "cookbook_mcp.products",
                "query_text", QUERY,
                "top_n", 3));
        System.out.println("Query: " + QUERY);
        String[] lines = text.split("\n", -1);
        int count = 0;
        for (String line : lines) {
            if (line.matches("Result \\d+/\\d+")) {
                count++;
            }
        }
        System.out.println("Results: " + count);
    
        int source = -1;
        for (int i = 0; i < lines.length; i++) {
            if (lines[i].startsWith("Source: ")
                    && lines[i].endsWith("(vector search rank: #1, chunk: 1)")) {
                source = i;
                break;
            }
        }
        String best = "";
        if (source >= 0) {
            for (int i = source + 1; i + 1 < lines.length; i++) {
                if (lines[i].isEmpty()) {
                    best = lines[i + 1];
                    break;
                }
            }
        }
        int colon = best.indexOf(": ");
        if (colon < 0) {
            throw new McpException("The reply had no closest match: " + shorten(text));
        }
        System.out.println("Best match: " + best.substring(0, colon));
    }
    ```

=== "C#"

    ```csharp
    // Searches the product descriptions for the query, and prints the number
    // of results and the name of the product that matches it most closely.
    // similarity_search finds the closest rows by vector distance, and then
    // reorders them, mixing in a keyword score and favouring variety, so the
    // first result in the reply is not always the closest. Each result has a
    // line such as "Source: cookbook_mcp.products.description (vector search
    // rank: #1, chunk: 1)"; the function picks the result ranked first by the
    // vector search, whose text follows the first blank line after it. Every
    // description starts with the product's name and a colon.
    static async Task SearchAsync(HttpClient client)
    {
        var text = await CallToolAsync(client, "similarity_search", new JsonObject
        {
            ["table_name"] = "cookbook_mcp.products",
            ["query_text"] = Query,
            ["top_n"] = 3,
        });
        Console.WriteLine($"Query: {Query}");
        var lines = text.Split('\n');
        var count = lines.Count(line => Regex.IsMatch(line, @"^Result \d+/\d+$"));
        Console.WriteLine($"Results: {count}");
    
        var source = Array.FindIndex(lines, line =>
            line.StartsWith("Source: ") &&
            line.EndsWith("(vector search rank: #1, chunk: 1)"));
        var blank = source < 0 ? -1 : Array.FindIndex(lines, source + 1, line => line.Length == 0);
        var best = blank < 0 || blank + 1 >= lines.Length ? "" : lines[blank + 1];
        var colon = best.IndexOf(": ", StringComparison.Ordinal);
        if (colon < 0)
        {
            throw new McpException($"The reply had no closest match: {Shorten(text)}");
        }
        Console.WriteLine($"Best match: {best[..colon]}");
    }
    ```

=== "Go"

    ```go
    // resultLine matches the line that starts each result, such as
    // "Result 1/3".
    var resultLine = regexp.MustCompile(`^Result \d+/\d+$`)
    
    // search searches the product descriptions for the query, and prints the
    // number of results and the name of the product that matches it most
    // closely. similarity_search finds the closest rows by vector distance,
    // and then reorders them, mixing in a keyword score and favouring variety,
    // so the first result in the reply is not always the closest. Each result
    // has a line such as "Source: cookbook_mcp.products.description (vector
    // search rank: #1, chunk: 1)"; the function picks the result ranked first
    // by the vector search, whose text follows the first blank line after it.
    // Every description starts with the product's name and a colon.
    func search(client *http.Client) error {
    	text, err := callTool(client, "similarity_search", map[string]any{
    		"table_name": "cookbook_mcp.products",
    		"query_text": query,
    		"top_n":      3,
    	})
    	if err != nil {
    		return err
    	}
    	fmt.Printf("Query: %s\n", query)
    	lines := strings.Split(text, "\n")
    	count := 0
    	for _, line := range lines {
    		if resultLine.MatchString(line) {
    			count++
    		}
    	}
    	fmt.Printf("Results: %d\n", count)
    
    	source := -1
    	for i, line := range lines {
    		if strings.HasPrefix(line, "Source: ") &&
    			strings.HasSuffix(line, "(vector search rank: #1, chunk: 1)") {
    			source = i
    			break
    		}
    	}
    	best := ""
    	if source >= 0 {
    		for i := source + 1; i+1 < len(lines); i++ {
    			if lines[i] == "" {
    				best = lines[i+1]
    				break
    			}
    		}
    	}
    	name, _, ok := strings.Cut(best, ": ")
    	if !ok {
    		return fmt.Errorf("the reply had no closest match: %s", shorten([]byte(text)))
    	}
    	fmt.Printf("Best match: %s\n", name)
    	return nil
    }
    
    ```

=== "Rust"

    ```rust
    /// Returns true for the line that starts each result, such as
    /// "Result 1/3".
    fn is_result_line(line: &str) -> bool {
        let Some(numbers) = line.strip_prefix("Result ") else {
            return false;
        };
        let Some((index, total)) = numbers.split_once('/') else {
            return false;
        };
        [index, total]
            .iter()
            .all(|n| !n.is_empty() && n.chars().all(|c| c.is_ascii_digit()))
    }
    
    /// Searches the product descriptions for the query, and prints the number
    /// of results and the name of the product that matches it most closely.
    /// similarity_search finds the closest rows by vector distance, and then
    /// reorders them, mixing in a keyword score and favouring variety, so the
    /// first result in the reply is not always the closest. Each result has a
    /// line such as "Source: cookbook_mcp.products.description (vector search
    /// rank: #1, chunk: 1)"; the function picks the result ranked first by the
    /// vector search, whose text follows the first blank line after it. Every
    /// description starts with the product's name and a colon.
    fn search(client: &Client) -> Result<(), BoxError> {
        let text = call_tool(
            client,
            "similarity_search",
            json!({
                "table_name": "cookbook_mcp.products",
                "query_text": QUERY,
                "top_n": 3,
            }),
        )?;
        println!("Query: {QUERY}");
        let count = text.split('\n').filter(|line| is_result_line(line)).count();
        println!("Results: {count}");
    
        let best = text
            .split('\n')
            .skip_while(|line| {
                !(line.starts_with("Source: ")
                    && line.ends_with("(vector search rank: #1, chunk: 1)"))
            })
            .skip_while(|line| !line.is_empty())
            .nth(1);
        let Some((name, _)) = best.and_then(|line| line.split_once(": ")) else {
            return Err(format!("The reply had no closest match: {}", shorten(&text)).into());
        };
        println!("Best match: {name}");
        Ok(())
    }
    ```

=== "Ruby"

    ```ruby
    # Searches the product descriptions for the query, and prints the number
    # of results and the name of the product that matches it most closely.
    # similarity_search finds the closest rows by vector distance, and then
    # reorders them, mixing in a keyword score and favouring variety, so the
    # first result in the reply is not always the closest. Each result has a
    # line such as "Source: cookbook_mcp.products.description (vector search
    # rank: #1, chunk: 1)"; the method picks the result ranked first by the
    # vector search, whose text follows the first blank line after it. Every
    # description starts with the product's name and a colon.
    def search(http)
      text = call_tool(http, "similarity_search", {
                         table_name: "cookbook_mcp.products",
                         query_text: QUERY,
                         top_n: 3
                       })
      puts "Query: #{QUERY}"
      # A limit of -1 keeps empty strings at the end.
      lines = text.split("\n", -1)
      puts "Results: #{lines.count { |line| line.match?(%r{\AResult \d+/\d+\z}) }}"
    
      source = lines.index do |line|
        line.start_with?("Source: ") && line.end_with?("(vector search rank: #1, chunk: 1)")
      end
      blank = source && (source + 1...lines.length).find { |i| lines[i].empty? }
      best = blank ? lines[blank + 1].to_s : ""
      raise McpError, "The reply had no closest match: #{text[0, 200]}" unless best.include?(": ")
    
      puts "Best match: #{best.split(": ", 2).first}"
    end
    ```

=== "curl"

    ```bash
    # Searches the product descriptions for the query, and prints the number
    # of results and the name of the product that matches it most closely.
    # similarity_search finds the closest rows by vector distance, and then
    # reorders them, mixing in a keyword score and favouring variety, so the
    # first result in the reply is not always the closest. Each result has a
    # line such as "Source: cookbook_mcp.products.description (vector search
    # rank: #1, chunk: 1)"; the script picks the result ranked first by the
    # vector search, whose text follows the first blank line after it. Every
    # description starts with the product's name and a colon.
    search() {
        local text best
        text=$(call_tool similarity_search "$(jq -nc --arg query "$QUERY" '{
            table_name: "cookbook_mcp.products",
            query_text: $query,
            top_n: 3
        }')") || return 1
        echo "Query: $QUERY"
        echo "Results: $(grep -cE '^Result [0-9]+/[0-9]+$' <<<"$text" || true)"
        best=$(awk '
            /^Source: .*\(vector search rank: #1, chunk: 1\)$/ { found = 1; next }
            found && $0 == "" { blank = 1; next }
            found && blank { print; exit }' <<<"$text")
        if [[ "$best" != *": "* ]]; then
            echo "The reply had no closest match: ${text:0:200}" >&2
            return 1
        fi
        echo "Best match: ${best%%: *}"
    }
    ```

## Handling Errors

The main part of each program checks that a token is set, runs the search,
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
                search(client)
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
        await search();
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
            search();
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
        await SearchAsync(client);
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
    // run makes the search and returns any error to the caller.
    func run() error {
    	if token == "" {
    		return errors.New("MCP_TOKEN must be set")
    	}
    	client := &http.Client{Timeout: timeout}
    	return search(client)
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
    /// Makes the search. The ? operator returns any error to the caller.
    fn run() -> Result<(), BoxError> {
        if token().is_empty() {
            return Err("MCP_TOKEN must be set".into());
        }
        let client = Client::builder().timeout(TIMEOUT).build()?;
        search(&client)
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
        search(http)
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
        search
    }
    
    main
    ```

## Running the Example

The complete project for each language is available in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/postgres_mcp/similarity_search).
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
    Searching by meaning through the pgEdge Postgres MCP Server, using httpx.
    
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
    
    # The server turns the query into an embedding before it searches, which
    # can take a while if the embedding model has to load first, so the
    # timeout is longer than in the other recipes.
    TIMEOUT_SECONDS = 90
    
    QUERY = "a gift for an amateur astronomer"
    
    
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
    
    
    def search(client: httpx.Client) -> None:
        """Searches the product descriptions for the query, and prints the
        number of results and the name of the product that matches it most
        closely.
    
        similarity_search finds the closest rows by vector distance, and then
        reorders them, mixing in a keyword score and favouring variety, so the
        first result in the reply is not always the closest. Each result has a
        line such as "Source: cookbook_mcp.products.description (vector search
        rank: #1, chunk: 1)"; the function picks the result ranked first by
        the vector search, whose text follows the first blank line after it.
        Every description starts with the product's name and a colon.
        """
        text = call_tool(client, "similarity_search", {
            "table_name": "cookbook_mcp.products",
            "query_text": QUERY,
            "top_n": 3,
        })
        print(f"Query: {QUERY}")
        lines = text.split("\n")
        count = sum(1 for line in lines if re.fullmatch(r"Result \d+/\d+", line))
        print(f"Results: {count}")
    
        source = next((i for i, line in enumerate(lines)
                       if line.startswith("Source: ") and
                       line.endswith("(vector search rank: #1, chunk: 1)")), None)
        blank = None if source is None else next(
            (i for i in range(source + 1, len(lines)) if lines[i] == ""), None)
        if blank is None or blank + 1 >= len(lines) or ": " not in lines[blank + 1]:
            raise McpError(f"The reply had no closest match: {text[:200]}")
        print(f"Best match: {lines[blank + 1].split(': ')[0]}")
    
    
    def main() -> int:
        if not TOKEN:
            print("MCP_TOKEN must be set", file=sys.stderr)
            return 1
        try:
            with httpx.Client(base_url=BASE_URL, timeout=TIMEOUT_SECONDS) as client:
                search(client)
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
     * Searching by meaning through the pgEdge Postgres MCP Server, using the
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
    
    // The server turns the query into an embedding before it searches, which
    // can take a while if the embedding model has to load first, so the
    // timeout is longer than in the other recipes.
    const timeoutMs = 90_000;
    
    const query = "a gift for an amateur astronomer";
    
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
    
    // Searches the product descriptions for the query, and prints the number
    // of results and the name of the product that matches it most closely.
    // similarity_search finds the closest rows by vector distance, and then
    // reorders them, mixing in a keyword score and favouring variety, so the
    // first result in the reply is not always the closest. Each result has a
    // line such as "Source: cookbook_mcp.products.description (vector search
    // rank: #1, chunk: 1)"; the function picks the result ranked first by the
    // vector search, whose text follows the first blank line after it. Every
    // description starts with the product's name and a colon.
    async function search(): Promise<void> {
      const text = await callTool("similarity_search", {
        table_name: "cookbook_mcp.products",
        query_text: query,
        top_n: 3,
      });
      console.log(`Query: ${query}`);
      const lines = text.split("\n");
      const count = lines.filter((line) => /^Result \d+\/\d+$/.test(line)).length;
      console.log(`Results: ${count}`);
    
      const source = lines.findIndex(
        (line) =>
          line.startsWith("Source: ") && line.endsWith("(vector search rank: #1, chunk: 1)"),
      );
      const blank = source < 0 ? -1 : lines.findIndex((line, i) => i > source && line === "");
      const best = blank < 0 ? undefined : lines[blank + 1];
      if (best === undefined || !best.includes(": ")) {
        throw new Error(`The reply had no closest match: ${text.slice(0, 200)}`);
      }
      console.log(`Best match: ${best.split(": ")[0]}`);
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
        await search();
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
     * Searching by meaning through the pgEdge Postgres MCP Server, using
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
    
        // The server turns the query into an embedding before it searches,
        // which can take a while if the embedding model has to load first, so
        // the timeout is longer than in the other recipes.
        static final Duration TIMEOUT = Duration.ofSeconds(90);
    
        static final String QUERY = "a gift for an amateur astronomer";
    
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
         * Searches the product descriptions for the query, and prints the
         * number of results and the name of the product that matches it most
         * closely. similarity_search finds the closest rows by vector distance,
         * and then reorders them, mixing in a keyword score and favouring
         * variety, so the first result in the reply is not always the closest.
         * Each result has a line such as "Source:
         * cookbook_mcp.products.description (vector search rank: #1, chunk:
         * 1)"; the method picks the result ranked first by the vector search,
         * whose text follows the first blank line after it. Every description
         * starts with the product's name and a colon.
         */
        static void search() throws IOException, InterruptedException, McpException {
            String text = callTool("similarity_search", Map.of(
                    "table_name", "cookbook_mcp.products",
                    "query_text", QUERY,
                    "top_n", 3));
            System.out.println("Query: " + QUERY);
            String[] lines = text.split("\n", -1);
            int count = 0;
            for (String line : lines) {
                if (line.matches("Result \\d+/\\d+")) {
                    count++;
                }
            }
            System.out.println("Results: " + count);
    
            int source = -1;
            for (int i = 0; i < lines.length; i++) {
                if (lines[i].startsWith("Source: ")
                        && lines[i].endsWith("(vector search rank: #1, chunk: 1)")) {
                    source = i;
                    break;
                }
            }
            String best = "";
            if (source >= 0) {
                for (int i = source + 1; i + 1 < lines.length; i++) {
                    if (lines[i].isEmpty()) {
                        best = lines[i + 1];
                        break;
                    }
                }
            }
            int colon = best.indexOf(": ");
            if (colon < 0) {
                throw new McpException("The reply had no closest match: " + shorten(text));
            }
            System.out.println("Best match: " + best.substring(0, colon));
        }
    
        public static void main(String[] args) {
            if (TOKEN.isEmpty()) {
                System.err.println("MCP_TOKEN must be set");
                System.exit(1);
            }
            try {
                search();
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
     * Searching by meaning through the pgEdge Postgres MCP Server, using
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
    
    // The server turns the query into an embedding before it searches, which
    // can take a while if the embedding model has to load first, so the
    // timeout is longer than in the other recipes.
    const int TimeoutSeconds = 90;
    
    const string Query = "a gift for an amateur astronomer";
    
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
    
    // Searches the product descriptions for the query, and prints the number
    // of results and the name of the product that matches it most closely.
    // similarity_search finds the closest rows by vector distance, and then
    // reorders them, mixing in a keyword score and favouring variety, so the
    // first result in the reply is not always the closest. Each result has a
    // line such as "Source: cookbook_mcp.products.description (vector search
    // rank: #1, chunk: 1)"; the function picks the result ranked first by the
    // vector search, whose text follows the first blank line after it. Every
    // description starts with the product's name and a colon.
    static async Task SearchAsync(HttpClient client)
    {
        var text = await CallToolAsync(client, "similarity_search", new JsonObject
        {
            ["table_name"] = "cookbook_mcp.products",
            ["query_text"] = Query,
            ["top_n"] = 3,
        });
        Console.WriteLine($"Query: {Query}");
        var lines = text.Split('\n');
        var count = lines.Count(line => Regex.IsMatch(line, @"^Result \d+/\d+$"));
        Console.WriteLine($"Results: {count}");
    
        var source = Array.FindIndex(lines, line =>
            line.StartsWith("Source: ") &&
            line.EndsWith("(vector search rank: #1, chunk: 1)"));
        var blank = source < 0 ? -1 : Array.FindIndex(lines, source + 1, line => line.Length == 0);
        var best = blank < 0 || blank + 1 >= lines.Length ? "" : lines[blank + 1];
        var colon = best.IndexOf(": ", StringComparison.Ordinal);
        if (colon < 0)
        {
            throw new McpException($"The reply had no closest match: {Shorten(text)}");
        }
        Console.WriteLine($"Best match: {best[..colon]}");
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
        await SearchAsync(client);
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
    // Searching by meaning through the pgEdge Postgres MCP Server, using
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
    
    // The server turns the query into an embedding before it searches, which
    // can take a while if the embedding model has to load first, so the
    // timeout is longer than in the other recipes.
    const timeout = 90 * time.Second
    
    const query = "a gift for an amateur astronomer"
    
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
    
    
    // resultLine matches the line that starts each result, such as
    // "Result 1/3".
    var resultLine = regexp.MustCompile(`^Result \d+/\d+$`)
    
    // search searches the product descriptions for the query, and prints the
    // number of results and the name of the product that matches it most
    // closely. similarity_search finds the closest rows by vector distance,
    // and then reorders them, mixing in a keyword score and favouring variety,
    // so the first result in the reply is not always the closest. Each result
    // has a line such as "Source: cookbook_mcp.products.description (vector
    // search rank: #1, chunk: 1)"; the function picks the result ranked first
    // by the vector search, whose text follows the first blank line after it.
    // Every description starts with the product's name and a colon.
    func search(client *http.Client) error {
    	text, err := callTool(client, "similarity_search", map[string]any{
    		"table_name": "cookbook_mcp.products",
    		"query_text": query,
    		"top_n":      3,
    	})
    	if err != nil {
    		return err
    	}
    	fmt.Printf("Query: %s\n", query)
    	lines := strings.Split(text, "\n")
    	count := 0
    	for _, line := range lines {
    		if resultLine.MatchString(line) {
    			count++
    		}
    	}
    	fmt.Printf("Results: %d\n", count)
    
    	source := -1
    	for i, line := range lines {
    		if strings.HasPrefix(line, "Source: ") &&
    			strings.HasSuffix(line, "(vector search rank: #1, chunk: 1)") {
    			source = i
    			break
    		}
    	}
    	best := ""
    	if source >= 0 {
    		for i := source + 1; i+1 < len(lines); i++ {
    			if lines[i] == "" {
    				best = lines[i+1]
    				break
    			}
    		}
    	}
    	name, _, ok := strings.Cut(best, ": ")
    	if !ok {
    		return fmt.Errorf("the reply had no closest match: %s", shorten([]byte(text)))
    	}
    	fmt.Printf("Best match: %s\n", name)
    	return nil
    }
    
    
    // run makes the search and returns any error to the caller.
    func run() error {
    	if token == "" {
    		return errors.New("MCP_TOKEN must be set")
    	}
    	client := &http.Client{Timeout: timeout}
    	return search(client)
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
    // Searching by meaning through the pgEdge Postgres MCP Server, using
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
    
    /// The server turns the query into an embedding before it searches, which
    /// can take a while if the embedding model has to load first, so the
    /// timeout is longer than in the other recipes.
    const TIMEOUT: Duration = Duration::from_secs(90);
    
    const QUERY: &str = "a gift for an amateur astronomer";
    
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
    
    /// Returns true for the line that starts each result, such as
    /// "Result 1/3".
    fn is_result_line(line: &str) -> bool {
        let Some(numbers) = line.strip_prefix("Result ") else {
            return false;
        };
        let Some((index, total)) = numbers.split_once('/') else {
            return false;
        };
        [index, total]
            .iter()
            .all(|n| !n.is_empty() && n.chars().all(|c| c.is_ascii_digit()))
    }
    
    /// Searches the product descriptions for the query, and prints the number
    /// of results and the name of the product that matches it most closely.
    /// similarity_search finds the closest rows by vector distance, and then
    /// reorders them, mixing in a keyword score and favouring variety, so the
    /// first result in the reply is not always the closest. Each result has a
    /// line such as "Source: cookbook_mcp.products.description (vector search
    /// rank: #1, chunk: 1)"; the function picks the result ranked first by the
    /// vector search, whose text follows the first blank line after it. Every
    /// description starts with the product's name and a colon.
    fn search(client: &Client) -> Result<(), BoxError> {
        let text = call_tool(
            client,
            "similarity_search",
            json!({
                "table_name": "cookbook_mcp.products",
                "query_text": QUERY,
                "top_n": 3,
            }),
        )?;
        println!("Query: {QUERY}");
        let count = text.split('\n').filter(|line| is_result_line(line)).count();
        println!("Results: {count}");
    
        let best = text
            .split('\n')
            .skip_while(|line| {
                !(line.starts_with("Source: ")
                    && line.ends_with("(vector search rank: #1, chunk: 1)"))
            })
            .skip_while(|line| !line.is_empty())
            .nth(1);
        let Some((name, _)) = best.and_then(|line| line.split_once(": ")) else {
            return Err(format!("The reply had no closest match: {}", shorten(&text)).into());
        };
        println!("Best match: {name}");
        Ok(())
    }
    
    /// Makes the search. The ? operator returns any error to the caller.
    fn run() -> Result<(), BoxError> {
        if token().is_empty() {
            return Err("MCP_TOKEN must be set".into());
        }
        let client = Client::builder().timeout(TIMEOUT).build()?;
        search(&client)
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
    # Searching by meaning through the pgEdge Postgres MCP Server, using
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
    
    # The server turns the query into an embedding before it searches, which
    # can take a while if the embedding model has to load first, so the
    # timeout is longer than in the other recipes.
    TIMEOUT_SECONDS = 90
    
    QUERY = "a gift for an amateur astronomer"
    
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
    
    # Searches the product descriptions for the query, and prints the number
    # of results and the name of the product that matches it most closely.
    # similarity_search finds the closest rows by vector distance, and then
    # reorders them, mixing in a keyword score and favouring variety, so the
    # first result in the reply is not always the closest. Each result has a
    # line such as "Source: cookbook_mcp.products.description (vector search
    # rank: #1, chunk: 1)"; the method picks the result ranked first by the
    # vector search, whose text follows the first blank line after it. Every
    # description starts with the product's name and a colon.
    def search(http)
      text = call_tool(http, "similarity_search", {
                         table_name: "cookbook_mcp.products",
                         query_text: QUERY,
                         top_n: 3
                       })
      puts "Query: #{QUERY}"
      # A limit of -1 keeps empty strings at the end.
      lines = text.split("\n", -1)
      puts "Results: #{lines.count { |line| line.match?(%r{\AResult \d+/\d+\z}) }}"
    
      source = lines.index do |line|
        line.start_with?("Source: ") && line.end_with?("(vector search rank: #1, chunk: 1)")
      end
      blank = source && (source + 1...lines.length).find { |i| lines[i].empty? }
      best = blank ? lines[blank + 1].to_s : ""
      raise McpError, "The reply had no closest match: #{text[0, 200]}" unless best.include?(": ")
    
      puts "Best match: #{best.split(": ", 2).first}"
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
        search(http)
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
    # Searching by meaning through the pgEdge Postgres MCP Server, using curl
    # and jq.
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
    
    # The server turns the query into an embedding before it searches, which
    # can take a while if the embedding model has to load first, so the
    # timeout is longer than in the other recipes.
    TIMEOUT_SECONDS=90
    
    QUERY="a gift for an amateur astronomer"
    
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
    
    # Searches the product descriptions for the query, and prints the number
    # of results and the name of the product that matches it most closely.
    # similarity_search finds the closest rows by vector distance, and then
    # reorders them, mixing in a keyword score and favouring variety, so the
    # first result in the reply is not always the closest. Each result has a
    # line such as "Source: cookbook_mcp.products.description (vector search
    # rank: #1, chunk: 1)"; the script picks the result ranked first by the
    # vector search, whose text follows the first blank line after it. Every
    # description starts with the product's name and a colon.
    search() {
        local text best
        text=$(call_tool similarity_search "$(jq -nc --arg query "$QUERY" '{
            table_name: "cookbook_mcp.products",
            query_text: $query,
            top_n: 3
        }')") || return 1
        echo "Query: $QUERY"
        echo "Results: $(grep -cE '^Result [0-9]+/[0-9]+$' <<<"$text" || true)"
        best=$(awk '
            /^Source: .*\(vector search rank: #1, chunk: 1\)$/ { found = 1; next }
            found && $0 == "" { blank = 1; next }
            found && blank { print; exit }' <<<"$text")
        if [[ "$best" != *": "* ]]; then
            echo "The reply had no closest match: ${text:0:200}" >&2
            return 1
        fi
        echo "Best match: ${best%%: *}"
    }
    
    main() {
        search
    }
    
    main
    
    ```

## Next Steps

The following resources provide more information about the topics in this
recipe:

- The [Exploring a Schema](explore_schema.md) recipe lists the tables and
  columns of a schema.
- The [Running Read-Only Queries](read_only.md) recipe runs a query, and shows
  that the server refuses to write.
- The [Calling AI DBA Workbench MCP Tools](../ai_dba_workbench/mcp_tools.md)
  recipe calls the same kind of tools through the AI DBA Workbench.
- The
  [pgEdge Postgres MCP Server documentation](https://docs.pgedge.com/pgedge-postgres-mcp-server/)
  describes every tool, resource and setting.
- The [Contributing a Recipe](../contributing.md) page explains how to add a
  recipe or a language to the cookbook.
