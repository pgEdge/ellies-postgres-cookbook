# Limiting Answers per User

This recipe asks a pgEdge RAG Server pipeline the same question on behalf of
two different people, and shows that each of them gets an answer built only
from the rows that PostgreSQL row-level security lets that person see. It also
shows that a request with no identity is refused. Each step shows the code in
every supported language; selecting a language tab switches every tab on the
site to that language.

These examples are for pgEdge RAG Server 2.0.0.

The wording of the answers varies from run to run, because a language model
writes them, but the output has the following shape:

```text
Question: What is the status of my warranty claim?

Caller: jane.doe@example.com
Answer:
Your warranty claim has been approved.
Sources: 1, 2

Caller: john.smith@example.com
Answer:
Your warranty claim was declined.
Sources: 3, 4

Caller: (no identity)
IDENTITY_REQUIRED (HTTP 401)
```

## Preparing the Ingredients

The examples assume a running RAG Server that has per-request identity turned
on, and a pipeline named `cookbook_private` that reads a table of fictional
documents, each owned by one of two made-up people. The
`scripts/start_rag_server.sh --identity` command in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook)
creates the table, the policy, and the database role, loads the documents, and
starts the server in Docker. The role has no password, because the test server
uses trust authentication, which accepts any connection without checking one.
Do not copy that into a real deployment: give the role a password, or a client
certificate, store it in your secrets manager, and use a PostgreSQL
authentication method that checks it, such as `scram-sha-256`.

The RAG Server can run each search as the person who asked, so that PostgreSQL
decides which rows the person may read. This depends on four things, and the
first two live in the database. The pipeline connects as a role that is not a
superuser, does not have `BYPASSRLS`, and does not own the table, because any
of those would let the role skip the policy. The table has row-level security
turned on, with a `SELECT` policy that reads the claims that the server passes
in the `request.jwt.claims` setting. The following example shows the policy
that the start script creates, which lets a person read only the rows whose
`owner` matches the `sub` claim:

```sql
ALTER TABLE cookbook_rag_private ENABLE ROW LEVEL SECURITY;

CREATE POLICY own_rows ON cookbook_rag_private FOR SELECT
  USING (owner = current_setting('request.jwt.claims', true)::json
                 ->> 'sub');
```

The third thing is the server configuration. Identity is a server-wide setting,
in a top-level `identity` block of the configuration file, and not a field of a
request, so every query to that server needs an identity once it is on. The
block lists the addresses of the proxies that the server trusts to supply the
identity, and the server checks at start-up that the policy and the role are
set up as described above, and refuses to start if they are not. The following
example shows the block that the start script writes:

```yaml
identity:
  enabled: true
  trusted_proxies:
    - 127.0.0.0/8
    - 10.0.0.0/8
    - 172.16.0.0/12
    - 192.168.0.0/16
```

The fourth thing is the request. A trusted proxy, such as the gateway that
authenticates the people who use your application, adds the claims of the
authenticated person to each request in the `X-Forwarded-Claims` header, as a
JSON object. The `X-Forwarded-User` header can carry a bare subject instead.
The server does not check these headers itself, apart from the address of the
peer that sent them, so a proxy that you control must remove any such header
that arrives from outside and set its own; if clients can reach the server
directly, any of them can claim to be anyone. The programs in this recipe play
the part of the proxy, to show the effect. Run the server on a private
interface that only the proxy can reach, and not on a public one, because any
host that can connect to it from a trusted address can claim any identity. The
demonstration value of `trusted_proxies` above covers every private address
range (RFC 1918) so that it works in Docker; in a real deployment, list only
the address of your proxy.

Because the identity is server-wide, this recipe needs its own server, apart
from the one that the other RAG Server recipes use. Set `RAG_SERVER_URL` to the
address of the server that has identity turned on. The following table lists
the HTTP client that each example uses:

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
    --8<-- "recipes/rag_server/row_level_security/python/requirements.txt:deps"
    ```

=== "TypeScript"

    ```json
    --8<-- "recipes/rag_server/row_level_security/typescript/package.json"
    ```

=== "Java"

    ```xml
    --8<-- "recipes/rag_server/row_level_security/java/pom.xml:deps"
    ```

=== "C#"

    ```xml
    --8<-- "recipes/rag_server/row_level_security/csharp/RowLevelSecurity.csproj:deps"
    ```

=== "Go"

    ```text
    --8<-- "recipes/rag_server/row_level_security/go/go.mod:deps"
    ```

=== "Rust"

    ```toml
    --8<-- "recipes/rag_server/row_level_security/rust/Cargo.toml:deps"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/rag_server/row_level_security/ruby/Gemfile:deps"
    ```

## Importing the Libraries

Each program begins by importing the HTTP client, along with any standard
library modules that it uses. The TypeScript program imports nothing, because
Node.js provides `fetch` as a global, and the curl script checks that `curl`
and `jq` are installed. The following tabs show the imports for each language:

=== "Python"

    ```python
    --8<-- "recipes/rag_server/row_level_security/python/main.py:imports"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/rag_server/row_level_security/typescript/main.ts:imports"
    ```

=== "Java"

    ```java
    --8<-- "recipes/rag_server/row_level_security/java/src/main/java/Main.java:imports"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/rag_server/row_level_security/csharp/Program.cs:imports"
    ```

=== "Go"

    ```go
    --8<-- "recipes/rag_server/row_level_security/go/main.go:imports"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/rag_server/row_level_security/rust/src/main.rs:imports"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/rag_server/row_level_security/ruby/main.rb:imports"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/rag_server/row_level_security/curl/main.sh:imports"
    ```

## Configuring the Program

The examples read the address of the RAG Server from the `RAG_SERVER_URL`
environment variable, and treat an empty value as unset. The `RAG_PIPELINE`
variable names the pipeline. The program also holds the question, the two
made-up callers, and the name of the header, and allows 300 seconds for each
reply, because a small model on a modest machine can take a while to write an
answer. The following table describes the environment variables:

| Variable         | Default                 | Description                      |
|------------------|-------------------------|----------------------------------|
| `RAG_SERVER_URL` | `http://localhost:8080` | The base URL of the RAG Server.  |
| `RAG_PIPELINE`   | `cookbook_private` | The name of the pipeline to ask. |

