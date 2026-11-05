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
    --8<-- "recipes/rag_server/filter_results/python/requirements.txt:deps"
    ```

=== "TypeScript"

    ```json
    --8<-- "recipes/rag_server/filter_results/typescript/package.json"
    ```

=== "Java"

    ```xml
    --8<-- "recipes/rag_server/filter_results/java/pom.xml:deps"
    ```

=== "C#"

    ```xml
    --8<-- "recipes/rag_server/filter_results/csharp/FilterResults.csproj:deps"
    ```

=== "Go"

    ```text
    --8<-- "recipes/rag_server/filter_results/go/go.mod:deps"
    ```

=== "Rust"

    ```toml
    --8<-- "recipes/rag_server/filter_results/rust/Cargo.toml:deps"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/rag_server/filter_results/ruby/Gemfile:deps"
    ```

## Importing the Libraries

Each program begins by importing the HTTP client, along with any standard
library modules that it uses. The TypeScript program imports nothing, and
the curl script stops at the first failed command and checks that `curl`
and `jq` are installed. The following tabs show the imports for each
language:

=== "Python"

    ```python
    --8<-- "recipes/rag_server/filter_results/python/main.py:imports"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/rag_server/filter_results/typescript/main.ts:imports"
    ```

=== "Java"

    ```java
    --8<-- "recipes/rag_server/filter_results/java/src/main/java/Main.java:imports"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/rag_server/filter_results/csharp/Program.cs:imports"
    ```

=== "Go"

    ```go
    --8<-- "recipes/rag_server/filter_results/go/main.go:imports"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/rag_server/filter_results/rust/src/main.rs:imports"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/rag_server/filter_results/ruby/main.rb:imports"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/rag_server/filter_results/curl/main.sh:imports"
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
    --8<-- "recipes/rag_server/filter_results/python/main.py:config"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/rag_server/filter_results/typescript/main.ts:config"
    ```

=== "Java"

    ```java
    --8<-- "recipes/rag_server/filter_results/java/src/main/java/Main.java:config"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/rag_server/filter_results/csharp/Program.cs:config"
    ```

=== "Go"

    ```go
    --8<-- "recipes/rag_server/filter_results/go/main.go:config"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/rag_server/filter_results/rust/src/main.rs:config"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/rag_server/filter_results/ruby/main.rb:config"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/rag_server/filter_results/curl/main.sh:config"
    ```

## Building the Filter

Each program builds the filter for a product and a version as a JSON object
with two conditions. Each program builds the object from its own data
structures, and never joins strings into JSON, so that a value containing a
quotation mark cannot break the request. The following tabs show how each
program builds the filter:

=== "Python"

    ```python
    --8<-- "recipes/rag_server/filter_results/python/main.py:filter"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/rag_server/filter_results/typescript/main.ts:filter"
    ```

=== "Java"

    ```java
    --8<-- "recipes/rag_server/filter_results/java/src/main/java/Main.java:filter"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/rag_server/filter_results/csharp/Program.cs:filter"
    ```

=== "Go"

    ```go
    --8<-- "recipes/rag_server/filter_results/go/main.go:filter"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/rag_server/filter_results/rust/src/main.rs:filter"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/rag_server/filter_results/ruby/main.rb:filter"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/rag_server/filter_results/curl/main.sh:filter"
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
    --8<-- "recipes/rag_server/filter_results/python/main.py:ask"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/rag_server/filter_results/typescript/main.ts:ask"
    ```

=== "Java"

    ```java
    --8<-- "recipes/rag_server/filter_results/java/src/main/java/Main.java:ask"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/rag_server/filter_results/csharp/Program.cs:ask"
    ```

=== "Go"

    ```go
    --8<-- "recipes/rag_server/filter_results/go/main.go:ask"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/rag_server/filter_results/rust/src/main.rs:ask"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/rag_server/filter_results/ruby/main.rb:ask"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/rag_server/filter_results/curl/main.sh:ask"
    ```

## Showing the Answer

Each program prints the answer, and then the IDs of the sources. The sources
show that the filter worked: the filter for version 1.0 returns only
documents 1 and 2, and the filter for version 2.0 returns only documents 3
and 4. The following tabs show how each program prints a reply:

=== "Python"

    ```python
    --8<-- "recipes/rag_server/filter_results/python/main.py:show"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/rag_server/filter_results/typescript/main.ts:show"
    ```

=== "Java"

    ```java
    --8<-- "recipes/rag_server/filter_results/java/src/main/java/Main.java:show"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/rag_server/filter_results/csharp/Program.cs:show"
    ```

=== "Go"

    ```go
    --8<-- "recipes/rag_server/filter_results/go/main.go:show"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/rag_server/filter_results/rust/src/main.rs:show"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/rag_server/filter_results/ruby/main.rb:show"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/rag_server/filter_results/curl/main.sh:show"
    ```

## Handling Errors

The main part of each program asks the question once for each version. The
program reports any failure on `stderr`, whether the server was unreachable
or replied with an error, and then exits with a non-zero status. The
following tabs show the main part of each program:

=== "Python"

    ```python
    --8<-- "recipes/rag_server/filter_results/python/main.py:main"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/rag_server/filter_results/typescript/main.ts:main"
    ```

=== "Java"

    ```java
    --8<-- "recipes/rag_server/filter_results/java/src/main/java/Main.java:main"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/rag_server/filter_results/csharp/Program.cs:main"
    ```

=== "Go"

    ```go
    --8<-- "recipes/rag_server/filter_results/go/main.go:main"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/rag_server/filter_results/rust/src/main.rs:main"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/rag_server/filter_results/ruby/main.rb:main"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/rag_server/filter_results/curl/main.sh:main"
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
    --8<-- "recipes/rag_server/filter_results/python/main.py"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/rag_server/filter_results/typescript/main.ts"
    ```

=== "Java"

    ```java
    --8<-- "recipes/rag_server/filter_results/java/src/main/java/Main.java"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/rag_server/filter_results/csharp/Program.cs"
    ```

=== "Go"

    ```go
    --8<-- "recipes/rag_server/filter_results/go/main.go"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/rag_server/filter_results/rust/src/main.rs"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/rag_server/filter_results/ruby/main.rb"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/rag_server/filter_results/curl/main.sh"
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
