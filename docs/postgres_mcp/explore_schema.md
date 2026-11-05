# Exploring a Schema

This recipe uses the tools of a pgEdge Postgres MCP Server to find out what a
database holds: it lists the tables in a schema with their comments, lists the
columns of one table with their types, and counts the rows that match a
condition. These are the tools that an AI assistant uses to learn about a
database before it writes a query. Each step shows the code in every supported
language; selecting a language tab switches every tab on the site to that
language.

These examples are for pgEdge Postgres MCP Server 1.1.0.

The program prints the following output:

```text
Tables in cookbook_mcp:
- products: Made-up products for the pgEdge Postgres MCP Server recipes
Columns of cookbook_mcp.products:
- category: text
- description: text
- description_embedding: vector(768)
- id: integer (primary key)
- in_stock: boolean
- name: text
- price: numeric(8,2)
Products in stock: 4
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
    --8<-- "recipes/postgres_mcp/explore_schema/python/requirements.txt:deps"
    ```

=== "TypeScript"

    ```json
    --8<-- "recipes/postgres_mcp/explore_schema/typescript/package.json"
    ```

=== "Java"

    ```xml
    --8<-- "recipes/postgres_mcp/explore_schema/java/pom.xml:deps"
    ```

=== "C#"

    ```xml
    --8<-- "recipes/postgres_mcp/explore_schema/csharp/ExploreSchema.csproj:deps"
    ```

=== "Go"

    ```text
    --8<-- "recipes/postgres_mcp/explore_schema/go/go.mod:deps"
    ```

=== "Rust"

    ```toml
    --8<-- "recipes/postgres_mcp/explore_schema/rust/Cargo.toml:deps"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgres_mcp/explore_schema/ruby/Gemfile:deps"
    ```

## Importing the Libraries

Each program begins by importing the HTTP client, along with any standard
library modules that it uses. The TypeScript program imports nothing, because
Node.js provides `fetch` as a global, and the curl script checks that `curl`
and `jq` are installed. The following tabs show the imports for each language:

