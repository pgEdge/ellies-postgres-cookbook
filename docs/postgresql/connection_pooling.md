# Using a Connection Pool

This recipe demonstrates how an application shares a small, fixed number of
database connections between many queries by using a connection pool.
Opening a connection to PostgreSQL is slow, because it involves a network
handshake, authentication, and the start of a server process, and each
connection also holds memory on the server. A pool opens the connections
once, lends one to each caller that needs it, and takes it back afterwards;
callers that arrive when every connection is busy wait for a free one.
Each step shows the code in every supported language; selecting a language
tab switches every tab on the site to that language.

The example program creates a pool of at most two connections, and then
starts five queries at once. Each query is `SELECT $1::int`, which returns
one of the numbers 1 to 5 that the program sends as a parameter. The pool
runs at most two of the queries at any moment, and the program adds up the
five results and closes the pool. The output is the same on every run:

```text
Ran 5 queries through a pool of at most 2 connections
Sum of results: 15
```

!!! note

    libpq, the C client library, has no connection pool, so this recipe has
    no C program. The C tab in each step explains the alternative: a
    separate pooling server such as [PgBouncer](https://www.pgbouncer.org/)
    pools connections for any client, whatever language the client uses.

## Preparing the Ingredients

Each example uses the pool that is most widely adopted for its language,
and the pool comes from a separate package in several languages. The
following table lists the driver and the pool that each example uses:

| Language   | Driver                                          | Pool |
|------------|-------------------------------------------------|------|
| Python     | [psycopg 3](https://www.psycopg.org/psycopg3/)  | [psycopg_pool](https://www.psycopg.org/psycopg3/docs/advanced/pool.html) |
| TypeScript | [node-postgres](https://node-postgres.com/)     | [pg.Pool](https://node-postgres.com/apis/pool), part of node-postgres |
| Java       | [pgJDBC](https://jdbc.postgresql.org/)          | [HikariCP](https://github.com/brettwooldridge/HikariCP) |
| C#         | [Npgsql](https://www.npgsql.org/)               | [NpgsqlDataSource](https://www.npgsql.org/doc/basic-usage.html), part of Npgsql |
| Go         | [pgx](https://github.com/jackc/pgx)             | [pgxpool](https://pkg.go.dev/github.com/jackc/pgx/v5/pgxpool), part of pgx |
| Rust       | [rust-postgres](https://github.com/rust-postgres/rust-postgres) | [r2d2_postgres](https://github.com/rust-postgres/r2d2-postgres) |
| Ruby       | [ruby-pg](https://github.com/ged/ruby-pg)      | [connection_pool](https://github.com/mperham/connection_pool) |
| C          | [libpq](https://www.postgresql.org/docs/current/libpq.html) | None; use [PgBouncer](https://www.pgbouncer.org/) |

The Rust example uses r2d2 because it works with the synchronous
`postgres` crate that the first recipe uses; an asynchronous program would
use a pool such as `deadpool-postgres` instead. The following tabs show the
dependency declaration from each example project:

=== "Python"

    ```text
    --8<-- "recipes/postgresql/connection_pooling/python/requirements.txt:deps"
    ```

=== "TypeScript"

    ```json
    --8<-- "recipes/postgresql/connection_pooling/typescript/package.json"
    ```

=== "Java"

    ```xml
    --8<-- "recipes/postgresql/connection_pooling/java/pom.xml:deps"
    ```

=== "C#"

    ```xml
    --8<-- "recipes/postgresql/connection_pooling/csharp/ConnectionPooling.csproj:deps"
    ```

=== "Go"

    ```text
    --8<-- "recipes/postgresql/connection_pooling/go/go.mod:deps"
    ```

=== "Rust"

    ```toml
    --8<-- "recipes/postgresql/connection_pooling/rust/Cargo.toml:deps"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgresql/connection_pooling/ruby/Gemfile:deps"
    ```

=== "C"

    There is no C example, because libpq has no built-in connection pool, so
    there are no dependencies to declare. A C application that needs pooling
    normally connects through [PgBouncer](https://www.pgbouncer.org/), a
    separate pooling server that runs between the application and PostgreSQL.

## Importing the Libraries

Each program begins by importing the driver and its pool, along with any
standard library modules that the program uses to run queries at the same
time. The following tabs show the imports for each language:

=== "Python"

    ```python
    --8<-- "recipes/postgresql/connection_pooling/python/main.py:imports"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgresql/connection_pooling/typescript/main.ts:imports"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgresql/connection_pooling/java/src/main/java/Main.java:imports"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgresql/connection_pooling/csharp/Program.cs:imports"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgresql/connection_pooling/go/main.go:imports"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgresql/connection_pooling/rust/src/main.rs:imports"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgresql/connection_pooling/ruby/main.rb:imports"
    ```

=== "C"

    A C application needs no pool library, because libpq has no connection pool
    and this recipe has no C program. [PgBouncer](https://www.pgbouncer.org/)
    provides pooling outside the application, and the application connects to
    it with the ordinary libpq calls.

## Configuring the Connection and the Pool

The examples read their connection settings from the same environment
variables as the first recipe: `PGHOST`, `PGPORT`, `PGDATABASE`, `PGUSER`,
and `PGPASSWORD`. Each example treats an empty variable as unset, and uses
the default instead. Each program also fixes the size of the pool at two
connections in one place, so that the size appears in the pool settings and
in the output. The following tabs show how each program assembles its
settings:

=== "Python"

    ```python
    --8<-- "recipes/postgresql/connection_pooling/python/main.py:config"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgresql/connection_pooling/typescript/main.ts:config"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgresql/connection_pooling/java/src/main/java/Main.java:config"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgresql/connection_pooling/csharp/Program.cs:config"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgresql/connection_pooling/go/main.go:config"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgresql/connection_pooling/rust/src/main.rs:config"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgresql/connection_pooling/ruby/main.rb:config"
    ```

=== "C"

    The settings in a C application that uses PgBouncer are the usual libpq
    settings, with `PGHOST` and `PGPORT` pointing at PgBouncer instead of the
    PostgreSQL server. This recipe has no C program.

## Creating the Pool

Each program creates one pool when it starts, and shares the pool between
every query; an application would normally do the same, and create the pool
once per process rather than once per request. The program sets the maximum
size of the pool to two connections, and sets a five-second timeout, so that
a caller that waits too long for a connection receives an error instead of
waiting forever.

Pools differ in when they connect. The Python, Java, and Rust pools open a
connection while they are created, so the program fails there if the server
is unreachable. The Go program calls `Ping()` to force the first connection,
and the TypeScript, C#, and Ruby pools open their connections when the first
query asks for one. In every language, the failure reaches the error
handling in the main part of the program. The following tabs show how each
program creates the pool:

=== "Python"

    ```python
    --8<-- "recipes/postgresql/connection_pooling/python/main.py:pool"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgresql/connection_pooling/typescript/main.ts:pool"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgresql/connection_pooling/java/src/main/java/Main.java:pool"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgresql/connection_pooling/csharp/Program.cs:pool"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgresql/connection_pooling/go/main.go:pool"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgresql/connection_pooling/rust/src/main.rs:pool"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgresql/connection_pooling/ruby/main.rb:pool"
    ```

=== "C"

    libpq has no connection pool, so there is no pool to create in C. Install
    [PgBouncer](https://www.pgbouncer.org/), set its `default_pool_size` to the
    number of server connections that it may open, and let the C application
    connect to PgBouncer.

## Running a Query Through the Pool

Each program runs the query in a function that takes the pool and a number,
borrows a connection, sends the number to the server as a parameter, and
reads the single value that comes back. The function returns the connection
to the pool when it finishes, and does not disconnect it from the server, so
the next query can reuse it. The `::int` cast gives the parameter a type,
because the server cannot infer one from `SELECT $1` alone. The TypeScript
program calls `pool.query()`, and the Go program calls `pool.QueryRow()`;
both borrow and return a connection automatically. The following tabs show
how each program runs the query:

=== "Python"

    ```python
    --8<-- "recipes/postgresql/connection_pooling/python/main.py:query"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgresql/connection_pooling/typescript/main.ts:query"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgresql/connection_pooling/java/src/main/java/Main.java:query"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgresql/connection_pooling/csharp/Program.cs:query"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgresql/connection_pooling/go/main.go:query"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgresql/connection_pooling/rust/src/main.rs:query"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgresql/connection_pooling/ruby/main.rb:query"
    ```

=== "C"

    In C, an application opens a connection with `PQconnectdbParams()` as in
    the first recipe, and runs queries on it with `PQexecParams()`. When the
    connection goes to PgBouncer, which holds the pooled server connections,
    the application needs no pool-specific code.

## Handling Errors and Closing the Pool

The main part of each program starts the five queries at the same time,
using threads in Python, Java, Rust, and Ruby, goroutines in Go, and
promises or tasks in TypeScript and C#. Only two queries run at any
moment, and the others wait for a connection. The program then adds up the
results and prints them.

The program reports any connection or query failure on `stderr`, and then
exits with a non-zero status. Closing the pool closes every connection that
it opened, and the program does so whether or not an error occurred: the
Python `with` block, the Java `try`-with-resources statement, and the C#
`await using` declaration close the pool automatically at the end of a
block. The TypeScript and Ruby programs close the pool in a `finally` block
and an `ensure` block, the Go program in a deferred call, and the Rust
program by dropping the pool. The following tabs show the main part of each
program:

=== "Python"

    ```python
    --8<-- "recipes/postgresql/connection_pooling/python/main.py:main"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgresql/connection_pooling/typescript/main.ts:main"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgresql/connection_pooling/java/src/main/java/Main.java:main"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgresql/connection_pooling/csharp/Program.cs:main"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgresql/connection_pooling/go/main.go:main"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgresql/connection_pooling/rust/src/main.rs:main"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgresql/connection_pooling/ruby/main.rb:main"
    ```

=== "C"

    A C application closes each connection with `PQfinish()`, as in the first
    recipe; when the connection goes to PgBouncer, closing it lets PgBouncer
    reuse the server connection for another client. This recipe has no C
    program.

## Running the Example

The complete project for each language is available in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/postgresql/connection_pooling).
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

    There is no C program to run. To pool connections for a C application,
    install [PgBouncer](https://www.pgbouncer.org/) and point the libpq
    settings at it.

## Viewing the Complete Program

The following tabs show the complete program for each language:

=== "Python"

    ```python
    --8<-- "recipes/postgresql/connection_pooling/python/main.py"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgresql/connection_pooling/typescript/main.ts"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgresql/connection_pooling/java/src/main/java/Main.java"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgresql/connection_pooling/csharp/Program.cs"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgresql/connection_pooling/go/main.go"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgresql/connection_pooling/rust/src/main.rs"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgresql/connection_pooling/ruby/main.rb"
    ```

=== "C"

    This recipe has no C program, because libpq has no connection pool. Use
    [PgBouncer](https://www.pgbouncer.org/) to pool connections for a C
    application.

## Next Steps

The following resources provide more information about the topics in this
recipe:

- The [PgBouncer documentation](https://www.pgbouncer.org/config.html)
  describes the three pooling modes, and the settings that size the pool.
- The [psycopg pool documentation](https://www.psycopg.org/psycopg3/docs/advanced/pool.html)
  explains how a pool grows and shrinks between its minimum and maximum
  sizes.
- The [first recipe](connect_and_query.md) explains the connection settings
  that every example uses.
