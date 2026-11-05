# Creating a Database and Waiting for It

This recipe shows the whole life of a pgEdge Starfleet database. The program
picks the smallest size, creates a database that only your machine can reach,
waits until the database is available, and then deletes it again. Starfleet
bills for the database whilst it exists, so the program removes it on every
path out, and waits until the API confirms that it has gone.

These examples are for the pgEdge Starfleet Managed API v1.

The name of the database and the number of status lines vary, so the output
looks similar to the following:

```text
Region: us-east-2
Size: small
Created database cookbook-3f9a1c
Database status: creating
Database status: available
Database is available
Deleted database
```

## Preparing the Ingredients

You need a pgEdge Starfleet account and an API client with its client ID and
secret. Never put the client secret in a file that you commit to version
control, and never paste it into a command line, because other users of the
machine can read the command lines of running processes. The programs in this
recipe read the secret from the environment and, for the curl script, pass it
to curl on standard input.

!!! warning "These examples create billable resources"

    Starfleet bills for a database until deletion is requested. The program
    deletes the database that it creates whether the example succeeds, fails,
    or is interrupted with Ctrl-C, and waits until the API no longer lists it.
    If the reply to the create request is lost, the program looks the database
    up by its name before it deletes it, and if that fails it tells you the
    name so that you can delete it by hand. A program that is killed outright,
    with `kill -9` for instance, cannot clean up, so check your account for
    databases whose display names start with `cookbook-` if you stop a run that
    way.

