# Creating a Database

This recipe asks a pgEdge Control Plane server to create a database with one
node, follows its state until the database is available, and then deletes it
again. Creating a database starts the Postgres containers on the chosen host,
so the program deletes the database on every path, after a success, after a
failure, and after Ctrl-C, and a test run leaves nothing behind. Each step
shows the code in every supported language; selecting a language tab switches
every tab on the site to that language.

These examples are for the Control Plane v0.11.0.

The program prints output like the following; the database ID ends in a random
suffix, and the number of state lines depends on how long the containers take
to start:

```text
Host: cookbook-host-1
Created database cookbook-recipe-3f9a1c
Database state: creating
Database state: available
Database is available on port 6433
Deleted database
```

## Preparing the Ingredients

The examples assume a running Control Plane server with at least one host,
and a free port on that host for the new database. The
`scripts/start_control_plane.sh` script in the [cookbook
repository](https://github.com/pgEdge/ellies-postgres-cookbook) starts a
suitable server in Docker; the [Checking the Cluster](cluster_status.md)
recipe shows how to check that its hosts are healthy.

The program calls the following endpoints:

| Endpoint                    | Description                                         |
|-----------------------------|-----------------------------------------------------|
| `GET /v1/hosts`             | Lists the hosts that can run a database node.       |
| `POST /v1/databases`        | Creates a database, and starts a task to build it.  |
| `GET /v1/databases/{id}`    | Returns the database, with its state.               |
| `DELETE /v1/databases/{id}` | Deletes a database, and starts a task to remove it. |

The client chooses the ID of a new database. An ID has between 1 and 36
characters, which are lowercase letters, digits and single hyphens, so each
program adds a random suffix to `cookbook-recipe-`. The create request
returns at once, with the database in the `creating` state, and the Control
Plane builds it in a task; the database then becomes `available`, or `failed`
if something goes wrong. The other states are `modifying`, `deleting`,
`degraded`, `restoring` and `unknown`.

The following tabs show the dependency declaration from each example project:

=== "Python"

    ```text
    --8<-- "recipes/control_plane/create_database/python/requirements.txt:deps"
    ```

=== "TypeScript"

    ```json
    --8<-- "recipes/control_plane/create_database/typescript/package.json"
    ```

=== "Java"

    ```xml
    --8<-- "recipes/control_plane/create_database/java/pom.xml:deps"
    ```

=== "C#"

    ```xml
    --8<-- "recipes/control_plane/create_database/csharp/CreateDatabase.csproj:deps"
    ```

=== "Go"

    ```text
    --8<-- "recipes/control_plane/create_database/go/go.mod:deps"
    ```

=== "Rust"

    ```toml
    --8<-- "recipes/control_plane/create_database/rust/Cargo.toml:deps"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/control_plane/create_database/ruby/Gemfile:deps"
    ```

## Importing the Libraries

Each program begins by importing its HTTP client and JSON library, along with
the standard library modules that it uses for the random suffix and for
handling Ctrl-C. The curl script checks that `curl` and `jq` are installed.
The following tabs show the imports for each language:

=== "Python"

    ```python
    --8<-- "recipes/control_plane/create_database/python/main.py:imports"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/control_plane/create_database/typescript/main.ts:imports"
    ```

=== "Java"

    ```java
    --8<-- "recipes/control_plane/create_database/java/src/main/java/Main.java:imports"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/control_plane/create_database/csharp/Program.cs:imports"
    ```

=== "Go"

    ```go
    --8<-- "recipes/control_plane/create_database/go/main.go:imports"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/control_plane/create_database/rust/src/main.rs:imports"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/control_plane/create_database/ruby/main.rb:imports"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/control_plane/create_database/curl/main.sh:imports"
    ```

## Configuring the Program

The examples read their settings from environment variables, and treat an
empty value as unset. Each request may take up to 30 seconds, and the program
waits up to 600 seconds for the database, checking every five seconds. The
following table describes the environment variables:

| Variable                    | Default                 | Description                               |
|-----------------------------|-------------------------|-------------------------------------------|
| `CONTROL_PLANE_URL`         | `http://localhost:3000` | The base URL of the Control Plane.        |
| `CONTROL_PLANE_RECIPE_PORT` | `6433`                  | A free port on the host for the database. |

The following tabs show how each program reads its settings, and how it sends
a request to the server:

=== "Python"

    ```python
    --8<-- "recipes/control_plane/create_database/python/main.py:config"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/control_plane/create_database/typescript/main.ts:config"
    ```

=== "Java"

    ```java
    --8<-- "recipes/control_plane/create_database/java/src/main/java/Main.java:config"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/control_plane/create_database/csharp/Program.cs:config"
    ```

=== "Go"

    ```go
    --8<-- "recipes/control_plane/create_database/go/main.go:config"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/control_plane/create_database/rust/src/main.rs:config"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/control_plane/create_database/ruby/main.rb:config"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/control_plane/create_database/curl/main.sh:config"
    ```

## Choosing a Host

A database places each of its nodes on one or more hosts, which run the
Postgres containers. Each program places its single node on the first host in
the cluster. The following tabs show how each program finds the host:

=== "Python"

    ```python
    --8<-- "recipes/control_plane/create_database/python/main.py:host"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/control_plane/create_database/typescript/main.ts:host"
    ```

=== "Java"

    ```java
    --8<-- "recipes/control_plane/create_database/java/src/main/java/Main.java:host"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/control_plane/create_database/csharp/Program.cs:host"
    ```

=== "Go"

    ```go
    --8<-- "recipes/control_plane/create_database/go/main.go:host"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/control_plane/create_database/rust/src/main.rs:host"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/control_plane/create_database/ruby/main.rb:host"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/control_plane/create_database/curl/main.sh:host"
    ```

## Creating the Database

The create request carries the ID and a specification of the database. Only
the database name and the nodes, each with its hosts, are required in the
specification; the program also sets the port that Postgres listens on, so
that it does not clash with another database on the host, and leaves out the
optional fields, such as the Postgres version. The following tabs show the
create request:

=== "Python"

    ```python
    --8<-- "recipes/control_plane/create_database/python/main.py:create"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/control_plane/create_database/typescript/main.ts:create"
    ```

=== "Java"

    ```java
    --8<-- "recipes/control_plane/create_database/java/src/main/java/Main.java:create"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/control_plane/create_database/csharp/Program.cs:create"
    ```

=== "Go"

    ```go
    --8<-- "recipes/control_plane/create_database/go/main.go:create"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/control_plane/create_database/rust/src/main.rs:create"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/control_plane/create_database/ruby/main.rb:create"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/control_plane/create_database/curl/main.sh:create"
    ```

## Waiting for the Database

Each program polls the database every five seconds, prints its state when the
state changes, and stops when the database is `available` or `failed`. The
`connection_info` of each instance holds the address and port that clients use.
The following tabs show the wait:

=== "Python"

    ```python
    --8<-- "recipes/control_plane/create_database/python/main.py:wait"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/control_plane/create_database/typescript/main.ts:wait"
    ```

=== "Java"

    ```java
    --8<-- "recipes/control_plane/create_database/java/src/main/java/Main.java:wait"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/control_plane/create_database/csharp/Program.cs:wait"
    ```

=== "Go"

    ```go
    --8<-- "recipes/control_plane/create_database/go/main.go:wait"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/control_plane/create_database/rust/src/main.rs:wait"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/control_plane/create_database/ruby/main.rb:wait"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/control_plane/create_database/curl/main.sh:wait"
    ```

## Deleting the Database

The delete request also starts a task, and the Control Plane answers 409
whilst another task, such as the create, is still running, so each program
repeats the request until the server accepts it. It then polls until the
database is gone, which a 404 reply shows. The cleanup ignores Ctrl-C, so that
a second interrupt cannot leave the database behind. The following tabs show
the delete:

=== "Python"

    ```python
    --8<-- "recipes/control_plane/create_database/python/main.py:delete"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/control_plane/create_database/typescript/main.ts:delete"
    ```

=== "Java"

    ```java
    --8<-- "recipes/control_plane/create_database/java/src/main/java/Main.java:delete"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/control_plane/create_database/csharp/Program.cs:delete"
    ```

=== "Go"

    ```go
    --8<-- "recipes/control_plane/create_database/go/main.go:delete"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/control_plane/create_database/rust/src/main.rs:delete"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/control_plane/create_database/ruby/main.rb:delete"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/control_plane/create_database/curl/main.sh:delete"
    ```

## Handling Errors

The main part of each program creates the database and waits for it, then
deletes it whether the example succeeded, failed, or was interrupted. Ctrl-C
and `SIGTERM` stop the example without ending the process, so that the cleanup
can run. The
program sets a flag before the create request, because the database may exist
even when no reply arrives, and clears it only if the server refuses the
request with a 4xx status, which means that it created nothing. If the delete
fails, the program names the database to delete by hand. The following tabs
show the main part of each program:

=== "Python"

    ```python
    --8<-- "recipes/control_plane/create_database/python/main.py:main"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/control_plane/create_database/typescript/main.ts:main"
    ```

=== "Java"

    ```java
    --8<-- "recipes/control_plane/create_database/java/src/main/java/Main.java:main"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/control_plane/create_database/csharp/Program.cs:main"
    ```

=== "Go"

    ```go
    --8<-- "recipes/control_plane/create_database/go/main.go:main"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/control_plane/create_database/rust/src/main.rs:main"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/control_plane/create_database/ruby/main.rb:main"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/control_plane/create_database/curl/main.sh:main"
    ```

## Running the Example

The complete project for each language is available in the [cookbook
repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/control_plane/create_database).
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
    --8<-- "recipes/control_plane/create_database/python/main.py"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/control_plane/create_database/typescript/main.ts"
    ```

=== "Java"

    ```java
    --8<-- "recipes/control_plane/create_database/java/src/main/java/Main.java"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/control_plane/create_database/csharp/Program.cs"
    ```

=== "Go"

    ```go
    --8<-- "recipes/control_plane/create_database/go/main.go"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/control_plane/create_database/rust/src/main.rs"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/control_plane/create_database/ruby/main.rb"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/control_plane/create_database/curl/main.sh"
    ```

## Next Steps

The following resources provide more information about the topics in this
recipe:

- The [Following a Task](track_tasks.md) recipe shows how to read the log of
  the task that builds a database.
- The [Connecting to a Database](connect_database.md) recipe shows how to
  connect to a database once it is available.
- The [pgEdge Control Plane
  documentation](https://docs.pgedge.com/control-plane/v0-11/) describes every
  endpoint and setting.
- The [Contributing a Recipe](../contributing.md) page explains how to add a
  recipe or a language to the cookbook.
