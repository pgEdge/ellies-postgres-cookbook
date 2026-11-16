# Handling RAG Server Errors

This recipe makes two requests that the pgEdge RAG Server must refuse, and
shows how a program can tell the failures apart by the error code in the reply.
A program that branches on the code can retry a temporary failure, correct a
bad request, or report a setting that is wrong, whereas one that only checks
the HTTP status cannot. Each step shows the code in every supported language;
selecting a language tab switches every tab on the site to that language.

These examples are for pgEdge RAG Server 2.0.0.

The program prints the following output:

```text
Asking a pipeline that does not exist
  PIPELINE_NOT_FOUND (HTTP 404): pipeline not found: no-such-pipeline
  Check the pipeline name; GET /v1/pipelines lists the pipelines.
Asking an empty question
  INVALID_REQUEST (HTTP 400): query is required
  Fix the request; the body must be JSON with a non-empty query.
```

## Preparing the Ingredients

The examples assume a running RAG Server with a pipeline named `cookbook` that
holds the fictional Acme Widget support documents. The
`scripts/start_rag_server.sh` script in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook) loads
those documents and starts the server in Docker, and the
[Preparing Data for the RAG Server](prepare_data.md) recipe shows how to build
such a table and pipeline yourself.

When a request fails, the server replies with an HTTP error status and a JSON
body of the following form, where `code` is a fixed string for a program to
read and `message` is text for a person to read, which may change between
releases:

```json
{"error": {"code": "PIPELINE_NOT_FOUND", "message": "pipeline not found: no-such-pipeline"}}
```

The following table lists the codes that a query can return; the programs in
this recipe provoke the first two:

| Code                    | HTTP status | Meaning                                 |
|-------------------------|-------------|-----------------------------------------|
| `PIPELINE_NOT_FOUND`    | 404         | No pipeline has the name in the URL.    |
| `INVALID_REQUEST`       | 400         | The body is not valid, or has no query. |
| `REQUEST_TOO_LARGE`     | 413         | The body exceeds the size limit.        |
| `REQUEST_TIMEOUT`       | 504         | The request took too long.              |
| `RETRIEVAL_UNAVAILABLE` | 503         | The pipeline cannot search at present.  |
| `INTERNAL_ERROR`        | 500         | The server failed unexpectedly.         |

The server can return other codes, such as `RETRIEVAL_REFUSED`,
`RETRIEVAL_FAILED`, `EXECUTION_ERROR`, and `STREAMING_ERROR`, so a program
needs a fallback for a code that it does not know.

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
      "name": "handle-errors",
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
    from urllib.parse import quote
    
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
    import java.net.URLEncoder;
    import java.net.http.HttpClient;
    import java.net.http.HttpRequest;
    import java.net.http.HttpResponse;
    import java.net.http.HttpTimeoutException;
    import java.nio.charset.StandardCharsets;
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
    use std::fmt;
    use std::process::ExitCode;
    use std::time::Duration;
    
    use reqwest::blocking::Client;
    use reqwest::Url;
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
    
    for tool in curl jq; do
        command -v "$tool" >/dev/null || { echo "$tool is required" >&2; exit 1; }
    done
    ```

## Configuring the Program

The examples read the address of the RAG Server from the `RAG_SERVER_URL`
environment variable, and treat an empty value as unset. The `RAG_PIPELINE`
variable names a pipeline that exists, and the program uses a made-up name for
the pipeline that does not. Both requests fail before the server calls a
language model, so each program allows 30 seconds for a reply. The following
table describes the environment variables:

| Variable         | Default                 | Description                      |
|------------------|-------------------------|----------------------------------|
| `RAG_SERVER_URL` | `http://localhost:8080` | The base URL of the RAG Server.  |
| `RAG_PIPELINE`   | `cookbook`              | The name of the pipeline to ask. |

The following tabs show how each program reads its settings:

=== "Python"

    ```python
    # The or operator treats an empty variable as unset.
    BASE_URL = (os.environ.get("RAG_SERVER_URL") or "http://localhost:8080").rstrip("/")
    PIPELINE = os.environ.get("RAG_PIPELINE") or "cookbook"
    
    # A pipeline name that no server has, to cause PIPELINE_NOT_FOUND.
    MISSING_PIPELINE = "no-such-pipeline"
    
    # The server rejects both requests before it calls a language model, so
    # they answer quickly.
    TIMEOUT_SECONDS = 30.0
    ```

=== "TypeScript"

    ```typescript
    // The || operator, unlike ??, also treats an empty variable as unset.
    const baseUrl = (process.env.RAG_SERVER_URL || "http://localhost:8080").replace(/\/+$/, "");
    const pipeline = process.env.RAG_PIPELINE || "cookbook";
    
    // A pipeline name that no server has, to cause PIPELINE_NOT_FOUND.
    const missingPipeline = "no-such-pipeline";
    
    // The server rejects both requests before it calls a language model, so
    // they answer quickly.
    const timeoutMs = 30_000;
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
    static final String PIPELINE = envOr("RAG_PIPELINE", "cookbook");
    
    // A pipeline name that no server has, to cause PIPELINE_NOT_FOUND.
    static final String MISSING_PIPELINE = "no-such-pipeline";
    
    // The server rejects both requests before it calls a language model,
    // so they answer quickly.
    static final Duration TIMEOUT = Duration.ofSeconds(30);
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
    static string Pipeline() => EnvOr("RAG_PIPELINE", "cookbook");
    
    // A pipeline name that no server has, to cause PIPELINE_NOT_FOUND.
    const string MissingPipeline = "no-such-pipeline";
    
    // The server rejects both requests before it calls a language model, so
    // they answer quickly.
    const int TimeoutSeconds = 30;
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
    	baseURL  = strings.TrimRight(envOr("RAG_SERVER_URL", "http://localhost:8080"), "/")
    	pipeline = envOr("RAG_PIPELINE", "cookbook")
    )
    
    // A pipeline name that no server has, to cause PIPELINE_NOT_FOUND.
    const missingPipeline = "no-such-pipeline"
    
    // The server rejects both requests before it calls a language model, so
    // they answer quickly.
    const timeout = 30 * time.Second
    
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
    
    fn pipeline() -> String {
        env_or("RAG_PIPELINE", "cookbook")
    }
    
    /// A pipeline name that no server has, to cause PIPELINE_NOT_FOUND.
    const MISSING_PIPELINE: &str = "no-such-pipeline";
    
    /// The server rejects both requests before it calls a language model, so
    /// they answer quickly.
    const TIMEOUT: Duration = Duration::from_secs(30);
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
    PIPELINE = env_or("RAG_PIPELINE", "cookbook")
    
    # A pipeline name that no server has, to cause PIPELINE_NOT_FOUND.
    MISSING_PIPELINE = "no-such-pipeline"
    
    # The server rejects both requests before it calls a language model, so
    # they answer quickly.
    TIMEOUT_SECONDS = 30
    ```

=== "curl"

    ```bash
    # The :- operator treats an empty variable as unset.
    RAG_SERVER_URL="${RAG_SERVER_URL:-http://localhost:8080}"
    RAG_SERVER_URL="${RAG_SERVER_URL%/}"
    RAG_PIPELINE="${RAG_PIPELINE:-cookbook}"
    
    # A pipeline name that no server has, to cause PIPELINE_NOT_FOUND.
    MISSING_PIPELINE="no-such-pipeline"
    
    # The server rejects both requests before it calls a language model, so
    # they answer quickly.
    TIMEOUT_SECONDS=30
    
    # Escapes a value for use in a URL path, as the other languages do.
    escape() { jq -rn --arg value "$1" '$value | @uri'; }
    ```

## Sending a Request and Reading the Error

Each program sends a query, and turns an error reply into an error that holds
the HTTP status, the code, and the message. A reply that is not in the expected
form, such as one from a proxy in front of the server, becomes a different
error, because it has no code to read. The following tabs show how each program
sends a query:

=== "Python"

    ```python
    class RagError(Exception):
        """Raised when a reply is not one that the program can interpret."""
    
    
    class ApiError(Exception):
        """Raised when the RAG Server replies with an error. The reply has an
        HTTP status and a JSON body of the form
        {"error": {"code": "...", "message": "..."}}."""
    
        def __init__(self, status: int, code: str, message: str):
            super().__init__(f"{code}: {message}")
            self.status = status
            self.code = code
            self.message = message
    
    
    def send_query(client: httpx.Client, pipeline: str, query: str) -> dict:
        """Sends a query to a pipeline, and returns the decoded reply. Raises
        ApiError when the server replies with an error."""
        response = client.post(
            f"/v1/pipelines/{quote(pipeline, safe='')}", json={"query": query}
        )
        if response.is_error:
            try:
                error = response.json()["error"]
                raise ApiError(response.status_code, error["code"], error["message"])
            except (ValueError, KeyError, TypeError):
                raise RagError(
                    f"HTTP {response.status_code}, {response.text[:200]}"
                ) from None
        return response.json()
    ```

