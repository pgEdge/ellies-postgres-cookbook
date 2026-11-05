# Following a Task

This recipe finds the task that a pgEdge Control Plane server ran to create a
database, prints the entries of its log as they appear, and then reports how
the task finished. The Control Plane runs every create, update and delete of a
database as a task in the background, so following the task is how a program
learns what the server is doing, and why a change failed. Each step shows the
code in every supported language; selecting a language tab switches every tab
on the site to that language.

These examples are for the Control Plane v0.11.0.

The program prints output like the following; the log has more entries than
are shown here, and the names and timings in them vary from run to run:

```text
Task: create
Log: refreshing current state
Log: finished refreshing current state (took 205.344792ms)
Log: creating resource common.patroni_cluster::n1
Log: finished creating resource common.patroni_cluster::n1 (took 16.625µs)
Log: creating resource database.postgres_database::n1:cookbook
Log: finished creating resource database.postgres_database::n1:cookbook (took 283.094583ms)
Status: completed
```

## Preparing the Ingredients

The examples assume a running Control Plane server with a database. The
`scripts/start_control_plane.sh` script in the [cookbook
repository](https://github.com/pgEdge/ellies-postgres-cookbook) starts a
server in Docker and creates a database with the ID `cookbook`, whose
creation task the program follows.

The program calls three endpoints, and each takes a `GET` request. The
following table describes them:

| Endpoint                                 | Description                            |
|------------------------------------------|----------------------------------------|
| `/v1/databases/{id}/tasks`               | Lists the tasks of a database.         |
| `/v1/databases/{id}/tasks/{task_id}`     | Returns a task, with its status.       |
| `/v1/databases/{id}/tasks/{task_id}/log` | Returns the entries of the task's log. |

A task has a `type`, such as `create`, and a `status`, which is `pending`,
`running`, `completed`, `failed`, `canceling`, `canceled` or `unknown`. The
reply from the log endpoint holds the `entries`, each with a `timestamp` and a
`message`, and the `last_entry_id`; passing that ID back in the
`after_entry_id` query parameter returns only the entries that came after it.

The following tabs show the dependency declaration from each example project:

=== "Python"

    ```text
    --8<-- "recipes/control_plane/track_tasks/python/requirements.txt:deps"
    ```

=== "TypeScript"

    ```json
    --8<-- "recipes/control_plane/track_tasks/typescript/package.json"
    ```

=== "Java"

    ```xml
    --8<-- "recipes/control_plane/track_tasks/java/pom.xml:deps"
    ```

=== "C#"

    ```xml
    --8<-- "recipes/control_plane/track_tasks/csharp/TrackTasks.csproj:deps"
    ```

=== "Go"

    ```text
    --8<-- "recipes/control_plane/track_tasks/go/go.mod:deps"
    ```

=== "Rust"

    ```toml
    --8<-- "recipes/control_plane/track_tasks/rust/Cargo.toml:deps"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/control_plane/track_tasks/ruby/Gemfile:deps"
    ```

## Importing the Libraries

Each program begins by importing its HTTP client and JSON library, along with
any standard library modules that it uses, and the curl script checks that
`curl` and `jq` are installed. The following tabs show the imports for each
language:

=== "Python"

    ```python
    --8<-- "recipes/control_plane/track_tasks/python/main.py:imports"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/control_plane/track_tasks/typescript/main.ts:imports"
    ```

=== "Java"

    ```java
    --8<-- "recipes/control_plane/track_tasks/java/src/main/java/Main.java:imports"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/control_plane/track_tasks/csharp/Program.cs:imports"
    ```

=== "Go"

    ```go
    --8<-- "recipes/control_plane/track_tasks/go/main.go:imports"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/control_plane/track_tasks/rust/src/main.rs:imports"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/control_plane/track_tasks/ruby/main.rb:imports"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/control_plane/track_tasks/curl/main.sh:imports"
    ```

## Configuring the Program

The examples read their settings from environment variables, and treat an
empty value as unset. Each request may take up to 30 seconds, and the program
follows a running task for up to 600 seconds, checking every five seconds. The
following table describes the environment variables:

| Variable                    | Default                 | Description                        |
|-----------------------------|-------------------------|------------------------------------|
| `CONTROL_PLANE_URL`         | `http://localhost:3000` | The base URL of the Control Plane. |
| `CONTROL_PLANE_DATABASE_ID` | `cookbook`              | The ID of the database.            |

The following tabs show how each program reads its settings, and how it fetches
a path from the server:

=== "Python"

    ```python
    --8<-- "recipes/control_plane/track_tasks/python/main.py:config"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/control_plane/track_tasks/typescript/main.ts:config"
    ```

=== "Java"

    ```java
    --8<-- "recipes/control_plane/track_tasks/java/src/main/java/Main.java:config"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/control_plane/track_tasks/csharp/Program.cs:config"
    ```

=== "Go"

    ```go
    --8<-- "recipes/control_plane/track_tasks/go/main.go:config"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/control_plane/track_tasks/rust/src/main.rs:config"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/control_plane/track_tasks/ruby/main.rb:config"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/control_plane/track_tasks/curl/main.sh:config"
    ```

## Finding the Task

Each program lists the tasks of the database, oldest first, by passing
`sort_order=asc`, and picks the first task whose type is `create`. The
following tabs show how each program finds the task:

=== "Python"

    ```python
    --8<-- "recipes/control_plane/track_tasks/python/main.py:list"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/control_plane/track_tasks/typescript/main.ts:list"
    ```

=== "Java"

    ```java
    --8<-- "recipes/control_plane/track_tasks/java/src/main/java/Main.java:list"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/control_plane/track_tasks/csharp/Program.cs:list"
    ```

=== "Go"

    ```go
    --8<-- "recipes/control_plane/track_tasks/go/main.go:list"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/control_plane/track_tasks/rust/src/main.rs:list"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/control_plane/track_tasks/ruby/main.rb:list"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/control_plane/track_tasks/curl/main.sh:list"
    ```

## Following the Log

Each program reads the status of the task and then the log entries that it
has not yet printed, and repeats both every five seconds until the status is
`completed`, `failed` or `canceled`. Reading the status before the log means
that, once the status is final, the log read after it is complete. The
following tabs show how each program follows the task:

=== "Python"

    ```python
    --8<-- "recipes/control_plane/track_tasks/python/main.py:follow"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/control_plane/track_tasks/typescript/main.ts:follow"
    ```

=== "Java"

    ```java
    --8<-- "recipes/control_plane/track_tasks/java/src/main/java/Main.java:follow"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/control_plane/track_tasks/csharp/Program.cs:follow"
    ```

=== "Go"

    ```go
    --8<-- "recipes/control_plane/track_tasks/go/main.go:follow"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/control_plane/track_tasks/rust/src/main.rs:follow"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/control_plane/track_tasks/ruby/main.rb:follow"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/control_plane/track_tasks/curl/main.sh:follow"
    ```

## Handling Errors

The main part of each program finds the task and follows it, reports any
failure on `stderr`, and exits with a non-zero status when the server is
unreachable or the task did not complete. The following tabs show the main part
of each program:

=== "Python"

    ```python
    --8<-- "recipes/control_plane/track_tasks/python/main.py:main"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/control_plane/track_tasks/typescript/main.ts:main"
    ```

=== "Java"

    ```java
    --8<-- "recipes/control_plane/track_tasks/java/src/main/java/Main.java:main"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/control_plane/track_tasks/csharp/Program.cs:main"
    ```

=== "Go"

    ```go
    --8<-- "recipes/control_plane/track_tasks/go/main.go:main"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/control_plane/track_tasks/rust/src/main.rs:main"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/control_plane/track_tasks/ruby/main.rb:main"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/control_plane/track_tasks/curl/main.sh:main"
    ```

## Running the Example

The complete project for each language is available in the [cookbook
repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/control_plane/track_tasks).
Set the environment variables for your Control Plane, and then run the command
for your language from the corresponding project directory. The following tabs
show the commands that build and run each example:

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
    --8<-- "recipes/control_plane/track_tasks/python/main.py"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/control_plane/track_tasks/typescript/main.ts"
    ```

=== "Java"

    ```java
    --8<-- "recipes/control_plane/track_tasks/java/src/main/java/Main.java"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/control_plane/track_tasks/csharp/Program.cs"
    ```

=== "Go"

    ```go
    --8<-- "recipes/control_plane/track_tasks/go/main.go"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/control_plane/track_tasks/rust/src/main.rs"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/control_plane/track_tasks/ruby/main.rb"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/control_plane/track_tasks/curl/main.sh"
    ```

## Next Steps

The following resources provide more information about the topics in this
recipe:

- The [Changing a Database's Settings](update_database.md) recipe shows how to
  start an update task and wait for it to finish.
- The [Creating a Database](create_database.md) recipe shows how to create a
  database, which starts a task like the one that this recipe follows.
- The [pgEdge Control Plane
  documentation](https://docs.pgedge.com/control-plane/v0-11/) describes every
  endpoint and setting.
- The [Contributing a Recipe](../contributing.md) page explains how to add a
  recipe or a language to the cookbook.
