# Retrying Serialisation Failures

This recipe demonstrates how an application retries a transaction that
PostgreSQL rejects with a serialisation failure or a deadlock. These errors
do not mean that the application is wrong; they mean that two transactions
conflicted, and that running the losing transaction again will normally
succeed. Each step shows the code in every supported language; selecting a
language tab switches every tab on the site to that language.

The example program keeps a counter in a one-row table, and adds one to the
counter inside a `REPEATABLE READ` transaction. On the first attempt, a
second connection changes the counter after the transaction has read it but
before the transaction writes it, which makes the server reject the write
with SQLSTATE `40001`. The program rolls back, waits briefly, and runs the
transaction again; the second attempt succeeds. The conflict is arranged
deterministically, so the output is the same on every run:

```text
Attempt 1: serialisation failure, retrying
Attempt 2: committed
Counter value: 2
```

## Understanding When to Retry

Under the `REPEATABLE READ` and `SERIALIZABLE` isolation levels, the server
raises an error rather than let a transaction overwrite a change that it
cannot see, or commit a result that no serial order of the transactions
could produce. The error carries one of two SQLSTATE codes that mean "try
again":

| SQLSTATE | Name                    | Meaning                         |
|----------|-------------------------|---------------------------------|
| `40001`  | `serialization_failure` | A conflict with another client. |
| `40P01`  | `deadlock_detected`     | The server ended a deadlock.    |

The retry wrapper checks the SQLSTATE code of each error, and retries only
for these two codes; any other error is a real failure and the wrapper
raises it again. The wrapper also gives up after five attempts, because a
transaction that fails repeatedly needs attention rather than more
retries. Every retry runs the whole transaction from the start, including
the reads, so the code inside the transaction must be safe to run more than
once; a transaction must never send an email or call another service
before it commits.

!!! note

    The `SERIALIZABLE` isolation level also raises `40001`, and the same
    wrapper handles it. The example uses `REPEATABLE READ` because a
    single conflicting update produces the error without any further set-up.

## Preparing the Ingredients

Each example uses the most widely adopted PostgreSQL driver for its
language. The C example links against libpq, so the example requires the
libpq client library and headers; on Debian and Ubuntu, the `libpq-dev`
package provides both. The following tabs show the dependency declaration
from each example project:

=== "Python"

    ```text
    --8<-- "recipes/postgresql/retry_transactions/python/requirements.txt:deps"
    ```

=== "TypeScript"

    ```json
    --8<-- "recipes/postgresql/retry_transactions/typescript/package.json"
    ```

=== "Java"

    ```xml
    --8<-- "recipes/postgresql/retry_transactions/java/pom.xml:deps"
    ```

=== "C#"

    ```xml
    --8<-- "recipes/postgresql/retry_transactions/csharp/RetryTransactions.csproj:deps"
    ```

=== "Go"

    ```text
    --8<-- "recipes/postgresql/retry_transactions/go/go.mod:deps"
    ```

=== "Rust"

    ```toml
    --8<-- "recipes/postgresql/retry_transactions/rust/Cargo.toml:deps"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgresql/retry_transactions/ruby/Gemfile:deps"
    ```

=== "C"

    ```make
    --8<-- "recipes/postgresql/retry_transactions/c/Makefile:deps"
    ```

## Importing the Driver

Each program begins by importing the driver, along with any standard
library modules that the program uses. The following tabs show the imports
for each language:

=== "Python"

    ```python
    --8<-- "recipes/postgresql/retry_transactions/python/main.py:imports"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgresql/retry_transactions/typescript/main.ts:imports"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgresql/retry_transactions/java/src/main/java/Main.java:imports"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgresql/retry_transactions/csharp/Program.cs:imports"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgresql/retry_transactions/go/main.go:imports"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgresql/retry_transactions/rust/src/main.rs:imports"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgresql/retry_transactions/ruby/main.rb:imports"
    ```

