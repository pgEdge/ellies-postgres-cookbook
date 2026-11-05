# Connecting to the MCP Server

This recipe connects to a pgEdge Postgres MCP Server in the way that any MCP
client does: it checks that the server is running, introduces itself with the
`initialize` handshake, and shows what the server does with a token that it
does not know. The checks suit a deployment script, or a first test of a new
server and token. Each step shows the code in every supported language;
selecting a language tab switches every tab on the site to that language.

These examples are for pgEdge Postgres MCP Server 1.1.0.

The program prints the following output:

```text
Health: ok
Server: pgedge-postgres-mcp 1.1.0
Protocol version: 2025-06-18
Wrong token: HTTP 401, Invalid or unknown token
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
    --8<-- "recipes/postgres_mcp/connect/python/requirements.txt:deps"
    ```

=== "TypeScript"

    ```json
    --8<-- "recipes/postgres_mcp/connect/typescript/package.json"
    ```

=== "Java"

    ```xml
    --8<-- "recipes/postgres_mcp/connect/java/pom.xml:deps"
    ```

=== "C#"

    ```xml
    --8<-- "recipes/postgres_mcp/connect/csharp/Connect.csproj:deps"
    ```

=== "Go"

    ```text
    --8<-- "recipes/postgres_mcp/connect/go/go.mod:deps"
    ```

=== "Rust"

    ```toml
    --8<-- "recipes/postgres_mcp/connect/rust/Cargo.toml:deps"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgres_mcp/connect/ruby/Gemfile:deps"
    ```

## Importing the Libraries

Each program begins by importing the HTTP client, along with any standard
library modules that it uses. The TypeScript program imports nothing, because
Node.js provides `fetch` as a global, and the curl script checks that `curl`
and `jq` are installed. The following tabs show the imports for each language:

=== "Python"

    ```python
    --8<-- "recipes/postgres_mcp/connect/python/main.py:imports"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgres_mcp/connect/typescript/main.ts:imports"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgres_mcp/connect/java/src/main/java/Main.java:imports"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgres_mcp/connect/csharp/Program.cs:imports"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgres_mcp/connect/go/main.go:imports"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgres_mcp/connect/rust/src/main.rs:imports"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgres_mcp/connect/ruby/main.rb:imports"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/postgres_mcp/connect/curl/main.sh:imports"
    ```

## Configuring the Program

The examples read their settings from the following environment variables,
and treat an empty value as unset; each program allows 30 seconds for a
reply:

| Variable    | Default                 | Description                     |
|-------------|-------------------------|---------------------------------|
| `MCP_URL`   | `http://localhost:8080` | The base URL of the MCP Server. |
| `MCP_TOKEN` | None; it must be set    | An API token for the server.    |

The `post` helper sends any JSON-RPC message with a given token, which lets the
program send a wrong token later, and the `rpc` helper sends a request with the
configured token and returns its result.

The following tabs show how each program reads its settings, and how it sends a
request to the server:

=== "Python"

    ```python
    --8<-- "recipes/postgres_mcp/connect/python/main.py:config"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgres_mcp/connect/typescript/main.ts:config"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgres_mcp/connect/java/src/main/java/Main.java:config"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgres_mcp/connect/csharp/Program.cs:config"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgres_mcp/connect/go/main.go:config"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgres_mcp/connect/rust/src/main.rs:config"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgres_mcp/connect/ruby/main.rb:config"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/postgres_mcp/connect/curl/main.sh:config"
    ```

## Checking That the Server Is Running

The `/health` endpoint takes a `GET` request without a token, and replies with
a JSON object whose `status` is `ok` while the server runs. Each program stops
if the server does not answer, because the other steps cannot succeed without
it. The following tabs show the health check:

=== "Python"

    ```python
    --8<-- "recipes/postgres_mcp/connect/python/main.py:health"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgres_mcp/connect/typescript/main.ts:health"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgres_mcp/connect/java/src/main/java/Main.java:health"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgres_mcp/connect/csharp/Program.cs:health"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgres_mcp/connect/go/main.go:health"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgres_mcp/connect/rust/src/main.rs:health"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgres_mcp/connect/ruby/main.rb:health"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/postgres_mcp/connect/curl/main.sh:health"
    ```

