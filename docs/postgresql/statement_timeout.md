# Setting a Statement Timeout

This recipe demonstrates how an application limits the time that a single
statement may run on the server, and how it recovers when the server
cancels a statement that runs for too long. A statement timeout protects
the database from runaway queries, and protects the application from
waiting indefinitely for a reply. Each step shows the code in every
supported language; selecting a language tab switches every tab on the site
to that language.

The example program sets the timeout to 100 milliseconds and runs
`SELECT pg_sleep(5)`, which would otherwise take five seconds. The server
cancels the statement and reports SQLSTATE `57014`, which the program
catches and handles. The program then runs `SELECT 1` to show that the
connection is still usable after the cancellation. The output is the same
on every run:

```text
Query cancelled after exceeding the statement timeout
Connection still usable: true
```

!!! note

    This recipe covers server-side timeouts only. The server enforces the
    timeout and cancels the statement itself, which works the same way for
    every driver. Client-side timeouts and cancellation, such as a socket
    timeout or a call that cancels a running query from another thread,
    differ too much between drivers to show in a uniform way, so this
    recipe leaves them out; the documentation for your driver describes
    them.

## Understanding the Statement Timeout

The `statement_timeout` setting is a limit on the run time of each
statement. A value of zero, which is the default, disables the limit. When
a statement exceeds the limit, the server stops the statement, rolls back
any work that the statement did, and returns an error with SQLSTATE
`57014` (`query_canceled`). Because the server enforces the limit, the
timeout still applies if the network drops or the client stops responding.

The setting takes a number of milliseconds, or a value with a unit such as
`100ms` or `5s`. There are two common ways to apply the setting to a
session. The first is to run an SQL command after connecting:

```sql
SET statement_timeout = '100ms';
```

The second is to ask for the setting when the connection starts, using the
`options` connection parameter of libpq, which the `PGOPTIONS` environment
variable also supplies:

```bash
PGOPTIONS="-c statement_timeout=100ms" psql
```

The second form has the advantage that the limit applies from the first
statement, and that application code cannot forget it; many drivers pass an
`options` setting through to the server. The examples use the first form,
because it works in every language in the same way. A timeout can also be
set for a role or a database with `ALTER ROLE ... SET` or `ALTER DATABASE
... SET`.

The error with code `57014` also appears when a user or a client cancels a
statement, so the program tests for the code rather than for the text of
the message. Other errors, such as a syntax error or a lost connection, are
real failures: the program lets them reach the main part of the program,
which reports them and exits with a non-zero status.

## Preparing the Ingredients

Each example uses the most widely adopted PostgreSQL driver for its
language. The C example links against libpq, so the example requires the
libpq client library and headers; on Debian and Ubuntu, the `libpq-dev`
package provides both. The following tabs show the dependency declaration
from each example project:

=== "Python"

    ```text
    --8<-- "recipes/postgresql/statement_timeout/python/requirements.txt:deps"
    ```

=== "TypeScript"

    ```json
    --8<-- "recipes/postgresql/statement_timeout/typescript/package.json"
    ```

=== "Java"

    ```xml
    --8<-- "recipes/postgresql/statement_timeout/java/pom.xml:deps"
    ```

=== "C#"

    ```xml
    --8<-- "recipes/postgresql/statement_timeout/csharp/StatementTimeout.csproj:deps"
    ```

=== "Go"

    ```text
    --8<-- "recipes/postgresql/statement_timeout/go/go.mod:deps"
    ```

=== "Rust"

    ```toml
    --8<-- "recipes/postgresql/statement_timeout/rust/Cargo.toml:deps"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgresql/statement_timeout/ruby/Gemfile:deps"
    ```

=== "C"

    ```make
    --8<-- "recipes/postgresql/statement_timeout/c/Makefile:deps"
    ```

## Importing the Driver

Each program begins by importing the driver, along with any standard
library modules that the program uses. The following tabs show the imports
for each language:

=== "Python"

    ```python
    --8<-- "recipes/postgresql/statement_timeout/python/main.py:imports"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgresql/statement_timeout/typescript/main.ts:imports"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgresql/statement_timeout/java/src/main/java/Main.java:imports"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgresql/statement_timeout/csharp/Program.cs:imports"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgresql/statement_timeout/go/main.go:imports"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgresql/statement_timeout/rust/src/main.rs:imports"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgresql/statement_timeout/ruby/main.rb:imports"
    ```

=== "C"

    ```c
    --8<-- "recipes/postgresql/statement_timeout/c/main.c:imports"
    ```

## Configuring the Connection

The examples read their connection settings from the same environment
variables that libpq and `psql` use, and treat an empty variable as unset,
as the [first recipe](connect_and_query.md) describes. This step also
defines the SQLSTATE code that identifies a cancelled statement. The
following tabs show the configuration for each language:

=== "Python"

    ```python
    --8<-- "recipes/postgresql/statement_timeout/python/main.py:config"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgresql/statement_timeout/typescript/main.ts:config"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgresql/statement_timeout/java/src/main/java/Main.java:config"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgresql/statement_timeout/csharp/Program.cs:config"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgresql/statement_timeout/go/main.go:config"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgresql/statement_timeout/rust/src/main.rs:config"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgresql/statement_timeout/ruby/main.rb:config"
    ```

=== "C"

    ```c
    --8<-- "recipes/postgresql/statement_timeout/c/main.c:config"
    ```

## Opening a Connection

Each program opens a connection with the settings from the previous step.
The connection runs each statement in its own transaction until the
program asks for a transaction explicitly; the Python program sets
autocommit mode to get this behaviour, and the other drivers do this by
default. This matters because a statement that fails inside a transaction
leaves the transaction in a failed state, and the session would then
reject the follow-up query. The following tabs show how each program
opens the connection:

=== "Python"

    ```python
    --8<-- "recipes/postgresql/statement_timeout/python/main.py:connect"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgresql/statement_timeout/typescript/main.ts:connect"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgresql/statement_timeout/java/src/main/java/Main.java:connect"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgresql/statement_timeout/csharp/Program.cs:connect"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgresql/statement_timeout/go/main.go:connect"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgresql/statement_timeout/rust/src/main.rs:connect"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgresql/statement_timeout/ruby/main.rb:connect"
    ```

=== "C"

    ```c
    --8<-- "recipes/postgresql/statement_timeout/c/main.c:connect"
    ```

## Setting the Timeout and Catching the Cancellation

Each program sets the timeout, runs the slow statement, and checks the
SQLSTATE code of any error. The `SET` command cannot take a parameter, so
the programs call the `set_config()` function instead, which accepts the
value as an ordinary parameter and so keeps the rule that programs never
build SQL from strings. The last argument of `set_config()` is `false`,
which makes the setting last for the session, exactly as `SET` does.

The function that runs the slow statement returns true if the server
cancelled it, and raises any other error again. Python, Java, and Ruby
read the code from the error, and TypeScript, Go, Rust, and C# do the
same through the error type of the driver; C reads the code from the
result with `PQresultErrorField()`. The final function runs `SELECT 1` and
returns whether the answer is correct. The following tabs show the three
functions in each language:

=== "Python"

    ```python
    --8<-- "recipes/postgresql/statement_timeout/python/main.py:timeout"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgresql/statement_timeout/typescript/main.ts:timeout"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgresql/statement_timeout/java/src/main/java/Main.java:timeout"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgresql/statement_timeout/csharp/Program.cs:timeout"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgresql/statement_timeout/go/main.go:timeout"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgresql/statement_timeout/rust/src/main.rs:timeout"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgresql/statement_timeout/ruby/main.rb:timeout"
    ```

=== "C"

    ```c
    --8<-- "recipes/postgresql/statement_timeout/c/main.c:timeout"
    ```

## Handling Errors and Closing the Connection

The main part of each program sets the timeout, runs the slow statement,
prints a message when the server cancels the statement, and then checks
that the connection still works. The program reports any other connection
or query failure on `stderr`, and then exits with a non-zero status. The
program closes the connection when the work completes or fails. The
following tabs show the main part of each program:

=== "Python"

    ```python
    --8<-- "recipes/postgresql/statement_timeout/python/main.py:main"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgresql/statement_timeout/typescript/main.ts:main"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgresql/statement_timeout/java/src/main/java/Main.java:main"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgresql/statement_timeout/csharp/Program.cs:main"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgresql/statement_timeout/go/main.go:main"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgresql/statement_timeout/rust/src/main.rs:main"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgresql/statement_timeout/ruby/main.rb:main"
    ```

=== "C"

    ```c
    --8<-- "recipes/postgresql/statement_timeout/c/main.c:main"
    ```

## Running the Example

The complete project for each language is available in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/postgresql/statement_timeout).
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
    --8<-- "recipes/postgresql/statement_timeout/python/main.py"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgresql/statement_timeout/typescript/main.ts"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgresql/statement_timeout/java/src/main/java/Main.java"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgresql/statement_timeout/csharp/Program.cs"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgresql/statement_timeout/go/main.go"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgresql/statement_timeout/rust/src/main.rs"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgresql/statement_timeout/ruby/main.rb"
    ```

=== "C"

    ```c
    --8<-- "recipes/postgresql/statement_timeout/c/main.c"
    ```

## Next Steps

The following resources provide more information about the topics in this
recipe:

- The [Retrying Serialisation Failures](retry_transactions.md) recipe shows
  how to handle another class of error that a program can recover from.
- The PostgreSQL documentation for
  [statement_timeout](https://www.postgresql.org/docs/current/runtime-config-client.html#GUC-STATEMENT-TIMEOUT)
  describes the setting in full.
- The PostgreSQL documentation for
  [lock_timeout](https://www.postgresql.org/docs/current/runtime-config-client.html#GUC-LOCK-TIMEOUT)
  limits the time that a statement waits for a lock.
- The PostgreSQL documentation for
  [error codes](https://www.postgresql.org/docs/current/errcodes-appendix.html)
  lists every SQLSTATE code.
