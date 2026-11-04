# Using Transactions

This recipe demonstrates how an application groups several SQL statements
into a transaction, so that the database server applies either all of them
or none of them. The example moves money between two accounts, which needs
two updates that must succeed or fail together. Each step shows the code in
every supported language; selecting a language tab switches every tab on
the site to that language.

The example program creates a temporary table of two accounts, with
balances of 100 and 50. The program moves 30 from the first account to the
second, and then tries to move 500, which the table rejects because a
balance may not go below zero. The following output shows the result:

```text
Transferred 30 from account 1 to account 2
Transfer of 500 from account 1 to account 2 failed and was rolled back
Account 1 balance: 70
Account 2 balance: 80
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
    --8<-- "recipes/postgresql/transactions/python/requirements.txt:deps"
    ```

=== "TypeScript"

    ```json
    --8<-- "recipes/postgresql/transactions/typescript/package.json"
    ```

=== "Java"

    ```xml
    --8<-- "recipes/postgresql/transactions/java/pom.xml:deps"
    ```

=== "C#"

    ```xml
    --8<-- "recipes/postgresql/transactions/csharp/Transactions.csproj:deps"
    ```

=== "Go"

    ```text
    --8<-- "recipes/postgresql/transactions/go/go.mod:deps"
    ```

=== "Rust"

    ```toml
    --8<-- "recipes/postgresql/transactions/rust/Cargo.toml:deps"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgresql/transactions/ruby/Gemfile:deps"
    ```

=== "C"

    ```make
    --8<-- "recipes/postgresql/transactions/c/Makefile:deps"
    ```

## Importing the Driver

Each program begins by importing the driver, along with any standard
library modules that the program uses. The Python, Go, and Rust programs
also import the type that identifies a particular server error. The
following tabs show the imports for each language:

=== "Python"

    ```python
    --8<-- "recipes/postgresql/transactions/python/main.py:imports"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgresql/transactions/typescript/main.ts:imports"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgresql/transactions/java/src/main/java/Main.java:imports"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgresql/transactions/csharp/Program.cs:imports"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgresql/transactions/go/main.go:imports"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgresql/transactions/rust/src/main.rs:imports"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgresql/transactions/ruby/main.rb:imports"
    ```

=== "C"

    ```c
    --8<-- "recipes/postgresql/transactions/c/main.c:imports"
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
    --8<-- "recipes/postgresql/transactions/python/main.py:config"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgresql/transactions/typescript/main.ts:config"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgresql/transactions/java/src/main/java/Main.java:config"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgresql/transactions/csharp/Program.cs:config"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgresql/transactions/go/main.go:config"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgresql/transactions/rust/src/main.rs:config"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgresql/transactions/ruby/main.rb:config"
    ```

=== "C"

    ```c
    --8<-- "recipes/postgresql/transactions/c/main.c:config"
    ```

## Opening a Connection

Each program opens a connection to the server with the settings from the
previous step. A transaction belongs to one connection, and so does a
temporary table, so every statement in this example runs on the same
connection. The C# program borrows one connection from an Npgsql data
source and keeps it for the whole run. The Python program also turns on
autocommit mode, in which each statement commits by itself, because
psycopg otherwise opens a transaction before the first statement and
holds it open until the program commits; the program then chooses exactly
where each transaction begins and ends. The other drivers commit each
statement by itself until the program starts a transaction. The following
tabs show how each program opens the connection:

=== "Python"

    ```python
    --8<-- "recipes/postgresql/transactions/python/main.py:connect"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgresql/transactions/typescript/main.ts:connect"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgresql/transactions/java/src/main/java/Main.java:connect"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgresql/transactions/csharp/Program.cs:connect"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgresql/transactions/go/main.go:connect"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgresql/transactions/rust/src/main.rs:connect"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgresql/transactions/ruby/main.rb:connect"
    ```

=== "C"

    ```c
    --8<-- "recipes/postgresql/transactions/c/main.c:connect"
    ```

## Creating the Accounts

Each program creates a temporary table named `accounts`, and inserts the
two accounts. A temporary table is private to the connection and vanishes
when the connection closes, so the example leaves nothing behind and can
run again straight away. The `CHECK (balance >= 0)` constraint makes the
server reject any change that would leave a balance below zero; that
rejection is what makes the second transfer fail. The following tabs show
how each program creates the table:

=== "Python"

    ```python
    --8<-- "recipes/postgresql/transactions/python/main.py:setup"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgresql/transactions/typescript/main.ts:setup"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgresql/transactions/java/src/main/java/Main.java:setup"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgresql/transactions/csharp/Program.cs:setup"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgresql/transactions/go/main.go:setup"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgresql/transactions/rust/src/main.rs:setup"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgresql/transactions/ruby/main.rb:setup"
    ```

=== "C"

    ```c
    --8<-- "recipes/postgresql/transactions/c/main.c:setup"
    ```

## Making a Transfer

Each program moves money in a function that credits the target account and
then debits the source account, both inside one transaction. The function
sends the amount and the account numbers as parameters, so the server never
interprets them as SQL. If both updates succeed, the function commits the
transaction and both changes become visible at once. If either update
fails, the function rolls the transaction back, and the server discards
every change made since the transaction began.

