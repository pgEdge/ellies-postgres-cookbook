# Connecting Securely with TLS

This recipe demonstrates how an application connects to a PostgreSQL server
over an encrypted connection, and checks the identity of the server before
it sends any data. Encryption alone protects against eavesdropping, but only
verification protects against an attacker who impersonates the server; the
recipe therefore uses the strictest verification mode that libpq and its
equivalents offer. Each step shows the code in every supported language;
selecting a language tab switches every tab on the site to that language.

The example program connects with full verification, asks the server
whether the session is encrypted, and prints the result. The program prints
the second line only after the driver has verified the server certificate,
so the output is the same on every server that is set up correctly:

```text
Connection is encrypted: true
Server certificate verified: true
```

## Preparing the Ingredients

The example needs a server with TLS enabled, and the certificate of the
certificate authority (CA) that signed the server certificate, in PEM
format. The `scripts/start_test_server.sh` script in the cookbook repository
starts a suitable server in Docker, and prints the path of the CA
certificate on a line that begins with `PGSSLROOTCERT=`. The server
certificate that the script generates names `localhost` and `127.0.0.1`,
and any other host name that you pass to the script.

Each example uses the same driver as the first recipe, with the addition of
OpenSSL for the Rust example. The following table lists the driver that each
example uses:

| Language   | Driver                                                 |
|------------|--------------------------------------------------------|
| Python     | [psycopg 3](https://www.psycopg.org/psycopg3/)         |
| TypeScript | [node-postgres](https://node-postgres.com/)            |
| Java       | [pgJDBC](https://jdbc.postgresql.org/)                 |
| C#         | [Npgsql](https://www.npgsql.org/)                      |
| Go         | [pgx](https://github.com/jackc/pgx)                    |
| Rust       | [rust-postgres](https://github.com/sfackler/rust-postgres) with [postgres-openssl](https://docs.rs/postgres-openssl) |
| Ruby       | [ruby-pg](https://github.com/ged/ruby-pg)              |
| C          | [libpq](https://www.postgresql.org/docs/current/libpq.html) |

The Rust example builds the `openssl` crate, which needs the OpenSSL
development headers; on Debian and Ubuntu, the `libssl-dev` package
provides them. The following tabs show the dependency declaration from each
example project:

=== "Python"

    ```text
    --8<-- "recipes/postgresql/tls_connect/python/requirements.txt:deps"
    ```

=== "TypeScript"

    ```json
    --8<-- "recipes/postgresql/tls_connect/typescript/package.json"
    ```

=== "Java"

    ```xml
    --8<-- "recipes/postgresql/tls_connect/java/pom.xml:deps"
    ```

=== "C#"

    ```xml
    --8<-- "recipes/postgresql/tls_connect/csharp/TlsConnect.csproj:deps"
    ```

=== "Go"

    ```text
    --8<-- "recipes/postgresql/tls_connect/go/go.mod:deps"
    ```

=== "Rust"

    ```toml
    --8<-- "recipes/postgresql/tls_connect/rust/Cargo.toml:deps"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgresql/tls_connect/ruby/Gemfile:deps"
    ```

=== "C"

    ```make
    --8<-- "recipes/postgresql/tls_connect/c/Makefile:deps"
    ```

## Importing the Driver

Each program begins by importing the driver, along with any standard
library modules that the program uses. The TypeScript program also imports
the function that reads the certificate file, and the Rust program imports
the OpenSSL connector. The following tabs show the imports for each
language:

=== "Python"

    ```python
    --8<-- "recipes/postgresql/tls_connect/python/main.py:imports"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgresql/tls_connect/typescript/main.ts:imports"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgresql/tls_connect/java/src/main/java/Main.java:imports"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgresql/tls_connect/csharp/Program.cs:imports"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgresql/tls_connect/go/main.go:imports"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgresql/tls_connect/rust/src/main.rs:imports"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgresql/tls_connect/ruby/main.rb:imports"
    ```

=== "C"

    ```c
    --8<-- "recipes/postgresql/tls_connect/c/main.c:imports"
    ```

## Configuring the Connection

The examples read their connection settings from the same environment
variables as the first recipe, and add `PGSSLROOTCERT`, which names the
file that holds the CA certificate. Like libpq, each example treats an empty
variable as unset and uses the default instead; the examples have no default
for `PGSSLROOTCERT`, and report an error if it is missing, because
verification means nothing without a certificate to verify against. The
following table describes the environment variables that the examples read:

| Variable        | Default     | Description                                 |
|-----------------|-------------|---------------------------------------------|
| `PGHOST`        | `localhost` | The host name of the server.                |
| `PGPORT`        | `5432`      | The TCP port on which the server listens.   |
| `PGDATABASE`    | `postgres`  | The name of the database to connect to.     |
| `PGUSER`        | `postgres`  | The user name to connect as.                |
| `PGPASSWORD`    | None        | The password; omitted if unset or empty.    |
| `PGSSLROOTCERT` | None        | The path of the CA certificate file.        |

The host name matters more than usual in this recipe. With `verify-full`,
the driver compares `PGHOST` with the names in the server certificate, so
the connection fails if you connect by a name that the certificate does not
list. Versions of libpq before PostgreSQL 15 do not match an IP address
against the `iPAddress` names in a certificate, so use a host name such as
`localhost` rather than `127.0.0.1` if you see a host name mismatch.

The `sslmode` setting controls how much a client checks. The following
table lists the modes that libpq defines, and the drivers use the same
names or an equivalent:

| Mode          | Encrypts | Checks the CA | Checks the host name |
|---------------|----------|---------------|----------------------|
| `disable`     | Never    | No            | No                   |
| `prefer`      | If the server offers it | No | No                |
| `require`     | Always   | No            | No                   |
| `verify-ca`   | Always   | Yes           | No                   |
| `verify-full` | Always   | Yes           | Yes                  |

The Python, Go, Ruby, Java, and C programs pass `verify-full` and the
certificate path as connection parameters, and the C# program sets the
`VerifyFull` mode and the root certificate on the connection string
builder. The TypeScript driver does not take an `sslmode` parameter;
instead, that program loads only the CA certificate into the TLS library
and leaves certificate and host name checks enabled, which is what
`verify-full` means. The Rust driver has an `ssl_mode` setting, but its
`Require` value only insists on encryption (its default, `Prefer`, falls
back to a plain connection if the server declines TLS), so the Rust
program sets `Require` and leaves the verification to the TLS connector
described in the next step. The following tabs show how each program
assembles the connection settings:

=== "Python"

    ```python
    --8<-- "recipes/postgresql/tls_connect/python/main.py:config"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgresql/tls_connect/typescript/main.ts:config"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgresql/tls_connect/java/src/main/java/Main.java:config"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgresql/tls_connect/csharp/Program.cs:config"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgresql/tls_connect/go/main.go:config"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgresql/tls_connect/rust/src/main.rs:config"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgresql/tls_connect/ruby/main.rb:config"
    ```

=== "C"

    ```c
    --8<-- "recipes/postgresql/tls_connect/c/main.c:config"
    ```

## Opening a Connection

Each program opens a connection to the server with the settings from the
previous step. The C# program creates an Npgsql data source, which lends
out pooled connections when the main part of the program asks for one. The
Rust program first builds an OpenSSL connector whose certificate store
holds only the CA certificate (the connector otherwise starts with the
system root certificates), and passes it to the driver in place of the `NoTls` value that
the first recipe uses. If the server certificate is not signed by that CA,
has expired, or does not match the host name, the driver raises an error
instead of connecting; the Handling Errors and Closing the Connection
section describes how each program reports the failure. The following tabs
show how each program opens the connection:

=== "Python"

    ```python
    --8<-- "recipes/postgresql/tls_connect/python/main.py:connect"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgresql/tls_connect/typescript/main.ts:connect"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgresql/tls_connect/java/src/main/java/Main.java:connect"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgresql/tls_connect/csharp/Program.cs:connect"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgresql/tls_connect/go/main.go:connect"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgresql/tls_connect/rust/src/main.rs:connect"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgresql/tls_connect/ruby/main.rb:connect"
    ```

=== "C"

    ```c
    --8<-- "recipes/postgresql/tls_connect/c/main.c:connect"
    ```

## Checking That the Connection Is Encrypted

Each program runs a query against the `pg_stat_ssl` system view, which
holds one row for each connection to the server. The `pg_backend_pid()`
function returns the process ID of the session that runs the query, so the
`WHERE` clause selects the row for the current connection. The `ssl` column
is `true` when the connection uses TLS, and the `version` column holds the
protocol version, such as `TLSv1.3`. The programs select the version but do
not print it, because it varies with the server and the client library.

The first output line comes from the server, so it reports what the server
sees, whereas the second line follows from the driver having accepted the
certificate. The following tabs show how each program runs the query and
reads the result:

=== "Python"

    ```python
    --8<-- "recipes/postgresql/tls_connect/python/main.py:query"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgresql/tls_connect/typescript/main.ts:query"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgresql/tls_connect/java/src/main/java/Main.java:query"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgresql/tls_connect/csharp/Program.cs:query"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgresql/tls_connect/go/main.go:query"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgresql/tls_connect/rust/src/main.rs:query"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgresql/tls_connect/ruby/main.rb:query"
    ```

=== "C"

    ```c
    --8<-- "recipes/postgresql/tls_connect/c/main.c:query"
    ```

## Handling Errors and Closing the Connection

The main part of each program calls the functions from the previous steps,
and prints the two lines of output. A failed verification is an ordinary
connection error: the program reports it on `stderr` and exits with a
non-zero status, and never prints the second line. A typical message from
libpq is `certificate verify failed` when the CA does not match, or
`server certificate for "name" does not match host name` when the host name
does not match. Treat the error as a sign of a wrong certificate file or a
wrong host name, and do not fall back to a weaker `sslmode` to silence it.

The error handling follows the first recipe: the Python, C#, and Ruby
programs catch the base error class of the driver, the Java program
catches `SQLException`, and the TypeScript program catches any rejected
promise. The Go and Rust programs return each error from a `run()`
function to `main()`, and the C program checks the result of each call.
Each program also closes the connection when the work completes or fails.
The following tabs show the main part of each program:

=== "Python"

    ```python
    --8<-- "recipes/postgresql/tls_connect/python/main.py:main"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgresql/tls_connect/typescript/main.ts:main"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgresql/tls_connect/java/src/main/java/Main.java:main"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgresql/tls_connect/csharp/Program.cs:main"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgresql/tls_connect/go/main.go:main"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgresql/tls_connect/rust/src/main.rs:main"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgresql/tls_connect/ruby/main.rb:main"
    ```

=== "C"

    ```c
    --8<-- "recipes/postgresql/tls_connect/c/main.c:main"
    ```

## Running the Example

The complete project for each language is available in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/postgresql/tls_connect).
Set the environment variables for your server, including `PGSSLROOTCERT`,
and then run the command for your language from the corresponding project
directory. The following tabs show the commands that build and run each
example:

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
    --8<-- "recipes/postgresql/tls_connect/python/main.py"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/postgresql/tls_connect/typescript/main.ts"
    ```

=== "Java"

    ```java
    --8<-- "recipes/postgresql/tls_connect/java/src/main/java/Main.java"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/postgresql/tls_connect/csharp/Program.cs"
    ```

=== "Go"

    ```go
    --8<-- "recipes/postgresql/tls_connect/go/main.go"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/postgresql/tls_connect/rust/src/main.rs"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/postgresql/tls_connect/ruby/main.rb"
    ```

=== "C"

    ```c
    --8<-- "recipes/postgresql/tls_connect/c/main.c"
    ```

## Next Steps

The following resources provide more information about the topics in this
recipe:

- The [Connecting to PostgreSQL and Running a Query](connect_and_query.md)
  recipe explains the parts of the program that this recipe shares with it.
- The PostgreSQL documentation for
  [SSL support](https://www.postgresql.org/docs/current/ssl-tcp.html)
  explains how to enable TLS on a server and create its certificates.
- The PostgreSQL documentation for
  [SSL mode descriptions](https://www.postgresql.org/docs/current/libpq-ssl.html#LIBPQ-SSL-PROTECTION)
  describes what each `sslmode` protects against.
- The
  [pg_stat_ssl](https://www.postgresql.org/docs/current/monitoring-stats.html#MONITORING-PG-STAT-SSL-VIEW)
  view documents the columns that the query reads.