=== "C"

    ```c
    --8<-- "recipes/postgresql/retry_transactions/c/main.c:imports"
    ```

## Configuring the Connection

The examples read their connection settings from the same environment
variables that libpq and `psql` use, and treat an empty variable as unset,
as the [first recipe](connect_and_query.md) describes. This step also
defines the two SQLSTATE codes that trigger a retry, and the maximum number
of attempts. The following tabs show the configuration for each language:

=== "Python"

    ```python
    --8<-- "recipes/postgresql/retry_transactions/python/main.py:config"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgresql/retry_transactions/typescript/main.ts:config"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgresql/retry_transactions/java/src/main/java/Main.java:config"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgresql/retry_transactions/csharp/Program.cs:config"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgresql/retry_transactions/go/main.go:config"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgresql/retry_transactions/rust/src/main.rs:config"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgresql/retry_transactions/ruby/main.rb:config"
    ```

=== "C"

    ```c
    --8<-- "recipes/postgresql/retry_transactions/c/main.c:config"
    ```

## Opening a Connection

Each program opens a connection with the settings from the previous step.
The program needs a second connection later, to simulate a competing
client, so it calls the same function again; the C# program borrows the
second connection from the pool of its data source instead. The
connections run each statement in its own transaction until the program
asks for a transaction explicitly; the Python program sets autocommit mode
to get this behaviour, and the other drivers do this by default or when
the program sends `BEGIN`. The following tabs show how each program opens
the connection:

=== "Python"

    ```python
    --8<-- "recipes/postgresql/retry_transactions/python/main.py:connect"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgresql/retry_transactions/typescript/main.ts:connect"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgresql/retry_transactions/java/src/main/java/Main.java:connect"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgresql/retry_transactions/csharp/Program.cs:connect"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgresql/retry_transactions/go/main.go:connect"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgresql/retry_transactions/rust/src/main.rs:connect"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgresql/retry_transactions/ruby/main.rb:connect"
    ```

=== "C"

    ```c
    --8<-- "recipes/postgresql/retry_transactions/c/main.c:connect"
    ```

## Preparing the Table

The example needs a table that a second connection can see, so it cannot
use a temporary table. The table is named `cookbook_retry_transactions` to
avoid clashing with anything else in the database, and the program drops
the table before it creates the table and again when it finishes, so the
program is safe to run repeatedly. The table holds a single row with the
counter set to zero. The following tabs show how each program creates and
drops the table:

=== "Python"

    ```python
    --8<-- "recipes/postgresql/retry_transactions/python/main.py:setup"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgresql/retry_transactions/typescript/main.ts:setup"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgresql/retry_transactions/java/src/main/java/Main.java:setup"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgresql/retry_transactions/csharp/Program.cs:setup"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgresql/retry_transactions/go/main.go:setup"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgresql/retry_transactions/rust/src/main.rs:setup"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgresql/retry_transactions/ruby/main.rb:setup"
    ```

=== "C"

    ```c
    --8<-- "recipes/postgresql/retry_transactions/c/main.c:setup"
    ```

## Writing the Transaction

The work of the transaction is a function that takes the connection and
the attempt number. The function reads the counter, and then writes back
the value plus one. On the first attempt only, the function updates the
same row from a second connection between the read and the write; that
connection commits immediately, so the original transaction's snapshot is
now out of date. When the original transaction tries to update the row, the
server raises SQLSTATE `40001`, which each driver reports as an error that
carries the code. The second attempt reads the new value, and the update
succeeds. The following tabs show the transaction in each language:

=== "Python"

    ```python
    --8<-- "recipes/postgresql/retry_transactions/python/main.py:work"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgresql/retry_transactions/typescript/main.ts:work"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgresql/retry_transactions/java/src/main/java/Main.java:work"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgresql/retry_transactions/csharp/Program.cs:work"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgresql/retry_transactions/go/main.go:work"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgresql/retry_transactions/rust/src/main.rs:work"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgresql/retry_transactions/ruby/main.rb:work"
    ```

