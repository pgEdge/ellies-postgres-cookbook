# Inserting Rows and Reading Generated Keys

This recipe demonstrates how an application inserts a row and learns the
key that the database server generated for it. The example uses the
`RETURNING` clause, which makes an `INSERT` statement send back values from
the new row, so the program needs no second query to find the key. Each
step shows the code in every supported language; selecting a language tab
switches every tab on the site to that language.

The example program creates a temporary table of people, in which the
server assigns each `id` from an identity column. The program inserts three
people and prints the id that the server chose for each one:

```text
Inserted 'Jane Doe' with id 1
Inserted 'John Smith' with id 2
Inserted 'Alex Example' with id 3
```

## Preparing the Ingredients

Each example uses the most widely adopted PostgreSQL driver for its
language, as in the
[first recipe](connect_and_query.md). The C example links against libpq,
so it requires the libpq client library and headers; on Debian and Ubuntu,
the `libpq-dev` package provides both. The following tabs show the
dependency declaration from each example project:

=== "Python"

    ```text
    --8<-- "recipes/postgresql/insert_returning/python/requirements.txt:deps"
    ```

=== "TypeScript"

    ```json
    --8<-- "recipes/postgresql/insert_returning/typescript/package.json"
    ```

=== "Java"

    ```xml
    --8<-- "recipes/postgresql/insert_returning/java/pom.xml:deps"
    ```

=== "C#"

    ```xml
    --8<-- "recipes/postgresql/insert_returning/csharp/InsertReturning.csproj:deps"
    ```

=== "Go"

    ```text
    --8<-- "recipes/postgresql/insert_returning/go/go.mod:deps"
    ```

=== "Rust"

    ```toml
    --8<-- "recipes/postgresql/insert_returning/rust/Cargo.toml:deps"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgresql/insert_returning/ruby/Gemfile:deps"
    ```

=== "C"

    ```make
    --8<-- "recipes/postgresql/insert_returning/c/Makefile:deps"
    ```

## Importing the Driver

Each program begins by importing the driver, along with any standard
library modules that the program uses. The following tabs show the imports
for each language:

=== "Python"

    ```python
    --8<-- "recipes/postgresql/insert_returning/python/main.py:imports"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgresql/insert_returning/typescript/main.ts:imports"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgresql/insert_returning/java/src/main/java/Main.java:imports"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgresql/insert_returning/csharp/Program.cs:imports"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgresql/insert_returning/go/main.go:imports"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgresql/insert_returning/rust/src/main.rs:imports"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgresql/insert_returning/ruby/main.rb:imports"
    ```

=== "C"

    ```c
    --8<-- "recipes/postgresql/insert_returning/c/main.c:imports"
    ```

## Configuring the Connection

The examples read their connection settings from the same environment
variables as the first recipe, and treat an empty variable as unset, as
libpq does. The variables are `PGHOST`, `PGPORT`, `PGDATABASE`, `PGUSER`,
and `PGPASSWORD`, with the defaults `localhost`, `5432`, `postgres`,
`postgres`, and no password. The following tabs show how each program
assembles the connection settings:

=== "Python"

    ```python
    --8<-- "recipes/postgresql/insert_returning/python/main.py:config"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgresql/insert_returning/typescript/main.ts:config"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgresql/insert_returning/java/src/main/java/Main.java:config"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgresql/insert_returning/csharp/Program.cs:config"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgresql/insert_returning/go/main.go:config"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgresql/insert_returning/rust/src/main.rs:config"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgresql/insert_returning/ruby/main.rb:config"
    ```

=== "C"

    ```c
    --8<-- "recipes/postgresql/insert_returning/c/main.c:config"
    ```

## Opening a Connection

Each program opens a connection to the server with the settings from the
previous step. A temporary table belongs to one connection, so every
statement in this example runs on the same connection. The C# program
borrows one connection from an Npgsql data source and keeps it for the
whole run. The following tabs show how each program opens the connection:

=== "Python"

    ```python
    --8<-- "recipes/postgresql/insert_returning/python/main.py:connect"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgresql/insert_returning/typescript/main.ts:connect"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgresql/insert_returning/java/src/main/java/Main.java:connect"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgresql/insert_returning/csharp/Program.cs:connect"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgresql/insert_returning/go/main.go:connect"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgresql/insert_returning/rust/src/main.rs:connect"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgresql/insert_returning/ruby/main.rb:connect"
    ```

=== "C"

    ```c
    --8<-- "recipes/postgresql/insert_returning/c/main.c:connect"
    ```

## Creating the Table