=== "TypeScript"

    ```typescript
    // ApiError is thrown when the RAG Server replies with an error. The reply
    // has an HTTP status and a JSON body of the form
    // {"error": {"code": "...", "message": "..."}}.
    class ApiError extends Error {
      constructor(
        readonly status: number,
        readonly code: string,
        message: string,
      ) {
        super(message);
      }
    }
    
    // Sends a query to a pipeline, and returns the decoded reply. Throws an
    // ApiError when the server replies with an error.
    async function sendQuery(name: string, query: string): Promise<unknown> {
      const response = await fetch(
        `${baseUrl}/v1/pipelines/${encodeURIComponent(name)}`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ query }),
          signal: AbortSignal.timeout(timeoutMs),
        },
      );
    
      // fetch only rejects when it cannot reach the server; an error status
      // is a normal response, so check it explicitly.
      if (!response.ok) {
        const text = await response.text();
        let error: { code?: unknown; message?: unknown } | undefined;
        try {
          error = JSON.parse(text).error;
        } catch {
          // Fall through to the generic error below.
        }
        if (typeof error?.code === "string" && typeof error.message === "string") {
          throw new ApiError(response.status, error.code, error.message);
        }
        throw new Error(`HTTP ${response.status}, ${text.slice(0, 200)}`);
      }
      return response.json();
    }
    ```

=== "Java"

    ```java
    /** Thrown when a reply is not one that the program can interpret. */
    static class RagException extends Exception {
        RagException(String message) {
            super(message);
        }
    }
    
    /**
     * Thrown when the RAG Server replies with an error. The reply has an
     * HTTP status and a JSON body of the form
     * {"error": {"code": "...", "message": "..."}}.
     */
    static class ApiException extends Exception {
        final int status;
        final String code;
        final String message;
    
        ApiException(int status, String code, String message) {
            super(code + ": " + message);
            this.status = status;
            this.code = code;
            this.message = message;
        }
    }
    
    // A mapper is safe to share, so the program creates only one.
    static final ObjectMapper MAPPER = JsonMapper.builder().build();
    
    /** Returns at most the first 200 characters of a reply. */
    static String shorten(String text) {
        return text.length() > 200 ? text.substring(0, 200) : text;
    }
    
    /**
     * Returns the URL of a pipeline. URLEncoder escapes any character that
     * is not safe in a URL, but it writes a space as + for an HTML form,
     * so the + becomes %20 for use in a URL path.
     */
    static URI pipelineUri(String pipeline) {
        String name = URLEncoder.encode(pipeline, StandardCharsets.UTF_8)
                .replace("+", "%20");
        return URI.create(BASE_URL + "/v1/pipelines/" + name);
    }
    
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
    
    /**
     * Sends a query to a pipeline, and returns the decoded reply. Throws
     * ApiException when the server replies with an error.
     */
    static JsonNode sendQuery(HttpClient client, String pipeline, String query)
            throws IOException, InterruptedException, RagException, ApiException {
        HttpRequest request = HttpRequest.newBuilder(pipelineUri(pipeline))
                .timeout(TIMEOUT)
                .header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString(MAPPER.writeValueAsString(
                        MAPPER.createObjectNode().put("query", query))))
                .build();
        HttpResponse<String> response = send(client, request);
    
        JsonNode body;
        try {
            body = MAPPER.readTree(response.body());
        } catch (JacksonException e) {
            throw new RagException("HTTP " + response.statusCode() + ", "
                    + shorten(response.body()));
        }
    
        if (response.statusCode() >= 400) {
            JsonNode error = body.path("error");
            if (!error.path("code").isString() || !error.path("message").isString()) {
                throw new RagException("HTTP " + response.statusCode() + ", "
                        + shorten(response.body()));
            }
            throw new ApiException(response.statusCode(),
                    error.path("code").stringValue(),
                    error.path("message").stringValue());
        }
        return body;
    }
    ```

=== "C#"

    ```csharp
    // Returns at most the first 200 characters of a reply.
    static string Shorten(string text) =>
        text.Length > 200 ? text[..200] : text;
    
    // Sends a query to a pipeline, and returns the decoded reply. Throws
    // ApiException when the server replies with an error.
    static async Task<JsonNode?> SendQueryAsync(
        HttpClient client, string pipeline, string query)
    {
        var url = $"{BaseUrl()}/v1/pipelines/{Uri.EscapeDataString(pipeline)}";
        using var response = await client.PostAsync(
            url, JsonContent.Create(new { query }));
        var body = await response.Content.ReadAsStringAsync();
        var status = (int)response.StatusCode;
    
        JsonNode? reply;
        try
        {
            reply = JsonNode.Parse(body);
        }
        catch (JsonException)
        {
            throw new RagException($"HTTP {status}, {Shorten(body)}");
        }
    
        if (!response.IsSuccessStatusCode)
        {
            if (reply?["error"] is JsonObject error &&
                error["code"] is JsonValue codeNode &&
                codeNode.TryGetValue(out string? code) &&
                error["message"] is JsonValue messageNode &&
                messageNode.TryGetValue(out string? message))
            {
                throw new ApiException(status, code, message);
            }
            throw new RagException($"HTTP {status}, {Shorten(body)}");
        }
        return reply;
    }
    ```

=== "Go"

    ```go
    // apiError is returned when the RAG Server replies with an error. The
    // reply has an HTTP status and a JSON body of the form
    // {"error": {"code": "...", "message": "..."}}.
    type apiError struct {
    	Status  int
    	Code    string
    	Message string
    }
    
    func (e *apiError) Error() string {
    	return fmt.Sprintf("%s: %s", e.Code, e.Message)
    }
    
    // sendQuery sends a query to a pipeline. It returns an *apiError when the
    // server replies with an error.
    func sendQuery(client *http.Client, name, query string) error {
    	payload, err := json.Marshal(map[string]string{"query": query})
    	if err != nil {
    		return err
    	}
    
    	endpoint := baseURL + "/v1/pipelines/" + url.PathEscape(name)
    	response, err := client.Post(endpoint, "application/json", bytes.NewReader(payload))
    	if err != nil {
    		return err
    	}
    	defer response.Body.Close()
    
    	body, err := io.ReadAll(response.Body)
    	if err != nil {
    		return err
    	}
    
    	// Go treats an error status as a normal response, so check it here.
    	if response.StatusCode == http.StatusOK {
    		return nil
    	}
    	var e struct {
    		Error struct {
    			Code    string `json:"code"`
    			Message string `json:"message"`
    		} `json:"error"`
    	}
    	if json.Unmarshal(body, &e) != nil || e.Error.Code == "" {
    		return fmt.Errorf("HTTP %d, %.200s", response.StatusCode, strings.TrimSpace(string(body)))
    	}
    	return &apiError{response.StatusCode, e.Error.Code, e.Error.Message}
    }
    
    ```

=== "Rust"

    ```rust
    /// The errors that the functions below return; a string converts into one
    /// with the ? operator or into().
    type BoxError = Box<dyn Error>;
    
    /// An error reply from the RAG Server, which has an HTTP status and a JSON
    /// body of the form {"error": {"code": "...", "message": "..."}}.
    #[derive(Debug)]
    struct ApiError {
        status: u16,
        code: String,
        message: String,
    }
    
    impl fmt::Display for ApiError {
        fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
            write!(f, "{}: {}", self.code, self.message)
        }
    }
    
    impl Error for ApiError {}
    
    /// The outcome of a query that reached the server: an ApiError when the
    /// server replied with an error, or any other error when the reply could
    /// not be had or understood.
    enum QueryError {
        Api(ApiError),
        Other(BoxError),
    }
    
    /// Lets the ? operator turn any other error into QueryError::Other.
    impl<E: Into<BoxError>> From<E> for QueryError {
        fn from(e: E) -> Self {
            QueryError::Other(e.into())
        }
    }
    
    /// Returns at most the first 200 characters of a reply.
    fn shorten(text: &str) -> String {
        text.chars().take(200).collect()
    }
    
    /// Returns the URL of a pipeline. push() escapes any character in the
    /// pipeline name that is not safe in a URL path.
    fn pipeline_url(name: &str) -> Result<Url, BoxError> {
        let mut url = Url::parse(&format!("{}/v1/pipelines/", base_url()))?;
        url.path_segments_mut()
            .map_err(|()| "RAG_SERVER_URL cannot be a base URL")?
            .pop_if_empty()
            .push(name);
        Ok(url)
    }
    
    /// Sends a query to a pipeline, and returns the decoded reply. Returns
    /// QueryError::Api when the server replies with an error.
    fn send_query(client: &Client, pipeline: &str, query: &str) -> Result<Value, QueryError> {
        let response = client
            .post(pipeline_url(pipeline)?)
            .json(&json!({ "query": query }))
            .send()?;
        let status = response.status();
        let body = response.text()?;
    
        let reply: Value = match serde_json::from_str(&body) {
            Ok(reply) => reply,
            Err(_) => return Err(format!("HTTP {}, {}", status.as_u16(), shorten(&body)).into()),
        };
    
        if !status.is_success() {
            let error = &reply["error"];
            return match (error["code"].as_str(), error["message"].as_str()) {
                (Some(code), Some(message)) => Err(QueryError::Api(ApiError {
                    status: status.as_u16(),
                    code: code.to_string(),
                    message: message.to_string(),
                })),
                _ => Err(format!("HTTP {}, {}", status.as_u16(), shorten(&body)).into()),
            };
        }
        Ok(reply)
    }
    ```

