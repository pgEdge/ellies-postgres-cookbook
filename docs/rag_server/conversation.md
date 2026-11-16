# Holding a Conversation

This recipe holds a short conversation with a pgEdge RAG Server pipeline, in
which the second question only makes sense with the first question and its
answer in front of it. The server keeps no conversation between requests, so
the program sends the earlier messages with each new question. Each step shows
the code in every supported language; selecting a language tab switches every
tab on the site to that language.

These examples are for pgEdge RAG Server 2.0.0.

The wording of the answers varies from run to run, because a language model
writes them, but the output has the following shape:

```text
You: How long does the Acme Widget 2.0 take to charge?
Assistant: The Acme Widget 2.0 takes ninety minutes to charge fully.
You: And how many hours does the Acme Widget run for once it is charged?
Assistant: Once charged, it runs for eighteen hours.
```

## Preparing the Ingredients

The examples assume a running RAG Server with a pipeline named `cookbook` that
holds the fictional Acme Widget support documents. The
`scripts/start_rag_server.sh` script in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook) loads
those documents and starts the server in Docker, and the
[Preparing Data for the RAG Server](prepare_data.md) recipe shows how to build
such a table and pipeline yourself.

The second question, 'And how many hours does the Acme Widget run for once it
is charged?', does not say which version of the product it means, so the model
can answer it only if it knows what the first question was about. The request
body therefore carries a `messages` list next to the `query`. Each message has
a `role` of `user` or `assistant`, and a `content` string, and the list holds
the earlier turns in order. The pipeline passes the history to the language
model, but it searches for documents using the `query` alone. A follow-up
question must therefore still name its subject, here the Acme Widget, for the
search to find the right documents, and the history only settles the details
that the question leaves out, here the version. The
[Asking a Question](ask_question.md) recipe describes the request without a
history. The following example shows the body of the second request:

```json
{
  "query": "And how many hours does the Acme Widget run for once it is charged?",
  "messages": [
    {"role": "user", "content": "How long does the Acme Widget 2.0 take to charge?"},
    {"role": "assistant", "content": "It takes ninety minutes."}
  ]
}
```

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
      "name": "conversation",
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
    import java.util.List;
    import java.util.concurrent.CompletableFuture;
    import java.util.concurrent.ExecutionException;
    import java.util.concurrent.TimeUnit;
    import java.util.concurrent.TimeoutException;
    
    import tools.jackson.core.JacksonException;
    import tools.jackson.databind.JsonNode;
    import tools.jackson.databind.ObjectMapper;
    import tools.jackson.databind.json.JsonMapper;
    import tools.jackson.databind.node.ArrayNode;
    import tools.jackson.databind.node.ObjectNode;
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

The examples read the address of the RAG Server from the `RAG_SERVER_URL`
environment variable, and treat an empty value as unset. The `RAG_PIPELINE`
variable names the pipeline. The program also holds the two questions, and
allows 300 seconds for each reply, because a small model on a modest machine
can take a while to write an answer. The following table describes the
environment variables:

| Variable         | Default                 | Description                      |
|------------------|-------------------------|----------------------------------|
| `RAG_SERVER_URL` | `http://localhost:8080` | The base URL of the RAG Server.  |
| `RAG_PIPELINE`   | `cookbook` | The name of the pipeline to ask. |

The following tabs show how each program reads its settings:

=== "Python"

    ```python
    # The or operator treats an empty variable as unset.
    BASE_URL = (os.environ.get("RAG_SERVER_URL") or "http://localhost:8080").rstrip("/")
    PIPELINE = os.environ.get("RAG_PIPELINE") or "cookbook"
    
    # The second question does not say which version of the Acme Widget it
    # means, so only the first question and its answer, which the model
    # receives as history, settle that. The search uses only the current
    # question, which is why this one still names the product.
    QUESTIONS = [
        "How long does the Acme Widget 2.0 take to charge?",
        "And how many hours does the Acme Widget run for once it is charged?",
    ]
    
    # The server waits for the language model before it replies, and a small
    # model on a modest machine can take a while, so allow plenty of time.
    TIMEOUT_SECONDS = 300.0
    ```

