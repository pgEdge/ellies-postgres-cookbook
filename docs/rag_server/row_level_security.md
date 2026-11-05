# Limiting Answers per User

This recipe asks a pgEdge RAG Server pipeline the same question on behalf of
two different people, and shows that each of them gets an answer built only
from the rows that PostgreSQL row-level security lets that person see. It also
shows that a request with no identity is refused. Each step shows the code in
every supported language; selecting a language tab switches every tab on the
site to that language.

These examples are for pgEdge RAG Server 2.0.0.

The wording of the answers varies from run to run, because a language model
writes them, but the output has the following shape:

```text
Question: What is the status of my warranty claim?

Caller: jane.doe@example.com
Answer:
Your warranty claim has been approved.
Sources: 1, 2

Caller: john.smith@example.com
Answer:
Your warranty claim was declined.
Sources: 3, 4

Caller: (no identity)
IDENTITY_REQUIRED (HTTP 401)
```

## Preparing the Ingredients

The examples assume a running RAG Server that has per-request identity turned
on, and a pipeline named `cookbook_private` that reads a table of fictional
documents, each owned by one of two made-up people. The
`scripts/start_rag_server.sh --identity` command in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook)
creates the table, the policy, and the database role, loads the documents, and
starts the server in Docker. The role has no password, because the test server
uses trust authentication, which accepts any connection without checking one.
Do not copy that into a real deployment: give the role a password, or a client
certificate, store it in your secrets manager, and use a PostgreSQL
authentication method that checks it, such as `scram-sha-256`.

The RAG Server can run each search as the person who asked, so that PostgreSQL
decides which rows the person may read. This depends on four things, and the
first two live in the database. The pipeline connects as a role that is not a
superuser, does not have `BYPASSRLS`, and does not own the table, because any
of those would let the role skip the policy. The table has row-level security
turned on, with a `SELECT` policy that reads the claims that the server passes
in the `request.jwt.claims` setting. The following example shows the policy
that the start script creates, which lets a person read only the rows whose
`owner` matches the `sub` claim:

```sql
ALTER TABLE cookbook_rag_private ENABLE ROW LEVEL SECURITY;

CREATE POLICY own_rows ON cookbook_rag_private FOR SELECT
  USING (owner = current_setting('request.jwt.claims', true)::json
                 ->> 'sub');
```

The third thing is the server configuration. Identity is a server-wide setting,
in a top-level `identity` block of the configuration file, and not a field of a
request, so every query to that server needs an identity once it is on. The
block lists the addresses of the proxies that the server trusts to supply the
identity, and the server checks at start-up that the policy and the role are
set up as described above, and refuses to start if they are not. The following
example shows the block that the start script writes:

```yaml
identity:
  enabled: true
  trusted_proxies:
    - 127.0.0.0/8
    - 10.0.0.0/8
    - 172.16.0.0/12
    - 192.168.0.0/16
```

The fourth thing is the request. A trusted proxy, such as the gateway that
authenticates the people who use your application, adds the claims of the
authenticated person to each request in the `X-Forwarded-Claims` header, as a
JSON object. The `X-Forwarded-User` header can carry a bare subject instead.
The server does not check these headers itself, apart from the address of the
peer that sent them, so a proxy that you control must remove any such header
that arrives from outside and set its own; if clients can reach the server
directly, any of them can claim to be anyone. The programs in this recipe play
the part of the proxy, to show the effect. Run the server on a private
interface that only the proxy can reach, and not on a public one, because any
host that can connect to it from a trusted address can claim any identity. The
demonstration value of `trusted_proxies` above covers every private address
range (RFC 1918) so that it works in Docker; in a real deployment, list only
the address of your proxy.

Because the identity is server-wide, this recipe needs its own server, apart
from the one that the other RAG Server recipes use. Set `RAG_SERVER_URL` to the
address of the server that has identity turned on. The following table lists
the HTTP client that each example uses:

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
      "name": "row-level-security",
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
    import java.util.ArrayList;
    import java.util.List;
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
variable names the pipeline. The program also holds the question, the two
made-up callers, and the name of the header, and allows 300 seconds for each
reply, because a small model on a modest machine can take a while to write an
answer. The following table describes the environment variables:

| Variable         | Default                 | Description                      |
|------------------|-------------------------|----------------------------------|
| `RAG_SERVER_URL` | `http://localhost:8080` | The base URL of the RAG Server.  |
| `RAG_PIPELINE`   | `cookbook_private` | The name of the pipeline to ask. |

The following tabs show how each program reads its settings:

=== "Python"

    ```python
    # The or operator treats an empty variable as unset.
    BASE_URL = (os.environ.get("RAG_SERVER_URL") or "http://localhost:8080").rstrip("/")
    PIPELINE = os.environ.get("RAG_PIPELINE") or "cookbook_private"
    
    QUESTION = "What is the status of my warranty claim?"
    
    # The callers to ask for. The fictional documents in the pipeline's table
    # belong to these two people.
    CALLERS = ["jane.doe@example.com", "john.smith@example.com"]
    
    # The header in which the server expects a trusted proxy to put the claims
    # of the caller. This is the server's default; the identity.claims_header
    # setting changes it.
    CLAIMS_HEADER = "X-Forwarded-Claims"
    
    # The server waits for the language model before it replies, and a small
    # model on a modest machine can take a while, so allow plenty of time.
    TIMEOUT_SECONDS = 300.0
    ```

=== "TypeScript"

    ```typescript
    // The || operator, unlike ??, also treats an empty variable as unset.
    const baseUrl = (process.env.RAG_SERVER_URL || "http://localhost:8080").replace(/\/+$/, "");
    const pipeline = process.env.RAG_PIPELINE || "cookbook_private";
    
    const question = "What is the status of my warranty claim?";
    
    // The callers to ask for. The fictional documents in the pipeline's table
    // belong to these two people.
    const callers = ["jane.doe@example.com", "john.smith@example.com"];
    
    // The header in which the server expects a trusted proxy to put the claims
    // of the caller. This is the server's default; the identity.claims_header
    // setting changes it.
    const claimsHeader = "X-Forwarded-Claims";
    
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
    static final String PIPELINE = envOr("RAG_PIPELINE", "cookbook_private");
    
    static final String QUESTION = "What is the status of my warranty claim?";
    
    // The callers to ask for. The fictional documents in the pipeline's
    // table belong to these two people.
    static final List<String> CALLERS =
            List.of("jane.doe@example.com", "john.smith@example.com");
    
    // The header in which the server expects a trusted proxy to put the
    // claims of the caller. This is the server's default; the
    // identity.claims_header setting changes it.
    static final String CLAIMS_HEADER = "X-Forwarded-Claims";
    
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
    static string Pipeline() => EnvOr("RAG_PIPELINE", "cookbook_private");
    
    const string Question = "What is the status of my warranty claim?";
    
    // The callers to ask for. The fictional documents in the pipeline's table
    // belong to these two people.
    string[] callers = ["jane.doe@example.com", "john.smith@example.com"];
    
    // The header in which the server expects a trusted proxy to put the claims
    // of the caller. This is the server's default; the identity.claims_header
    // setting changes it.
    const string ClaimsHeader = "X-Forwarded-Claims";
    
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
    	pipeline = envOr("RAG_PIPELINE", "cookbook_private")
    )
    
    const question = "What is the status of my warranty claim?"
    
    // The callers to ask for. The fictional documents in the pipeline's table
    // belong to these two people.
    var callers = []string{"jane.doe@example.com", "john.smith@example.com"}
    
    // The header in which the server expects a trusted proxy to put the claims
    // of the caller. This is the server's default; the identity.claims_header
    // setting changes it.
    const claimsHeader = "X-Forwarded-Claims"
    
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
        env_or("RAG_PIPELINE", "cookbook_private")
    }
    
    const QUESTION: &str = "What is the status of my warranty claim?";
    
    /// The callers to ask for. The fictional documents in the pipeline's table
    /// belong to these two people.
    const CALLERS: [&str; 2] = ["jane.doe@example.com", "john.smith@example.com"];
    
    /// The header in which the server expects a trusted proxy to put the
    /// claims of the caller. This is the server's default; the
    /// identity.claims_header setting changes it.
    const CLAIMS_HEADER: &str = "X-Forwarded-Claims";
    
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
    PIPELINE = env_or("RAG_PIPELINE", "cookbook_private")
    
    QUESTION = "What is the status of my warranty claim?"
    
    # The callers to ask for. The fictional documents in the pipeline's table
    # belong to these two people.
    CALLERS = ["jane.doe@example.com", "john.smith@example.com"].freeze
    
    # The header in which the server expects a trusted proxy to put the claims
    # of the caller. This is the server's default; the identity.claims_header
    # setting changes it.
    CLAIMS_HEADER = "X-Forwarded-Claims"
    
    # The server waits for the language model before it replies, and a small
    # model on a modest machine can take a while, so allow plenty of time.
    TIMEOUT_SECONDS = 300
    ```