## Introducing the Client

An MCP client starts a session with the `initialize` method, which gives the
protocol revision that the client wants, the client's capabilities, and its
name and version. The server replies with its own name and version and the
revision that it has chosen; version 1.1.0 supports the revisions `2024-11-05`,
`2025-03-26`, `2025-06-18` and `2025-11-25`, and answers a revision that it
does not know with one that it does, so a client must check the answer. The
client then sends the `notifications/initialized` notification, which has no
`id`, and the server replies with HTTP 202 and no body. The following tabs show
the handshake:

=== "Python"

    ```python
    --8<-- "recipes/postgres_mcp/connect/python/main.py:initialize"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgres_mcp/connect/typescript/main.ts:initialize"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgres_mcp/connect/java/src/main/java/Main.java:initialize"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgres_mcp/connect/csharp/Program.cs:initialize"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgres_mcp/connect/go/main.go:initialize"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgres_mcp/connect/rust/src/main.rs:initialize"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgres_mcp/connect/ruby/main.rb:initialize"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/postgres_mcp/connect/curl/main.sh:initialize"
    ```

## Sending a Wrong Token

The server rejects a token that it does not know with HTTP 401 and a JSON
object with an `error` member, which is not a JSON-RPC reply. Each program
sends a made-up token, and stops if the server does not reject it. The
following tabs show the request:

=== "Python"

    ```python
    --8<-- "recipes/postgres_mcp/connect/python/main.py:wrong_token"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgres_mcp/connect/typescript/main.ts:wrong_token"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgres_mcp/connect/java/src/main/java/Main.java:wrong_token"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgres_mcp/connect/csharp/Program.cs:wrong_token"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgres_mcp/connect/go/main.go:wrong_token"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgres_mcp/connect/rust/src/main.rs:wrong_token"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgres_mcp/connect/ruby/main.rb:wrong_token"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/postgres_mcp/connect/curl/main.sh:wrong_token"
    ```

## Handling Errors

The main part of each program checks that a token is set, runs the three steps,
reports any failure on `stderr`, and exits with a non-zero status, so that a
script can act on the result. The following tabs show the main part of each
program:

=== "Python"

    ```python
    --8<-- "recipes/postgres_mcp/connect/python/main.py:main"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgres_mcp/connect/typescript/main.ts:main"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgres_mcp/connect/java/src/main/java/Main.java:main"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgres_mcp/connect/csharp/Program.cs:main"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgres_mcp/connect/go/main.go:main"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgres_mcp/connect/rust/src/main.rs:main"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgres_mcp/connect/ruby/main.rb:main"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/postgres_mcp/connect/curl/main.sh:main"
    ```

## Running the Example

The complete project for each language is available in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/postgres_mcp/connect).
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
    --8<-- "recipes/postgres_mcp/connect/python/main.py"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgres_mcp/connect/typescript/main.ts"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgres_mcp/connect/java/src/main/java/Main.java"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgres_mcp/connect/csharp/Program.cs"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgres_mcp/connect/go/main.go"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgres_mcp/connect/rust/src/main.rs"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgres_mcp/connect/ruby/main.rb"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/postgres_mcp/connect/curl/main.sh"
    ```

## Next Steps

The following resources provide more information about the topics in this
recipe:

- The [Exploring a Schema](explore_schema.md) recipe lists the tables and
  columns of a schema.
- The [Reading Resources and Prompts](resources_and_prompts.md) recipe reads
  the resources and prompts that the server offers.
- The [Calling AI DBA Workbench MCP Tools](../ai_dba_workbench/mcp_tools.md)
  recipe calls the same kind of tools through the AI DBA Workbench.
- The
  [pgEdge Postgres MCP Server documentation](https://docs.pgedge.com/pgedge-postgres-mcp-server/)
  describes every tool, resource and setting.
- The [Contributing a Recipe](../contributing.md) page explains how to add a
  recipe or a language to the cookbook.