=== "TypeScript"

    ```typescript
    // The || operator, unlike ??, also treats an empty variable as unset.
    const baseUrl = (process.env.RAG_SERVER_URL || "http://localhost:8080").replace(/\/+$/, "");
    const pipeline = process.env.RAG_PIPELINE || "cookbook";
    
    // The second question does not say which version of the Acme Widget it
    // means, so only the first question and its answer, which the model
    // receives as history, settle that. The search uses only the current
    // question, which is why this one still names the product.
    const questions = [
      "How long does the Acme Widget 2.0 take to charge?",
      "And how many hours does the Acme Widget run for once it is charged?",
    ];
    
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
    
    // The second question does not say which version of the Acme Widget
    // it means, so only the first question and its answer, which the
    // model receives as history, settle that. The search uses only the
    // current question, which is why this one still names the product.
    static final List<String> QUESTIONS = List.of(
            "How long does the Acme Widget 2.0 take to charge?",
            "And how many hours does the Acme Widget run for once it is charged?");
    
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
    
    // The second question does not say which version of the Acme Widget it
    // means, so only the first question and its answer, which the model
    // receives as history, settle that. The search uses only the current
    // question, which is why this one still names the product.
    string[] questions =
    [
        "How long does the Acme Widget 2.0 take to charge?",
        "And how many hours does the Acme Widget run for once it is charged?",
    ];
    
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
    
    // The second question does not say which version of the Acme Widget it
    // means, so only the first question and its answer, which the model
    // receives as history, settle that. The search uses only the current
    // question, which is why this one still names the product.
    var questions = []string{
    	"How long does the Acme Widget 2.0 take to charge?",
    	"And how many hours does the Acme Widget run for once it is charged?",
    }
    
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
    
    /// The second question does not say which version of the Acme Widget it
    /// means, so only the first question and its answer, which the model
    /// receives as history, settle that. The search uses only the current
    /// question, which is why this one still names the product.
    const QUESTIONS: [&str; 2] = [
        "How long does the Acme Widget 2.0 take to charge?",
        "And how many hours does the Acme Widget run for once it is charged?",
    ];
    
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
    
    # The second question does not say which version of the Acme Widget it
    # means, so only the first question and its answer, which the model
    # receives as history, settle that. The search uses only the current
    # question, which is why this one still names the product.
    QUESTIONS = [
      "How long does the Acme Widget 2.0 take to charge?",
      "And how many hours does the Acme Widget run for once it is charged?"
    ].freeze
    
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
    
    # The second question does not say which version of the Acme Widget it
    # means, so only the first question and its answer, which the model
    # receives as history, settle that. The search uses only the current
    # question, which is why this one still names the product.
    QUESTIONS=(
        "How long does the Acme Widget 2.0 take to charge?"
        "And how many hours does the Acme Widget run for once it is charged?"
    )
    
    # The server waits for the language model before it replies, and a small
    # model on a modest machine can take a while, so allow plenty of time.
    TIMEOUT_SECONDS=300
    
    # Escapes a value for use in a URL path, as the other languages do.
    escape() { jq -rn --arg value "$1" '$value | @uri'; }
    ```

## Asking a Question with a History

