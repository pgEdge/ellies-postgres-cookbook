# Rotating a Role Password

This recipe shows how to rotate the password of the built-in `app` role of a
pgEdge Starfleet database, wait for the database to apply it, and connect with
the new password. Because the recipe needs a database, the program creates one
with the code from the "Creating a Database and Waiting for It" recipe, and
deletes it at the end. Starfleet bills for the database whilst it exists, so
the program removes it on every path out. The server generates the new
password, and the program never prints a password.

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
Rotating the password of the app role
Database status: modifying
Database status: available
Password rotated
Connected as app with the new password
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

    Starfleet bills for a database until deletion is requested. The program
    deletes the database that it creates whether the example succeeds, fails,
    or is interrupted with Ctrl-C, and waits until the API no longer lists it.
    If the reply to the create request is lost, the program looks the database
    up by its name before it deletes it, and if that fails it tells you the
    name so that you can delete it by hand. A program that is killed outright,
    with `kill -9` for instance, cannot clean up, so check your account for
    databases whose display names start with `cookbook-` if you stop a run that
    way.

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
    --8<-- "recipes/starfleet/rotate_password/python/requirements.txt:deps"
    ```

=== "TypeScript"

    ```json
    --8<-- "recipes/starfleet/rotate_password/typescript/package.json"
    ```

=== "Java"

    ```xml
    --8<-- "recipes/starfleet/rotate_password/java/pom.xml:deps"
    ```

=== "C#"

    ```xml
    --8<-- "recipes/starfleet/rotate_password/csharp/RotatePassword.csproj:deps"
    ```

=== "Go"

    ```text
    --8<-- "recipes/starfleet/rotate_password/go/go.mod:deps"
    ```

=== "Rust"

    ```toml
    --8<-- "recipes/starfleet/rotate_password/rust/Cargo.toml:deps"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/starfleet/rotate_password/ruby/Gemfile:deps"
    ```

## Importing the Libraries

The following code shows the imports and, for the curl script, the check for
the tools that it needs:

=== "Python"

    ```python
    --8<-- "recipes/starfleet/rotate_password/python/main.py:imports"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/starfleet/rotate_password/typescript/main.ts:imports"
    ```

=== "Java"

    ```java
    --8<-- "recipes/starfleet/rotate_password/java/src/main/java/Main.java:imports"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/starfleet/rotate_password/csharp/Program.cs:imports"
    ```

=== "Go"

    ```go
    --8<-- "recipes/starfleet/rotate_password/go/main.go:imports"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/starfleet/rotate_password/rust/src/main.rs:imports"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/starfleet/rotate_password/ruby/main.rb:imports"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/starfleet/rotate_password/curl/main.sh:imports"
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
    --8<-- "recipes/starfleet/rotate_password/python/main.py:config"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/starfleet/rotate_password/typescript/main.ts:config"
    ```

=== "Java"

    ```java
    --8<-- "recipes/starfleet/rotate_password/java/src/main/java/Main.java:config"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/starfleet/rotate_password/csharp/Program.cs:config"
    ```

=== "Go"

    ```go
    --8<-- "recipes/starfleet/rotate_password/go/main.go:config"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/starfleet/rotate_password/rust/src/main.rs:config"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/starfleet/rotate_password/ruby/main.rb:config"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/starfleet/rotate_password/curl/main.sh:config"
    ```

## Getting a Token

The program gets a token in the same way as the "Getting an Access Token"
recipe:

=== "Python"

    ```python
    --8<-- "recipes/starfleet/rotate_password/python/main.py:token"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/starfleet/rotate_password/typescript/main.ts:token"
    ```

=== "Java"

    ```java
    --8<-- "recipes/starfleet/rotate_password/java/src/main/java/Main.java:token"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/starfleet/rotate_password/csharp/Program.cs:token"
    ```

=== "Go"

    ```go
    --8<-- "recipes/starfleet/rotate_password/go/main.go:token"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/starfleet/rotate_password/rust/src/main.rs:token"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/starfleet/rotate_password/ruby/main.rb:token"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/starfleet/rotate_password/curl/main.sh:token"
    ```

## Calling the Managed API

The `api` function sends an authenticated request and returns the decoded
reply. The program also reacts to particular error statuses, so the error that
the function raises carries the HTTP status:

=== "Python"

    ```python
    --8<-- "recipes/starfleet/rotate_password/python/main.py:api"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/starfleet/rotate_password/typescript/main.ts:api"
    ```

=== "Java"

    ```java
    --8<-- "recipes/starfleet/rotate_password/java/src/main/java/Main.java:api"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/starfleet/rotate_password/csharp/Program.cs:api"
    ```

=== "Go"

    ```go
    --8<-- "recipes/starfleet/rotate_password/go/main.go:api"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/starfleet/rotate_password/rust/src/main.rs:api"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/starfleet/rotate_password/ruby/main.rb:api"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/starfleet/rotate_password/curl/main.sh:api"
    ```

## Choosing a Region and Size

The program creates its own database, with the code from the "Creating a
Database and Waiting for It" recipe. It chooses the first region and the
smallest size, and the following code makes the choice:

=== "Python"

    ```python
    --8<-- "recipes/starfleet/rotate_password/python/main.py:placement"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/starfleet/rotate_password/typescript/main.ts:placement"
    ```

=== "Java"

    ```java
    --8<-- "recipes/starfleet/rotate_password/java/src/main/java/Main.java:placement"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/starfleet/rotate_password/csharp/Program.cs:placement"
    ```

=== "Go"

    ```go
    --8<-- "recipes/starfleet/rotate_password/go/main.go:placement"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/starfleet/rotate_password/rust/src/main.rs:placement"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/starfleet/rotate_password/ruby/main.rb:placement"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/starfleet/rotate_password/curl/main.sh:placement"
    ```

## Creating the Database

The following code creates the database, which only your machine can reach, and
names it with the `cookbook-` prefix:

=== "Python"

    ```python
    --8<-- "recipes/starfleet/rotate_password/python/main.py:create"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/starfleet/rotate_password/typescript/main.ts:create"
    ```

=== "Java"

    ```java
    --8<-- "recipes/starfleet/rotate_password/java/src/main/java/Main.java:create"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/starfleet/rotate_password/csharp/Program.cs:create"
    ```

=== "Go"

    ```go
    --8<-- "recipes/starfleet/rotate_password/go/main.go:create"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/starfleet/rotate_password/rust/src/main.rs:create"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/starfleet/rotate_password/ruby/main.rb:create"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/starfleet/rotate_password/curl/main.sh:create"
    ```

## Waiting for the Database

The following code polls the database until its status is `available`, and
stops at once if the status is `degraded` or `failed`:

=== "Python"

    ```python
    --8<-- "recipes/starfleet/rotate_password/python/main.py:wait"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/starfleet/rotate_password/typescript/main.ts:wait"
    ```

=== "Java"

    ```java
    --8<-- "recipes/starfleet/rotate_password/java/src/main/java/Main.java:wait"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/starfleet/rotate_password/csharp/Program.cs:wait"
    ```

=== "Go"

    ```go
    --8<-- "recipes/starfleet/rotate_password/go/main.go:wait"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/starfleet/rotate_password/rust/src/main.rs:wait"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/starfleet/rotate_password/ruby/main.rb:wait"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/starfleet/rotate_password/curl/main.sh:wait"
    ```

## Reading the Connection Details

The description of an available database includes a `connection` object with
the host name, the port, the database name, the user name, and the password of
the application user. The API requires the user name, the password, the port,
and the database name but not the host, so the code checks that they are all
present, and falls back to the external IP address if the host is missing. The
details appear only once the database is available, and the description holds
the current password, so the program reads it again after the rotation. The
password never goes in a connection string that the program writes, or on a
command line: Python, TypeScript, and Ruby pass it to the driver as a separate
setting, Java puts it in the connection properties rather than the URL, C# sets
it on an `NpgsqlConnectionStringBuilder`, Go and Rust set it on the
configuration object, and the curl script writes it to a temporary password
file that only its owner can read, and removes the file at the end:

=== "Python"

    ```python
    --8<-- "recipes/starfleet/rotate_password/python/main.py:connection"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/starfleet/rotate_password/typescript/main.ts:connection"
    ```

=== "Java"

    ```java
    --8<-- "recipes/starfleet/rotate_password/java/src/main/java/Main.java:connection"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/starfleet/rotate_password/csharp/Program.cs:connection"
    ```

=== "Go"

    ```go
    --8<-- "recipes/starfleet/rotate_password/go/main.go:connection"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/starfleet/rotate_password/rust/src/main.rs:connection"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/starfleet/rotate_password/ruby/main.rb:connection"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/starfleet/rotate_password/curl/main.sh:connection"
    ```

## Rotating the Password

The API rotates the password of a built-in role from a `POST` request with no
body to the `rotate-password` endpoint of the role, and answers 204 once it has
accepted the rotation. The server generates the new password: the request does
not carry one, and the program reads the new password from the description of
the database. The `app` role is one of the built-in roles (the others are
`admin` and `app_read_only`). The API documents that the rotation is
asynchronous, that the database moves to the `modifying` status until it is
live, and that until then the previous password still works and the new one
does not. It also documents that a rotation that fails leaves the database
`degraded` with the previous password still working. The wait therefore ends
only when the status is `available` and the password in the description differs
from the old one, and stops at once on `degraded` or `failed`. The following
code rotates the password and waits for it to take effect:

=== "Python"

    ```python
    --8<-- "recipes/starfleet/rotate_password/python/main.py:rotate"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/starfleet/rotate_password/typescript/main.ts:rotate"
    ```

=== "Java"

    ```java
    --8<-- "recipes/starfleet/rotate_password/java/src/main/java/Main.java:rotate"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/starfleet/rotate_password/csharp/Program.cs:rotate"
    ```

=== "Go"

    ```go
    --8<-- "recipes/starfleet/rotate_password/go/main.go:rotate"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/starfleet/rotate_password/rust/src/main.rs:rotate"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/starfleet/rotate_password/ruby/main.rb:rotate"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/starfleet/rotate_password/curl/main.sh:rotate"
    ```

## Running the Query

If the `PGSSLROOTCERT` environment variable is set, as it is after you start
the test server for the TLS recipe, unset it before you run the Python, Go, and
Ruby programs or the curl script. The libpq library (and so psycopg, ruby-pg,
and `psql`) and pgx then treat `sslmode=require` as `verify-ca`, and reject the
certificate of a Starfleet database. The Java, C#, and Rust programs are not
affected.

The program connects with the new password, using the driver for the language
(psycopg for Python, node-postgres for TypeScript, pgJDBC for Java, Npgsql for
C#, pgx for Go, rust-postgres for Rust, ruby-pg for Ruby, and `psql` for the
curl script), and runs `SELECT current_user`, which shows that the login
worked. The connection is encrypted. The certificate of a Starfleet database is
not signed by a public authority, so the example does not verify it. That
leaves the connection open to a man-in-the-middle attack, because anyone who
can intercept the traffic could pose as the server, so do not use this approach
for data that matters. A server can refuse connections for a short while after
a change, so the code makes up to six attempts, ten seconds apart. The Python,
TypeScript, Java, C#, Go, and Rust code retries failures to connect, and also a
failed login (SQLSTATE 28P01), because the API may report the database as
available a moment before the new password works, but not other errors that the
server reports; libpq gives no SQLSTATE code for any failure to connect, so
ruby-pg cannot tell a failed login from a refused connection, and the Ruby code
repeats them all, as the curl script does, because `psql` gives the same exit
status for every failure to connect. The following code runs the query:

=== "Python"

    ```python
    --8<-- "recipes/starfleet/rotate_password/python/main.py:query"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/starfleet/rotate_password/typescript/main.ts:query"
    ```

=== "Java"

    ```java
    --8<-- "recipes/starfleet/rotate_password/java/src/main/java/Main.java:query"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/starfleet/rotate_password/csharp/Program.cs:query"
    ```

=== "Go"

    ```go
    --8<-- "recipes/starfleet/rotate_password/go/main.go:query"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/starfleet/rotate_password/rust/src/main.rs:query"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/starfleet/rotate_password/ruby/main.rb:query"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/starfleet/rotate_password/curl/main.sh:query"
    ```

## Deleting the Resources

The API documents a 409 reply to a delete as meaning that the database has
branches, and offers a `force` parameter for that case. In testing, the API
also answered 409 whilst a database was still being created, so the program
repeats the request after a 409, after a 429 or 5xx status, and after a failure
to get any reply, until the time limit passes. A 404 means that the database
has gone already. A delete only starts the teardown, so the program then polls
until the API answers 404, which in testing was the sign that the database had
gone. If the outcome of the create request is unknown (no reply arrived, the
service answered with a 5xx status, the reply could not be read, or you
interrupted the program during the request), the program has no database ID, so
it first lists the databases and picks the one with the name that it chose
before the request, trying up to three times, ten seconds apart, and then
reports the name so that you can check your account by hand. It does not look
after a 4xx reply, because that is a definite refusal. The list request passes
`limit=100` and `descending=true`, but the API specification does not say which
property it sorts on. If the delete or the lookup fails, the program tells you
to delete the database by hand. The program cannot delete the backup, because
the API has no way to do so, and the specification does not say what happens to
a backup when its database is deleted. The following code deletes the database:

=== "Python"

    ```python
    --8<-- "recipes/starfleet/rotate_password/python/main.py:delete"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/starfleet/rotate_password/typescript/main.ts:delete"
    ```

=== "Java"

    ```java
    --8<-- "recipes/starfleet/rotate_password/java/src/main/java/Main.java:delete"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/starfleet/rotate_password/csharp/Program.cs:delete"
    ```

=== "Go"

    ```go
    --8<-- "recipes/starfleet/rotate_password/go/main.go:delete"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/starfleet/rotate_password/rust/src/main.rs:delete"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/starfleet/rotate_password/ruby/main.rb:delete"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/starfleet/rotate_password/curl/main.sh:delete"
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
to finish doing so, and then ends the program. The program keeps the old
password only in memory, to compare it with the new one, and never prints
either. The program chooses the database name before it sends the create
request, so the cleanup can find the database by name if the reply never
arrives. The cleanup ignores further interrupts, because a second Ctrl-C must
not leave a billable database behind. The following code shows the function:

=== "Python"

    ```python
    --8<-- "recipes/starfleet/rotate_password/python/main.py:main"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/starfleet/rotate_password/typescript/main.ts:main"
    ```

=== "Java"

    ```java
    --8<-- "recipes/starfleet/rotate_password/java/src/main/java/Main.java:main"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/starfleet/rotate_password/csharp/Program.cs:main"
    ```

=== "Go"

    ```go
    --8<-- "recipes/starfleet/rotate_password/go/main.go:main"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/starfleet/rotate_password/rust/src/main.rs:main"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/starfleet/rotate_password/ruby/main.rb:main"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/starfleet/rotate_password/curl/main.sh:main"
    ```

## Running the Example

The complete project for each language is available in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/starfleet/rotate_password).
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
    --8<-- "recipes/starfleet/rotate_password/python/main.py"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/starfleet/rotate_password/typescript/main.ts"
    ```

=== "Java"

    ```java
    --8<-- "recipes/starfleet/rotate_password/java/src/main/java/Main.java"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/starfleet/rotate_password/csharp/Program.cs"
    ```

=== "Go"

    ```go
    --8<-- "recipes/starfleet/rotate_password/go/main.go"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/starfleet/rotate_password/rust/src/main.rs"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/starfleet/rotate_password/ruby/main.rb"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/starfleet/rotate_password/curl/main.sh"
    ```

## Next Steps

The following resources provide more information about the topics in this
recipe:

- The "Connecting to a Starfleet Database" recipe explains the connection step
  in more detail.
- The "Creating a Database and Waiting for It" recipe explains the creation and
  deletion steps in more detail.
