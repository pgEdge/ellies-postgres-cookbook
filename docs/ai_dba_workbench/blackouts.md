# Scheduling a Maintenance Blackout with the AI DBA Workbench API

This recipe shows how a program schedules a maintenance blackout for a
monitored server with the pgEdge AI DBA Workbench API, reads it back, stops it,
and deletes it. These examples are for AI DBA Workbench 1.0.0. Each step shows
the code in every supported language; selecting a language tab switches every
tab on the site to that language.

A blackout suppresses alert notifications for a server, a cluster, a group of
servers, or the whole estate while planned maintenance takes place. The example
program creates a blackout for one server that started a minute ago and ends in
an hour, reads it back, stops it early, and then deletes it. The program
deletes the blackout even when a step in the middle fails, so a failed run does
not leave alerts suppressed. The output has the following form:

```text
Created a blackout for the server (active: true)
Read the blackout back (active: true)
Stopped the blackout (active: false)
Deleted the blackout
```

## Preparing the Ingredients

The `scripts/start_workbench.sh` script in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook)
starts a test Workbench in Docker. The script creates a `cookbook` user and an
API token, registers a test PostgreSQL server as a monitored connection, and
prints the `WORKBENCH_URL`, `WORKBENCH_TOKEN`, `WORKBENCH_USERNAME`,
`WORKBENCH_PASSWORD`, and `WORKBENCH_CONNECTION_ID` values that the examples
read from the environment.

The examples need a running Workbench server that monitors at least one
PostgreSQL server, and an API token for a user that may manage blackouts. The
following table lists the HTTP client and the JSON library that each example
uses:

| Language   | HTTP client and JSON library                                   |
|------------|----------------------------------------------------------------|
| Python     | [httpx](https://www.python-httpx.org/) and the `json` module   |
| TypeScript | The `fetch` function that Node.js provides                     |
| Java       | The `java.net.http` client and [Jackson](https://github.com/FasterXML/jackson) |
| C#         | `HttpClient` and `System.Text.Json`, which are part of .NET    |
| Go         | The `net/http` and `encoding/json` standard library packages   |
| Rust       | [reqwest](https://docs.rs/reqwest) and [serde_json](https://docs.rs/serde_json) |
| Ruby       | `Net::HTTP` and `json`, which come with Ruby                   |

The curl example is a bash script that uses [jq](https://jqlang.org/) to build
the requests and read the JSON replies. The Rust example also uses
[humantime](https://docs.rs/humantime) to write the start and end times, and
[signal-hook](https://docs.rs/signal-hook) to catch signals. The following tabs
show the dependency declaration from each example project:

=== "Python"

    ```text
    --8<-- "recipes/ai_dba_workbench/blackouts/python/requirements.txt:deps"
    ```

=== "TypeScript"

    ```json
    --8<-- "recipes/ai_dba_workbench/blackouts/typescript/package.json"
    ```

=== "Java"

    ```xml
    --8<-- "recipes/ai_dba_workbench/blackouts/java/pom.xml:deps"
    ```

=== "C#"

    ```xml
    --8<-- "recipes/ai_dba_workbench/blackouts/csharp/Blackouts.csproj:deps"
    ```

=== "Go"

    ```text
    --8<-- "recipes/ai_dba_workbench/blackouts/go/go.mod:deps"
    ```

=== "Rust"

    ```toml
    --8<-- "recipes/ai_dba_workbench/blackouts/rust/Cargo.toml:deps"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/ai_dba_workbench/blackouts/ruby/Gemfile:deps"
    ```

## Importing the Libraries

Each program begins by importing the modules that it uses. The following tabs
show the imports for each language:

=== "Python"

    ```python
    --8<-- "recipes/ai_dba_workbench/blackouts/python/main.py:imports"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/ai_dba_workbench/blackouts/typescript/main.ts:imports"
    ```

=== "Java"

    ```java
    --8<-- "recipes/ai_dba_workbench/blackouts/java/src/main/java/Main.java:imports"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/ai_dba_workbench/blackouts/csharp/Program.cs:imports"
    ```

=== "Go"

    ```go
    --8<-- "recipes/ai_dba_workbench/blackouts/go/main.go:imports"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/ai_dba_workbench/blackouts/rust/src/main.rs:imports"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/ai_dba_workbench/blackouts/ruby/main.rb:imports"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/ai_dba_workbench/blackouts/curl/main.sh:imports"
    ```

## Configuring the Connection

The examples read their settings from environment variables, and treat an empty
variable as unset. The following table describes the variables that the
examples read:

| Variable                  | Description                                   |
|---------------------------|-----------------------------------------------|
| `WORKBENCH_URL`           | The base URL; default `http://localhost:8080` |
| `WORKBENCH_TOKEN`         | An API token for the Workbench.               |
| `WORKBENCH_CONNECTION_ID` | The ID of the server to put in a blackout.    |

The [Authenticating with the AI DBA Workbench API](authenticate.md) recipe
shows how to create an API token. The user that owns the token needs the
`manage_blackouts` administrative permission, which a superuser has; a token
with a restricted scope must include that permission too. The Workbench accepts
an API token for the blackout endpoints, so unlike the connection endpoints,
they need no login. The following tabs show how each program reads the settings
and stops with an error when the token or the connection ID is missing:

=== "Python"

    ```python
    --8<-- "recipes/ai_dba_workbench/blackouts/python/main.py:config"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/ai_dba_workbench/blackouts/typescript/main.ts:config"
    ```

=== "Java"

    ```java
    --8<-- "recipes/ai_dba_workbench/blackouts/java/src/main/java/Main.java:config"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/ai_dba_workbench/blackouts/csharp/Program.cs:config"
    ```

=== "Go"

    ```go
    --8<-- "recipes/ai_dba_workbench/blackouts/go/main.go:config"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/ai_dba_workbench/blackouts/rust/src/main.rs:config"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/ai_dba_workbench/blackouts/ruby/main.rb:config"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/ai_dba_workbench/blackouts/curl/main.sh:config"
    ```

## Sending Requests

Every call to the API goes through one helper function. The function adds the
`/api/v1` prefix to the path, sends the token as a `Bearer` credential in the
`Authorization` header, and sets a timeout so that a stalled server cannot hang
the program. When the server rejects a request, the function raises an error
that includes the status code and the message from the server. The following
tabs show the helper function from each program:

=== "Python"

    ```python
    --8<-- "recipes/ai_dba_workbench/blackouts/python/main.py:request"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/ai_dba_workbench/blackouts/typescript/main.ts:request"
    ```

=== "Java"

    ```java
    --8<-- "recipes/ai_dba_workbench/blackouts/java/src/main/java/Main.java:request"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/ai_dba_workbench/blackouts/csharp/Program.cs:request"
    ```

=== "Go"

    ```go
    --8<-- "recipes/ai_dba_workbench/blackouts/go/main.go:request"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/ai_dba_workbench/blackouts/rust/src/main.rs:request"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/ai_dba_workbench/blackouts/ruby/main.rb:request"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/ai_dba_workbench/blackouts/curl/main.sh:request"
    ```

## Creating the Blackout

The program creates the blackout with `POST /api/v1/blackouts`. The `scope`
field is `estate`, `group`, `cluster`, or `server`, and a `server` blackout
also needs the `connection_id` of the server. The `start_time` and `end_time`
fields are timestamps in RFC 3339 format, and the end must come after the
start. The program starts the blackout a minute in the past, so that a small
difference between the clocks of the two machines cannot leave it inactive. The
reply is the new blackout, including its `id` and an `is_active` flag. The
following tabs show how each program creates the blackout:

=== "Python"

    ```python
    --8<-- "recipes/ai_dba_workbench/blackouts/python/main.py:create"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/ai_dba_workbench/blackouts/typescript/main.ts:create"
    ```

=== "Java"

    ```java
    --8<-- "recipes/ai_dba_workbench/blackouts/java/src/main/java/Main.java:create"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/ai_dba_workbench/blackouts/csharp/Program.cs:create"
    ```

=== "Go"

    ```go
    --8<-- "recipes/ai_dba_workbench/blackouts/go/main.go:create"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/ai_dba_workbench/blackouts/rust/src/main.rs:create"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/ai_dba_workbench/blackouts/ruby/main.rb:create"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/ai_dba_workbench/blackouts/curl/main.sh:create"
    ```

## Reading the Blackout

The program reads the blackout back with `GET /api/v1/blackouts/{id}`. The
reply has the same fields as the reply to the create call, and `is_active` is
`true` while the current time lies between the start and the end. The following
tabs show how each program reads the blackout:

=== "Python"

    ```python
    --8<-- "recipes/ai_dba_workbench/blackouts/python/main.py:read"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/ai_dba_workbench/blackouts/typescript/main.ts:read"
    ```

=== "Java"

    ```java
    --8<-- "recipes/ai_dba_workbench/blackouts/java/src/main/java/Main.java:read"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/ai_dba_workbench/blackouts/csharp/Program.cs:read"
    ```

=== "Go"

    ```go
    --8<-- "recipes/ai_dba_workbench/blackouts/go/main.go:read"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/ai_dba_workbench/blackouts/rust/src/main.rs:read"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/ai_dba_workbench/blackouts/ruby/main.rb:read"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/ai_dba_workbench/blackouts/curl/main.sh:read"
    ```

## Stopping the Blackout

The program ends the blackout early with `POST /api/v1/blackouts/{id}/stop`,
which sets the end time to the current time. The reply is the stopped blackout,
and `is_active` is now `false`. The Workbench keeps a stopped blackout as a
record, and a second stop request fails with a 404 status because the blackout
is no longer in progress. The following tabs show how each program stops the
blackout:

=== "Python"

    ```python
    --8<-- "recipes/ai_dba_workbench/blackouts/python/main.py:stop"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/ai_dba_workbench/blackouts/typescript/main.ts:stop"
    ```

=== "Java"

    ```java
    --8<-- "recipes/ai_dba_workbench/blackouts/java/src/main/java/Main.java:stop"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/ai_dba_workbench/blackouts/csharp/Program.cs:stop"
    ```

=== "Go"

    ```go
    --8<-- "recipes/ai_dba_workbench/blackouts/go/main.go:stop"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/ai_dba_workbench/blackouts/rust/src/main.rs:stop"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/ai_dba_workbench/blackouts/ruby/main.rb:stop"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/ai_dba_workbench/blackouts/curl/main.sh:stop"
    ```

## Deleting the Blackout

The program removes the record with `DELETE /api/v1/blackouts/{id}`. The reply
is a short status message. The following tabs show how each program deletes the
blackout:

=== "Python"

    ```python
    --8<-- "recipes/ai_dba_workbench/blackouts/python/main.py:delete"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/ai_dba_workbench/blackouts/typescript/main.ts:delete"
    ```

=== "Java"

    ```java
    --8<-- "recipes/ai_dba_workbench/blackouts/java/src/main/java/Main.java:delete"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/ai_dba_workbench/blackouts/csharp/Program.cs:delete"
    ```

=== "Go"

    ```go
    --8<-- "recipes/ai_dba_workbench/blackouts/go/main.go:delete"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/ai_dba_workbench/blackouts/rust/src/main.rs:delete"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/ai_dba_workbench/blackouts/ruby/main.rb:delete"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/ai_dba_workbench/blackouts/curl/main.sh:delete"
    ```

## Cleaning Up After a Failure

The main part of each program deletes the blackout on every path, so that a
failure after the create call does not leave alerts suppressed for the next
hour. This includes SIGINT (Ctrl+C) and SIGTERM: each program catches both
signals, so that the default action of ending the program does not skip the
cleanup. In every program except the Java one, a signal makes the next request
that the program would send fail with an `Interrupted` error, or abandons the
request in progress (in the TypeScript, C# and Go programs), and the cleanup
then deletes the blackout. In these programs the create call and the delete
call ignore signals, so that the program never loses the ID of a blackout that
the server created, and a second signal during the cleanup does nothing. The
Python program uses a `finally` block and a signal handler, the TypeScript
program keeps the delete step in a variable that runs after the `try` block,
and the Go program returns the delete step from its `run()` function to
`main()`, which uses `signal.NotifyContext`. The C# program registers a
`PosixSignalRegistration` handler that cancels the requests in progress, the
Rust program sets a flag with signal-hook, and the Ruby program sets one with
`Signal.trap` and deletes the blackout in an `ensure` block.

Java's supported API cannot catch a signal, so the Java program registers a
shutdown hook, which the JVM runs when SIGINT or SIGTERM ends the program. The
hook deletes the blackout if the program has not already done so, and the JVM
then exits with a non-zero status. The hook and the create call share a lock,
so a signal during the create call makes the hook wait until the program has
recorded the ID of the new blackout.

The curl script cannot ignore signals during the create call, because
Ctrl+C in a terminal sends SIGINT to every process in the foreground group,
including the `curl` process that is making the request. The script instead
puts a random marker in the reason of the blackout, and sets it before the
create call. If the script ends without having read the ID from the reply, its
`EXIT` trap lists the blackouts and deletes the one whose reason contains the
marker, looking up to three times in case the server is still handling the
request. The trap ignores further signals, and treats a 404 status from the
delete call as success, because that means the blackout is already gone. Each
program reports a failure on `stderr` and exits with a non-zero status. The
following tabs show the main part of each program:

=== "Python"

    ```python
    --8<-- "recipes/ai_dba_workbench/blackouts/python/main.py:main"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/ai_dba_workbench/blackouts/typescript/main.ts:main"
    ```

=== "Java"

    ```java
    --8<-- "recipes/ai_dba_workbench/blackouts/java/src/main/java/Main.java:main"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/ai_dba_workbench/blackouts/csharp/Program.cs:main"
    ```

=== "Go"

    ```go
    --8<-- "recipes/ai_dba_workbench/blackouts/go/main.go:main"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/ai_dba_workbench/blackouts/rust/src/main.rs:main"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/ai_dba_workbench/blackouts/ruby/main.rb:main"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/ai_dba_workbench/blackouts/curl/main.sh:main"
    ```

If a run is killed without a chance to clean up (with `kill -9`, for example),
the blackout stays in place until its end time. To end it sooner, send a `POST`
request to the `stop` path of the blackout.

## Running the Example

The complete project for each language is available in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/ai_dba_workbench/blackouts).
Set `WORKBENCH_URL`, `WORKBENCH_TOKEN`, and `WORKBENCH_CONNECTION_ID` for your
server, and then run the command for your language from the corresponding
project directory. The following tabs show the commands that build and run each
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
    --8<-- "recipes/ai_dba_workbench/blackouts/python/main.py"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/ai_dba_workbench/blackouts/typescript/main.ts"
    ```

=== "Java"

    ```java
    --8<-- "recipes/ai_dba_workbench/blackouts/java/src/main/java/Main.java"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/ai_dba_workbench/blackouts/csharp/Program.cs"
    ```

=== "Go"

    ```go
    --8<-- "recipes/ai_dba_workbench/blackouts/go/main.go"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/ai_dba_workbench/blackouts/rust/src/main.rs"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/ai_dba_workbench/blackouts/ruby/main.rb"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/ai_dba_workbench/blackouts/curl/main.sh"
    ```

## Next Steps

The following resources provide more information about the topics in this
recipe:

- The [Authenticating with the AI DBA Workbench API](authenticate.md) recipe
  explains how to create the API token that these examples use.
- The
  [Listing and Acknowledging Alerts with the AI DBA Workbench API](alerts.md)
  recipe shows the alerts that a blackout suppresses.
- The AI DBA Workbench
  [blackouts guide](https://github.com/pgEdge/ai-dba-workbench/blob/v1.0.0/docs/user-guide/blackouts.md)
  describes how blackouts affect alerting.
- The AI DBA Workbench
  [API reference](https://github.com/pgEdge/ai-dba-workbench/blob/v1.0.0/docs/admin-guide/api/reference.md)
  describes every endpoint.