=== "Ruby"

    ```ruby
    # Raised when a reply is not one that the program can interpret.
    class RagError < StandardError; end
    
    # Raised when the RAG Server replies with an error. The reply has an HTTP
    # status and a JSON body of the form
    # {"error": {"code": "...", "message": "..."}}.
    class ApiError < StandardError
      attr_reader :status, :code, :detail
    
      def initialize(status, code, detail)
        super("#{code}: #{detail}")
        @status = status
        @code = code
        @detail = detail
      end
    end
    
    # Sends a query to a pipeline, and returns the decoded reply. Raises
    # ApiError when the server replies with an error.
    def send_query(http, pipeline, query)
      uri = URI("#{BASE_URL}/v1/pipelines/#{URI.encode_uri_component(pipeline)}")
      request = Net::HTTP::Post.new(uri, "Content-Type" => "application/json")
      request.body = JSON.generate({ query: query })
      response = http.request(request)
      status = response.code.to_i
    
      begin
        body = JSON.parse(response.body.to_s)
      rescue JSON::ParserError
        raise RagError, "HTTP #{status}, #{response.body.to_s[0, 200]}"
      end
    
      unless response.is_a?(Net::HTTPSuccess)
        error = body.is_a?(Hash) ? body["error"] : nil
        unless error.is_a?(Hash) && error["code"].is_a?(String) && error["message"].is_a?(String)
          raise RagError, "HTTP #{status}, #{response.body.to_s[0, 200]}"
        end
    
        raise ApiError.new(status, error["code"], error["message"])
      end
    
      body
    end
    ```

=== "curl"

    ```bash
    # Sends a query to a pipeline. On success, the function prints the JSON
    # reply. On an error reply, it sets the variables STATUS, CODE, and MESSAGE
    # from the HTTP status and the "error" object in the body, and returns 1.
    # With --fail-with-body, curl exits non-zero on an HTTP error status but
    # still prints the body; --write-out adds the HTTP status after it. When
    # the server cannot be reached at all, curl prints status 000 and the
    # function exits the program, since there is no reply to branch on. The
    # script leaves out --show-error, because it reports each failure itself.
    STATUS="" CODE="" MESSAGE=""
    send_query() {
        local pipeline="$1" query="$2" output rc=0
        output="$(jq -n --arg query "$query" '{query: $query}' |
            curl --silent --fail-with-body \
                --max-time "$TIMEOUT_SECONDS" \
                --header 'Content-Type: application/json' \
                --data-binary @- \
                --write-out '\n%{http_code}' \
                "$RAG_SERVER_URL/v1/pipelines/$(escape "$pipeline")")" || rc=$?
    
        STATUS="${output##*$'\n'}"
        local body="${output%$'\n'*}"
        if [[ "$STATUS" == 000 ]]; then
            echo "RAG Server error: could not reach $RAG_SERVER_URL" >&2
            exit 1
        fi
        [[ $rc -eq 0 ]] && { printf '%s\n' "$body"; return 0; }
    
        # An error reply has the form {"error": {"code": "...", "message": "..."}}.
        CODE="$(jq -r '.error.code // empty' <<<"$body" 2>/dev/null || true)"
        MESSAGE="$(jq -r '.error.message // empty' <<<"$body" 2>/dev/null || true)"
        if [[ -z "$CODE" ]]; then
            echo "RAG Server error: HTTP $STATUS, ${body:0:200}" >&2
            exit 1
        fi
        return 1
    }
    ```

## Choosing a Response

Each program branches on the error code, and not on the message, to choose its
advice. The HTTP status is the fallback for temporary failures, which a program
can retry, and a code that the program does not know gets a general message.
The following tabs show how each program chooses a response:

=== "Python"

    ```python
    def advise(err: ApiError) -> str:
        """Returns advice for an error, chosen by the error code. Branch on the
        code rather than on the message, which is meant for people and may
        change; branch on the HTTP status only for the temporary failures that
        have no code worth handling individually."""
        if err.code == "PIPELINE_NOT_FOUND":
            return "Check the pipeline name; GET /v1/pipelines lists the pipelines."
        if err.code == "INVALID_REQUEST":
            return "Fix the request; the body must be JSON with a non-empty query."
        if err.status in (503, 504):
            return "The failure may be temporary, so retry the request later."
        return f"This program does not handle {err.code}."
    ```

=== "TypeScript"

    ```typescript
    // Returns advice for an error, chosen by the error code. Branch on the
    // code rather than on the message, which is meant for people and may
    // change; branch on the HTTP status only for the temporary failures that
    // have no code worth handling individually.
    function advise(err: ApiError): string {
      switch (err.code) {
        case "PIPELINE_NOT_FOUND":
          return "Check the pipeline name; GET /v1/pipelines lists the pipelines.";
        case "INVALID_REQUEST":
          return "Fix the request; the body must be JSON with a non-empty query.";
        default:
          if (err.status === 503 || err.status === 504) {
            return "The failure may be temporary, so retry the request later.";
          }
          return `This program does not handle ${err.code}.`;
      }
    }
    ```

=== "Java"

    ```java
    /**
     * Returns advice for an error, chosen by the error code. Branch on the
     * code rather than on the message, which is meant for people and may
     * change; branch on the HTTP status only for the temporary failures
     * that have no code worth handling individually.
     */
    static String advise(ApiException err) {
        if (err.code.equals("PIPELINE_NOT_FOUND")) {
            return "Check the pipeline name; GET /v1/pipelines lists the pipelines.";
        }
        if (err.code.equals("INVALID_REQUEST")) {
            return "Fix the request; the body must be JSON with a non-empty query.";
        }
        if (err.status == 503 || err.status == 504) {
            return "The failure may be temporary, so retry the request later.";
        }
        return "This program does not handle " + err.code + ".";
    }
    ```

=== "C#"

    ```csharp
    // Returns advice for an error, chosen by the error code. Branch on the code
    // rather than on the message, which is meant for people and may change;
    // branch on the HTTP status only for the temporary failures that have no
    // code worth handling individually.
    static string Advise(ApiException err) => err switch
    {
        { Code: "PIPELINE_NOT_FOUND" } =>
            "Check the pipeline name; GET /v1/pipelines lists the pipelines.",
        { Code: "INVALID_REQUEST" } =>
            "Fix the request; the body must be JSON with a non-empty query.",
        { Status: 503 or 504 } =>
            "The failure may be temporary, so retry the request later.",
        _ => $"This program does not handle {err.Code}.",
    };
    ```

=== "Go"

    ```go
    // advise returns advice for an error, chosen by the error code. Branch on
    // the code rather than on the message, which is meant for people and may
    // change; branch on the HTTP status only for the temporary failures that
    // have no code worth handling individually.
    func advise(e *apiError) string {
    	switch {
    	case e.Code == "PIPELINE_NOT_FOUND":
    		return "Check the pipeline name; GET /v1/pipelines lists the pipelines."
    	case e.Code == "INVALID_REQUEST":
    		return "Fix the request; the body must be JSON with a non-empty query."
    	case e.Status == http.StatusServiceUnavailable, e.Status == http.StatusGatewayTimeout:
    		return "The failure may be temporary, so retry the request later."
    	default:
    		return "This program does not handle " + e.Code + "."
    	}
    }
    
    ```

=== "Rust"

    ```rust
    /// Returns advice for an error, chosen by the error code. Branch on the
    /// code rather than on the message, which is meant for people and may
    /// change; branch on the HTTP status only for the temporary failures that
    /// have no code worth handling individually.
    fn advise(err: &ApiError) -> String {
        match (err.code.as_str(), err.status) {
            ("PIPELINE_NOT_FOUND", _) => {
                "Check the pipeline name; GET /v1/pipelines lists the pipelines.".to_string()
            }
            ("INVALID_REQUEST", _) => {
                "Fix the request; the body must be JSON with a non-empty query.".to_string()
            }
            (_, 503 | 504) => "The failure may be temporary, so retry the request later.".to_string(),
            (code, _) => format!("This program does not handle {code}."),
        }
    }
    ```

=== "Ruby"

    ```ruby
    # Returns advice for an error, chosen by the error code. Branch on the code
    # rather than on the message, which is meant for people and may change;
    # branch on the HTTP status only for the temporary failures that have no
    # code worth handling individually.
    def advise(err)
      return "Check the pipeline name; GET /v1/pipelines lists the pipelines." if err.code == "PIPELINE_NOT_FOUND"
      return "Fix the request; the body must be JSON with a non-empty query." if err.code == "INVALID_REQUEST"
      return "The failure may be temporary, so retry the request later." if [503, 504].include?(err.status)
    
      "This program does not handle #{err.code}."
    end
    ```

=== "curl"

    ```bash
    # Returns advice for an error, chosen by the error code. Branch on the
    # code rather than on the message, which is meant for people and may
    # change; branch on the HTTP status only for the temporary failures that
    # have no code worth handling individually.
    advise() {
        case "$CODE" in
            PIPELINE_NOT_FOUND)
                echo "Check the pipeline name; GET /v1/pipelines lists the pipelines." ;;
            INVALID_REQUEST)
                echo "Fix the request; the body must be JSON with a non-empty query." ;;
            *)
                case "$STATUS" in
                    503|504) echo "The failure may be temporary, so retry the request later." ;;
                    *)       echo "This program does not handle $CODE." ;;
                esac ;;
        esac
    }
    ```

## Handling Errors

The main part of each program provokes the two errors, prints how it handles
each, and fails if the server replies in any other way. It reports any other
failure on `stderr`, and exits with a non-zero status. The following tabs show
the main part of each program:

