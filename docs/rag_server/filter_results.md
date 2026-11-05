# Filtering Retrieved Documents

This recipe asks a pgEdge RAG Server pipeline the same question twice, and
uses a structured filter to limit each search to the documents for one
product version. A filter lets one pipeline serve a table that holds many
products, versions, or languages, without a separate pipeline for each. Each
step shows the code in every supported language; selecting a language tab
switches every tab on the site to that language.

These examples are for pgEdge RAG Server 2.0.0.

The wording of the answers varies from run to run, because a language model
writes them, but the output has the following shape:

```text
Question: How long does the Acme Widget take to charge?

Filter: product = Acme Widget, version = 1.0
Answer:
The Acme Widget 1.0 takes four hours to fully charge.
Sources: 1, 2

Filter: product = Acme Widget, version = 2.0
Answer:
The Acme Widget 2.0 takes ninety minutes to fully charge.
Sources: 3, 4
```

## Preparing the Ingredients

The examples need a running RAG Server with a pipeline that reads a table of
embedded documents; the
[Preparing Data for the RAG Server](prepare_data.md) recipe shows how to
build such a table and its pipeline. The examples assume a pipeline named
`cookbook` that holds the fictional Acme Widget support documents, which the
`scripts/start_rag_server.sh` script in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook)
loads and starts in Docker. The table has `product` and `version` columns
next to the text and the embedding, and the filter uses them. The
[Asking a Question](ask_question.md) recipe describes the request that this
recipe extends.

The question names no version, so without a filter the pipeline would search
every document and the answer could describe any version of the product. A
`filter` object in the request body limits the search to the rows that match
its conditions, before the pipeline ranks them. The object has the following
fields:

| Field        | Description                                                  |
|--------------|--------------------------------------------------------------|
| `conditions` | A list of up to 50 conditions, each with a `column`, an `operator`, and a `value`. |
| `logic`      | `AND` (the default) or `OR`, which says how to combine the conditions. |

The `operator` of a condition is one of `=`, `!=`, `<`, `>`, `<=`, `>=`,
`LIKE`, `ILIKE`, `IN`, `NOT IN`, `IS NULL`, or `IS NOT NULL`. The server passes
each value to PostgreSQL as a parameter, so a value cannot change the shape of
the query, and it quotes each column name as an identifier. It does not check
the names against the table, so a column that does not exist makes the search
fail; the server then replies with HTTP 500 and the `RETRIEVAL_REFUSED` code,
and a message that says only that the document search could not be run because
of a configuration or permissions problem. The conditions in this recipe select
one product and one version:

```json
{
  "logic": "AND",
  "conditions": [
    {"column": "product", "operator": "=", "value": "Acme Widget"},
    {"column": "version", "operator": "=", "value": "1.0"}
  ]
}
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
      "name": "filter-results",
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

The examples read the address of the RAG Server and the name of the pipeline
from environment variables. Each example treats an empty variable as unset,
and uses the default instead. The following table describes the environment
variables that the examples read:

| Variable         | Default                 | Description                      |
|------------------|-------------------------|----------------------------------|
| `RAG_SERVER_URL` | `http://localhost:8080` | The base URL of the RAG Server.  |
| `RAG_PIPELINE`   | `cookbook`              | The name of the pipeline to ask. |

The programs also hold the question, the product, and the versions to ask
about. A language model can take a while to write an answer, particularly a
small model on a modest machine, so each program allows 300 seconds for each
reply. The following tabs show how each program reads its settings:

=== "Python"

    ```python
    # The or operator treats an empty variable as unset.
    BASE_URL = (os.environ.get("RAG_SERVER_URL") or "http://localhost:8080").rstrip("/")
    PIPELINE = os.environ.get("RAG_PIPELINE") or "cookbook"
    
    QUESTION = "How long does the Acme Widget take to charge?"
    
    # The product to search, and the versions to ask about in turn. The
    # question names no version, so only the filter tells the pipeline which
    # documents to use.
    PRODUCT = "Acme Widget"
    VERSIONS = ["1.0", "2.0"]
    
    # The server waits for the language model before it replies, and a small
    # model on a modest machine can take a while, so allow plenty of time.
    TIMEOUT_SECONDS = 300.0
    ```

