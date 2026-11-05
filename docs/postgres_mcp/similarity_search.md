# Searching by Meaning

This recipe uses the `similarity_search` tool of a pgEdge Postgres MCP Server
to find the products whose descriptions are closest in meaning to a question,
even when they share no words with it. The server turns the question into an
embedding with the same model that made the embeddings in the table, and finds
the rows whose embeddings are nearest to it. Each step shows the code in every
supported language; selecting a language tab switches every tab on the site to
that language.

These examples are for pgEdge Postgres MCP Server 1.1.0.

The program prints the following output:

```text
Query: a gift for an amateur astronomer
Results: 3
Best match: Acme Night Sky Telescope
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

The tool searches a table that has a text column and a `vector` column of its
embeddings. The `products` table has a `description` column and a
`description_embedding` column, and the server pairs them by their names; the
server must use the same embedding model as the one that made the embeddings,
which the start script arranges.

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
    --8<-- "recipes/postgres_mcp/similarity_search/python/requirements.txt:deps"
    ```

=== "TypeScript"

    ```json
    --8<-- "recipes/postgres_mcp/similarity_search/typescript/package.json"
    ```

=== "Java"

    ```xml
    --8<-- "recipes/postgres_mcp/similarity_search/java/pom.xml:deps"
    ```

=== "C#"

    ```xml
    --8<-- "recipes/postgres_mcp/similarity_search/csharp/SimilaritySearch.csproj:deps"
    ```

=== "Go"

    ```text
    --8<-- "recipes/postgres_mcp/similarity_search/go/go.mod:deps"
    ```

=== "Rust"

    ```toml
    --8<-- "recipes/postgres_mcp/similarity_search/rust/Cargo.toml:deps"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgres_mcp/similarity_search/ruby/Gemfile:deps"
    ```

## Importing the Libraries

Each program begins by importing the HTTP client, along with any standard
library modules that it uses. The TypeScript program imports nothing, because
Node.js provides `fetch` as a global, and the curl script checks that `curl`
and `jq` are installed. The following tabs show the imports for each language:

=== "Python"

    ```python
    --8<-- "recipes/postgres_mcp/similarity_search/python/main.py:imports"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgres_mcp/similarity_search/typescript/main.ts:imports"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgres_mcp/similarity_search/java/src/main/java/Main.java:imports"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgres_mcp/similarity_search/csharp/Program.cs:imports"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgres_mcp/similarity_search/go/main.go:imports"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgres_mcp/similarity_search/rust/src/main.rs:imports"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgres_mcp/similarity_search/ruby/main.rb:imports"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/postgres_mcp/similarity_search/curl/main.sh:imports"
    ```

## Configuring the Program

The examples read their settings from the following environment variables,
and treat an empty value as unset; each program allows 90 seconds for a
reply:

| Variable    | Default                 | Description                     |
|-------------|-------------------------|---------------------------------|
| `MCP_URL`   | `http://localhost:8080` | The base URL of the MCP Server. |
| `MCP_TOKEN` | None; it must be set    | An API token for the server.    |

The server turns the question into an embedding before it searches, which can
take a while if the embedding model has to load first, so the timeout is longer
than in the other MCP Server recipes. A program calls a tool with the
`tools/call` method, giving the tool's `name` and its `arguments`, and the
server needs no `initialize` handshake first. A tool's reply is text, in the
`text` member of the first item of the result's `content` array. A tool that
fails still returns a result rather than a JSON-RPC error, with `isError` set
to `true` and the error message as its text, so the helper checks that too.

The following tabs show how each program reads its settings, and how it calls a
tool:

=== "Python"

    ```python
    --8<-- "recipes/postgres_mcp/similarity_search/python/main.py:config"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgres_mcp/similarity_search/typescript/main.ts:config"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgres_mcp/similarity_search/java/src/main/java/Main.java:config"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgres_mcp/similarity_search/csharp/Program.cs:config"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgres_mcp/similarity_search/go/main.go:config"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgres_mcp/similarity_search/rust/src/main.rs:config"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgres_mcp/similarity_search/ruby/main.rb:config"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/postgres_mcp/similarity_search/curl/main.sh:config"
    ```

## Searching

The tool takes the table in `table_name`, the question in `query_text`, and the
number of results in `top_n`. Its reply is text, with a block for each result
that starts with a line such as `Result 1/3`. The server finds the closest rows
by vector distance and then reorders them, mixing in a keyword score and
favouring variety, so the first block is not always the closest match. Each
block has a `Source` line that gives the rank from the vector search, such as
`(vector search rank: #1, chunk: 1)`, and the program picks the block ranked
first, whose text follows the next blank line. Every description starts with
the product's name and a colon. The parsing depends on the layout of the text
in version 1.1.0, so check it again after an upgrade. The following tabs show
the search:

=== "Python"

    ```python
    --8<-- "recipes/postgres_mcp/similarity_search/python/main.py:search"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgres_mcp/similarity_search/typescript/main.ts:search"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgres_mcp/similarity_search/java/src/main/java/Main.java:search"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgres_mcp/similarity_search/csharp/Program.cs:search"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgres_mcp/similarity_search/go/main.go:search"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgres_mcp/similarity_search/rust/src/main.rs:search"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgres_mcp/similarity_search/ruby/main.rb:search"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/postgres_mcp/similarity_search/curl/main.sh:search"
    ```

## Handling Errors

The main part of each program checks that a token is set, runs the search,
reports any failure on `stderr`, and exits with a non-zero status. The
following tabs show the main part of each program:

=== "Python"

    ```python
    --8<-- "recipes/postgres_mcp/similarity_search/python/main.py:main"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgres_mcp/similarity_search/typescript/main.ts:main"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgres_mcp/similarity_search/java/src/main/java/Main.java:main"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgres_mcp/similarity_search/csharp/Program.cs:main"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgres_mcp/similarity_search/go/main.go:main"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgres_mcp/similarity_search/rust/src/main.rs:main"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgres_mcp/similarity_search/ruby/main.rb:main"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/postgres_mcp/similarity_search/curl/main.sh:main"
    ```

## Running the Example

The complete project for each language is available in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/postgres_mcp/similarity_search).
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
    --8<-- "recipes/postgres_mcp/similarity_search/python/main.py"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgres_mcp/similarity_search/typescript/main.ts"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgres_mcp/similarity_search/java/src/main/java/Main.java"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgres_mcp/similarity_search/csharp/Program.cs"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgres_mcp/similarity_search/go/main.go"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgres_mcp/similarity_search/rust/src/main.rs"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgres_mcp/similarity_search/ruby/main.rb"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/postgres_mcp/similarity_search/curl/main.sh"
    ```

## Next Steps

The following resources provide more information about the topics in this
recipe:

- The [Exploring a Schema](explore_schema.md) recipe lists the tables and
  columns of a schema.
- The [Running Read-Only Queries](read_only.md) recipe runs a query, and shows
  that the server refuses to write.
- The [Calling AI DBA Workbench MCP Tools](../ai_dba_workbench/mcp_tools.md)
  recipe calls the same kind of tools through the AI DBA Workbench.
- The
  [pgEdge Postgres MCP Server documentation](https://docs.pgedge.com/pgedge-postgres-mcp-server/)
  describes every tool, resource and setting.
- The [Contributing a Recipe](../contributing.md) page explains how to add a
  recipe or a language to the cookbook.
