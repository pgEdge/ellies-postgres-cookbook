# Asking a Question

This recipe sends a question to a pgEdge RAG Server pipeline and prints the
answer, together with the number of tokens that the request used. The RAG
Server finds the stored documents that best match the question, gives them
to a language model as context, and returns the model's answer. Each step
shows the code in every supported language; selecting a language tab
switches every tab on the site to that language.

These examples are for pgEdge RAG Server 2.0.0.

The example programs ask how long the fictional Acme Widget 2.0 takes to
charge. The wording of the answer varies from run to run, because a language
model writes it, but the output has the following shape:

```text
Question: How long does the Acme Widget 2.0 take to charge?
Answer:
The Acme Widget 2.0 takes ninety minutes to fully charge.
Tokens used: 812
```

## Preparing the Ingredients

The examples need a running RAG Server with a pipeline that reads a table of
embedded documents; the
[Preparing Data for the RAG Server](prepare_data.md) recipe shows how to
build such a table and its pipeline. The examples assume a pipeline named
`cookbook` that holds the fictional Acme Widget support documents, which the
`scripts/start_rag_server.sh` script in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook)
loads and starts in Docker. Any pipeline works if you change the question.

The RAG Server answers a question with a `POST` request to
`/v1/pipelines/{name}`, where `{name}` is the name of the pipeline. The body
is a JSON object, and only the `query` field is required:

```json
{"query": "How long does the Acme Widget 2.0 take to charge?"}
```

The reply is a JSON object with the answer and the total number of tokens
that the request consumed:

```json
{"answer": "...", "tokens_used": 812}
```

The programs use only an HTTP client and a JSON encoder. The following table
lists the client that each example uses:

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
      "name": "ask-question",
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
library modules that it uses. The TypeScript program imports nothing, and
the curl script stops at the first failed command and checks that `curl`
and `jq` are installed. The following tabs show the imports for each
language:

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

The examples read the address of the RAG Server and the name of the pipeline
from environment variables. Each example treats an empty variable as unset,
and uses the default instead. The following table describes the environment
variables that the examples read:

| Variable         | Default                 | Description                      |
|------------------|-------------------------|----------------------------------|
| `RAG_SERVER_URL` | `http://localhost:8080` | The base URL of the RAG Server.  |
| `RAG_PIPELINE`   | `cookbook`              | The name of the pipeline to ask. |

A language model can take a while to write an answer, particularly a small
model on a modest machine, so each program allows 300 seconds for the
reply. The following tabs show how each program reads its settings:

=== "Python"

    ```python
    # The or operator treats an empty variable as unset.
    BASE_URL = (os.environ.get("RAG_SERVER_URL") or "http://localhost:8080").rstrip("/")
    PIPELINE = os.environ.get("RAG_PIPELINE") or "cookbook"
    
    QUESTION = "How long does the Acme Widget 2.0 take to charge?"
    
    # The server waits for the language model before it replies, and a small
    # model on a modest machine can take a while, so allow plenty of time.
    TIMEOUT_SECONDS = 300.0
    ```

=== "TypeScript"

    ```typescript
    // The || operator, unlike ??, also treats an empty variable as unset.
    const baseUrl = (process.env.RAG_SERVER_URL || "http://localhost:8080").replace(/\/+$/, "");
    const pipeline = process.env.RAG_PIPELINE || "cookbook";
    
    const question = "How long does the Acme Widget 2.0 take to charge?";
    
    // The server waits for the language model before it replies, and a small
    // model on a modest machine can take a while, so allow plenty of time.
    const timeoutMs = 300_000;
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
    
    static final String QUESTION =
            "How long does the Acme Widget 2.0 take to charge?";
    
    // The server waits for the language model before it replies, and a
    // small model on a modest machine can take a while, so allow plenty
    // of time.
    static final Duration TIMEOUT = Duration.ofSeconds(300);
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
    
    const string Question = "How long does the Acme Widget 2.0 take to charge?";
    
    // The server waits for the language model before it replies, and a small
    // model on a modest machine can take a while, so allow plenty of time.
    const int TimeoutSeconds = 300;
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
    
    const question = "How long does the Acme Widget 2.0 take to charge?"
    
    // The server waits for the language model before it replies, and a small
    // model on a modest machine can take a while, so allow plenty of time.
    const timeout = 300 * time.Second
    
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
    
    const QUESTION: &str = "How long does the Acme Widget 2.0 take to charge?";
    
    /// The server waits for the language model before it replies, and a small
    /// model on a modest machine can take a while, so allow plenty of time.
    const TIMEOUT: Duration = Duration::from_secs(300);
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
    
    QUESTION = "How long does the Acme Widget 2.0 take to charge?"
    
    # The server waits for the language model before it replies, and a small
    # model on a modest machine can take a while, so allow plenty of time.
    TIMEOUT_SECONDS = 300
    ```

=== "curl"

    ```bash
    # The :- operator treats an empty variable as unset.
    RAG_SERVER_URL="${RAG_SERVER_URL:-http://localhost:8080}"
    RAG_SERVER_URL="${RAG_SERVER_URL%/}"
    RAG_PIPELINE="${RAG_PIPELINE:-cookbook}"
    
    QUESTION="How long does the Acme Widget 2.0 take to charge?"
    
    # The server waits for the language model before it replies, and a small
    # model on a modest machine can take a while, so allow plenty of time.
    TIMEOUT_SECONDS=300
    
    # Escapes a value for use in a URL path, as the other languages do.
    escape() { jq -rn --arg value "$1" '$value | @uri'; }
    ```

## Sending the Question

Each program sends the question in a `POST` request with a JSON body, and
reads the `answer` and `tokens_used` fields of the reply. Each program
builds the URL from the pipeline name, and escapes any character in the
name that is not safe in a URL path (the curl script uses `jq` for this).
Each program builds the JSON body with a JSON encoder (`jq` in the curl script)
rather than by joining strings, so a question that contains quotation marks
cannot break the request.

