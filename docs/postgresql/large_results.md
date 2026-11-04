# Reading Large Results in Batches

This recipe demonstrates how an application reads a query result that is
too large to hold in memory. By default, most drivers transfer the whole
result to the client before the program sees the first row, so a query
that returns millions of rows can exhaust the memory of the application.
Each driver offers a way to read the result as a stream, or in batches,
and the examples show the idiomatic approach for each language. Each step
shows the code in every supported language; selecting a language tab
switches every tab on the site to that language.

The example program runs `SELECT g FROM generate_series(1, 100000) AS g`,
which returns the integers 1 to 100000, reads every row without holding
the whole result at once, and adds up the values. The sum of the first
100,000 integers is always 5000050000, so the output is easy to verify:

```text
Rows read: 100000
Sum of values: 5000050000
```

## Preparing the Ingredients

Each example uses the most widely adopted PostgreSQL driver for its
language; the TypeScript example adds the `pg-cursor` companion library,
because node-postgres needs it to read a result in batches. The following
table lists the driver that each example uses:

| Language   | Driver                                                 |
|------------|--------------------------------------------------------|
| Python     | [psycopg 3](https://www.psycopg.org/psycopg3/)         |
| TypeScript | [node-postgres](https://node-postgres.com/) with [pg-cursor](https://github.com/brianc/node-postgres/tree/master/packages/pg-cursor) |
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
    --8<-- "recipes/postgresql/large_results/python/requirements.txt:deps"
    ```

=== "TypeScript"

    ```json
    --8<-- "recipes/postgresql/large_results/typescript/package.json"
    ```

=== "Java"

    ```xml
    --8<-- "recipes/postgresql/large_results/java/pom.xml:deps"
    ```

=== "C#"

    ```xml
    --8<-- "recipes/postgresql/large_results/csharp/LargeResults.csproj:deps"
    ```

=== "Go"

    ```text
    --8<-- "recipes/postgresql/large_results/go/go.mod:deps"
    ```

=== "Rust"

    ```toml
    --8<-- "recipes/postgresql/large_results/rust/Cargo.toml:deps"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgresql/large_results/ruby/Gemfile:deps"
    ```

=== "C"

    ```make
    --8<-- "recipes/postgresql/large_results/c/Makefile:deps"
    ```

## Importing the Driver

Each program begins by importing the driver, along with any standard
library modules that the program uses. The following tabs show the imports
for each language:

=== "Python"

    ```python
    --8<-- "recipes/postgresql/large_results/python/main.py:imports"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgresql/large_results/typescript/main.ts:imports"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgresql/large_results/java/src/main/java/Main.java:imports"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgresql/large_results/csharp/Program.cs:imports"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgresql/large_results/go/main.go:imports"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgresql/large_results/rust/src/main.rs:imports"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgresql/large_results/ruby/main.rb:imports"
    ```

=== "C"

    ```c
    --8<-- "recipes/postgresql/large_results/c/main.c:imports"
    ```

## Configuring the Connection

The examples read their connection settings from the same environment
variables that libpq and `psql` use: `PGHOST`, `PGPORT`, `PGDATABASE`,
`PGUSER`, and `PGPASSWORD`. Like libpq, each example treats an empty
variable as unset, and uses a default suitable for a local server instead.
The [first recipe](connect_and_query.md) describes the variables in
detail. The following tabs show how each program assembles the connection
settings:

=== "Python"

    ```python
    --8<-- "recipes/postgresql/large_results/python/main.py:config"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgresql/large_results/typescript/main.ts:config"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgresql/large_results/java/src/main/java/Main.java:config"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgresql/large_results/csharp/Program.cs:config"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgresql/large_results/go/main.go:config"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgresql/large_results/rust/src/main.rs:config"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgresql/large_results/ruby/main.rb:config"
    ```

=== "C"

    ```c
    --8<-- "recipes/postgresql/large_results/c/main.c:config"
    ```

## Opening a Connection

Each program opens a connection to the server with the settings from the
previous step. The C# program creates an Npgsql data source instead, which
lends out pooled connections when the main part of the program asks for
one. The following tabs show how each program opens the connection:

=== "Python"

    ```python
    --8<-- "recipes/postgresql/large_results/python/main.py:connect"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgresql/large_results/typescript/main.ts:connect"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgresql/large_results/java/src/main/java/Main.java:connect"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgresql/large_results/csharp/Program.cs:connect"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgresql/large_results/go/main.go:connect"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgresql/large_results/rust/src/main.rs:connect"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgresql/large_results/ruby/main.rb:connect"
    ```

=== "C"

    ```c
    --8<-- "recipes/postgresql/large_results/c/main.c:connect"
    ```

## Reading the Result in Batches

Each program runs the query and reads the rows without loading the whole
result into memory. The drivers use two different approaches, and the
approach decides what a batch size means.

Most drivers use a cursor, which makes the server keep the result and send
rows only when the program asks for them. A cursor exists only inside a
transaction, which some drivers start implicitly: the Python and
TypeScript programs rely on the transaction that psycopg and the
PostgreSQL protocol open for them, and the other programs start one
explicitly. The Python program names its
cursor, which makes psycopg create a server-side cursor, and calls
`fetchmany(1000)` for each batch. The TypeScript program runs a `pg-cursor`
query, and calls `read(1000)` for each batch. The Java program turns off
autocommit and sets a fetch size of 1,000, and the driver then fetches
each batch when `next()` reaches the end of the previous one; with
autocommit on, pgJDBC ignores the fetch size and loads the whole result.
The Rust program binds the query to a portal, which is the protocol name
for a cursor, and calls `query_portal()` for each batch. The Ruby and C
programs declare a cursor with `DECLARE` and read each batch with
`FETCH 1000`. A cursor name cannot be a query parameter, so those two
programs write it into the SQL as a fixed string rather than as
application data.

The Go and C# drivers instead read rows from the network as the program
consumes them. A pgx `Rows` object and an Npgsql `NpgsqlDataReader` hold
only the rows that have arrived in the connection's read buffer, so the
program never has the whole result in memory, but there is no batch size
to set. The loop reads one row at a time, and the Go program checks
`rows.Err()` afterwards because `Next()` returns false both at the end of
the result and after an error. The following tabs show how each program
reads the result:

=== "Python"

    ```python
    --8<-- "recipes/postgresql/large_results/python/main.py:read_batches"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgresql/large_results/typescript/main.ts:read_batches"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgresql/large_results/java/src/main/java/Main.java:read_batches"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgresql/large_results/csharp/Program.cs:read_batches"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgresql/large_results/go/main.go:read_batches"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgresql/large_results/rust/src/main.rs:read_batches"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgresql/large_results/ruby/main.rb:read_batches"
    ```

=== "C"

    ```c
    --8<-- "recipes/postgresql/large_results/c/main.c:read_batches"
    ```

## Handling Errors and Closing the Connection

The main part of each program calls the function from the previous step,
and prints the results. The program reports any connection or query
failure on `stderr`, and then exits with a non-zero status, and it closes
the connection when the work completes or fails. The error handling and
the cleanup follow the pattern of the
[first recipe](connect_and_query.md). The following tabs show the main part
of each program:

=== "Python"

    ```python
    --8<-- "recipes/postgresql/large_results/python/main.py:main"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgresql/large_results/typescript/main.ts:main"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgresql/large_results/java/src/main/java/Main.java:main"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgresql/large_results/csharp/Program.cs:main"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgresql/large_results/go/main.go:main"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgresql/large_results/rust/src/main.rs:main"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgresql/large_results/ruby/main.rb:main"
    ```

=== "C"

    ```c
    --8<-- "recipes/postgresql/large_results/c/main.c:main"
    ```

## Running the Example

The complete project for each language is available in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/postgresql/large_results).
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
    --8<-- "recipes/postgresql/large_results/python/main.py"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgresql/large_results/typescript/main.ts"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgresql/large_results/java/src/main/java/Main.java"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgresql/large_results/csharp/Program.cs"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgresql/large_results/go/main.go"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgresql/large_results/rust/src/main.rs"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgresql/large_results/ruby/main.rb"
    ```

=== "C"

    ```c
    --8<-- "recipes/postgresql/large_results/c/main.c"
    ```

## Next Steps

The following resources provide more information about the topics in this
recipe:

- The PostgreSQL documentation for
  [DECLARE](https://www.postgresql.org/docs/current/sql-declare.html)
  and [FETCH](https://www.postgresql.org/docs/current/sql-fetch.html)
  describes server-side cursors.
- The PostgreSQL documentation for
  [retrieving query results row by row](https://www.postgresql.org/docs/current/libpq-single-row-mode.html)
  describes the single-row mode that libpq offers as an alternative to a
  cursor.
- The [Contributing a Recipe](../contributing.md) page explains how to add
  a recipe or a language to the cookbook.