The function credits the target first on purpose. When the debit fails
because of the check constraint, the credit has already happened inside the
transaction, so the unchanged balances at the end of the program prove that
the rollback undid it.

The drivers differ in how much of this they do for the program:

- The Python `transaction()` block and the Ruby `transaction` method
  commit when the work ends normally and roll back when an error leaves
  it.
- The Go `Begin()`, C# `BeginTransactionAsync()`, and Rust `transaction()`
  calls return a transaction object that rolls back if the program never
  commits it, so each program calls `commit()` explicitly. The Go program
  defers a `Rollback()` call, which does nothing after a commit, the C#
  program disposes of the object with `await using`, and the Rust program
  drops the object when the `?` operator returns an error.
- The Java program turns off autocommit, commits explicitly, rolls back if
  any exception occurs, and turns autocommit back on in a `finally` block.
- The TypeScript and C programs send `BEGIN`, `COMMIT`, and `ROLLBACK`
  themselves, because node-postgres and libpq have no transaction object.

The following tabs show how each program makes a transfer:

=== "Python"

    ```python
    --8<-- "recipes/postgresql/transactions/python/main.py:transfer"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgresql/transactions/typescript/main.ts:transfer"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgresql/transactions/java/src/main/java/Main.java:transfer"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgresql/transactions/csharp/Program.cs:transfer"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgresql/transactions/go/main.go:transfer"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgresql/transactions/rust/src/main.rs:transfer"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgresql/transactions/ruby/main.rb:transfer"
    ```

=== "C"

    ```c
    --8<-- "recipes/postgresql/transactions/c/main.c:transfer"
    ```

## Reading the Balances

Each program reads a balance with a parameterised query, after the
transfers, to show the state that the server kept. The C and Ruby drivers
return every value as text, so those programs convert the value to an
integer. The following tabs show how each program reads a balance:

=== "Python"

    ```python
    --8<-- "recipes/postgresql/transactions/python/main.py:balance"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgresql/transactions/typescript/main.ts:balance"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgresql/transactions/java/src/main/java/Main.java:balance"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgresql/transactions/csharp/Program.cs:balance"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgresql/transactions/go/main.go:balance"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgresql/transactions/rust/src/main.rs:balance"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgresql/transactions/ruby/main.rb:balance"
    ```

=== "C"

    ```c
    --8<-- "recipes/postgresql/transactions/c/main.c:balance"
    ```

## Handling Errors and Closing the Connection

The main part of each program creates the accounts, makes the transfer of
30, and then attempts the transfer of 500. A check constraint violation
has the SQLSTATE code `23514`, and the program treats that single error as
an expected outcome: it reports that the transfer was rolled back and
carries on. Any other error is unexpected, so the program reports it on
`stderr` and exits with a non-zero status, as does a failure to connect.

The Python, Ruby, and C# programs catch a specific error class for the
constraint violation (`CheckViolation` in Python and Ruby, and a
`PostgresException` filtered on its SQLSTATE in C#). The TypeScript, Java,
and C programs compare the SQLSTATE code with `23514`, and the Go and Rust
programs do the same through the error types of their drivers. The program
also closes the connection when the work completes or fails, in the same
way as the first recipe. The following tabs show the main part of each
program:

=== "Python"

    ```python
    --8<-- "recipes/postgresql/transactions/python/main.py:main"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgresql/transactions/typescript/main.ts:main"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgresql/transactions/java/src/main/java/Main.java:main"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgresql/transactions/csharp/Program.cs:main"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgresql/transactions/go/main.go:main"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgresql/transactions/rust/src/main.rs:main"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgresql/transactions/ruby/main.rb:main"
    ```

=== "C"

    ```c
    --8<-- "recipes/postgresql/transactions/c/main.c:main"
    ```

## Running the Example

The complete project for each language is available in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/postgresql/transactions).
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
    --8<-- "recipes/postgresql/transactions/python/main.py"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgresql/transactions/typescript/main.ts"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgresql/transactions/java/src/main/java/Main.java"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgresql/transactions/csharp/Program.cs"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgresql/transactions/go/main.go"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgresql/transactions/rust/src/main.rs"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgresql/transactions/ruby/main.rb"
    ```

=== "C"

    ```c
    --8<-- "recipes/postgresql/transactions/c/main.c"
    ```

## Next Steps

The following resources provide more information about the topics in this
recipe:

- The [Connecting to PostgreSQL and Running a Query](connect_and_query.md)
  recipe explains the connection settings in more detail.
- The PostgreSQL documentation for
  [transactions](https://www.postgresql.org/docs/current/tutorial-transactions.html)
  introduces the concept with an example.
- The PostgreSQL documentation for
  [error codes](https://www.postgresql.org/docs/current/errcodes-appendix.html)
  lists every SQLSTATE code, including `23514`.
- The PostgreSQL documentation for
  [constraints](https://www.postgresql.org/docs/current/ddl-constraints.html)
  describes check constraints and the other kinds.