The RAG Server reports a failure with an HTTP error status and a JSON body that
holds an error code and a message, such as `PIPELINE_NOT_FOUND` for a pipeline
that does not exist, or `REQUEST_TIMEOUT` when the request takes too long. The
programs print the code and the message. Some HTTP clients treat an error
status as a normal response, so the Python program checks `is_error`, the
TypeScript program checks `response.ok`, the Java and Go programs compare the
status code, the C# program checks `IsSuccessStatusCode`, the Rust program
checks `is_success()`, the Ruby program checks for `Net::HTTPSuccess`, and curl
uses `--fail-with-body`, which makes `curl` exit with an error and still print
the body. The following tabs show how each program sends the question and reads
the reply:

=== "Python"

    ```python
    class RagError(Exception):
        """Raised when the RAG Server rejects a request or replies oddly."""
    
    
    def error_text(response: httpx.Response) -> str:
        """Describes an error response, which carries a JSON body of the form
        {"error": {"code": "...", "message": "..."}}."""
        try:
            error = response.json()["error"]
            return f"{error['code']}: {error['message']}"
        except (ValueError, KeyError, TypeError):
            return response.text[:200] or response.reason_phrase
    
    
    def ask(client: httpx.Client, question: str) -> tuple[str, int]:
        """Sends the question to the pipeline, and returns the answer with the
        number of tokens the request used."""
        # quote() escapes any character in the pipeline name that is not safe
        # in a URL path.
        response = client.post(
            f"/v1/pipelines/{quote(PIPELINE, safe='')}",
            json={"query": question},
        )
        if response.is_error:
            raise RagError(f"HTTP {response.status_code}, {error_text(response)}")
    
        try:
            body = response.json()
            return body["answer"], body["tokens_used"]
        except (ValueError, KeyError, TypeError):
            raise RagError(f"Unexpected response: {response.text[:200]}")
    ```

=== "TypeScript"

    ```typescript
    interface QueryResponse {
      answer: string;
      tokens_used: number;
    }
    
    // Describes an error response, which carries a JSON body of the form
    // {"error": {"code": "...", "message": "..."}}.
    async function errorText(response: Response): Promise<string> {
      const text = await response.text();
      try {
        const { error } = JSON.parse(text);
        return `${error.code}: ${error.message}`;
      } catch {
        return text.slice(0, 200) || response.statusText;
      }
    }
    
    // Sends the question to the pipeline, and returns the answer with the
    // number of tokens the request used.
    async function ask(question: string): Promise<QueryResponse> {
      // encodeURIComponent escapes any character in the pipeline name that is
      // not safe in a URL path.
      const response = await fetch(
        `${baseUrl}/v1/pipelines/${encodeURIComponent(pipeline)}`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ query: question }),
          signal: AbortSignal.timeout(timeoutMs),
        },
      );
    
      // fetch only rejects when it cannot reach the server; an error status
      // is a normal response, so check it explicitly.
      if (!response.ok) {
        throw new Error(`HTTP ${response.status}, ${await errorText(response)}`);
      }
    
      const body = (await response.json()) as Partial<QueryResponse>;
      if (typeof body.answer !== "string" || typeof body.tokens_used !== "number") {
        throw new Error(`Unexpected response: ${JSON.stringify(body).slice(0, 200)}`);
      }
      return { answer: body.answer, tokens_used: body.tokens_used };
    }
    ```