=== "C"

    ```c
    --8<-- "recipes/postgresql/retry_transactions/c/main.c:work"
    ```

## Retrying the Transaction

The retry wrapper runs the work in a `REPEATABLE READ` transaction, and
commits when the work returns normally. The Python `transaction()` block,
the Go and Rust transaction objects, and the C# transaction handle roll
back on any error; the TypeScript, Java, Ruby, and C programs send
`ROLLBACK` or call `rollback()` themselves. When the error carries a retry
code and attempts remain, the wrapper prints a message, sleeps for 50
milliseconds multiplied by the attempt number, and loops. The growing
pause is a simple back-off that gives the competing transaction time to
finish; a busy production system would normally add some random jitter, so
that many clients do not retry at the same moment. The following tabs show
the wrapper in each language:

=== "Python"

    ```python
    --8<-- "recipes/postgresql/retry_transactions/python/main.py:retry"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgresql/retry_transactions/typescript/main.ts:retry"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgresql/retry_transactions/java/src/main/java/Main.java:retry"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgresql/retry_transactions/csharp/Program.cs:retry"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgresql/retry_transactions/go/main.go:retry"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgresql/retry_transactions/rust/src/main.rs:retry"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgresql/retry_transactions/ruby/main.rb:retry"
    ```

=== "C"

    ```c
    --8<-- "recipes/postgresql/retry_transactions/c/main.c:retry"
    ```

## Handling Errors and Closing the Connection

The main part of each program creates the table, runs the transaction
through the retry wrapper, reads the final counter, and prints the result.
The cleanup drops the table whether or not the work succeeded, using a
`finally` or `ensure` block, a deferred call, or the equivalent in each
language, before the program closes the connection. The program reports
any connection or query failure on `stderr`, and then exits with a non-zero
status. The following tabs show the main part of each program:

=== "Python"

    ```python
    --8<-- "recipes/postgresql/retry_transactions/python/main.py:main"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgresql/retry_transactions/typescript/main.ts:main"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgresql/retry_transactions/java/src/main/java/Main.java:main"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgresql/retry_transactions/csharp/Program.cs:main"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgresql/retry_transactions/go/main.go:main"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgresql/retry_transactions/rust/src/main.rs:main"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgresql/retry_transactions/ruby/main.rb:main"
    ```

=== "C"

    ```c
    --8<-- "recipes/postgresql/retry_transactions/c/main.c:main"
    ```

## Running the Example

The complete project for each language is available in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/postgresql/retry_transactions).
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
    --8<-- "recipes/postgresql/retry_transactions/python/main.py"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgresql/retry_transactions/typescript/main.ts"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgresql/retry_transactions/java/src/main/java/Main.java"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgresql/retry_transactions/csharp/Program.cs"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgresql/retry_transactions/go/main.go"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgresql/retry_transactions/rust/src/main.rs"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgresql/retry_transactions/ruby/main.rb"
    ```

=== "C"

    ```c
    --8<-- "recipes/postgresql/retry_transactions/c/main.c"
    ```

## Next Steps

The following resources provide more information about the topics in this
recipe:

- The [Connecting to PostgreSQL and Running a Query](connect_and_query.md)
  recipe explains the connection settings that every example uses.
- The PostgreSQL documentation for
  [transaction isolation](https://www.postgresql.org/docs/current/transaction-iso.html)
  describes the isolation levels and the errors that they raise.
- The PostgreSQL documentation for
  [serialization failure handling](https://www.postgresql.org/docs/current/mvcc-serialization-failure-handling.html)
  explains why applications must retry.
- The PostgreSQL documentation for
  [error codes](https://www.postgresql.org/docs/current/errcodes-appendix.html)
  lists every SQLSTATE code.
