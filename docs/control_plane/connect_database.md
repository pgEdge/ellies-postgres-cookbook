# Connecting to a Database

This recipe asks a pgEdge Control Plane server where a database's instances
listen, and then connects to one of them with an ordinary PostgreSQL driver.
The Control Plane chooses the address and port of each instance, so a client
that reads them from the API keeps working when a database moves or gains a
node. Each step shows the code in every supported language; selecting a
language tab switches every tab on the site to that language.

These examples are for the Control Plane v0.11.0.

The program prints the following output for the cookbook database:

```text
Connecting to node n1
Connected to database cookbook
Spock: 5.0.12
```

## Preparing the Ingredients

The examples assume a running Control Plane server with an available
database, and a database user with the `LOGIN` attribute. The
`scripts/start_control_plane.sh` script in the [cookbook
repository](https://github.com/pgEdge/ellies-postgres-cookbook) starts a
server in Docker and creates a database with the ID `cookbook` and a
`cookbook` user, and prints the password that it generated for that user.

The program reads the database with a `GET /v1/databases/{id}` request. Each
entry in the `instances` array of the reply runs one node of the database,
and has a `state`, a `node_name`, and a `connection_info` object that holds
the `addresses` and `port` that clients use. The `spec` of the database holds
its `database_name`. The Control Plane never returns a password, so the
program reads the password from the environment.

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
    --8<-- "recipes/control_plane/connect_database/python/requirements.txt:deps"
    ```

=== "TypeScript"

    ```json
    --8<-- "recipes/control_plane/connect_database/typescript/package.json"
    ```

=== "Java"

    ```xml
    --8<-- "recipes/control_plane/connect_database/java/pom.xml:deps"
    ```

=== "C#"

    ```xml
    --8<-- "recipes/control_plane/connect_database/csharp/ConnectDatabase.csproj:deps"
    ```

=== "Go"

    ```text
    --8<-- "recipes/control_plane/connect_database/go/go.mod:deps"
    ```

=== "Rust"

    ```toml
    --8<-- "recipes/control_plane/connect_database/rust/Cargo.toml:deps"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/control_plane/connect_database/ruby/Gemfile:deps"
    ```

## Importing the Libraries

Each program begins by importing its HTTP client, its JSON library and its
PostgreSQL driver. The curl script checks that `curl`, `jq` and `psql` are
installed. The following tabs show the imports for each language:

=== "Python"

    ```python
    --8<-- "recipes/control_plane/connect_database/python/main.py:imports"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/control_plane/connect_database/typescript/main.ts:imports"
    ```

=== "Java"

    ```java
    --8<-- "recipes/control_plane/connect_database/java/src/main/java/Main.java:imports"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/control_plane/connect_database/csharp/Program.cs:imports"
    ```

=== "Go"

    ```go
    --8<-- "recipes/control_plane/connect_database/go/main.go:imports"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/control_plane/connect_database/rust/src/main.rs:imports"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/control_plane/connect_database/ruby/main.rb:imports"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/control_plane/connect_database/curl/main.sh:imports"
    ```

## Configuring the Program

The examples read their settings from environment variables, and treat an
empty value as unset. Each request, and the connection to the database, may
take up to 30 seconds. The following table describes the environment
variables:

| Variable                          | Default                 | Description                        |
|-----------------------------------|-------------------------|------------------------------------|
| `CONTROL_PLANE_URL`               | `http://localhost:3000` | The base URL of the Control Plane. |
| `CONTROL_PLANE_DATABASE_ID`       | `cookbook`              | The ID of the database.            |
| `CONTROL_PLANE_DATABASE_USER`     | `cookbook`              | The database user to connect as.   |
| `CONTROL_PLANE_DATABASE_PASSWORD` | None                    | The password of the database user. |

The following tabs show how each program reads its settings, and how it fetches
a path from the server:

=== "Python"

    ```python
    --8<-- "recipes/control_plane/connect_database/python/main.py:config"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/control_plane/connect_database/typescript/main.ts:config"
    ```

=== "Java"

    ```java
    --8<-- "recipes/control_plane/connect_database/java/src/main/java/Main.java:config"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/control_plane/connect_database/csharp/Program.cs:config"
    ```

=== "Go"

    ```go
    --8<-- "recipes/control_plane/connect_database/go/main.go:config"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/control_plane/connect_database/rust/src/main.rs:config"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/control_plane/connect_database/ruby/main.rb:config"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/control_plane/connect_database/curl/main.sh:config"
    ```

## Finding an Instance

Each program reads the database and picks the first instance that is
`available` and has an address. The following tabs show how each program finds
the instance:

=== "Python"

    ```python
    --8<-- "recipes/control_plane/connect_database/python/main.py:find"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/control_plane/connect_database/typescript/main.ts:find"
    ```

=== "Java"

    ```java
    --8<-- "recipes/control_plane/connect_database/java/src/main/java/Main.java:find"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/control_plane/connect_database/csharp/Program.cs:find"
    ```

=== "Go"

    ```go
    --8<-- "recipes/control_plane/connect_database/go/main.go:find"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/control_plane/connect_database/rust/src/main.rs:find"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/control_plane/connect_database/ruby/main.rb:find"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/control_plane/connect_database/curl/main.sh:find"
    ```

## Connecting to the Instance

Each program connects to the instance with its PostgreSQL driver, then asks for
the name of the database and the version of the Spock extension, if it is
installed. The following tabs show the connection and the queries:

=== "Python"

    ```python
    --8<-- "recipes/control_plane/connect_database/python/main.py:connect"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/control_plane/connect_database/typescript/main.ts:connect"
    ```

=== "Java"

    ```java
    --8<-- "recipes/control_plane/connect_database/java/src/main/java/Main.java:connect"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/control_plane/connect_database/csharp/Program.cs:connect"
    ```

=== "Go"

    ```go
    --8<-- "recipes/control_plane/connect_database/go/main.go:connect"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/control_plane/connect_database/rust/src/main.rs:connect"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/control_plane/connect_database/ruby/main.rb:connect"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/control_plane/connect_database/curl/main.sh:connect"
    ```

## Handling Errors

The main part of each program finds the instance and then connects to it. It
reports a failure to reach the Control Plane with the prefix `Control Plane
error:` and a failure to connect or query with the prefix `Database error:`,
so that the message shows which side failed. The following tabs show the main
part of each program:

=== "Python"

    ```python
    --8<-- "recipes/control_plane/connect_database/python/main.py:main"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/control_plane/connect_database/typescript/main.ts:main"
    ```

=== "Java"

    ```java
    --8<-- "recipes/control_plane/connect_database/java/src/main/java/Main.java:main"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/control_plane/connect_database/csharp/Program.cs:main"
    ```

=== "Go"

    ```go
    --8<-- "recipes/control_plane/connect_database/go/main.go:main"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/control_plane/connect_database/rust/src/main.rs:main"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/control_plane/connect_database/ruby/main.rb:main"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/control_plane/connect_database/curl/main.sh:main"
    ```

## Running the Example

The complete project for each language is available in the [cookbook
repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/control_plane/connect_database).
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
    --8<-- "recipes/control_plane/connect_database/python/main.py"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/control_plane/connect_database/typescript/main.ts"
    ```

=== "Java"

    ```java
    --8<-- "recipes/control_plane/connect_database/java/src/main/java/Main.java"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/control_plane/connect_database/csharp/Program.cs"
    ```

=== "Go"

    ```go
    --8<-- "recipes/control_plane/connect_database/go/main.go"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/control_plane/connect_database/rust/src/main.rs"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/control_plane/connect_database/ruby/main.rb"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/control_plane/connect_database/curl/main.sh"
    ```

## Next Steps

The following resources provide more information about the topics in this
recipe:

- The [Changing a Database's Settings](update_database.md) recipe shows how to
  change a Postgres setting through the Control Plane, and check it over a
  connection.
- The [Creating a Database](create_database.md) recipe shows how to create a
  database to connect to.
- The [pgEdge Control Plane
  documentation](https://docs.pgedge.com/control-plane/v0-11/) describes every
  endpoint and setting.
- The [Contributing a Recipe](../contributing.md) page explains how to add a
  recipe or a language to the cookbook.