=== "Java"

    ```java
    /** Thrown when the RAG Server rejects a request or replies oddly. */
    static class RagException extends Exception {
        RagException(String message) {
            super(message);
        }
    }
    
    /** The answer, and the number of tokens that the request used. */
    record Reply(String answer, long tokensUsed) {}
    
    // A mapper is safe to share, so the program creates only one.
    static final ObjectMapper MAPPER = JsonMapper.builder().build();
    
    /** Returns at most the first 200 characters of a reply. */
    static String shorten(String text) {
        return text.length() > 200 ? text.substring(0, 200) : text;
    }
    
    /**
     * Describes an error response, which carries a JSON body of the form
     * {"error": {"code": "...", "message": "..."}}.
     */
    static String errorText(String body) {
        try {
            JsonNode error = MAPPER.readTree(body).path("error");
            if (error.path("code").isString()) {
                return error.path("code").stringValue() + ": "
                        + error.path("message").asString();
            }
        } catch (JacksonException e) {
            // The body is not JSON, so show it as it is.
        }
        return shorten(body.strip());
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
     * Sends the question to the pipeline, and returns the answer with the
     * number of tokens the request used.
     */
    static Reply ask(HttpClient client, String question)
            throws IOException, InterruptedException, RagException {
        // Jackson builds the request body, which escapes the question
        // correctly.
        String payload = MAPPER.writeValueAsString(
                MAPPER.createObjectNode().put("query", question));
        HttpRequest request = HttpRequest.newBuilder(pipelineUri(PIPELINE))
                .timeout(TIMEOUT)
                .header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString(payload))
                .build();
        HttpResponse<String> response = send(client, request);
    
        // The client treats an error status as a normal response, so check
        // it here.
        if (response.statusCode() != 200) {
            throw new RagException("HTTP " + response.statusCode() + ", "
                    + errorText(response.body()));
        }
    
        try {
            JsonNode body = MAPPER.readTree(response.body());
            JsonNode answer = body.path("answer");
            JsonNode tokensUsed = body.path("tokens_used");
            if (answer.isString() && tokensUsed.isIntegralNumber()) {
                return new Reply(answer.stringValue(), tokensUsed.longValue());
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
    // Returns at most the first 200 characters of a reply.
    static string Shorten(string text) =>
        text.Length > 200 ? text[..200] : text;
    
    // Describes an error response, which carries a JSON body of the form
    // {"error": {"code": "...", "message": "..."}}.
    static string ErrorText(string body)
    {
        try
        {
            if (JsonNode.Parse(body)?["error"] is JsonObject error &&
                error["code"] is JsonValue codeNode &&
                codeNode.TryGetValue(out string? code))
            {
                return $"{code}: {error["message"]}";
            }
        }
        catch (JsonException)
        {
            // The body is not JSON, so show it as it is.
        }
        return Shorten(body.Trim());
    }
    
    // Sends the question to the pipeline, and returns the answer with the
    // number of tokens the request used.
    static async Task<(string Answer, long TokensUsed)> AskAsync(
        HttpClient client, string question)
    {
        // EscapeDataString escapes any character in the pipeline name that is
        // not safe in a URL path. JsonContent serialises the request body,
        // which escapes the question correctly.
        var url = $"{BaseUrl()}/v1/pipelines/{Uri.EscapeDataString(Pipeline())}";
        using var response = await client.PostAsync(
            url, JsonContent.Create(new { query = question }));
        var body = await response.Content.ReadAsStringAsync();
    
        // HttpClient treats an error status as a normal response, so check it
        // here.
        if (!response.IsSuccessStatusCode)
        {
            throw new RagException(
                $"HTTP {(int)response.StatusCode}, {ErrorText(body)}");
        }
    
        try
        {
            // TryGetValue fails when a field holds a different type, such as
            // a number where the answer should be.
            var reply = JsonNode.Parse(body);
            if (reply?["answer"] is JsonValue answerNode &&
                answerNode.TryGetValue(out string? answer) &&
                reply["tokens_used"] is JsonValue tokensNode &&
                tokensNode.TryGetValue(out long tokensUsed))
            {
                return (answer, tokensUsed);
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
    // queryResponse holds the fields of the reply that the program uses; a
    // pointer lets the program tell a missing field from a zero value.
    type queryResponse struct {
    	Answer     *string `json:"answer"`
    	TokensUsed *int    `json:"tokens_used"`
    }
    
    // errorText describes an error response, which carries a JSON body of the
    // form {"error": {"code": "...", "message": "..."}}.
    func errorText(body []byte) string {
    	var e struct {
    		Error struct {
    			Code    string `json:"code"`
    			Message string `json:"message"`
    		} `json:"error"`
    	}
    	if json.Unmarshal(body, &e) == nil && e.Error.Code != "" {
    		return e.Error.Code + ": " + e.Error.Message
    	}
    	return strings.TrimSpace(string(body))
    }
    
    // ask sends the question to the pipeline, and returns the answer with the
    // number of tokens the request used.
    func ask(client *http.Client, question string) (string, int, error) {
    	payload, err := json.Marshal(map[string]any{"query": question})
    	if err != nil {
    		return "", 0, err
    	}
    
    	// PathEscape escapes any character in the pipeline name that is not
    	// safe in a URL path.
    	endpoint := baseURL + "/v1/pipelines/" + url.PathEscape(pipeline)
    	response, err := client.Post(endpoint, "application/json", bytes.NewReader(payload))
    	if err != nil {
    		return "", 0, err
    	}
    	defer response.Body.Close()
    
    	body, err := io.ReadAll(response.Body)
    	if err != nil {
    		return "", 0, err
    	}
    
    	// Go treats an error status as a normal response, so check it here.
    	if response.StatusCode != http.StatusOK {
    		return "", 0, fmt.Errorf("HTTP %d, %s", response.StatusCode, errorText(body))
    	}
    
    	var result queryResponse
    	if err := json.Unmarshal(body, &result); err != nil ||
    		result.Answer == nil || result.TokensUsed == nil {
    		return "", 0, fmt.Errorf("unexpected response: %.200s", body)
    	}
    	return *result.Answer, *result.TokensUsed, nil
    }
    
    ```

=== "Rust"

    ```rust
    /// The errors that the functions below return; a string converts into one
    /// with the ? operator or into().
    type BoxError = Box<dyn Error>;
    
    /// Returns at most the first 200 characters of a reply.
    fn shorten(text: &str) -> String {
        text.chars().take(200).collect()
    }
    
    /// Describes an error response, which carries a JSON body of the form
    /// {"error": {"code": "...", "message": "..."}}.
    fn error_text(body: &str) -> String {
        // A body that is not JSON becomes Null, and indexing Null (or any
        // missing field) gives Null again, which as_str() turns into None.
        let reply: Value = serde_json::from_str(body).unwrap_or(Value::Null);
        let error = &reply["error"];
        match (error["code"].as_str(), error["message"].as_str()) {
            (Some(code), message) => format!("{code}: {}", message.unwrap_or("")),
            _ => shorten(body.trim()),
        }
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
    
    /// Sends the question to the pipeline, and returns the answer with the
    /// number of tokens the request used.
    fn ask(client: &Client, question: &str) -> Result<(String, u64), BoxError> {
        // json() serialises the request body, which escapes the question
        // correctly.
        let response = client
            .post(pipeline_url(&pipeline())?)
            .json(&json!({ "query": question }))
            .send()?;
        let status = response.status();
        let body = response.text()?;
    
        // reqwest treats an error status as a normal response, so check it
        // here.
        if !status.is_success() {
            return Err(format!("HTTP {}, {}", status.as_u16(), error_text(&body)).into());
        }
    
        // The as_ methods check the presence and the type of each field
        // together, as they give None for Null.
        let reply: Value = serde_json::from_str(&body).unwrap_or(Value::Null);
        match (reply["answer"].as_str(), reply["tokens_used"].as_u64()) {
            (Some(answer), Some(tokens_used)) => Ok((answer.to_string(), tokens_used)),
            _ => Err(format!("Unexpected response: {}", shorten(&body)).into()),
        }
    }
    ```