=== "TypeScript"

    ```typescript
    // The || operator, unlike ??, also treats an empty variable as unset.
    const baseUrl = (process.env.RAG_SERVER_URL || "http://localhost:8080").replace(/\/+$/, "");
    const pipeline = process.env.RAG_PIPELINE || "cookbook";
    
    const question = "How long does the Acme Widget take to charge?";
    
    // The product to search, and the versions to ask about in turn. The
    // question names no version, so only the filter tells the pipeline which
    // documents to use.
    const product = "Acme Widget";
    const versions = ["1.0", "2.0"];
    
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
            "How long does the Acme Widget take to charge?";
    
    // The product to search, and the versions to ask about in turn. The
    // question names no version, so only the filter tells the pipeline
    // which documents to use.
    static final String PRODUCT = "Acme Widget";
    static final List<String> VERSIONS = List.of("1.0", "2.0");
    
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
    
    const string Question = "How long does the Acme Widget take to charge?";
    
    // The product to search, and the versions to ask about in turn. The
    // question names no version, so only the filter tells the pipeline which
    // documents to use.
    const string Product = "Acme Widget";
    string[] versions = ["1.0", "2.0"];
    
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
    
    const question = "How long does the Acme Widget take to charge?"
    
    // The product to search, and the versions to ask about in turn. The
    // question names no version, so only the filter tells the pipeline which
    // documents to use.
    const product = "Acme Widget"
    
    var versions = []string{"1.0", "2.0"}
    
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
    
    const QUESTION: &str = "How long does the Acme Widget take to charge?";
    
    /// The product to search, and the versions to ask about in turn. The
    /// question names no version, so only the filter tells the pipeline which
    /// documents to use.
    const PRODUCT: &str = "Acme Widget";
    const VERSIONS: [&str; 2] = ["1.0", "2.0"];
    
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
    
    QUESTION = "How long does the Acme Widget take to charge?"
    
    # The product to search, and the versions to ask about in turn. The
    # question names no version, so only the filter tells the pipeline which
    # documents to use.
    PRODUCT = "Acme Widget"
    VERSIONS = ["1.0", "2.0"].freeze
    
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
    
    QUESTION="How long does the Acme Widget take to charge?"
    
    # The product to search, and the versions to ask about in turn. The
    # question names no version, so only the filter tells the pipeline which
    # documents to use.
    PRODUCT="Acme Widget"
    VERSIONS=("1.0" "2.0")
    
    # The server waits for the language model before it replies, and a small
    # model on a modest machine can take a while, so allow plenty of time.
    TIMEOUT_SECONDS=300
    
    # Escapes a value for use in a URL path, as the other languages do.
    escape() { jq -rn --arg value "$1" '$value | @uri'; }
    ```

## Building the Filter

Each program builds the filter for a product and a version as a JSON object
with two conditions. Each program builds the object from its own data
structures, and never joins strings into JSON, so that a value containing a
quotation mark cannot break the request. The following tabs show how each
program builds the filter:

=== "Python"

    ```python
    def build_filter(product: str, version: str) -> dict:
        """Returns the filter for a product and a version. The conditions are
        joined with AND, which is the default, and each one compares a column
        of the pipeline's table with a value. The server passes the values to
        PostgreSQL as parameters, so they need no escaping."""
        return {
            "logic": "AND",
            "conditions": [
                {"column": "product", "operator": "=", "value": product},
                {"column": "version", "operator": "=", "value": version},
            ],
        }
    ```

=== "TypeScript"

    ```typescript
    interface Condition {
      column: string;
      operator: string;
      value: string;
    }
    
    interface Filter {
      logic: "AND" | "OR";
      conditions: Condition[];
    }
    
    // Returns the filter for a product and a version. The conditions are
    // joined with AND, which is the default, and each one compares a column of
    // the pipeline's table with a value. The server passes the values to
    // PostgreSQL as parameters, so they need no escaping.
    function buildFilter(product: string, version: string): Filter {
      return {
        logic: "AND",
        conditions: [
          { column: "product", operator: "=", value: product },
          { column: "version", operator: "=", value: version },
        ],
      };
    }
    ```

=== "Java"

    ```java
    // A mapper is safe to share, so the program creates only one.
    static final ObjectMapper MAPPER = JsonMapper.builder().build();
    
    /**
     * Returns the filter for a product and a version. The conditions are
     * joined with AND, which is the default, and each one compares a column
     * of the pipeline's table with a value. The server passes the values to
     * PostgreSQL as parameters, so they need no escaping.
     */
    static ObjectNode buildFilter(String product, String version) {
        ObjectNode filter = MAPPER.createObjectNode().put("logic", "AND");
        ArrayNode conditions = filter.putArray("conditions");
        conditions.addObject()
                .put("column", "product").put("operator", "=").put("value", product);
        conditions.addObject()
                .put("column", "version").put("operator", "=").put("value", version);
        return filter;
    }
    ```

=== "C#"

    ```csharp
    // Returns the filter for a product and a version. The conditions are
    // joined with AND, which is the default, and each one compares a column of
    // the pipeline's table with a value. The server passes the values to
    // PostgreSQL as parameters, so they need no escaping.
    static JsonObject BuildFilter(string product, string version) => new()
    {
        ["logic"] = "AND",
        ["conditions"] = new JsonArray(
            new JsonObject
            {
                ["column"] = "product", ["operator"] = "=", ["value"] = product,
            },
            new JsonObject
            {
                ["column"] = "version", ["operator"] = "=", ["value"] = version,
            }),
    };
    ```

=== "Go"

    ```go
    // condition compares one column of the pipeline's table with a value.
    type condition struct {
    	Column   string `json:"column"`
    	Operator string `json:"operator"`
    	Value    string `json:"value"`
    }
    
    // filter holds conditions that the server combines with Logic.
    type filter struct {
    	Logic      string      `json:"logic"`
    	Conditions []condition `json:"conditions"`
    }
    
    // buildFilter returns the filter for a product and a version. The
    // conditions are joined with AND, which is the default. The server passes
    // the values to PostgreSQL as parameters, so they need no escaping.
    func buildFilter(product, version string) filter {
    	return filter{
    		Logic: "AND",
    		Conditions: []condition{
    			{Column: "product", Operator: "=", Value: product},
    			{Column: "version", Operator: "=", Value: version},
    		},
    	}
    }
    
    ```

