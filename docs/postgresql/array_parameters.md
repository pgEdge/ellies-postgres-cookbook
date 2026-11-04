# Passing a List of Values

This recipe demonstrates how an application passes a list of values to a
PostgreSQL query as a single parameter. The example finds which of four
names exist as data types in the `pg_catalog.pg_type` system catalog, by
sending all four names in one array and matching them with `= ANY(...)`.
Each step shows the code in every supported language; selecting a language
tab switches every tab on the site to that language.

The list contains `int4`, `text`, `bool`, and `no_such_type`. The first
three names exist on every PostgreSQL server and the last does not, so the
output is easy to verify:

```text
Found 3 of 4 types: bool, int4, text
```

## Choosing an Array over an IN List

A query that matches a column against a list of values often appears as
`WHERE name IN ('a', 'b', 'c')`. An application that builds that text has
to add one placeholder per value, or worse, paste the values into the SQL
string. Both approaches cause trouble: the SQL text changes with the length
of the list, so the server cannot reuse a prepared statement, and a value
pasted into the text invites SQL injection.

The `= ANY($1)` form takes the whole list as one array parameter instead.
The SQL text never changes, whatever the length of the list, and the
driver sends the values separately from the SQL, so the server never
interprets a value as SQL. The same form also works for an empty list,
which matches no rows, whereas an empty `IN ()` list is a syntax error.

## Preparing the Ingredients

This recipe uses the same drivers as the
[first recipe](connect_and_query.md), and the C and Ruby examples need
libpq, as before. The following tabs show the dependency declaration from
each example project:

=== "Python"

    ```text
    --8<-- "recipes/postgresql/array_parameters/python/requirements.txt:deps"
    ```

=== "TypeScript"

    ```json
    --8<-- "recipes/postgresql/array_parameters/typescript/package.json"
    ```

=== "Java"

    ```xml
    --8<-- "recipes/postgresql/array_parameters/java/pom.xml:deps"
    ```

=== "C#"

    ```xml
    --8<-- "recipes/postgresql/array_parameters/csharp/ArrayParameters.csproj:deps"
    ```

=== "Go"

    ```text
    --8<-- "recipes/postgresql/array_parameters/go/go.mod:deps"
    ```

=== "Rust"

    ```toml
    --8<-- "recipes/postgresql/array_parameters/rust/Cargo.toml:deps"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgresql/array_parameters/ruby/Gemfile:deps"
    ```

=== "C"

    ```make
    --8<-- "recipes/postgresql/array_parameters/c/Makefile:deps"
    ```

## Importing the Driver

Each program begins by importing the driver, along with any standard
library modules that the program uses. The following tabs show the imports
for each language:

=== "Python"

    ```python
    --8<-- "recipes/postgresql/array_parameters/python/main.py:imports"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgresql/array_parameters/typescript/main.ts:imports"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgresql/array_parameters/java/src/main/java/Main.java:imports"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgresql/array_parameters/csharp/Program.cs:imports"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgresql/array_parameters/go/main.go:imports"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgresql/array_parameters/rust/src/main.rs:imports"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgresql/array_parameters/ruby/main.rb:imports"
    ```

=== "C"

    ```c
    --8<-- "recipes/postgresql/array_parameters/c/main.c:imports"
    ```

## Configuring the Connection

The examples read their connection settings from the same five
environment variables as the first recipe: `PGHOST`, `PGPORT`,
`PGDATABASE`, `PGUSER`, and `PGPASSWORD`. Like libpq, each example treats
an empty variable as unset, and uses the default instead. The following
tabs show how each program assembles the connection settings:

=== "Python"

    ```python
    --8<-- "recipes/postgresql/array_parameters/python/main.py:config"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgresql/array_parameters/typescript/main.ts:config"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgresql/array_parameters/java/src/main/java/Main.java:config"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgresql/array_parameters/csharp/Program.cs:config"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgresql/array_parameters/go/main.go:config"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgresql/array_parameters/rust/src/main.rs:config"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgresql/array_parameters/ruby/main.rb:config"
    ```

=== "C"

    ```c
    --8<-- "recipes/postgresql/array_parameters/c/main.c:config"
    ```

## Opening a Connection

Each program opens a connection to the server with the settings from the
previous step. The C# program creates an Npgsql data source instead, which
lends out pooled connections when the main part of the program asks for
one. The following tabs show how each program opens the connection:

=== "Python"

    ```python
    --8<-- "recipes/postgresql/array_parameters/python/main.py:connect"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgresql/array_parameters/typescript/main.ts:connect"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgresql/array_parameters/java/src/main/java/Main.java:connect"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgresql/array_parameters/csharp/Program.cs:connect"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgresql/array_parameters/go/main.go:connect"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgresql/array_parameters/rust/src/main.rs:connect"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgresql/array_parameters/ruby/main.rb:connect"
    ```

=== "C"

    ```c
    --8<-- "recipes/postgresql/array_parameters/c/main.c:connect"
    ```

## Running the Query

Each program sends the list as the only parameter of the query, and then
reads the matching names from the first column of each row. The way that
each driver turns a list into an array parameter differs:

- Python, TypeScript, C#, Go, and Rust convert a native list, array, or
  slice into a PostgreSQL array automatically.
- Java builds an array with `createArrayOf()` and passes it with
  `setArray()`, and then calls `free()` on the array when the query is
  done.
- Ruby encodes the list as the text form of an array with
  `PG::TextEncoder::Array`, which quotes each element as needed.
- C has no array type, so the program builds the text form of an array,
  such as `{"int4","text"}`, and sends it as an ordinary text parameter. The
  `$1::text[]` cast in the query tells the server to read the text as an
  array.

The C program must quote the text form itself, because the server parses
that text as an array literal. Each element is wrapped in double quotes,
and a backslash or double quote inside an element is escaped with a
backslash; without this, an element containing a comma or a brace would
split into several elements or end the array early. This quoting only
protects the array syntax: the text is still a parameter, so the server
never executes it as SQL.

The following tabs show how each program runs the query and reads the
result:

=== "Python"

    ```python
    --8<-- "recipes/postgresql/array_parameters/python/main.py:query"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgresql/array_parameters/typescript/main.ts:query"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgresql/array_parameters/java/src/main/java/Main.java:query"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgresql/array_parameters/csharp/Program.cs:query"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgresql/array_parameters/go/main.go:query"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgresql/array_parameters/rust/src/main.rs:query"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgresql/array_parameters/ruby/main.rb:query"
    ```

=== "C"

    ```c
    --8<-- "recipes/postgresql/array_parameters/c/main.c:query"
    ```

## Handling Errors and Closing the Connection

The main part of each program calls the functions from the previous steps,
and prints the result. The program reports any connection or query failure
on `stderr`, and then exits with a non-zero status. The program also
closes the connection when the work completes or fails, using the same
mechanism as the first recipe in each language. The following tabs show
the main part of each program:

=== "Python"

    ```python
    --8<-- "recipes/postgresql/array_parameters/python/main.py:main"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgresql/array_parameters/typescript/main.ts:main"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgresql/array_parameters/java/src/main/java/Main.java:main"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgresql/array_parameters/csharp/Program.cs:main"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgresql/array_parameters/go/main.go:main"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgresql/array_parameters/rust/src/main.rs:main"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgresql/array_parameters/ruby/main.rb:main"
    ```

=== "C"

    ```c
    --8<-- "recipes/postgresql/array_parameters/c/main.c:main"
    ```

## Running the Example

The complete project for each language is available in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/postgresql/array_parameters).
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
    --8<-- "recipes/postgresql/array_parameters/python/main.py"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgresql/array_parameters/typescript/main.ts"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgresql/array_parameters/java/src/main/java/Main.java"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgresql/array_parameters/csharp/Program.cs"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgresql/array_parameters/go/main.go"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgresql/array_parameters/rust/src/main.rs"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgresql/array_parameters/ruby/main.rb"
    ```

=== "C"

    ```c
    --8<-- "recipes/postgresql/array_parameters/c/main.c"
    ```

## Next Steps

The following resources provide more information about the topics in this
recipe:

- The [Connecting to PostgreSQL and Running a Query](connect_and_query.md)
  recipe explains the connection settings and the parameter syntax of each
  driver.
- The PostgreSQL documentation for
  [row and array comparisons](https://www.postgresql.org/docs/current/functions-comparisons.html)
  describes `ANY` and `ALL`.
- The PostgreSQL documentation for
  [array input and output syntax](https://www.postgresql.org/docs/current/arrays.html#ARRAYS-IO)
  describes the quoting rules that the C program follows.
