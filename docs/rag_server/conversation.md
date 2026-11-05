# Holding a Conversation

This recipe holds a short conversation with a pgEdge RAG Server pipeline, in
which the second question only makes sense with the first question and its
answer in front of it. The server keeps no conversation between requests, so
the program sends the earlier messages with each new question. Each step shows
the code in every supported language; selecting a language tab switches every
tab on the site to that language.

These examples are for pgEdge RAG Server 2.0.0.

The wording of the answers varies from run to run, because a language model
writes them, but the output has the following shape:

```text
You: How long does the Acme Widget 2.0 take to charge?
Assistant: The Acme Widget 2.0 takes ninety minutes to charge fully.
You: And how many hours does the Acme Widget run for once it is charged?
Assistant: Once charged, it runs for eighteen hours.
```

## Preparing the Ingredients

The examples assume a running RAG Server with a pipeline named `cookbook` that
holds the fictional Acme Widget support documents. The
`scripts/start_rag_server.sh` script in the [cookbook
repository](https://github.com/pgEdge/ellies-postgres-cookbook) loads those
documents and starts the server in Docker, and the [Preparing Data for the RAG
Server](prepare_data.md) recipe shows how to build such a table and pipeline
yourself.

The second question, 'And how many hours does the Acme Widget run for once it
is charged?', does not say which version of the product it means, so the model
can answer it only if it knows what the first question was about. The request
body therefore carries a `messages` list next to the `query`. Each message has
a `role` of `user` or `assistant`, and a `content` string, and the list holds
the earlier turns in order. The pipeline passes the history to the language
model, but it searches for documents using the `query` alone. A follow-up
question must therefore still name its subject, here the Acme Widget, for the
search to find the right documents, and the history only settles the details
that the question leaves out, here the version. The [Asking a
Question](ask_question.md) recipe describes the request without a history. The
following example shows the body of the second request:

```json
{
  "query": "And how many hours does the Acme Widget run for once it is charged?",
  "messages": [
    {"role": "user", "content": "How long does the Acme Widget 2.0 take to charge?"},
    {"role": "assistant", "content": "It takes ninety minutes."}
  ]
}
```

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
    --8<-- "recipes/rag_server/conversation/python/requirements.txt:deps"
    ```

=== "TypeScript"

    ```json
    --8<-- "recipes/rag_server/conversation/typescript/package.json"
    ```

=== "Java"

    ```xml
    --8<-- "recipes/rag_server/conversation/java/pom.xml:deps"
    ```

=== "C#"

    ```xml
    --8<-- "recipes/rag_server/conversation/csharp/Conversation.csproj:deps"
    ```

=== "Go"

    ```text
    --8<-- "recipes/rag_server/conversation/go/go.mod:deps"
    ```

=== "Rust"

    ```toml
    --8<-- "recipes/rag_server/conversation/rust/Cargo.toml:deps"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/rag_server/conversation/ruby/Gemfile:deps"
    ```

## Importing the Libraries

Each program begins by importing the HTTP client, along with any standard
library modules that it uses. The TypeScript program imports nothing, because
Node.js provides `fetch` as a global, and the curl script checks that `curl`
and `jq` are installed. The following tabs show the imports for each language:

=== "Python"

    ```python
    --8<-- "recipes/rag_server/conversation/python/main.py:imports"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/rag_server/conversation/typescript/main.ts:imports"
    ```

=== "Java"

    ```java
    --8<-- "recipes/rag_server/conversation/java/src/main/java/Main.java:imports"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/rag_server/conversation/csharp/Program.cs:imports"
    ```

=== "Go"

    ```go
    --8<-- "recipes/rag_server/conversation/go/main.go:imports"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/rag_server/conversation/rust/src/main.rs:imports"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/rag_server/conversation/ruby/main.rb:imports"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/rag_server/conversation/curl/main.sh:imports"
    ```

## Configuring the Program

The examples read the address of the RAG Server from the `RAG_SERVER_URL`
environment variable, and treat an empty value as unset. The `RAG_PIPELINE`
variable names the pipeline. The program also holds the two questions, and
allows 300 seconds for each reply, because a small model on a modest machine
can take a while to write an answer. The following table describes the
environment variables:

| Variable         | Default                 | Description                      |
|------------------|-------------------------|----------------------------------|
| `RAG_SERVER_URL` | `http://localhost:8080` | The base URL of the RAG Server.  |
| `RAG_PIPELINE`   | `cookbook` | The name of the pipeline to ask. |

The following tabs show how each program reads its settings:

=== "Python"

    ```python
    --8<-- "recipes/rag_server/conversation/python/main.py:config"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/rag_server/conversation/typescript/main.ts:config"
    ```

=== "Java"

    ```java
    --8<-- "recipes/rag_server/conversation/java/src/main/java/Main.java:config"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/rag_server/conversation/csharp/Program.cs:config"
    ```

=== "Go"

    ```go
    --8<-- "recipes/rag_server/conversation/go/main.go:config"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/rag_server/conversation/rust/src/main.rs:config"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/rag_server/conversation/ruby/main.rb:config"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/rag_server/conversation/curl/main.sh:config"
    ```

## Asking a Question with a History

Each program sends the question and the history in a `POST` request, and
returns the answer. The RAG Server reports a failure with an HTTP error status
and a JSON body that holds an error code and a message, and the programs print
both. The following tabs show how each program sends a question:

=== "Python"

    ```python
    --8<-- "recipes/rag_server/conversation/python/main.py:ask"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/rag_server/conversation/typescript/main.ts:ask"
    ```

=== "Java"

    ```java
    --8<-- "recipes/rag_server/conversation/java/src/main/java/Main.java:ask"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/rag_server/conversation/csharp/Program.cs:ask"
    ```

=== "Go"

    ```go
    --8<-- "recipes/rag_server/conversation/go/main.go:ask"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/rag_server/conversation/rust/src/main.rs:ask"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/rag_server/conversation/ruby/main.rb:ask"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/rag_server/conversation/curl/main.sh:ask"
    ```

## Keeping the History

After each answer, the program adds the question as a `user` message and the
answer as an `assistant` message, so that the next request carries both. The
history belongs to the client, which means that it can also trim or edit the
history to keep requests small. The following tabs show how each program asks
the questions in turn:

=== "Python"

    ```python
    --8<-- "recipes/rag_server/conversation/python/main.py:converse"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/rag_server/conversation/typescript/main.ts:converse"
    ```

=== "Java"

    ```java
    --8<-- "recipes/rag_server/conversation/java/src/main/java/Main.java:converse"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/rag_server/conversation/csharp/Program.cs:converse"
    ```

=== "Go"

    ```go
    --8<-- "recipes/rag_server/conversation/go/main.go:converse"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/rag_server/conversation/rust/src/main.rs:converse"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/rag_server/conversation/ruby/main.rb:converse"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/rag_server/conversation/curl/main.sh:converse"
    ```

## Handling Errors

The main part of each program holds the conversation, reports any failure on
`stderr`, whether the server was unreachable or replied with an error, and then
exits with a non-zero status. The following tabs show the main part of each
program:

=== "Python"

    ```python
    --8<-- "recipes/rag_server/conversation/python/main.py:main"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/rag_server/conversation/typescript/main.ts:main"
    ```

=== "Java"

    ```java
    --8<-- "recipes/rag_server/conversation/java/src/main/java/Main.java:main"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/rag_server/conversation/csharp/Program.cs:main"
    ```

=== "Go"

    ```go
    --8<-- "recipes/rag_server/conversation/go/main.go:main"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/rag_server/conversation/rust/src/main.rs:main"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/rag_server/conversation/ruby/main.rb:main"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/rag_server/conversation/curl/main.sh:main"
    ```

## Running the Example

The complete project for each language is available in the [cookbook
repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/rag_server/conversation).
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
    --8<-- "recipes/rag_server/conversation/python/main.py"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/rag_server/conversation/typescript/main.ts"
    ```

=== "Java"

    ```java
    --8<-- "recipes/rag_server/conversation/java/src/main/java/Main.java"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/rag_server/conversation/csharp/Program.cs"
    ```

=== "Go"

    ```go
    --8<-- "recipes/rag_server/conversation/go/main.go"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/rag_server/conversation/rust/src/main.rs"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/rag_server/conversation/ruby/main.rb"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/rag_server/conversation/curl/main.sh"
    ```

## Next Steps

The following resources provide more information about the topics in this
recipe:

- The [Asking a Question](ask_question.md) recipe shows a single question
  without a history.
- The [Streaming an Answer](stream_answer.md) recipe shows how to receive an
  answer as the model writes it.
- The [pgEdge RAG Server
  documentation](https://docs.pgedge.com/pgedge-rag-server/) describes every
  endpoint and setting.
- The [Contributing a Recipe](../contributing.md) page explains how to add a
  recipe or a language to the cookbook.