=== "Rust"

    ```rust
    /// Returns the filter for a product and a version. The conditions are
    /// joined with AND, which is the default, and each one compares a column
    /// of the pipeline's table with a value. The server passes the values to
    /// PostgreSQL as parameters, so they need no escaping.
    fn build_filter(product: &str, version: &str) -> Value {
        json!({
            "logic": "AND",
            "conditions": [
                { "column": "product", "operator": "=", "value": product },
                { "column": "version", "operator": "=", "value": version },
            ],
        })
    }
    ```

=== "Ruby"

    ```ruby
    # Returns the filter for a product and a version. The conditions are
    # joined with AND, which is the default, and each one compares a column of
    # the pipeline's table with a value. The server passes the values to
    # PostgreSQL as parameters, so they need no escaping.
    def build_filter(product, version)
      {
        logic: "AND",
        conditions: [
          { column: "product", operator: "=", value: product },
          { column: "version", operator: "=", value: version }
        ]
      }
    end
    ```

=== "curl"

    ```bash
    # Prints the filter for a product and a version as JSON. The conditions
    # are joined with AND, which is the default, and each one compares a
    # column of the pipeline's table with a value. The server passes the
    # values to PostgreSQL as parameters, so they need no escaping.
    build_filter() {
        jq -n --arg product "$1" --arg version "$2" '{
            logic: "AND",
            conditions: [
                {column: "product", operator: "=", value: $product},
                {column: "version", operator: "=", value: $version}
            ]}'
    }
    ```

## Asking with a Filter

