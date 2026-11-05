# Creating a Branch for a Test Run

This recipe shows how to create a copy-on-write branch of a pgEdge Starfleet
database for a test run, wait for it, connect to the branch and run a query,
and delete it. Because the recipe needs a database to branch, the program
creates one with the code from the "Creating a Database and Waiting for It"
recipe, and deletes the branch and then the database at the end. Starfleet
bills for each of them whilst it exists, so the program removes both on every
path out. Creating a branch also takes a backup of the source, which the
program cannot delete.

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
Created branch cookbook-3f9a1c-branch
Branch status: creating
Branch status: available
Branch is available
Branch server version: PostgreSQL 18.1 on x86_64-pc-linux-gnu, 64-bit
Deleted branch
Deleted database
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

    Starfleet bills for a database, and for each of its branches, until
    deletion is requested. The program deletes the branch and then the database
    that it creates whether the example succeeds, fails, or is interrupted with
    Ctrl-C, and waits until the API no longer lists them. If the reply to a
    create request is lost, the program looks the resource up by its name
    before it deletes it, and if that fails it tells you the name so that you
    can delete it by hand. A program that is killed outright, with `kill -9`
    for instance, cannot clean up, so check your account for databases whose
    display names start with `cookbook-` if you stop a run that way.

    Creating a branch also takes a backup of the source database, which the API
    documents with the purpose `prebranch`. The API has no way to delete a
    backup, and its specification does not document how long backups are kept
    or whether they are billed, so every run of this recipe leaves a
    backup behind. For that reason the scheduled test job for this repository
    does not run this recipe.

The programs use the same HTTP clients as the "Getting an Access Token" recipe,
and connect to the database with the following drivers:

| Language   | PostgreSQL driver                                               |
|------------|-----------------------------------------------------------------|
| Python     | [psycopg](https://www.psycopg.org/psycopg3/)                    |
| TypeScript | [node-postgres](https://node-postgres.com/)                     |
| Java       | [pgJDBC](https://jdbc.postgresql.org/)                          |
| C#         | [Npgsql](https://www.npgsql.org/)                               |
| Go         | [pgx](https://github.com/jackc/pgx)                             |
| Rust       | [rust-postgres](https://github.com/rust-postgres/rust-postgres), with [postgres-openssl](https://docs.rs/postgres-openssl) for TLS |
| Ruby       | [ruby-pg](https://github.com/ged/ruby-pg)                       |

The Rust program also uses [signal-hook](https://docs.rs/signal-hook) to catch
signals. The curl script needs `psql`, the PostgreSQL command line client, in
addition to `curl` and `jq`. The following excerpts show the dependencies:

=== "Python"

    ```text
    --8<-- "recipes/starfleet/branches/python/requirements.txt:deps"
    ```

=== "TypeScript"

    ```json
    --8<-- "recipes/starfleet/branches/typescript/package.json"
    ```

=== "Java"

    ```xml
    --8<-- "recipes/starfleet/branches/java/pom.xml:deps"
    ```

=== "C#"

    ```xml
    --8<-- "recipes/starfleet/branches/csharp/Branches.csproj:deps"
    ```

=== "Go"

    ```text
    --8<-- "recipes/starfleet/branches/go/go.mod:deps"
    ```

=== "Rust"

    ```toml
    --8<-- "recipes/starfleet/branches/rust/Cargo.toml:deps"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/starfleet/branches/ruby/Gemfile:deps"
    ```

## Importing the Libraries

The following code shows the imports and, for the curl script, the check for
the tools that it needs:

=== "Python"

    ```python
    --8<-- "recipes/starfleet/branches/python/main.py:imports"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/starfleet/branches/typescript/main.ts:imports"
    ```

=== "Java"

    ```java
    --8<-- "recipes/starfleet/branches/java/src/main/java/Main.java:imports"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/starfleet/branches/csharp/Program.cs:imports"
    ```

=== "Go"

    ```go
    --8<-- "recipes/starfleet/branches/go/main.go:imports"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/starfleet/branches/rust/src/main.rs:imports"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/starfleet/branches/ruby/main.rb:imports"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/starfleet/branches/curl/main.sh:imports"
    ```

## Configuring the Program

The program reads the same environment variables as the other Starfleet
recipes, and treats an empty variable as unset:

| Variable                  | Default                  | Description         |
|---------------------------|--------------------------|---------------------|
| `STARFLEET_CLIENT_ID`     | None                     | Your client ID.     |
| `STARFLEET_CLIENT_SECRET` | None                     | Your client secret. |
| `STARFLEET_API_URL`       | `https://api.pgedge.com` | The API base URL.   |

The constants set how long to wait for each resource, which can take several
minutes to provision, and how often to check. The following code reads the
settings:

=== "Python"

    ```python
    --8<-- "recipes/starfleet/branches/python/main.py:config"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/starfleet/branches/typescript/main.ts:config"
    ```

=== "Java"

    ```java
    --8<-- "recipes/starfleet/branches/java/src/main/java/Main.java:config"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/starfleet/branches/csharp/Program.cs:config"
    ```

=== "Go"

    ```go
    --8<-- "recipes/starfleet/branches/go/main.go:config"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/starfleet/branches/rust/src/main.rs:config"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/starfleet/branches/ruby/main.rb:config"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/starfleet/branches/curl/main.sh:config"
    ```

## Getting a Token

The program gets a token in the same way as the "Getting an Access Token"
recipe:

=== "Python"

    ```python
    --8<-- "recipes/starfleet/branches/python/main.py:token"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/starfleet/branches/typescript/main.ts:token"
    ```

=== "Java"

    ```java
    --8<-- "recipes/starfleet/branches/java/src/main/java/Main.java:token"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/starfleet/branches/csharp/Program.cs:token"
    ```

=== "Go"

    ```go
    --8<-- "recipes/starfleet/branches/go/main.go:token"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/starfleet/branches/rust/src/main.rs:token"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/starfleet/branches/ruby/main.rb:token"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/starfleet/branches/curl/main.sh:token"
    ```

## Calling the Managed API

The `api` function sends an authenticated request and returns the decoded
reply. The program also reacts to particular error statuses, so the error that
the function raises carries the HTTP status:

=== "Python"

    ```python
    --8<-- "recipes/starfleet/branches/python/main.py:api"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/starfleet/branches/typescript/main.ts:api"
    ```

=== "Java"

    ```java
    --8<-- "recipes/starfleet/branches/java/src/main/java/Main.java:api"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/starfleet/branches/csharp/Program.cs:api"
    ```

=== "Go"

    ```go
    --8<-- "recipes/starfleet/branches/go/main.go:api"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/starfleet/branches/rust/src/main.rs:api"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/starfleet/branches/ruby/main.rb:api"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/starfleet/branches/curl/main.sh:api"
    ```

## Choosing a Region and Size

The program creates its own database, with the code from the "Creating a
Database and Waiting for It" recipe. It chooses the first region and the
smallest size, and the following code makes the choice:

=== "Python"

    ```python
    --8<-- "recipes/starfleet/branches/python/main.py:placement"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/starfleet/branches/typescript/main.ts:placement"
    ```

=== "Java"

    ```java
    --8<-- "recipes/starfleet/branches/java/src/main/java/Main.java:placement"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/starfleet/branches/csharp/Program.cs:placement"
    ```

=== "Go"

    ```go
    --8<-- "recipes/starfleet/branches/go/main.go:placement"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/starfleet/branches/rust/src/main.rs:placement"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/starfleet/branches/ruby/main.rb:placement"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/starfleet/branches/curl/main.sh:placement"
    ```

## Creating the Database

The following code creates the database, which only your machine can reach, and
names it with the `cookbook-` prefix:

=== "Python"

    ```python
    --8<-- "recipes/starfleet/branches/python/main.py:create"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/starfleet/branches/typescript/main.ts:create"
    ```

=== "Java"

    ```java
    --8<-- "recipes/starfleet/branches/java/src/main/java/Main.java:create"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/starfleet/branches/csharp/Program.cs:create"
    ```

=== "Go"

    ```go
    --8<-- "recipes/starfleet/branches/go/main.go:create"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/starfleet/branches/rust/src/main.rs:create"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/starfleet/branches/ruby/main.rb:create"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/starfleet/branches/curl/main.sh:create"
    ```

## Waiting for the Database

The following code polls the database until its status is `available`, and
stops at once if the status is `degraded` or `failed`:

=== "Python"

    ```python
    --8<-- "recipes/starfleet/branches/python/main.py:wait"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/starfleet/branches/typescript/main.ts:wait"
    ```

=== "Java"

    ```java
    --8<-- "recipes/starfleet/branches/java/src/main/java/Main.java:wait"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/starfleet/branches/csharp/Program.cs:wait"
    ```

=== "Go"

    ```go
    --8<-- "recipes/starfleet/branches/go/main.go:wait"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/starfleet/branches/rust/src/main.rs:wait"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/starfleet/branches/ruby/main.rb:wait"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/starfleet/branches/curl/main.sh:wait"
    ```

## Creating the Branch

The API creates a branch from the `POST` request to the branches of a database,
and documents that the new branch copies the source's size, Postgres version,
options, and service configuration at creation, with its own name, host name,
and credentials. The request here sets only a display name, which the program
chooses before the request so that it can find the branch again if the reply is
lost. It sends no IP allowlist, so the branch copies the rules of the database,
which admit your machine. The API documents that the request is refused while
the source is not available, when the database is at its branch limit, and
while the subscription has a failed payment. The following code creates the
branch and polls it until its status is `available`, and stops at once if the
status is `degraded` or `failed`:

=== "Python"

    ```python
    --8<-- "recipes/starfleet/branches/python/main.py:branch"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/starfleet/branches/typescript/main.ts:branch"
    ```

=== "Java"

    ```java
    --8<-- "recipes/starfleet/branches/java/src/main/java/Main.java:branch"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/starfleet/branches/csharp/Program.cs:branch"
    ```

=== "Go"

    ```go
    --8<-- "recipes/starfleet/branches/go/main.go:branch"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/starfleet/branches/rust/src/main.rs:branch"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/starfleet/branches/ruby/main.rb:branch"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/starfleet/branches/curl/main.sh:branch"
    ```

## Reading the Connection Details

The description of an available branch includes a `connection` object with the
host name, the port, the database name, the user name, and the password. The
API documents that the database name is the source's Postgres database name and
that the credentials are the branch's own, and that the connection is present
only while the branch is available. The API requires the user name, the
password, the port, and the database name but not the host, so the code checks
that they are all present, and falls back to the external IP address if the
host is missing. The password never goes in a connection string that the
program writes, or on a command line: Python, TypeScript, and Ruby pass it to
the driver as a separate setting, Java puts it in the connection properties
rather than the URL, C# sets it on an `NpgsqlConnectionStringBuilder`, Go and
Rust set it on the configuration object, and the curl script writes it to a
temporary password file that only its owner can read, and removes the file at
the end:

=== "Python"

    ```python
    --8<-- "recipes/starfleet/branches/python/main.py:connection"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/starfleet/branches/typescript/main.ts:connection"
    ```

=== "Java"

    ```java
    --8<-- "recipes/starfleet/branches/java/src/main/java/Main.java:connection"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/starfleet/branches/csharp/Program.cs:connection"
    ```

=== "Go"

    ```go
    --8<-- "recipes/starfleet/branches/go/main.go:connection"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/starfleet/branches/rust/src/main.rs:connection"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/starfleet/branches/ruby/main.rb:connection"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/starfleet/branches/curl/main.sh:connection"
    ```

## Running the Query

If the `PGSSLROOTCERT` environment variable is set, as it is after you start
the test server for the TLS recipe, unset it before you run the Python, Go, and
Ruby programs or the curl script. The libpq library (and so psycopg, ruby-pg,
and `psql`) and pgx then treat `sslmode=require` as `verify-ca`, and reject the
certificate of a Starfleet database. The Java, C#, and Rust programs are not
affected.

The program connects to the branch with the driver for the language (psycopg
for Python, node-postgres for TypeScript, pgJDBC for Java, Npgsql for C#, pgx
for Go, rust-postgres for Rust, ruby-pg for Ruby, and `psql` for the curl
script) and runs `SELECT version()`. The connection is encrypted. The
certificate of a Starfleet database is not signed by a public authority, so the
example does not verify it. That leaves the connection open to a
man-in-the-middle attack, because anyone who can intercept the traffic could
pose as the server, so do not use this approach for data that matters. A server
can refuse connections for a short while after the API reports it as available,
so the code makes up to six attempts, ten seconds apart. The Python,
TypeScript, Java, C#, Go, and Rust code retries only failures to connect, and
not errors that the server reports, such as a failed login; libpq gives no
SQLSTATE code for any failure to connect, so ruby-pg cannot tell a failed login
from a refused connection, and the Ruby code repeats them all, as the curl
script does, because `psql` gives the same exit status for every failure to
connect. The following code runs the query:

=== "Python"

    ```python
    --8<-- "recipes/starfleet/branches/python/main.py:query"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/starfleet/branches/typescript/main.ts:query"
    ```

=== "Java"

    ```java
    --8<-- "recipes/starfleet/branches/java/src/main/java/Main.java:query"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/starfleet/branches/csharp/Program.cs:query"
    ```

=== "Go"

    ```go
    --8<-- "recipes/starfleet/branches/go/main.go:query"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/starfleet/branches/rust/src/main.rs:query"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/starfleet/branches/ruby/main.rb:query"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/starfleet/branches/curl/main.sh:query"
    ```

## Deleting the Resources

The program deletes the branch first and then the database. The API documents
that a delete is refused while the database has branches, unless the `force`
parameter is set, in which case it deletes every branch first, so the database
delete passes `force=true` as a safety net for a branch that the program could
not find. After a delete request the program polls until the API no longer
lists the branch, and until it answers 404 for the database. A delete of a
branch that is still being created is refused until it settles, and in testing
the API answered 409 to a database delete whilst the database was still being
created, so both deletes repeat the request after a 409, a 429 or 5xx status,
or a failure to get any reply, until the time limit passes. A 404 means that
the resource has gone already. The API assigns the name of a branch, so if the
outcome of the branch request is unknown (no reply arrived, the service
answered with a 5xx status, the reply could not be read, or you interrupted the
program during the request), the program lists the branches of the database and
picks the one with the display name that it chose before the request, trying up
to three times, ten seconds apart. It does not look after a 4xx reply, because
that is a definite refusal. The list request passes `limit=100` and
`descending=true`, which the API documents as sorting by creation time, newest
first. (The database list has no such documentation, so the program cannot be
sure that a new database is on the first page of an account with more than 100
databases.) If a delete of the branch fails, the forced delete of the database
that follows removes it. If the database delete or a lookup fails, the program
prints the name or ID and tells you to delete the resource by hand. The
following code deletes the branch and the database:

=== "Python"

    ```python
    --8<-- "recipes/starfleet/branches/python/main.py:delete"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/starfleet/branches/typescript/main.ts:delete"
    ```

=== "Java"

    ```java
    --8<-- "recipes/starfleet/branches/java/src/main/java/Main.java:delete"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/starfleet/branches/csharp/Program.cs:delete"
    ```

=== "Go"

    ```go
    --8<-- "recipes/starfleet/branches/go/main.go:delete"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/starfleet/branches/rust/src/main.rs:delete"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/starfleet/branches/ruby/main.rb:delete"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/starfleet/branches/curl/main.sh:delete"
    ```

## Running the Program

The `main` function runs the steps in order, and deletes the branch and the
database on every path: in a `finally` block in Python, TypeScript, Java, and
C#, in an `ensure` block in Ruby, after `run` returns in Rust, with a `defer`
in Go, and with a trap on `EXIT` in the curl script. The deletion therefore
happens when a step fails or when you press Ctrl-C, and the Rust program
catches a panic with `catch_unwind` so that one cannot skip the deletion
either. Each program also handles the SIGTERM signal as it does Ctrl-C
(SIGINT), so that `kill` cleans up as well. The C# program registers
`PosixSignalRegistration` handlers that cancel the request in progress, the
Rust program sets a flag with signal-hook that stops it before its next
request, and the Ruby program receives each signal as an exception. Java's
supported API cannot catch a signal, so the Java program registers a shutdown
hook, which the JVM runs when SIGINT or SIGTERM ends the program; the hook
deletes the branch and the database, or waits for the main thread to finish
doing so, and then ends the program. The program chooses the database name and
the branch display name before it sends each create request, so the cleanup can
find the resource by name if the reply never arrives. The cleanup ignores
further interrupts, because a second Ctrl-C must not leave a billable resource
behind. The following code shows the function:

=== "Python"

    ```python
    --8<-- "recipes/starfleet/branches/python/main.py:main"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/starfleet/branches/typescript/main.ts:main"
    ```

=== "Java"

    ```java
    --8<-- "recipes/starfleet/branches/java/src/main/java/Main.java:main"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/starfleet/branches/csharp/Program.cs:main"
    ```

=== "Go"

    ```go
    --8<-- "recipes/starfleet/branches/go/main.go:main"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/starfleet/branches/rust/src/main.rs:main"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/starfleet/branches/ruby/main.rb:main"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/starfleet/branches/curl/main.sh:main"
    ```

## Running the Example

The complete project for each language is available in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/starfleet/branches).
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
and then the branch to become available.

## Viewing the Complete Program

The following tabs show the complete program for each language:

=== "Python"

    ```python
    --8<-- "recipes/starfleet/branches/python/main.py"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/starfleet/branches/typescript/main.ts"
    ```

=== "Java"

    ```java
    --8<-- "recipes/starfleet/branches/java/src/main/java/Main.java"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/starfleet/branches/csharp/Program.cs"
    ```

=== "Go"

    ```go
    --8<-- "recipes/starfleet/branches/go/main.go"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/starfleet/branches/rust/src/main.rs"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/starfleet/branches/ruby/main.rb"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/starfleet/branches/curl/main.sh"
    ```

## Next Steps

The following resources provide more information about the topics in this
recipe:

- The "Creating a Database and Waiting for It" recipe explains the creation and
  deletion steps in more detail.
- The "Connecting to a Starfleet Database" recipe explains the connection step
  in more detail.
- The PostgreSQL documentation for
  [SSL support](https://www.postgresql.org/docs/current/libpq-ssl.html)
  explains the `sslmode` setting.
