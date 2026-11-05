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
    --8<-- "recipes/rag_server/handle_errors/python/requirements.txt:deps"
    ```

=== "TypeScript"

    ```json
    --8<-- "recipes/rag_server/handle_errors/typescript/package.json"
    ```

=== "Java"

    ```xml
    --8<-- "recipes/rag_server/handle_errors/java/pom.xml:deps"
    ```

=== "C#"

    ```xml
    --8<-- "recipes/rag_server/handle_errors/csharp/HandleErrors.csproj:deps"
    ```

=== "Go"

    ```text
    --8<-- "recipes/rag_server/handle_errors/go/go.mod:deps"
    ```

=== "Rust"

    ```toml
    --8<-- "recipes/rag_server/handle_errors/rust/Cargo.toml:deps"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/rag_server/handle_errors/ruby/Gemfile:deps"
    ```

## Importing the Libraries

Each program begins by importing the HTTP client, along with any standard
library modules that it uses. The TypeScript program imports nothing, because
Node.js provides `fetch` as a global, and the curl script checks that `curl`
and `jq` are installed. The following tabs show the imports for each language:

=== "Python"

    ```python
    --8<-- "recipes/rag_server/handle_errors/python/main.py:imports"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/rag_server/handle_errors/typescript/main.ts:imports"
    ```

=== "Java"

    ```java
    --8<-- "recipes/rag_server/handle_errors/java/src/main/java/Main.java:imports"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/rag_server/handle_errors/csharp/Program.cs:imports"
    ```

=== "Go"

    ```go
    --8<-- "recipes/rag_server/handle_errors/go/main.go:imports"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/rag_server/handle_errors/rust/src/main.rs:imports"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/rag_server/handle_errors/ruby/main.rb:imports"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/rag_server/handle_errors/curl/main.sh:imports"
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
    --8<-- "recipes/rag_server/handle_errors/python/main.py:config"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/rag_server/handle_errors/typescript/main.ts:config"
    ```

=== "Java"

    ```java
    --8<-- "recipes/rag_server/handle_errors/java/src/main/java/Main.java:config"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/rag_server/handle_errors/csharp/Program.cs:config"
    ```

=== "Go"

    ```go
    --8<-- "recipes/rag_server/handle_errors/go/main.go:config"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/rag_server/handle_errors/rust/src/main.rs:config"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/rag_server/handle_errors/ruby/main.rb:config"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/rag_server/handle_errors/curl/main.sh:config"
    ```

## Sending a Request and Reading the Error

Each program sends a query, and turns an error reply into an error that holds
the HTTP status, the code, and the message. A reply that is not in the expected
form, such as one from a proxy in front of the server, becomes a different
error, because it has no code to read. The following tabs show how each program
sends a query:

=== "Python"

    ```python
    --8<-- "recipes/rag_server/handle_errors/python/main.py:request"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/rag_server/handle_errors/typescript/main.ts:request"
    ```

=== "Java"

    ```java
    --8<-- "recipes/rag_server/handle_errors/java/src/main/java/Main.java:request"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/rag_server/handle_errors/csharp/Program.cs:request"
    ```

=== "Go"

    ```go
    --8<-- "recipes/rag_server/handle_errors/go/main.go:request"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/rag_server/handle_errors/rust/src/main.rs:request"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/rag_server/handle_errors/ruby/main.rb:request"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/rag_server/handle_errors/curl/main.sh:request"
    ```

## Choosing a Response

Each program branches on the error code, and not on the message, to choose its
advice. The HTTP status is the fallback for temporary failures, which a program
can retry, and a code that the program does not know gets a general message.
The following tabs show how each program chooses a response:

=== "Python"

    ```python
    --8<-- "recipes/rag_server/handle_errors/python/main.py:advise"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/rag_server/handle_errors/typescript/main.ts:advise"
    ```

=== "Java"

    ```java
    --8<-- "recipes/rag_server/handle_errors/java/src/main/java/Main.java:advise"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/rag_server/handle_errors/csharp/Program.cs:advise"
    ```

=== "Go"

    ```go
    --8<-- "recipes/rag_server/handle_errors/go/main.go:advise"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/rag_server/handle_errors/rust/src/main.rs:advise"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/rag_server/handle_errors/ruby/main.rb:advise"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/rag_server/handle_errors/curl/main.sh:advise"
    ```

## Handling Errors

The main part of each program provokes the two errors, prints how it handles
each, and fails if the server replies in any other way. It reports any other
failure on `stderr`, and exits with a non-zero status. The following tabs show
the main part of each program:

=== "Python"

    ```python
    --8<-- "recipes/rag_server/handle_errors/python/main.py:main"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/rag_server/handle_errors/typescript/main.ts:main"
    ```

=== "Java"

    ```java
    --8<-- "recipes/rag_server/handle_errors/java/src/main/java/Main.java:main"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/rag_server/handle_errors/csharp/Program.cs:main"
    ```

=== "Go"

    ```go
    --8<-- "recipes/rag_server/handle_errors/go/main.go:main"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/rag_server/handle_errors/rust/src/main.rs:main"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/rag_server/handle_errors/ruby/main.rb:main"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/rag_server/handle_errors/curl/main.sh:main"
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
    --8<-- "recipes/rag_server/handle_errors/python/main.py"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/rag_server/handle_errors/typescript/main.ts"
    ```

=== "Java"

    ```java
    --8<-- "recipes/rag_server/handle_errors/java/src/main/java/Main.java"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/rag_server/handle_errors/csharp/Program.cs"
    ```

=== "Go"

    ```go
    --8<-- "recipes/rag_server/handle_errors/go/main.go"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/rag_server/handle_errors/rust/src/main.rs"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/rag_server/handle_errors/ruby/main.rb"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/rag_server/handle_errors/curl/main.sh"
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
