# Listening for Notifications

This recipe demonstrates how an application receives notifications from
PostgreSQL with `LISTEN` and `NOTIFY`. One connection subscribes to a
channel, a second connection sends a notification on that channel, and the
first connection waits up to five seconds to receive it. Each step shows
the code in every supported language; selecting a language tab switches
every tab on the site to that language.

The example program uses a channel named `cookbook_listen_notify`, and
prints the following output:

```text
Listening on channel 'cookbook_listen_notify'
Received notification on 'cookbook_listen_notify': Hello from connection B
```

## Understanding Notifications

Any session can send a notification on a named channel, with an optional
text payload, and the server delivers it to every session that is
listening on that channel. Applications use notifications to learn about
changes without polling a table: a worker wakes when a producer queues a
job, or a cache clears when the data behind it changes.

Two details matter when writing the code. First, a notification is
delivered when the sending transaction commits, and a listener hears only
notifications sent after its `LISTEN` took effect, so each example runs
`LISTEN` and `NOTIFY` outside an explicit transaction, where each statement
commits as soon as it completes. The listener is therefore subscribed
before the sender sends. Second, no driver receives a notification
asynchronously on its own: the program has to ask the driver to wait for
one, and each driver offers its own way of doing so.

## Preparing the Ingredients

This recipe uses the same drivers as the
[first recipe](connect_and_query.md), and the C and Ruby examples need
libpq, as before. The following tabs show the dependency declaration from
each example project:

=== "Python"

    ```text
    --8<-- "recipes/postgresql/listen_notify/python/requirements.txt:deps"
    ```

=== "TypeScript"

    ```json
    --8<-- "recipes/postgresql/listen_notify/typescript/package.json"
    ```

=== "Java"

    ```xml
    --8<-- "recipes/postgresql/listen_notify/java/pom.xml:deps"
    ```

=== "C#"

    ```xml
    --8<-- "recipes/postgresql/listen_notify/csharp/ListenNotify.csproj:deps"
    ```

=== "Go"

    ```text
    --8<-- "recipes/postgresql/listen_notify/go/go.mod:deps"
    ```

=== "Rust"

    ```toml
    --8<-- "recipes/postgresql/listen_notify/rust/Cargo.toml:deps"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgresql/listen_notify/ruby/Gemfile:deps"
    ```

=== "C"

    ```make
    --8<-- "recipes/postgresql/listen_notify/c/Makefile:deps"
    ```

## Importing the Driver

Each program begins by importing the driver, along with any standard
library modules that the program uses. The following tabs show the imports
for each language:

=== "Python"

    ```python
    --8<-- "recipes/postgresql/listen_notify/python/main.py:imports"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgresql/listen_notify/typescript/main.ts:imports"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgresql/listen_notify/java/src/main/java/Main.java:imports"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgresql/listen_notify/csharp/Program.cs:imports"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgresql/listen_notify/go/main.go:imports"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgresql/listen_notify/rust/src/main.rs:imports"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgresql/listen_notify/ruby/main.rb:imports"
    ```

=== "C"

    ```c
    --8<-- "recipes/postgresql/listen_notify/c/main.c:imports"
    ```

## Configuring the Connection

The examples read their connection settings from the same five
environment variables as the first recipe: `PGHOST`, `PGPORT`,
`PGDATABASE`, `PGUSER`, and `PGPASSWORD`. Like libpq, each example treats
an empty variable as unset, and uses the default instead. The same step
also sets the channel name and the five second timeout. The following tabs
show how each program assembles its settings:

=== "Python"

    ```python
    --8<-- "recipes/postgresql/listen_notify/python/main.py:config"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgresql/listen_notify/typescript/main.ts:config"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgresql/listen_notify/java/src/main/java/Main.java:config"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgresql/listen_notify/csharp/Program.cs:config"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgresql/listen_notify/go/main.go:config"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgresql/listen_notify/rust/src/main.rs:config"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgresql/listen_notify/ruby/main.rb:config"
    ```

=== "C"

    ```c
    --8<-- "recipes/postgresql/listen_notify/c/main.c:config"
    ```

## Opening a Connection

Each program opens two connections with the settings from the previous
step: one to listen and one to send. Two connections in one program stand in
for two separate processes, which is how an application normally uses
notifications. Each connection must be in autocommit
mode, as described above; the Python program requests autocommit
explicitly, and the other drivers use it by default. The C# program creates
an Npgsql data source and borrows two connections from it when the main
part of the program asks. The following tabs show how each program opens a
connection:

=== "Python"

    ```python
    --8<-- "recipes/postgresql/listen_notify/python/main.py:connect"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgresql/listen_notify/typescript/main.ts:connect"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgresql/listen_notify/java/src/main/java/Main.java:connect"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgresql/listen_notify/csharp/Program.cs:connect"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgresql/listen_notify/go/main.go:connect"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgresql/listen_notify/rust/src/main.rs:connect"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgresql/listen_notify/ruby/main.rb:connect"
    ```

=== "C"

    ```c
    --8<-- "recipes/postgresql/listen_notify/c/main.c:connect"
    ```

## Listening on a Channel

The listening connection runs `LISTEN` to subscribe to the channel. The
command takes an identifier rather than a value, so it cannot use a
parameter placeholder, and each program quotes the channel name with the
quoting function of its driver. The Rust program quotes the name itself,
because the crate has no such function. The following tabs show how each
program subscribes to the channel:

=== "Python"

    ```python
    --8<-- "recipes/postgresql/listen_notify/python/main.py:listen"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgresql/listen_notify/typescript/main.ts:listen"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgresql/listen_notify/java/src/main/java/Main.java:listen"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgresql/listen_notify/csharp/Program.cs:listen"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgresql/listen_notify/go/main.go:listen"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgresql/listen_notify/rust/src/main.rs:listen"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgresql/listen_notify/ruby/main.rb:listen"
    ```

=== "C"

    ```c
    --8<-- "recipes/postgresql/listen_notify/c/main.c:listen"
    ```

## Sending a Notification

The sending connection calls the `pg_notify()` function, which takes the
channel and the payload as ordinary parameters. The `NOTIFY` command does
the same work, but takes literal text, so the function is the better choice
for an application. The following tabs show how each program sends the
notification:

=== "Python"

    ```python
    --8<-- "recipes/postgresql/listen_notify/python/main.py:notify"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgresql/listen_notify/typescript/main.ts:notify"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgresql/listen_notify/java/src/main/java/Main.java:notify"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgresql/listen_notify/csharp/Program.cs:notify"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgresql/listen_notify/go/main.go:notify"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgresql/listen_notify/rust/src/main.rs:notify"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgresql/listen_notify/ruby/main.rb:notify"
    ```

=== "C"

    ```c
    --8<-- "recipes/postgresql/listen_notify/c/main.c:notify"
    ```

## Waiting for the Notification

Each program waits up to five seconds for a notification on the listening
connection, and treats a timeout as an error. The wait works differently
in each language:

- Python iterates over `notifies()` with a timeout and `stop_after`.
- TypeScript registers a listener for the `notification` event. The
  program creates the promise before it sends the notification, because
  node-postgres emits the event as soon as the message arrives.
- Java calls `getNotifications()` on the pgJDBC `PGConnection`, with a
  timeout in milliseconds.
- C# subscribes to the `Notification` event and calls `WaitAsync()` with a
  cancellation token that expires after the timeout.
- Go calls `WaitForNotification()` with a context that has a deadline.
- Rust iterates over `timeout_iter()` of the client notifications.
- Ruby calls `wait_for_notify()` with a timeout in seconds.
- C waits on the connection socket with `poll()`, calls
  `PQconsumeInput()` to read what arrived, and then calls `PQnotifies()`
  to fetch a queued notification, repeating until the timeout passes.

The following tabs show how each program waits:

=== "Python"

    ```python
    --8<-- "recipes/postgresql/listen_notify/python/main.py:wait"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgresql/listen_notify/typescript/main.ts:wait"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgresql/listen_notify/java/src/main/java/Main.java:wait"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgresql/listen_notify/csharp/Program.cs:wait"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgresql/listen_notify/go/main.go:wait"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgresql/listen_notify/rust/src/main.rs:wait"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgresql/listen_notify/ruby/main.rb:wait"
    ```

=== "C"

    ```c
    --8<-- "recipes/postgresql/listen_notify/c/main.c:wait"
    ```

## Handling Errors and Closing the Connections

The main part of each program calls the functions from the previous steps
in order: listen, notify, wait, and print. The program reports any
connection or query failure, and a timeout, on `stderr`, and then exits
with a non-zero status. The program also closes both connections when the
work completes or fails, using the same mechanism as the first recipe in
each language. The following tabs show the main part of each program:

=== "Python"

    ```python
    --8<-- "recipes/postgresql/listen_notify/python/main.py:main"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgresql/listen_notify/typescript/main.ts:main"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgresql/listen_notify/java/src/main/java/Main.java:main"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgresql/listen_notify/csharp/Program.cs:main"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgresql/listen_notify/go/main.go:main"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgresql/listen_notify/rust/src/main.rs:main"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgresql/listen_notify/ruby/main.rb:main"
    ```

=== "C"

    ```c
    --8<-- "recipes/postgresql/listen_notify/c/main.c:main"
    ```

## Running the Example

The complete project for each language is available in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/postgresql/listen_notify).
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
    --8<-- "recipes/postgresql/listen_notify/python/main.py"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgresql/listen_notify/typescript/main.ts"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgresql/listen_notify/java/src/main/java/Main.java"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgresql/listen_notify/csharp/Program.cs"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgresql/listen_notify/go/main.go"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgresql/listen_notify/rust/src/main.rs"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgresql/listen_notify/ruby/main.rb"
    ```

=== "C"

    ```c
    --8<-- "recipes/postgresql/listen_notify/c/main.c"
    ```

## Next Steps

The following resources provide more information about the topics in this
recipe:

- The [Connecting to PostgreSQL and Running a Query](connect_and_query.md)
  recipe explains the connection settings used by every example.
- The PostgreSQL documentation for
  [LISTEN](https://www.postgresql.org/docs/current/sql-listen.html) and
  [NOTIFY](https://www.postgresql.org/docs/current/sql-notify.html)
  describes the delivery rules, including the size limit on payloads.
- The libpq documentation for
  [asynchronous notification](https://www.postgresql.org/docs/current/libpq-notify.html)
  describes `PQnotifies()`.
