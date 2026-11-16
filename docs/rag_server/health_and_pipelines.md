# Checking Health and Listing Pipelines

This recipe checks that a pgEdge RAG Server is running, that its pipelines can
reach their language model providers, and then lists the pipelines that it
offers. The checks suit a deployment script, a monitoring probe, or a program
that needs to choose a pipeline. None of the endpoints calls a language model
to write an answer, so they reply quickly. Each step shows the code in every
supported language; selecting a language tab switches every tab on the site to
that language.

These examples are for pgEdge RAG Server 2.0.0.

The program prints the following output when the server is healthy:

```text
Live: ok
Health: healthy
- cookbook: embedding reachable, completion reachable
Pipelines (1):
- cookbook: Questions about the Acme Widget product range
```

## Preparing the Ingredients

The examples assume a running RAG Server with a pipeline named `cookbook` that
holds the fictional Acme Widget support documents. The
`scripts/start_rag_server.sh` script in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook) loads
those documents and starts the server in Docker, and the
[Preparing Data for the RAG Server](prepare_data.md) recipe shows how to build
such a table and pipeline yourself.

The server offers three endpoints for these checks, and each takes a `GET`
request. The following table describes them:

| Endpoint        | Description                                       |
|-----------------|---------------------------------------------------|
| `/v1/live`      | Replies `{"status": "ok"}` while the server runs. |
| `/v1/health`    | Contacts the providers of each pipeline.          |
| `/v1/pipelines` | Lists the name and description of each pipeline.  |