Each program creates a temporary table named `people`. A temporary table is
private to the connection and vanishes when the connection closes, so the
example leaves nothing behind and can run again straight away. The `id`
column is declared `GENERATED ALWAYS AS IDENTITY`, which makes the server
take each value from an internal sequence and refuse any attempt to supply
one. The following tabs show how each program creates the table:

=== "Python"

    ```python
    --8<-- "recipes/postgresql/insert_returning/python/main.py:setup"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgresql/insert_returning/typescript/main.ts:setup"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgresql/insert_returning/java/src/main/java/Main.java:setup"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgresql/insert_returning/csharp/Program.cs:setup"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgresql/insert_returning/go/main.go:setup"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgresql/insert_returning/rust/src/main.rs:setup"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgresql/insert_returning/ruby/main.rb:setup"
    ```

=== "C"

    ```c
    --8<-- "recipes/postgresql/insert_returning/c/main.c:setup"
    ```

## Inserting a Row and Reading Its Key

Each program inserts a row in a function that takes the name of the person
and returns the new id. The statement ends with `RETURNING id`, which turns
the `INSERT` into a statement that produces a result set with one row, in
the same way as a `SELECT`. The program therefore sends the statement as a
query and reads the id from the first column of the first row. Reading the
key this way is safe when several sessions insert at the same time, because
the server returns the value that it assigned to this row, whereas a
separate query for the largest id could return a row from another session.

The function sends the name as a parameter, so the server never interprets
it as SQL. The drivers differ slightly in how they run a statement that
returns rows:

- The Java program calls `executeQuery()` rather than `executeUpdate()`,
  because JDBC rejects a result set from an update call.
- The Python, TypeScript, Go, Rust, and Ruby programs use their ordinary
  query calls, and the C# program calls `ExecuteScalarAsync()`.
- The C program calls `PQexecParams()` and expects `PGRES_TUPLES_OK`,
  rather than the `PGRES_COMMAND_OK` that a plain `INSERT` returns. The C
  and Ruby drivers return the id as text, so those programs convert it to an
  integer.

The following tabs show how each program inserts a row:

=== "Python"

    ```python
    --8<-- "recipes/postgresql/insert_returning/python/main.py:add_person"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgresql/insert_returning/typescript/main.ts:add_person"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgresql/insert_returning/java/src/main/java/Main.java:add_person"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgresql/insert_returning/csharp/Program.cs:add_person"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgresql/insert_returning/go/main.go:add_person"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgresql/insert_returning/rust/src/main.rs:add_person"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgresql/insert_returning/ruby/main.rb:add_person"
    ```

=== "C"

    ```c
    --8<-- "recipes/postgresql/insert_returning/c/main.c:add_person"
    ```

## Handling Errors and Closing the Connection

The main part of each program creates the table, inserts the three people,
and prints the id of each one. The program reports any connection or query
failure on `stderr`, and then exits with a non-zero status. It also closes
the connection when the work completes or fails, in the same way as the
first recipe. The following tabs show the main part of each program:

=== "Python"

    ```python
    --8<-- "recipes/postgresql/insert_returning/python/main.py:main"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgresql/insert_returning/typescript/main.ts:main"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgresql/insert_returning/java/src/main/java/Main.java:main"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgresql/insert_returning/csharp/Program.cs:main"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgresql/insert_returning/go/main.go:main"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgresql/insert_returning/rust/src/main.rs:main"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgresql/insert_returning/ruby/main.rb:main"
    ```

=== "C"

    ```c
    --8<-- "recipes/postgresql/insert_returning/c/main.c:main"
    ```

## Running the Example

The complete project for each language is available in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/postgresql/insert_returning).
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
    --8<-- "recipes/postgresql/insert_returning/python/main.py"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgresql/insert_returning/typescript/main.ts"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgresql/insert_returning/java/src/main/java/Main.java"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgresql/insert_returning/csharp/Program.cs"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgresql/insert_returning/go/main.go"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgresql/insert_returning/rust/src/main.rs"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgresql/insert_returning/ruby/main.rb"
    ```

=== "C"

    ```c
    --8<-- "recipes/postgresql/insert_returning/c/main.c"
    ```

## Next Steps

The following resources provide more information about the topics in this
recipe:

- The [Connecting to PostgreSQL and Running a Query](connect_and_query.md)
  recipe explains the connection settings in more detail.
- The PostgreSQL documentation for
  [`RETURNING`](https://www.postgresql.org/docs/current/dml-returning.html)
  describes how to return data from `INSERT`, `UPDATE`, and `DELETE`.
- The PostgreSQL documentation for
  [identity columns](https://www.postgresql.org/docs/current/ddl-identity-columns.html)
  explains `GENERATED ALWAYS` and `GENERATED BY DEFAULT`.
