# Reading Resources and Prompts

Besides tools, an MCP server can offer resources, which are documents that a
client reads by URI, and prompts, which are ready-made sets of messages that
guide a language model through a task with the server's tools. This recipe
lists both, reads the `pg://system_info` resource to find the PostgreSQL
version and whether the server allows writes, and fetches the
`explore-database` prompt. Each step shows the code in every supported
language; selecting a language tab switches every tab on the site to that
language.

These examples are for pgEdge Postgres MCP Server 1.1.0.

The program prints the following output when the server uses PostgreSQL 18:

```text
Resources: pg://system_info
PostgreSQL major version: 18
Writes allowed: false
Prompts: design-schema, diagnose-query-issue, explore-database, setup-semantic-search
explore-database: Systematic database exploration workflow
First message role: user
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
    --8<-- "recipes/postgres_mcp/resources_and_prompts/python/requirements.txt:deps"
    ```

=== "TypeScript"

    ```json
    --8<-- "recipes/postgres_mcp/resources_and_prompts/typescript/package.json"
    ```

=== "Java"

    ```xml
    --8<-- "recipes/postgres_mcp/resources_and_prompts/java/pom.xml:deps"
    ```

=== "C#"

    ```xml
    --8<-- "recipes/postgres_mcp/resources_and_prompts/csharp/ResourcesAndPrompts.csproj:deps"
    ```

=== "Go"

    ```text
    --8<-- "recipes/postgres_mcp/resources_and_prompts/go/go.mod:deps"
    ```

=== "Rust"

    ```toml
    --8<-- "recipes/postgres_mcp/resources_and_prompts/rust/Cargo.toml:deps"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgres_mcp/resources_and_prompts/ruby/Gemfile:deps"
    ```

## Importing the Libraries

Each program begins by importing the HTTP client, along with any standard
library modules that it uses. The TypeScript program imports nothing, because
Node.js provides `fetch` as a global, and the curl script checks that `curl`
and `jq` are installed. The following tabs show the imports for each language:

=== "Python"

    ```python
    --8<-- "recipes/postgres_mcp/resources_and_prompts/python/main.py:imports"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgres_mcp/resources_and_prompts/typescript/main.ts:imports"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgres_mcp/resources_and_prompts/java/src/main/java/Main.java:imports"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgres_mcp/resources_and_prompts/csharp/Program.cs:imports"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgres_mcp/resources_and_prompts/go/main.go:imports"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgres_mcp/resources_and_prompts/rust/src/main.rs:imports"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgres_mcp/resources_and_prompts/ruby/main.rb:imports"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/postgres_mcp/resources_and_prompts/curl/main.sh:imports"
    ```

## Configuring the Program

The examples read their settings from the following environment variables,
and treat an empty value as unset; each program allows 30 seconds for a
reply:

| Variable    | Default                 | Description                     |
|-------------|-------------------------|---------------------------------|
| `MCP_URL`   | `http://localhost:8080` | The base URL of the MCP Server. |
| `MCP_TOKEN` | None; it must be set    | An API token for the server.    |

The `rpc` helper sends a request and returns its result. Resources and prompts
need no `initialize` handshake first.

The following tabs show how each program reads its settings, and how it sends a
request to the server:

=== "Python"

    ```python
    --8<-- "recipes/postgres_mcp/resources_and_prompts/python/main.py:config"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgres_mcp/resources_and_prompts/typescript/main.ts:config"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgres_mcp/resources_and_prompts/java/src/main/java/Main.java:config"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgres_mcp/resources_and_prompts/csharp/Program.cs:config"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgres_mcp/resources_and_prompts/go/main.go:config"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgres_mcp/resources_and_prompts/rust/src/main.rs:config"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgres_mcp/resources_and_prompts/ruby/main.rb:config"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/postgres_mcp/resources_and_prompts/curl/main.sh:config"
    ```

## Reading a Resource