=== "Python"

    ```python
    def demonstrate(
        client: httpx.Client, title: str, pipeline: str, query: str, expected: str
    ) -> None:
        """Sends one query that the server must refuse with the expected error
        code, and prints how the program handles the refusal. Any other outcome
        is a failure."""
        print(title)
        try:
            send_query(client, pipeline, query)
        except ApiError as e:
            print(f"  {e.code} (HTTP {e.status}): {e.message}")
            print(f"  {advise(e)}")
            if e.code != expected:
                raise RagError(f"expected {expected}, got {e.code}") from None
            return
        raise RagError("the request unexpectedly succeeded")
    
    
    def main() -> int:
        try:
            with httpx.Client(base_url=BASE_URL, timeout=TIMEOUT_SECONDS) as client:
                demonstrate(client, "Asking a pipeline that does not exist",
                            MISSING_PIPELINE, "Hello", "PIPELINE_NOT_FOUND")
                demonstrate(client, "Asking an empty question",
                            PIPELINE, "", "INVALID_REQUEST")
        # httpx.HTTPError is the base class for failures to reach the server,
        # such as a refused connection or a timeout.
        except (httpx.HTTPError, RagError) as e:
            print(f"RAG Server error: {e}", file=sys.stderr)
            return 1
    
        return 0
    
    
    if __name__ == "__main__":
        sys.exit(main())
    ```

=== "TypeScript"

    ```typescript
    // Sends one query that the server must refuse with the expected error
    // code, and prints how the program handles the refusal. Any other outcome
    // is a failure.
    async function demonstrate(
      title: string,
      name: string,
      query: string,
      expected: string,
    ): Promise<void> {
      console.log(title);
      try {
        await sendQuery(name, query);
      } catch (err) {
        if (!(err instanceof ApiError)) {
          throw err;
        }
        console.log(`  ${err.code} (HTTP ${err.status}): ${err.message}`);
        console.log(`  ${advise(err)}`);
        if (err.code !== expected) {
          throw new Error(`expected ${expected}, got ${err.code}`);
        }
        return;
      }
      throw new Error("the request unexpectedly succeeded");
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
        await demonstrate(
          "Asking a pipeline that does not exist",
          missingPipeline,
          "Hello",
          "PIPELINE_NOT_FOUND",
        );
        await demonstrate("Asking an empty question", pipeline, "", "INVALID_REQUEST");
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
    /**
     * Sends one query that the server must refuse with the expected error
     * code, and prints how the program handles the refusal. Any other
     * outcome is a failure.
     */
    static void demonstrate(HttpClient client, String title, String pipeline,
            String query, String expected)
            throws IOException, InterruptedException, RagException {
        System.out.println(title);
        try {
            sendQuery(client, pipeline, query);
        } catch (ApiException e) {
            System.out.println("  " + e.code + " (HTTP " + e.status + "): " + e.message);
            System.out.println("  " + advise(e));
            if (!e.code.equals(expected)) {
                throw new RagException("expected " + expected + ", got " + e.code);
            }
            return;
        }
        throw new RagException("the request unexpectedly succeeded");
    }
    
    public static void main(String[] args) {
        HttpClient client = HttpClient.newHttpClient();
        try {
            demonstrate(client, "Asking a pipeline that does not exist",
                    MISSING_PIPELINE, "Hello", "PIPELINE_NOT_FOUND");
            demonstrate(client, "Asking an empty question",
                    PIPELINE, "", "INVALID_REQUEST");
        // IOException covers failures to reach the server, such as a
        // refused connection or a timeout. The message of a refused
        // connection can be empty, so print the exception itself, which
        // includes its type.
        } catch (IOException | InterruptedException e) {
            System.err.println("RAG Server error: " + e);
            System.exit(1);
        } catch (RagException e) {
            System.err.println("RAG Server error: " + e.getMessage());
            System.exit(1);
        }
    }
    ```

=== "C#"

    ```csharp
    // Sends one query that the server must refuse with the expected error
    // code, and prints how the program handles the refusal. Any other outcome
    // is a failure.
    static async Task DemonstrateAsync(HttpClient client, string title,
        string pipeline, string query, string expected)
    {
        Console.WriteLine(title);
        try
        {
            await SendQueryAsync(client, pipeline, query);
        }
        catch (ApiException e)
        {
            Console.WriteLine($"  {e.Code} (HTTP {e.Status}): {e.Detail}");
            Console.WriteLine($"  {Advise(e)}");
            if (e.Code != expected)
            {
                throw new RagException($"expected {expected}, got {e.Code}");
            }
            return;
        }
        throw new RagException("the request unexpectedly succeeded");
    }
    
    try
    {
        // using disposes of the client, and closes its connections, when the
        // block exits, whether or not an error occurred.
        using var client = new HttpClient
        {
            Timeout = TimeSpan.FromSeconds(TimeoutSeconds),
        };
        await DemonstrateAsync(client, "Asking a pipeline that does not exist",
            MissingPipeline, "Hello", "PIPELINE_NOT_FOUND");
        await DemonstrateAsync(client, "Asking an empty question",
            Pipeline(), "", "INVALID_REQUEST");
    }
    // HttpRequestException covers failures to reach the server, such as a
    // refused connection, and TaskCanceledException covers a timeout.
    catch (Exception e) when (
        e is HttpRequestException or TaskCanceledException or RagException)
    {
        Console.Error.WriteLine($"RAG Server error: {e.Message}");
        return 1;
    }
    
    return 0;
    
    // C# requires type declarations to follow the top-level statements, so
    // the exceptions that the program throws are declared here, at the end.
    // RagException is for a reply that the program cannot interpret, and
    // ApiException is for an error reply, which has an HTTP status and a JSON
    // body of the form {"error": {"code": "...", "message": "..."}}.
    class RagException(string message) : Exception(message);
    
    class ApiException(int status, string code, string detail)
        : Exception($"{code}: {detail}")
    {
        public int Status { get; } = status;
        public string Code { get; } = code;
        public string Detail { get; } = detail;
    }
    ```

=== "Go"

    ```go
    // demonstrate sends one query that the server must refuse with the
    // expected error code, and prints how the program handles the refusal.
    // Any other outcome is a failure.
    func demonstrate(client *http.Client, title, name, query, expected string) error {
    	fmt.Println(title)
    	err := sendQuery(client, name, query)
    
    	var apiErr *apiError
    	if !errors.As(err, &apiErr) {
    		if err == nil {
    			return errors.New("the request unexpectedly succeeded")
    		}
    		return err
    	}
    
    	fmt.Printf("  %s (HTTP %d): %s\n", apiErr.Code, apiErr.Status, apiErr.Message)
    	fmt.Printf("  %s\n", advise(apiErr))
    	if apiErr.Code != expected {
    		return fmt.Errorf("expected %s, got %s", expected, apiErr.Code)
    	}
    	return nil
    }
    
    // run causes each error in turn and returns any unexpected outcome to the
    // caller.
    func run() error {
    	client := &http.Client{Timeout: timeout}
    
    	if err := demonstrate(client, "Asking a pipeline that does not exist",
    		missingPipeline, "Hello", "PIPELINE_NOT_FOUND"); err != nil {
    		return err
    	}
    	return demonstrate(client, "Asking an empty question",
    		pipeline, "", "INVALID_REQUEST")
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
    /// Sends one query that the server must refuse with the expected error
    /// code, and prints how the program handles the refusal. Any other outcome
    /// is a failure.
    fn demonstrate(
        client: &Client,
        title: &str,
        pipeline: &str,
        query: &str,
        expected: &str,
    ) -> Result<(), BoxError> {
        println!("{title}");
        match send_query(client, pipeline, query) {
            Err(QueryError::Api(e)) => {
                println!("  {} (HTTP {}): {}", e.code, e.status, e.message);
                println!("  {}", advise(&e));
                if e.code != expected {
                    return Err(format!("expected {expected}, got {}", e.code).into());
                }
                Ok(())
            }
            Err(QueryError::Other(e)) => Err(e),
            Ok(_) => Err("the request unexpectedly succeeded".into()),
        }
    }
    
    /// Sends the two queries. The ? operator returns any error to the caller.
    fn run() -> Result<(), BoxError> {
        let client = Client::builder().timeout(TIMEOUT).build()?;
        demonstrate(
            &client,
            "Asking a pipeline that does not exist",
            MISSING_PIPELINE,
            "Hello",
            "PIPELINE_NOT_FOUND",
        )?;
        demonstrate(&client, "Asking an empty question", &pipeline(), "", "INVALID_REQUEST")
    }
    
    /// Reports any error returned by run() and exits with a failure status.
    /// The top-level error is often generic ("error sending request"), so the
    /// chain of underlying causes is printed too.
    fn main() -> ExitCode {
        match run() {
            Ok(()) => ExitCode::SUCCESS,
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
    # Sends one query that the server must refuse with the expected error
    # code, and prints how the program handles the refusal. Any other outcome
    # is a failure.
    def demonstrate(http, title, pipeline, query, expected)
      puts title
      begin
        send_query(http, pipeline, query)
      rescue ApiError => e
        puts "  #{e.code} (HTTP #{e.status}): #{e.detail}"
        puts "  #{advise(e)}"
        raise RagError, "expected #{expected}, got #{e.code}" if e.code != expected
    
        return
      end
      raise RagError, "the request unexpectedly succeeded"
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
        demonstrate(http, "Asking a pipeline that does not exist",
                    MISSING_PIPELINE, "Hello", "PIPELINE_NOT_FOUND")
        demonstrate(http, "Asking an empty question",
                    PIPELINE, "", "INVALID_REQUEST")
      end
    # SystemCallError covers a refused connection, Timeout::Error covers the
    # connection and read timeouts, and SocketError covers an unknown host.
    rescue RagError, SystemCallError, Timeout::Error, SocketError, IOError => e
      warn "RAG Server error: #{e.message}"
      exit 1
    end
    ```

