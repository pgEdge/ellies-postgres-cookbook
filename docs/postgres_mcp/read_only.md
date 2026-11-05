# Running Read-Only Queries

This recipe runs SQL through the `query_database` tool of a pgEdge Postgres MCP
Server: it runs a `SELECT` and prints the rows, and then tries an `INSERT` to
show that the server refuses to change the data. The server runs every query in
a read-only transaction, so PostgreSQL itself rejects a write, whatever the SQL
looks like. Each step shows the code in every supported language; selecting a
language tab switches every tab on the site to that language.

These examples are for pgEdge Postgres MCP Server 1.1.0.

The program prints the following output:

```text
Columns: name, price
Row: Acme Seedling Kit, 19.95
Row: Acme Quiet Keys, 64.25
Row: Acme Trail Runner, 89.99
INSERT rejected: Error iterating rows: ERROR: cannot execute INSERT in a read-only transaction (SQLSTATE 25006)
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
    --8<-- "recipes/postgres_mcp/read_only/python/requirements.txt:deps"
    ```

=== "TypeScript"

    ```json
    --8<-- "recipes/postgres_mcp/read_only/typescript/package.json"
    ```

=== "Java"

    ```xml
    --8<-- "recipes/postgres_mcp/read_only/java/pom.xml:deps"
    ```

=== "C#"

    ```xml
    --8<-- "recipes/postgres_mcp/read_only/csharp/ReadOnly.csproj:deps"
    ```

=== "Go"

    ```text
    --8<-- "recipes/postgres_mcp/read_only/go/go.mod:deps"
    ```

=== "Rust"

    ```toml
    --8<-- "recipes/postgres_mcp/read_only/rust/Cargo.toml:deps"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgres_mcp/read_only/ruby/Gemfile:deps"
    ```

## Importing the Libraries

Each program begins by importing the HTTP client, along with any standard
library modules that it uses. The TypeScript program imports nothing, because
Node.js provides `fetch` as a global, and the curl script checks that `curl`
and `jq` are installed. The following tabs show the imports for each language:

=== "Python"

    ```python
    --8<-- "recipes/postgres_mcp/read_only/python/main.py:imports"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgres_mcp/read_only/typescript/main.ts:imports"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgres_mcp/read_only/java/src/main/java/Main.java:imports"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgres_mcp/read_only/csharp/Program.cs:imports"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgres_mcp/read_only/go/main.go:imports"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgres_mcp/read_only/rust/src/main.rs:imports"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgres_mcp/read_only/ruby/main.rb:imports"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/postgres_mcp/read_only/curl/main.sh:imports"
    ```

## Configuring the Program

The examples read their settings from the following environment variables,
and treat an empty value as unset; each program allows 30 seconds for a
reply:

| Variable    | Default                 | Description                     |
|-------------|-------------------------|---------------------------------|
| `MCP_URL`   | `http://localhost:8080` | The base URL of the MCP Server. |
| `MCP_TOKEN` | None; it must be set    | An API token for the server.    |

A program calls a tool with the `tools/call` method, giving the tool's `name`
and its `arguments`, and the server needs no `initialize` handshake first. A
tool's reply is text, in the `text` member of the first item of the result's
`content` array. A tool that fails still returns a result rather than a
JSON-RPC error, with `isError` set to `true` and the error message as its text,
so the helper returns that flag with the text.

The following tabs show how each program reads its settings, and how it calls a
tool:

=== "Python"

    ```python
    --8<-- "recipes/postgres_mcp/read_only/python/main.py:config"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgres_mcp/read_only/typescript/main.ts:config"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgres_mcp/read_only/java/src/main/java/Main.java:config"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgres_mcp/read_only/csharp/Program.cs:config"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgres_mcp/read_only/go/main.go:config"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgres_mcp/read_only/rust/src/main.rs:config"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgres_mcp/read_only/ruby/main.rb:config"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/postgres_mcp/read_only/curl/main.sh:config"
    ```

## Running a Query