=== "Ruby"

    ```ruby
    # Raised when the RAG Server rejects a request or replies oddly.
    class RagError < StandardError; end
    
    # Parses text as a JSON object, and returns nil if it is not one.
    def parse_object(text)
      value = JSON.parse(text.to_s)
      value.is_a?(Hash) ? value : nil
    rescue JSON::ParserError
      nil
    end
    
    # Describes an error response, which carries a JSON body of the form
    # {"error": {"code": "...", "message": "..."}}.
    def error_text(response)
      error = parse_object(response.body)&.fetch("error", nil)
      if error.is_a?(Hash) && error["code"].is_a?(String)
        return "#{error["code"]}: #{error["message"]}"
      end
    
      response.body.to_s.strip[0, 200]
    end
    
    # Sends the question to the pipeline, and returns the answer with the
    # number of tokens the request used.
    def ask(http, question)
      # encode_uri_component escapes any character in the pipeline name that
      # is not safe in a URL path. JSON.generate builds the request body,
      # which escapes the question correctly.
      uri = URI("#{BASE_URL}/v1/pipelines/#{URI.encode_uri_component(PIPELINE)}")
      request = Net::HTTP::Post.new(uri, "Content-Type" => "application/json")
      request.body = JSON.generate({ query: question })
      response = http.request(request)
    
      # Net::HTTP treats an error status as a normal response, so check it
      # here.
      unless response.is_a?(Net::HTTPSuccess)
        raise RagError, "HTTP #{response.code}, #{error_text(response)}"
      end
    
      body = parse_object(response.body) || {}
      answer = body["answer"]
      tokens_used = body["tokens_used"]
      unless answer.is_a?(String) && tokens_used.is_a?(Integer)
        raise RagError, "Unexpected response: #{response.body.to_s[0, 200]}"
      end
    
      [answer, tokens_used]
    end
    ```

=== "curl"

    ```bash
    # Sends the question to the pipeline, and prints the JSON reply. jq builds
    # the request body, which escapes the question correctly. With
    # --fail-with-body, curl exits non-zero on an HTTP error status but still
    # prints the body, which carries the server's explanation.
    ask() {
        jq -n --arg query "$1" '{query: $query}' |
            curl --silent --show-error --fail-with-body \
                --max-time "$TIMEOUT_SECONDS" \
                --header 'Content-Type: application/json' \
                --data-binary @- \
                "$RAG_SERVER_URL/v1/pipelines/$(escape "$RAG_PIPELINE")"
    }
    ```

## Handling Errors and Printing the Answer

The main part of each program calls the function from the previous step and
prints the question, the answer, and the token count. The program reports any
failure on `stderr`, whether the server was unreachable or replied with an
error, and then exits with a non-zero status. The Python program catches
`httpx.HTTPError`, the base class for connection failures and timeouts, as well
as its own error class for error replies; the TypeScript program catches any
rejected promise; the Java program catches `IOException`, which covers
connection failures and timeouts, and its own exception class; the C# program
uses an exception filter that accepts `HttpRequestException`,
`TaskCanceledException` (for a timeout) and its own exception class; the Go and
Rust programs return each error from a `run()` function to `main()`, and the
Rust program also prints the chain of underlying causes; the Ruby program
rescues the standard library's network errors and its own error class; and the
curl script checks the exit status of `curl` explicitly. The following tabs
show the main part of each program:

=== "Python"

    ```python
    def main() -> int:
        try:
            # The with block closes the client's connections when it exits,
            # whether or not an error occurred.
            with httpx.Client(base_url=BASE_URL, timeout=TIMEOUT_SECONDS) as client:
                answer, tokens_used = ask(client, QUESTION)
        # httpx.HTTPError is the base class for failures to reach the server,
        # such as a refused connection or a timeout.
        except (httpx.HTTPError, RagError) as e:
            print(f"RAG Server error: {e}", file=sys.stderr)
            return 1
    
        print(f"Question: {QUESTION}")
        print(f"Answer:\n{answer}")
        print(f"Tokens used: {tokens_used}")
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
        const { answer, tokens_used } = await ask(question);
        console.log(`Question: ${question}`);
        console.log(`Answer:\n${answer}`);
        console.log(`Tokens used: ${tokens_used}`);
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
        try {
            Reply reply = ask(client, QUESTION);
            System.out.println("Question: " + QUESTION);
            System.out.println("Answer:\n" + reply.answer());
            System.out.println("Tokens used: " + reply.tokensUsed());
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
    try
    {
        // using disposes of the client, and closes its connections, when the
        // block exits, whether or not an error occurred.
        using var client = new HttpClient
        {
            Timeout = TimeSpan.FromSeconds(TimeoutSeconds),
        };
        var (answer, tokensUsed) = await AskAsync(client, Question);
    
        Console.WriteLine($"Question: {Question}");
        Console.WriteLine($"Answer:\n{answer}");
        Console.WriteLine($"Tokens used: {tokensUsed}");
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
    // the exception that the program throws for an error reply is declared
    // here, at the end.
    class RagException(string message) : Exception(message);
    ```