=== "curl"

    ```bash
    # Sends one query that the server must refuse with the expected error
    # code, and prints how the program handles the refusal. A reply with any
    # other outcome is a failure.
    demonstrate() {
        local title="$1" pipeline="$2" query="$3" expected="$4"
    
        echo "$title"
        if send_query "$pipeline" "$query" >/dev/null; then
            echo "RAG Server error: the request unexpectedly succeeded" >&2
            return 1
        fi
        echo "  $CODE (HTTP $STATUS): $MESSAGE"
        echo "  $(advise)"
        if [[ "$CODE" != "$expected" ]]; then
            echo "RAG Server error: expected $expected, got $CODE" >&2
            return 1
        fi
    }
    
    main() {
        demonstrate "Asking a pipeline that does not exist" \
            "$MISSING_PIPELINE" "Hello" PIPELINE_NOT_FOUND
        demonstrate "Asking an empty question" \
            "$RAG_PIPELINE" "" INVALID_REQUEST
    }
    
    main
    ```

## Running the Example

The complete project for each language is available in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/rag_server/handle_errors).
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
    Handling errors from the pgEdge RAG Server by error code, using httpx.
    
    These examples are for pgEdge RAG Server 2.0.0.
    
    Copyright (c) 2026, pgEdge, Inc.
    This code is released under the PostgreSQL License.
    """
    
    import os
    import sys
    from urllib.parse import quote
    
    import httpx
    
    
    # The or operator treats an empty variable as unset.
    BASE_URL = (os.environ.get("RAG_SERVER_URL") or "http://localhost:8080").rstrip("/")
    PIPELINE = os.environ.get("RAG_PIPELINE") or "cookbook"
    
    # A pipeline name that no server has, to cause PIPELINE_NOT_FOUND.
    MISSING_PIPELINE = "no-such-pipeline"
    
    # The server rejects both requests before it calls a language model, so
    # they answer quickly.
    TIMEOUT_SECONDS = 30.0
    
    
    class RagError(Exception):
        """Raised when a reply is not one that the program can interpret."""
    
    
    class ApiError(Exception):
        """Raised when the RAG Server replies with an error. The reply has an
        HTTP status and a JSON body of the form
        {"error": {"code": "...", "message": "..."}}."""
    
        def __init__(self, status: int, code: str, message: str):
            super().__init__(f"{code}: {message}")
            self.status = status
            self.code = code
            self.message = message
    
    
    def send_query(client: httpx.Client, pipeline: str, query: str) -> dict:
        """Sends a query to a pipeline, and returns the decoded reply. Raises
        ApiError when the server replies with an error."""
        response = client.post(
            f"/v1/pipelines/{quote(pipeline, safe='')}", json={"query": query}
        )
        if response.is_error:
            try:
                error = response.json()["error"]
                raise ApiError(response.status_code, error["code"], error["message"])
            except (ValueError, KeyError, TypeError):
                raise RagError(
                    f"HTTP {response.status_code}, {response.text[:200]}"
                ) from None
        return response.json()
    
    
    def advise(err: ApiError) -> str:
        """Returns advice for an error, chosen by the error code. Branch on the
        code rather than on the message, which is meant for people and may
        change; branch on the HTTP status only for the temporary failures that
        have no code worth handling individually."""
        if err.code == "PIPELINE_NOT_FOUND":
            return "Check the pipeline name; GET /v1/pipelines lists the pipelines."
        if err.code == "INVALID_REQUEST":
            return "Fix the request; the body must be JSON with a non-empty query."
        if err.status in (503, 504):
            return "The failure may be temporary, so retry the request later."
        return f"This program does not handle {err.code}."
    
    
    def demonstrate(
        client: httpx.Client, title: str, pipeline: str, query: str, expected: str
    ) -> None:
        """Sends one query that the server must refuse with the expected error
        code, and prints how the program handles the refusal. Any other outcome
        is a failure."""
        print(title)
        try:
            send_query(client, pipeline, query)
        except ApiError as e:
            print(f"  {e.code} (HTTP {e.status}): {e.message}")
            print(f"  {advise(e)}")
            if e.code != expected:
                raise RagError(f"expected {expected}, got {e.code}") from None
            return
        raise RagError("the request unexpectedly succeeded")
    
    
    def main() -> int:
        try:
            with httpx.Client(base_url=BASE_URL, timeout=TIMEOUT_SECONDS) as client:
                demonstrate(client, "Asking a pipeline that does not exist",
                            MISSING_PIPELINE, "Hello", "PIPELINE_NOT_FOUND")
                demonstrate(client, "Asking an empty question",
                            PIPELINE, "", "INVALID_REQUEST")
        # httpx.HTTPError is the base class for failures to reach the server,
        # such as a refused connection or a timeout.
        except (httpx.HTTPError, RagError) as e:
            print(f"RAG Server error: {e}", file=sys.stderr)
            return 1
    
        return 0
    
    
    if __name__ == "__main__":
        sys.exit(main())
    
    ```

=== "TypeScript"

    ```typescript
    /*
     * Ellie's Postgres Cookbook
     * Handling errors from the pgEdge RAG Server by error code, using the
     * built-in fetch.
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
    const pipeline = process.env.RAG_PIPELINE || "cookbook";
    
    // A pipeline name that no server has, to cause PIPELINE_NOT_FOUND.
    const missingPipeline = "no-such-pipeline";
    
    // The server rejects both requests before it calls a language model, so
    // they answer quickly.
    const timeoutMs = 30_000;
    
    // ApiError is thrown when the RAG Server replies with an error. The reply
    // has an HTTP status and a JSON body of the form
    // {"error": {"code": "...", "message": "..."}}.
    class ApiError extends Error {
      constructor(
        readonly status: number,
        readonly code: string,
        message: string,
      ) {
        super(message);
      }
    }
    
    // Sends a query to a pipeline, and returns the decoded reply. Throws an
    // ApiError when the server replies with an error.
    async function sendQuery(name: string, query: string): Promise<unknown> {
      const response = await fetch(
        `${baseUrl}/v1/pipelines/${encodeURIComponent(name)}`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ query }),
          signal: AbortSignal.timeout(timeoutMs),
        },
      );
    
      // fetch only rejects when it cannot reach the server; an error status
      // is a normal response, so check it explicitly.
      if (!response.ok) {
        const text = await response.text();
        let error: { code?: unknown; message?: unknown } | undefined;
        try {
          error = JSON.parse(text).error;
        } catch {
          // Fall through to the generic error below.
        }
        if (typeof error?.code === "string" && typeof error.message === "string") {
          throw new ApiError(response.status, error.code, error.message);
        }
        throw new Error(`HTTP ${response.status}, ${text.slice(0, 200)}`);
      }
      return response.json();
    }
    
    // Returns advice for an error, chosen by the error code. Branch on the
    // code rather than on the message, which is meant for people and may
    // change; branch on the HTTP status only for the temporary failures that
    // have no code worth handling individually.
    function advise(err: ApiError): string {
      switch (err.code) {
        case "PIPELINE_NOT_FOUND":
          return "Check the pipeline name; GET /v1/pipelines lists the pipelines.";
        case "INVALID_REQUEST":
          return "Fix the request; the body must be JSON with a non-empty query.";
        default:
          if (err.status === 503 || err.status === 504) {
            return "The failure may be temporary, so retry the request later.";
          }
          return `This program does not handle ${err.code}.`;
      }
    }
    
    // Sends one query that the server must refuse with the expected error
    // code, and prints how the program handles the refusal. Any other outcome
    // is a failure.
    async function demonstrate(
      title: string,
      name: string,
      query: string,
      expected: string,
    ): Promise<void> {
      console.log(title);
      try {
        await sendQuery(name, query);
      } catch (err) {
        if (!(err instanceof ApiError)) {
          throw err;
        }
        console.log(`  ${err.code} (HTTP ${err.status}): ${err.message}`);
        console.log(`  ${advise(err)}`);
        if (err.code !== expected) {
          throw new Error(`expected ${expected}, got ${err.code}`);
        }
        return;
      }
      throw new Error("the request unexpectedly succeeded");
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
        await demonstrate(
          "Asking a pipeline that does not exist",
          missingPipeline,
          "Hello",
          "PIPELINE_NOT_FOUND",
        );
        await demonstrate("Asking an empty question", pipeline, "", "INVALID_REQUEST");
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
     * Handling errors from the pgEdge RAG Server, using java.net.http and
     * Jackson.
     *
     * These examples are for pgEdge RAG Server 2.0.0.
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
        static final String PIPELINE = envOr("RAG_PIPELINE", "cookbook");
    
        // A pipeline name that no server has, to cause PIPELINE_NOT_FOUND.
        static final String MISSING_PIPELINE = "no-such-pipeline";
    
        // The server rejects both requests before it calls a language model,
        // so they answer quickly.
        static final Duration TIMEOUT = Duration.ofSeconds(30);
    
        /** Thrown when a reply is not one that the program can interpret. */
        static class RagException extends Exception {
            RagException(String message) {
                super(message);
            }
        }
    
        /**
         * Thrown when the RAG Server replies with an error. The reply has an
         * HTTP status and a JSON body of the form
         * {"error": {"code": "...", "message": "..."}}.
         */
        static class ApiException extends Exception {
            final int status;
            final String code;
            final String message;
    
            ApiException(int status, String code, String message) {
                super(code + ": " + message);
                this.status = status;
                this.code = code;
                this.message = message;
            }
        }
    
        // A mapper is safe to share, so the program creates only one.
        static final ObjectMapper MAPPER = JsonMapper.builder().build();
    
        /** Returns at most the first 200 characters of a reply. */
        static String shorten(String text) {
            return text.length() > 200 ? text.substring(0, 200) : text;
        }
    
        /**
         * Returns the URL of a pipeline. URLEncoder escapes any character that
         * is not safe in a URL, but it writes a space as + for an HTML form,
         * so the + becomes %20 for use in a URL path.
         */
        static URI pipelineUri(String pipeline) {
            String name = URLEncoder.encode(pipeline, StandardCharsets.UTF_8)
                    .replace("+", "%20");
            return URI.create(BASE_URL + "/v1/pipelines/" + name);
        }
    
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
    
        /**
         * Sends a query to a pipeline, and returns the decoded reply. Throws
         * ApiException when the server replies with an error.
         */
        static JsonNode sendQuery(HttpClient client, String pipeline, String query)
                throws IOException, InterruptedException, RagException, ApiException {
            HttpRequest request = HttpRequest.newBuilder(pipelineUri(pipeline))
                    .timeout(TIMEOUT)
                    .header("Content-Type", "application/json")
                    .POST(HttpRequest.BodyPublishers.ofString(MAPPER.writeValueAsString(
                            MAPPER.createObjectNode().put("query", query))))
                    .build();
            HttpResponse<String> response = send(client, request);
    
            JsonNode body;
            try {
                body = MAPPER.readTree(response.body());
            } catch (JacksonException e) {
                throw new RagException("HTTP " + response.statusCode() + ", "
                        + shorten(response.body()));
            }
    
            if (response.statusCode() >= 400) {
                JsonNode error = body.path("error");
                if (!error.path("code").isString() || !error.path("message").isString()) {
                    throw new RagException("HTTP " + response.statusCode() + ", "
                            + shorten(response.body()));
                }
                throw new ApiException(response.statusCode(),
                        error.path("code").stringValue(),
                        error.path("message").stringValue());
            }
            return body;
        }
    
        /**
         * Returns advice for an error, chosen by the error code. Branch on the
         * code rather than on the message, which is meant for people and may
         * change; branch on the HTTP status only for the temporary failures
         * that have no code worth handling individually.
         */
        static String advise(ApiException err) {
            if (err.code.equals("PIPELINE_NOT_FOUND")) {
                return "Check the pipeline name; GET /v1/pipelines lists the pipelines.";
            }
            if (err.code.equals("INVALID_REQUEST")) {
                return "Fix the request; the body must be JSON with a non-empty query.";
            }
            if (err.status == 503 || err.status == 504) {
                return "The failure may be temporary, so retry the request later.";
            }
            return "This program does not handle " + err.code + ".";
        }
    
        /**
         * Sends one query that the server must refuse with the expected error
         * code, and prints how the program handles the refusal. Any other
         * outcome is a failure.
         */
        static void demonstrate(HttpClient client, String title, String pipeline,
                String query, String expected)
                throws IOException, InterruptedException, RagException {
            System.out.println(title);
            try {
                sendQuery(client, pipeline, query);
            } catch (ApiException e) {
                System.out.println("  " + e.code + " (HTTP " + e.status + "): " + e.message);
                System.out.println("  " + advise(e));
                if (!e.code.equals(expected)) {
                    throw new RagException("expected " + expected + ", got " + e.code);
                }
                return;
            }
            throw new RagException("the request unexpectedly succeeded");
        }
    
        public static void main(String[] args) {
            HttpClient client = HttpClient.newHttpClient();
            try {
                demonstrate(client, "Asking a pipeline that does not exist",
                        MISSING_PIPELINE, "Hello", "PIPELINE_NOT_FOUND");
                demonstrate(client, "Asking an empty question",
                        PIPELINE, "", "INVALID_REQUEST");
            // IOException covers failures to reach the server, such as a
            // refused connection or a timeout. The message of a refused
            // connection can be empty, so print the exception itself, which
            // includes its type.
            } catch (IOException | InterruptedException e) {
                System.err.println("RAG Server error: " + e);
                System.exit(1);
            } catch (RagException e) {
                System.err.println("RAG Server error: " + e.getMessage());
                System.exit(1);
            }
        }
    }
    
    ```

=== "C#"

    ```csharp
    /*
     * Ellie's Postgres Cookbook
     * Handling errors from the pgEdge RAG Server, using HttpClient and
     * System.Text.Json.
     *
     * These examples are for pgEdge RAG Server 2.0.0.
     *
     * Copyright (c) 2026, pgEdge, Inc.
     * This code is released under the PostgreSQL License.
     */
    
    using System.Net.Http.Json;
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
    static string Pipeline() => EnvOr("RAG_PIPELINE", "cookbook");
    
    // A pipeline name that no server has, to cause PIPELINE_NOT_FOUND.
    const string MissingPipeline = "no-such-pipeline";
    
    // The server rejects both requests before it calls a language model, so
    // they answer quickly.
    const int TimeoutSeconds = 30;
    
    // Returns at most the first 200 characters of a reply.
    static string Shorten(string text) =>
        text.Length > 200 ? text[..200] : text;
    
    // Sends a query to a pipeline, and returns the decoded reply. Throws
    // ApiException when the server replies with an error.
    static async Task<JsonNode?> SendQueryAsync(
        HttpClient client, string pipeline, string query)
    {
        var url = $"{BaseUrl()}/v1/pipelines/{Uri.EscapeDataString(pipeline)}";
        using var response = await client.PostAsync(
            url, JsonContent.Create(new { query }));
        var body = await response.Content.ReadAsStringAsync();
        var status = (int)response.StatusCode;
    
        JsonNode? reply;
        try
        {
            reply = JsonNode.Parse(body);
        }
        catch (JsonException)
        {
            throw new RagException($"HTTP {status}, {Shorten(body)}");
        }
    
        if (!response.IsSuccessStatusCode)
        {
            if (reply?["error"] is JsonObject error &&
                error["code"] is JsonValue codeNode &&
                codeNode.TryGetValue(out string? code) &&
                error["message"] is JsonValue messageNode &&
                messageNode.TryGetValue(out string? message))
            {
                throw new ApiException(status, code, message);
            }
            throw new RagException($"HTTP {status}, {Shorten(body)}");
        }
        return reply;
    }
    
    // Returns advice for an error, chosen by the error code. Branch on the code
    // rather than on the message, which is meant for people and may change;
    // branch on the HTTP status only for the temporary failures that have no
    // code worth handling individually.
    static string Advise(ApiException err) => err switch
    {
        { Code: "PIPELINE_NOT_FOUND" } =>
            "Check the pipeline name; GET /v1/pipelines lists the pipelines.",
        { Code: "INVALID_REQUEST" } =>
            "Fix the request; the body must be JSON with a non-empty query.",
        { Status: 503 or 504 } =>
            "The failure may be temporary, so retry the request later.",
        _ => $"This program does not handle {err.Code}.",
    };
    
    // Sends one query that the server must refuse with the expected error
    // code, and prints how the program handles the refusal. Any other outcome
    // is a failure.
    static async Task DemonstrateAsync(HttpClient client, string title,
        string pipeline, string query, string expected)
    {
        Console.WriteLine(title);
        try
        {
            await SendQueryAsync(client, pipeline, query);
        }
        catch (ApiException e)
        {
            Console.WriteLine($"  {e.Code} (HTTP {e.Status}): {e.Detail}");
            Console.WriteLine($"  {Advise(e)}");
            if (e.Code != expected)
            {
                throw new RagException($"expected {expected}, got {e.Code}");
            }
            return;
        }
        throw new RagException("the request unexpectedly succeeded");
    }
    
    try
    {
        // using disposes of the client, and closes its connections, when the
        // block exits, whether or not an error occurred.
        using var client = new HttpClient
        {
            Timeout = TimeSpan.FromSeconds(TimeoutSeconds),
        };
        await DemonstrateAsync(client, "Asking a pipeline that does not exist",
            MissingPipeline, "Hello", "PIPELINE_NOT_FOUND");
        await DemonstrateAsync(client, "Asking an empty question",
            Pipeline(), "", "INVALID_REQUEST");
    }
    // HttpRequestException covers failures to reach the server, such as a
    // refused connection, and TaskCanceledException covers a timeout.
    catch (Exception e) when (
        e is HttpRequestException or TaskCanceledException or RagException)
    {
        Console.Error.WriteLine($"RAG Server error: {e.Message}");
        return 1;
    }
    
    return 0;
    
    // C# requires type declarations to follow the top-level statements, so
    // the exceptions that the program throws are declared here, at the end.
    // RagException is for a reply that the program cannot interpret, and
    // ApiException is for an error reply, which has an HTTP status and a JSON
    // body of the form {"error": {"code": "...", "message": "..."}}.
    class RagException(string message) : Exception(message);
    
    class ApiException(int status, string code, string detail)
        : Exception($"{code}: {detail}")
    {
        public int Status { get; } = status;
        public string Code { get; } = code;
        public string Detail { get; } = detail;
    }
    
    ```

=== "Go"

    ```go
    // Ellie's Postgres Cookbook
    // Handling errors from the pgEdge RAG Server by error code, using
    // net/http.
    //
    // These examples are for pgEdge RAG Server 2.0.0.
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
    	"net/url"
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
    	baseURL  = strings.TrimRight(envOr("RAG_SERVER_URL", "http://localhost:8080"), "/")
    	pipeline = envOr("RAG_PIPELINE", "cookbook")
    )
    
    // A pipeline name that no server has, to cause PIPELINE_NOT_FOUND.
    const missingPipeline = "no-such-pipeline"
    
    // The server rejects both requests before it calls a language model, so
    // they answer quickly.
    const timeout = 30 * time.Second
    
    
    // apiError is returned when the RAG Server replies with an error. The
    // reply has an HTTP status and a JSON body of the form
    // {"error": {"code": "...", "message": "..."}}.
    type apiError struct {
    	Status  int
    	Code    string
    	Message string
    }
    
    func (e *apiError) Error() string {
    	return fmt.Sprintf("%s: %s", e.Code, e.Message)
    }
    
    // sendQuery sends a query to a pipeline. It returns an *apiError when the
    // server replies with an error.
    func sendQuery(client *http.Client, name, query string) error {
    	payload, err := json.Marshal(map[string]string{"query": query})
    	if err != nil {
    		return err
    	}
    
    	endpoint := baseURL + "/v1/pipelines/" + url.PathEscape(name)
    	response, err := client.Post(endpoint, "application/json", bytes.NewReader(payload))
    	if err != nil {
    		return err
    	}
    	defer response.Body.Close()
    
    	body, err := io.ReadAll(response.Body)
    	if err != nil {
    		return err
    	}
    
    	// Go treats an error status as a normal response, so check it here.
    	if response.StatusCode == http.StatusOK {
    		return nil
    	}
    	var e struct {
    		Error struct {
    			Code    string `json:"code"`
    			Message string `json:"message"`
    		} `json:"error"`
    	}
    	if json.Unmarshal(body, &e) != nil || e.Error.Code == "" {
    		return fmt.Errorf("HTTP %d, %.200s", response.StatusCode, strings.TrimSpace(string(body)))
    	}
    	return &apiError{response.StatusCode, e.Error.Code, e.Error.Message}
    }
    
    
    // advise returns advice for an error, chosen by the error code. Branch on
    // the code rather than on the message, which is meant for people and may
    // change; branch on the HTTP status only for the temporary failures that
    // have no code worth handling individually.
    func advise(e *apiError) string {
    	switch {
    	case e.Code == "PIPELINE_NOT_FOUND":
    		return "Check the pipeline name; GET /v1/pipelines lists the pipelines."
    	case e.Code == "INVALID_REQUEST":
    		return "Fix the request; the body must be JSON with a non-empty query."
    	case e.Status == http.StatusServiceUnavailable, e.Status == http.StatusGatewayTimeout:
    		return "The failure may be temporary, so retry the request later."
    	default:
    		return "This program does not handle " + e.Code + "."
    	}
    }
    
    
    // demonstrate sends one query that the server must refuse with the
    // expected error code, and prints how the program handles the refusal.
    // Any other outcome is a failure.
    func demonstrate(client *http.Client, title, name, query, expected string) error {
    	fmt.Println(title)
    	err := sendQuery(client, name, query)
    
    	var apiErr *apiError
    	if !errors.As(err, &apiErr) {
    		if err == nil {
    			return errors.New("the request unexpectedly succeeded")
    		}
    		return err
    	}
    
    	fmt.Printf("  %s (HTTP %d): %s\n", apiErr.Code, apiErr.Status, apiErr.Message)
    	fmt.Printf("  %s\n", advise(apiErr))
    	if apiErr.Code != expected {
    		return fmt.Errorf("expected %s, got %s", expected, apiErr.Code)
    	}
    	return nil
    }
    
    // run causes each error in turn and returns any unexpected outcome to the
    // caller.
    func run() error {
    	client := &http.Client{Timeout: timeout}
    
    	if err := demonstrate(client, "Asking a pipeline that does not exist",
    		missingPipeline, "Hello", "PIPELINE_NOT_FOUND"); err != nil {
    		return err
    	}
    	return demonstrate(client, "Asking an empty question",
    		pipeline, "", "INVALID_REQUEST")
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
    // Handling errors from the pgEdge RAG Server, using reqwest and
    // serde_json.
    //
    // These examples are for pgEdge RAG Server 2.0.0.
    //
    // Copyright (c) 2026, pgEdge, Inc.
    // This code is released under the PostgreSQL License.
    
    use std::env;
    use std::error::Error;
    use std::fmt;
    use std::process::ExitCode;
    use std::time::Duration;
    
    use reqwest::blocking::Client;
    use reqwest::Url;
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
        env_or("RAG_SERVER_URL", "http://localhost:8080")
            .trim_end_matches('/')
            .to_string()
    }
    
    fn pipeline() -> String {
        env_or("RAG_PIPELINE", "cookbook")
    }
    
    /// A pipeline name that no server has, to cause PIPELINE_NOT_FOUND.
    const MISSING_PIPELINE: &str = "no-such-pipeline";
    
    /// The server rejects both requests before it calls a language model, so
    /// they answer quickly.
    const TIMEOUT: Duration = Duration::from_secs(30);
    
    /// The errors that the functions below return; a string converts into one
    /// with the ? operator or into().
    type BoxError = Box<dyn Error>;
    
    /// An error reply from the RAG Server, which has an HTTP status and a JSON
    /// body of the form {"error": {"code": "...", "message": "..."}}.
    #[derive(Debug)]
    struct ApiError {
        status: u16,
        code: String,
        message: String,
    }
    
    impl fmt::Display for ApiError {
        fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
            write!(f, "{}: {}", self.code, self.message)
        }
    }
    
    impl Error for ApiError {}
    
    /// The outcome of a query that reached the server: an ApiError when the
    /// server replied with an error, or any other error when the reply could
    /// not be had or understood.
    enum QueryError {
        Api(ApiError),
        Other(BoxError),
    }
    
    /// Lets the ? operator turn any other error into QueryError::Other.
    impl<E: Into<BoxError>> From<E> for QueryError {
        fn from(e: E) -> Self {
            QueryError::Other(e.into())
        }
    }
    
    /// Returns at most the first 200 characters of a reply.
    fn shorten(text: &str) -> String {
        text.chars().take(200).collect()
    }
    
    /// Returns the URL of a pipeline. push() escapes any character in the
    /// pipeline name that is not safe in a URL path.
    fn pipeline_url(name: &str) -> Result<Url, BoxError> {
        let mut url = Url::parse(&format!("{}/v1/pipelines/", base_url()))?;
        url.path_segments_mut()
            .map_err(|()| "RAG_SERVER_URL cannot be a base URL")?
            .pop_if_empty()
            .push(name);
        Ok(url)
    }
    
    /// Sends a query to a pipeline, and returns the decoded reply. Returns
    /// QueryError::Api when the server replies with an error.
    fn send_query(client: &Client, pipeline: &str, query: &str) -> Result<Value, QueryError> {
        let response = client
            .post(pipeline_url(pipeline)?)
            .json(&json!({ "query": query }))
            .send()?;
        let status = response.status();
        let body = response.text()?;
    
        let reply: Value = match serde_json::from_str(&body) {
            Ok(reply) => reply,
            Err(_) => return Err(format!("HTTP {}, {}", status.as_u16(), shorten(&body)).into()),
        };
    
        if !status.is_success() {
            let error = &reply["error"];
            return match (error["code"].as_str(), error["message"].as_str()) {
                (Some(code), Some(message)) => Err(QueryError::Api(ApiError {
                    status: status.as_u16(),
                    code: code.to_string(),
                    message: message.to_string(),
                })),
                _ => Err(format!("HTTP {}, {}", status.as_u16(), shorten(&body)).into()),
            };
        }
        Ok(reply)
    }
    
    /// Returns advice for an error, chosen by the error code. Branch on the
    /// code rather than on the message, which is meant for people and may
    /// change; branch on the HTTP status only for the temporary failures that
    /// have no code worth handling individually.
    fn advise(err: &ApiError) -> String {
        match (err.code.as_str(), err.status) {
            ("PIPELINE_NOT_FOUND", _) => {
                "Check the pipeline name; GET /v1/pipelines lists the pipelines.".to_string()
            }
            ("INVALID_REQUEST", _) => {
                "Fix the request; the body must be JSON with a non-empty query.".to_string()
            }
            (_, 503 | 504) => "The failure may be temporary, so retry the request later.".to_string(),
            (code, _) => format!("This program does not handle {code}."),
        }
    }
    
    /// Sends one query that the server must refuse with the expected error
    /// code, and prints how the program handles the refusal. Any other outcome
    /// is a failure.
    fn demonstrate(
        client: &Client,
        title: &str,
        pipeline: &str,
        query: &str,
        expected: &str,
    ) -> Result<(), BoxError> {
        println!("{title}");
        match send_query(client, pipeline, query) {
            Err(QueryError::Api(e)) => {
                println!("  {} (HTTP {}): {}", e.code, e.status, e.message);
                println!("  {}", advise(&e));
                if e.code != expected {
                    return Err(format!("expected {expected}, got {}", e.code).into());
                }
                Ok(())
            }
            Err(QueryError::Other(e)) => Err(e),
            Ok(_) => Err("the request unexpectedly succeeded".into()),
        }
    }
    
    /// Sends the two queries. The ? operator returns any error to the caller.
    fn run() -> Result<(), BoxError> {
        let client = Client::builder().timeout(TIMEOUT).build()?;
        demonstrate(
            &client,
            "Asking a pipeline that does not exist",
            MISSING_PIPELINE,
            "Hello",
            "PIPELINE_NOT_FOUND",
        )?;
        demonstrate(&client, "Asking an empty question", &pipeline(), "", "INVALID_REQUEST")
    }
    
    /// Reports any error returned by run() and exits with a failure status.
    /// The top-level error is often generic ("error sending request"), so the
    /// chain of underlying causes is printed too.
    fn main() -> ExitCode {
        match run() {
            Ok(()) => ExitCode::SUCCESS,
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
    # Handling errors from the pgEdge RAG Server, using Net::HTTP.
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
    PIPELINE = env_or("RAG_PIPELINE", "cookbook")
    
    # A pipeline name that no server has, to cause PIPELINE_NOT_FOUND.
    MISSING_PIPELINE = "no-such-pipeline"
    
    # The server rejects both requests before it calls a language model, so
    # they answer quickly.
    TIMEOUT_SECONDS = 30
    
    # Raised when a reply is not one that the program can interpret.
    class RagError < StandardError; end
    
    # Raised when the RAG Server replies with an error. The reply has an HTTP
    # status and a JSON body of the form
    # {"error": {"code": "...", "message": "..."}}.
    class ApiError < StandardError
      attr_reader :status, :code, :detail
    
      def initialize(status, code, detail)
        super("#{code}: #{detail}")
        @status = status
        @code = code
        @detail = detail
      end
    end
    
    # Sends a query to a pipeline, and returns the decoded reply. Raises
    # ApiError when the server replies with an error.
    def send_query(http, pipeline, query)
      uri = URI("#{BASE_URL}/v1/pipelines/#{URI.encode_uri_component(pipeline)}")
      request = Net::HTTP::Post.new(uri, "Content-Type" => "application/json")
      request.body = JSON.generate({ query: query })
      response = http.request(request)
      status = response.code.to_i
    
      begin
        body = JSON.parse(response.body.to_s)
      rescue JSON::ParserError
        raise RagError, "HTTP #{status}, #{response.body.to_s[0, 200]}"
      end
    
      unless response.is_a?(Net::HTTPSuccess)
        error = body.is_a?(Hash) ? body["error"] : nil
        unless error.is_a?(Hash) && error["code"].is_a?(String) && error["message"].is_a?(String)
          raise RagError, "HTTP #{status}, #{response.body.to_s[0, 200]}"
        end
    
        raise ApiError.new(status, error["code"], error["message"])
      end
    
      body
    end
    
    # Returns advice for an error, chosen by the error code. Branch on the code
    # rather than on the message, which is meant for people and may change;
    # branch on the HTTP status only for the temporary failures that have no
    # code worth handling individually.
    def advise(err)
      return "Check the pipeline name; GET /v1/pipelines lists the pipelines." if err.code == "PIPELINE_NOT_FOUND"
      return "Fix the request; the body must be JSON with a non-empty query." if err.code == "INVALID_REQUEST"
      return "The failure may be temporary, so retry the request later." if [503, 504].include?(err.status)
    
      "This program does not handle #{err.code}."
    end
    
    # Sends one query that the server must refuse with the expected error
    # code, and prints how the program handles the refusal. Any other outcome
    # is a failure.
    def demonstrate(http, title, pipeline, query, expected)
      puts title
      begin
        send_query(http, pipeline, query)
      rescue ApiError => e
        puts "  #{e.code} (HTTP #{e.status}): #{e.detail}"
        puts "  #{advise(e)}"
        raise RagError, "expected #{expected}, got #{e.code}" if e.code != expected
    
        return
      end
      raise RagError, "the request unexpectedly succeeded"
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
        demonstrate(http, "Asking a pipeline that does not exist",
                    MISSING_PIPELINE, "Hello", "PIPELINE_NOT_FOUND")
        demonstrate(http, "Asking an empty question",
                    PIPELINE, "", "INVALID_REQUEST")
      end
    # SystemCallError covers a refused connection, Timeout::Error covers the
    # connection and read timeouts, and SocketError covers an unknown host.
    rescue RagError, SystemCallError, Timeout::Error, SocketError, IOError => e
      warn "RAG Server error: #{e.message}"
      exit 1
    end
    
    ```

=== "curl"

    ```bash
    #!/usr/bin/env bash
    #
    # Ellie's Postgres Cookbook
    # Handling errors from the pgEdge RAG Server by error code, using curl and
    # jq.
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
    RAG_PIPELINE="${RAG_PIPELINE:-cookbook}"
    
    # A pipeline name that no server has, to cause PIPELINE_NOT_FOUND.
    MISSING_PIPELINE="no-such-pipeline"
    
    # The server rejects both requests before it calls a language model, so
    # they answer quickly.
    TIMEOUT_SECONDS=30
    
    # Escapes a value for use in a URL path, as the other languages do.
    escape() { jq -rn --arg value "$1" '$value | @uri'; }
    
    # Sends a query to a pipeline. On success, the function prints the JSON
    # reply. On an error reply, it sets the variables STATUS, CODE, and MESSAGE
    # from the HTTP status and the "error" object in the body, and returns 1.
    # With --fail-with-body, curl exits non-zero on an HTTP error status but
    # still prints the body; --write-out adds the HTTP status after it. When
    # the server cannot be reached at all, curl prints status 000 and the
    # function exits the program, since there is no reply to branch on. The
    # script leaves out --show-error, because it reports each failure itself.
    STATUS="" CODE="" MESSAGE=""
    send_query() {
        local pipeline="$1" query="$2" output rc=0
        output="$(jq -n --arg query "$query" '{query: $query}' |
            curl --silent --fail-with-body \
                --max-time "$TIMEOUT_SECONDS" \
                --header 'Content-Type: application/json' \
                --data-binary @- \
                --write-out '\n%{http_code}' \
                "$RAG_SERVER_URL/v1/pipelines/$(escape "$pipeline")")" || rc=$?
    
        STATUS="${output##*$'\n'}"
        local body="${output%$'\n'*}"
        if [[ "$STATUS" == 000 ]]; then
            echo "RAG Server error: could not reach $RAG_SERVER_URL" >&2
            exit 1
        fi
        [[ $rc -eq 0 ]] && { printf '%s\n' "$body"; return 0; }
    
        # An error reply has the form {"error": {"code": "...", "message": "..."}}.
        CODE="$(jq -r '.error.code // empty' <<<"$body" 2>/dev/null || true)"
        MESSAGE="$(jq -r '.error.message // empty' <<<"$body" 2>/dev/null || true)"
        if [[ -z "$CODE" ]]; then
            echo "RAG Server error: HTTP $STATUS, ${body:0:200}" >&2
            exit 1
        fi
        return 1
    }
    
    # Returns advice for an error, chosen by the error code. Branch on the
    # code rather than on the message, which is meant for people and may
    # change; branch on the HTTP status only for the temporary failures that
    # have no code worth handling individually.
    advise() {
        case "$CODE" in
            PIPELINE_NOT_FOUND)
                echo "Check the pipeline name; GET /v1/pipelines lists the pipelines." ;;
            INVALID_REQUEST)
                echo "Fix the request; the body must be JSON with a non-empty query." ;;
            *)
                case "$STATUS" in
                    503|504) echo "The failure may be temporary, so retry the request later." ;;
                    *)       echo "This program does not handle $CODE." ;;
                esac ;;
        esac
    }
    
    # Sends one query that the server must refuse with the expected error
    # code, and prints how the program handles the refusal. A reply with any
    # other outcome is a failure.
    demonstrate() {
        local title="$1" pipeline="$2" query="$3" expected="$4"
    
        echo "$title"
        if send_query "$pipeline" "$query" >/dev/null; then
            echo "RAG Server error: the request unexpectedly succeeded" >&2
            return 1
        fi
        echo "  $CODE (HTTP $STATUS): $MESSAGE"
        echo "  $(advise)"
        if [[ "$CODE" != "$expected" ]]; then
            echo "RAG Server error: expected $expected, got $CODE" >&2
            return 1
        fi
    }
    
    main() {
        demonstrate "Asking a pipeline that does not exist" \
            "$MISSING_PIPELINE" "Hello" PIPELINE_NOT_FOUND
        demonstrate "Asking an empty question" \
            "$RAG_PIPELINE" "" INVALID_REQUEST
    }
    
    main
    
    ```

## Next Steps

The following resources provide more information about the topics in this
recipe:

- The [Asking a Question](ask_question.md) recipe shows the request that
  succeeds.
- The [Checking Health and Listing Pipelines](health_and_pipelines.md) recipe
  shows how to check the server before asking.
- The
  [pgEdge RAG Server documentation](https://docs.pgedge.com/pgedge-rag-server/)
  describes every endpoint and setting.
- The [Contributing a Recipe](../contributing.md) page explains how to add a
  recipe or a language to the cookbook.