=== "curl"

    ```bash
    # The :- operator treats an empty variable as unset.
    RAG_SERVER_URL="${RAG_SERVER_URL:-http://localhost:8080}"
    RAG_SERVER_URL="${RAG_SERVER_URL%/}"
    RAG_PIPELINE="${RAG_PIPELINE:-cookbook_private}"
    
    QUESTION="What is the status of my warranty claim?"
    
    # The callers to ask for. The fictional documents in the pipeline's table
    # belong to these two people.
    CALLERS=("jane.doe@example.com" "john.smith@example.com")
    
    # The header in which the server expects a trusted proxy to put the claims
    # of the caller. This is the server's default; the identity.claims_header
    # setting changes it.
    CLAIMS_HEADER="X-Forwarded-Claims"
    
    # The server waits for the language model before it replies, and a small
    # model on a modest machine can take a while, so allow plenty of time.
    TIMEOUT_SECONDS=300
    
    # Escapes a value for use in a URL path, as the other languages do.
    escape() { jq -rn --arg value "$1" '$value | @uri'; }
    ```

## Asking on Behalf of a Caller

Each program sends the question in a `POST` request with `include_sources` set
to true, and adds the claims header when it has a caller. It builds the claims
as a JSON object with its own JSON encoder, and never joins strings, so that an
unusual subject cannot break the header. The RAG Server reports a failure with
an HTTP error status and a JSON body that holds an error code and a message,
and the programs keep the status, the code, and the message. The following tabs
show how each program asks:

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
    
    
    def ask(client: httpx.Client, subject: str | None) -> dict:
        """Sends the question to the pipeline on behalf of a caller, and asks
        for the documents that the answer came from. Returns the decoded reply.
        A subject of None sends no identity at all."""
        # The claims are a JSON object, which json.dumps builds, so that the
        # subject needs no escaping.
        headers = {}
        if subject is not None:
            headers[CLAIMS_HEADER] = json.dumps({"sub": subject})
    
        response = client.post(
            f"/v1/pipelines/{quote(PIPELINE, safe='')}",
            json={"query": QUESTION, "include_sources": True},
            headers=headers,
        )
        if response.is_error:
            try:
                error = response.json()["error"]
                raise ApiError(response.status_code, error["code"], error["message"])
            except (ValueError, KeyError, TypeError):
                raise RagError(
                    f"HTTP {response.status_code}, {response.text[:200]}"
                ) from None
    
        try:
            body = response.json()
            if isinstance(body["answer"], str):
                return body
        except (ValueError, KeyError, TypeError):
            pass
        raise RagError(f"Unexpected response: {response.text[:200]}")
    ```

=== "TypeScript"

    ```typescript
    interface Source {
      id?: string;
    }
    
    interface QueryResponse {
      answer: string;
      sources?: Source[];
    }
    
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
    
    // Sends the question to the pipeline on behalf of a caller, and asks for
    // the documents that the answer came from. Returns the decoded reply. A
    // subject of undefined sends no identity at all.
    async function ask(subject?: string): Promise<QueryResponse> {
      // The claims are a JSON object, which JSON.stringify builds, so that the
      // subject needs no escaping.
      const headers: Record<string, string> = { "Content-Type": "application/json" };
      if (subject !== undefined) {
        headers[claimsHeader] = JSON.stringify({ sub: subject });
      }
    
      const response = await fetch(
        `${baseUrl}/v1/pipelines/${encodeURIComponent(pipeline)}`,
        {
          method: "POST",
          headers,
          body: JSON.stringify({ query: question, include_sources: true }),
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
    
      const body = (await response.json()) as Partial<QueryResponse>;
      if (typeof body.answer !== "string") {
        throw new Error(`Unexpected response: ${JSON.stringify(body).slice(0, 200)}`);
      }
      return body as QueryResponse;
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
    
        ApiException(int status, String code, String message) {
            super(code + ": " + message);
            this.status = status;
            this.code = code;
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
     * Sends the question to the pipeline on behalf of a caller, and asks
     * for the documents that the answer came from. Returns the decoded
     * reply. A subject of null sends no identity at all.
     */
    static JsonNode ask(HttpClient client, String subject)
            throws IOException, InterruptedException, RagException, ApiException {
        String payload = MAPPER.writeValueAsString(MAPPER.createObjectNode()
                .put("query", QUESTION)
                .put("include_sources", true));
        HttpRequest.Builder builder = HttpRequest.newBuilder(pipelineUri(PIPELINE))
                .timeout(TIMEOUT)
                .header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString(payload));
        // The claims are a JSON object, which Jackson builds, so that the
        // subject needs no escaping.
        if (subject != null) {
            builder.header(CLAIMS_HEADER, MAPPER.writeValueAsString(
                    MAPPER.createObjectNode().put("sub", subject)));
        }
        HttpResponse<String> response = send(client, builder.build());
    
        JsonNode body = null;
        try {
            body = MAPPER.readTree(response.body());
        } catch (JacksonException e) {
            // The body is not JSON; report it below.
        }
    
        if (response.statusCode() >= 400) {
            JsonNode error = body == null ? null : body.path("error");
            if (error == null || !error.path("code").isString()
                    || !error.path("message").isString()) {
                throw new RagException("HTTP " + response.statusCode() + ", "
                        + shorten(response.body()));
            }
            throw new ApiException(response.statusCode(),
                    error.path("code").stringValue(),
                    error.path("message").stringValue());
        }
    
        if (body == null || !body.path("answer").isString()) {
            throw new RagException(
                    "Unexpected response: " + shorten(response.body()));
        }
        return body;
    }
    ```

=== "C#"

    ```csharp
    // Returns at most the first 200 characters of a reply.
    static string Shorten(string text) =>
        text.Length > 200 ? text[..200] : text;
    
    // Sends the question to the pipeline on behalf of a caller, and asks for
    // the documents that the answer came from. Returns the decoded reply. A
    // subject of null sends no identity at all.
    static async Task<JsonNode> AskAsync(HttpClient client, string? subject)
    {
        var url = $"{BaseUrl()}/v1/pipelines/{Uri.EscapeDataString(Pipeline())}";
        using var request = new HttpRequestMessage(HttpMethod.Post, url)
        {
            Content = JsonContent.Create(new { query = Question, include_sources = true }),
        };
        // The claims are a JSON object, which JsonSerializer builds, so that
        // the subject needs no escaping.
        if (subject is not null)
        {
            request.Headers.Add(ClaimsHeader, JsonSerializer.Serialize(new { sub = subject }));
        }
        using var response = await client.SendAsync(request);
        var body = await response.Content.ReadAsStringAsync();
        var status = (int)response.StatusCode;
    
        JsonNode? reply = null;
        try
        {
            reply = JsonNode.Parse(body);
        }
        catch (JsonException)
        {
            // The body is not JSON; report it below.
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
    
        if (reply?["answer"] is JsonValue answerNode &&
            answerNode.TryGetValue(out string? _))
        {
            return reply;
        }
        throw new RagException($"Unexpected response: {Shorten(body)}");
    }
    ```

=== "Go"

    ```go
    // source is a document that the answer came from.
    type source struct {
    	ID string `json:"id"`
    }
    
    // queryResponse holds the fields of the reply that the program uses. The
    // answer is a pointer so that the program can tell a missing field from
    // an empty one.
    type queryResponse struct {
    	Answer  *string  `json:"answer"`
    	Sources []source `json:"sources"`
    }
    
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
    
    // ask sends the question to the pipeline on behalf of a caller, and asks
    // for the documents that the answer came from. It returns the decoded
    // reply. An empty subject sends no identity at all.
    func ask(client *http.Client, subject string) (*queryResponse, error) {
    	payload, err := json.Marshal(map[string]any{
    		"query":           question,
    		"include_sources": true,
    	})
    	if err != nil {
    		return nil, err
    	}
    
    	endpoint := baseURL + "/v1/pipelines/" + url.PathEscape(pipeline)
    	request, err := http.NewRequest(http.MethodPost, endpoint, bytes.NewReader(payload))
    	if err != nil {
    		return nil, err
    	}
    	request.Header.Set("Content-Type", "application/json")
    	if subject != "" {
    		// The claims are a JSON object, which json.Marshal builds, so that
    		// the subject needs no escaping.
    		claims, err := json.Marshal(map[string]string{"sub": subject})
    		if err != nil {
    			return nil, err
    		}
    		request.Header.Set(claimsHeader, string(claims))
    	}
    
    	response, err := client.Do(request)
    	if err != nil {
    		return nil, err
    	}
    	defer response.Body.Close()
    
    	body, err := io.ReadAll(response.Body)
    	if err != nil {
    		return nil, err
    	}
    
    	// Go treats an error status as a normal response, so check it here.
    	if response.StatusCode != http.StatusOK {
    		var e struct {
    			Error struct {
    				Code    string `json:"code"`
    				Message string `json:"message"`
    			} `json:"error"`
    		}
    		if json.Unmarshal(body, &e) != nil || e.Error.Code == "" {
    			return nil, fmt.Errorf("HTTP %d, %.200s", response.StatusCode, strings.TrimSpace(string(body)))
    		}
    		return nil, &apiError{response.StatusCode, e.Error.Code, e.Error.Message}
    	}
    
    	var result queryResponse
    	if err := json.Unmarshal(body, &result); err != nil || result.Answer == nil {
    		return nil, fmt.Errorf("unexpected response: %.200s", body)
    	}
    	return &result, nil
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
    
    /// Sends the question to the pipeline on behalf of a caller, and asks for
    /// the documents that the answer came from. Returns the decoded reply, or
    /// an ApiError, which the caller can recover with downcast_ref(), when the
    /// server replies with an error. A subject of None sends no identity at
    /// all.
    fn ask(client: &Client, subject: Option<&str>) -> Result<Value, BoxError> {
        let mut request = client
            .post(pipeline_url(&pipeline())?)
            .json(&json!({ "query": QUESTION, "include_sources": true }));
        // The claims are a JSON object, which json! builds, so that the subject
        // needs no escaping.
        if let Some(subject) = subject {
            request = request.header(CLAIMS_HEADER, json!({ "sub": subject }).to_string());
        }
        let response = request.send()?;
        let status = response.status();
        let body = response.text()?;
    
        // A body that is not JSON becomes Null, and indexing Null (or any
        // missing field) gives Null again, which as_str() turns into None.
        let reply: Value = serde_json::from_str(&body).unwrap_or(Value::Null);
    
        if !status.is_success() {
            let error = &reply["error"];
            return match (error["code"].as_str(), error["message"].as_str()) {
                (Some(code), Some(message)) => Err(Box::new(ApiError {
                    status: status.as_u16(),
                    code: code.to_string(),
                    message: message.to_string(),
                })),
                _ => Err(format!("HTTP {}, {}", status.as_u16(), shorten(&body)).into()),
            };
        }
    
        if !reply["answer"].is_string() {
            return Err(format!("Unexpected response: {}", shorten(&body)).into());
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
      attr_reader :status, :code
    
      def initialize(status, code, detail)
        super("#{code}: #{detail}")
        @status = status
        @code = code
      end
    end
    
    # Parses text as a JSON object, and returns nil if it is not one.
    def parse_object(text)
      value = JSON.parse(text.to_s)
      value.is_a?(Hash) ? value : nil
    rescue JSON::ParserError
      nil
    end
    
    # Sends the question to the pipeline on behalf of a caller, and asks for
    # the documents that the answer came from. Returns the decoded reply. A
    # subject of nil sends no identity at all.
    def ask(http, subject)
      uri = URI("#{BASE_URL}/v1/pipelines/#{URI.encode_uri_component(PIPELINE)}")
      request = Net::HTTP::Post.new(uri, "Content-Type" => "application/json")
      # The claims are a JSON object, which JSON.generate builds, so that the
      # subject needs no escaping.
      request[CLAIMS_HEADER] = JSON.generate({ sub: subject }) unless subject.nil?
      request.body = JSON.generate({ query: QUESTION, include_sources: true })
      response = http.request(request)
      body = parse_object(response.body)
    
      unless response.is_a?(Net::HTTPSuccess)
        error = body&.fetch("error", nil)
        unless error.is_a?(Hash) && error["code"].is_a?(String) && error["message"].is_a?(String)
          raise RagError, "HTTP #{response.code}, #{response.body.to_s[0, 200]}"
        end
    
        raise ApiError.new(response.code.to_i, error["code"], error["message"])
      end
    
      unless body && body["answer"].is_a?(String)
        raise RagError, "Unexpected response: #{response.body.to_s[0, 200]}"
      end
    
      body
    end
    ```

=== "curl"

    ```bash
    # Sends the question to the pipeline on behalf of a caller, and asks for
    # the documents that the answer came from. The argument is the caller's
    # subject, or an empty string to send no identity. The function sets
    # STATUS to the HTTP status and BODY to the reply, and returns 1 when the
    # status is an error. The claims are a JSON object, which jq builds, so
    # that the subject needs no escaping. With --fail-with-body, curl exits
    # non-zero on an HTTP error status but still prints the body; --write-out
    # adds the HTTP status after it. The script leaves out --show-error,
    # because it reports each failure itself.
    STATUS="" BODY=""
    ask() {
        local subject="$1" output rc=0 headers=()
        if [[ -n "$subject" ]]; then
            headers=(--header "$CLAIMS_HEADER: $(jq -cn --arg sub "$subject" '{sub: $sub}')")
        fi
    
        output="$(jq -n --arg query "$QUESTION" '{query: $query, include_sources: true}' |
            curl --silent --fail-with-body \
                --max-time "$TIMEOUT_SECONDS" \
                --header 'Content-Type: application/json' \
                ${headers[@]+"${headers[@]}"} \
                --data-binary @- \
                --write-out '\n%{http_code}' \
                "$RAG_SERVER_URL/v1/pipelines/$(escape "$RAG_PIPELINE")")" || rc=$?
    
        STATUS="${output##*$'\n'}"
        BODY="${output%$'\n'*}"
        if [[ "$STATUS" == 000 ]]; then
            echo "RAG Server error: could not reach $RAG_SERVER_URL" >&2
            exit 1
        fi
        return "$rc"
    }
    ```

## Showing the Answer

Each program prints the answer, and then the IDs of the sources. The sources
show the effect of the policy: the first caller gets only documents 1 and 2,
and the second only documents 3 and 4. The following tabs show how each program
prints a reply:

=== "Python"

    ```python
    def show(body: dict) -> None:
        """Prints the answer in a reply, and then the IDs of its sources."""
        ids = [str(source.get("id", "(no id)")) for source in body.get("sources") or []]
        print(f"Answer:\n{body['answer']}")
        print(f"Sources: {', '.join(ids)}")
    ```

=== "TypeScript"

    ```typescript
    // Prints the answer in a reply, and then the IDs of its sources.
    function show(body: QueryResponse): void {
      const ids = (body.sources ?? []).map((source) => source.id ?? "(no id)");
      console.log(`Answer:\n${body.answer}`);
      console.log(`Sources: ${ids.join(", ")}`);
    }
    ```

=== "Java"

    ```java
    /** Prints the answer in a reply, and then the IDs of its sources. */
    static void show(JsonNode body) {
        // path() gives a missing node, which holds no elements, when the
        // reply has no sources.
        List<String> ids = new ArrayList<>();
        for (JsonNode source : body.path("sources")) {
            ids.add(source.has("id") ? source.get("id").asString() : "(no id)");
        }
        System.out.println("Answer:\n" + body.path("answer").stringValue());
        System.out.println("Sources: " + String.join(", ", ids));
    }
    ```

=== "C#"

    ```csharp
    // Prints the answer in a reply, and then the IDs of its sources.
    static void Show(JsonNode reply)
    {
        var ids = new List<string>();
        if (reply["sources"] is JsonArray sources)
        {
            foreach (var source in sources)
            {
                ids.Add(source?["id"]?.ToString() ?? "(no id)");
            }
        }
        Console.WriteLine($"Answer:\n{reply["answer"]}");
        Console.WriteLine($"Sources: {string.Join(", ", ids)}");
    }
    ```

=== "Go"

    ```go
    // show prints the answer in a reply, and then the IDs of its sources.
    func show(result *queryResponse) {
    	ids := make([]string, 0, len(result.Sources))
    	for _, s := range result.Sources {
    		ids = append(ids, s.ID)
    	}
    	fmt.Printf("Answer:\n%s\n", *result.Answer)
    	fmt.Printf("Sources: %s\n", strings.Join(ids, ", "))
    }
    
    ```

=== "Rust"

    ```rust
    /// Prints the answer in a reply, and then the IDs of its sources.
    fn show(reply: &Value) {
        // as_array() gives None when the reply has no sources.
        let ids: Vec<&str> = reply["sources"]
            .as_array()
            .map(|sources| {
                sources
                    .iter()
                    .map(|source| source["id"].as_str().unwrap_or("(no id)"))
                    .collect()
            })
            .unwrap_or_default();
        println!("Answer:\n{}", reply["answer"].as_str().unwrap_or(""));
        println!("Sources: {}", ids.join(", "));
    }
    ```

=== "Ruby"

    ```ruby
    # Prints the answer in a reply, and then the IDs of its sources.
    def show(body)
      ids = (body["sources"] || []).map { |source| source.fetch("id", "(no id)").to_s }
      puts "Answer:\n#{body["answer"]}"
      puts "Sources: #{ids.join(", ")}"
    end
    ```

=== "curl"

    ```bash
    # Prints the answer in the reply, and then the IDs of its sources. The
    # error call makes jq fail when the answer is missing or is not a string,
    # since interpolating null would print the word "null".
    show() {
        jq -er 'if (.answer | type) == "string"
                then "Answer:\n\(.answer)"
                else error("missing answer") end,
                "Sources: \((.sources // []) | map(.id // "(no id)") | join(", "))"'
    }
    ```

## Handling Errors

The main part of each program asks the question as each caller, and then asks
without an identity, which the server must refuse with the `IDENTITY_REQUIRED`
code and HTTP status 401. The server never falls back to the database role of
the pipeline, which could read every row. The program fails if the server
answers, or refuses for another reason. It reports any other failure on
`stderr`, and exits with a non-zero status. The following tabs show the main
part of each program:

=== "Python"

    ```python
    def ask_anonymously(client: httpx.Client) -> None:
        """Asks the question without an identity. The server must refuse with
        IDENTITY_REQUIRED, because it never falls back to the pipeline's own
        database role; any other outcome is a failure."""
        print()
        print("Caller: (no identity)")
        try:
            ask(client, None)
        except ApiError as e:
            print(f"{e.code} (HTTP {e.status})")
            if e.code != "IDENTITY_REQUIRED":
                raise RagError(f"expected IDENTITY_REQUIRED, got {e}") from None
            return
        raise RagError("the server answered without an identity; "
                       "is identity.enabled set?")
    
    
    def main() -> int:
        try:
            with httpx.Client(base_url=BASE_URL, timeout=TIMEOUT_SECONDS) as client:
                print(f"Question: {QUESTION}")
                for caller in CALLERS:
                    body = ask(client, caller)
                    print()
                    print(f"Caller: {caller}")
                    show(body)
                ask_anonymously(client)
        # httpx.HTTPError is the base class for failures to reach the server,
        # such as a refused connection or a timeout.
        except (httpx.HTTPError, ApiError, RagError) as e:
            print(f"RAG Server error: {e}", file=sys.stderr)
            return 1
    
        return 0
    
    
    if __name__ == "__main__":
        sys.exit(main())
    ```

=== "TypeScript"

    ```typescript
    // Asks the question without an identity. The server must refuse with
    // IDENTITY_REQUIRED, because it never falls back to the pipeline's own
    // database role; any other outcome is a failure.
    async function askAnonymously(): Promise<void> {
      console.log();
      console.log("Caller: (no identity)");
      try {
        await ask();
      } catch (err) {
        if (!(err instanceof ApiError)) {
          throw err;
        }
        console.log(`${err.code} (HTTP ${err.status})`);
        if (err.code !== "IDENTITY_REQUIRED") {
          throw new Error(`expected IDENTITY_REQUIRED, got ${err.code}: ${err.message}`);
        }
        return;
      }
      throw new Error("the server answered without an identity; is identity.enabled set?");
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
        console.log(`Question: ${question}`);
        for (const caller of callers) {
          const body = await ask(caller);
          console.log();
          console.log(`Caller: ${caller}`);
          show(body);
        }
        await askAnonymously();
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
     * Asks the question without an identity. The server must refuse with
     * IDENTITY_REQUIRED, because it never falls back to the pipeline's own
     * database role; any other outcome is a failure.
     */
    static void askAnonymously(HttpClient client)
            throws IOException, InterruptedException, RagException {
        System.out.println();
        System.out.println("Caller: (no identity)");
        try {
            ask(client, null);
        } catch (ApiException e) {
            System.out.println(e.code + " (HTTP " + e.status + ")");
            if (!e.code.equals("IDENTITY_REQUIRED")) {
                throw new RagException(
                        "expected IDENTITY_REQUIRED, got " + e.getMessage());
            }
            return;
        }
        throw new RagException("the server answered without an identity; "
                + "is identity.enabled set?");
    }
    
    public static void main(String[] args) {
        HttpClient client = HttpClient.newHttpClient();
        try {
            System.out.println("Question: " + QUESTION);
            for (String caller : CALLERS) {
                JsonNode body = ask(client, caller);
                System.out.println();
                System.out.println("Caller: " + caller);
                show(body);
            }
            askAnonymously(client);
        // IOException covers failures to reach the server, such as a
        // refused connection or a timeout. The message of a refused
        // connection can be empty, so print the exception itself, which
        // includes its type.
        } catch (IOException | InterruptedException e) {
            System.err.println("RAG Server error: " + e);
            System.exit(1);
        } catch (ApiException | RagException e) {
            System.err.println("RAG Server error: " + e.getMessage());
            System.exit(1);
        }
    }
    ```

=== "C#"

    ```csharp
    // Asks the question without an identity. The server must refuse with
    // IDENTITY_REQUIRED, because it never falls back to the pipeline's own
    // database role; any other outcome is a failure.
    static async Task AskAnonymouslyAsync(HttpClient client)
    {
        Console.WriteLine();
        Console.WriteLine("Caller: (no identity)");
        try
        {
            await AskAsync(client, null);
        }
        catch (ApiException e)
        {
            Console.WriteLine($"{e.Code} (HTTP {e.Status})");
            if (e.Code != "IDENTITY_REQUIRED")
            {
                throw new RagException($"expected IDENTITY_REQUIRED, got {e.Message}");
            }
            return;
        }
        throw new RagException(
            "the server answered without an identity; is identity.enabled set?");
    }
    
    try
    {
        // using disposes of the client, and closes its connections, when the
        // block exits, whether or not an error occurred.
        using var client = new HttpClient
        {
            Timeout = TimeSpan.FromSeconds(TimeoutSeconds),
        };
        Console.WriteLine($"Question: {Question}");
        foreach (var caller in callers)
        {
            var reply = await AskAsync(client, caller);
            Console.WriteLine();
            Console.WriteLine($"Caller: {caller}");
            Show(reply);
        }
        await AskAnonymouslyAsync(client);
    }
    // HttpRequestException covers failures to reach the server, such as a
    // refused connection, and TaskCanceledException covers a timeout.
    catch (Exception e) when (e is HttpRequestException or TaskCanceledException
        or ApiException or RagException)
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
    }
    ```

=== "Go"

    ```go
    // askAnonymously asks the question without an identity. The server must
    // refuse with IDENTITY_REQUIRED, because it never falls back to the
    // pipeline's own database role; any other outcome is a failure.
    func askAnonymously(client *http.Client) error {
    	fmt.Println()
    	fmt.Println("Caller: (no identity)")
    
    	_, err := ask(client, "")
    	var apiErr *apiError
    	if !errors.As(err, &apiErr) {
    		if err == nil {
    			return errors.New("the server answered without an identity; is identity.enabled set?")
    		}
    		return err
    	}
    
    	fmt.Printf("%s (HTTP %d)\n", apiErr.Code, apiErr.Status)
    	if apiErr.Code != "IDENTITY_REQUIRED" {
    		return fmt.Errorf("expected IDENTITY_REQUIRED, got %v", apiErr)
    	}
    	return nil
    }
    
    // run asks the question as each caller, and then without an identity,
    // returning any error to the caller.
    func run() error {
    	client := &http.Client{Timeout: timeout}
    
    	fmt.Printf("Question: %s\n", question)
    	for _, caller := range callers {
    		result, err := ask(client, caller)
    		if err != nil {
    			return err
    		}
    		fmt.Println()
    		fmt.Printf("Caller: %s\n", caller)
    		show(result)
    	}
    	return askAnonymously(client)
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
    /// Asks the question without an identity. The server must refuse with
    /// IDENTITY_REQUIRED, because it never falls back to the pipeline's own
    /// database role; any other outcome is a failure.
    fn ask_anonymously(client: &Client) -> Result<(), BoxError> {
        println!();
        println!("Caller: (no identity)");
        let e = match ask(client, None) {
            Ok(_) => {
                return Err("the server answered without an identity; is identity.enabled set?".into())
            }
            Err(e) => e,
        };
        // Any error other than an ApiError, such as a refused connection, is
        // returned as it is.
        let Some(api) = e.downcast_ref::<ApiError>() else {
            return Err(e);
        };
        println!("{} (HTTP {})", api.code, api.status);
        if api.code != "IDENTITY_REQUIRED" {
            return Err(format!("expected IDENTITY_REQUIRED, got {api}").into());
        }
        Ok(())
    }
    
    /// Asks the question for each caller, and then without an identity. The ?
    /// operator returns any error to the caller.
    fn run() -> Result<(), BoxError> {
        let client = Client::builder().timeout(TIMEOUT).build()?;
        println!("Question: {QUESTION}");
        for caller in CALLERS {
            let reply = ask(&client, Some(caller))?;
            println!();
            println!("Caller: {caller}");
            show(&reply);
        }
        ask_anonymously(&client)
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
    # Asks the question without an identity. The server must refuse with
    # IDENTITY_REQUIRED, because it never falls back to the pipeline's own
    # database role; any other outcome is a failure.
    def ask_anonymously(http)
      puts
      puts "Caller: (no identity)"
      begin
        ask(http, nil)
      rescue ApiError => e
        puts "#{e.code} (HTTP #{e.status})"
        raise RagError, "expected IDENTITY_REQUIRED, got #{e.message}" if e.code != "IDENTITY_REQUIRED"
    
        return
      end
      raise RagError, "the server answered without an identity; is identity.enabled set?"
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
        puts "Question: #{QUESTION}"
        CALLERS.each do |caller|
          body = ask(http, caller)
          puts
          puts "Caller: #{caller}"
          show(body)
        end
        ask_anonymously(http)
      end
    # SystemCallError covers a refused connection, Timeout::Error covers the
    # connection and read timeouts, and SocketError covers an unknown host.
    rescue ApiError, RagError, SystemCallError, Timeout::Error, SocketError, IOError => e
      warn "RAG Server error: #{e.message}"
      exit 1
    end
    ```

=== "curl"

    ```bash
    # Asks the question as a caller who has an identity, and prints what that
    # caller may see.
    ask_as() {
        echo
        echo "Caller: $1"
        if ! ask "$1"; then
            echo "RAG Server error: HTTP $STATUS, ${BODY:0:200}" >&2
            return 1
        fi
        show <<<"$BODY" || {
            echo "Unexpected response: ${BODY:0:200}" >&2
            return 1
        }
    }
    
    # Asks the question without an identity. The server must refuse with
    # IDENTITY_REQUIRED, because it never falls back to the pipeline's own
    # database role; any other outcome is a failure.
    ask_anonymously() {
        local code
    
        echo
        echo "Caller: (no identity)"
        if ask ""; then
            echo "RAG Server error: the server answered without an identity;" \
                 "is identity.enabled set?" >&2
            return 1
        fi
        code="$(jq -r '.error.code // empty' <<<"$BODY" 2>/dev/null || true)"
        echo "$code (HTTP $STATUS)"
        if [[ "$code" != IDENTITY_REQUIRED ]]; then
            echo "RAG Server error: expected IDENTITY_REQUIRED, got HTTP $STATUS:" \
                 "${BODY:0:200}" >&2
            return 1
        fi
    }
    
    main() {
        local caller
    
        echo "Question: $QUESTION"
        for caller in "${CALLERS[@]}"; do
            ask_as "$caller"
        done
        ask_anonymously
    }
    
    main
    ```

## Running the Example

The complete project for each language is available in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/rag_server/row_level_security).
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
    Limiting the answers of the pgEdge RAG Server to each caller's own rows,
    using httpx.
    
    These examples are for pgEdge RAG Server 2.0.0.
    
    Copyright (c) 2026, pgEdge, Inc.
    This code is released under the PostgreSQL License.
    """
    
    import json
    import os
    import sys
    from urllib.parse import quote
    
    import httpx
    
    
    # The or operator treats an empty variable as unset.
    BASE_URL = (os.environ.get("RAG_SERVER_URL") or "http://localhost:8080").rstrip("/")
    PIPELINE = os.environ.get("RAG_PIPELINE") or "cookbook_private"
    
    QUESTION = "What is the status of my warranty claim?"
    
    # The callers to ask for. The fictional documents in the pipeline's table
    # belong to these two people.
    CALLERS = ["jane.doe@example.com", "john.smith@example.com"]
    
    # The header in which the server expects a trusted proxy to put the claims
    # of the caller. This is the server's default; the identity.claims_header
    # setting changes it.
    CLAIMS_HEADER = "X-Forwarded-Claims"
    
    # The server waits for the language model before it replies, and a small
    # model on a modest machine can take a while, so allow plenty of time.
    TIMEOUT_SECONDS = 300.0
    
    
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
    
    
    def ask(client: httpx.Client, subject: str | None) -> dict:
        """Sends the question to the pipeline on behalf of a caller, and asks
        for the documents that the answer came from. Returns the decoded reply.
        A subject of None sends no identity at all."""
        # The claims are a JSON object, which json.dumps builds, so that the
        # subject needs no escaping.
        headers = {}
        if subject is not None:
            headers[CLAIMS_HEADER] = json.dumps({"sub": subject})
    
        response = client.post(
            f"/v1/pipelines/{quote(PIPELINE, safe='')}",
            json={"query": QUESTION, "include_sources": True},
            headers=headers,
        )
        if response.is_error:
            try:
                error = response.json()["error"]
                raise ApiError(response.status_code, error["code"], error["message"])
            except (ValueError, KeyError, TypeError):
                raise RagError(
                    f"HTTP {response.status_code}, {response.text[:200]}"
                ) from None
    
        try:
            body = response.json()
            if isinstance(body["answer"], str):
                return body
        except (ValueError, KeyError, TypeError):
            pass
        raise RagError(f"Unexpected response: {response.text[:200]}")
    
    
    def show(body: dict) -> None:
        """Prints the answer in a reply, and then the IDs of its sources."""
        ids = [str(source.get("id", "(no id)")) for source in body.get("sources") or []]
        print(f"Answer:\n{body['answer']}")
        print(f"Sources: {', '.join(ids)}")
    
    
    def ask_anonymously(client: httpx.Client) -> None:
        """Asks the question without an identity. The server must refuse with
        IDENTITY_REQUIRED, because it never falls back to the pipeline's own
        database role; any other outcome is a failure."""
        print()
        print("Caller: (no identity)")
        try:
            ask(client, None)
        except ApiError as e:
            print(f"{e.code} (HTTP {e.status})")
            if e.code != "IDENTITY_REQUIRED":
                raise RagError(f"expected IDENTITY_REQUIRED, got {e}") from None
            return
        raise RagError("the server answered without an identity; "
                       "is identity.enabled set?")
    
    
    def main() -> int:
        try:
            with httpx.Client(base_url=BASE_URL, timeout=TIMEOUT_SECONDS) as client:
                print(f"Question: {QUESTION}")
                for caller in CALLERS:
                    body = ask(client, caller)
                    print()
                    print(f"Caller: {caller}")
                    show(body)
                ask_anonymously(client)
        # httpx.HTTPError is the base class for failures to reach the server,
        # such as a refused connection or a timeout.
        except (httpx.HTTPError, ApiError, RagError) as e:
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
     * Limiting the answers of the pgEdge RAG Server to each caller's own rows,
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
    const pipeline = process.env.RAG_PIPELINE || "cookbook_private";
    
    const question = "What is the status of my warranty claim?";
    
    // The callers to ask for. The fictional documents in the pipeline's table
    // belong to these two people.
    const callers = ["jane.doe@example.com", "john.smith@example.com"];
    
    // The header in which the server expects a trusted proxy to put the claims
    // of the caller. This is the server's default; the identity.claims_header
    // setting changes it.
    const claimsHeader = "X-Forwarded-Claims";
    
    // The server waits for the language model before it replies, and a small
    // model on a modest machine can take a while, so allow plenty of time.
    const timeoutMs = 300_000;
    
    interface Source {
      id?: string;
    }
    
    interface QueryResponse {
      answer: string;
      sources?: Source[];
    }
    
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
    
    // Sends the question to the pipeline on behalf of a caller, and asks for
    // the documents that the answer came from. Returns the decoded reply. A
    // subject of undefined sends no identity at all.
    async function ask(subject?: string): Promise<QueryResponse> {
      // The claims are a JSON object, which JSON.stringify builds, so that the
      // subject needs no escaping.
      const headers: Record<string, string> = { "Content-Type": "application/json" };
      if (subject !== undefined) {
        headers[claimsHeader] = JSON.stringify({ sub: subject });
      }
    
      const response = await fetch(
        `${baseUrl}/v1/pipelines/${encodeURIComponent(pipeline)}`,
        {
          method: "POST",
          headers,
          body: JSON.stringify({ query: question, include_sources: true }),
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
    
      const body = (await response.json()) as Partial<QueryResponse>;
      if (typeof body.answer !== "string") {
        throw new Error(`Unexpected response: ${JSON.stringify(body).slice(0, 200)}`);
      }
      return body as QueryResponse;
    }
    
    // Prints the answer in a reply, and then the IDs of its sources.
    function show(body: QueryResponse): void {
      const ids = (body.sources ?? []).map((source) => source.id ?? "(no id)");
      console.log(`Answer:\n${body.answer}`);
      console.log(`Sources: ${ids.join(", ")}`);
    }
    
    // Asks the question without an identity. The server must refuse with
    // IDENTITY_REQUIRED, because it never falls back to the pipeline's own
    // database role; any other outcome is a failure.
    async function askAnonymously(): Promise<void> {
      console.log();
      console.log("Caller: (no identity)");
      try {
        await ask();
      } catch (err) {
        if (!(err instanceof ApiError)) {
          throw err;
        }
        console.log(`${err.code} (HTTP ${err.status})`);
        if (err.code !== "IDENTITY_REQUIRED") {
          throw new Error(`expected IDENTITY_REQUIRED, got ${err.code}: ${err.message}`);
        }
        return;
      }
      throw new Error("the server answered without an identity; is identity.enabled set?");
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
        console.log(`Question: ${question}`);
        for (const caller of callers) {
          const body = await ask(caller);
          console.log();
          console.log(`Caller: ${caller}`);
          show(body);
        }
        await askAnonymously();
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
     * Answering each caller from only their own documents with the pgEdge RAG
     * Server and row-level security, using java.net.http and Jackson.
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
    import java.util.ArrayList;
    import java.util.List;
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
        static final String PIPELINE = envOr("RAG_PIPELINE", "cookbook_private");
    
        static final String QUESTION = "What is the status of my warranty claim?";
    
        // The callers to ask for. The fictional documents in the pipeline's
        // table belong to these two people.
        static final List<String> CALLERS =
                List.of("jane.doe@example.com", "john.smith@example.com");
    
        // The header in which the server expects a trusted proxy to put the
        // claims of the caller. This is the server's default; the
        // identity.claims_header setting changes it.
        static final String CLAIMS_HEADER = "X-Forwarded-Claims";
    
        // The server waits for the language model before it replies, and a
        // small model on a modest machine can take a while, so allow plenty
        // of time.
        static final Duration TIMEOUT = Duration.ofSeconds(300);
    
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
    
            ApiException(int status, String code, String message) {
                super(code + ": " + message);
                this.status = status;
                this.code = code;
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
         * Sends the question to the pipeline on behalf of a caller, and asks
         * for the documents that the answer came from. Returns the decoded
         * reply. A subject of null sends no identity at all.
         */
        static JsonNode ask(HttpClient client, String subject)
                throws IOException, InterruptedException, RagException, ApiException {
            String payload = MAPPER.writeValueAsString(MAPPER.createObjectNode()
                    .put("query", QUESTION)
                    .put("include_sources", true));
            HttpRequest.Builder builder = HttpRequest.newBuilder(pipelineUri(PIPELINE))
                    .timeout(TIMEOUT)
                    .header("Content-Type", "application/json")
                    .POST(HttpRequest.BodyPublishers.ofString(payload));
            // The claims are a JSON object, which Jackson builds, so that the
            // subject needs no escaping.
            if (subject != null) {
                builder.header(CLAIMS_HEADER, MAPPER.writeValueAsString(
                        MAPPER.createObjectNode().put("sub", subject)));
            }
            HttpResponse<String> response = send(client, builder.build());
    
            JsonNode body = null;
            try {
                body = MAPPER.readTree(response.body());
            } catch (JacksonException e) {
                // The body is not JSON; report it below.
            }
    
            if (response.statusCode() >= 400) {
                JsonNode error = body == null ? null : body.path("error");
                if (error == null || !error.path("code").isString()
                        || !error.path("message").isString()) {
                    throw new RagException("HTTP " + response.statusCode() + ", "
                            + shorten(response.body()));
                }
                throw new ApiException(response.statusCode(),
                        error.path("code").stringValue(),
                        error.path("message").stringValue());
            }
    
            if (body == null || !body.path("answer").isString()) {
                throw new RagException(
                        "Unexpected response: " + shorten(response.body()));
            }
            return body;
        }
    
        /** Prints the answer in a reply, and then the IDs of its sources. */
        static void show(JsonNode body) {
            // path() gives a missing node, which holds no elements, when the
            // reply has no sources.
            List<String> ids = new ArrayList<>();
            for (JsonNode source : body.path("sources")) {
                ids.add(source.has("id") ? source.get("id").asString() : "(no id)");
            }
            System.out.println("Answer:\n" + body.path("answer").stringValue());
            System.out.println("Sources: " + String.join(", ", ids));
        }
    
        /**
         * Asks the question without an identity. The server must refuse with
         * IDENTITY_REQUIRED, because it never falls back to the pipeline's own
         * database role; any other outcome is a failure.
         */
        static void askAnonymously(HttpClient client)
                throws IOException, InterruptedException, RagException {
            System.out.println();
            System.out.println("Caller: (no identity)");
            try {
                ask(client, null);
            } catch (ApiException e) {
                System.out.println(e.code + " (HTTP " + e.status + ")");
                if (!e.code.equals("IDENTITY_REQUIRED")) {
                    throw new RagException(
                            "expected IDENTITY_REQUIRED, got " + e.getMessage());
                }
                return;
            }
            throw new RagException("the server answered without an identity; "
                    + "is identity.enabled set?");
        }
    
        public static void main(String[] args) {
            HttpClient client = HttpClient.newHttpClient();
            try {
                System.out.println("Question: " + QUESTION);
                for (String caller : CALLERS) {
                    JsonNode body = ask(client, caller);
                    System.out.println();
                    System.out.println("Caller: " + caller);
                    show(body);
                }
                askAnonymously(client);
            // IOException covers failures to reach the server, such as a
            // refused connection or a timeout. The message of a refused
            // connection can be empty, so print the exception itself, which
            // includes its type.
            } catch (IOException | InterruptedException e) {
                System.err.println("RAG Server error: " + e);
                System.exit(1);
            } catch (ApiException | RagException e) {
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
     * Answering each caller from only their own documents with the pgEdge RAG
     * Server and row-level security, using HttpClient and System.Text.Json.
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
    static string Pipeline() => EnvOr("RAG_PIPELINE", "cookbook_private");
    
    const string Question = "What is the status of my warranty claim?";
    
    // The callers to ask for. The fictional documents in the pipeline's table
    // belong to these two people.
    string[] callers = ["jane.doe@example.com", "john.smith@example.com"];
    
    // The header in which the server expects a trusted proxy to put the claims
    // of the caller. This is the server's default; the identity.claims_header
    // setting changes it.
    const string ClaimsHeader = "X-Forwarded-Claims";
    
    // The server waits for the language model before it replies, and a small
    // model on a modest machine can take a while, so allow plenty of time.
    const int TimeoutSeconds = 300;
    
    // Returns at most the first 200 characters of a reply.
    static string Shorten(string text) =>
        text.Length > 200 ? text[..200] : text;
    
    // Sends the question to the pipeline on behalf of a caller, and asks for
    // the documents that the answer came from. Returns the decoded reply. A
    // subject of null sends no identity at all.
    static async Task<JsonNode> AskAsync(HttpClient client, string? subject)
    {
        var url = $"{BaseUrl()}/v1/pipelines/{Uri.EscapeDataString(Pipeline())}";
        using var request = new HttpRequestMessage(HttpMethod.Post, url)
        {
            Content = JsonContent.Create(new { query = Question, include_sources = true }),
        };
        // The claims are a JSON object, which JsonSerializer builds, so that
        // the subject needs no escaping.
        if (subject is not null)
        {
            request.Headers.Add(ClaimsHeader, JsonSerializer.Serialize(new { sub = subject }));
        }
        using var response = await client.SendAsync(request);
        var body = await response.Content.ReadAsStringAsync();
        var status = (int)response.StatusCode;
    
        JsonNode? reply = null;
        try
        {
            reply = JsonNode.Parse(body);
        }
        catch (JsonException)
        {
            // The body is not JSON; report it below.
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
    
        if (reply?["answer"] is JsonValue answerNode &&
            answerNode.TryGetValue(out string? _))
        {
            return reply;
        }
        throw new RagException($"Unexpected response: {Shorten(body)}");
    }
    
    // Prints the answer in a reply, and then the IDs of its sources.
    static void Show(JsonNode reply)
    {
        var ids = new List<string>();
        if (reply["sources"] is JsonArray sources)
        {
            foreach (var source in sources)
            {
                ids.Add(source?["id"]?.ToString() ?? "(no id)");
            }
        }
        Console.WriteLine($"Answer:\n{reply["answer"]}");
        Console.WriteLine($"Sources: {string.Join(", ", ids)}");
    }
    
    // Asks the question without an identity. The server must refuse with
    // IDENTITY_REQUIRED, because it never falls back to the pipeline's own
    // database role; any other outcome is a failure.
    static async Task AskAnonymouslyAsync(HttpClient client)
    {
        Console.WriteLine();
        Console.WriteLine("Caller: (no identity)");
        try
        {
            await AskAsync(client, null);
        }
        catch (ApiException e)
        {
            Console.WriteLine($"{e.Code} (HTTP {e.Status})");
            if (e.Code != "IDENTITY_REQUIRED")
            {
                throw new RagException($"expected IDENTITY_REQUIRED, got {e.Message}");
            }
            return;
        }
        throw new RagException(
            "the server answered without an identity; is identity.enabled set?");
    }
    
    try
    {
        // using disposes of the client, and closes its connections, when the
        // block exits, whether or not an error occurred.
        using var client = new HttpClient
        {
            Timeout = TimeSpan.FromSeconds(TimeoutSeconds),
        };
        Console.WriteLine($"Question: {Question}");
        foreach (var caller in callers)
        {
            var reply = await AskAsync(client, caller);
            Console.WriteLine();
            Console.WriteLine($"Caller: {caller}");
            Show(reply);
        }
        await AskAnonymouslyAsync(client);
    }
    // HttpRequestException covers failures to reach the server, such as a
    // refused connection, and TaskCanceledException covers a timeout.
    catch (Exception e) when (e is HttpRequestException or TaskCanceledException
        or ApiException or RagException)
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
    }
    
    ```

=== "Go"

    ```go
    // Ellie's Postgres Cookbook
    // Limiting the answers of the pgEdge RAG Server to each caller's own rows,
    // using net/http.
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
    	pipeline = envOr("RAG_PIPELINE", "cookbook_private")
    )
    
    const question = "What is the status of my warranty claim?"
    
    // The callers to ask for. The fictional documents in the pipeline's table
    // belong to these two people.
    var callers = []string{"jane.doe@example.com", "john.smith@example.com"}
    
    // The header in which the server expects a trusted proxy to put the claims
    // of the caller. This is the server's default; the identity.claims_header
    // setting changes it.
    const claimsHeader = "X-Forwarded-Claims"
    
    // The server waits for the language model before it replies, and a small
    // model on a modest machine can take a while, so allow plenty of time.
    const timeout = 300 * time.Second
    
    
    // source is a document that the answer came from.
    type source struct {
    	ID string `json:"id"`
    }
    
    // queryResponse holds the fields of the reply that the program uses. The
    // answer is a pointer so that the program can tell a missing field from
    // an empty one.
    type queryResponse struct {
    	Answer  *string  `json:"answer"`
    	Sources []source `json:"sources"`
    }
    
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
    
    // ask sends the question to the pipeline on behalf of a caller, and asks
    // for the documents that the answer came from. It returns the decoded
    // reply. An empty subject sends no identity at all.
    func ask(client *http.Client, subject string) (*queryResponse, error) {
    	payload, err := json.Marshal(map[string]any{
    		"query":           question,
    		"include_sources": true,
    	})
    	if err != nil {
    		return nil, err
    	}
    
    	endpoint := baseURL + "/v1/pipelines/" + url.PathEscape(pipeline)
    	request, err := http.NewRequest(http.MethodPost, endpoint, bytes.NewReader(payload))
    	if err != nil {
    		return nil, err
    	}
    	request.Header.Set("Content-Type", "application/json")
    	if subject != "" {
    		// The claims are a JSON object, which json.Marshal builds, so that
    		// the subject needs no escaping.
    		claims, err := json.Marshal(map[string]string{"sub": subject})
    		if err != nil {
    			return nil, err
    		}
    		request.Header.Set(claimsHeader, string(claims))
    	}
    
    	response, err := client.Do(request)
    	if err != nil {
    		return nil, err
    	}
    	defer response.Body.Close()
    
    	body, err := io.ReadAll(response.Body)
    	if err != nil {
    		return nil, err
    	}
    
    	// Go treats an error status as a normal response, so check it here.
    	if response.StatusCode != http.StatusOK {
    		var e struct {
    			Error struct {
    				Code    string `json:"code"`
    				Message string `json:"message"`
    			} `json:"error"`
    		}
    		if json.Unmarshal(body, &e) != nil || e.Error.Code == "" {
    			return nil, fmt.Errorf("HTTP %d, %.200s", response.StatusCode, strings.TrimSpace(string(body)))
    		}
    		return nil, &apiError{response.StatusCode, e.Error.Code, e.Error.Message}
    	}
    
    	var result queryResponse
    	if err := json.Unmarshal(body, &result); err != nil || result.Answer == nil {
    		return nil, fmt.Errorf("unexpected response: %.200s", body)
    	}
    	return &result, nil
    }
    
    
    // show prints the answer in a reply, and then the IDs of its sources.
    func show(result *queryResponse) {
    	ids := make([]string, 0, len(result.Sources))
    	for _, s := range result.Sources {
    		ids = append(ids, s.ID)
    	}
    	fmt.Printf("Answer:\n%s\n", *result.Answer)
    	fmt.Printf("Sources: %s\n", strings.Join(ids, ", "))
    }
    
    
    // askAnonymously asks the question without an identity. The server must
    // refuse with IDENTITY_REQUIRED, because it never falls back to the
    // pipeline's own database role; any other outcome is a failure.
    func askAnonymously(client *http.Client) error {
    	fmt.Println()
    	fmt.Println("Caller: (no identity)")
    
    	_, err := ask(client, "")
    	var apiErr *apiError
    	if !errors.As(err, &apiErr) {
    		if err == nil {
    			return errors.New("the server answered without an identity; is identity.enabled set?")
    		}
    		return err
    	}
    
    	fmt.Printf("%s (HTTP %d)\n", apiErr.Code, apiErr.Status)
    	if apiErr.Code != "IDENTITY_REQUIRED" {
    		return fmt.Errorf("expected IDENTITY_REQUIRED, got %v", apiErr)
    	}
    	return nil
    }
    
    // run asks the question as each caller, and then without an identity,
    // returning any error to the caller.
    func run() error {
    	client := &http.Client{Timeout: timeout}
    
    	fmt.Printf("Question: %s\n", question)
    	for _, caller := range callers {
    		result, err := ask(client, caller)
    		if err != nil {
    			return err
    		}
    		fmt.Println()
    		fmt.Printf("Caller: %s\n", caller)
    		show(result)
    	}
    	return askAnonymously(client)
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
    // Answering each caller from only their own documents with the pgEdge RAG
    // Server and row-level security, using reqwest and serde_json.
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
        env_or("RAG_PIPELINE", "cookbook_private")
    }
    
    const QUESTION: &str = "What is the status of my warranty claim?";
    
    /// The callers to ask for. The fictional documents in the pipeline's table
    /// belong to these two people.
    const CALLERS: [&str; 2] = ["jane.doe@example.com", "john.smith@example.com"];
    
    /// The header in which the server expects a trusted proxy to put the
    /// claims of the caller. This is the server's default; the
    /// identity.claims_header setting changes it.
    const CLAIMS_HEADER: &str = "X-Forwarded-Claims";
    
    /// The server waits for the language model before it replies, and a small
    /// model on a modest machine can take a while, so allow plenty of time.
    const TIMEOUT: Duration = Duration::from_secs(300);
    
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
    
    /// Sends the question to the pipeline on behalf of a caller, and asks for
    /// the documents that the answer came from. Returns the decoded reply, or
    /// an ApiError, which the caller can recover with downcast_ref(), when the
    /// server replies with an error. A subject of None sends no identity at
    /// all.
    fn ask(client: &Client, subject: Option<&str>) -> Result<Value, BoxError> {
        let mut request = client
            .post(pipeline_url(&pipeline())?)
            .json(&json!({ "query": QUESTION, "include_sources": true }));
        // The claims are a JSON object, which json! builds, so that the subject
        // needs no escaping.
        if let Some(subject) = subject {
            request = request.header(CLAIMS_HEADER, json!({ "sub": subject }).to_string());
        }
        let response = request.send()?;
        let status = response.status();
        let body = response.text()?;
    
        // A body that is not JSON becomes Null, and indexing Null (or any
        // missing field) gives Null again, which as_str() turns into None.
        let reply: Value = serde_json::from_str(&body).unwrap_or(Value::Null);
    
        if !status.is_success() {
            let error = &reply["error"];
            return match (error["code"].as_str(), error["message"].as_str()) {
                (Some(code), Some(message)) => Err(Box::new(ApiError {
                    status: status.as_u16(),
                    code: code.to_string(),
                    message: message.to_string(),
                })),
                _ => Err(format!("HTTP {}, {}", status.as_u16(), shorten(&body)).into()),
            };
        }
    
        if !reply["answer"].is_string() {
            return Err(format!("Unexpected response: {}", shorten(&body)).into());
        }
        Ok(reply)
    }
    
    /// Prints the answer in a reply, and then the IDs of its sources.
    fn show(reply: &Value) {
        // as_array() gives None when the reply has no sources.
        let ids: Vec<&str> = reply["sources"]
            .as_array()
            .map(|sources| {
                sources
                    .iter()
                    .map(|source| source["id"].as_str().unwrap_or("(no id)"))
                    .collect()
            })
            .unwrap_or_default();
        println!("Answer:\n{}", reply["answer"].as_str().unwrap_or(""));
        println!("Sources: {}", ids.join(", "));
    }
    
    /// Asks the question without an identity. The server must refuse with
    /// IDENTITY_REQUIRED, because it never falls back to the pipeline's own
    /// database role; any other outcome is a failure.
    fn ask_anonymously(client: &Client) -> Result<(), BoxError> {
        println!();
        println!("Caller: (no identity)");
        let e = match ask(client, None) {
            Ok(_) => {
                return Err("the server answered without an identity; is identity.enabled set?".into())
            }
            Err(e) => e,
        };
        // Any error other than an ApiError, such as a refused connection, is
        // returned as it is.
        let Some(api) = e.downcast_ref::<ApiError>() else {
            return Err(e);
        };
        println!("{} (HTTP {})", api.code, api.status);
        if api.code != "IDENTITY_REQUIRED" {
            return Err(format!("expected IDENTITY_REQUIRED, got {api}").into());
        }
        Ok(())
    }
    
    /// Asks the question for each caller, and then without an identity. The ?
    /// operator returns any error to the caller.
    fn run() -> Result<(), BoxError> {
        let client = Client::builder().timeout(TIMEOUT).build()?;
        println!("Question: {QUESTION}");
        for caller in CALLERS {
            let reply = ask(&client, Some(caller))?;
            println!();
            println!("Caller: {caller}");
            show(&reply);
        }
        ask_anonymously(&client)
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
    # Answering each caller from only their own documents with the pgEdge RAG
    # Server and row-level security, using Net::HTTP.
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
    PIPELINE = env_or("RAG_PIPELINE", "cookbook_private")
    
    QUESTION = "What is the status of my warranty claim?"
    
    # The callers to ask for. The fictional documents in the pipeline's table
    # belong to these two people.
    CALLERS = ["jane.doe@example.com", "john.smith@example.com"].freeze
    
    # The header in which the server expects a trusted proxy to put the claims
    # of the caller. This is the server's default; the identity.claims_header
    # setting changes it.
    CLAIMS_HEADER = "X-Forwarded-Claims"
    
    # The server waits for the language model before it replies, and a small
    # model on a modest machine can take a while, so allow plenty of time.
    TIMEOUT_SECONDS = 300
    
    # Raised when a reply is not one that the program can interpret.
    class RagError < StandardError; end
    
    # Raised when the RAG Server replies with an error. The reply has an HTTP
    # status and a JSON body of the form
    # {"error": {"code": "...", "message": "..."}}.
    class ApiError < StandardError
      attr_reader :status, :code
    
      def initialize(status, code, detail)
        super("#{code}: #{detail}")
        @status = status
        @code = code
      end
    end
    
    # Parses text as a JSON object, and returns nil if it is not one.
    def parse_object(text)
      value = JSON.parse(text.to_s)
      value.is_a?(Hash) ? value : nil
    rescue JSON::ParserError
      nil
    end
    
    # Sends the question to the pipeline on behalf of a caller, and asks for
    # the documents that the answer came from. Returns the decoded reply. A
    # subject of nil sends no identity at all.
    def ask(http, subject)
      uri = URI("#{BASE_URL}/v1/pipelines/#{URI.encode_uri_component(PIPELINE)}")
      request = Net::HTTP::Post.new(uri, "Content-Type" => "application/json")
      # The claims are a JSON object, which JSON.generate builds, so that the
      # subject needs no escaping.
      request[CLAIMS_HEADER] = JSON.generate({ sub: subject }) unless subject.nil?
      request.body = JSON.generate({ query: QUESTION, include_sources: true })
      response = http.request(request)
      body = parse_object(response.body)
    
      unless response.is_a?(Net::HTTPSuccess)
        error = body&.fetch("error", nil)
        unless error.is_a?(Hash) && error["code"].is_a?(String) && error["message"].is_a?(String)
          raise RagError, "HTTP #{response.code}, #{response.body.to_s[0, 200]}"
        end
    
        raise ApiError.new(response.code.to_i, error["code"], error["message"])
      end
    
      unless body && body["answer"].is_a?(String)
        raise RagError, "Unexpected response: #{response.body.to_s[0, 200]}"
      end
    
      body
    end
    
    # Prints the answer in a reply, and then the IDs of its sources.
    def show(body)
      ids = (body["sources"] || []).map { |source| source.fetch("id", "(no id)").to_s }
      puts "Answer:\n#{body["answer"]}"
      puts "Sources: #{ids.join(", ")}"
    end
    
    # Asks the question without an identity. The server must refuse with
    # IDENTITY_REQUIRED, because it never falls back to the pipeline's own
    # database role; any other outcome is a failure.
    def ask_anonymously(http)
      puts
      puts "Caller: (no identity)"
      begin
        ask(http, nil)
      rescue ApiError => e
        puts "#{e.code} (HTTP #{e.status})"
        raise RagError, "expected IDENTITY_REQUIRED, got #{e.message}" if e.code != "IDENTITY_REQUIRED"
    
        return
      end
      raise RagError, "the server answered without an identity; is identity.enabled set?"
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
        puts "Question: #{QUESTION}"
        CALLERS.each do |caller|
          body = ask(http, caller)
          puts
          puts "Caller: #{caller}"
          show(body)
        end
        ask_anonymously(http)
      end
    # SystemCallError covers a refused connection, Timeout::Error covers the
    # connection and read timeouts, and SocketError covers an unknown host.
    rescue ApiError, RagError, SystemCallError, Timeout::Error, SocketError, IOError => e
      warn "RAG Server error: #{e.message}"
      exit 1
    end
    
    ```

=== "curl"

    ```bash
    #!/usr/bin/env bash
    #
    # Ellie's Postgres Cookbook
    # Limiting the answers of the pgEdge RAG Server to each caller's own rows,
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
    RAG_PIPELINE="${RAG_PIPELINE:-cookbook_private}"
    
    QUESTION="What is the status of my warranty claim?"
    
    # The callers to ask for. The fictional documents in the pipeline's table
    # belong to these two people.
    CALLERS=("jane.doe@example.com" "john.smith@example.com")
    
    # The header in which the server expects a trusted proxy to put the claims
    # of the caller. This is the server's default; the identity.claims_header
    # setting changes it.
    CLAIMS_HEADER="X-Forwarded-Claims"
    
    # The server waits for the language model before it replies, and a small
    # model on a modest machine can take a while, so allow plenty of time.
    TIMEOUT_SECONDS=300
    
    # Escapes a value for use in a URL path, as the other languages do.
    escape() { jq -rn --arg value "$1" '$value | @uri'; }
    
    # Sends the question to the pipeline on behalf of a caller, and asks for
    # the documents that the answer came from. The argument is the caller's
    # subject, or an empty string to send no identity. The function sets
    # STATUS to the HTTP status and BODY to the reply, and returns 1 when the
    # status is an error. The claims are a JSON object, which jq builds, so
    # that the subject needs no escaping. With --fail-with-body, curl exits
    # non-zero on an HTTP error status but still prints the body; --write-out
    # adds the HTTP status after it. The script leaves out --show-error,
    # because it reports each failure itself.
    STATUS="" BODY=""
    ask() {
        local subject="$1" output rc=0 headers=()
        if [[ -n "$subject" ]]; then
            headers=(--header "$CLAIMS_HEADER: $(jq -cn --arg sub "$subject" '{sub: $sub}')")
        fi
    
        output="$(jq -n --arg query "$QUESTION" '{query: $query, include_sources: true}' |
            curl --silent --fail-with-body \
                --max-time "$TIMEOUT_SECONDS" \
                --header 'Content-Type: application/json' \
                ${headers[@]+"${headers[@]}"} \
                --data-binary @- \
                --write-out '\n%{http_code}' \
                "$RAG_SERVER_URL/v1/pipelines/$(escape "$RAG_PIPELINE")")" || rc=$?
    
        STATUS="${output##*$'\n'}"
        BODY="${output%$'\n'*}"
        if [[ "$STATUS" == 000 ]]; then
            echo "RAG Server error: could not reach $RAG_SERVER_URL" >&2
            exit 1
        fi
        return "$rc"
    }
    
    # Prints the answer in the reply, and then the IDs of its sources. The
    # error call makes jq fail when the answer is missing or is not a string,
    # since interpolating null would print the word "null".
    show() {
        jq -er 'if (.answer | type) == "string"
                then "Answer:\n\(.answer)"
                else error("missing answer") end,
                "Sources: \((.sources // []) | map(.id // "(no id)") | join(", "))"'
    }
    
    # Asks the question as a caller who has an identity, and prints what that
    # caller may see.
    ask_as() {
        echo
        echo "Caller: $1"
        if ! ask "$1"; then
            echo "RAG Server error: HTTP $STATUS, ${BODY:0:200}" >&2
            return 1
        fi
        show <<<"$BODY" || {
            echo "Unexpected response: ${BODY:0:200}" >&2
            return 1
        }
    }
    
    # Asks the question without an identity. The server must refuse with
    # IDENTITY_REQUIRED, because it never falls back to the pipeline's own
    # database role; any other outcome is a failure.
    ask_anonymously() {
        local code
    
        echo
        echo "Caller: (no identity)"
        if ask ""; then
            echo "RAG Server error: the server answered without an identity;" \
                 "is identity.enabled set?" >&2
            return 1
        fi
        code="$(jq -r '.error.code // empty' <<<"$BODY" 2>/dev/null || true)"
        echo "$code (HTTP $STATUS)"
        if [[ "$code" != IDENTITY_REQUIRED ]]; then
            echo "RAG Server error: expected IDENTITY_REQUIRED, got HTTP $STATUS:" \
                 "${BODY:0:200}" >&2
            return 1
        fi
    }
    
    main() {
        local caller
    
        echo "Question: $QUESTION"
        for caller in "${CALLERS[@]}"; do
            ask_as "$caller"
        done
        ask_anonymously
    }
    
    main
    
    ```

## Next Steps

The following resources provide more information about the topics in this
recipe:

- The [Showing the Sources of an Answer](include_sources.md) recipe explains
  the `include_sources` setting.
- The [Handling RAG Server Errors](handle_errors.md) recipe shows how to react
  to the error codes that the server returns.
- The
  [pgEdge RAG Server documentation](https://docs.pgedge.com/pgedge-rag-server/)
  describes the identity settings, such as `allowed_roles` and the claims
  setting name.
- The [Contributing a Recipe](../contributing.md) page explains how to add a
  recipe or a language to the cookbook.
