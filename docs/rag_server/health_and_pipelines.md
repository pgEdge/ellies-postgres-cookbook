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
    --8<-- "recipes/rag_server/health_and_pipelines/python/requirements.txt:deps"
    ```

=== "TypeScript"

    ```json
    --8<-- "recipes/rag_server/health_and_pipelines/typescript/package.json"
    ```

=== "Java"

    ```xml
    --8<-- "recipes/rag_server/health_and_pipelines/java/pom.xml:deps"
    ```

=== "C#"

    ```xml
    --8<-- "recipes/rag_server/health_and_pipelines/csharp/HealthAndPipelines.csproj:deps"
    ```

=== "Go"

    ```text
    --8<-- "recipes/rag_server/health_and_pipelines/go/go.mod:deps"
    ```

=== "Rust"

    ```toml
    --8<-- "recipes/rag_server/health_and_pipelines/rust/Cargo.toml:deps"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/rag_server/health_and_pipelines/ruby/Gemfile:deps"
    ```

## Importing the Libraries

Each program begins by importing the HTTP client, along with any standard
library modules that it uses. The TypeScript program imports nothing, because
Node.js provides `fetch` as a global, and the curl script checks that `curl`
and `jq` are installed. The following tabs show the imports for each language:

=== "Python"

    ```python
    --8<-- "recipes/rag_server/health_and_pipelines/python/main.py:imports"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/rag_server/health_and_pipelines/typescript/main.ts:imports"
    ```

=== "Java"

    ```java
    --8<-- "recipes/rag_server/health_and_pipelines/java/src/main/java/Main.java:imports"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/rag_server/health_and_pipelines/csharp/Program.cs:imports"
    ```

=== "Go"

    ```go
    --8<-- "recipes/rag_server/health_and_pipelines/go/main.go:imports"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/rag_server/health_and_pipelines/rust/src/main.rs:imports"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/rag_server/health_and_pipelines/ruby/main.rb:imports"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/rag_server/health_and_pipelines/curl/main.sh:imports"
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
    --8<-- "recipes/rag_server/health_and_pipelines/python/main.py:config"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/rag_server/health_and_pipelines/typescript/main.ts:config"
    ```

=== "Java"

    ```java
    --8<-- "recipes/rag_server/health_and_pipelines/java/src/main/java/Main.java:config"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/rag_server/health_and_pipelines/csharp/Program.cs:config"
    ```

=== "Go"

    ```go
    --8<-- "recipes/rag_server/health_and_pipelines/go/main.go:config"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/rag_server/health_and_pipelines/rust/src/main.rs:config"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/rag_server/health_and_pipelines/ruby/main.rb:config"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/rag_server/health_and_pipelines/curl/main.sh:config"
    ```

## Checking That the Server Is Live

Each program asks the liveness endpoint first, and stops if the server does not
answer, because the other checks cannot succeed without it. The following tabs
show the liveness check:

=== "Python"

    ```python
    --8<-- "recipes/rag_server/health_and_pipelines/python/main.py:live"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/rag_server/health_and_pipelines/typescript/main.ts:live"
    ```

=== "Java"

    ```java
    --8<-- "recipes/rag_server/health_and_pipelines/java/src/main/java/Main.java:live"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/rag_server/health_and_pipelines/csharp/Program.cs:live"
    ```

=== "Go"

    ```go
    --8<-- "recipes/rag_server/health_and_pipelines/go/main.go:live"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/rag_server/health_and_pipelines/rust/src/main.rs:live"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/rag_server/health_and_pipelines/ruby/main.rb:live"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/rag_server/health_and_pipelines/curl/main.sh:live"
    ```

## Checking Health

Each program reads the overall status and the state of each provider, and
reports whether the server is healthy. The following tabs show the health
check:

=== "Python"

    ```python
    --8<-- "recipes/rag_server/health_and_pipelines/python/main.py:health"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/rag_server/health_and_pipelines/typescript/main.ts:health"
    ```

=== "Java"

    ```java
    --8<-- "recipes/rag_server/health_and_pipelines/java/src/main/java/Main.java:health"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/rag_server/health_and_pipelines/csharp/Program.cs:health"
    ```

=== "Go"

    ```go
    --8<-- "recipes/rag_server/health_and_pipelines/go/main.go:health"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/rag_server/health_and_pipelines/rust/src/main.rs:health"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/rag_server/health_and_pipelines/ruby/main.rb:health"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/rag_server/health_and_pipelines/curl/main.sh:health"
    ```

## Listing the Pipelines

Each program prints the name and description of every pipeline, which is how a
client can discover the pipelines to ask. The following tabs show how each
program lists the pipelines:

=== "Python"

    ```python
    --8<-- "recipes/rag_server/health_and_pipelines/python/main.py:pipelines"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/rag_server/health_and_pipelines/typescript/main.ts:pipelines"
    ```

=== "Java"

    ```java
    --8<-- "recipes/rag_server/health_and_pipelines/java/src/main/java/Main.java:pipelines"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/rag_server/health_and_pipelines/csharp/Program.cs:pipelines"
    ```

=== "Go"

    ```go
    --8<-- "recipes/rag_server/health_and_pipelines/go/main.go:pipelines"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/rag_server/health_and_pipelines/rust/src/main.rs:pipelines"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/rag_server/health_and_pipelines/ruby/main.rb:pipelines"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/rag_server/health_and_pipelines/curl/main.sh:pipelines"
    ```

## Handling Errors

The main part of each program runs the three checks, reports any failure on
`stderr`, and exits with a non-zero status when the server is unreachable or
degraded, so that a script can act on the result. The following tabs show the
main part of each program:

=== "Python"

    ```python
    --8<-- "recipes/rag_server/health_and_pipelines/python/main.py:main"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/rag_server/health_and_pipelines/typescript/main.ts:main"
    ```

=== "Java"

    ```java
    --8<-- "recipes/rag_server/health_and_pipelines/java/src/main/java/Main.java:main"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/rag_server/health_and_pipelines/csharp/Program.cs:main"
    ```

=== "Go"

    ```go
    --8<-- "recipes/rag_server/health_and_pipelines/go/main.go:main"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/rag_server/health_and_pipelines/rust/src/main.rs:main"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/rag_server/health_and_pipelines/ruby/main.rb:main"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/rag_server/health_and_pipelines/curl/main.sh:main"
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
    --8<-- "recipes/rag_server/health_and_pipelines/python/main.py"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/rag_server/health_and_pipelines/typescript/main.ts"
    ```

=== "Java"

    ```java
    --8<-- "recipes/rag_server/health_and_pipelines/java/src/main/java/Main.java"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/rag_server/health_and_pipelines/csharp/Program.cs"
    ```

=== "Go"

    ```go
    --8<-- "recipes/rag_server/health_and_pipelines/go/main.go"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/rag_server/health_and_pipelines/rust/src/main.rs"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/rag_server/health_and_pipelines/ruby/main.rb"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/rag_server/health_and_pipelines/curl/main.sh"
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