=== "Python"

    ```python
    --8<-- "recipes/postgres_mcp/explore_schema/python/main.py:imports"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgres_mcp/explore_schema/typescript/main.ts:imports"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgres_mcp/explore_schema/java/src/main/java/Main.java:imports"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgres_mcp/explore_schema/csharp/Program.cs:imports"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgres_mcp/explore_schema/go/main.go:imports"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgres_mcp/explore_schema/rust/src/main.rs:imports"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgres_mcp/explore_schema/ruby/main.rb:imports"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/postgres_mcp/explore_schema/curl/main.sh:imports"
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
so the helper checks that too.

The program also names the schema and the table that it explores.

The following tabs show how each program reads its settings, and how it calls a
tool:

=== "Python"

    ```python
    --8<-- "recipes/postgres_mcp/explore_schema/python/main.py:config"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgres_mcp/explore_schema/typescript/main.ts:config"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgres_mcp/explore_schema/java/src/main/java/Main.java:config"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgres_mcp/explore_schema/csharp/Program.cs:config"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgres_mcp/explore_schema/go/main.go:config"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgres_mcp/explore_schema/rust/src/main.rs:config"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgres_mcp/explore_schema/ruby/main.rb:config"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/postgres_mcp/explore_schema/curl/main.sh:config"
    ```

## Reading the Tool Replies

The `get_schema_info` tool replies with a table as text: a line or two about
the database, then a header line and one line for each row, with the values
separated by tabs. The server writes a tab or a newline inside a value as `\t`
or `\n`, so splitting the text on them is safe. The parsing depends on the
layout of the text in version 1.1.0, so check it again after an upgrade. The
following tabs show how each program reads the table into rows:

=== "Python"

    ```python
    --8<-- "recipes/postgres_mcp/explore_schema/python/main.py:parse_tsv"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgres_mcp/explore_schema/typescript/main.ts:parse_tsv"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgres_mcp/explore_schema/java/src/main/java/Main.java:parse_tsv"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgres_mcp/explore_schema/csharp/Program.cs:parse_tsv"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgres_mcp/explore_schema/go/main.go:parse_tsv"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgres_mcp/explore_schema/rust/src/main.rs:parse_tsv"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgres_mcp/explore_schema/ruby/main.rb:parse_tsv"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/postgres_mcp/explore_schema/curl/main.sh:parse_tsv"
    ```

## Listing the Tables

With `compact` set to `true`, `get_schema_info` returns one line for each table
in the schema named by `schema_name`, with its type and its comment but without
its columns, which suits a first look at a large database. The following tabs
show how each program lists the tables:

=== "Python"

    ```python
    --8<-- "recipes/postgres_mcp/explore_schema/python/main.py:list_tables"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgres_mcp/explore_schema/typescript/main.ts:list_tables"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgres_mcp/explore_schema/java/src/main/java/Main.java:list_tables"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgres_mcp/explore_schema/csharp/Program.cs:list_tables"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgres_mcp/explore_schema/go/main.go:list_tables"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgres_mcp/explore_schema/rust/src/main.rs:list_tables"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgres_mcp/explore_schema/ruby/main.rb:list_tables"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/postgres_mcp/explore_schema/curl/main.sh:list_tables"
    ```

## Describing a Table

Given a `table_name` as well, `get_schema_info` returns one line for each
column of that table, in alphabetical order, with its data type and whether it
is part of the primary key. The following tabs show how each program lists the
columns:

=== "Python"

    ```python
    --8<-- "recipes/postgres_mcp/explore_schema/python/main.py:describe_table"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgres_mcp/explore_schema/typescript/main.ts:describe_table"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgres_mcp/explore_schema/java/src/main/java/Main.java:describe_table"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgres_mcp/explore_schema/csharp/Program.cs:describe_table"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgres_mcp/explore_schema/go/main.go:describe_table"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgres_mcp/explore_schema/rust/src/main.rs:describe_table"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgres_mcp/explore_schema/ruby/main.rb:describe_table"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/postgres_mcp/explore_schema/curl/main.sh:describe_table"
    ```

## Counting Rows

The `count_rows` tool counts the rows of a table, and its optional `where`
argument is a condition without the `WHERE` keyword; the server rejects a
condition that contains a subquery. The reply ends with a line such as
`Count: 4`. The following tabs show how each program counts the products in
stock:

=== "Python"

    ```python
    --8<-- "recipes/postgres_mcp/explore_schema/python/main.py:count_rows"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgres_mcp/explore_schema/typescript/main.ts:count_rows"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgres_mcp/explore_schema/java/src/main/java/Main.java:count_rows"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgres_mcp/explore_schema/csharp/Program.cs:count_rows"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgres_mcp/explore_schema/go/main.go:count_rows"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgres_mcp/explore_schema/rust/src/main.rs:count_rows"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgres_mcp/explore_schema/ruby/main.rb:count_rows"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/postgres_mcp/explore_schema/curl/main.sh:count_rows"
    ```

## Handling Errors

The main part of each program checks that a token is set, runs the three steps,
reports any failure on `stderr`, and exits with a non-zero status. The
following tabs show the main part of each program:

=== "Python"

    ```python
    --8<-- "recipes/postgres_mcp/explore_schema/python/main.py:main"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgres_mcp/explore_schema/typescript/main.ts:main"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgres_mcp/explore_schema/java/src/main/java/Main.java:main"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgres_mcp/explore_schema/csharp/Program.cs:main"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgres_mcp/explore_schema/go/main.go:main"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgres_mcp/explore_schema/rust/src/main.rs:main"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgres_mcp/explore_schema/ruby/main.rb:main"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/postgres_mcp/explore_schema/curl/main.sh:main"
    ```

## Running the Example

The complete project for each language is available in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/postgres_mcp/explore_schema).
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
    --8<-- "recipes/postgres_mcp/explore_schema/python/main.py"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgres_mcp/explore_schema/typescript/main.ts"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgres_mcp/explore_schema/java/src/main/java/Main.java"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgres_mcp/explore_schema/csharp/Program.cs"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgres_mcp/explore_schema/go/main.go"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgres_mcp/explore_schema/rust/src/main.rs"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgres_mcp/explore_schema/ruby/main.rb"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/postgres_mcp/explore_schema/curl/main.sh"
    ```

## Next Steps

The following resources provide more information about the topics in this
recipe:

- The [Running Read-Only Queries](read_only.md) recipe runs a query, and shows
  that the server refuses to write.
- The [Searching by Meaning](similarity_search.md) recipe finds the rows whose
  text is closest in meaning to a question.
- The [Calling AI DBA Workbench MCP Tools](../ai_dba_workbench/mcp_tools.md)
  recipe calls the same kind of tools through the AI DBA Workbench.
- The
  [pgEdge Postgres MCP Server documentation](https://docs.pgedge.com/pgedge-postgres-mcp-server/)
  describes every tool, resource and setting.
- The [Contributing a Recipe](../contributing.md) page explains how to add a
  recipe or a language to the cookbook.
