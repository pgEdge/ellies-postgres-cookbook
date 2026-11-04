# Bulk Loading with COPY

This recipe demonstrates how an application loads many rows into a
PostgreSQL table with the `COPY` command, which is far faster than sending
one `INSERT` statement for each row. Each driver exposes `COPY ... FROM
STDIN` through its own API, and the examples stream the rows to the server
without building the whole data set in memory. Each step shows the code in
every supported language; selecting a language tab switches every tab on
the site to that language.

The example program creates a temporary table named `items`, generates
1,000 rows with the ids 1 to 1000 and the names `item 1` to `item 1000`,
and loads them with a single `COPY` command. The program then asks the
server for the number of rows in the table and the sum of their ids, which
is always 500500, so the output is easy to verify:

```text
Copied 1000 rows
Rows in table: 1000
Sum of ids: 500500
```

## Preparing the Ingredients

Each example uses the most widely adopted PostgreSQL driver for its
language; the TypeScript example adds the `pg-copy-streams` companion
library, because node-postgres has no copy support of its own. The
following table lists the API that each example uses for `COPY`:

| Language   | Copy API                                                       |
|------------|----------------------------------------------------------------|
| Python     | [psycopg 3](https://www.psycopg.org/psycopg3/) `cursor.copy()` |
| TypeScript | [pg-copy-streams](https://github.com/brianc/node-pg-copy-streams) |
| Java       | [pgJDBC](https://jdbc.postgresql.org/) `CopyManager` API       |
| C#         | [Npgsql](https://www.npgsql.org/) `BeginBinaryImport()`        |
| Go         | [pgx](https://github.com/jackc/pgx) `CopyFrom()`               |
| Rust       | [rust-postgres](https://github.com/sfackler/rust-postgres) `copy_in()` |
| Ruby       | [ruby-pg](https://github.com/ged/ruby-pg) `copy_data()`        |
| C          | [libpq](https://www.postgresql.org/docs/current/libpq.html) `PQputCopyData()` |

The C example links against libpq, so the example requires the libpq
client library and headers; on Debian and Ubuntu, the `libpq-dev` package
provides both. The Ruby gem also uses libpq, and may require the same
package on platforms without a pre-built gem. The following tabs show the
dependency declaration from each example project:

=== "Python"

    ```text
    --8<-- "recipes/postgresql/bulk_copy/python/requirements.txt:deps"
    ```

=== "TypeScript"

    ```json
    --8<-- "recipes/postgresql/bulk_copy/typescript/package.json"
    ```

=== "Java"

    ```xml
    --8<-- "recipes/postgresql/bulk_copy/java/pom.xml:deps"
    ```

=== "C#"

    ```xml
    --8<-- "recipes/postgresql/bulk_copy/csharp/BulkCopy.csproj:deps"
    ```

=== "Go"

    ```text
    --8<-- "recipes/postgresql/bulk_copy/go/go.mod:deps"
    ```

=== "Rust"

    ```toml
    --8<-- "recipes/postgresql/bulk_copy/rust/Cargo.toml:deps"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgresql/bulk_copy/ruby/Gemfile:deps"
    ```

=== "C"

    ```make
    --8<-- "recipes/postgresql/bulk_copy/c/Makefile:deps"
    ```

## Importing the Driver

Each program begins by importing the driver, along with any standard
library modules that the program uses. The following tabs show the imports
for each language:

=== "Python"

    ```python
    --8<-- "recipes/postgresql/bulk_copy/python/main.py:imports"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgresql/bulk_copy/typescript/main.ts:imports"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgresql/bulk_copy/java/src/main/java/Main.java:imports"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgresql/bulk_copy/csharp/Program.cs:imports"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgresql/bulk_copy/go/main.go:imports"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgresql/bulk_copy/rust/src/main.rs:imports"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgresql/bulk_copy/ruby/main.rb:imports"
    ```

=== "C"

    ```c
    --8<-- "recipes/postgresql/bulk_copy/c/main.c:imports"
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
    --8<-- "recipes/postgresql/bulk_copy/python/main.py:config"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgresql/bulk_copy/typescript/main.ts:config"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgresql/bulk_copy/java/src/main/java/Main.java:config"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgresql/bulk_copy/csharp/Program.cs:config"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgresql/bulk_copy/go/main.go:config"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgresql/bulk_copy/rust/src/main.rs:config"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgresql/bulk_copy/ruby/main.rb:config"
    ```

=== "C"

    ```c
    --8<-- "recipes/postgresql/bulk_copy/c/main.c:config"
    ```

## Opening a Connection

Each program opens a connection to the server with the settings from the
previous step. The C# program creates an Npgsql data source instead, which
lends out pooled connections when the main part of the program asks for
one. The following tabs show how each program opens the connection:

=== "Python"

    ```python
    --8<-- "recipes/postgresql/bulk_copy/python/main.py:connect"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgresql/bulk_copy/typescript/main.ts:connect"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgresql/bulk_copy/java/src/main/java/Main.java:connect"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgresql/bulk_copy/csharp/Program.cs:connect"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgresql/bulk_copy/go/main.go:connect"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgresql/bulk_copy/rust/src/main.rs:connect"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgresql/bulk_copy/ruby/main.rb:connect"
    ```

=== "C"

    ```c
    --8<-- "recipes/postgresql/bulk_copy/c/main.c:connect"
    ```

## Creating the Table

Each program creates the table that receives the rows. The table is
`TEMPORARY`, so only the connection that creates it can see it, and
PostgreSQL drops it when the connection closes; the example can therefore
run any number of times without leaving anything behind. The following tabs
show how each program creates the table:

=== "Python"

    ```python
    --8<-- "recipes/postgresql/bulk_copy/python/main.py:create_table"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgresql/bulk_copy/typescript/main.ts:create_table"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgresql/bulk_copy/java/src/main/java/Main.java:create_table"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgresql/bulk_copy/csharp/Program.cs:create_table"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgresql/bulk_copy/go/main.go:create_table"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgresql/bulk_copy/rust/src/main.rs:create_table"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgresql/bulk_copy/ruby/main.rb:create_table"
    ```

=== "C"

    ```c
    --8<-- "recipes/postgresql/bulk_copy/c/main.c:create_table"
    ```

## Generating the Rows

Each program produces its rows lazily, one at a time, through a generator,
an iterator, or a function that the loop calls for each id, so the program
never holds all of the rows in memory. A real application would read the
rows from a file, another database, or a network service in the same way.

The Python, Go, and C# drivers convert each row from native values to the
`COPY` format themselves; psycopg writes the text format, and pgx and
Npgsql write the binary format, so these programs need no escaping. The
other drivers send the text format as it is written, so the TypeScript,
Java, Rust, Ruby, and C programs build each line themselves. In the
`COPY` text format, a tab separates the columns, a newline ends the row,
and a backslash begins an escape sequence. A value that contains any of
those characters, or a carriage return, must therefore have each of them
replaced by `\\`, `\t`, `\n`, or `\r`, and each program does so with an
`escapeText()` or `escape_text()` function. The generated names contain
none of these characters, but the function keeps the program correct for
data that does. The following tabs show how each program generates the
rows:

=== "Python"

    ```python
    --8<-- "recipes/postgresql/bulk_copy/python/main.py:generate_rows"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgresql/bulk_copy/typescript/main.ts:generate_rows"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgresql/bulk_copy/java/src/main/java/Main.java:generate_rows"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgresql/bulk_copy/csharp/Program.cs:generate_rows"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgresql/bulk_copy/go/main.go:generate_rows"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgresql/bulk_copy/rust/src/main.rs:generate_rows"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgresql/bulk_copy/ruby/main.rb:generate_rows"
    ```

=== "C"

    ```c
    --8<-- "recipes/postgresql/bulk_copy/c/main.c:generate_rows"
    ```

## Copying the Rows

Each program sends the rows with `COPY items (id, name) FROM STDIN`, which
tells the server to expect the data on the same connection. The program
writes the rows to the copy stream, and then ends the stream; the server
stores nothing until it receives the end of the stream, and discards
every row if an error occurs first. The final result reports the number of
rows that the server stored.

The details differ between drivers. The Python `with` block and the Ruby
`copy_data()` block end the copy when the block finishes, and the Ruby
method also raises an error if the server rejects the data. The pgx
`CopyFrom()` function pulls every row from the source and finishes the
copy itself. The TypeScript program uses `pipeline()` to connect a stream
of rows to the copy stream, which applies back-pressure when the server is
slower than the program. The Rust, Java, and C# programs finish the copy
explicitly with `finish()`, `endCopy()`, and `CompleteAsync()`; the Rust
and C# programs cancel the copy if they drop the writer without finishing,
and the Java program cancels an unfinished copy after an error so that the
connection remains usable. The C program ends the copy with
`PQputCopyEnd()`, and then reads the result with `PQgetResult()`. The
following tabs show how each program copies the rows:

=== "Python"

    ```python
    --8<-- "recipes/postgresql/bulk_copy/python/main.py:copy_rows"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgresql/bulk_copy/typescript/main.ts:copy_rows"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgresql/bulk_copy/java/src/main/java/Main.java:copy_rows"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgresql/bulk_copy/csharp/Program.cs:copy_rows"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgresql/bulk_copy/go/main.go:copy_rows"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgresql/bulk_copy/rust/src/main.rs:copy_rows"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgresql/bulk_copy/ruby/main.rb:copy_rows"
    ```

=== "C"

    ```c
    --8<-- "recipes/postgresql/bulk_copy/c/main.c:copy_rows"
    ```

## Checking the Result

Each program runs an ordinary query to confirm what the server stored. The
`sum()` aggregate returns a `bigint` for an `int` column, so the total fits
in a 64-bit integer; the TypeScript program receives both values as
strings, because node-postgres does not convert large integers to a
JavaScript number. The following tabs show how each program reads the
result:

=== "Python"

    ```python
    --8<-- "recipes/postgresql/bulk_copy/python/main.py:summarise"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgresql/bulk_copy/typescript/main.ts:summarise"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgresql/bulk_copy/java/src/main/java/Main.java:summarise"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgresql/bulk_copy/csharp/Program.cs:summarise"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgresql/bulk_copy/go/main.go:summarise"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgresql/bulk_copy/rust/src/main.rs:summarise"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgresql/bulk_copy/ruby/main.rb:summarise"
    ```

=== "C"

    ```c
    --8<-- "recipes/postgresql/bulk_copy/c/main.c:summarise"
    ```

## Handling Errors and Closing the Connection

The main part of each program calls the functions from the previous steps,
and prints the results. The program reports any connection or `COPY`
failure on `stderr`, and then exits with a non-zero status, and it closes
the connection when the work completes or fails. The error handling and
the cleanup follow the pattern of the
[first recipe](connect_and_query.md). The following tabs show the main part
of each program:

=== "Python"

    ```python
    --8<-- "recipes/postgresql/bulk_copy/python/main.py:main"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgresql/bulk_copy/typescript/main.ts:main"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgresql/bulk_copy/java/src/main/java/Main.java:main"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgresql/bulk_copy/csharp/Program.cs:main"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgresql/bulk_copy/go/main.go:main"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgresql/bulk_copy/rust/src/main.rs:main"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgresql/bulk_copy/ruby/main.rb:main"
    ```

=== "C"

    ```c
    --8<-- "recipes/postgresql/bulk_copy/c/main.c:main"
    ```

## Running the Example

The complete project for each language is available in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/postgresql/bulk_copy).
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
    --8<-- "recipes/postgresql/bulk_copy/python/main.py"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgresql/bulk_copy/typescript/main.ts"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgresql/bulk_copy/java/src/main/java/Main.java"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgresql/bulk_copy/csharp/Program.cs"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgresql/bulk_copy/go/main.go"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgresql/bulk_copy/rust/src/main.rs"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgresql/bulk_copy/ruby/main.rb"
    ```

=== "C"

    ```c
    --8<-- "recipes/postgresql/bulk_copy/c/main.c"
    ```

## Next Steps

The following resources provide more information about the topics in this
recipe:

- The PostgreSQL documentation for the
  [COPY command](https://www.postgresql.org/docs/current/sql-copy.html)
  describes the text, CSV, and binary formats, and every option.
- The PostgreSQL documentation for
  [COPY operations in libpq](https://www.postgresql.org/docs/current/libpq-copy.html)
  describes the protocol that every driver uses.
- The [Contributing a Recipe](../contributing.md) page explains how to add
  a recipe or a language to the cookbook.
