# Storing and Searching Vectors with pgvector

This recipe demonstrates how an application stores vectors in PostgreSQL and
finds the rows nearest to a query vector, using the
[pgvector](https://github.com/pgvector/pgvector) extension. Vectors are the
numeric form of embeddings, which represent text, images, and other data in
a way that makes similar items lie close together. The example uses
three-dimensional vectors that hold the red, green, and blue components of
five colours, so that the nearest colours are easy to check by eye. Each
step shows the code in every supported language; selecting a language tab
switches every tab on the site to that language.

The example program stores the five colours, and then asks for the three
colours nearest to the vector `[0.9,0.7,0.2]`, which is a muddy orange. The
program prints the colours in order of increasing Euclidean distance:

```text
Colours nearest to [0.9,0.7,0.2]:
1. yellow
2. red
3. white
```

## Preparing the Ingredients

The server needs the pgvector extension installed, and the user that runs
the program needs permission to create extensions; the `pgvector/pgvector`
Docker images include the extension, and most managed PostgreSQL services
offer it. Each example uses the same driver as the
[first recipe](connect_and_query.md), and sends vectors to the server as
text, so no extra library is required. The following table lists each
language's driver, and the optional pgvector client library that converts
vectors to and from native types such as arrays:

| Language   | Driver                                          | pgvector client library |
|------------|-------------------------------------------------|-------------------------|
| Python     | [psycopg 3](https://www.psycopg.org/psycopg3/)  | [pgvector](https://github.com/pgvector/pgvector-python) |
| TypeScript | [node-postgres](https://node-postgres.com/)     | [pgvector](https://github.com/pgvector/pgvector-node) |
| Java       | [pgJDBC](https://jdbc.postgresql.org/)          | [com.pgvector:pgvector](https://github.com/pgvector/pgvector-java) |
| C#         | [Npgsql](https://www.npgsql.org/)               | [Pgvector](https://github.com/pgvector/pgvector-dotnet) |
| Go         | [pgx](https://github.com/jackc/pgx)             | [pgvector-go](https://github.com/pgvector/pgvector-go) |
| Rust       | [rust-postgres](https://github.com/rust-postgres/rust-postgres) | [pgvector](https://github.com/pgvector/pgvector-rust) |
| Ruby       | [ruby-pg](https://github.com/ged/ruby-pg)      | [pgvector](https://github.com/pgvector/pgvector-ruby) |
| C          | [libpq](https://www.postgresql.org/docs/current/libpq.html) | None; use the text format |

The dependency declarations are the same as those of the first recipe,
because the examples add no libraries. The following tabs show the
declaration from each example project:

=== "Python"

    ```text
    --8<-- "recipes/postgresql/pgvector_search/python/requirements.txt:deps"
    ```

=== "TypeScript"

    ```json
    --8<-- "recipes/postgresql/pgvector_search/typescript/package.json"
    ```

=== "Java"

    ```xml
    --8<-- "recipes/postgresql/pgvector_search/java/pom.xml:deps"
    ```

=== "C#"

    ```xml
    --8<-- "recipes/postgresql/pgvector_search/csharp/PgvectorSearch.csproj:deps"
    ```

=== "Go"

    ```text
    --8<-- "recipes/postgresql/pgvector_search/go/go.mod:deps"
    ```

=== "Rust"

    ```toml
    --8<-- "recipes/postgresql/pgvector_search/rust/Cargo.toml:deps"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgresql/pgvector_search/ruby/Gemfile:deps"
    ```

=== "C"

    ```make
    --8<-- "recipes/postgresql/pgvector_search/c/Makefile:deps"
    ```

## Importing the Driver

Each program begins by importing the driver, along with any standard
library modules that the program uses. The following tabs show the imports
for each language:

=== "Python"

    ```python
    --8<-- "recipes/postgresql/pgvector_search/python/main.py:imports"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgresql/pgvector_search/typescript/main.ts:imports"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgresql/pgvector_search/java/src/main/java/Main.java:imports"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgresql/pgvector_search/csharp/Program.cs:imports"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgresql/pgvector_search/go/main.go:imports"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgresql/pgvector_search/rust/src/main.rs:imports"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgresql/pgvector_search/ruby/main.rb:imports"
    ```

=== "C"

    ```c
    --8<-- "recipes/postgresql/pgvector_search/c/main.c:imports"
    ```

## Configuring the Connection

The examples read their connection settings from the same environment
variables as the first recipe: `PGHOST`, `PGPORT`, `PGDATABASE`, `PGUSER`,
and `PGPASSWORD`. Each example treats an empty variable as unset, and uses
the default instead. The following tabs show how each program assembles the
connection settings:

=== "Python"

    ```python
    --8<-- "recipes/postgresql/pgvector_search/python/main.py:config"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgresql/pgvector_search/typescript/main.ts:config"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgresql/pgvector_search/java/src/main/java/Main.java:config"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgresql/pgvector_search/csharp/Program.cs:config"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgresql/pgvector_search/go/main.go:config"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgresql/pgvector_search/rust/src/main.rs:config"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgresql/pgvector_search/ruby/main.rb:config"
    ```

=== "C"

    ```c
    --8<-- "recipes/postgresql/pgvector_search/c/main.c:config"
    ```

## Opening a Connection

Each program opens a single connection and uses it for every step, because
a temporary table belongs to one session. The C# program creates an Npgsql
data source and borrows one connection from it. The following tabs show
how each program opens the connection:

=== "Python"

    ```python
    --8<-- "recipes/postgresql/pgvector_search/python/main.py:connect"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgresql/pgvector_search/typescript/main.ts:connect"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgresql/pgvector_search/java/src/main/java/Main.java:connect"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgresql/pgvector_search/csharp/Program.cs:connect"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgresql/pgvector_search/go/main.go:connect"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgresql/pgvector_search/rust/src/main.rs:connect"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgresql/pgvector_search/ruby/main.rb:connect"
    ```

=== "C"

    ```c
    --8<-- "recipes/postgresql/pgvector_search/c/main.c:connect"
    ```

## Creating the Schema

The program enables the extension, creates a table with a `vector(3)`
column, and builds an index on that column. The `CREATE EXTENSION IF NOT
EXISTS` statement does nothing if the extension is already present. The
number in `vector(3)` fixes the dimensions of every value in the column;
the server rejects a vector with any other number of elements. The table is
`TEMPORARY`, so it disappears when the session ends and the program can run
repeatedly.

The index uses the Hierarchical Navigable Small World (HNSW) method with the
`vector_l2_ops` operator class, which matches the `<->` operator that
measures Euclidean (L2) distance. Use `vector_cosine_ops` for cosine
distance, or `vector_ip_ops` for inner product, if the search uses the
`<=>` or `<#>` operator instead. An HNSW index is approximate: it trades a
small chance of missing a true neighbour for much faster searches on large
tables. The five rows in this example are too few for that to matter, and
the planner may simply scan the table, so the program always prints the
exact order. The following tabs show the schema statements for
each language:

=== "Python"

    ```python
    --8<-- "recipes/postgresql/pgvector_search/python/main.py:schema"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgresql/pgvector_search/typescript/main.ts:schema"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgresql/pgvector_search/java/src/main/java/Main.java:schema"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgresql/pgvector_search/csharp/Program.cs:schema"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgresql/pgvector_search/go/main.go:schema"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgresql/pgvector_search/rust/src/main.rs:schema"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgresql/pgvector_search/ruby/main.rb:schema"
    ```

=== "C"

    ```c
    --8<-- "recipes/postgresql/pgvector_search/c/main.c:schema"
    ```

## Inserting Vectors

Each program inserts the five colours one row at a time. A vector is
written as text in the form `[x,y,z]`, which each program passes as an
ordinary text parameter and converts on the server with a `::vector` cast.
This approach needs no pgvector client library, and the same statement
works in every language. The Rust program writes `::text::vector`, because
the rust-postgres driver checks the type of each parameter against the Rust
value and refuses to send a string as a `vector`; the `::text` cast declares
the parameter as text first. The following tabs show how each program
inserts the rows:

=== "Python"

    ```python
    --8<-- "recipes/postgresql/pgvector_search/python/main.py:insert"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgresql/pgvector_search/typescript/main.ts:insert"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgresql/pgvector_search/java/src/main/java/Main.java:insert"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgresql/pgvector_search/csharp/Program.cs:insert"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgresql/pgvector_search/go/main.go:insert"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgresql/pgvector_search/rust/src/main.rs:insert"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgresql/pgvector_search/ruby/main.rb:insert"
    ```

=== "C"

    ```c
    --8<-- "recipes/postgresql/pgvector_search/c/main.c:insert"
    ```

## Searching for the Nearest Vectors

The search orders the rows by their distance from the query vector, and
returns the first three. PostgreSQL can use the HNSW index to answer a query
of this shape, which has an `ORDER BY` on the distance operator and a
`LIMIT`. The query vector is another text parameter with a `::vector` cast,
and the limit is a parameter too. The C program sends every parameter as
text, so it converts the limit to a string first. The following tabs show
how each program runs the search and reads the names in order:

=== "Python"

    ```python
    --8<-- "recipes/postgresql/pgvector_search/python/main.py:search"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgresql/pgvector_search/typescript/main.ts:search"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgresql/pgvector_search/java/src/main/java/Main.java:search"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgresql/pgvector_search/csharp/Program.cs:search"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgresql/pgvector_search/go/main.go:search"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgresql/pgvector_search/rust/src/main.rs:search"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgresql/pgvector_search/ruby/main.rb:search"
    ```

=== "C"

    ```c
    --8<-- "recipes/postgresql/pgvector_search/c/main.c:search"
    ```

## Handling Errors and Closing the Connection

The main part of each program calls the functions from the previous steps,
and prints the colours with their rank. The program reports any connection
or query failure on `stderr`, and then exits with a non-zero status; this
includes the error that the server raises if the extension is not available.
Each program closes the connection when the work completes or fails, using
the same mechanism as the first recipe. The following tabs show the main
part of each program:

=== "Python"

    ```python
    --8<-- "recipes/postgresql/pgvector_search/python/main.py:main"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgresql/pgvector_search/typescript/main.ts:main"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgresql/pgvector_search/java/src/main/java/Main.java:main"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgresql/pgvector_search/csharp/Program.cs:main"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgresql/pgvector_search/go/main.go:main"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgresql/pgvector_search/rust/src/main.rs:main"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgresql/pgvector_search/ruby/main.rb:main"
    ```

=== "C"

    ```c
    --8<-- "recipes/postgresql/pgvector_search/c/main.c:main"
    ```

## Running the Example

The complete project for each language is available in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/postgresql/pgvector_search).
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
    --8<-- "recipes/postgresql/pgvector_search/python/main.py"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgresql/pgvector_search/typescript/main.ts"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgresql/pgvector_search/java/src/main/java/Main.java"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgresql/pgvector_search/csharp/Program.cs"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgresql/pgvector_search/go/main.go"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgresql/pgvector_search/rust/src/main.rs"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgresql/pgvector_search/ruby/main.rb"
    ```

=== "C"

    ```c
    --8<-- "recipes/postgresql/pgvector_search/c/main.c"
    ```

## Next Steps

The following resources provide more information about the topics in this
recipe:

- The [pgvector README](https://github.com/pgvector/pgvector#readme)
  describes the vector types, the distance operators, and the options for
  both the HNSW and IVFFlat indexes.
- The pgvector documentation on
  [querying](https://github.com/pgvector/pgvector#querying) explains how to
  tune `hnsw.ef_search` to trade speed for accuracy.
- The [first recipe](connect_and_query.md) explains the connection settings
  that every example uses.