The following tabs show how each program reads its settings:

=== "Python"

    ```python
    --8<-- "recipes/rag_server/row_level_security/python/main.py:config"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/rag_server/row_level_security/typescript/main.ts:config"
    ```

=== "Java"

    ```java
    --8<-- "recipes/rag_server/row_level_security/java/src/main/java/Main.java:config"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/rag_server/row_level_security/csharp/Program.cs:config"
    ```

=== "Go"

    ```go
    --8<-- "recipes/rag_server/row_level_security/go/main.go:config"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/rag_server/row_level_security/rust/src/main.rs:config"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/rag_server/row_level_security/ruby/main.rb:config"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/rag_server/row_level_security/curl/main.sh:config"
    ```

## Asking on Behalf of a Caller

Each program sends the question in a `POST` request with `include_sources` set
to true, and adds the claims header when it has a caller. It builds the claims
as a JSON object with its own JSON encoder, and never joins strings, so that an
unusual subject cannot break the header. The RAG Server reports a failure with
an HTTP error status and a JSON body that holds an error code and a message,
and the programs keep the status, the code, and the message. The following tabs
show how each program asks:

=== "Python"

    ```python
    --8<-- "recipes/rag_server/row_level_security/python/main.py:ask"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/rag_server/row_level_security/typescript/main.ts:ask"
    ```

=== "Java"

    ```java
    --8<-- "recipes/rag_server/row_level_security/java/src/main/java/Main.java:ask"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/rag_server/row_level_security/csharp/Program.cs:ask"
    ```

=== "Go"

    ```go
    --8<-- "recipes/rag_server/row_level_security/go/main.go:ask"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/rag_server/row_level_security/rust/src/main.rs:ask"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/rag_server/row_level_security/ruby/main.rb:ask"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/rag_server/row_level_security/curl/main.sh:ask"
    ```

## Showing the Answer

Each program prints the answer, and then the IDs of the sources. The sources
show the effect of the policy: the first caller gets only documents 1 and 2,
and the second only documents 3 and 4. The following tabs show how each program
prints a reply:

=== "Python"

    ```python
    --8<-- "recipes/rag_server/row_level_security/python/main.py:show"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/rag_server/row_level_security/typescript/main.ts:show"
    ```

=== "Java"

    ```java
    --8<-- "recipes/rag_server/row_level_security/java/src/main/java/Main.java:show"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/rag_server/row_level_security/csharp/Program.cs:show"
    ```

=== "Go"

    ```go
    --8<-- "recipes/rag_server/row_level_security/go/main.go:show"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/rag_server/row_level_security/rust/src/main.rs:show"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/rag_server/row_level_security/ruby/main.rb:show"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/rag_server/row_level_security/curl/main.sh:show"
    ```

## Handling Errors

The main part of each program asks the question as each caller, and then asks
without an identity, which the server must refuse with the `IDENTITY_REQUIRED`
code and HTTP status 401. The server never falls back to the database role of
the pipeline, which could read every row. The program fails if the server
answers, or refuses for another reason. It reports any other failure on
`stderr`, and exits with a non-zero status. The following tabs show the main
part of each program:

=== "Python"

    ```python
    --8<-- "recipes/rag_server/row_level_security/python/main.py:main"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/rag_server/row_level_security/typescript/main.ts:main"
    ```

=== "Java"

    ```java
    --8<-- "recipes/rag_server/row_level_security/java/src/main/java/Main.java:main"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/rag_server/row_level_security/csharp/Program.cs:main"
    ```

=== "Go"

    ```go
    --8<-- "recipes/rag_server/row_level_security/go/main.go:main"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/rag_server/row_level_security/rust/src/main.rs:main"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/rag_server/row_level_security/ruby/main.rb:main"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/rag_server/row_level_security/curl/main.sh:main"
    ```

## Running the Example

The complete project for each language is available in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/rag_server/row_level_security).
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
    --8<-- "recipes/rag_server/row_level_security/python/main.py"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/rag_server/row_level_security/typescript/main.ts"
    ```

=== "Java"

    ```java
    --8<-- "recipes/rag_server/row_level_security/java/src/main/java/Main.java"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/rag_server/row_level_security/csharp/Program.cs"
    ```

=== "Go"

    ```go
    --8<-- "recipes/rag_server/row_level_security/go/main.go"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/rag_server/row_level_security/rust/src/main.rs"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/rag_server/row_level_security/ruby/main.rb"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/rag_server/row_level_security/curl/main.sh"
    ```

## Next Steps

The following resources provide more information about the topics in this
recipe:

- The [Showing the Sources of an Answer](include_sources.md) recipe explains
  the `include_sources` setting.
- The [Handling RAG Server Errors](handle_errors.md) recipe shows how to react
  to the error codes that the server returns.
- The
  [pgEdge RAG Server documentation](https://docs.pgedge.com/pgedge-rag-server/)
  describes the identity settings, such as `allowed_roles` and the claims
  setting name.
- The [Contributing a Recipe](../contributing.md) page explains how to add a
  recipe or a language to the cookbook.