The `/v1/health` endpoint replies with HTTP 200 even when a provider is down,
so a program must read the `status` field, which is `healthy` or `degraded`,
rather than rely on the HTTP status. Each pipeline in the reply says whether
its embedding and completion providers are reachable, with an error message
when they are not. Use `/v1/live` for a frequent probe, because it calls
nothing else, and `/v1/health` less often, because it contacts the providers.

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
      "name": "health-and-pipelines",
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
    using System.Text.Json;
    using System.Text.Json.Nodes;
    ```

=== "Go"

    ```go
    import (
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
    use serde_json::Value;
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
    
    for tool in curl jq; do
        command -v "$tool" >/dev/null || { echo "$tool is required" >&2; exit 1; }
    done
    ```

## Configuring the Program

The examples read the address of the RAG Server from the `RAG_SERVER_URL`
environment variable, and treat an empty value as unset. These endpoints call
no language model, but the health check contacts each provider, so each program
allows 30 seconds for a reply. The following table describes the environment
variable:

| Variable         | Default                 | Description                     |
|------------------|-------------------------|---------------------------------|
| `RAG_SERVER_URL` | `http://localhost:8080` | The base URL of the RAG Server. |

The following tabs show how each program reads its settings, and how it fetches
a path from the server:

=== "Python"

    ```python
    # The or operator treats an empty variable as unset.
    BASE_URL = (os.environ.get("RAG_SERVER_URL") or "http://localhost:8080").rstrip("/")
    
    # None of these endpoints calls a language model, but the health check
    # contacts each provider, so allow it some time.
    TIMEOUT_SECONDS = 30.0
    
    
    class RagError(Exception):
        """Raised when the RAG Server rejects a request or replies oddly."""
    
    
    def get(client: httpx.Client, path: str) -> dict:
        """Fetches a path from the server, and returns the decoded reply."""
        response = client.get(path)
        if response.is_error:
            raise RagError(f"HTTP {response.status_code}, {response.text[:200]}")
        try:
            body = response.json()
            if isinstance(body, dict):
                return body
        except ValueError:
            pass
        raise RagError(f"Unexpected response: {response.text[:200]}")
    ```

=== "TypeScript"

    ```typescript
    // The || operator, unlike ??, also treats an empty variable as unset.
    const baseUrl = (process.env.RAG_SERVER_URL || "http://localhost:8080").replace(/\/+$/, "");
    
    // None of these endpoints calls a language model, but the health check
    // contacts each provider, so allow it some time.
    const timeoutMs = 30_000;
    
    // Fetches a path from the server, and returns the decoded reply.
    async function get<T>(path: string): Promise<T> {
      const response = await fetch(`${baseUrl}${path}`, {
        signal: AbortSignal.timeout(timeoutMs),
      });
    
      // fetch only rejects when it cannot reach the server; an error status
      // is a normal response, so check it explicitly.
      if (!response.ok) {
        const text = await response.text();
        throw new Error(`HTTP ${response.status}, ${text.slice(0, 200) || response.statusText}`);
      }
      return (await response.json()) as T;
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
            envOr("RAG_SERVER_URL", "http://localhost:8080")
                    .replaceAll("/+$", "");
    
    // None of these endpoints calls a language model, but the health
    // check contacts each provider, so allow it some time.
    static final Duration TIMEOUT = Duration.ofSeconds(30);
    
    /** Thrown when the RAG Server rejects a request or replies oddly. */
    static class RagException extends Exception {
        RagException(String message) {
            super(message);
        }
    }
    
    // A mapper is safe to share, so the program creates only one.
    static final ObjectMapper MAPPER = JsonMapper.builder().build();
    
    /** Returns at most the first 200 characters of a reply. */
    static String shorten(String text) {
        return text.length() > 200 ? text.substring(0, 200) : text;
    }
    
    /** Fetches a path from the server, and returns the decoded reply. */
    /**
     * Sends a request and returns the response with its whole body. The
     * request timeout stops applying once the headers arrive, so a server
     * that stalls part of the way through the body would hang send(); this
     * applies the same timeout to the whole exchange instead.
     */
    static HttpResponse<String> send(HttpClient client, HttpRequest request)
            throws IOException, InterruptedException {
        Duration timeout = request.timeout().orElseThrow();
        CompletableFuture<HttpResponse<String>> pending =
                client.sendAsync(request, HttpResponse.BodyHandlers.ofString());
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
    
    static JsonNode get(HttpClient client, String path)
            throws IOException, InterruptedException, RagException {
        HttpRequest request = HttpRequest.newBuilder(URI.create(BASE_URL + path))
                .timeout(TIMEOUT)
                .GET()
                .build();
        HttpResponse<String> response = send(client, request);
        if (response.statusCode() >= 400) {
            throw new RagException("HTTP " + response.statusCode() + ", "
                    + shorten(response.body()));
        }
        try {
            JsonNode body = MAPPER.readTree(response.body());
            if (body.isObject()) {
                return body;
            }
        } catch (JacksonException e) {
            // The body is not JSON; report it below.
        }
        throw new RagException(
                "Unexpected response: " + shorten(response.body()));
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
    
    static string BaseUrl() =>
        EnvOr("RAG_SERVER_URL", "http://localhost:8080").TrimEnd('/');
    
    // None of these endpoints calls a language model, but the health check
    // contacts each provider, so allow it some time.
    const int TimeoutSeconds = 30;
    
    // Returns at most the first 200 characters of a reply.
    static string Shorten(string text) =>
        text.Length > 200 ? text[..200] : text;
    
    // Fetches a path from the server, and returns the decoded reply.
    static async Task<JsonObject> GetAsync(HttpClient client, string path)
    {
        using var response = await client.GetAsync(BaseUrl() + path);
        var body = await response.Content.ReadAsStringAsync();
        if (!response.IsSuccessStatusCode)
        {
            throw new RagException(
                $"HTTP {(int)response.StatusCode}, {Shorten(body)}");
        }
        try
        {
            if (JsonNode.Parse(body) is JsonObject reply)
            {
                return reply;
            }
        }
        catch (JsonException)
        {
            // The body is not JSON; report it below.
        }
        throw new RagException($"Unexpected response: {Shorten(body)}");
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
    
    var baseURL = strings.TrimRight(envOr("RAG_SERVER_URL", "http://localhost:8080"), "/")
    
    // None of these endpoints calls a language model, but the health check
    // contacts each provider, so allow it some time.
    const timeout = 30 * time.Second
    
    // get fetches a path from the server, and decodes the reply into out.
    func get(client *http.Client, path string, out any) error {
    	response, err := client.Get(baseURL + path)
    	if err != nil {
    		return err
    	}
    	defer response.Body.Close()
    
    	body, err := io.ReadAll(response.Body)
    	if err != nil {
    		return err
    	}
    
    	// Go treats an error status as a normal response, so check it here.
    	if response.StatusCode != http.StatusOK {
    		return fmt.Errorf("HTTP %d, %.200s", response.StatusCode, strings.TrimSpace(string(body)))
    	}
    	if err := json.Unmarshal(body, out); err != nil {
    		return fmt.Errorf("unexpected response: %.200s", body)
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
        env_or("RAG_SERVER_URL", "http://localhost:8080")
            .trim_end_matches('/')
            .to_string()
    }
    
    /// None of these endpoints calls a language model, but the health check
    /// contacts each provider, so allow it some time.
    const TIMEOUT: Duration = Duration::from_secs(30);
    
    /// The errors that the functions below return; a string converts into one
    /// with the ? operator or into().
    type BoxError = Box<dyn Error>;
    
    /// Returns at most the first 200 characters of a reply.
    fn shorten(text: &str) -> String {
        text.chars().take(200).collect()
    }
    
    /// Fetches a path from the server, and returns the decoded reply.
    fn get(client: &Client, path: &str) -> Result<Value, BoxError> {
        let response = client.get(format!("{}{path}", base_url())).send()?;
        let status = response.status();
        let body = response.text()?;
        if !status.is_success() {
            return Err(format!("HTTP {}, {}", status.as_u16(), shorten(&body)).into());
        }
        match serde_json::from_str::<Value>(&body) {
            Ok(reply) if reply.is_object() => Ok(reply),
            _ => Err(format!("Unexpected response: {}", shorten(&body)).into()),
        }
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
    
    BASE_URL = env_or("RAG_SERVER_URL", "http://localhost:8080").sub(%r{/+\z}, "")
    
    # None of these endpoints calls a language model, but the health check
    # contacts each provider, so allow it some time.
    TIMEOUT_SECONDS = 30
    
    # Raised when the RAG Server rejects a request or replies oddly.
    class RagError < StandardError; end
    
    # Fetches a path from the server, and returns the decoded reply.
    def get(http, path)
      response = http.request(Net::HTTP::Get.new(URI("#{BASE_URL}#{path}")))
      unless response.is_a?(Net::HTTPSuccess)
        raise RagError, "HTTP #{response.code}, #{response.body.to_s[0, 200]}"
      end
    
      begin
        body = JSON.parse(response.body.to_s)
        return body if body.is_a?(Hash)
      rescue JSON::ParserError
        # The body is not JSON; report it below.
      end
      raise RagError, "Unexpected response: #{response.body.to_s[0, 200]}"
    end
    ```

=== "curl"

    ```bash
    # The :- operator treats an empty variable as unset.
    RAG_SERVER_URL="${RAG_SERVER_URL:-http://localhost:8080}"
    RAG_SERVER_URL="${RAG_SERVER_URL%/}"
    
    # None of these endpoints calls a language model, but the health check
    # contacts each provider, so allow it some time.
    TIMEOUT_SECONDS=30
    
    # Fetches a path from the server and prints the JSON reply. With
    # --fail-with-body, curl exits non-zero on an HTTP error status but still
    # prints the body, which carries the server's explanation.
    get() {
        curl --silent --show-error --fail-with-body \
            --max-time "$TIMEOUT_SECONDS" "$RAG_SERVER_URL$1"
    }
    ```

## Checking That the Server Is Live

Each program asks the liveness endpoint first, and stops if the server does not
answer, because the other checks cannot succeed without it. The following tabs
show the liveness check:

=== "Python"

    ```python
    def check_live(client: httpx.Client) -> None:
        """Checks that the server process is running. The /v1/live endpoint is
        cheap and calls nothing else, so it suits a frequent liveness probe."""
        body = get(client, "/v1/live")
        if body.get("status") != "ok":
            raise RagError(f"Unexpected response: {body}")
        print("Live: ok")
    ```

=== "TypeScript"

    ```typescript
    // Checks that the server process is running. The /v1/live endpoint is
    // cheap and calls nothing else, so it suits a frequent liveness probe.
    async function checkLive(): Promise<void> {
      const body = await get<{ status?: string }>("/v1/live");
      if (body.status !== "ok") {
        throw new Error(`Unexpected response: ${JSON.stringify(body)}`);
      }
      console.log("Live: ok");
    }
    ```

=== "Java"

    ```java
    /**
     * Checks that the server process is running. The /v1/live endpoint is
     * cheap and calls nothing else, so it suits a frequent liveness probe.
     */
    static void checkLive(HttpClient client)
            throws IOException, InterruptedException, RagException {
        JsonNode body = get(client, "/v1/live");
        if (!"ok".equals(body.path("status").asString())) {
            throw new RagException("Unexpected response: " + body);
        }
        System.out.println("Live: ok");
    }
    ```

=== "C#"

    ```csharp
    // Checks that the server process is running. The /v1/live endpoint is
    // cheap and calls nothing else, so it suits a frequent liveness probe.
    static async Task CheckLiveAsync(HttpClient client)
    {
        var reply = await GetAsync(client, "/v1/live");
        if (reply["status"]?.ToString() != "ok")
        {
            throw new RagException($"Unexpected response: {reply.ToJsonString()}");
        }
        Console.WriteLine("Live: ok");
    }
    ```

=== "Go"

    ```go
    // checkLive checks that the server process is running. The /v1/live
    // endpoint is cheap and calls nothing else, so it suits a frequent
    // liveness probe.
    func checkLive(client *http.Client) error {
    	var body struct {
    		Status string `json:"status"`
    	}
    	if err := get(client, "/v1/live", &body); err != nil {
    		return err
    	}
    	if body.Status != "ok" {
    		return fmt.Errorf("unexpected status %q", body.Status)
    	}
    	fmt.Println("Live: ok")
    	return nil
    }
    
    ```

=== "Rust"

    ```rust
    /// Checks that the server process is running. The /v1/live endpoint is
    /// cheap and calls nothing else, so it suits a frequent liveness probe.
    fn check_live(client: &Client) -> Result<(), BoxError> {
        let reply = get(client, "/v1/live")?;
        if reply["status"].as_str() != Some("ok") {
            return Err(format!("Unexpected response: {reply}").into());
        }
        println!("Live: ok");
        Ok(())
    }
    ```

=== "Ruby"

    ```ruby
    # Checks that the server process is running. The /v1/live endpoint is
    # cheap and calls nothing else, so it suits a frequent liveness probe.
    def check_live(http)
      body = get(http, "/v1/live")
      raise RagError, "Unexpected response: #{body}" unless body["status"] == "ok"
    
      puts "Live: ok"
    end
    ```

=== "curl"

    ```bash
    # Checks that the server process is running. The /v1/live endpoint is
    # cheap and calls nothing else, so it suits a frequent liveness probe. The
    # error call makes jq fail unless the status is the string "ok".
    check_live() {
        local response
        response="$(get /v1/live)" || {
            echo "RAG Server error: $response" >&2
            return 1
        }
        jq -er 'if .status == "ok" then "Live: ok"
                else error("status is not ok") end' <<<"$response" || {
            echo "Unexpected response: $response" >&2
            return 1
        }
    }
    ```

## Checking Health

Each program reads the overall status and the state of each provider, and
reports whether the server is healthy. The following tabs show the health
check:

=== "Python"

    ```python
    def describe_provider(provider: dict) -> str:
        """Describes whether a language model provider answered the check."""
        if provider.get("reachable"):
            return "reachable"
        return f"unreachable ({provider.get('error', 'unknown')})"
    
    
    def check_health(client: httpx.Client) -> bool:
        """Checks whether each pipeline can reach its language model providers.
        The /v1/health endpoint answers with HTTP 200 even when a provider is
        down, so the status field is the thing to check: it is "healthy" or
        "degraded". Prints the report, and returns whether the server is
        healthy."""
        body = get(client, "/v1/health")
        status = body.get("status")
        if not isinstance(status, str):
            raise RagError(f"Unexpected response: {body}")
    
        print(f"Health: {status}")
        for pipeline in body.get("pipelines") or []:
            embedding = describe_provider(pipeline.get("embedding", {}))
            completion = describe_provider(pipeline.get("completion", {}))
            print(f"- {pipeline.get('name')}: embedding {embedding}, "
                  f"completion {completion}")
        return status == "healthy"
    ```

=== "TypeScript"

    ```typescript
    interface Provider {
      reachable?: boolean;
      error?: string;
    }
    
    interface PipelineHealth {
      name?: string;
      embedding?: Provider;
      completion?: Provider;
    }
    
    // Describes whether a language model provider answered the check.
    function describeProvider(provider: Provider = {}): string {
      return provider.reachable ? "reachable" : `unreachable (${provider.error ?? "unknown"})`;
    }
    
    // Checks whether each pipeline can reach its language model providers.
    // The /v1/health endpoint answers with HTTP 200 even when a provider is
    // down, so the status field is the thing to check: it is "healthy" or
    // "degraded". Prints the report, and returns whether the server is
    // healthy.
    async function checkHealth(): Promise<boolean> {
      const body = await get<{ status?: unknown; pipelines?: PipelineHealth[] }>("/v1/health");
      if (typeof body.status !== "string") {
        throw new Error(`Unexpected response: ${JSON.stringify(body)}`);
      }
    
      console.log(`Health: ${body.status}`);
      for (const pipeline of body.pipelines ?? []) {
        console.log(
          `- ${pipeline.name}: embedding ${describeProvider(pipeline.embedding)}, ` +
            `completion ${describeProvider(pipeline.completion)}`,
        );
      }
      return body.status === "healthy";
    }
    ```

=== "Java"

    ```java
    /** Describes whether a language model provider answered the check. */
    static String describeProvider(JsonNode provider) {
        if (provider.path("reachable").asBoolean()) {
            return "reachable";
        }
        return "unreachable (" + provider.path("error").asString("unknown") + ")";
    }
    
    /**
     * Checks whether each pipeline can reach its language model providers.
     * The /v1/health endpoint answers with HTTP 200 even when a provider is
     * down, so the status field is the thing to check: it is "healthy" or
     * "degraded". Prints the report, and returns whether the server is
     * healthy.
     */
    static boolean checkHealth(HttpClient client)
            throws IOException, InterruptedException, RagException {
        JsonNode body = get(client, "/v1/health");
        JsonNode status = body.path("status");
        if (!status.isString()) {
            throw new RagException("Unexpected response: " + body);
        }
    
        System.out.println("Health: " + status.stringValue());
        // path() gives a missing node, which holds no elements, when the
        // reply lists no pipelines.
        for (JsonNode pipeline : body.path("pipelines")) {
            String embedding = describeProvider(pipeline.path("embedding"));
            String completion = describeProvider(pipeline.path("completion"));
            System.out.println("- " + pipeline.path("name").asString()
                    + ": embedding " + embedding + ", completion " + completion);
        }
        return status.stringValue().equals("healthy");
    }
    ```

=== "C#"

    ```csharp
    // Describes whether a language model provider answered the check.
    static string DescribeProvider(JsonNode? provider)
    {
        if (provider?["reachable"] is JsonValue reachable &&
            reachable.TryGetValue(out bool isReachable) && isReachable)
        {
            return "reachable";
        }
        return $"unreachable ({provider?["error"]?.ToString() ?? "unknown"})";
    }
    
    // Checks whether each pipeline can reach its language model providers.
    // The /v1/health endpoint answers with HTTP 200 even when a provider is
    // down, so the status field is the thing to check: it is "healthy" or
    // "degraded". Prints the report, and returns whether the server is
    // healthy.
    static async Task<bool> CheckHealthAsync(HttpClient client)
    {
        var reply = await GetAsync(client, "/v1/health");
        if (reply["status"] is not JsonValue statusNode ||
            !statusNode.TryGetValue(out string? status))
        {
            throw new RagException($"Unexpected response: {reply.ToJsonString()}");
        }
    
        Console.WriteLine($"Health: {status}");
        if (reply["pipelines"] is JsonArray pipelines)
        {
            foreach (var pipeline in pipelines)
            {
                var embedding = DescribeProvider(pipeline?["embedding"]);
                var completion = DescribeProvider(pipeline?["completion"]);
                Console.WriteLine(
                    $"- {pipeline?["name"]}: embedding {embedding}, completion {completion}");
            }
        }
        return status == "healthy";
    }
    ```

=== "Go"

    ```go
    // provider reports whether a language model provider answered the check.
    type provider struct {
    	Reachable bool   `json:"reachable"`
    	Error     string `json:"error"`
    }
    
    // describe says in words whether the provider answered.
    func (p provider) describe() string {
    	if p.Reachable {
    		return "reachable"
    	}
    	if p.Error == "" {
    		return "unreachable (unknown)"
    	}
    	return "unreachable (" + p.Error + ")"
    }
    
    // checkHealth checks whether each pipeline can reach its language model
    // providers. The /v1/health endpoint answers with HTTP 200 even when a
    // provider is down, so the status field is the thing to check: it is
    // "healthy" or "degraded". It prints the report, and returns whether the
    // server is healthy.
    func checkHealth(client *http.Client) (bool, error) {
    	var body struct {
    		Status    *string `json:"status"`
    		Pipelines []struct {
    			Name       string   `json:"name"`
    			Embedding  provider `json:"embedding"`
    			Completion provider `json:"completion"`
    		} `json:"pipelines"`
    	}
    	if err := get(client, "/v1/health", &body); err != nil {
    		return false, err
    	}
    	if body.Status == nil {
    		return false, errors.New("unexpected response: missing status")
    	}
    
    	fmt.Printf("Health: %s\n", *body.Status)
    	for _, p := range body.Pipelines {
    		fmt.Printf("- %s: embedding %s, completion %s\n",
    			p.Name, p.Embedding.describe(), p.Completion.describe())
    	}
    	return *body.Status == "healthy", nil
    }
    
    ```

=== "Rust"

    ```rust
    /// Describes whether a language model provider answered the check.
    fn describe_provider(provider: &Value) -> String {
        if provider["reachable"].as_bool() == Some(true) {
            return "reachable".to_string();
        }
        format!("unreachable ({})", provider["error"].as_str().unwrap_or("unknown"))
    }
    
    /// Checks whether each pipeline can reach its language model providers.
    /// The /v1/health endpoint answers with HTTP 200 even when a provider is
    /// down, so the status field is the thing to check: it is "healthy" or
    /// "degraded". Prints the report, and returns whether the server is
    /// healthy.
    fn check_health(client: &Client) -> Result<bool, BoxError> {
        let reply = get(client, "/v1/health")?;
        let Some(status) = reply["status"].as_str() else {
            return Err(format!("Unexpected response: {reply}").into());
        };
    
        println!("Health: {status}");
        // as_array() gives None when the reply lists no pipelines.
        for pipeline in reply["pipelines"].as_array().into_iter().flatten() {
            println!(
                "- {}: embedding {}, completion {}",
                pipeline["name"].as_str().unwrap_or(""),
                describe_provider(&pipeline["embedding"]),
                describe_provider(&pipeline["completion"]),
            );
        }
        Ok(status == "healthy")
    }
    ```

=== "Ruby"

    ```ruby
    # Describes whether a language model provider answered the check.
    def describe_provider(provider)
      return "reachable" if provider["reachable"]
    
      "unreachable (#{provider.fetch("error", "unknown")})"
    end
    
    # Checks whether each pipeline can reach its language model providers.
    # The /v1/health endpoint answers with HTTP 200 even when a provider is
    # down, so the status field is the thing to check: it is "healthy" or
    # "degraded". Prints the report, and returns whether the server is
    # healthy.
    def check_health(http)
      body = get(http, "/v1/health")
      status = body["status"]
      raise RagError, "Unexpected response: #{body}" unless status.is_a?(String)
    
      puts "Health: #{status}"
      (body["pipelines"] || []).each do |pipeline|
        embedding = describe_provider(pipeline["embedding"] || {})
        completion = describe_provider(pipeline["completion"] || {})
        puts "- #{pipeline["name"]}: embedding #{embedding}, completion #{completion}"
      end
      status == "healthy"
    end
    ```

=== "curl"

    ```bash
    # Checks whether each pipeline can reach its language model providers.
    # The /v1/health endpoint answers with HTTP 200 even when a provider is
    # down, so curl succeeds either way; the status field is "healthy" or
    # "degraded". This function prints the report, returns 1 when a request
    # or reply fails, and returns 2 when the status is anything but "healthy".
    check_health() {
        local response
        response="$(get /v1/health)" || {
            echo "RAG Server error: $response" >&2
            return 1
        }
        jq -er '
            def provider:
                if .reachable then "reachable"
                else "unreachable (\(.error // "unknown"))" end;
    
            if (.status | type) != "string" then error("missing status") else
                "Health: \(.status)",
                ((.pipelines // [])[]
                 | "- \(.name): embedding \(.embedding | provider), "
                   + "completion \(.completion | provider)")
            end' <<<"$response" || {
            echo "Unexpected response: $response" >&2
            return 1
        }
        [[ "$(jq -r '.status' <<<"$response")" == "healthy" ]] || {
            echo "RAG Server is not healthy" >&2
            return 2
        }
    }
    ```

## Listing the Pipelines

Each program prints the name and description of every pipeline, which is how a
client can discover the pipelines to ask. The following tabs show how each
program lists the pipelines:

=== "Python"

    ```python
    def list_pipelines(client: httpx.Client) -> None:
        """Lists the pipelines that the server offers, with their
        descriptions."""
        pipelines = get(client, "/v1/pipelines").get("pipelines")
        if not isinstance(pipelines, list):
            raise RagError("Unexpected response: missing pipelines")
    
        print(f"Pipelines ({len(pipelines)}):")
        for pipeline in pipelines:
            description = pipeline.get("description") or "(no description)"
            print(f"- {pipeline.get('name')}: {description}")
    ```

=== "TypeScript"

    ```typescript
    // Lists the pipelines that the server offers, with their descriptions.
    async function listPipelines(): Promise<void> {
      const body = await get<{ pipelines?: { name?: string; description?: string }[] }>(
        "/v1/pipelines",
      );
      if (!Array.isArray(body.pipelines)) {
        throw new Error("Unexpected response: missing pipelines");
      }
    
      console.log(`Pipelines (${body.pipelines.length}):`);
      for (const pipeline of body.pipelines) {
        console.log(`- ${pipeline.name}: ${pipeline.description || "(no description)"}`);
      }
    }
    ```

=== "Java"

    ```java
    /**
     * Lists the pipelines that the server offers, with their descriptions.
     */
    static void listPipelines(HttpClient client)
            throws IOException, InterruptedException, RagException {
        JsonNode pipelines = get(client, "/v1/pipelines").path("pipelines");
        if (!pipelines.isArray()) {
            throw new RagException("Unexpected response: missing pipelines");
        }
    
        System.out.println("Pipelines (" + pipelines.size() + "):");
        for (JsonNode pipeline : pipelines) {
            String description = pipeline.path("description").asString("");
            if (description.isEmpty()) {
                description = "(no description)";
            }
            System.out.println("- " + pipeline.path("name").asString()
                    + ": " + description);
        }
    }
    ```

=== "C#"

    ```csharp
    // Lists the pipelines that the server offers, with their descriptions.
    static async Task ListPipelinesAsync(HttpClient client)
    {
        var reply = await GetAsync(client, "/v1/pipelines");
        if (reply["pipelines"] is not JsonArray pipelines)
        {
            throw new RagException("Unexpected response: missing pipelines");
        }
    
        Console.WriteLine($"Pipelines ({pipelines.Count}):");
        foreach (var pipeline in pipelines)
        {
            var description = pipeline?["description"]?.ToString();
            if (string.IsNullOrEmpty(description))
            {
                description = "(no description)";
            }
            Console.WriteLine($"- {pipeline?["name"]}: {description}");
        }
    }
    ```

=== "Go"

    ```go
    // listPipelines lists the pipelines that the server offers, with their
    // descriptions.
    func listPipelines(client *http.Client) error {
    	var body struct {
    		Pipelines *[]struct {
    			Name        string `json:"name"`
    			Description string `json:"description"`
    		} `json:"pipelines"`
    	}
    	if err := get(client, "/v1/pipelines", &body); err != nil {
    		return err
    	}
    	if body.Pipelines == nil {
    		return errors.New("unexpected response: missing pipelines")
    	}
    
    	fmt.Printf("Pipelines (%d):\n", len(*body.Pipelines))
    	for _, p := range *body.Pipelines {
    		description := p.Description
    		if description == "" {
    			description = "(no description)"
    		}
    		fmt.Printf("- %s: %s\n", p.Name, description)
    	}
    	return nil
    }
    
    ```

=== "Rust"

    ```rust
    /// Lists the pipelines that the server offers, with their descriptions.
    fn list_pipelines(client: &Client) -> Result<(), BoxError> {
        let reply = get(client, "/v1/pipelines")?;
        let Some(pipelines) = reply["pipelines"].as_array() else {
            return Err("Unexpected response: missing pipelines".into());
        };
    
        println!("Pipelines ({}):", pipelines.len());
        for pipeline in pipelines {
            let description = match pipeline["description"].as_str() {
                Some(text) if !text.is_empty() => text,
                _ => "(no description)",
            };
            println!("- {}: {description}", pipeline["name"].as_str().unwrap_or(""));
        }
        Ok(())
    }
    ```

=== "Ruby"

    ```ruby
    # Lists the pipelines that the server offers, with their descriptions.
    def list_pipelines(http)
      pipelines = get(http, "/v1/pipelines")["pipelines"]
      raise RagError, "Unexpected response: missing pipelines" unless pipelines.is_a?(Array)
    
      puts "Pipelines (#{pipelines.length}):"
      pipelines.each do |pipeline|
        description = pipeline["description"]
        description = "(no description)" if description.nil? || description.empty?
        puts "- #{pipeline["name"]}: #{description}"
      end
    end
    ```

=== "curl"

    ```bash
    # Lists the pipelines that the server offers, with their descriptions.
    list_pipelines() {
        local response
        response="$(get /v1/pipelines)" || {
            echo "RAG Server error: $response" >&2
            return 1
        }
        jq -er '
            if (.pipelines | type) != "array" then error("missing pipelines") else
                "Pipelines (\(.pipelines | length)):",
                (.pipelines[] | "- \(.name): \(.description // "(no description)")")
            end' <<<"$response" || {
            echo "Unexpected response: $response" >&2
            return 1
        }
    }
    ```

## Handling Errors

The main part of each program runs the three checks, reports any failure on
`stderr`, and exits with a non-zero status when the server is unreachable or
degraded, so that a script can act on the result. The following tabs show the
main part of each program:

=== "Python"

    ```python
    def main() -> int:
        try:
            with httpx.Client(base_url=BASE_URL, timeout=TIMEOUT_SECONDS) as client:
                check_live(client)
                healthy = check_health(client)
                list_pipelines(client)
        # httpx.HTTPError is the base class for failures to reach the server,
        # such as a refused connection or a timeout.
        except (httpx.HTTPError, RagError) as e:
            print(f"RAG Server error: {e}", file=sys.stderr)
            return 1
    
        # A degraded server still answers with HTTP 200, so report it with the
        # exit status.
        if not healthy:
            print("RAG Server is not healthy", file=sys.stderr)
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
      try {
        await checkLive();
        const healthy = await checkHealth();
        await listPipelines();
    
        // A degraded server still answers with HTTP 200, so report it with the
        // exit status.
        if (!healthy) {
          console.error("RAG Server is not healthy");
          return 1;
        }
        return 0;
      } catch (err) {
        console.error(`RAG Server error: ${describe(err)}`);
        return 1;
      }
    }
    
    process.exitCode = await main();
    ```

=== "Java"

    ```java
    public static void main(String[] args) {
        HttpClient client = HttpClient.newHttpClient();
        boolean healthy;
        try {
            checkLive(client);
            healthy = checkHealth(client);
            listPipelines(client);
        // IOException covers failures to reach the server, such as a
        // refused connection or a timeout. The message of a refused
        // connection can be empty, so print the exception itself, which
        // includes its type.
        } catch (IOException | InterruptedException e) {
            System.err.println("RAG Server error: " + e);
            System.exit(1);
            return;
        } catch (RagException e) {
            System.err.println("RAG Server error: " + e.getMessage());
            System.exit(1);
            return;
        }
    
        // A degraded server still answers with HTTP 200, so report it with
        // the exit status.
        if (!healthy) {
            System.err.println("RAG Server is not healthy");
            System.exit(1);
        }
    }
    ```

=== "C#"

    ```csharp
    bool healthy;
    try
    {
        // using disposes of the client, and closes its connections, when the
        // block exits, whether or not an error occurred.
        using var client = new HttpClient
        {
            Timeout = TimeSpan.FromSeconds(TimeoutSeconds),
        };
        await CheckLiveAsync(client);
        healthy = await CheckHealthAsync(client);
        await ListPipelinesAsync(client);
    }
    // HttpRequestException covers failures to reach the server, such as a
    // refused connection, and TaskCanceledException covers a timeout.
    catch (Exception e) when (
        e is HttpRequestException or TaskCanceledException or RagException)
    {
        Console.Error.WriteLine($"RAG Server error: {e.Message}");
        return 1;
    }
    
    // A degraded server still answers with HTTP 200, so report it with the
    // exit status.
    if (!healthy)
    {
        Console.Error.WriteLine("RAG Server is not healthy");
        return 1;
    }
    return 0;
    
    // C# requires type declarations to follow the top-level statements, so
    // the exception that the program throws for an error reply is declared
    // here, at the end.
    class RagException(string message) : Exception(message);
    ```

=== "Go"

    ```go
    // run performs the checks and returns any error to the caller.
    func run() error {
    	client := &http.Client{Timeout: timeout}
    
    	if err := checkLive(client); err != nil {
    		return err
    	}
    	healthy, err := checkHealth(client)
    	if err != nil {
    		return err
    	}
    	if err := listPipelines(client); err != nil {
    		return err
    	}
    
    	// A degraded server still answers with HTTP 200, so report it with the
    	// exit status.
    	if !healthy {
    		return errors.New("the server is not healthy")
    	}
    	return nil
    }
    
    // main reports any error returned by run() and exits with a non-zero
    // status.
    func main() {
    	if err := run(); err != nil {
    		fmt.Fprintf(os.Stderr, "RAG Server error: %v\n", err)
    		os.Exit(1)
    	}
    }
    
    ```

=== "Rust"

    ```rust
    /// Runs the three checks, and returns whether the server is healthy. The
    /// ? operator returns any error to the caller.
    fn run() -> Result<bool, BoxError> {
        let client = Client::builder().timeout(TIMEOUT).build()?;
        check_live(&client)?;
        let healthy = check_health(&client)?;
        list_pipelines(&client)?;
        Ok(healthy)
    }
    
    /// Reports any error returned by run() and exits with a failure status.
    /// The top-level error is often generic ("error sending request"), so the
    /// chain of underlying causes is printed too.
    fn main() -> ExitCode {
        match run() {
            Ok(true) => ExitCode::SUCCESS,
            // A degraded server still answers with HTTP 200, so report it
            // with the exit status.
            Ok(false) => {
                eprintln!("RAG Server is not healthy");
                ExitCode::FAILURE
            }
            Err(e) => {
                eprintln!("RAG Server error: {e}");
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
    begin
      uri = URI(BASE_URL)
      # start opens a connection, and closes it when the block exits, whether
      # or not an error occurred.
      healthy = Net::HTTP.start(
        uri.host, uri.port,
        use_ssl: uri.scheme == "https",
        open_timeout: TIMEOUT_SECONDS, read_timeout: TIMEOUT_SECONDS
      ) do |http|
        check_live(http)
        result = check_health(http)
        list_pipelines(http)
        result
      end
    # SystemCallError covers a refused connection, Timeout::Error covers the
    # connection and read timeouts, and SocketError covers an unknown host.
    rescue RagError, SystemCallError, Timeout::Error, SocketError, IOError => e
      warn "RAG Server error: #{e.message}"
      exit 1
    end
    
    # A degraded server still answers with HTTP 200, so report it with the
    # exit status.
    unless healthy
      warn "RAG Server is not healthy"
      exit 1
    end
    ```

=== "curl"

    ```bash
    main() {
        local status=0 result=0
    
        # Stop at the first request that fails, as the other examples do. A
        # degraded server still answers every request, so carry on and list the
        # pipelines, and then exit non-zero.
        check_live || exit 1
        check_health || result=$?
        if [[ "$result" -eq 2 ]]; then
            status=1
        elif [[ "$result" -ne 0 ]]; then
            exit 1
        fi
        list_pipelines || exit 1
        exit "$status"
    }
    
    main
    ```

## Running the Example

The complete project for each language is available in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/rag_server/health_and_pipelines).
Set the environment variables for your RAG Server, and then run the command for
your language from the corresponding project directory. The following tabs show
the commands that build and run each example:

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
    Checking the health of the pgEdge RAG Server and listing its pipelines,
    using httpx.
    
    These examples are for pgEdge RAG Server 2.0.0.
    
    Copyright (c) 2026, pgEdge, Inc.
    This code is released under the PostgreSQL License.
    """
    
    import os
    import sys
    
    import httpx
    
    
    # The or operator treats an empty variable as unset.
    BASE_URL = (os.environ.get("RAG_SERVER_URL") or "http://localhost:8080").rstrip("/")
    
    # None of these endpoints calls a language model, but the health check
    # contacts each provider, so allow it some time.
    TIMEOUT_SECONDS = 30.0
    
    
    class RagError(Exception):
        """Raised when the RAG Server rejects a request or replies oddly."""
    
    
    def get(client: httpx.Client, path: str) -> dict:
        """Fetches a path from the server, and returns the decoded reply."""
        response = client.get(path)
        if response.is_error:
            raise RagError(f"HTTP {response.status_code}, {response.text[:200]}")
        try:
            body = response.json()
            if isinstance(body, dict):
                return body
        except ValueError:
            pass
        raise RagError(f"Unexpected response: {response.text[:200]}")
    
    
    def check_live(client: httpx.Client) -> None:
        """Checks that the server process is running. The /v1/live endpoint is
        cheap and calls nothing else, so it suits a frequent liveness probe."""
        body = get(client, "/v1/live")
        if body.get("status") != "ok":
            raise RagError(f"Unexpected response: {body}")
        print("Live: ok")
    
    
    def describe_provider(provider: dict) -> str:
        """Describes whether a language model provider answered the check."""
        if provider.get("reachable"):
            return "reachable"
        return f"unreachable ({provider.get('error', 'unknown')})"
    
    
    def check_health(client: httpx.Client) -> bool:
        """Checks whether each pipeline can reach its language model providers.
        The /v1/health endpoint answers with HTTP 200 even when a provider is
        down, so the status field is the thing to check: it is "healthy" or
        "degraded". Prints the report, and returns whether the server is
        healthy."""
        body = get(client, "/v1/health")
        status = body.get("status")
        if not isinstance(status, str):
            raise RagError(f"Unexpected response: {body}")
    
        print(f"Health: {status}")
        for pipeline in body.get("pipelines") or []:
            embedding = describe_provider(pipeline.get("embedding", {}))
            completion = describe_provider(pipeline.get("completion", {}))
            print(f"- {pipeline.get('name')}: embedding {embedding}, "
                  f"completion {completion}")
        return status == "healthy"
    
    
    def list_pipelines(client: httpx.Client) -> None:
        """Lists the pipelines that the server offers, with their
        descriptions."""
        pipelines = get(client, "/v1/pipelines").get("pipelines")
        if not isinstance(pipelines, list):
            raise RagError("Unexpected response: missing pipelines")
    
        print(f"Pipelines ({len(pipelines)}):")
        for pipeline in pipelines:
            description = pipeline.get("description") or "(no description)"
            print(f"- {pipeline.get('name')}: {description}")
    
    
    def main() -> int:
        try:
            with httpx.Client(base_url=BASE_URL, timeout=TIMEOUT_SECONDS) as client:
                check_live(client)
                healthy = check_health(client)
                list_pipelines(client)
        # httpx.HTTPError is the base class for failures to reach the server,
        # such as a refused connection or a timeout.
        except (httpx.HTTPError, RagError) as e:
            print(f"RAG Server error: {e}", file=sys.stderr)
            return 1
    
        # A degraded server still answers with HTTP 200, so report it with the
        # exit status.
        if not healthy:
            print("RAG Server is not healthy", file=sys.stderr)
            return 1
        return 0
    
    
    if __name__ == "__main__":
        sys.exit(main())
    
    ```

=== "TypeScript"

    ```typescript
    /*
     * Ellie's Postgres Cookbook
     * Checking the health of the pgEdge RAG Server and listing its pipelines,
     * using the built-in fetch.
     *
     * These examples are for pgEdge RAG Server 2.0.0.
     *
     * Copyright (c) 2026, pgEdge, Inc.
     * This code is released under the PostgreSQL License.
     */
    
    // Node.js provides fetch and AbortSignal as globals, so this program
    // imports nothing.
    
    // The || operator, unlike ??, also treats an empty variable as unset.
    const baseUrl = (process.env.RAG_SERVER_URL || "http://localhost:8080").replace(/\/+$/, "");
    
    // None of these endpoints calls a language model, but the health check
    // contacts each provider, so allow it some time.
    const timeoutMs = 30_000;
    
    // Fetches a path from the server, and returns the decoded reply.
    async function get<T>(path: string): Promise<T> {
      const response = await fetch(`${baseUrl}${path}`, {
        signal: AbortSignal.timeout(timeoutMs),
      });
    
      // fetch only rejects when it cannot reach the server; an error status
      // is a normal response, so check it explicitly.
      if (!response.ok) {
        const text = await response.text();
        throw new Error(`HTTP ${response.status}, ${text.slice(0, 200) || response.statusText}`);
      }
      return (await response.json()) as T;
    }
    
    // Checks that the server process is running. The /v1/live endpoint is
    // cheap and calls nothing else, so it suits a frequent liveness probe.
    async function checkLive(): Promise<void> {
      const body = await get<{ status?: string }>("/v1/live");
      if (body.status !== "ok") {
        throw new Error(`Unexpected response: ${JSON.stringify(body)}`);
      }
      console.log("Live: ok");
    }
    
    interface Provider {
      reachable?: boolean;
      error?: string;
    }
    
    interface PipelineHealth {
      name?: string;
      embedding?: Provider;
      completion?: Provider;
    }
    
    // Describes whether a language model provider answered the check.
    function describeProvider(provider: Provider = {}): string {
      return provider.reachable ? "reachable" : `unreachable (${provider.error ?? "unknown"})`;
    }
    
    // Checks whether each pipeline can reach its language model providers.
    // The /v1/health endpoint answers with HTTP 200 even when a provider is
    // down, so the status field is the thing to check: it is "healthy" or
    // "degraded". Prints the report, and returns whether the server is
    // healthy.
    async function checkHealth(): Promise<boolean> {
      const body = await get<{ status?: unknown; pipelines?: PipelineHealth[] }>("/v1/health");
      if (typeof body.status !== "string") {
        throw new Error(`Unexpected response: ${JSON.stringify(body)}`);
      }
    
      console.log(`Health: ${body.status}`);
      for (const pipeline of body.pipelines ?? []) {
        console.log(
          `- ${pipeline.name}: embedding ${describeProvider(pipeline.embedding)}, ` +
            `completion ${describeProvider(pipeline.completion)}`,
        );
      }
      return body.status === "healthy";
    }
    
    // Lists the pipelines that the server offers, with their descriptions.
    async function listPipelines(): Promise<void> {
      const body = await get<{ pipelines?: { name?: string; description?: string }[] }>(
        "/v1/pipelines",
      );
      if (!Array.isArray(body.pipelines)) {
        throw new Error("Unexpected response: missing pipelines");
      }
    
      console.log(`Pipelines (${body.pipelines.length}):`);
      for (const pipeline of body.pipelines) {
        console.log(`- ${pipeline.name}: ${pipeline.description || "(no description)"}`);
      }
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
      try {
        await checkLive();
        const healthy = await checkHealth();
        await listPipelines();
    
        // A degraded server still answers with HTTP 200, so report it with the
        // exit status.
        if (!healthy) {
          console.error("RAG Server is not healthy");
          return 1;
        }
        return 0;
      } catch (err) {
        console.error(`RAG Server error: ${describe(err)}`);
        return 1;
      }
    }
    
    process.exitCode = await main();
    
    ```

=== "Java"

    ```java
    /*
     * Ellie's Postgres Cookbook
     * Checking the health of the pgEdge RAG Server and listing its pipelines,
     * using java.net.http and Jackson.
     *
     * These examples are for pgEdge RAG Server 2.0.0.
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
                envOr("RAG_SERVER_URL", "http://localhost:8080")
                        .replaceAll("/+$", "");
    
        // None of these endpoints calls a language model, but the health
        // check contacts each provider, so allow it some time.
        static final Duration TIMEOUT = Duration.ofSeconds(30);
    
        /** Thrown when the RAG Server rejects a request or replies oddly. */
        static class RagException extends Exception {
            RagException(String message) {
                super(message);
            }
        }
    
        // A mapper is safe to share, so the program creates only one.
        static final ObjectMapper MAPPER = JsonMapper.builder().build();
    
        /** Returns at most the first 200 characters of a reply. */
        static String shorten(String text) {
            return text.length() > 200 ? text.substring(0, 200) : text;
        }
    
        /** Fetches a path from the server, and returns the decoded reply. */
        /**
         * Sends a request and returns the response with its whole body. The
         * request timeout stops applying once the headers arrive, so a server
         * that stalls part of the way through the body would hang send(); this
         * applies the same timeout to the whole exchange instead.
         */
        static HttpResponse<String> send(HttpClient client, HttpRequest request)
                throws IOException, InterruptedException {
            Duration timeout = request.timeout().orElseThrow();
            CompletableFuture<HttpResponse<String>> pending =
                    client.sendAsync(request, HttpResponse.BodyHandlers.ofString());
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
    
        static JsonNode get(HttpClient client, String path)
                throws IOException, InterruptedException, RagException {
            HttpRequest request = HttpRequest.newBuilder(URI.create(BASE_URL + path))
                    .timeout(TIMEOUT)
                    .GET()
                    .build();
            HttpResponse<String> response = send(client, request);
            if (response.statusCode() >= 400) {
                throw new RagException("HTTP " + response.statusCode() + ", "
                        + shorten(response.body()));
            }
            try {
                JsonNode body = MAPPER.readTree(response.body());
                if (body.isObject()) {
                    return body;
                }
            } catch (JacksonException e) {
                // The body is not JSON; report it below.
            }
            throw new RagException(
                    "Unexpected response: " + shorten(response.body()));
        }
    
        /**
         * Checks that the server process is running. The /v1/live endpoint is
         * cheap and calls nothing else, so it suits a frequent liveness probe.
         */
        static void checkLive(HttpClient client)
                throws IOException, InterruptedException, RagException {
            JsonNode body = get(client, "/v1/live");
            if (!"ok".equals(body.path("status").asString())) {
                throw new RagException("Unexpected response: " + body);
            }
            System.out.println("Live: ok");
        }
    
        /** Describes whether a language model provider answered the check. */
        static String describeProvider(JsonNode provider) {
            if (provider.path("reachable").asBoolean()) {
                return "reachable";
            }
            return "unreachable (" + provider.path("error").asString("unknown") + ")";
        }
    
        /**
         * Checks whether each pipeline can reach its language model providers.
         * The /v1/health endpoint answers with HTTP 200 even when a provider is
         * down, so the status field is the thing to check: it is "healthy" or
         * "degraded". Prints the report, and returns whether the server is
         * healthy.
         */
        static boolean checkHealth(HttpClient client)
                throws IOException, InterruptedException, RagException {
            JsonNode body = get(client, "/v1/health");
            JsonNode status = body.path("status");
            if (!status.isString()) {
                throw new RagException("Unexpected response: " + body);
            }
    
            System.out.println("Health: " + status.stringValue());
            // path() gives a missing node, which holds no elements, when the
            // reply lists no pipelines.
            for (JsonNode pipeline : body.path("pipelines")) {
                String embedding = describeProvider(pipeline.path("embedding"));
                String completion = describeProvider(pipeline.path("completion"));
                System.out.println("- " + pipeline.path("name").asString()
                        + ": embedding " + embedding + ", completion " + completion);
            }
            return status.stringValue().equals("healthy");
        }
    
        /**
         * Lists the pipelines that the server offers, with their descriptions.
         */
        static void listPipelines(HttpClient client)
                throws IOException, InterruptedException, RagException {
            JsonNode pipelines = get(client, "/v1/pipelines").path("pipelines");
            if (!pipelines.isArray()) {
                throw new RagException("Unexpected response: missing pipelines");
            }
    
            System.out.println("Pipelines (" + pipelines.size() + "):");
            for (JsonNode pipeline : pipelines) {
                String description = pipeline.path("description").asString("");
                if (description.isEmpty()) {
                    description = "(no description)";
                }
                System.out.println("- " + pipeline.path("name").asString()
                        + ": " + description);
            }
        }
    
        public static void main(String[] args) {
            HttpClient client = HttpClient.newHttpClient();
            boolean healthy;
            try {
                checkLive(client);
                healthy = checkHealth(client);
                listPipelines(client);
            // IOException covers failures to reach the server, such as a
            // refused connection or a timeout. The message of a refused
            // connection can be empty, so print the exception itself, which
            // includes its type.
            } catch (IOException | InterruptedException e) {
                System.err.println("RAG Server error: " + e);
                System.exit(1);
                return;
            } catch (RagException e) {
                System.err.println("RAG Server error: " + e.getMessage());
                System.exit(1);
                return;
            }
    
            // A degraded server still answers with HTTP 200, so report it with
            // the exit status.
            if (!healthy) {
                System.err.println("RAG Server is not healthy");
                System.exit(1);
            }
        }
    }
    
    ```

=== "C#"

    ```csharp
    /*
     * Ellie's Postgres Cookbook
     * Checking the health of the pgEdge RAG Server and listing its pipelines,
     * using HttpClient and System.Text.Json.
     *
     * These examples are for pgEdge RAG Server 2.0.0.
     *
     * Copyright (c) 2026, pgEdge, Inc.
     * This code is released under the PostgreSQL License.
     */
    
    using System.Text.Json;
    using System.Text.Json.Nodes;
    
    // Returns the value of an environment variable, or a fallback if the
    // variable is unset or empty.
    static string EnvOr(string name, string fallback) =>
        Environment.GetEnvironmentVariable(name) is { Length: > 0 } value
            ? value
            : fallback;
    
    static string BaseUrl() =>
        EnvOr("RAG_SERVER_URL", "http://localhost:8080").TrimEnd('/');
    
    // None of these endpoints calls a language model, but the health check
    // contacts each provider, so allow it some time.
    const int TimeoutSeconds = 30;
    
    // Returns at most the first 200 characters of a reply.
    static string Shorten(string text) =>
        text.Length > 200 ? text[..200] : text;
    
    // Fetches a path from the server, and returns the decoded reply.
    static async Task<JsonObject> GetAsync(HttpClient client, string path)
    {
        using var response = await client.GetAsync(BaseUrl() + path);
        var body = await response.Content.ReadAsStringAsync();
        if (!response.IsSuccessStatusCode)
        {
            throw new RagException(
                $"HTTP {(int)response.StatusCode}, {Shorten(body)}");
        }
        try
        {
            if (JsonNode.Parse(body) is JsonObject reply)
            {
                return reply;
            }
        }
        catch (JsonException)
        {
            // The body is not JSON; report it below.
        }
        throw new RagException($"Unexpected response: {Shorten(body)}");
    }
    
    // Checks that the server process is running. The /v1/live endpoint is
    // cheap and calls nothing else, so it suits a frequent liveness probe.
    static async Task CheckLiveAsync(HttpClient client)
    {
        var reply = await GetAsync(client, "/v1/live");
        if (reply["status"]?.ToString() != "ok")
        {
            throw new RagException($"Unexpected response: {reply.ToJsonString()}");
        }
        Console.WriteLine("Live: ok");
    }
    
    // Describes whether a language model provider answered the check.
    static string DescribeProvider(JsonNode? provider)
    {
        if (provider?["reachable"] is JsonValue reachable &&
            reachable.TryGetValue(out bool isReachable) && isReachable)
        {
            return "reachable";
        }
        return $"unreachable ({provider?["error"]?.ToString() ?? "unknown"})";
    }
    
    // Checks whether each pipeline can reach its language model providers.
    // The /v1/health endpoint answers with HTTP 200 even when a provider is
    // down, so the status field is the thing to check: it is "healthy" or
    // "degraded". Prints the report, and returns whether the server is
    // healthy.
    static async Task<bool> CheckHealthAsync(HttpClient client)
    {
        var reply = await GetAsync(client, "/v1/health");
        if (reply["status"] is not JsonValue statusNode ||
            !statusNode.TryGetValue(out string? status))
        {
            throw new RagException($"Unexpected response: {reply.ToJsonString()}");
        }
    
        Console.WriteLine($"Health: {status}");
        if (reply["pipelines"] is JsonArray pipelines)
        {
            foreach (var pipeline in pipelines)
            {
                var embedding = DescribeProvider(pipeline?["embedding"]);
                var completion = DescribeProvider(pipeline?["completion"]);
                Console.WriteLine(
                    $"- {pipeline?["name"]}: embedding {embedding}, completion {completion}");
            }
        }
        return status == "healthy";
    }
    
    // Lists the pipelines that the server offers, with their descriptions.
    static async Task ListPipelinesAsync(HttpClient client)
    {
        var reply = await GetAsync(client, "/v1/pipelines");
        if (reply["pipelines"] is not JsonArray pipelines)
        {
            throw new RagException("Unexpected response: missing pipelines");
        }
    
        Console.WriteLine($"Pipelines ({pipelines.Count}):");
        foreach (var pipeline in pipelines)
        {
            var description = pipeline?["description"]?.ToString();
            if (string.IsNullOrEmpty(description))
            {
                description = "(no description)";
            }
            Console.WriteLine($"- {pipeline?["name"]}: {description}");
        }
    }
    
    bool healthy;
    try
    {
        // using disposes of the client, and closes its connections, when the
        // block exits, whether or not an error occurred.
        using var client = new HttpClient
        {
            Timeout = TimeSpan.FromSeconds(TimeoutSeconds),
        };
        await CheckLiveAsync(client);
        healthy = await CheckHealthAsync(client);
        await ListPipelinesAsync(client);
    }
    // HttpRequestException covers failures to reach the server, such as a
    // refused connection, and TaskCanceledException covers a timeout.
    catch (Exception e) when (
        e is HttpRequestException or TaskCanceledException or RagException)
    {
        Console.Error.WriteLine($"RAG Server error: {e.Message}");
        return 1;
    }
    
    // A degraded server still answers with HTTP 200, so report it with the
    // exit status.
    if (!healthy)
    {
        Console.Error.WriteLine("RAG Server is not healthy");
        return 1;
    }
    return 0;
    
    // C# requires type declarations to follow the top-level statements, so
    // the exception that the program throws for an error reply is declared
    // here, at the end.
    class RagException(string message) : Exception(message);
    
    ```

=== "Go"

    ```go
    // Ellie's Postgres Cookbook
    // Checking the health of the pgEdge RAG Server and listing its pipelines,
    // using net/http.
    //
    // These examples are for pgEdge RAG Server 2.0.0.
    //
    // Copyright (c) 2026, pgEdge, Inc.
    // This code is released under the PostgreSQL License.
    
    package main
    
    import (
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
    
    var baseURL = strings.TrimRight(envOr("RAG_SERVER_URL", "http://localhost:8080"), "/")
    
    // None of these endpoints calls a language model, but the health check
    // contacts each provider, so allow it some time.
    const timeout = 30 * time.Second
    
    // get fetches a path from the server, and decodes the reply into out.
    func get(client *http.Client, path string, out any) error {
    	response, err := client.Get(baseURL + path)
    	if err != nil {
    		return err
    	}
    	defer response.Body.Close()
    
    	body, err := io.ReadAll(response.Body)
    	if err != nil {
    		return err
    	}
    
    	// Go treats an error status as a normal response, so check it here.
    	if response.StatusCode != http.StatusOK {
    		return fmt.Errorf("HTTP %d, %.200s", response.StatusCode, strings.TrimSpace(string(body)))
    	}
    	if err := json.Unmarshal(body, out); err != nil {
    		return fmt.Errorf("unexpected response: %.200s", body)
    	}
    	return nil
    }
    
    
    // checkLive checks that the server process is running. The /v1/live
    // endpoint is cheap and calls nothing else, so it suits a frequent
    // liveness probe.
    func checkLive(client *http.Client) error {
    	var body struct {
    		Status string `json:"status"`
    	}
    	if err := get(client, "/v1/live", &body); err != nil {
    		return err
    	}
    	if body.Status != "ok" {
    		return fmt.Errorf("unexpected status %q", body.Status)
    	}
    	fmt.Println("Live: ok")
    	return nil
    }
    
    
    // provider reports whether a language model provider answered the check.
    type provider struct {
    	Reachable bool   `json:"reachable"`
    	Error     string `json:"error"`
    }
    
    // describe says in words whether the provider answered.
    func (p provider) describe() string {
    	if p.Reachable {
    		return "reachable"
    	}
    	if p.Error == "" {
    		return "unreachable (unknown)"
    	}
    	return "unreachable (" + p.Error + ")"
    }
    
    // checkHealth checks whether each pipeline can reach its language model
    // providers. The /v1/health endpoint answers with HTTP 200 even when a
    // provider is down, so the status field is the thing to check: it is
    // "healthy" or "degraded". It prints the report, and returns whether the
    // server is healthy.
    func checkHealth(client *http.Client) (bool, error) {
    	var body struct {
    		Status    *string `json:"status"`
    		Pipelines []struct {
    			Name       string   `json:"name"`
    			Embedding  provider `json:"embedding"`
    			Completion provider `json:"completion"`
    		} `json:"pipelines"`
    	}
    	if err := get(client, "/v1/health", &body); err != nil {
    		return false, err
    	}
    	if body.Status == nil {
    		return false, errors.New("unexpected response: missing status")
    	}
    
    	fmt.Printf("Health: %s\n", *body.Status)
    	for _, p := range body.Pipelines {
    		fmt.Printf("- %s: embedding %s, completion %s\n",
    			p.Name, p.Embedding.describe(), p.Completion.describe())
    	}
    	return *body.Status == "healthy", nil
    }
    
    
    // listPipelines lists the pipelines that the server offers, with their
    // descriptions.
    func listPipelines(client *http.Client) error {
    	var body struct {
    		Pipelines *[]struct {
    			Name        string `json:"name"`
    			Description string `json:"description"`
    		} `json:"pipelines"`
    	}
    	if err := get(client, "/v1/pipelines", &body); err != nil {
    		return err
    	}
    	if body.Pipelines == nil {
    		return errors.New("unexpected response: missing pipelines")
    	}
    
    	fmt.Printf("Pipelines (%d):\n", len(*body.Pipelines))
    	for _, p := range *body.Pipelines {
    		description := p.Description
    		if description == "" {
    			description = "(no description)"
    		}
    		fmt.Printf("- %s: %s\n", p.Name, description)
    	}
    	return nil
    }
    
    
    // run performs the checks and returns any error to the caller.
    func run() error {
    	client := &http.Client{Timeout: timeout}
    
    	if err := checkLive(client); err != nil {
    		return err
    	}
    	healthy, err := checkHealth(client)
    	if err != nil {
    		return err
    	}
    	if err := listPipelines(client); err != nil {
    		return err
    	}
    
    	// A degraded server still answers with HTTP 200, so report it with the
    	// exit status.
    	if !healthy {
    		return errors.New("the server is not healthy")
    	}
    	return nil
    }
    
    // main reports any error returned by run() and exits with a non-zero
    // status.
    func main() {
    	if err := run(); err != nil {
    		fmt.Fprintf(os.Stderr, "RAG Server error: %v\n", err)
    		os.Exit(1)
    	}
    }
    
    
    ```

=== "Rust"

    ```rust
    // Ellie's Postgres Cookbook
    // Checking the health of the pgEdge RAG Server and listing its pipelines,
    // using reqwest and serde_json.
    //
    // These examples are for pgEdge RAG Server 2.0.0.
    //
    // Copyright (c) 2026, pgEdge, Inc.
    // This code is released under the PostgreSQL License.
    
    use std::env;
    use std::error::Error;
    use std::process::ExitCode;
    use std::time::Duration;
    
    use reqwest::blocking::Client;
    use serde_json::Value;
    
    /// Returns the value of an environment variable, or a fallback if the
    /// variable is unset or empty.
    fn env_or(name: &str, fallback: &str) -> String {
        env::var(name)
            .ok()
            .filter(|value| !value.is_empty())
            .unwrap_or_else(|| fallback.to_string())
    }
    
    fn base_url() -> String {
        env_or("RAG_SERVER_URL", "http://localhost:8080")
            .trim_end_matches('/')
            .to_string()
    }
    
    /// None of these endpoints calls a language model, but the health check
    /// contacts each provider, so allow it some time.
    const TIMEOUT: Duration = Duration::from_secs(30);
    
    /// The errors that the functions below return; a string converts into one
    /// with the ? operator or into().
    type BoxError = Box<dyn Error>;
    
    /// Returns at most the first 200 characters of a reply.
    fn shorten(text: &str) -> String {
        text.chars().take(200).collect()
    }
    
    /// Fetches a path from the server, and returns the decoded reply.
    fn get(client: &Client, path: &str) -> Result<Value, BoxError> {
        let response = client.get(format!("{}{path}", base_url())).send()?;
        let status = response.status();
        let body = response.text()?;
        if !status.is_success() {
            return Err(format!("HTTP {}, {}", status.as_u16(), shorten(&body)).into());
        }
        match serde_json::from_str::<Value>(&body) {
            Ok(reply) if reply.is_object() => Ok(reply),
            _ => Err(format!("Unexpected response: {}", shorten(&body)).into()),
        }
    }
    
    /// Checks that the server process is running. The /v1/live endpoint is
    /// cheap and calls nothing else, so it suits a frequent liveness probe.
    fn check_live(client: &Client) -> Result<(), BoxError> {
        let reply = get(client, "/v1/live")?;
        if reply["status"].as_str() != Some("ok") {
            return Err(format!("Unexpected response: {reply}").into());
        }
        println!("Live: ok");
        Ok(())
    }
    
    /// Describes whether a language model provider answered the check.
    fn describe_provider(provider: &Value) -> String {
        if provider["reachable"].as_bool() == Some(true) {
            return "reachable".to_string();
        }
        format!("unreachable ({})", provider["error"].as_str().unwrap_or("unknown"))
    }
    
    /// Checks whether each pipeline can reach its language model providers.
    /// The /v1/health endpoint answers with HTTP 200 even when a provider is
    /// down, so the status field is the thing to check: it is "healthy" or
    /// "degraded". Prints the report, and returns whether the server is
    /// healthy.
    fn check_health(client: &Client) -> Result<bool, BoxError> {
        let reply = get(client, "/v1/health")?;
        let Some(status) = reply["status"].as_str() else {
            return Err(format!("Unexpected response: {reply}").into());
        };
    
        println!("Health: {status}");
        // as_array() gives None when the reply lists no pipelines.
        for pipeline in reply["pipelines"].as_array().into_iter().flatten() {
            println!(
                "- {}: embedding {}, completion {}",
                pipeline["name"].as_str().unwrap_or(""),
                describe_provider(&pipeline["embedding"]),
                describe_provider(&pipeline["completion"]),
            );
        }
        Ok(status == "healthy")
    }
    
    /// Lists the pipelines that the server offers, with their descriptions.
    fn list_pipelines(client: &Client) -> Result<(), BoxError> {
        let reply = get(client, "/v1/pipelines")?;
        let Some(pipelines) = reply["pipelines"].as_array() else {
            return Err("Unexpected response: missing pipelines".into());
        };
    
        println!("Pipelines ({}):", pipelines.len());
        for pipeline in pipelines {
            let description = match pipeline["description"].as_str() {
                Some(text) if !text.is_empty() => text,
                _ => "(no description)",
            };
            println!("- {}: {description}", pipeline["name"].as_str().unwrap_or(""));
        }
        Ok(())
    }
    
    /// Runs the three checks, and returns whether the server is healthy. The
    /// ? operator returns any error to the caller.
    fn run() -> Result<bool, BoxError> {
        let client = Client::builder().timeout(TIMEOUT).build()?;
        check_live(&client)?;
        let healthy = check_health(&client)?;
        list_pipelines(&client)?;
        Ok(healthy)
    }
    
    /// Reports any error returned by run() and exits with a failure status.
    /// The top-level error is often generic ("error sending request"), so the
    /// chain of underlying causes is printed too.
    fn main() -> ExitCode {
        match run() {
            Ok(true) => ExitCode::SUCCESS,
            // A degraded server still answers with HTTP 200, so report it
            // with the exit status.
            Ok(false) => {
                eprintln!("RAG Server is not healthy");
                ExitCode::FAILURE
            }
            Err(e) => {
                eprintln!("RAG Server error: {e}");
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
    # Checking the health of the pgEdge RAG Server and listing its pipelines,
    # using Net::HTTP.
    #
    # These examples are for pgEdge RAG Server 2.0.0.
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
    
    BASE_URL = env_or("RAG_SERVER_URL", "http://localhost:8080").sub(%r{/+\z}, "")
    
    # None of these endpoints calls a language model, but the health check
    # contacts each provider, so allow it some time.
    TIMEOUT_SECONDS = 30
    
    # Raised when the RAG Server rejects a request or replies oddly.
    class RagError < StandardError; end
    
    # Fetches a path from the server, and returns the decoded reply.
    def get(http, path)
      response = http.request(Net::HTTP::Get.new(URI("#{BASE_URL}#{path}")))
      unless response.is_a?(Net::HTTPSuccess)
        raise RagError, "HTTP #{response.code}, #{response.body.to_s[0, 200]}"
      end
    
      begin
        body = JSON.parse(response.body.to_s)
        return body if body.is_a?(Hash)
      rescue JSON::ParserError
        # The body is not JSON; report it below.
      end
      raise RagError, "Unexpected response: #{response.body.to_s[0, 200]}"
    end
    
    # Checks that the server process is running. The /v1/live endpoint is
    # cheap and calls nothing else, so it suits a frequent liveness probe.
    def check_live(http)
      body = get(http, "/v1/live")
      raise RagError, "Unexpected response: #{body}" unless body["status"] == "ok"
    
      puts "Live: ok"
    end
    
    # Describes whether a language model provider answered the check.
    def describe_provider(provider)
      return "reachable" if provider["reachable"]
    
      "unreachable (#{provider.fetch("error", "unknown")})"
    end
    
    # Checks whether each pipeline can reach its language model providers.
    # The /v1/health endpoint answers with HTTP 200 even when a provider is
    # down, so the status field is the thing to check: it is "healthy" or
    # "degraded". Prints the report, and returns whether the server is
    # healthy.
    def check_health(http)
      body = get(http, "/v1/health")
      status = body["status"]
      raise RagError, "Unexpected response: #{body}" unless status.is_a?(String)
    
      puts "Health: #{status}"
      (body["pipelines"] || []).each do |pipeline|
        embedding = describe_provider(pipeline["embedding"] || {})
        completion = describe_provider(pipeline["completion"] || {})
        puts "- #{pipeline["name"]}: embedding #{embedding}, completion #{completion}"
      end
      status == "healthy"
    end
    
    # Lists the pipelines that the server offers, with their descriptions.
    def list_pipelines(http)
      pipelines = get(http, "/v1/pipelines")["pipelines"]
      raise RagError, "Unexpected response: missing pipelines" unless pipelines.is_a?(Array)
    
      puts "Pipelines (#{pipelines.length}):"
      pipelines.each do |pipeline|
        description = pipeline["description"]
        description = "(no description)" if description.nil? || description.empty?
        puts "- #{pipeline["name"]}: #{description}"
      end
    end
    
    begin
      uri = URI(BASE_URL)
      # start opens a connection, and closes it when the block exits, whether
      # or not an error occurred.
      healthy = Net::HTTP.start(
        uri.host, uri.port,
        use_ssl: uri.scheme == "https",
        open_timeout: TIMEOUT_SECONDS, read_timeout: TIMEOUT_SECONDS
      ) do |http|
        check_live(http)
        result = check_health(http)
        list_pipelines(http)
        result
      end
    # SystemCallError covers a refused connection, Timeout::Error covers the
    # connection and read timeouts, and SocketError covers an unknown host.
    rescue RagError, SystemCallError, Timeout::Error, SocketError, IOError => e
      warn "RAG Server error: #{e.message}"
      exit 1
    end
    
    # A degraded server still answers with HTTP 200, so report it with the
    # exit status.
    unless healthy
      warn "RAG Server is not healthy"
      exit 1
    end
    
    ```

=== "curl"

    ```bash
    #!/usr/bin/env bash
    #
    # Ellie's Postgres Cookbook
    # Checking the health of the pgEdge RAG Server and listing its pipelines,
    # using curl and jq.
    #
    # These examples are for pgEdge RAG Server 2.0.0.
    #
    # Copyright (c) 2026, pgEdge, Inc.
    # This code is released under the PostgreSQL License.
    
    # Stop at the first failed command or unset variable, and treat a failure
    # anywhere in a pipeline as a failure of the whole pipeline.
    set -euo pipefail
    
    for tool in curl jq; do
        command -v "$tool" >/dev/null || { echo "$tool is required" >&2; exit 1; }
    done
    
    # The :- operator treats an empty variable as unset.
    RAG_SERVER_URL="${RAG_SERVER_URL:-http://localhost:8080}"
    RAG_SERVER_URL="${RAG_SERVER_URL%/}"
    
    # None of these endpoints calls a language model, but the health check
    # contacts each provider, so allow it some time.
    TIMEOUT_SECONDS=30
    
    # Fetches a path from the server and prints the JSON reply. With
    # --fail-with-body, curl exits non-zero on an HTTP error status but still
    # prints the body, which carries the server's explanation.
    get() {
        curl --silent --show-error --fail-with-body \
            --max-time "$TIMEOUT_SECONDS" "$RAG_SERVER_URL$1"
    }
    
    # Checks that the server process is running. The /v1/live endpoint is
    # cheap and calls nothing else, so it suits a frequent liveness probe. The
    # error call makes jq fail unless the status is the string "ok".
    check_live() {
        local response
        response="$(get /v1/live)" || {
            echo "RAG Server error: $response" >&2
            return 1
        }
        jq -er 'if .status == "ok" then "Live: ok"
                else error("status is not ok") end' <<<"$response" || {
            echo "Unexpected response: $response" >&2
            return 1
        }
    }
    
    # Checks whether each pipeline can reach its language model providers.
    # The /v1/health endpoint answers with HTTP 200 even when a provider is
    # down, so curl succeeds either way; the status field is "healthy" or
    # "degraded". This function prints the report, returns 1 when a request
    # or reply fails, and returns 2 when the status is anything but "healthy".
    check_health() {
        local response
        response="$(get /v1/health)" || {
            echo "RAG Server error: $response" >&2
            return 1
        }
        jq -er '
            def provider:
                if .reachable then "reachable"
                else "unreachable (\(.error // "unknown"))" end;
    
            if (.status | type) != "string" then error("missing status") else
                "Health: \(.status)",
                ((.pipelines // [])[]
                 | "- \(.name): embedding \(.embedding | provider), "
                   + "completion \(.completion | provider)")
            end' <<<"$response" || {
            echo "Unexpected response: $response" >&2
            return 1
        }
        [[ "$(jq -r '.status' <<<"$response")" == "healthy" ]] || {
            echo "RAG Server is not healthy" >&2
            return 2
        }
    }
    
    # Lists the pipelines that the server offers, with their descriptions.
    list_pipelines() {
        local response
        response="$(get /v1/pipelines)" || {
            echo "RAG Server error: $response" >&2
            return 1
        }
        jq -er '
            if (.pipelines | type) != "array" then error("missing pipelines") else
                "Pipelines (\(.pipelines | length)):",
                (.pipelines[] | "- \(.name): \(.description // "(no description)")")
            end' <<<"$response" || {
            echo "Unexpected response: $response" >&2
            return 1
        }
    }
    
    main() {
        local status=0 result=0
    
        # Stop at the first request that fails, as the other examples do. A
        # degraded server still answers every request, so carry on and list the
        # pipelines, and then exit non-zero.
        check_live || exit 1
        check_health || result=$?
        if [[ "$result" -eq 2 ]]; then
            status=1
        elif [[ "$result" -ne 0 ]]; then
            exit 1
        fi
        list_pipelines || exit 1
        exit "$status"
    }
    
    main
    
    ```

## Next Steps

The following resources provide more information about the topics in this
recipe:

- The [Handling RAG Server Errors](handle_errors.md) recipe shows how to react
  to the errors that a query can return.
- The [Asking a Question](ask_question.md) recipe shows how to query one of the
  pipelines that this recipe lists.
- The
  [pgEdge RAG Server documentation](https://docs.pgedge.com/pgedge-rag-server/)
  describes every endpoint and setting.
- The [Contributing a Recipe](../contributing.md) page explains how to add a
  recipe or a language to the cookbook.