=== "Go"

    ```go
    // run asks the question and prints the reply, returning any error to the
    // caller.
    func run() error {
    	client := &http.Client{Timeout: timeout}
    
    	answer, tokensUsed, err := ask(client, question)
    	if err != nil {
    		return err
    	}
    
    	fmt.Printf("Question: %s\n", question)
    	fmt.Printf("Answer:\n%s\n", answer)
    	fmt.Printf("Tokens used: %d\n", tokensUsed)
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
    /// Asks the question and prints the reply. The ? operator returns any
    /// error to the caller.
    fn run() -> Result<(), BoxError> {
        let client = Client::builder().timeout(TIMEOUT).build()?;
        let (answer, tokens_used) = ask(&client, QUESTION)?;
    
        println!("Question: {QUESTION}");
        println!("Answer:\n{answer}");
        println!("Tokens used: {tokens_used}");
        Ok(())
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
    begin
      uri = URI(BASE_URL)
      # start opens a connection, and closes it when the block exits, whether
      # or not an error occurred.
      answer, tokens_used = Net::HTTP.start(
        uri.host, uri.port,
        use_ssl: uri.scheme == "https",
        open_timeout: TIMEOUT_SECONDS, read_timeout: TIMEOUT_SECONDS
      ) { |http| ask(http, QUESTION) }
    
      puts "Question: #{QUESTION}"
      puts "Answer:\n#{answer}"
      puts "Tokens used: #{tokens_used}"
    # SystemCallError covers a refused connection, Timeout::Error covers the
    # connection and read timeouts, and SocketError covers an unknown host.
    rescue RagError, SystemCallError, Timeout::Error, SocketError, IOError => e
      warn "RAG Server error: #{e.message}"
      exit 1
    end
    ```

=== "curl"

    ```bash
    main() {
        local response
        if ! response="$(ask "$QUESTION")"; then
            echo "RAG Server error: $response" >&2
            exit 1
        fi
    
        echo "Question: $QUESTION"
        # The error call makes jq fail when a field is missing or has the wrong
        # type, since interpolating null would print the word "null".
        jq -er 'if (.answer | type) == "string" and (.tokens_used | type) == "number"
                then "Answer:\n\(.answer)\nTokens used: \(.tokens_used)"
                else error("missing field") end' \
            <<<"$response" || {
            echo "Unexpected response: $response" >&2
            exit 1
        }
    }
    
    main
    ```

## Running the Example