The dependencies are the same as for the "Getting an Access Token" recipe,
except that the Rust program also uses
[signal-hook](https://docs.rs/signal-hook) to catch signals. The following
excerpts show them:

=== "Python"

    ```text
    --8<-- "recipes/starfleet/create_database/python/requirements.txt:deps"
    ```

=== "TypeScript"

    ```json
    --8<-- "recipes/starfleet/create_database/typescript/package.json"
    ```

=== "Java"

    ```xml
    --8<-- "recipes/starfleet/create_database/java/pom.xml:deps"
    ```

=== "C#"

    ```xml
    --8<-- "recipes/starfleet/create_database/csharp/CreateDatabase.csproj:deps"
    ```

=== "Go"

    ```text
    --8<-- "recipes/starfleet/create_database/go/go.mod:deps"
    ```

=== "Rust"

    ```toml
    --8<-- "recipes/starfleet/create_database/rust/Cargo.toml:deps"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/starfleet/create_database/ruby/Gemfile:deps"
    ```

## Importing the Libraries

The following code shows the imports and, for the curl script, the check for
the tools that it needs:

=== "Python"

    ```python
    --8<-- "recipes/starfleet/create_database/python/main.py:imports"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/starfleet/create_database/typescript/main.ts:imports"
    ```

=== "Java"

    ```java
    --8<-- "recipes/starfleet/create_database/java/src/main/java/Main.java:imports"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/starfleet/create_database/csharp/Program.cs:imports"
    ```

=== "Go"

    ```go
    --8<-- "recipes/starfleet/create_database/go/main.go:imports"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/starfleet/create_database/rust/src/main.rs:imports"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/starfleet/create_database/ruby/main.rb:imports"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/starfleet/create_database/curl/main.sh:imports"
    ```

## Configuring the Program

The program reads the same environment variables as the other Starfleet
recipes, and treats an empty variable as unset:

| Variable                  | Default                  | Description         |
|---------------------------|--------------------------|---------------------|
| `STARFLEET_CLIENT_ID`     | None                     | Your client ID.     |
| `STARFLEET_CLIENT_SECRET` | None                     | Your client secret. |
| `STARFLEET_API_URL`       | `https://api.pgedge.com` | The API base URL.   |

The constants set how long to wait for the database, which can take several
minutes to provision, and how often to check. The following code reads the
settings:

=== "Python"

    ```python
    --8<-- "recipes/starfleet/create_database/python/main.py:config"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/starfleet/create_database/typescript/main.ts:config"
    ```

=== "Java"

    ```java
    --8<-- "recipes/starfleet/create_database/java/src/main/java/Main.java:config"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/starfleet/create_database/csharp/Program.cs:config"
    ```

=== "Go"

    ```go
    --8<-- "recipes/starfleet/create_database/go/main.go:config"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/starfleet/create_database/rust/src/main.rs:config"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/starfleet/create_database/ruby/main.rb:config"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/starfleet/create_database/curl/main.sh:config"
    ```

## Getting a Token

The program gets a token in the same way as the "Getting an Access Token"
recipe:

=== "Python"

    ```python
    --8<-- "recipes/starfleet/create_database/python/main.py:token"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/starfleet/create_database/typescript/main.ts:token"
    ```

=== "Java"

    ```java
    --8<-- "recipes/starfleet/create_database/java/src/main/java/Main.java:token"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/starfleet/create_database/csharp/Program.cs:token"
    ```

=== "Go"

    ```go
    --8<-- "recipes/starfleet/create_database/go/main.go:token"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/starfleet/create_database/rust/src/main.rs:token"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/starfleet/create_database/ruby/main.rb:token"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/starfleet/create_database/curl/main.sh:token"
    ```

## Calling the Managed API

The `api` function sends an authenticated request and returns the decoded
reply. The program also reacts to particular error statuses, so the error that
the function raises carries the HTTP status:

=== "Python"

    ```python
    --8<-- "recipes/starfleet/create_database/python/main.py:api"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/starfleet/create_database/typescript/main.ts:api"
    ```

=== "Java"

    ```java
    --8<-- "recipes/starfleet/create_database/java/src/main/java/Main.java:api"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/starfleet/create_database/csharp/Program.cs:api"
    ```

=== "Go"

    ```go
    --8<-- "recipes/starfleet/create_database/go/main.go:api"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/starfleet/create_database/rust/src/main.rs:api"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/starfleet/create_database/ruby/main.rb:api"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/starfleet/create_database/curl/main.sh:api"
    ```

## Choosing a Region and Size

The program asks the API for the regions and the sizes, and picks the first
size, which is the smallest and therefore the cheapest. The API does not price
regions, so the program takes the first region in the list. The following code
makes the choice:

=== "Python"

    ```python
    --8<-- "recipes/starfleet/create_database/python/main.py:placement"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/starfleet/create_database/typescript/main.ts:placement"
    ```

=== "Java"

    ```java
    --8<-- "recipes/starfleet/create_database/java/src/main/java/Main.java:placement"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/starfleet/create_database/csharp/Program.cs:placement"
    ```

=== "Go"

    ```go
    --8<-- "recipes/starfleet/create_database/go/main.go:placement"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/starfleet/create_database/rust/src/main.rs:placement"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/starfleet/create_database/ruby/main.rb:placement"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/starfleet/create_database/curl/main.sh:placement"
    ```

## Creating the Database

A new database refuses every connection until an allowlist rule admits the
source address. The program asks the API for the address that it sees the
request come from, and admits only that address; a bare address means a single
host. The `name` of a database becomes its Postgres database name, so in
testing it accepted only letters and digits; the readable `cookbook-` prefix
and a random suffix go in the `display_name`, which is how you recognise the
database in your account. The following code creates the database:

=== "Python"

    ```python
    --8<-- "recipes/starfleet/create_database/python/main.py:create"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/starfleet/create_database/typescript/main.ts:create"
    ```

=== "Java"

    ```java
    --8<-- "recipes/starfleet/create_database/java/src/main/java/Main.java:create"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/starfleet/create_database/csharp/Program.cs:create"
    ```

=== "Go"

    ```go
    --8<-- "recipes/starfleet/create_database/go/main.go:create"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/starfleet/create_database/rust/src/main.rs:create"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/starfleet/create_database/ruby/main.rb:create"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/starfleet/create_database/curl/main.sh:create"
    ```

## Waiting for the Database

Creating a database takes the API a few minutes. The program polls the database
every ten seconds, prints each new status, and stops when the status is
`available`, or the time limit passes, or the status is `degraded` or `failed`,
which the API does not document but which the program treats as failures. In
testing, `available` was the status of a database that is ready. The following
code waits:

=== "Python"

    ```python
    --8<-- "recipes/starfleet/create_database/python/main.py:wait"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/starfleet/create_database/typescript/main.ts:wait"
    ```

=== "Java"

    ```java
    --8<-- "recipes/starfleet/create_database/java/src/main/java/Main.java:wait"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/starfleet/create_database/csharp/Program.cs:wait"
    ```

=== "Go"

    ```go
    --8<-- "recipes/starfleet/create_database/go/main.go:wait"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/starfleet/create_database/rust/src/main.rs:wait"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/starfleet/create_database/ruby/main.rb:wait"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/starfleet/create_database/curl/main.sh:wait"
    ```

## Deleting the Database

The API documents a 409 reply to a delete as meaning that the database has
branches, and offers a `force` parameter for that case. In testing, the API
also answered 409 whilst a database was still being created, so the program
repeats the request after a 409, after a 429 or 5xx status, and after a failure
to get any reply, until the time limit passes. A 404 means that the database
has gone already. A delete only starts the teardown, so the program then polls
until the API answers 404, which in testing was the sign that the database had
gone. The following code deletes the database. If the outcome of the create
request is unknown (no reply arrived, the service answered with a 5xx status,
the reply could not be read, or you interrupted the program during the
request), the program has no database ID, so it first lists the databases and
picks the one with the name that it chose before the request. If the list has
no such database, the program tries up to three times, ten seconds apart, in
case the service has not yet recorded the request, and then reports the name so
that you can check your account by hand. It does not look after a 4xx reply,
because that is a definite refusal. The request passes `limit=100` and
`descending=true`, but the API specification does not say which property it
sorts on, so the program cannot be sure that a new database is on the first
page of an account with more than 100 databases. The program repeats the
listing in the same way as the delete, and if it still fails, prints the name
of the database and tells you to delete it by hand:

=== "Python"

    ```python
    --8<-- "recipes/starfleet/create_database/python/main.py:delete"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/starfleet/create_database/typescript/main.ts:delete"
    ```

=== "Java"

    ```java
    --8<-- "recipes/starfleet/create_database/java/src/main/java/Main.java:delete"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/starfleet/create_database/csharp/Program.cs:delete"
    ```

=== "Go"

    ```go
    --8<-- "recipes/starfleet/create_database/go/main.go:delete"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/starfleet/create_database/rust/src/main.rs:delete"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/starfleet/create_database/ruby/main.rb:delete"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/starfleet/create_database/curl/main.sh:delete"
    ```

## Running the Program

The `main` function runs the steps in order, and deletes the database on every
path: in a `finally` block in Python, TypeScript, Java, and C#, in an `ensure`
block in Ruby, after `run` returns in Rust, with a `defer` in Go, and with a
trap on `EXIT` in the curl script. The deletion therefore happens when a step
fails or when you press Ctrl-C, and the Rust program catches a panic with
`catch_unwind` so that one cannot skip the deletion either. Each program also
handles the SIGTERM signal as it does Ctrl-C (SIGINT), so that `kill` cleans up
as well. The C# program registers `PosixSignalRegistration` handlers that
cancel the request in progress, the Rust program sets a flag with signal-hook
that stops it before its next request, and the Ruby program receives each
signal as an exception. Java's supported API cannot catch a signal, so the Java
program registers a shutdown hook, which the JVM runs when SIGINT or SIGTERM
ends the program; the hook deletes the database, or waits for the main thread
to finish doing so, and then ends the program. The program chooses the database
name before it sends the create request, so the cleanup can find the database
by name if the reply never arrives. The cleanup ignores further interrupts,
because a second Ctrl-C must not leave a billable database behind. The
following code shows the function:

=== "Python"

    ```python
    --8<-- "recipes/starfleet/create_database/python/main.py:main"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/starfleet/create_database/typescript/main.ts:main"
    ```

=== "Java"

    ```java
    --8<-- "recipes/starfleet/create_database/java/src/main/java/Main.java:main"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/starfleet/create_database/csharp/Program.cs:main"
    ```

=== "Go"

    ```go
    --8<-- "recipes/starfleet/create_database/go/main.go:main"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/starfleet/create_database/rust/src/main.rs:main"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/starfleet/create_database/ruby/main.rb:main"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/starfleet/create_database/curl/main.sh:main"
    ```

## Running the Example

The complete project for each language is available in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/starfleet/create_database).
Set the environment variables for your account, and then run the command for
your language from the corresponding project directory. The following tabs show
the commands that build and run each example:

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

=== "curl"

    ```bash
    ./main.sh
    ```

The run takes several minutes, almost all of it spent waiting for the database
to become available.

## Viewing the Complete Program

The following tabs show the complete program for each language:

=== "Python"

    ```python
    --8<-- "recipes/starfleet/create_database/python/main.py"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/starfleet/create_database/typescript/main.ts"
    ```

=== "Java"

    ```java
    --8<-- "recipes/starfleet/create_database/java/src/main/java/Main.java"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/starfleet/create_database/csharp/Program.cs"
    ```

=== "Go"

    ```go
    --8<-- "recipes/starfleet/create_database/go/main.go"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/starfleet/create_database/rust/src/main.rs"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/starfleet/create_database/ruby/main.rb"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/starfleet/create_database/curl/main.sh"
    ```

## Next Steps

The following resources provide more information about the topics in this
recipe:

- The "Connecting to a Starfleet Database" recipe connects to the database
  and runs a query before it deletes the database.
