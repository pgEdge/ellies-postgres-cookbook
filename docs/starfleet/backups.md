# Taking a Backup and Tracking Its Task

This recipe shows how to take an on-demand backup of a pgEdge Starfleet
database, poll the backup until it completes, and list the tasks that the API
recorded for the database. Because the recipe needs a database, the program
creates one with the code from the "Creating a Database and Waiting for It"
recipe, and deletes it at the end. Starfleet bills for the database whilst it
exists, so the program removes it on every path out. The backup is different:
the API has no way to delete a backup, so every run leaves one behind.

These examples are for the pgEdge Starfleet Managed API v1.

The names of the resources, the number of status lines, and the version strings
vary, so the output looks similar to the following:

```text
Region: us-east-2
Size: small
Created database cookbook-3f9a1c
Database status: creating
Database status: available
Database is available
Backup started
Backup status: pending
Backup status: started
Backup status: completed
Task: backup-managed (succeeded)
Task: create-managed (succeeded)
Deleted database
Backup after the database was deleted: still listed
```

## Preparing the Ingredients

You need a pgEdge Starfleet account and an API client with its client ID and
secret. Never put the client secret in a file that you commit to version
control, and never paste it into a command line, because other users of the
machine can read the command lines of running processes. The programs in this
recipe read the secret from the environment and, for the curl script, pass it
to curl on standard input.

The following warning describes what the example creates and what it does to
clean up:

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

    The API has no way to delete a backup, so every run of this recipe leaves a
    backup behind, and the API specification does not document how long backups
    are kept or whether they are billed. For that reason the scheduled test job
    for this repository does not run this recipe, and you should run it
    sparingly.