The `query_database` tool takes the SQL in its `query` argument. Its reply is
text rather than JSON: it names the database, repeats the query with a `LIMIT`
that the server adds, and then has a line that starts with `Results`, a header
line of column names, and one line for each row, with the values separated by
tabs. A tab or a newline inside a value appears as `\t` or `\n`, and a NULL as
an empty string. The program prints the part after the `Results` line, with the
tabs replaced by commas. The parsing depends on the layout of the text in
version 1.1.0, so check it again after an upgrade. The following tabs show how
each program runs the query:

=== "Python"

    ```python
    --8<-- "recipes/postgres_mcp/read_only/python/main.py:select"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgres_mcp/read_only/typescript/main.ts:select"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgres_mcp/read_only/java/src/main/java/Main.java:select"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgres_mcp/read_only/csharp/Program.cs:select"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgres_mcp/read_only/go/main.go:select"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgres_mcp/read_only/rust/src/main.rs:select"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgres_mcp/read_only/ruby/main.rb:select"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/postgres_mcp/read_only/curl/main.sh:select"
    ```

## Trying to Write

The `INSERT` reaches PostgreSQL, which refuses it with SQLSTATE `25006` because
the transaction is read-only, and the tool returns the error with `isError` set
to `true`. The `INSERT` leaves out `id`, which the table requires, so that even
a server that allows writes would refuse it rather than save a row. For that
reason, each program checks for SQLSTATE `25006` itself rather than for any
error, and fails if the write succeeds or fails for another reason. Some errors
from the tool start with the query that failed, so each program prints only
the last line of the error, which holds the message from PostgreSQL. The
following tabs show the attempt:

=== "Python"

    ```python
    --8<-- "recipes/postgres_mcp/read_only/python/main.py:insert"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgres_mcp/read_only/typescript/main.ts:insert"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgres_mcp/read_only/java/src/main/java/Main.java:insert"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgres_mcp/read_only/csharp/Program.cs:insert"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgres_mcp/read_only/go/main.go:insert"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgres_mcp/read_only/rust/src/main.rs:insert"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgres_mcp/read_only/ruby/main.rb:insert"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/postgres_mcp/read_only/curl/main.sh:insert"
    ```

## Handling Errors

The main part of each program checks that a token is set, runs both steps,
reports any failure on `stderr`, and exits with a non-zero status. The
following tabs show the main part of each program:

=== "Python"

    ```python
    --8<-- "recipes/postgres_mcp/read_only/python/main.py:main"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgres_mcp/read_only/typescript/main.ts:main"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgres_mcp/read_only/java/src/main/java/Main.java:main"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgres_mcp/read_only/csharp/Program.cs:main"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgres_mcp/read_only/go/main.go:main"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgres_mcp/read_only/rust/src/main.rs:main"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgres_mcp/read_only/ruby/main.rb:main"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/postgres_mcp/read_only/curl/main.sh:main"
    ```

## Running the Example

The complete project for each language is available in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/postgres_mcp/read_only).
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
    --8<-- "recipes/postgres_mcp/read_only/python/main.py"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgres_mcp/read_only/typescript/main.ts"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgres_mcp/read_only/java/src/main/java/Main.java"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgres_mcp/read_only/csharp/Program.cs"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgres_mcp/read_only/go/main.go"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgres_mcp/read_only/rust/src/main.rs"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgres_mcp/read_only/ruby/main.rb"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/postgres_mcp/read_only/curl/main.sh"
    ```

## Next Steps

The following resources provide more information about the topics in this
recipe:

- The [Exploring a Schema](explore_schema.md) recipe lists the tables and
  columns of a schema.
- The [Searching by Meaning](similarity_search.md) recipe finds the rows whose
  text is closest in meaning to a question.
- The [Calling AI DBA Workbench MCP Tools](../ai_dba_workbench/mcp_tools.md)
  recipe calls the same kind of tools through the AI DBA Workbench.
- The
  [pgEdge Postgres MCP Server documentation](https://docs.pgedge.com/pgedge-postgres-mcp-server/)
  describes every tool, resource and setting.
- The [Contributing a Recipe](../contributing.md) page explains how to add a
  recipe or a language to the cookbook.