The complete project for each language is available in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/rag_server/ask_question).
Set the environment variables for your RAG Server, and then run the command
for your language from the corresponding project directory. The following
tabs show the commands that build and run each example:

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
    Asking the pgEdge RAG Server a question, using httpx.
    
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
    
    QUESTION = "How long does the Acme Widget 2.0 take to charge?"
    
    # The server waits for the language model before it replies, and a small
    # model on a modest machine can take a while, so allow plenty of time.
    TIMEOUT_SECONDS = 300.0
    
    
    class RagError(Exception):
        """Raised when the RAG Server rejects a request or replies oddly."""
    
    
    def error_text(response: httpx.Response) -> str:
        """Describes an error response, which carries a JSON body of the form
        {"error": {"code": "...", "message": "..."}}."""
        try:
            error = response.json()["error"]
            return f"{error['code']}: {error['message']}"
        except (ValueError, KeyError, TypeError):
            return response.text[:200] or response.reason_phrase
    
    
    def ask(client: httpx.Client, question: str) -> tuple[str, int]:
        """Sends the question to the pipeline, and returns the answer with the
        number of tokens the request used."""
        # quote() escapes any character in the pipeline name that is not safe
        # in a URL path.
        response = client.post(
            f"/v1/pipelines/{quote(PIPELINE, safe='')}",
            json={"query": question},
        )
        if response.is_error:
            raise RagError(f"HTTP {response.status_code}, {error_text(response)}")
    
        try:
            body = response.json()
            return body["answer"], body["tokens_used"]
        except (ValueError, KeyError, TypeError):
            raise RagError(f"Unexpected response: {response.text[:200]}")
    
    
    def main() -> int:
        try:
            # The with block closes the client's connections when it exits,
            # whether or not an error occurred.
            with httpx.Client(base_url=BASE_URL, timeout=TIMEOUT_SECONDS) as client:
                answer, tokens_used = ask(client, QUESTION)
        # httpx.HTTPError is the base class for failures to reach the server,
        # such as a refused connection or a timeout.
        except (httpx.HTTPError, RagError) as e:
            print(f"RAG Server error: {e}", file=sys.stderr)
            return 1
    
        print(f"Question: {QUESTION}")
        print(f"Answer:\n{answer}")
        print(f"Tokens used: {tokens_used}")
        return 0
    
    
    if __name__ == "__main__":
        sys.exit(main())
    
    ```

=== "TypeScript"

    ```typescript
    /*
     * Ellie's Postgres Cookbook
     * Asking the pgEdge RAG Server a question, using the built-in fetch.
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
    
    const question = "How long does the Acme Widget 2.0 take to charge?";
    
    // The server waits for the language model before it replies, and a small
    // model on a modest machine can take a while, so allow plenty of time.
    const timeoutMs = 300_000;
    
    interface QueryResponse {
      answer: string;
      tokens_used: number;
    }
    
    // Describes an error response, which carries a JSON body of the form
    // {"error": {"code": "...", "message": "..."}}.
    async function errorText(response: Response): Promise<string> {
      const text = await response.text();
      try {
        const { error } = JSON.parse(text);
        return `${error.code}: ${error.message}`;
      } catch {
        return text.slice(0, 200) || response.statusText;
      }
    }
    
    // Sends the question to the pipeline, and returns the answer with the
    // number of tokens the request used.
    async function ask(question: string): Promise<QueryResponse> {
      // encodeURIComponent escapes any character in the pipeline name that is
      // not safe in a URL path.
      const response = await fetch(
        `${baseUrl}/v1/pipelines/${encodeURIComponent(pipeline)}`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ query: question }),
          signal: AbortSignal.timeout(timeoutMs),
        },
      );
    
      // fetch only rejects when it cannot reach the server; an error status
      // is a normal response, so check it explicitly.
      if (!response.ok) {
        throw new Error(`HTTP ${response.status}, ${await errorText(response)}`);
      }
    
      const body = (await response.json()) as Partial<QueryResponse>;
      if (typeof body.answer !== "string" || typeof body.tokens_used !== "number") {
        throw new Error(`Unexpected response: ${JSON.stringify(body).slice(0, 200)}`);
      }
      return { answer: body.answer, tokens_used: body.tokens_used };
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
        const { answer, tokens_used } = await ask(question);
        console.log(`Question: ${question}`);
        console.log(`Answer:\n${answer}`);
        console.log(`Tokens used: ${tokens_used}`);
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
     * Asking the pgEdge RAG Server a question, using java.net.http and
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
    
        static final String QUESTION =
                "How long does the Acme Widget 2.0 take to charge?";
    
        // The server waits for the language model before it replies, and a
        // small model on a modest machine can take a while, so allow plenty
        // of time.
        static final Duration TIMEOUT = Duration.ofSeconds(300);
    
        /** Thrown when the RAG Server rejects a request or replies oddly. */
        static class RagException extends Exception {
            RagException(String message) {
                super(message);
            }
        }
    
        /** The answer, and the number of tokens that the request used. */
        record Reply(String answer, long tokensUsed) {}
    
        // A mapper is safe to share, so the program creates only one.
        static final ObjectMapper MAPPER = JsonMapper.builder().build();
    
        /** Returns at most the first 200 characters of a reply. */
        static String shorten(String text) {
            return text.length() > 200 ? text.substring(0, 200) : text;
        }
    
        /**
         * Describes an error response, which carries a JSON body of the form
         * {"error": {"code": "...", "message": "..."}}.
         */
        static String errorText(String body) {
            try {
                JsonNode error = MAPPER.readTree(body).path("error");
                if (error.path("code").isString()) {
                    return error.path("code").stringValue() + ": "
                            + error.path("message").asString();
                }
            } catch (JacksonException e) {
                // The body is not JSON, so show it as it is.
            }
            return shorten(body.strip());
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
         * Sends the question to the pipeline, and returns the answer with the
         * number of tokens the request used.
         */
        static Reply ask(HttpClient client, String question)
                throws IOException, InterruptedException, RagException {
            // Jackson builds the request body, which escapes the question
            // correctly.
            String payload = MAPPER.writeValueAsString(
                    MAPPER.createObjectNode().put("query", question));
            HttpRequest request = HttpRequest.newBuilder(pipelineUri(PIPELINE))
                    .timeout(TIMEOUT)
                    .header("Content-Type", "application/json")
                    .POST(HttpRequest.BodyPublishers.ofString(payload))
                    .build();
            HttpResponse<String> response = send(client, request);
    
            // The client treats an error status as a normal response, so check
            // it here.
            if (response.statusCode() != 200) {
                throw new RagException("HTTP " + response.statusCode() + ", "
                        + errorText(response.body()));
            }
    
            try {
                JsonNode body = MAPPER.readTree(response.body());
                JsonNode answer = body.path("answer");
                JsonNode tokensUsed = body.path("tokens_used");
                if (answer.isString() && tokensUsed.isIntegralNumber()) {
                    return new Reply(answer.stringValue(), tokensUsed.longValue());
                }
            } catch (JacksonException e) {
                // The body is not JSON; report it below.
            }
            throw new RagException(
                    "Unexpected response: " + shorten(response.body()));
        }
    
        public static void main(String[] args) {
            HttpClient client = HttpClient.newHttpClient();
            try {
                Reply reply = ask(client, QUESTION);
                System.out.println("Question: " + QUESTION);
                System.out.println("Answer:\n" + reply.answer());
                System.out.println("Tokens used: " + reply.tokensUsed());
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
     * Asking the pgEdge RAG Server a question, using HttpClient and
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
    
    const string Question = "How long does the Acme Widget 2.0 take to charge?";
    
    // The server waits for the language model before it replies, and a small
    // model on a modest machine can take a while, so allow plenty of time.
    const int TimeoutSeconds = 300;
    
    // Returns at most the first 200 characters of a reply.
    static string Shorten(string text) =>
        text.Length > 200 ? text[..200] : text;
    
    // Describes an error response, which carries a JSON body of the form
    // {"error": {"code": "...", "message": "..."}}.
    static string ErrorText(string body)
    {
        try
        {
            if (JsonNode.Parse(body)?["error"] is JsonObject error &&
                error["code"] is JsonValue codeNode &&
                codeNode.TryGetValue(out string? code))
            {
                return $"{code}: {error["message"]}";
            }
        }
        catch (JsonException)
        {
            // The body is not JSON, so show it as it is.
        }
        return Shorten(body.Trim());
    }
    
    // Sends the question to the pipeline, and returns the answer with the
    // number of tokens the request used.
    static async Task<(string Answer, long TokensUsed)> AskAsync(
        HttpClient client, string question)
    {
        // EscapeDataString escapes any character in the pipeline name that is
        // not safe in a URL path. JsonContent serialises the request body,
        // which escapes the question correctly.
        var url = $"{BaseUrl()}/v1/pipelines/{Uri.EscapeDataString(Pipeline())}";
        using var response = await client.PostAsync(
            url, JsonContent.Create(new { query = question }));
        var body = await response.Content.ReadAsStringAsync();
    
        // HttpClient treats an error status as a normal response, so check it
        // here.
        if (!response.IsSuccessStatusCode)
        {
            throw new RagException(
                $"HTTP {(int)response.StatusCode}, {ErrorText(body)}");
        }
    
        try
        {
            // TryGetValue fails when a field holds a different type, such as
            // a number where the answer should be.
            var reply = JsonNode.Parse(body);
            if (reply?["answer"] is JsonValue answerNode &&
                answerNode.TryGetValue(out string? answer) &&
                reply["tokens_used"] is JsonValue tokensNode &&
                tokensNode.TryGetValue(out long tokensUsed))
            {
                return (answer, tokensUsed);
            }
        }
        catch (JsonException)
        {
            // The body is not JSON; report it below.
        }
        throw new RagException($"Unexpected response: {Shorten(body)}");
    }
    
    try
    {
        // using disposes of the client, and closes its connections, when the
        // block exits, whether or not an error occurred.
        using var client = new HttpClient
        {
            Timeout = TimeSpan.FromSeconds(TimeoutSeconds),
        };
        var (answer, tokensUsed) = await AskAsync(client, Question);
    
        Console.WriteLine($"Question: {Question}");
        Console.WriteLine($"Answer:\n{answer}");
        Console.WriteLine($"Tokens used: {tokensUsed}");
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
    // the exception that the program throws for an error reply is declared
    // here, at the end.
    class RagException(string message) : Exception(message);
    
    ```

=== "Go"

    ```go
    // Ellie's Postgres Cookbook
    // Asking the pgEdge RAG Server a question, using net/http.
    //
    // These examples are for pgEdge RAG Server 2.0.0.
    //
    // Copyright (c) 2026, pgEdge, Inc.
    // This code is released under the PostgreSQL License.
    
    package main
    
    import (
    	"bytes"
    	"encoding/json"
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
    
    const question = "How long does the Acme Widget 2.0 take to charge?"
    
    // The server waits for the language model before it replies, and a small
    // model on a modest machine can take a while, so allow plenty of time.
    const timeout = 300 * time.Second
    
    
    // queryResponse holds the fields of the reply that the program uses; a
    // pointer lets the program tell a missing field from a zero value.
    type queryResponse struct {
    	Answer     *string `json:"answer"`
    	TokensUsed *int    `json:"tokens_used"`
    }
    
    // errorText describes an error response, which carries a JSON body of the
    // form {"error": {"code": "...", "message": "..."}}.
    func errorText(body []byte) string {
    	var e struct {
    		Error struct {
    			Code    string `json:"code"`
    			Message string `json:"message"`
    		} `json:"error"`
    	}
    	if json.Unmarshal(body, &e) == nil && e.Error.Code != "" {
    		return e.Error.Code + ": " + e.Error.Message
    	}
    	return strings.TrimSpace(string(body))
    }
    
    // ask sends the question to the pipeline, and returns the answer with the
    // number of tokens the request used.
    func ask(client *http.Client, question string) (string, int, error) {
    	payload, err := json.Marshal(map[string]any{"query": question})
    	if err != nil {
    		return "", 0, err
    	}
    
    	// PathEscape escapes any character in the pipeline name that is not
    	// safe in a URL path.
    	endpoint := baseURL + "/v1/pipelines/" + url.PathEscape(pipeline)
    	response, err := client.Post(endpoint, "application/json", bytes.NewReader(payload))
    	if err != nil {
    		return "", 0, err
    	}
    	defer response.Body.Close()
    
    	body, err := io.ReadAll(response.Body)
    	if err != nil {
    		return "", 0, err
    	}
    
    	// Go treats an error status as a normal response, so check it here.
    	if response.StatusCode != http.StatusOK {
    		return "", 0, fmt.Errorf("HTTP %d, %s", response.StatusCode, errorText(body))
    	}
    
    	var result queryResponse
    	if err := json.Unmarshal(body, &result); err != nil ||
    		result.Answer == nil || result.TokensUsed == nil {
    		return "", 0, fmt.Errorf("unexpected response: %.200s", body)
    	}
    	return *result.Answer, *result.TokensUsed, nil
    }
    
    
    // run asks the question and prints the reply, returning any error to the
    // caller.
    func run() error {
    	client := &http.Client{Timeout: timeout}
    
    	answer, tokensUsed, err := ask(client, question)
    	if err != nil {
    		return err
    	}
    
    	fmt.Printf("Question: %s\n", question)
    	fmt.Printf("Answer:\n%s\n", answer)
    	fmt.Printf("Tokens used: %d\n", tokensUsed)
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
    // Asking the pgEdge RAG Server a question, using reqwest and serde_json.
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
    
    const QUESTION: &str = "How long does the Acme Widget 2.0 take to charge?";
    
    /// The server waits for the language model before it replies, and a small
    /// model on a modest machine can take a while, so allow plenty of time.
    const TIMEOUT: Duration = Duration::from_secs(300);
    
    /// The errors that the functions below return; a string converts into one
    /// with the ? operator or into().
    type BoxError = Box<dyn Error>;
    
    /// Returns at most the first 200 characters of a reply.
    fn shorten(text: &str) -> String {
        text.chars().take(200).collect()
    }
    
    /// Describes an error response, which carries a JSON body of the form
    /// {"error": {"code": "...", "message": "..."}}.
    fn error_text(body: &str) -> String {
        // A body that is not JSON becomes Null, and indexing Null (or any
        // missing field) gives Null again, which as_str() turns into None.
        let reply: Value = serde_json::from_str(body).unwrap_or(Value::Null);
        let error = &reply["error"];
        match (error["code"].as_str(), error["message"].as_str()) {
            (Some(code), message) => format!("{code}: {}", message.unwrap_or("")),
            _ => shorten(body.trim()),
        }
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
    
    /// Sends the question to the pipeline, and returns the answer with the
    /// number of tokens the request used.
    fn ask(client: &Client, question: &str) -> Result<(String, u64), BoxError> {
        // json() serialises the request body, which escapes the question
        // correctly.
        let response = client
            .post(pipeline_url(&pipeline())?)
            .json(&json!({ "query": question }))
            .send()?;
        let status = response.status();
        let body = response.text()?;
    
        // reqwest treats an error status as a normal response, so check it
        // here.
        if !status.is_success() {
            return Err(format!("HTTP {}, {}", status.as_u16(), error_text(&body)).into());
        }
    
        // The as_ methods check the presence and the type of each field
        // together, as they give None for Null.
        let reply: Value = serde_json::from_str(&body).unwrap_or(Value::Null);
        match (reply["answer"].as_str(), reply["tokens_used"].as_u64()) {
            (Some(answer), Some(tokens_used)) => Ok((answer.to_string(), tokens_used)),
            _ => Err(format!("Unexpected response: {}", shorten(&body)).into()),
        }
    }
    
    /// Asks the question and prints the reply. The ? operator returns any
    /// error to the caller.
    fn run() -> Result<(), BoxError> {
        let client = Client::builder().timeout(TIMEOUT).build()?;
        let (answer, tokens_used) = ask(&client, QUESTION)?;
    
        println!("Question: {QUESTION}");
        println!("Answer:\n{answer}");
        println!("Tokens used: {tokens_used}");
        Ok(())
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
    # Asking the pgEdge RAG Server a question, using Net::HTTP.
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
    
    QUESTION = "How long does the Acme Widget 2.0 take to charge?"
    
    # The server waits for the language model before it replies, and a small
    # model on a modest machine can take a while, so allow plenty of time.
    TIMEOUT_SECONDS = 300
    
    # Raised when the RAG Server rejects a request or replies oddly.
    class RagError < StandardError; end
    
    # Parses text as a JSON object, and returns nil if it is not one.
    def parse_object(text)
      value = JSON.parse(text.to_s)
      value.is_a?(Hash) ? value : nil
    rescue JSON::ParserError
      nil
    end
    
    # Describes an error response, which carries a JSON body of the form
    # {"error": {"code": "...", "message": "..."}}.
    def error_text(response)
      error = parse_object(response.body)&.fetch("error", nil)
      if error.is_a?(Hash) && error["code"].is_a?(String)
        return "#{error["code"]}: #{error["message"]}"
      end
    
      response.body.to_s.strip[0, 200]
    end
    
    # Sends the question to the pipeline, and returns the answer with the
    # number of tokens the request used.
    def ask(http, question)
      # encode_uri_component escapes any character in the pipeline name that
      # is not safe in a URL path. JSON.generate builds the request body,
      # which escapes the question correctly.
      uri = URI("#{BASE_URL}/v1/pipelines/#{URI.encode_uri_component(PIPELINE)}")
      request = Net::HTTP::Post.new(uri, "Content-Type" => "application/json")
      request.body = JSON.generate({ query: question })
      response = http.request(request)
    
      # Net::HTTP treats an error status as a normal response, so check it
      # here.
      unless response.is_a?(Net::HTTPSuccess)
        raise RagError, "HTTP #{response.code}, #{error_text(response)}"
      end
    
      body = parse_object(response.body) || {}
      answer = body["answer"]
      tokens_used = body["tokens_used"]
      unless answer.is_a?(String) && tokens_used.is_a?(Integer)
        raise RagError, "Unexpected response: #{response.body.to_s[0, 200]}"
      end
    
      [answer, tokens_used]
    end
    
    begin
      uri = URI(BASE_URL)
      # start opens a connection, and closes it when the block exits, whether
      # or not an error occurred.
      answer, tokens_used = Net::HTTP.start(
        uri.host, uri.port,
        use_ssl: uri.scheme == "https",
        open_timeout: TIMEOUT_SECONDS, read_timeout: TIMEOUT_SECONDS
      ) { |http| ask(http, QUESTION) }
    
      puts "Question: #{QUESTION}"
      puts "Answer:\n#{answer}"
      puts "Tokens used: #{tokens_used}"
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
    # Asking the pgEdge RAG Server a question, using curl and jq.
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
    
    QUESTION="How long does the Acme Widget 2.0 take to charge?"
    
    # The server waits for the language model before it replies, and a small
    # model on a modest machine can take a while, so allow plenty of time.
    TIMEOUT_SECONDS=300
    
    # Escapes a value for use in a URL path, as the other languages do.
    escape() { jq -rn --arg value "$1" '$value | @uri'; }
    
    # Sends the question to the pipeline, and prints the JSON reply. jq builds
    # the request body, which escapes the question correctly. With
    # --fail-with-body, curl exits non-zero on an HTTP error status but still
    # prints the body, which carries the server's explanation.
    ask() {
        jq -n --arg query "$1" '{query: $query}' |
            curl --silent --show-error --fail-with-body \
                --max-time "$TIMEOUT_SECONDS" \
                --header 'Content-Type: application/json' \
                --data-binary @- \
                "$RAG_SERVER_URL/v1/pipelines/$(escape "$RAG_PIPELINE")"
    }
    
    main() {
        local response
        if ! response="$(ask "$QUESTION")"; then
            echo "RAG Server error: $response" >&2
            exit 1
        fi
    
        echo "Question: $QUESTION"
        # The error call makes jq fail when a field is missing or has the wrong
        # type, since interpolating null would print the word "null".
        jq -er 'if (.answer | type) == "string" and (.tokens_used | type) == "number"
                then "Answer:\n\(.answer)\nTokens used: \(.tokens_used)"
                else error("missing field") end' \
            <<<"$response" || {
            echo "Unexpected response: $response" >&2
            exit 1
        }
    }
    
    main
    
    ```

## Next Steps

The following resources provide more information about the topics in this
recipe:

- The [Streaming an Answer](stream_answer.md) recipe shows how to display
  the answer as the model writes it.
- The [Showing the Sources of an Answer](include_sources.md) recipe shows how
  to list the documents that an answer came from.
- The
  [pgEdge RAG Server documentation](https://docs.pgedge.com/pgedge-rag-server/)
  describes the API and the pipeline configuration.
- The [Contributing a Recipe](../contributing.md) page explains how to add
  a recipe or a language to the cookbook.
