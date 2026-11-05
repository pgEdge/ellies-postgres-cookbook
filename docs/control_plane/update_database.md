# Changing a Database's Settings

This recipe changes a Postgres setting of a database through a pgEdge Control
Plane server, waits for the update to finish, checks the new value over a
connection to the database, and then puts the original settings back. The
Control Plane writes the Postgres configuration of the instances that it
manages, so a change to a setting goes through the database's specification in
the API. Each step shows the code in every supported language; selecting a
language tab switches every tab on the site to that language.

These examples are for the Control Plane v0.11.0.

The program prints the following output for the cookbook database:

```text
Setting work_mem to 16MB
Update completed
work_mem is now 16MB
Restored the original settings
```

## Preparing the Ingredients

The examples assume a running Control Plane server with an available database,
and a database user with the `LOGIN` attribute. The
`scripts/start_control_plane.sh` script in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook)
starts a server in Docker and creates a database with the ID `cookbook` and a
`cookbook` user, and prints the password that it generated for that user.

The program calls the following endpoints:

| Endpoint                                 | Description                                    |
|------------------------------------------|------------------------------------------------|
| `GET /v1/databases/{id}`                 | Returns the database, with its specification.  |
| `POST /v1/databases/{id}`                | Replaces the specification, and starts a task. |
| `GET /v1/databases/{id}/tasks/{task_id}` | Returns a task, with its status.               |

An update sends the whole specification of the database, in a `spec` object,
and the Control Plane changes whatever differs from the current one. Each
program therefore reads the current specification, changes one field, and
sends it back. The `postgresql_conf` object of the specification holds extra
`postgresql.conf` settings, which the Control Plane merges with the settings
that it provides itself; it is missing until a setting is first added. The
specification that the API returns leaves out the
passwords of the database users, and an update that leaves them out keeps them
unchanged.

The following table lists the PostgreSQL driver that each example uses
alongside its HTTP client:

| Language   | PostgreSQL driver                                               |
|------------|-----------------------------------------------------------------|
| Python     | [psycopg](https://www.psycopg.org/psycopg3/)                    |
| TypeScript | [node-postgres](https://node-postgres.com/)                     |
| Java       | [pgJDBC](https://jdbc.postgresql.org/)                          |
| C#         | [Npgsql](https://www.npgsql.org/)                               |
| Go         | [pgx](https://github.com/jackc/pgx)                             |
| Rust       | [rust-postgres](https://github.com/rust-postgres/rust-postgres) |
| Ruby       | [ruby-pg](https://github.com/ged/ruby-pg)                       |
| curl       | [psql](https://www.postgresql.org/docs/current/app-psql.html)   |

The following tabs show the dependency declaration from each example project:

=== "Python"

    ```text
    --8<-- "recipes/control_plane/update_database/python/requirements.txt:deps"
    ```

=== "TypeScript"

    ```json
    --8<-- "recipes/control_plane/update_database/typescript/package.json"
    ```

=== "Java"

    ```xml
    --8<-- "recipes/control_plane/update_database/java/pom.xml:deps"
    ```

=== "C#"

    ```xml
    --8<-- "recipes/control_plane/update_database/csharp/UpdateDatabase.csproj:deps"
    ```

=== "Go"

    ```text
    --8<-- "recipes/control_plane/update_database/go/go.mod:deps"
    ```

=== "Rust"

    ```toml
    --8<-- "recipes/control_plane/update_database/rust/Cargo.toml:deps"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/control_plane/update_database/ruby/Gemfile:deps"
    ```

## Importing the Libraries

Each program begins by importing its HTTP client, its JSON library and its
PostgreSQL driver, along with the standard library modules that it uses for
handling Ctrl-C. The curl script checks that `curl`, `jq` and `psql` are
installed. The following tabs show the imports for each language:

=== "Python"

    ```python
    --8<-- "recipes/control_plane/update_database/python/main.py:imports"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/control_plane/update_database/typescript/main.ts:imports"
    ```

=== "Java"

    ```java
    --8<-- "recipes/control_plane/update_database/java/src/main/java/Main.java:imports"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/control_plane/update_database/csharp/Program.cs:imports"
    ```

=== "Go"

    ```go
    --8<-- "recipes/control_plane/update_database/go/main.go:imports"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/control_plane/update_database/rust/src/main.rs:imports"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/control_plane/update_database/ruby/main.rb:imports"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/control_plane/update_database/curl/main.sh:imports"
    ```

## Configuring the Program

The examples read their settings from environment variables, and treat an
empty value as unset. Each request, and the connection to the database, may
take up to 30 seconds, and the program waits up to 600 seconds for each task,
checking every five seconds. The setting and its new value are constants in
the program. The following table describes the environment variables:

| Variable                          | Default                 | Description                        |
|-----------------------------------|-------------------------|------------------------------------|
| `CONTROL_PLANE_URL`               | `http://localhost:3000` | The base URL of the Control Plane. |
| `CONTROL_PLANE_DATABASE_ID`       | `cookbook`              | The ID of the database.            |
| `CONTROL_PLANE_DATABASE_USER`     | `cookbook`              | The database user to connect as.   |
| `CONTROL_PLANE_DATABASE_PASSWORD` | None                    | The password of the database user. |

The following tabs show how each program reads its settings, and how it sends
a request to the server:

=== "Python"

    ```python
    --8<-- "recipes/control_plane/update_database/python/main.py:config"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/control_plane/update_database/typescript/main.ts:config"
    ```

=== "Java"

    ```java
    --8<-- "recipes/control_plane/update_database/java/src/main/java/Main.java:config"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/control_plane/update_database/csharp/Program.cs:config"
    ```

=== "Go"

    ```go
    --8<-- "recipes/control_plane/update_database/go/main.go:config"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/control_plane/update_database/rust/src/main.rs:config"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/control_plane/update_database/ruby/main.rb:config"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/control_plane/update_database/curl/main.sh:config"
    ```

## Sending the Update

Each program copies the specification, adds the setting to its
`postgresql_conf` object, and posts the result. The reply carries the task
that applies the change; the work happens in that task after the reply. The
following tabs show the update:

=== "Python"

    ```python
    --8<-- "recipes/control_plane/update_database/python/main.py:update"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/control_plane/update_database/typescript/main.ts:update"
    ```

=== "Java"

    ```java
    --8<-- "recipes/control_plane/update_database/java/src/main/java/Main.java:update"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/control_plane/update_database/csharp/Program.cs:update"
    ```

=== "Go"

    ```go
    --8<-- "recipes/control_plane/update_database/go/main.go:update"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/control_plane/update_database/rust/src/main.rs:update"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/control_plane/update_database/ruby/main.rb:update"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/control_plane/update_database/curl/main.sh:update"
    ```

## Waiting for the Task

Each program polls the task every five seconds until its status is
`completed`, and treats `failed` or `canceled` as an error. A poll that gets
no reply, a 409 or a server failure is repeated until the wait runs out, rather
than ending the wait. Against the
cookbook's one-node database, each update task took about 40 seconds. The
following tabs show the wait:

=== "Python"

    ```python
    --8<-- "recipes/control_plane/update_database/python/main.py:wait"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/control_plane/update_database/typescript/main.ts:wait"
    ```

=== "Java"

    ```java
    --8<-- "recipes/control_plane/update_database/java/src/main/java/Main.java:wait"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/control_plane/update_database/csharp/Program.cs:wait"
    ```

=== "Go"

    ```go
    --8<-- "recipes/control_plane/update_database/go/main.go:wait"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/control_plane/update_database/rust/src/main.rs:wait"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/control_plane/update_database/ruby/main.rb:wait"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/control_plane/update_database/curl/main.sh:wait"
    ```

## Checking the Setting

Each program connects to the first available instance, as the
[Connecting to a Database](connect_database.md) recipe does, and reads the
current value of the setting. The following tabs show the check:

=== "Python"

    ```python
    --8<-- "recipes/control_plane/update_database/python/main.py:connect"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/control_plane/update_database/typescript/main.ts:connect"
    ```

=== "Java"

    ```java
    --8<-- "recipes/control_plane/update_database/java/src/main/java/Main.java:connect"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/control_plane/update_database/csharp/Program.cs:connect"
    ```

=== "Go"

    ```go
    --8<-- "recipes/control_plane/update_database/go/main.go:connect"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/control_plane/update_database/rust/src/main.rs:connect"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/control_plane/update_database/ruby/main.rb:connect"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/control_plane/update_database/curl/main.sh:connect"
    ```

## Restoring the Original Settings

To restore the settings, each program sends the original specification back,
without the setting, and waits for that task as well. The Control Plane
answers 409 whilst another task, such as the update, is still running on the
database, so each program repeats the request until the server accepts it, as
it does when no reply arrived or the server failed. The following tabs show
the restore:

=== "Python"

    ```python
    --8<-- "recipes/control_plane/update_database/python/main.py:restore"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/control_plane/update_database/typescript/main.ts:restore"
    ```

=== "Java"

    ```java
    --8<-- "recipes/control_plane/update_database/java/src/main/java/Main.java:restore"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/control_plane/update_database/csharp/Program.cs:restore"
    ```

=== "Go"

    ```go
    --8<-- "recipes/control_plane/update_database/go/main.go:restore"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/control_plane/update_database/rust/src/main.rs:restore"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/control_plane/update_database/ruby/main.rb:restore"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/control_plane/update_database/curl/main.sh:restore"
    ```

## Handling Errors

The main part of each program reads the original specification, sends the
update, waits for it, and checks the setting, then restores the original
settings whether the example succeeded, failed, or was interrupted. Ctrl-C and
`SIGTERM` stop the example without ending the process, so that the cleanup can
run; a signal that arrives during a step that cannot be interrupted, such as
some drivers' connection attempts, takes effect when that step returns. The
program sets a flag before the update request, because the change may
take effect even when no reply arrives, and clears it only if the server
refuses the request with a 4xx status, which means that it changed nothing.
If the restore fails, the program names the database whose settings to restore
by hand. The following tabs show the main part of each program:

=== "Python"

    ```python
    --8<-- "recipes/control_plane/update_database/python/main.py:main"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/control_plane/update_database/typescript/main.ts:main"
    ```

=== "Java"

    ```java
    --8<-- "recipes/control_plane/update_database/java/src/main/java/Main.java:main"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/control_plane/update_database/csharp/Program.cs:main"
    ```

=== "Go"

    ```go
    --8<-- "recipes/control_plane/update_database/go/main.go:main"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/control_plane/update_database/rust/src/main.rs:main"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/control_plane/update_database/ruby/main.rb:main"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/control_plane/update_database/curl/main.sh:main"
    ```

## Running the Example

The complete project for each language is available in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/control_plane/update_database).
Set the environment variables for your Control Plane and database user, and
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
    --8<-- "recipes/control_plane/update_database/python/main.py"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/control_plane/update_database/typescript/main.ts"
    ```

=== "Java"

    ```java
    --8<-- "recipes/control_plane/update_database/java/src/main/java/Main.java"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/control_plane/update_database/csharp/Program.cs"
    ```

=== "Go"

    ```go
    --8<-- "recipes/control_plane/update_database/go/main.go"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/control_plane/update_database/rust/src/main.rs"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/control_plane/update_database/ruby/main.rb"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/control_plane/update_database/curl/main.sh"
    ```

## Next Steps

The following resources provide more information about the topics in this
recipe:

- The [Following a Task](track_tasks.md) recipe shows how to read the log of a
  task, which explains why an update failed.
- The [Connecting to a Database](connect_database.md) recipe explains how to
  find the address of each instance.
- The
  [pgEdge Control Plane documentation](https://docs.pgedge.com/control-plane/v0-11/)
  describes every endpoint and setting.
- The [Contributing a Recipe](../contributing.md) page explains how to add a
  recipe or a language to the cookbook.
