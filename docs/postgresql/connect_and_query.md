# Connecting to PostgreSQL and Running a Query

This recipe demonstrates how an application connects to a PostgreSQL server
and runs a query that returns a single value. The example passes a value to
the query as a parameter, which is the safe way to send application data to
the database server. Each step shows the code in every supported language;
selecting a language tab switches every tab on the site to that language.

The example program counts the rows in the `pg_catalog.pg_type` system
catalog that describe the `int4` data type. The query always returns the
value 1 on any PostgreSQL server, which makes the output easy to verify:

```text
Number of types named 'int4': 1
```

## Preparing the Ingredients

Each example uses the most widely adopted PostgreSQL driver for its
language. The following table lists the driver that each example uses:

| Language   | Driver                                                 |
|------------|--------------------------------------------------------|
| Python     | [psycopg 3](https://www.psycopg.org/psycopg3/)         |
| TypeScript | [node-postgres](https://node-postgres.com/)            |
| Java       | [pgJDBC](https://jdbc.postgresql.org/)                 |
| C#         | [Npgsql](https://www.npgsql.org/)                      |
| Go         | [pgx](https://github.com/jackc/pgx)                    |
| Rust       | [rust-postgres](https://github.com/rust-postgres/rust-postgres) |
| Ruby       | [ruby-pg](https://github.com/ged/ruby-pg)              |
| C          | [libpq](https://www.postgresql.org/docs/current/libpq.html) |

The C example links against libpq, so the example requires the libpq
client library and headers; on Debian and Ubuntu, the `libpq-dev` package
provides both. The Ruby gem also uses libpq, and may require the same
package on platforms without a pre-built gem. The following tabs show the
dependency declaration from each example project:

=== "Python"

    ```text
    --8<-- "recipes/postgresql/connect_and_query/python/requirements.txt:deps"
    ```

=== "TypeScript"

    ```json
    --8<-- "recipes/postgresql/connect_and_query/typescript/package.json"
    ```

=== "Java"

    ```xml
    --8<-- "recipes/postgresql/connect_and_query/java/pom.xml:deps"
    ```

=== "C#"

    ```xml
    --8<-- "recipes/postgresql/connect_and_query/csharp/ConnectAndQuery.csproj:deps"
    ```

=== "Go"

    ```text
    --8<-- "recipes/postgresql/connect_and_query/go/go.mod:deps"
    ```

=== "Rust"

    ```toml
    --8<-- "recipes/postgresql/connect_and_query/rust/Cargo.toml:deps"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgresql/connect_and_query/ruby/Gemfile:deps"
    ```

=== "C"

    ```make
    --8<-- "recipes/postgresql/connect_and_query/c/Makefile:deps"
    ```

## Importing the Driver

Each program begins by importing the driver, along with any standard
library modules that the program uses. The following tabs show the imports
for each language:

=== "Python"

    ```python
    --8<-- "recipes/postgresql/connect_and_query/python/main.py:imports"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgresql/connect_and_query/typescript/main.ts:imports"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgresql/connect_and_query/java/src/main/java/Main.java:imports"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgresql/connect_and_query/csharp/Program.cs:imports"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgresql/connect_and_query/go/main.go:imports"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgresql/connect_and_query/rust/src/main.rs:imports"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgresql/connect_and_query/ruby/main.rb:imports"
    ```

=== "C"

    ```c
    --8<-- "recipes/postgresql/connect_and_query/c/main.c:imports"
    ```

## Configuring the Connection

The examples read their connection settings from the same environment
variables that libpq and `psql` use, so a single set of variables
configures every example. The examples read only the five variables in the
table, and expect a TCP host name or IPv4 address in `PGHOST`. Like libpq,
each example treats an empty variable as unset, and uses the default
instead. The following table describes the environment variables that the
examples read:

| Variable     | Default     | Description                                    |
|--------------|-------------|------------------------------------------------|
| `PGHOST`     | `localhost` | The host name or IP address of the server.     |
| `PGPORT`     | `5432`      | The TCP port on which the server listens.      |
| `PGDATABASE` | `postgres`  | The name of the database to connect to.        |
| `PGUSER`     | `postgres`  | The user name to connect as.                   |
| `PGPASSWORD` | None        | The password; omitted if unset or empty.       |

!!! note

    Production applications should not store passwords in environment
    variables or source code. The
    [password file](https://www.postgresql.org/docs/current/libpq-pgpass.html)
    or a secrets manager provides a safer alternative.

The following tabs show how each program assembles the connection settings:

=== "Python"

    ```python
    --8<-- "recipes/postgresql/connect_and_query/python/main.py:config"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgresql/connect_and_query/typescript/main.ts:config"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgresql/connect_and_query/java/src/main/java/Main.java:config"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgresql/connect_and_query/csharp/Program.cs:config"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgresql/connect_and_query/go/main.go:config"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgresql/connect_and_query/rust/src/main.rs:config"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgresql/connect_and_query/ruby/main.rb:config"
    ```

=== "C"

    ```c
    --8<-- "recipes/postgresql/connect_and_query/c/main.c:config"
    ```

## Opening a Connection

Each program opens a connection to the server with the settings from the
previous step. The C# program creates an Npgsql data source instead, which
lends out pooled connections when the main part of the program asks for
one. The driver reports a failure if the server is unreachable or rejects
the credentials; the Handling Errors and Closing the Connection section
describes how each program reports the failure. The following tabs show
how each program opens the connection:

=== "Python"

    ```python
    --8<-- "recipes/postgresql/connect_and_query/python/main.py:connect"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgresql/connect_and_query/typescript/main.ts:connect"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgresql/connect_and_query/java/src/main/java/Main.java:connect"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgresql/connect_and_query/csharp/Program.cs:connect"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgresql/connect_and_query/go/main.go:connect"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgresql/connect_and_query/rust/src/main.rs:connect"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgresql/connect_and_query/ruby/main.rb:connect"
    ```

=== "C"

    ```c
    --8<-- "recipes/postgresql/connect_and_query/c/main.c:connect"
    ```

## Running the Query

Each program runs the query in a function that takes the type name, sends
the name to the server as a parameter, and then reads the single value
from the first column of the first row. Each driver sends parameters
separately from the SQL text, so the server never interprets a parameter
as SQL; this approach eliminates SQL injection attacks. The placeholder
syntax differs between drivers.

The following table shows the placeholder syntax that each driver uses:

| Language   | Placeholder syntax |
|------------|--------------------|
| Python     | `%s`               |
| TypeScript | `$1`, `$2`, ...    |
| Java       | `?`                |
| C#         | `$1`, `$2`, ...    |
| Go         | `$1`, `$2`, ...    |
| Rust       | `$1`, `$2`, ...    |
| Ruby       | `$1`, `$2`, ...    |
| C          | `$1`, `$2`, ...    |

The `count(*)` aggregate returns a `bigint`. The C and Ruby drivers return
every value as text, so those programs convert the value to an integer;
node-postgres returns a `bigint` as a string because the value may exceed
the range of a JavaScript number. The other drivers return a native 64-bit
integer. The following tabs show how each program runs the query and reads
the result:

=== "Python"

    ```python
    --8<-- "recipes/postgresql/connect_and_query/python/main.py:query"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgresql/connect_and_query/typescript/main.ts:query"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgresql/connect_and_query/java/src/main/java/Main.java:query"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgresql/connect_and_query/csharp/Program.cs:query"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgresql/connect_and_query/go/main.go:query"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgresql/connect_and_query/rust/src/main.rs:query"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgresql/connect_and_query/ruby/main.rb:query"
    ```

=== "C"

    ```c
    --8<-- "recipes/postgresql/connect_and_query/c/main.c:query"
    ```

## Handling Errors and Closing the Connection

The main part of each program calls the functions from the previous steps,
and prints the result. The program reports any connection or query failure
on `stderr`, and then exits with a non-zero status. The Python, C#, and
Ruby programs catch the base error class of the driver, and the Java
program catches the JDBC `SQLException` class; the TypeScript program
catches any rejected promise. The Go and Rust programs return each
error from a `run()` function to `main()`, and the C program checks the
result of each call.

The program also closes the connection when the work completes or fails, so
the server can release the resources that the connection holds. The Python
`with` block, the Java `try`-with-resources statement, and the C# `await
using` declaration close the connection automatically at the end of a
block. The TypeScript, Ruby, and Go programs close the connection in a
`finally` block, an `ensure` block, or a deferred call, and the C program
calls `PQfinish()` on both paths. The Rust program closes the connection
explicitly on success, and drops the client to close the connection after
an error. The following tabs show the main part of each program:

=== "Python"

    ```python
    --8<-- "recipes/postgresql/connect_and_query/python/main.py:main"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgresql/connect_and_query/typescript/main.ts:main"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgresql/connect_and_query/java/src/main/java/Main.java:main"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgresql/connect_and_query/csharp/Program.cs:main"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgresql/connect_and_query/go/main.go:main"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgresql/connect_and_query/rust/src/main.rs:main"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgresql/connect_and_query/ruby/main.rb:main"
    ```

=== "C"

    ```c
    --8<-- "recipes/postgresql/connect_and_query/c/main.c:main"
    ```

## Running the Example

The complete project for each language is available in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/postgresql/connect_and_query).
Set the environment variables for your server, and then run the command for
your language from the corresponding project directory. The following tabs
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

=== "C"

    ```bash
    make
    ./main
    ```

## Viewing the Complete Program

The following tabs show the complete program for each language:

=== "Python"

    ```python
    --8<-- "recipes/postgresql/connect_and_query/python/main.py"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgresql/connect_and_query/typescript/main.ts"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgresql/connect_and_query/java/src/main/java/Main.java"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgresql/connect_and_query/csharp/Program.cs"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgresql/connect_and_query/go/main.go"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgresql/connect_and_query/rust/src/main.rs"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgresql/connect_and_query/ruby/main.rb"
    ```

=== "C"

    ```c
    --8<-- "recipes/postgresql/connect_and_query/c/main.c"
    ```

## Next Steps

The following resources provide more information about the topics in this
recipe:

- The [Contributing a Recipe](../contributing.md) page explains how to add
  a recipe or a language to the cookbook.
- The PostgreSQL documentation for
  [environment variables](https://www.postgresql.org/docs/current/libpq-envars.html)
  describes every variable that libpq recognises.
- The PostgreSQL documentation for
  [connection strings](https://www.postgresql.org/docs/current/libpq-connect.html#LIBPQ-CONNSTRING)
  describes the full set of connection parameters.