Each program sends the question in a `POST` request whose JSON body holds the
`filter` object, and sets `include_sources` to true so that the reply names
the documents that the answer came from. The pipeline must set
`allow_include_sources: true` for the reply to include them. The RAG Server
reports a failure with an HTTP error status and a JSON body that holds an
error code and a message, and the programs print both. The following tabs
show how each program sends the question:

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
    
    
    def ask(client: httpx.Client, question: str, filter_: dict) -> dict:
        """Sends the question and the filter to the pipeline, and asks for the
        documents that the answer came from. Returns the decoded reply."""
        response = client.post(
            f"/v1/pipelines/{quote(PIPELINE, safe='')}",
            json={"query": question, "filter": filter_, "include_sources": True},
        )
        if response.is_error:
            raise RagError(f"HTTP {response.status_code}, {error_text(response)}")
    
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
      content?: string;
      score?: number;
    }
    
    interface QueryResponse {
      answer: string;
      sources?: Source[];
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
    
    // Sends the question and the filter to the pipeline, and asks for the
    // documents that the answer came from. Returns the decoded reply.
    async function ask(question: string, filter: Filter): Promise<QueryResponse> {
      const response = await fetch(
        `${baseUrl}/v1/pipelines/${encodeURIComponent(pipeline)}`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ query: question, filter, include_sources: true }),
          signal: AbortSignal.timeout(timeoutMs),
        },
      );
    
      // fetch only rejects when it cannot reach the server; an error status
      // is a normal response, so check it explicitly.
      if (!response.ok) {
        throw new Error(`HTTP ${response.status}, ${await errorText(response)}`);
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
    /** Thrown when the RAG Server rejects a request or replies oddly. */
    static class RagException extends Exception {
        RagException(String message) {
            super(message);
        }
    }
    
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
     * Sends the question and the filter to the pipeline, and asks for the
     * documents that the answer came from. Returns the decoded reply.
     */
    static JsonNode ask(HttpClient client, String question, ObjectNode filter)
            throws IOException, InterruptedException, RagException {
        ObjectNode payload = MAPPER.createObjectNode();
        payload.put("query", question);
        payload.set("filter", filter);
        payload.put("include_sources", true);
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
            JsonNode body = MAPPER.readTree(response.body());
            if (body.path("answer").isString()) {
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
    
    // Sends the question and the filter to the pipeline, and asks for the
    // documents that the answer came from. Returns the decoded reply.
    static async Task<JsonNode> AskAsync(
        HttpClient client, string question, JsonObject filter)
    {
        var url = $"{BaseUrl()}/v1/pipelines/{Uri.EscapeDataString(Pipeline())}";
        var payload = new JsonObject
        {
            ["query"] = question,
            ["filter"] = filter,
            ["include_sources"] = true,
        };
        using var response = await client.PostAsync(url, JsonContent.Create(payload));
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
            var reply = JsonNode.Parse(body);
            if (reply?["answer"] is JsonValue answerNode &&
                answerNode.TryGetValue(out string? _))
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
    // source is a document that the answer came from.
    type source struct {
    	ID      string  `json:"id"`
    	Content string  `json:"content"`
    	Score   float64 `json:"score"`
    }
    
    // queryResponse holds the fields of the reply that the program uses. The
    // answer is a pointer so that the program can tell a missing field from
    // an empty one.
    type queryResponse struct {
    	Answer  *string  `json:"answer"`
    	Sources []source `json:"sources"`
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
    
    // ask sends the question and the filter to the pipeline, and asks for the
    // documents that the answer came from. It returns the decoded reply.
    func ask(client *http.Client, question string, f filter) (*queryResponse, error) {
    	payload, err := json.Marshal(map[string]any{
    		"query":           question,
    		"filter":          f,
    		"include_sources": true,
    	})
    	if err != nil {
    		return nil, err
    	}
    
    	endpoint := baseURL + "/v1/pipelines/" + url.PathEscape(pipeline)
    	response, err := client.Post(endpoint, "application/json", bytes.NewReader(payload))
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
    		return nil, fmt.Errorf("HTTP %d, %s", response.StatusCode, errorText(body))
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
    
    /// Sends the question and the filter to the pipeline, and asks for the
    /// documents that the answer came from. Returns the decoded reply.
    fn ask(client: &Client, question: &str, filter: Value) -> Result<Value, BoxError> {
        let response = client
            .post(pipeline_url(&pipeline())?)
            .json(&json!({ "query": question, "filter": filter, "include_sources": true }))
            .send()?;
        let status = response.status();
        let body = response.text()?;
    
        // reqwest treats an error status as a normal response, so check it
        // here.
        if !status.is_success() {
            return Err(format!("HTTP {}, {}", status.as_u16(), error_text(&body)).into());
        }
    
        let reply: Value = serde_json::from_str(&body).unwrap_or(Value::Null);
        if !reply["answer"].is_string() {
            return Err(format!("Unexpected response: {}", shorten(&body)).into());
        }
        Ok(reply)
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
    
    # Sends the question and the filter to the pipeline, and asks for the
    # documents that the answer came from. Returns the decoded reply.
    def ask(http, question, filter)
      uri = URI("#{BASE_URL}/v1/pipelines/#{URI.encode_uri_component(PIPELINE)}")
      request = Net::HTTP::Post.new(uri, "Content-Type" => "application/json")
      request.body = JSON.generate({ query: question, filter: filter, include_sources: true })
      response = http.request(request)
    
      # Net::HTTP treats an error status as a normal response, so check it
      # here.
      unless response.is_a?(Net::HTTPSuccess)
        raise RagError, "HTTP #{response.code}, #{error_text(response)}"
      end
    
      body = parse_object(response.body)
      unless body && body["answer"].is_a?(String)
        raise RagError, "Unexpected response: #{response.body.to_s[0, 200]}"
      end
    
      body
    end
    ```

=== "curl"

    ```bash
    # Sends the question and the filter to the pipeline, asks for the documents
    # that the answer came from, and prints the JSON reply. With
    # --fail-with-body, curl exits non-zero on an HTTP error status but still
    # prints the body, which carries the server's explanation.
    ask() {
        jq -n --arg query "$QUESTION" --argjson filter "$1" \
            '{query: $query, filter: $filter, include_sources: true}' |
            curl --silent --show-error --fail-with-body \
                --max-time "$TIMEOUT_SECONDS" \
                --header 'Content-Type: application/json' \
                --data-binary @- \
                "$RAG_SERVER_URL/v1/pipelines/$(escape "$RAG_PIPELINE")"
    }
    ```

## Showing the Answer

Each program prints the answer, and then the IDs of the sources. The sources
show that the filter worked: the filter for version 1.0 returns only
documents 1 and 2, and the filter for version 2.0 returns only documents 3
and 4. The following tabs show how each program prints a reply:

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
        // The sources are missing, rather than an empty list, when there are
        // none, so treat anything other than an array as no sources.
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
    # Prints the answer in a reply, and then the IDs of its sources. The error
    # call makes jq fail when the answer is missing or is not a string, since
    # interpolating null would print the word "null".
    show() {
        jq -er 'if (.answer | type) == "string"
                then "Answer:\n\(.answer)"
                else error("missing answer") end,
                "Sources: \((.sources // []) | map(.id // "(no id)") | join(", "))"'
    }
    ```

## Handling Errors

The main part of each program asks the question once for each version. The
program reports any failure on `stderr`, whether the server was unreachable
or replied with an error, and then exits with a non-zero status. The
following tabs show the main part of each program:

=== "Python"

    ```python
    def main() -> int:
        try:
            with httpx.Client(base_url=BASE_URL, timeout=TIMEOUT_SECONDS) as client:
                print(f"Question: {QUESTION}")
                for version in VERSIONS:
                    body = ask(client, QUESTION, build_filter(PRODUCT, version))
                    print()
                    print(f"Filter: product = {PRODUCT}, version = {version}")
                    show(body)
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
        console.log(`Question: ${question}`);
        for (const version of versions) {
          const body = await ask(question, buildFilter(product, version));
          console.log();
          console.log(`Filter: product = ${product}, version = ${version}`);
          show(body);
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
        try {
            System.out.println("Question: " + QUESTION);
            for (String version : VERSIONS) {
                JsonNode body = ask(client, QUESTION, buildFilter(PRODUCT, version));
                System.out.println();
                System.out.println(
                        "Filter: product = " + PRODUCT + ", version = " + version);
                show(body);
            }
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
        Console.WriteLine($"Question: {Question}");
        foreach (var version in versions)
        {
            var reply = await AskAsync(client, Question, BuildFilter(Product, version));
            Console.WriteLine();
            Console.WriteLine($"Filter: product = {Product}, version = {version}");
            Show(reply);
        }
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
    // run asks the question once for each version and prints the replies,
    // returning any error to the caller.
    func run() error {
    	client := &http.Client{Timeout: timeout}
    
    	fmt.Printf("Question: %s\n", question)
    	for _, version := range versions {
    		result, err := ask(client, question, buildFilter(product, version))
    		if err != nil {
    			return err
    		}
    		fmt.Println()
    		fmt.Printf("Filter: product = %s, version = %s\n", product, version)
    		show(result)
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
    /// Asks the question once for each version. The ? operator returns any
    /// error to the caller.
    fn run() -> Result<(), BoxError> {
        let client = Client::builder().timeout(TIMEOUT).build()?;
        println!("Question: {QUESTION}");
        for version in VERSIONS {
            let reply = ask(&client, QUESTION, build_filter(PRODUCT, version))?;
            println!();
            println!("Filter: product = {PRODUCT}, version = {version}");
            show(&reply);
        }
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
      Net::HTTP.start(
        uri.host, uri.port,
        use_ssl: uri.scheme == "https",
        open_timeout: TIMEOUT_SECONDS, read_timeout: TIMEOUT_SECONDS
      ) do |http|
        puts "Question: #{QUESTION}"
        VERSIONS.each do |version|
          body = ask(http, QUESTION, build_filter(PRODUCT, version))
          puts
          puts "Filter: product = #{PRODUCT}, version = #{version}"
          show(body)
        end
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
    main() {
        local version response
    
        echo "Question: $QUESTION"
        for version in "${VERSIONS[@]}"; do
            echo
            echo "Filter: product = $PRODUCT, version = $version"
            if ! response="$(ask "$(build_filter "$PRODUCT" "$version")")"; then
                echo "RAG Server error: $response" >&2
                exit 1
            fi
            show <<<"$response" || {
                echo "Unexpected response: $response" >&2
                exit 1
            }
        done
    }
    
    main
    ```

## Running the Example

The complete project for each language is available in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/rag_server/filter_results).
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
    Filtering the documents that the pgEdge RAG Server retrieves, using httpx.
    
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
    
    QUESTION = "How long does the Acme Widget take to charge?"
    
    # The product to search, and the versions to ask about in turn. The
    # question names no version, so only the filter tells the pipeline which
    # documents to use.
    PRODUCT = "Acme Widget"
    VERSIONS = ["1.0", "2.0"]
    
    # The server waits for the language model before it replies, and a small
    # model on a modest machine can take a while, so allow plenty of time.
    TIMEOUT_SECONDS = 300.0
    
    
    def build_filter(product: str, version: str) -> dict:
        """Returns the filter for a product and a version. The conditions are
        joined with AND, which is the default, and each one compares a column
        of the pipeline's table with a value. The server passes the values to
        PostgreSQL as parameters, so they need no escaping."""
        return {
            "logic": "AND",
            "conditions": [
                {"column": "product", "operator": "=", "value": product},
                {"column": "version", "operator": "=", "value": version},
            ],
        }
    
    
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
    
    
    def ask(client: httpx.Client, question: str, filter_: dict) -> dict:
        """Sends the question and the filter to the pipeline, and asks for the
        documents that the answer came from. Returns the decoded reply."""
        response = client.post(
            f"/v1/pipelines/{quote(PIPELINE, safe='')}",
            json={"query": question, "filter": filter_, "include_sources": True},
        )
        if response.is_error:
            raise RagError(f"HTTP {response.status_code}, {error_text(response)}")
    
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
    
    
    def main() -> int:
        try:
            with httpx.Client(base_url=BASE_URL, timeout=TIMEOUT_SECONDS) as client:
                print(f"Question: {QUESTION}")
                for version in VERSIONS:
                    body = ask(client, QUESTION, build_filter(PRODUCT, version))
                    print()
                    print(f"Filter: product = {PRODUCT}, version = {version}")
                    show(body)
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
     * Filtering the documents that the pgEdge RAG Server retrieves, using the
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
    
    const question = "How long does the Acme Widget take to charge?";
    
    // The product to search, and the versions to ask about in turn. The
    // question names no version, so only the filter tells the pipeline which
    // documents to use.
    const product = "Acme Widget";
    const versions = ["1.0", "2.0"];
    
    // The server waits for the language model before it replies, and a small
    // model on a modest machine can take a while, so allow plenty of time.
    const timeoutMs = 300_000;
    
    interface Condition {
      column: string;
      operator: string;
      value: string;
    }
    
    interface Filter {
      logic: "AND" | "OR";
      conditions: Condition[];
    }
    
    // Returns the filter for a product and a version. The conditions are
    // joined with AND, which is the default, and each one compares a column of
    // the pipeline's table with a value. The server passes the values to
    // PostgreSQL as parameters, so they need no escaping.
    function buildFilter(product: string, version: string): Filter {
      return {
        logic: "AND",
        conditions: [
          { column: "product", operator: "=", value: product },
          { column: "version", operator: "=", value: version },
        ],
      };
    }
    
    interface Source {
      id?: string;
      content?: string;
      score?: number;
    }
    
    interface QueryResponse {
      answer: string;
      sources?: Source[];
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
    
    // Sends the question and the filter to the pipeline, and asks for the
    // documents that the answer came from. Returns the decoded reply.
    async function ask(question: string, filter: Filter): Promise<QueryResponse> {
      const response = await fetch(
        `${baseUrl}/v1/pipelines/${encodeURIComponent(pipeline)}`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ query: question, filter, include_sources: true }),
          signal: AbortSignal.timeout(timeoutMs),
        },
      );
    
      // fetch only rejects when it cannot reach the server; an error status
      // is a normal response, so check it explicitly.
      if (!response.ok) {
        throw new Error(`HTTP ${response.status}, ${await errorText(response)}`);
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
        for (const version of versions) {
          const body = await ask(question, buildFilter(product, version));
          console.log();
          console.log(`Filter: product = ${product}, version = ${version}`);
          show(body);
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
     * Filtering the documents that the pgEdge RAG Server retrieves, using
     * java.net.http and Jackson.
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
    
        static final String QUESTION =
                "How long does the Acme Widget take to charge?";
    
        // The product to search, and the versions to ask about in turn. The
        // question names no version, so only the filter tells the pipeline
        // which documents to use.
        static final String PRODUCT = "Acme Widget";
        static final List<String> VERSIONS = List.of("1.0", "2.0");
    
        // The server waits for the language model before it replies, and a
        // small model on a modest machine can take a while, so allow plenty
        // of time.
        static final Duration TIMEOUT = Duration.ofSeconds(300);
    
        // A mapper is safe to share, so the program creates only one.
        static final ObjectMapper MAPPER = JsonMapper.builder().build();
    
        /**
         * Returns the filter for a product and a version. The conditions are
         * joined with AND, which is the default, and each one compares a column
         * of the pipeline's table with a value. The server passes the values to
         * PostgreSQL as parameters, so they need no escaping.
         */
        static ObjectNode buildFilter(String product, String version) {
            ObjectNode filter = MAPPER.createObjectNode().put("logic", "AND");
            ArrayNode conditions = filter.putArray("conditions");
            conditions.addObject()
                    .put("column", "product").put("operator", "=").put("value", product);
            conditions.addObject()
                    .put("column", "version").put("operator", "=").put("value", version);
            return filter;
        }
    
        /** Thrown when the RAG Server rejects a request or replies oddly. */
        static class RagException extends Exception {
            RagException(String message) {
                super(message);
            }
        }
    
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
         * Sends the question and the filter to the pipeline, and asks for the
         * documents that the answer came from. Returns the decoded reply.
         */
        static JsonNode ask(HttpClient client, String question, ObjectNode filter)
                throws IOException, InterruptedException, RagException {
            ObjectNode payload = MAPPER.createObjectNode();
            payload.put("query", question);
            payload.set("filter", filter);
            payload.put("include_sources", true);
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
                JsonNode body = MAPPER.readTree(response.body());
                if (body.path("answer").isString()) {
                    return body;
                }
            } catch (JacksonException e) {
                // The body is not JSON; report it below.
            }
            throw new RagException(
                    "Unexpected response: " + shorten(response.body()));
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
    
        public static void main(String[] args) {
            HttpClient client = HttpClient.newHttpClient();
            try {
                System.out.println("Question: " + QUESTION);
                for (String version : VERSIONS) {
                    JsonNode body = ask(client, QUESTION, buildFilter(PRODUCT, version));
                    System.out.println();
                    System.out.println(
                            "Filter: product = " + PRODUCT + ", version = " + version);
                    show(body);
                }
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
     * Filtering the documents that the pgEdge RAG Server retrieves, using
     * HttpClient and System.Text.Json.
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
    
    const string Question = "How long does the Acme Widget take to charge?";
    
    // The product to search, and the versions to ask about in turn. The
    // question names no version, so only the filter tells the pipeline which
    // documents to use.
    const string Product = "Acme Widget";
    string[] versions = ["1.0", "2.0"];
    
    // The server waits for the language model before it replies, and a small
    // model on a modest machine can take a while, so allow plenty of time.
    const int TimeoutSeconds = 300;
    
    // Returns the filter for a product and a version. The conditions are
    // joined with AND, which is the default, and each one compares a column of
    // the pipeline's table with a value. The server passes the values to
    // PostgreSQL as parameters, so they need no escaping.
    static JsonObject BuildFilter(string product, string version) => new()
    {
        ["logic"] = "AND",
        ["conditions"] = new JsonArray(
            new JsonObject
            {
                ["column"] = "product", ["operator"] = "=", ["value"] = product,
            },
            new JsonObject
            {
                ["column"] = "version", ["operator"] = "=", ["value"] = version,
            }),
    };
    
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
    
    // Sends the question and the filter to the pipeline, and asks for the
    // documents that the answer came from. Returns the decoded reply.
    static async Task<JsonNode> AskAsync(
        HttpClient client, string question, JsonObject filter)
    {
        var url = $"{BaseUrl()}/v1/pipelines/{Uri.EscapeDataString(Pipeline())}";
        var payload = new JsonObject
        {
            ["query"] = question,
            ["filter"] = filter,
            ["include_sources"] = true,
        };
        using var response = await client.PostAsync(url, JsonContent.Create(payload));
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
            var reply = JsonNode.Parse(body);
            if (reply?["answer"] is JsonValue answerNode &&
                answerNode.TryGetValue(out string? _))
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
    
    // Prints the answer in a reply, and then the IDs of its sources.
    static void Show(JsonNode reply)
    {
        // The sources are missing, rather than an empty list, when there are
        // none, so treat anything other than an array as no sources.
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
    
    try
    {
        // using disposes of the client, and closes its connections, when the
        // block exits, whether or not an error occurred.
        using var client = new HttpClient
        {
            Timeout = TimeSpan.FromSeconds(TimeoutSeconds),
        };
        Console.WriteLine($"Question: {Question}");
        foreach (var version in versions)
        {
            var reply = await AskAsync(client, Question, BuildFilter(Product, version));
            Console.WriteLine();
            Console.WriteLine($"Filter: product = {Product}, version = {version}");
            Show(reply);
        }
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
    // Filtering the documents that the pgEdge RAG Server retrieves, using
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
    
    const question = "How long does the Acme Widget take to charge?"
    
    // The product to search, and the versions to ask about in turn. The
    // question names no version, so only the filter tells the pipeline which
    // documents to use.
    const product = "Acme Widget"
    
    var versions = []string{"1.0", "2.0"}
    
    // The server waits for the language model before it replies, and a small
    // model on a modest machine can take a while, so allow plenty of time.
    const timeout = 300 * time.Second
    
    
    // condition compares one column of the pipeline's table with a value.
    type condition struct {
    	Column   string `json:"column"`
    	Operator string `json:"operator"`
    	Value    string `json:"value"`
    }
    
    // filter holds conditions that the server combines with Logic.
    type filter struct {
    	Logic      string      `json:"logic"`
    	Conditions []condition `json:"conditions"`
    }
    
    // buildFilter returns the filter for a product and a version. The
    // conditions are joined with AND, which is the default. The server passes
    // the values to PostgreSQL as parameters, so they need no escaping.
    func buildFilter(product, version string) filter {
    	return filter{
    		Logic: "AND",
    		Conditions: []condition{
    			{Column: "product", Operator: "=", Value: product},
    			{Column: "version", Operator: "=", Value: version},
    		},
    	}
    }
    
    
    // source is a document that the answer came from.
    type source struct {
    	ID      string  `json:"id"`
    	Content string  `json:"content"`
    	Score   float64 `json:"score"`
    }
    
    // queryResponse holds the fields of the reply that the program uses. The
    // answer is a pointer so that the program can tell a missing field from
    // an empty one.
    type queryResponse struct {
    	Answer  *string  `json:"answer"`
    	Sources []source `json:"sources"`
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
    
    // ask sends the question and the filter to the pipeline, and asks for the
    // documents that the answer came from. It returns the decoded reply.
    func ask(client *http.Client, question string, f filter) (*queryResponse, error) {
    	payload, err := json.Marshal(map[string]any{
    		"query":           question,
    		"filter":          f,
    		"include_sources": true,
    	})
    	if err != nil {
    		return nil, err
    	}
    
    	endpoint := baseURL + "/v1/pipelines/" + url.PathEscape(pipeline)
    	response, err := client.Post(endpoint, "application/json", bytes.NewReader(payload))
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
    		return nil, fmt.Errorf("HTTP %d, %s", response.StatusCode, errorText(body))
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
    
    
    // run asks the question once for each version and prints the replies,
    // returning any error to the caller.
    func run() error {
    	client := &http.Client{Timeout: timeout}
    
    	fmt.Printf("Question: %s\n", question)
    	for _, version := range versions {
    		result, err := ask(client, question, buildFilter(product, version))
    		if err != nil {
    			return err
    		}
    		fmt.Println()
    		fmt.Printf("Filter: product = %s, version = %s\n", product, version)
    		show(result)
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
    // Filtering the documents that the pgEdge RAG Server retrieves, using
    // reqwest and serde_json.
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
    
    const QUESTION: &str = "How long does the Acme Widget take to charge?";
    
    /// The product to search, and the versions to ask about in turn. The
    /// question names no version, so only the filter tells the pipeline which
    /// documents to use.
    const PRODUCT: &str = "Acme Widget";
    const VERSIONS: [&str; 2] = ["1.0", "2.0"];
    
    /// The server waits for the language model before it replies, and a small
    /// model on a modest machine can take a while, so allow plenty of time.
    const TIMEOUT: Duration = Duration::from_secs(300);
    
    /// Returns the filter for a product and a version. The conditions are
    /// joined with AND, which is the default, and each one compares a column
    /// of the pipeline's table with a value. The server passes the values to
    /// PostgreSQL as parameters, so they need no escaping.
    fn build_filter(product: &str, version: &str) -> Value {
        json!({
            "logic": "AND",
            "conditions": [
                { "column": "product", "operator": "=", "value": product },
                { "column": "version", "operator": "=", "value": version },
            ],
        })
    }
    
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
    
    /// Sends the question and the filter to the pipeline, and asks for the
    /// documents that the answer came from. Returns the decoded reply.
    fn ask(client: &Client, question: &str, filter: Value) -> Result<Value, BoxError> {
        let response = client
            .post(pipeline_url(&pipeline())?)
            .json(&json!({ "query": question, "filter": filter, "include_sources": true }))
            .send()?;
        let status = response.status();
        let body = response.text()?;
    
        // reqwest treats an error status as a normal response, so check it
        // here.
        if !status.is_success() {
            return Err(format!("HTTP {}, {}", status.as_u16(), error_text(&body)).into());
        }
    
        let reply: Value = serde_json::from_str(&body).unwrap_or(Value::Null);
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
    
    /// Asks the question once for each version. The ? operator returns any
    /// error to the caller.
    fn run() -> Result<(), BoxError> {
        let client = Client::builder().timeout(TIMEOUT).build()?;
        println!("Question: {QUESTION}");
        for version in VERSIONS {
            let reply = ask(&client, QUESTION, build_filter(PRODUCT, version))?;
            println!();
            println!("Filter: product = {PRODUCT}, version = {version}");
            show(&reply);
        }
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
    # Filtering the documents that the pgEdge RAG Server retrieves, using
    # Net::HTTP.
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
    
    QUESTION = "How long does the Acme Widget take to charge?"
    
    # The product to search, and the versions to ask about in turn. The
    # question names no version, so only the filter tells the pipeline which
    # documents to use.
    PRODUCT = "Acme Widget"
    VERSIONS = ["1.0", "2.0"].freeze
    
    # The server waits for the language model before it replies, and a small
    # model on a modest machine can take a while, so allow plenty of time.
    TIMEOUT_SECONDS = 300
    
    # Returns the filter for a product and a version. The conditions are
    # joined with AND, which is the default, and each one compares a column of
    # the pipeline's table with a value. The server passes the values to
    # PostgreSQL as parameters, so they need no escaping.
    def build_filter(product, version)
      {
        logic: "AND",
        conditions: [
          { column: "product", operator: "=", value: product },
          { column: "version", operator: "=", value: version }
        ]
      }
    end
    
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
    
    # Sends the question and the filter to the pipeline, and asks for the
    # documents that the answer came from. Returns the decoded reply.
    def ask(http, question, filter)
      uri = URI("#{BASE_URL}/v1/pipelines/#{URI.encode_uri_component(PIPELINE)}")
      request = Net::HTTP::Post.new(uri, "Content-Type" => "application/json")
      request.body = JSON.generate({ query: question, filter: filter, include_sources: true })
      response = http.request(request)
    
      # Net::HTTP treats an error status as a normal response, so check it
      # here.
      unless response.is_a?(Net::HTTPSuccess)
        raise RagError, "HTTP #{response.code}, #{error_text(response)}"
      end
    
      body = parse_object(response.body)
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
        VERSIONS.each do |version|
          body = ask(http, QUESTION, build_filter(PRODUCT, version))
          puts
          puts "Filter: product = #{PRODUCT}, version = #{version}"
          show(body)
        end
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
    # Filtering the documents that the pgEdge RAG Server retrieves, using curl
    # and jq.
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
    
    QUESTION="How long does the Acme Widget take to charge?"
    
    # The product to search, and the versions to ask about in turn. The
    # question names no version, so only the filter tells the pipeline which
    # documents to use.
    PRODUCT="Acme Widget"
    VERSIONS=("1.0" "2.0")
    
    # The server waits for the language model before it replies, and a small
    # model on a modest machine can take a while, so allow plenty of time.
    TIMEOUT_SECONDS=300
    
    # Escapes a value for use in a URL path, as the other languages do.
    escape() { jq -rn --arg value "$1" '$value | @uri'; }
    
    # Prints the filter for a product and a version as JSON. The conditions
    # are joined with AND, which is the default, and each one compares a
    # column of the pipeline's table with a value. The server passes the
    # values to PostgreSQL as parameters, so they need no escaping.
    build_filter() {
        jq -n --arg product "$1" --arg version "$2" '{
            logic: "AND",
            conditions: [
                {column: "product", operator: "=", value: $product},
                {column: "version", operator: "=", value: $version}
            ]}'
    }
    
    # Sends the question and the filter to the pipeline, asks for the documents
    # that the answer came from, and prints the JSON reply. With
    # --fail-with-body, curl exits non-zero on an HTTP error status but still
    # prints the body, which carries the server's explanation.
    ask() {
        jq -n --arg query "$QUESTION" --argjson filter "$1" \
            '{query: $query, filter: $filter, include_sources: true}' |
            curl --silent --show-error --fail-with-body \
                --max-time "$TIMEOUT_SECONDS" \
                --header 'Content-Type: application/json' \
                --data-binary @- \
                "$RAG_SERVER_URL/v1/pipelines/$(escape "$RAG_PIPELINE")"
    }
    
    # Prints the answer in a reply, and then the IDs of its sources. The error
    # call makes jq fail when the answer is missing or is not a string, since
    # interpolating null would print the word "null".
    show() {
        jq -er 'if (.answer | type) == "string"
                then "Answer:\n\(.answer)"
                else error("missing answer") end,
                "Sources: \((.sources // []) | map(.id // "(no id)") | join(", "))"'
    }
    
    main() {
        local version response
    
        echo "Question: $QUESTION"
        for version in "${VERSIONS[@]}"; do
            echo
            echo "Filter: product = $PRODUCT, version = $version"
            if ! response="$(ask "$(build_filter "$PRODUCT" "$version")")"; then
                echo "RAG Server error: $response" >&2
                exit 1
            fi
            show <<<"$response" || {
                echo "Unexpected response: $response" >&2
                exit 1
            }
        done
    }
    
    main
    
    ```

## Next Steps

The following resources provide more information about the topics in this
recipe:

- The [Asking a Question](ask_question.md) recipe shows the same request
  without a filter.
- The [Showing the Sources of an Answer](include_sources.md) recipe explains
  the `include_sources` setting in more detail.
- The
  [pgEdge RAG Server documentation](https://docs.pgedge.com/pgedge-rag-server/)
  describes the filter, and the pipeline configuration that can set a filter
  for every query.
- The [Contributing a Recipe](../contributing.md) page explains how to add
  a recipe or a language to the cookbook.