Each program sends the question and the history in a `POST` request, and
returns the answer. The RAG Server reports a failure with an HTTP error status
and a JSON body that holds an error code and a message, and the programs print
both. The following tabs show how each program sends a question:

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
    
    
    def ask(client: httpx.Client, question: str, history: list[dict]) -> str:
        """Sends a question and the conversation so far to the pipeline, and
        returns the answer. The server keeps no conversation between requests,
        so history lists the earlier messages, each with a role of user or
        assistant, in order."""
        response = client.post(
            f"/v1/pipelines/{quote(PIPELINE, safe='')}",
            json={"query": question, "messages": history},
        )
        if response.is_error:
            raise RagError(f"HTTP {response.status_code}, {error_text(response)}")
    
        try:
            answer = response.json()["answer"]
            if isinstance(answer, str):
                return answer
        except (ValueError, KeyError, TypeError):
            pass
        raise RagError(f"Unexpected response: {response.text[:200]}")
    ```

=== "TypeScript"

    ```typescript
    interface Message {
      role: "user" | "assistant";
      content: string;
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
    
    // Sends a question and the conversation so far to the pipeline, and
    // returns the answer. The server keeps no conversation between requests,
    // so history lists the earlier messages, each with a role of user or
    // assistant, in order.
    async function ask(question: string, history: Message[]): Promise<string> {
      const response = await fetch(
        `${baseUrl}/v1/pipelines/${encodeURIComponent(pipeline)}`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ query: question, messages: history }),
          signal: AbortSignal.timeout(timeoutMs),
        },
      );
    
      // fetch only rejects when it cannot reach the server; an error status
      // is a normal response, so check it explicitly.
      if (!response.ok) {
        throw new Error(`HTTP ${response.status}, ${await errorText(response)}`);
      }
    
      const body = (await response.json()) as { answer?: unknown };
      if (typeof body.answer !== "string") {
        throw new Error(`Unexpected response: ${JSON.stringify(body).slice(0, 200)}`);
      }
      return body.answer;
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
     * Sends a question and the conversation so far to the pipeline, and
     * returns the answer. The server keeps no conversation between
     * requests, so history lists the earlier messages, each with a role of
     * user or assistant, in order.
     */
    static String ask(HttpClient client, String question, ArrayNode history)
            throws IOException, InterruptedException, RagException {
        ObjectNode payload = MAPPER.createObjectNode();
        payload.put("query", question);
        payload.set("messages", history);
        HttpRequest request = HttpRequest.newBuilder(pipelineUri(PIPELINE))
                .timeout(TIMEOUT)
                .header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString(
                        MAPPER.writeValueAsString(payload)))
                .build();
        HttpResponse<String> response = send(client, request);
    
        // The client treats an error status as a normal response, so check
        // it here.
        if (response.statusCode() != 200) {
            throw new RagException("HTTP " + response.statusCode() + ", "
                    + errorText(response.body()));
        }
    
        try {
            JsonNode answer = MAPPER.readTree(response.body()).path("answer");
            if (answer.isString()) {
                return answer.stringValue();
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
    
    // Sends a question and the conversation so far to the pipeline, and
    // returns the answer. The server keeps no conversation between requests,
    // so history lists the earlier messages, each with a role of user or
    // assistant, in order.
    static async Task<string> AskAsync(
        HttpClient client, string question, List<Message> history)
    {
        var url = $"{BaseUrl()}/v1/pipelines/{Uri.EscapeDataString(Pipeline())}";
        using var response = await client.PostAsync(
            url, JsonContent.Create(new { query = question, messages = history }));
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
            // TryGetValue fails when the answer holds a different type, such
            // as a number.
            if (JsonNode.Parse(body)?["answer"] is JsonValue answerNode &&
                answerNode.TryGetValue(out string? answer))
            {
                return answer;
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
    // message is one turn of a conversation. The role is "user" or
    // "assistant".
    type message struct {
    	Role    string `json:"role"`
    	Content string `json:"content"`
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
    
    // ask sends a question and the conversation so far to the pipeline, and
    // returns the answer. The server keeps no conversation between requests,
    // so history lists the earlier messages, each with a role of user or
    // assistant, in order.
    func ask(client *http.Client, question string, history []message) (string, error) {
    	payload, err := json.Marshal(map[string]any{
    		"query":    question,
    		"messages": history,
    	})
    	if err != nil {
    		return "", err
    	}
    
    	endpoint := baseURL + "/v1/pipelines/" + url.PathEscape(pipeline)
    	response, err := client.Post(endpoint, "application/json", bytes.NewReader(payload))
    	if err != nil {
    		return "", err
    	}
    	defer response.Body.Close()
    
    	body, err := io.ReadAll(response.Body)
    	if err != nil {
    		return "", err
    	}
    
    	// Go treats an error status as a normal response, so check it here.
    	if response.StatusCode != http.StatusOK {
    		return "", fmt.Errorf("HTTP %d, %s", response.StatusCode, errorText(body))
    	}
    
    	// The answer is a pointer so that the program can tell a missing field
    	// from an empty one.
    	var result struct {
    		Answer *string `json:"answer"`
    	}
    	if err := json.Unmarshal(body, &result); err != nil || result.Answer == nil {
    		return "", fmt.Errorf("unexpected response: %.200s", body)
    	}
    	return *result.Answer, nil
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
    
    /// Sends a question and the conversation so far to the pipeline, and
    /// returns the answer. The server keeps no conversation between requests,
    /// so history lists the earlier messages, each with a role of user or
    /// assistant, in order.
    fn ask(client: &Client, question: &str, history: &[Value]) -> Result<String, BoxError> {
        let response = client
            .post(pipeline_url(&pipeline())?)
            .json(&json!({ "query": question, "messages": history }))
            .send()?;
        let status = response.status();
        let body = response.text()?;
    
        // reqwest treats an error status as a normal response, so check it
        // here.
        if !status.is_success() {
            return Err(format!("HTTP {}, {}", status.as_u16(), error_text(&body)).into());
        }
    
        // as_str() gives None when the answer is missing or is not a string.
        let reply: Value = serde_json::from_str(&body).unwrap_or(Value::Null);
        match reply["answer"].as_str() {
            Some(answer) => Ok(answer.to_string()),
            None => Err(format!("Unexpected response: {}", shorten(&body)).into()),
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
    
    # Sends a question and the conversation so far to the pipeline, and
    # returns the answer. The server keeps no conversation between requests,
    # so history lists the earlier messages, each with a role of user or
    # assistant, in order.
    def ask(http, question, history)
      uri = URI("#{BASE_URL}/v1/pipelines/#{URI.encode_uri_component(PIPELINE)}")
      request = Net::HTTP::Post.new(uri, "Content-Type" => "application/json")
      request.body = JSON.generate({ query: question, messages: history })
      response = http.request(request)
    
      # Net::HTTP treats an error status as a normal response, so check it
      # here.
      unless response.is_a?(Net::HTTPSuccess)
        raise RagError, "HTTP #{response.code}, #{error_text(response)}"
      end
    
      answer = parse_object(response.body)&.fetch("answer", nil)
      unless answer.is_a?(String)
        raise RagError, "Unexpected response: #{response.body.to_s[0, 200]}"
      end
    
      answer
    end
    ```

=== "curl"

    ```bash
    # Sends a question and the conversation so far to the pipeline, and prints
    # the JSON reply. The server keeps no conversation between requests, so
    # the second argument is a JSON array of the earlier messages, each with a
    # role of user or assistant, in order. With --fail-with-body, curl exits
    # non-zero on an HTTP error status but still prints the body, which
    # carries the server's explanation.
    ask() {
        jq -n --arg query "$1" --argjson messages "$2" \
            '{query: $query, messages: $messages}' |
            curl --silent --show-error --fail-with-body \
                --max-time "$TIMEOUT_SECONDS" \
                --header 'Content-Type: application/json' \
                --data-binary @- \
                "$RAG_SERVER_URL/v1/pipelines/$(escape "$RAG_PIPELINE")"
    }
    ```

## Keeping the History

After each answer, the program adds the question as a `user` message and the
answer as an `assistant` message, so that the next request carries both. The
history belongs to the client, which means that it can also trim or edit the
history to keep requests small. The following tabs show how each program asks
the questions in turn:

=== "Python"

    ```python
    def converse(client: httpx.Client) -> None:
        """Asks each question in turn, printing both sides of the conversation.
        After each answer, the question and the answer join the history that
        the next request carries."""
        history: list[dict] = []
        for question in QUESTIONS:
            answer = ask(client, question, history)
            print(f"You: {question}")
            print(f"Assistant: {answer}")
            history += [
                {"role": "user", "content": question},
                {"role": "assistant", "content": answer},
            ]
    ```

=== "TypeScript"

    ```typescript
    // Asks each question in turn, printing both sides of the conversation.
    // After each answer, the question and the answer join the history that the
    // next request carries.
    async function converse(): Promise<void> {
      const history: Message[] = [];
      for (const question of questions) {
        const answer = await ask(question, history);
        console.log(`You: ${question}`);
        console.log(`Assistant: ${answer}`);
        history.push(
          { role: "user", content: question },
          { role: "assistant", content: answer },
        );
      }
    }
    ```

=== "Java"

    ```java
    /**
     * Asks each question in turn, printing both sides of the conversation.
     * After each answer, the question and the answer join the history that
     * the next request carries.
     */
    static void converse(HttpClient client)
            throws IOException, InterruptedException, RagException {
        ArrayNode history = MAPPER.createArrayNode();
        for (String question : QUESTIONS) {
            String answer = ask(client, question, history);
            System.out.println("You: " + question);
            System.out.println("Assistant: " + answer);
            history.addObject().put("role", "user").put("content", question);
            history.addObject().put("role", "assistant").put("content", answer);
        }
    }
    ```

=== "C#"

    ```csharp
    // Asks each question in turn, printing both sides of the conversation.
    // After each answer, the question and the answer join the history that
    // the next request carries.
    static async Task ConverseAsync(HttpClient client, string[] questions)
    {
        var history = new List<Message>();
        foreach (var question in questions)
        {
            var answer = await AskAsync(client, question, history);
            Console.WriteLine($"You: {question}");
            Console.WriteLine($"Assistant: {answer}");
            history.Add(new Message("user", question));
            history.Add(new Message("assistant", answer));
        }
    }
    ```

=== "Go"

    ```go
    // converse asks each question in turn, printing both sides of the
    // conversation. After each answer, the question and the answer join the
    // history that the next request carries.
    func converse(client *http.Client) error {
    	// A non-nil slice encodes as [] rather than null in the first request.
    	history := []message{}
    	for _, question := range questions {
    		answer, err := ask(client, question, history)
    		if err != nil {
    			return err
    		}
    		fmt.Printf("You: %s\n", question)
    		fmt.Printf("Assistant: %s\n", answer)
    		history = append(history,
    			message{Role: "user", Content: question},
    			message{Role: "assistant", Content: answer})
    	}
    	return nil
    }
    
    ```

=== "Rust"

    ```rust
    /// Asks each question in turn, printing both sides of the conversation.
    /// After each answer, the question and the answer join the history that
    /// the next request carries.
    fn converse(client: &Client) -> Result<(), BoxError> {
        let mut history: Vec<Value> = Vec::new();
        for question in QUESTIONS {
            let answer = ask(client, question, &history)?;
            println!("You: {question}");
            println!("Assistant: {answer}");
            history.push(json!({ "role": "user", "content": question }));
            history.push(json!({ "role": "assistant", "content": answer }));
        }
        Ok(())
    }
    ```

=== "Ruby"

    ```ruby
    # Asks each question in turn, printing both sides of the conversation.
    # After each answer, the question and the answer join the history that
    # the next request carries.
    def converse(http)
      history = []
      QUESTIONS.each do |question|
        answer = ask(http, question, history)
        puts "You: #{question}"
        puts "Assistant: #{answer}"
        history << { role: "user", content: question }
        history << { role: "assistant", content: answer }
      end
    end
    ```

=== "curl"

    ```bash
    # Asks each question in turn, printing both sides of the conversation. After
    # each answer, the question and the answer join the history that the next
    # request carries.
    converse() {
        local history='[]' question response answer
    
        for question in "${QUESTIONS[@]}"; do
            if ! response="$(ask "$question" "$history")"; then
                echo "RAG Server error: $response" >&2
                return 1
            fi
    
            # The error call makes jq fail when the answer is missing or is not
            # a string, since interpolating null would print the word "null".
            if ! answer="$(jq -er 'if (.answer | type) == "string"
                                   then .answer
                                   else error("missing answer") end' \
                              <<<"$response")"; then
                echo "Unexpected response: $response" >&2
                return 1
            fi
    
            echo "You: $question"
            echo "Assistant: $answer"
    
            history="$(jq -c --arg question "$question" --arg answer "$answer" \
                '. + [{role: "user", content: $question},
                      {role: "assistant", content: $answer}]' <<<"$history")"
        done
    }
    ```

## Handling Errors

The main part of each program holds the conversation, reports any failure on
`stderr`, whether the server was unreachable or replied with an error, and then
exits with a non-zero status. The following tabs show the main part of each
program:

=== "Python"

    ```python
    def main() -> int:
        try:
            with httpx.Client(base_url=BASE_URL, timeout=TIMEOUT_SECONDS) as client:
                converse(client)
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
        await converse();
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
            converse(client);
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
        await ConverseAsync(client, questions);
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
    // the types that the program uses are declared here, at the end. A
    // message is one turn of the conversation; JsonContent writes its
    // properties in camel case, as role and content.
    record Message(string Role, string Content);
    
    class RagException(string message) : Exception(message);
    ```

=== "Go"

    ```go
    // main reports any error returned by converse() and exits with a non-zero
    // status.
    func main() {
    	client := &http.Client{Timeout: timeout}
    	if err := converse(client); err != nil {
    		fmt.Fprintf(os.Stderr, "RAG Server error: %v\n", err)
    		os.Exit(1)
    	}
    }
    
    ```

=== "Rust"

    ```rust
    /// Holds the conversation. The ? operator returns any error to the
    /// caller.
    fn run() -> Result<(), BoxError> {
        let client = Client::builder().timeout(TIMEOUT).build()?;
        converse(&client)
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
      Net::HTTP.start(
        uri.host, uri.port,
        use_ssl: uri.scheme == "https",
        open_timeout: TIMEOUT_SECONDS, read_timeout: TIMEOUT_SECONDS
      ) { |http| converse(http) }
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
        converse
    }
    
    main
    ```

## Running the Example

The complete project for each language is available in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/rag_server/conversation).
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
    Holding a conversation with the pgEdge RAG Server, using httpx.
    
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
    
    # The second question does not say which version of the Acme Widget it
    # means, so only the first question and its answer, which the model
    # receives as history, settle that. The search uses only the current
    # question, which is why this one still names the product.
    QUESTIONS = [
        "How long does the Acme Widget 2.0 take to charge?",
        "And how many hours does the Acme Widget run for once it is charged?",
    ]
    
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
    
    
    def ask(client: httpx.Client, question: str, history: list[dict]) -> str:
        """Sends a question and the conversation so far to the pipeline, and
        returns the answer. The server keeps no conversation between requests,
        so history lists the earlier messages, each with a role of user or
        assistant, in order."""
        response = client.post(
            f"/v1/pipelines/{quote(PIPELINE, safe='')}",
            json={"query": question, "messages": history},
        )
        if response.is_error:
            raise RagError(f"HTTP {response.status_code}, {error_text(response)}")
    
        try:
            answer = response.json()["answer"]
            if isinstance(answer, str):
                return answer
        except (ValueError, KeyError, TypeError):
            pass
        raise RagError(f"Unexpected response: {response.text[:200]}")
    
    
    def converse(client: httpx.Client) -> None:
        """Asks each question in turn, printing both sides of the conversation.
        After each answer, the question and the answer join the history that
        the next request carries."""
        history: list[dict] = []
        for question in QUESTIONS:
            answer = ask(client, question, history)
            print(f"You: {question}")
            print(f"Assistant: {answer}")
            history += [
                {"role": "user", "content": question},
                {"role": "assistant", "content": answer},
            ]
    
    
    def main() -> int:
        try:
            with httpx.Client(base_url=BASE_URL, timeout=TIMEOUT_SECONDS) as client:
                converse(client)
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
     * Holding a conversation with the pgEdge RAG Server, using the built-in
     * fetch.
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
    
    // The second question does not say which version of the Acme Widget it
    // means, so only the first question and its answer, which the model
    // receives as history, settle that. The search uses only the current
    // question, which is why this one still names the product.
    const questions = [
      "How long does the Acme Widget 2.0 take to charge?",
      "And how many hours does the Acme Widget run for once it is charged?",
    ];
    
    // The server waits for the language model before it replies, and a small
    // model on a modest machine can take a while, so allow plenty of time.
    const timeoutMs = 300_000;
    
    interface Message {
      role: "user" | "assistant";
      content: string;
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
    
    // Sends a question and the conversation so far to the pipeline, and
    // returns the answer. The server keeps no conversation between requests,
    // so history lists the earlier messages, each with a role of user or
    // assistant, in order.
    async function ask(question: string, history: Message[]): Promise<string> {
      const response = await fetch(
        `${baseUrl}/v1/pipelines/${encodeURIComponent(pipeline)}`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ query: question, messages: history }),
          signal: AbortSignal.timeout(timeoutMs),
        },
      );
    
      // fetch only rejects when it cannot reach the server; an error status
      // is a normal response, so check it explicitly.
      if (!response.ok) {
        throw new Error(`HTTP ${response.status}, ${await errorText(response)}`);
      }
    
      const body = (await response.json()) as { answer?: unknown };
      if (typeof body.answer !== "string") {
        throw new Error(`Unexpected response: ${JSON.stringify(body).slice(0, 200)}`);
      }
      return body.answer;
    }
    
    // Asks each question in turn, printing both sides of the conversation.
    // After each answer, the question and the answer join the history that the
    // next request carries.
    async function converse(): Promise<void> {
      const history: Message[] = [];
      for (const question of questions) {
        const answer = await ask(question, history);
        console.log(`You: ${question}`);
        console.log(`Assistant: ${answer}`);
        history.push(
          { role: "user", content: question },
          { role: "assistant", content: answer },
        );
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
        await converse();
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
     * Holding a conversation with the pgEdge RAG Server, using java.net.http
     * and Jackson.
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
    import java.util.List;
    import java.util.concurrent.CompletableFuture;
    import java.util.concurrent.ExecutionException;
    import java.util.concurrent.TimeUnit;
    import java.util.concurrent.TimeoutException;
    
    import tools.jackson.core.JacksonException;
    import tools.jackson.databind.JsonNode;
    import tools.jackson.databind.ObjectMapper;
    import tools.jackson.databind.json.JsonMapper;
    import tools.jackson.databind.node.ArrayNode;
    import tools.jackson.databind.node.ObjectNode;
    
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
    
        // The second question does not say which version of the Acme Widget
        // it means, so only the first question and its answer, which the
        // model receives as history, settle that. The search uses only the
        // current question, which is why this one still names the product.
        static final List<String> QUESTIONS = List.of(
                "How long does the Acme Widget 2.0 take to charge?",
                "And how many hours does the Acme Widget run for once it is charged?");
    
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
         * Sends a question and the conversation so far to the pipeline, and
         * returns the answer. The server keeps no conversation between
         * requests, so history lists the earlier messages, each with a role of
         * user or assistant, in order.
         */
        static String ask(HttpClient client, String question, ArrayNode history)
                throws IOException, InterruptedException, RagException {
            ObjectNode payload = MAPPER.createObjectNode();
            payload.put("query", question);
            payload.set("messages", history);
            HttpRequest request = HttpRequest.newBuilder(pipelineUri(PIPELINE))
                    .timeout(TIMEOUT)
                    .header("Content-Type", "application/json")
                    .POST(HttpRequest.BodyPublishers.ofString(
                            MAPPER.writeValueAsString(payload)))
                    .build();
            HttpResponse<String> response = send(client, request);
    
            // The client treats an error status as a normal response, so check
            // it here.
            if (response.statusCode() != 200) {
                throw new RagException("HTTP " + response.statusCode() + ", "
                        + errorText(response.body()));
            }
    
            try {
                JsonNode answer = MAPPER.readTree(response.body()).path("answer");
                if (answer.isString()) {
                    return answer.stringValue();
                }
            } catch (JacksonException e) {
                // The body is not JSON; report it below.
            }
            throw new RagException(
                    "Unexpected response: " + shorten(response.body()));
        }
    
        /**
         * Asks each question in turn, printing both sides of the conversation.
         * After each answer, the question and the answer join the history that
         * the next request carries.
         */
        static void converse(HttpClient client)
                throws IOException, InterruptedException, RagException {
            ArrayNode history = MAPPER.createArrayNode();
            for (String question : QUESTIONS) {
                String answer = ask(client, question, history);
                System.out.println("You: " + question);
                System.out.println("Assistant: " + answer);
                history.addObject().put("role", "user").put("content", question);
                history.addObject().put("role", "assistant").put("content", answer);
            }
        }
    
        public static void main(String[] args) {
            HttpClient client = HttpClient.newHttpClient();
            try {
                converse(client);
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
     * Holding a conversation with the pgEdge RAG Server, using HttpClient and
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
    
    // The second question does not say which version of the Acme Widget it
    // means, so only the first question and its answer, which the model
    // receives as history, settle that. The search uses only the current
    // question, which is why this one still names the product.
    string[] questions =
    [
        "How long does the Acme Widget 2.0 take to charge?",
        "And how many hours does the Acme Widget run for once it is charged?",
    ];
    
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
    
    // Sends a question and the conversation so far to the pipeline, and
    // returns the answer. The server keeps no conversation between requests,
    // so history lists the earlier messages, each with a role of user or
    // assistant, in order.
    static async Task<string> AskAsync(
        HttpClient client, string question, List<Message> history)
    {
        var url = $"{BaseUrl()}/v1/pipelines/{Uri.EscapeDataString(Pipeline())}";
        using var response = await client.PostAsync(
            url, JsonContent.Create(new { query = question, messages = history }));
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
            // TryGetValue fails when the answer holds a different type, such
            // as a number.
            if (JsonNode.Parse(body)?["answer"] is JsonValue answerNode &&
                answerNode.TryGetValue(out string? answer))
            {
                return answer;
            }
        }
        catch (JsonException)
        {
            // The body is not JSON; report it below.
        }
        throw new RagException($"Unexpected response: {Shorten(body)}");
    }
    
    // Asks each question in turn, printing both sides of the conversation.
    // After each answer, the question and the answer join the history that
    // the next request carries.
    static async Task ConverseAsync(HttpClient client, string[] questions)
    {
        var history = new List<Message>();
        foreach (var question in questions)
        {
            var answer = await AskAsync(client, question, history);
            Console.WriteLine($"You: {question}");
            Console.WriteLine($"Assistant: {answer}");
            history.Add(new Message("user", question));
            history.Add(new Message("assistant", answer));
        }
    }
    
    try
    {
        // using disposes of the client, and closes its connections, when the
        // block exits, whether or not an error occurred.
        using var client = new HttpClient
        {
            Timeout = TimeSpan.FromSeconds(TimeoutSeconds),
        };
        await ConverseAsync(client, questions);
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
    // the types that the program uses are declared here, at the end. A
    // message is one turn of the conversation; JsonContent writes its
    // properties in camel case, as role and content.
    record Message(string Role, string Content);
    
    class RagException(string message) : Exception(message);
    
    ```

=== "Go"

    ```go
    // Ellie's Postgres Cookbook
    // Holding a conversation with the pgEdge RAG Server, using net/http.
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
    
    // The second question does not say which version of the Acme Widget it
    // means, so only the first question and its answer, which the model
    // receives as history, settle that. The search uses only the current
    // question, which is why this one still names the product.
    var questions = []string{
    	"How long does the Acme Widget 2.0 take to charge?",
    	"And how many hours does the Acme Widget run for once it is charged?",
    }
    
    // The server waits for the language model before it replies, and a small
    // model on a modest machine can take a while, so allow plenty of time.
    const timeout = 300 * time.Second
    
    
    // message is one turn of a conversation. The role is "user" or
    // "assistant".
    type message struct {
    	Role    string `json:"role"`
    	Content string `json:"content"`
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
    
    // ask sends a question and the conversation so far to the pipeline, and
    // returns the answer. The server keeps no conversation between requests,
    // so history lists the earlier messages, each with a role of user or
    // assistant, in order.
    func ask(client *http.Client, question string, history []message) (string, error) {
    	payload, err := json.Marshal(map[string]any{
    		"query":    question,
    		"messages": history,
    	})
    	if err != nil {
    		return "", err
    	}
    
    	endpoint := baseURL + "/v1/pipelines/" + url.PathEscape(pipeline)
    	response, err := client.Post(endpoint, "application/json", bytes.NewReader(payload))
    	if err != nil {
    		return "", err
    	}
    	defer response.Body.Close()
    
    	body, err := io.ReadAll(response.Body)
    	if err != nil {
    		return "", err
    	}
    
    	// Go treats an error status as a normal response, so check it here.
    	if response.StatusCode != http.StatusOK {
    		return "", fmt.Errorf("HTTP %d, %s", response.StatusCode, errorText(body))
    	}
    
    	// The answer is a pointer so that the program can tell a missing field
    	// from an empty one.
    	var result struct {
    		Answer *string `json:"answer"`
    	}
    	if err := json.Unmarshal(body, &result); err != nil || result.Answer == nil {
    		return "", fmt.Errorf("unexpected response: %.200s", body)
    	}
    	return *result.Answer, nil
    }
    
    
    // converse asks each question in turn, printing both sides of the
    // conversation. After each answer, the question and the answer join the
    // history that the next request carries.
    func converse(client *http.Client) error {
    	// A non-nil slice encodes as [] rather than null in the first request.
    	history := []message{}
    	for _, question := range questions {
    		answer, err := ask(client, question, history)
    		if err != nil {
    			return err
    		}
    		fmt.Printf("You: %s\n", question)
    		fmt.Printf("Assistant: %s\n", answer)
    		history = append(history,
    			message{Role: "user", Content: question},
    			message{Role: "assistant", Content: answer})
    	}
    	return nil
    }
    
    
    // main reports any error returned by converse() and exits with a non-zero
    // status.
    func main() {
    	client := &http.Client{Timeout: timeout}
    	if err := converse(client); err != nil {
    		fmt.Fprintf(os.Stderr, "RAG Server error: %v\n", err)
    		os.Exit(1)
    	}
    }
    
    
    ```

=== "Rust"

    ```rust
    // Ellie's Postgres Cookbook
    // Holding a conversation with the pgEdge RAG Server, using reqwest and
    // serde_json.
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
    
    /// The second question does not say which version of the Acme Widget it
    /// means, so only the first question and its answer, which the model
    /// receives as history, settle that. The search uses only the current
    /// question, which is why this one still names the product.
    const QUESTIONS: [&str; 2] = [
        "How long does the Acme Widget 2.0 take to charge?",
        "And how many hours does the Acme Widget run for once it is charged?",
    ];
    
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
    
    /// Sends a question and the conversation so far to the pipeline, and
    /// returns the answer. The server keeps no conversation between requests,
    /// so history lists the earlier messages, each with a role of user or
    /// assistant, in order.
    fn ask(client: &Client, question: &str, history: &[Value]) -> Result<String, BoxError> {
        let response = client
            .post(pipeline_url(&pipeline())?)
            .json(&json!({ "query": question, "messages": history }))
            .send()?;
        let status = response.status();
        let body = response.text()?;
    
        // reqwest treats an error status as a normal response, so check it
        // here.
        if !status.is_success() {
            return Err(format!("HTTP {}, {}", status.as_u16(), error_text(&body)).into());
        }
    
        // as_str() gives None when the answer is missing or is not a string.
        let reply: Value = serde_json::from_str(&body).unwrap_or(Value::Null);
        match reply["answer"].as_str() {
            Some(answer) => Ok(answer.to_string()),
            None => Err(format!("Unexpected response: {}", shorten(&body)).into()),
        }
    }
    
    /// Asks each question in turn, printing both sides of the conversation.
    /// After each answer, the question and the answer join the history that
    /// the next request carries.
    fn converse(client: &Client) -> Result<(), BoxError> {
        let mut history: Vec<Value> = Vec::new();
        for question in QUESTIONS {
            let answer = ask(client, question, &history)?;
            println!("You: {question}");
            println!("Assistant: {answer}");
            history.push(json!({ "role": "user", "content": question }));
            history.push(json!({ "role": "assistant", "content": answer }));
        }
        Ok(())
    }
    
    /// Holds the conversation. The ? operator returns any error to the
    /// caller.
    fn run() -> Result<(), BoxError> {
        let client = Client::builder().timeout(TIMEOUT).build()?;
        converse(&client)
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
    # Holding a conversation with the pgEdge RAG Server, using Net::HTTP.
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
    
    # The second question does not say which version of the Acme Widget it
    # means, so only the first question and its answer, which the model
    # receives as history, settle that. The search uses only the current
    # question, which is why this one still names the product.
    QUESTIONS = [
      "How long does the Acme Widget 2.0 take to charge?",
      "And how many hours does the Acme Widget run for once it is charged?"
    ].freeze
    
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
    
    # Sends a question and the conversation so far to the pipeline, and
    # returns the answer. The server keeps no conversation between requests,
    # so history lists the earlier messages, each with a role of user or
    # assistant, in order.
    def ask(http, question, history)
      uri = URI("#{BASE_URL}/v1/pipelines/#{URI.encode_uri_component(PIPELINE)}")
      request = Net::HTTP::Post.new(uri, "Content-Type" => "application/json")
      request.body = JSON.generate({ query: question, messages: history })
      response = http.request(request)
    
      # Net::HTTP treats an error status as a normal response, so check it
      # here.
      unless response.is_a?(Net::HTTPSuccess)
        raise RagError, "HTTP #{response.code}, #{error_text(response)}"
      end
    
      answer = parse_object(response.body)&.fetch("answer", nil)
      unless answer.is_a?(String)
        raise RagError, "Unexpected response: #{response.body.to_s[0, 200]}"
      end
    
      answer
    end
    
    # Asks each question in turn, printing both sides of the conversation.
    # After each answer, the question and the answer join the history that
    # the next request carries.
    def converse(http)
      history = []
      QUESTIONS.each do |question|
        answer = ask(http, question, history)
        puts "You: #{question}"
        puts "Assistant: #{answer}"
        history << { role: "user", content: question }
        history << { role: "assistant", content: answer }
      end
    end
    
    begin
      uri = URI(BASE_URL)
      # start opens a connection, and closes it when the block exits, whether
      # or not an error occurred.
      Net::HTTP.start(
        uri.host, uri.port,
        use_ssl: uri.scheme == "https",
        open_timeout: TIMEOUT_SECONDS, read_timeout: TIMEOUT_SECONDS
      ) { |http| converse(http) }
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
    # Holding a conversation with the pgEdge RAG Server, using curl and jq.
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
    
    # The second question does not say which version of the Acme Widget it
    # means, so only the first question and its answer, which the model
    # receives as history, settle that. The search uses only the current
    # question, which is why this one still names the product.
    QUESTIONS=(
        "How long does the Acme Widget 2.0 take to charge?"
        "And how many hours does the Acme Widget run for once it is charged?"
    )
    
    # The server waits for the language model before it replies, and a small
    # model on a modest machine can take a while, so allow plenty of time.
    TIMEOUT_SECONDS=300
    
    # Escapes a value for use in a URL path, as the other languages do.
    escape() { jq -rn --arg value "$1" '$value | @uri'; }
    
    # Sends a question and the conversation so far to the pipeline, and prints
    # the JSON reply. The server keeps no conversation between requests, so
    # the second argument is a JSON array of the earlier messages, each with a
    # role of user or assistant, in order. With --fail-with-body, curl exits
    # non-zero on an HTTP error status but still prints the body, which
    # carries the server's explanation.
    ask() {
        jq -n --arg query "$1" --argjson messages "$2" \
            '{query: $query, messages: $messages}' |
            curl --silent --show-error --fail-with-body \
                --max-time "$TIMEOUT_SECONDS" \
                --header 'Content-Type: application/json' \
                --data-binary @- \
                "$RAG_SERVER_URL/v1/pipelines/$(escape "$RAG_PIPELINE")"
    }
    
    # Asks each question in turn, printing both sides of the conversation. After
    # each answer, the question and the answer join the history that the next
    # request carries.
    converse() {
        local history='[]' question response answer
    
        for question in "${QUESTIONS[@]}"; do
            if ! response="$(ask "$question" "$history")"; then
                echo "RAG Server error: $response" >&2
                return 1
            fi
    
            # The error call makes jq fail when the answer is missing or is not
            # a string, since interpolating null would print the word "null".
            if ! answer="$(jq -er 'if (.answer | type) == "string"
                                   then .answer
                                   else error("missing answer") end' \
                              <<<"$response")"; then
                echo "Unexpected response: $response" >&2
                return 1
            fi
    
            echo "You: $question"
            echo "Assistant: $answer"
    
            history="$(jq -c --arg question "$question" --arg answer "$answer" \
                '. + [{role: "user", content: $question},
                      {role: "assistant", content: $answer}]' <<<"$history")"
        done
    }
    
    main() {
        converse
    }
    
    main
    
    ```

## Next Steps

The following resources provide more information about the topics in this
recipe:

- The [Asking a Question](ask_question.md) recipe shows a single question
  without a history.
- The [Streaming an Answer](stream_answer.md) recipe shows how to receive an
  answer as the model writes it.
- The
  [pgEdge RAG Server documentation](https://docs.pgedge.com/pgedge-rag-server/)
  describes every endpoint and setting.
- The [Contributing a Recipe](../contributing.md) page explains how to add a
  recipe or a language to the cookbook.