The `resources/list` method returns the URI, name, description and MIME type of
each resource, and the server sorts them by URI. The `resources/read` method
returns a resource's `contents`, whose first item holds the text;
`pg://system_info` has the MIME type `application/json`, so its text is itself
a JSON object, so each program parses it a second time. Its `version_number` is
a string such as `180006`, from which integer division by 10000 gives the major
version, and its `allow_writes` is a boolean. The following tabs show how each
program reads the resource:

=== "Python"

    ```python
    --8<-- "recipes/postgres_mcp/resources_and_prompts/python/main.py:resources"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgres_mcp/resources_and_prompts/typescript/main.ts:resources"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgres_mcp/resources_and_prompts/java/src/main/java/Main.java:resources"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgres_mcp/resources_and_prompts/csharp/Program.cs:resources"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgres_mcp/resources_and_prompts/go/main.go:resources"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgres_mcp/resources_and_prompts/rust/src/main.rs:resources"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgres_mcp/resources_and_prompts/ruby/main.rb:resources"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/postgres_mcp/resources_and_prompts/curl/main.sh:resources"
    ```

## Fetching a Prompt

The `prompts/list` method returns the name, description and arguments of each
prompt, sorted by name, and the `prompts/get` method returns a prompt's
description and messages, filled in with the `arguments` that the client gives.
The `explore-database` prompt takes no arguments. The following tabs show how
each program lists the prompts and fetches one:

=== "Python"

    ```python
    --8<-- "recipes/postgres_mcp/resources_and_prompts/python/main.py:prompts"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgres_mcp/resources_and_prompts/typescript/main.ts:prompts"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgres_mcp/resources_and_prompts/java/src/main/java/Main.java:prompts"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgres_mcp/resources_and_prompts/csharp/Program.cs:prompts"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgres_mcp/resources_and_prompts/go/main.go:prompts"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgres_mcp/resources_and_prompts/rust/src/main.rs:prompts"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgres_mcp/resources_and_prompts/ruby/main.rb:prompts"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/postgres_mcp/resources_and_prompts/curl/main.sh:prompts"
    ```

## Handling Errors

The main part of each program checks that a token is set, runs both steps,
reports any failure on `stderr`, and exits with a non-zero status. The
following tabs show the main part of each program:

=== "Python"

    ```python
    --8<-- "recipes/postgres_mcp/resources_and_prompts/python/main.py:main"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgres_mcp/resources_and_prompts/typescript/main.ts:main"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgres_mcp/resources_and_prompts/java/src/main/java/Main.java:main"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgres_mcp/resources_and_prompts/csharp/Program.cs:main"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgres_mcp/resources_and_prompts/go/main.go:main"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgres_mcp/resources_and_prompts/rust/src/main.rs:main"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgres_mcp/resources_and_prompts/ruby/main.rb:main"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/postgres_mcp/resources_and_prompts/curl/main.sh:main"
    ```

## Running the Example

The complete project for each language is available in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/postgres_mcp/resources_and_prompts).
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
    --8<-- "recipes/postgres_mcp/resources_and_prompts/python/main.py"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgres_mcp/resources_and_prompts/typescript/main.ts"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgres_mcp/resources_and_prompts/java/src/main/java/Main.java"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgres_mcp/resources_and_prompts/csharp/Program.cs"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgres_mcp/resources_and_prompts/go/main.go"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgres_mcp/resources_and_prompts/rust/src/main.rs"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgres_mcp/resources_and_prompts/ruby/main.rb"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/postgres_mcp/resources_and_prompts/curl/main.sh"
    ```

## Next Steps

The following resources provide more information about the topics in this
recipe:

- The [Connecting to the MCP Server](connect.md) recipe shows the handshake
  that an MCP client performs, and what the server does with a wrong token.
- The [Exploring a Schema](explore_schema.md) recipe lists the tables and
  columns of a schema.
- The [Calling AI DBA Workbench MCP Tools](../ai_dba_workbench/mcp_tools.md)
  recipe calls the same kind of tools through the AI DBA Workbench.
- The
  [pgEdge Postgres MCP Server documentation](https://docs.pgedge.com/pgedge-postgres-mcp-server/)
  describes every tool, resource and setting.
- The [Contributing a Recipe](../contributing.md) page explains how to add a
  recipe or a language to the cookbook.