The programs need only the HTTP clients of the "Getting an Access Token"
recipe, except that the Rust program also uses
[signal-hook](https://docs.rs/signal-hook) to catch signals. The curl script
needs `curl` and `jq`. The following excerpts show the dependencies:

=== "Python"

    ```text
    --8<-- "recipes/starfleet/backups/python/requirements.txt:deps"
    ```

=== "TypeScript"

    ```json
    --8<-- "recipes/starfleet/backups/typescript/package.json"
    ```

=== "Java"

    ```xml
    --8<-- "recipes/starfleet/backups/java/pom.xml:deps"
    ```

=== "C#"

    ```xml
    --8<-- "recipes/starfleet/backups/csharp/Backups.csproj:deps"
    ```

=== "Go"

    ```text
    --8<-- "recipes/starfleet/backups/go/go.mod:deps"
    ```

=== "Rust"

    ```toml
    --8<-- "recipes/starfleet/backups/rust/Cargo.toml:deps"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/starfleet/backups/ruby/Gemfile:deps"
    ```

## Importing the Libraries

The following code shows the imports and, for the curl script, the check for
the tools that it needs:

=== "Python"

    ```python
    --8<-- "recipes/starfleet/backups/python/main.py:imports"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/starfleet/backups/typescript/main.ts:imports"
    ```

=== "Java"

    ```java
    --8<-- "recipes/starfleet/backups/java/src/main/java/Main.java:imports"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/starfleet/backups/csharp/Program.cs:imports"
    ```

=== "Go"

    ```go
    --8<-- "recipes/starfleet/backups/go/main.go:imports"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/starfleet/backups/rust/src/main.rs:imports"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/starfleet/backups/ruby/main.rb:imports"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/starfleet/backups/curl/main.sh:imports"
    ```

## Configuring the Program

The program reads the same environment variables as the other Starfleet
recipes, and treats an empty variable as unset:

| Variable                  | Default                  | Description         |
|---------------------------|--------------------------|---------------------|
| `STARFLEET_CLIENT_ID`     | None                     | Your client ID.     |
| `STARFLEET_CLIENT_SECRET` | None                     | Your client secret. |
| `STARFLEET_API_URL`       | `https://api.pgedge.com` | The API base URL.   |

The constants set how long to wait for the database and the backup, which can
take several minutes, and how often to check. The following code reads the
settings:

=== "Python"

    ```python
    --8<-- "recipes/starfleet/backups/python/main.py:config"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/starfleet/backups/typescript/main.ts:config"
    ```

=== "Java"

    ```java
    --8<-- "recipes/starfleet/backups/java/src/main/java/Main.java:config"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/starfleet/backups/csharp/Program.cs:config"
    ```

=== "Go"

    ```go
    --8<-- "recipes/starfleet/backups/go/main.go:config"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/starfleet/backups/rust/src/main.rs:config"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/starfleet/backups/ruby/main.rb:config"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/starfleet/backups/curl/main.sh:config"
    ```

## Getting a Token

The program gets a token in the same way as the "Getting an Access Token"
recipe:

=== "Python"

    ```python
    --8<-- "recipes/starfleet/backups/python/main.py:token"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/starfleet/backups/typescript/main.ts:token"
    ```

=== "Java"

    ```java
    --8<-- "recipes/starfleet/backups/java/src/main/java/Main.java:token"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/starfleet/backups/csharp/Program.cs:token"
    ```

=== "Go"

    ```go
    --8<-- "recipes/starfleet/backups/go/main.go:token"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/starfleet/backups/rust/src/main.rs:token"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/starfleet/backups/ruby/main.rb:token"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/starfleet/backups/curl/main.sh:token"
    ```

## Calling the Managed API

The `api` function sends an authenticated request and returns the decoded
reply. The program also reacts to particular error statuses, so the error that
the function raises carries the HTTP status:

=== "Python"

    ```python
    --8<-- "recipes/starfleet/backups/python/main.py:api"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/starfleet/backups/typescript/main.ts:api"
    ```

=== "Java"

    ```java
    --8<-- "recipes/starfleet/backups/java/src/main/java/Main.java:api"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/starfleet/backups/csharp/Program.cs:api"
    ```

=== "Go"

    ```go
    --8<-- "recipes/starfleet/backups/go/main.go:api"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/starfleet/backups/rust/src/main.rs:api"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/starfleet/backups/ruby/main.rb:api"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/starfleet/backups/curl/main.sh:api"
    ```

## Choosing a Region and Size

The program creates its own database, with the code from the "Creating a
Database and Waiting for It" recipe. It chooses the first region and the
smallest size, and the following code makes the choice:

=== "Python"

    ```python
    --8<-- "recipes/starfleet/backups/python/main.py:placement"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/starfleet/backups/typescript/main.ts:placement"
    ```

=== "Java"

    ```java
    --8<-- "recipes/starfleet/backups/java/src/main/java/Main.java:placement"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/starfleet/backups/csharp/Program.cs:placement"
    ```

=== "Go"

    ```go
    --8<-- "recipes/starfleet/backups/go/main.go:placement"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/starfleet/backups/rust/src/main.rs:placement"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/starfleet/backups/ruby/main.rb:placement"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/starfleet/backups/curl/main.sh:placement"
    ```

## Creating the Database

The following code creates the database, which only your machine can reach, and
names it with the `cookbook-` prefix:

=== "Python"

    ```python
    --8<-- "recipes/starfleet/backups/python/main.py:create"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/starfleet/backups/typescript/main.ts:create"
    ```

=== "Java"

    ```java
    --8<-- "recipes/starfleet/backups/java/src/main/java/Main.java:create"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/starfleet/backups/csharp/Program.cs:create"
    ```

=== "Go"

    ```go
    --8<-- "recipes/starfleet/backups/go/main.go:create"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/starfleet/backups/rust/src/main.rs:create"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/starfleet/backups/ruby/main.rb:create"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/starfleet/backups/curl/main.sh:create"
    ```

## Waiting for the Database

The following code polls the database until its status is `available`, and
stops at once if the status is `degraded` or `failed`:

=== "Python"

    ```python
    --8<-- "recipes/starfleet/backups/python/main.py:wait"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/starfleet/backups/typescript/main.ts:wait"
    ```

=== "Java"

    ```java
    --8<-- "recipes/starfleet/backups/java/src/main/java/Main.java:wait"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/starfleet/backups/csharp/Program.cs:wait"
    ```

=== "Go"

    ```go
    --8<-- "recipes/starfleet/backups/go/main.go:wait"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/starfleet/backups/rust/src/main.rs:wait"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/starfleet/backups/ruby/main.rb:wait"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/starfleet/backups/curl/main.sh:wait"
    ```

## Taking and Tracking the Backup

The API takes an on-demand backup from a `POST` request to the backup endpoint
of a database, with a `kind` of `hot` or `durable`. The API documents a hot
backup as a fast local snapshot, and a durable backup as a fresh base backup
that streams to object storage and needs the durable tier to be enabled for the
database, so the example takes a hot backup. The API answers 202 with the
pending backup, and runs the backup in the background. The API documents
`completed` as the status of a usable backup but does not list the others. In
testing, the status went from `pending` to `started` to `completed`, so the
program treats `failed` as a failure that ends the wait at once, and anything
else as still in progress. The API records the progress of managed database
operations as tasks, with the subject kind `database` and the database ID as
the subject, and in testing a database with one backup had two tasks, named
`create-managed` and `backup-managed`, that had both succeeded. The task names
are not in the specification. After the database is deleted, the program asks
for the backup once more and reports what it finds, because the specification
does not say what happens to a backup when its database goes. In testing, the
API still listed the backup. The following code takes the backup, waits for it,
and lists the tasks:

=== "Python"

    ```python
    --8<-- "recipes/starfleet/backups/python/main.py:backup"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/starfleet/backups/typescript/main.ts:backup"
    ```

=== "Java"

    ```java
    --8<-- "recipes/starfleet/backups/java/src/main/java/Main.java:backup"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/starfleet/backups/csharp/Program.cs:backup"
    ```

=== "Go"

    ```go
    --8<-- "recipes/starfleet/backups/go/main.go:backup"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/starfleet/backups/rust/src/main.rs:backup"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/starfleet/backups/ruby/main.rb:backup"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/starfleet/backups/curl/main.sh:backup"
    ```

## Deleting the Resources

The program deletes the database when it has finished with the backup. The API
documents a 409 reply to a delete as meaning that the database has branches,
and offers a `force` parameter for that case. In testing, the API also answered
409 whilst a database was still being created, so the program repeats the
request after a 409, after a 429 or 5xx status, and after a failure to get any
reply, until the time limit passes. A 404 means that the database has gone
already. A delete only starts the teardown, so the program then polls until the
API answers 404, which in testing was the sign that the database had gone. If
the outcome of the create request is unknown (no reply arrived, the service
answered with a 5xx status, the reply could not be read, or you interrupted the
program during the request), the program has no database ID, so it first lists
the databases and picks the one with the name that it chose before the request,
trying up to three times, ten seconds apart, and then reports the name so that
you can check your account by hand. It does not look after a 4xx reply, because
that is a definite refusal. The list request passes `limit=100` and
`descending=true`, but the API specification does not say which property it
sorts on. If the delete or the lookup fails, the program tells you to delete
the database by hand. The program cannot delete the backup, because the API has
no way to do so, and the specification does not say what happens to a backup
when its database is deleted. The following code deletes the database:

=== "Python"

    ```python
    --8<-- "recipes/starfleet/backups/python/main.py:delete"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/starfleet/backups/typescript/main.ts:delete"
    ```

=== "Java"

    ```java
    --8<-- "recipes/starfleet/backups/java/src/main/java/Main.java:delete"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/starfleet/backups/csharp/Program.cs:delete"
    ```

=== "Go"

    ```go
    --8<-- "recipes/starfleet/backups/go/main.go:delete"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/starfleet/backups/rust/src/main.rs:delete"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/starfleet/backups/ruby/main.rb:delete"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/starfleet/backups/curl/main.sh:delete"
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
    --8<-- "recipes/starfleet/backups/python/main.py:main"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/starfleet/backups/typescript/main.ts:main"
    ```

=== "Java"

    ```java
    --8<-- "recipes/starfleet/backups/java/src/main/java/Main.java:main"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/starfleet/backups/csharp/Program.cs:main"
    ```

=== "Go"

    ```go
    --8<-- "recipes/starfleet/backups/go/main.go:main"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/starfleet/backups/rust/src/main.rs:main"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/starfleet/backups/ruby/main.rb:main"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/starfleet/backups/curl/main.sh:main"
    ```

## Running the Example

The complete project for each language is available in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/starfleet/backups).
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
    --8<-- "recipes/starfleet/backups/python/main.py"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/starfleet/backups/typescript/main.ts"
    ```

=== "Java"

    ```java
    --8<-- "recipes/starfleet/backups/java/src/main/java/Main.java"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/starfleet/backups/csharp/Program.cs"
    ```

=== "Go"

    ```go
    --8<-- "recipes/starfleet/backups/go/main.go"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/starfleet/backups/rust/src/main.rs"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/starfleet/backups/ruby/main.rb"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/starfleet/backups/curl/main.sh"
    ```

## Next Steps

The following resources provide more information about the topics in this
recipe:

- The "Creating a Database and Waiting for It" recipe explains the creation and
  deletion steps in more detail.
- The "Getting an Access Token" recipe explains the token exchange in more
  detail.
