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
| Rust       | [rust-postgres](https://github.com/rust-postgres/rust-postgres) with [postgres-openssl](https://docs.rs/postgres-openssl) |
| Ruby       | [ruby-pg](https://github.com/ged/ruby-pg)              |
| C          | [libpq](https://www.postgresql.org/docs/current/libpq.html) |

The Rust example builds the `openssl` crate, which needs the OpenSSL
development headers; on Debian and Ubuntu, the `libssl-dev` package
provides them. The following tabs show the dependency declaration from each
example project:

=== "Python"

    ```text
    # psycopg 3, with the pre-built binary package that bundles libpq (and
    # therefore OpenSSL).
    psycopg[binary]>=3.2,<4
    ```

=== "TypeScript"

    ```json
    {
      "name": "tls-connect",
      "private": true,
      "type": "module",
      "scripts": {
        "build": "tsc",
        "start": "node dist/main.js"
      },
      "dependencies": {
        "pg": "^8.23.1"
      },
      "devDependencies": {
        "@types/node": "^22.0.0",
        "@types/pg": "^8.23.1",
        "typescript": "^5.9.0"
      }
    }
    
    ```

=== "Java"

    ```xml
    <dependencies>
      <!-- The PostgreSQL JDBC driver (pgJDBC). -->
      <dependency>
        <groupId>org.postgresql</groupId>
        <artifactId>postgresql</artifactId>
        <version>42.7.14</version>
      </dependency>
    </dependencies>
    ```

=== "C#"

    ```xml
    <ItemGroup>
      <!-- Npgsql, the ADO.NET data provider for PostgreSQL. -->
      <PackageReference Include="Npgsql" Version="10.0.3" />
    </ItemGroup>
    ```

=== "Go"

    ```text
    // pgx is a pure Go driver and toolkit for PostgreSQL.
    require github.com/jackc/pgx/v5 v5.12.0
    
    require (
    	github.com/jackc/pgpassfile v1.0.0 // indirect
    	github.com/jackc/pgservicefile v0.0.0-20240606120523-5a60cdf6a761 // indirect
    	golang.org/x/text v0.41.0 // indirect
    )
    
    ```

=== "Rust"

    ```toml
    [dependencies]
    # The synchronous client; tokio-postgres is the asynchronous equivalent.
    postgres = "0.19"
    # TLS support for rust-postgres, using OpenSSL through the openssl crate.
    postgres-openssl = "0.5"
    openssl = "0.10"
    ```

=== "Ruby"

    ```ruby
    source "https://rubygems.org"
    
    # The pg gem wraps libpq, so libpq and its headers must be installed.
    gem "pg", "~> 1.6"
    ```

=== "C"

    ```make
    # Build with libpq, using pg_config to find the headers and library.
    CFLAGS += -Wall -Wextra -I$(shell pg_config --includedir)
    LDFLAGS += -L$(shell pg_config --libdir)
    LDLIBS += -lpq
    
    main: main.c
    ```

## Importing the Driver

Each program begins by importing the driver, along with any standard
library modules that the program uses. The TypeScript program also imports
the function that reads the certificate file, and the Rust program imports
the OpenSSL connector. The following tabs show the imports for each
language:

=== "Python"

    ```python
    import os
    import sys
    
    import psycopg
    ```

=== "TypeScript"

    ```typescript
    import { readFileSync } from "node:fs";
    
    import pg from "pg";
    ```

=== "Java"

    ```java
    import java.sql.Connection;
    import java.sql.DriverManager;
    import java.sql.ResultSet;
    import java.sql.SQLException;
    import java.sql.Statement;
    import java.util.Properties;
    ```

=== "C#"

    ```csharp
    using Npgsql;
    ```

=== "Go"

    ```go
    import (
    	"context"
    	"errors"
    	"fmt"
    	"net"
    	"net/url"
    	"os"
    
    	"github.com/jackc/pgx/v5"
    )
    
    ```

=== "Rust"

    ```rust
    use std::env;
    use std::error::Error;
    use std::process::ExitCode;
    
    use openssl::ssl::{SslConnector, SslMethod};
    use openssl::x509::store::X509StoreBuilder;
    use openssl::x509::X509;
    use postgres::config::SslMode;
    use postgres::{Client, Config};
    use postgres_openssl::MakeTlsConnector;
    ```

=== "Ruby"

    ```ruby
    require "pg"
    ```

=== "C"

    ```c
    #include <stdbool.h>
    #include <stdio.h>
    #include <stdlib.h>
    #include <string.h>
    
    #include <libpq-fe.h>
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
    def connection_settings() -> dict:
        """Reads the connection settings from the standard libpq environment
        variables, with defaults suitable for a local development server.
    
        The or operator treats an empty variable as unset, as libpq does, and
        a password of None is simply not sent. PGSSLROOTCERT has no default,
        because verification is meaningless without the certificate of the
        authority that signed the server certificate.
        """
        root_cert = os.environ.get("PGSSLROOTCERT")
        if not root_cert:
            raise RuntimeError("PGSSLROOTCERT must name the root certificate")
    
        return {
            "host": os.environ.get("PGHOST") or "localhost",
            "port": os.environ.get("PGPORT") or "5432",
            "dbname": os.environ.get("PGDATABASE") or "postgres",
            "user": os.environ.get("PGUSER") or "postgres",
            "password": os.environ.get("PGPASSWORD") or None,
            # verify-full checks that the certificate chains to the root
            # certificate and that it matches the host name. Weaker modes,
            # such as require, encrypt the connection without proving who is
            # on the other end.
            "sslmode": "verify-full",
            "sslrootcert": root_cert,
        }
    ```

=== "TypeScript"

    ```typescript
    // Read the connection settings from the standard libpq environment
    // variables, with defaults suitable for a local development server.
    // The || operator, unlike ??, also treats an empty variable as unset, as
    // libpq does.
    function connectionConfig(): pg.ClientConfig {
      // PGSSLROOTCERT has no default, because verification is meaningless
      // without the certificate of the authority that signed the server
      // certificate.
      const rootCert = process.env.PGSSLROOTCERT;
      if (!rootCert) {
        throw new Error("PGSSLROOTCERT must name the root certificate");
      }
    
      return {
        host: process.env.PGHOST || "localhost",
        port: Number(process.env.PGPORT || "5432"),
        database: process.env.PGDATABASE || "postgres",
        user: process.env.PGUSER || "postgres",
        password: process.env.PGPASSWORD || undefined,
        // Supplying the root certificate as ca makes Node trust only that
        // authority, and rejectUnauthorized makes Node reject a certificate
        // that does not chain to it or does not match the host name. Together
        // they are the equivalent of sslmode=verify-full.
        ssl: { ca: readFileSync(rootCert), rejectUnauthorized: true },
      };
    }
    ```

=== "Java"

    ```java
    /** Returns the value of an environment variable, or a fallback. */
    static String envOr(String name, String fallback) {
        String value = System.getenv(name);
        return (value != null && !value.isEmpty()) ? value : fallback;
    }
    
    /**
     * Returns the JDBC URL that identifies the server and database, built
     * from the standard libpq environment variables.
     */
    static String connectionUrl() {
        return "jdbc:postgresql://"
                + envOr("PGHOST", "localhost") + ":"
                + envOr("PGPORT", "5432") + "/"
                + envOr("PGDATABASE", "postgres");
    }
    
    /**
     * Returns the user name, password, and TLS settings as connection
     * properties; the password is omitted if PGPASSWORD is unset or
     * empty. PGSSLROOTCERT has no default, because verification is
     * meaningless without the certificate of the authority that signed
     * the server certificate.
     */
    static Properties connectionProperties() {
        String rootCert = envOr("PGSSLROOTCERT", null);
        if (rootCert == null) {
            throw new IllegalStateException(
                    "PGSSLROOTCERT must name the root certificate");
        }
    
        Properties props = new Properties();
        props.setProperty("user", envOr("PGUSER", "postgres"));
        String password = envOr("PGPASSWORD", null);
        if (password != null) {
            props.setProperty("password", password);
        }
        // verify-full checks that the certificate chains to the root
        // certificate and that it matches the host name. Weaker modes,
        // such as require, encrypt the connection without proving who is
        // on the other end.
        props.setProperty("sslmode", "verify-full");
        props.setProperty("sslrootcert", rootCert);
        return props;
    }
    ```

=== "C#"

    ```csharp
    // Returns the value of an environment variable, or null if the variable
    // is unset or empty; libpq also treats an empty variable as unset.
    static string? EnvValue(string name) =>
        Environment.GetEnvironmentVariable(name) is { Length: > 0 } value
            ? value
            : null;
    
    // Returns the value of an environment variable, or a fallback if unset.
    static string EnvOr(string name, string fallback) =>
        EnvValue(name) ?? fallback;
    
    // Builds a connection string from the standard libpq environment
    // variables, with defaults suitable for a local development server. The
    // builder takes care of quoting any special characters. PGSSLROOTCERT has
    // no default, because verification is meaningless without the certificate
    // of the authority that signed the server certificate.
    static string ConnectionString() =>
        new NpgsqlConnectionStringBuilder
        {
            Host = EnvOr("PGHOST", "localhost"),
            Port = int.Parse(EnvOr("PGPORT", "5432")),
            Database = EnvOr("PGDATABASE", "postgres"),
            Username = EnvOr("PGUSER", "postgres"),
            Password = EnvValue("PGPASSWORD"),
            // VerifyFull checks that the certificate chains to the root
            // certificate and that it matches the host name. Weaker modes,
            // such as Require, encrypt the connection without proving who is
            // on the other end.
            SslMode = SslMode.VerifyFull,
            RootCertificate = EnvValue("PGSSLROOTCERT")
                ?? throw new InvalidOperationException(
                    "PGSSLROOTCERT must name the root certificate"),
        }.ConnectionString;
    ```

=== "Go"

    ```go
    // envOr returns the value of an environment variable, or a fallback if
    // the variable is unset or empty.
    func envOr(name, fallback string) string {
    	if value := os.Getenv(name); value != "" {
    		return value
    	}
    	return fallback
    }
    
    // connString builds a postgres:// URL from the standard libpq environment
    // variables. net/url takes care of escaping any special characters in
    // the user name, password, or database name. PGSSLROOTCERT has no
    // default, because verification is meaningless without the certificate
    // of the authority that signed the server certificate.
    func connString() (string, error) {
    	rootCert := os.Getenv("PGSSLROOTCERT")
    	if rootCert == "" {
    		return "", errors.New("PGSSLROOTCERT must name the root certificate")
    	}
    
    	u := url.URL{
    		Scheme: "postgres",
    		Host:   net.JoinHostPort(envOr("PGHOST", "localhost"), envOr("PGPORT", "5432")),
    		Path:   "/" + envOr("PGDATABASE", "postgres"),
    		// verify-full checks that the certificate chains to the root
    		// certificate and that it matches the host name. Weaker modes,
    		// such as require, encrypt the connection without proving who
    		// is on the other end.
    		RawQuery: url.Values{
    			"sslmode":     {"verify-full"},
    			"sslrootcert": {rootCert},
    		}.Encode(),
    	}
    	if password := os.Getenv("PGPASSWORD"); password != "" {
    		u.User = url.UserPassword(envOr("PGUSER", "postgres"), password)
    	} else {
    		u.User = url.User(envOr("PGUSER", "postgres"))
    	}
    	return u.String(), nil
    }
    
    ```

=== "Rust"

    ```rust
    /// Returns the value of an environment variable, if it is set and not
    /// empty; libpq also treats an empty variable as unset.
    fn env_value(name: &str) -> Option<String> {
        env::var(name).ok().filter(|value| !value.is_empty())
    }
    
    /// Returns the value of an environment variable, or a fallback if the
    /// variable is unset or empty.
    fn env_or(name: &str, fallback: &str) -> String {
        env_value(name).unwrap_or_else(|| fallback.to_string())
    }
    
    /// Builds the connection configuration from the standard libpq
    /// environment variables, with defaults suitable for a local server.
    /// The default SSL mode of the crate is Prefer, which falls back to a
    /// plain connection if the server declines TLS, so Require is set
    /// explicitly. Require makes the connection fail instead; the TLS
    /// connector built below then verifies the certificate.
    fn config() -> Config {
        let mut config = Config::new();
        config
            .ssl_mode(SslMode::Require)
            .host(&env_or("PGHOST", "localhost"))
            .port(env_or("PGPORT", "5432").parse().expect("PGPORT must be a number"))
            .dbname(&env_or("PGDATABASE", "postgres"))
            .user(&env_or("PGUSER", "postgres"));
        if let Some(password) = env_value("PGPASSWORD") {
            config.password(&password);
        }
        config
    }
    
    /// Returns the path of the root certificate file. PGSSLROOTCERT has no
    /// default, because verification is meaningless without the certificate
    /// of the authority that signed the server certificate.
    fn root_cert_path() -> Result<String, Box<dyn Error>> {
        env_value("PGSSLROOTCERT").ok_or_else(|| "PGSSLROOTCERT must name the root certificate".into())
    }
    ```

=== "Ruby"

    ```ruby
    # Returns the value of an environment variable, or a fallback if the
    # variable is unset or empty; libpq also treats an empty variable as unset.
    def env_or(name, fallback)
      value = ENV[name]
      value.nil? || value.empty? ? fallback : value
    end
    
    # Returns the connection settings from the standard libpq environment
    # variables, with defaults suitable for a local development server.
    # compact removes the password if PGPASSWORD is not set.
    def connection_params
      # PGSSLROOTCERT has no default, because verification is meaningless
      # without the certificate of the authority that signed the server
      # certificate.
      root_cert = env_or("PGSSLROOTCERT", nil)
      raise ArgumentError, "PGSSLROOTCERT must name the root certificate" unless root_cert
    
      {
        host: env_or("PGHOST", "localhost"),
        port: env_or("PGPORT", "5432"),
        dbname: env_or("PGDATABASE", "postgres"),
        user: env_or("PGUSER", "postgres"),
        password: env_or("PGPASSWORD", nil),
        # verify-full checks that the certificate chains to the root
        # certificate and that it matches the host name. Weaker modes, such
        # as require, encrypt the connection without proving who is on the
        # other end.
        sslmode: "verify-full",
        sslrootcert: root_cert
      }.compact
    end
    ```

=== "C"

    ```c
    /* Return the value of an environment variable, or a fallback if unset. */
    static const char *
    env_or(const char *name, const char *fallback)
    {
        const char *value = getenv(name);
    
        return (value != NULL && value[0] != '\0') ? value : fallback;
    }
    
    /*
     * Connection parameters are passed to libpq as two parallel,
     * NULL-terminated arrays of keywords and values. A NULL value is ignored,
     * so the password is only sent if PGPASSWORD is set.
     */
    static const char *const keywords[] = {
        "host", "port", "dbname", "user", "password",
        "sslmode", "sslrootcert", NULL
    };
    
    /*
     * Fill in the value for each keyword from the environment, and return
     * false if PGSSLROOTCERT is missing. It has no default, because
     * verification is meaningless without the certificate of the authority
     * that signed the server certificate.
     */
    static bool
    read_settings(const char *values[])
    {
        values[0] = env_or("PGHOST", "localhost");
        values[1] = env_or("PGPORT", "5432");
        values[2] = env_or("PGDATABASE", "postgres");
        values[3] = env_or("PGUSER", "postgres");
        values[4] = env_or("PGPASSWORD", NULL);
    
        /*
         * verify-full checks that the certificate chains to the root
         * certificate and that it matches the host name. Weaker modes, such
         * as require, encrypt the connection without proving who is on the
         * other end.
         */
        values[5] = "verify-full";
        values[6] = env_or("PGSSLROOTCERT", NULL);
        values[7] = NULL;
        return values[6] != NULL;
    }
    ```

## Opening a Connection

Each program opens a connection to the server with the settings from the
previous step. The C# program creates an Npgsql data source, which lends out
pooled connections when the main part of the program asks for one. The Rust
program first builds an OpenSSL connector whose certificate store holds only
the CA certificate (the connector otherwise starts with the system root
certificates), and passes it to the driver in place of the `NoTls` value that
the first recipe uses. If the server certificate is not signed by that CA, has
expired, or does not match the host name, the driver raises an error instead of
connecting; the Handling Errors and Closing the Connection section describes
how each program reports the failure. The following tabs show how each program
opens the connection:

=== "Python"

    ```python
    def connect() -> psycopg.Connection:
        """Opens a verified TLS connection with the settings from the
        environment. The connection fails if verification fails."""
        return psycopg.connect(**connection_settings())
    ```

=== "TypeScript"

    ```typescript
    // Opens a verified TLS connection with the settings from the
    // environment. The connection fails if verification fails.
    async function connect(): Promise<pg.Client> {
      const client = new pg.Client(connectionConfig());
      try {
        await client.connect();
      } catch (err) {
        // Release the client before passing the failure to the caller.
        await client.end();
        throw err;
      }
      return client;
    }
    ```

=== "Java"

    ```java
    /**
     * Opens a verified TLS connection with the settings from the
     * environment. The connection fails if verification fails.
     */
    static Connection connect() throws SQLException {
        return DriverManager.getConnection(
                connectionUrl(), connectionProperties());
    }
    ```

=== "C#"

    ```csharp
    // Creates a data source with the settings from the environment. A data
    // source manages a pool of physical connections, and each call to
    // OpenConnectionAsync borrows one from the pool; the connection fails if
    // verification fails.
    static NpgsqlDataSource CreateDataSource() =>
        NpgsqlDataSource.Create(ConnectionString());
    ```

=== "Go"

    ```go
    // connect opens a verified TLS connection with the settings from the
    // environment. The connection fails if verification fails.
    func connect(ctx context.Context) (*pgx.Conn, error) {
    	dsn, err := connString()
    	if err != nil {
    		return nil, err
    	}
    	conn, err := pgx.Connect(ctx, dsn)
    	if err != nil {
    		return nil, fmt.Errorf("connection failed: %w", err)
    	}
    	return conn, nil
    }
    
    ```

=== "Rust"

    ```rust
    /// Builds a TLS connector that trusts only the given root certificate.
    /// SslConnector::builder starts with the system root certificates, so the
    /// certificate store is replaced with one that holds nothing but the
    /// certificates in the file; otherwise any publicly trusted certificate
    /// for the host name would also be accepted. The connector verifies the
    /// certificate chain and the host name by default, which together are the
    /// equivalent of sslmode=verify-full; the host name checked is the one in
    /// the Config.
    fn tls_connector(root_cert: &str) -> Result<MakeTlsConnector, Box<dyn Error>> {
        let mut store = X509StoreBuilder::new()?;
        for cert in X509::stack_from_pem(&std::fs::read(root_cert)?)? {
            store.add_cert(cert)?;
        }
    
        let mut builder = SslConnector::builder(SslMethod::tls())?;
        builder.set_cert_store(store.build());
        Ok(MakeTlsConnector::new(builder.build()))
    }
    
    /// Opens a verified TLS connection with the settings from the
    /// environment. The connection fails if verification fails.
    fn connect() -> Result<Client, Box<dyn Error>> {
        let tls = tls_connector(&root_cert_path()?)?;
        Ok(config().connect(tls)?)
    }
    ```

=== "Ruby"

    ```ruby
    # Opens a verified TLS connection with the settings from the environment.
    # The connection fails if verification fails.
    def connect
      PG.connect(connection_params)
    end
    ```

=== "C"

    ```c
    /*
     * Open a verified TLS connection with the settings from the environment,
     * or return NULL if PGSSLROOTCERT is missing. libpq otherwise always
     * returns a connection object, which the caller must check with
     * PQstatus() and release with PQfinish(), even if the connection attempt
     * failed; the attempt fails if verification fails.
     */
    static PGconn *
    connect_to_server(void)
    {
        const char *values[sizeof(keywords) / sizeof(keywords[0])];
    
        if (!read_settings(values))
            return NULL;
        return PQconnectdbParams(keywords, values, 0);
    }
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
    def connection_is_encrypted(conn: psycopg.Connection) -> bool:
        """Asks the server whether this connection uses TLS."""
        # pg_stat_ssl has one row for each connection; pg_backend_pid()
        # identifies the one that belongs to this session. The version column
        # holds the protocol version, such as TLSv1.3.
        row = conn.execute(
            "SELECT ssl, version FROM pg_catalog.pg_stat_ssl "
            "WHERE pid = pg_backend_pid()"
        ).fetchone()
        return row[0]
    ```

=== "TypeScript"

    ```typescript
    // Asks the server whether this connection uses TLS.
    async function connectionIsEncrypted(client: pg.Client): Promise<boolean> {
      // pg_stat_ssl has one row for each connection; pg_backend_pid()
      // identifies the one that belongs to this session. The version column
      // holds the protocol version, such as TLSv1.3.
      const result = await client.query<{ ssl: boolean; version: string }>(
        "SELECT ssl, version FROM pg_catalog.pg_stat_ssl " +
          "WHERE pid = pg_backend_pid()",
      );
      return result.rows[0].ssl;
    }
    ```

=== "Java"

    ```java
    /** Asks the server whether this connection uses TLS. */
    static boolean connectionIsEncrypted(Connection conn)
            throws SQLException {
        // pg_stat_ssl has one row for each connection; pg_backend_pid()
        // identifies the one that belongs to this session. The version
        // column holds the protocol version, such as TLSv1.3.
        String sql = "SELECT ssl, version FROM pg_catalog.pg_stat_ssl "
                + "WHERE pid = pg_backend_pid()";
    
        // try-with-resources closes the statement and the result set when
        // each block exits, whether or not an error occurred.
        try (Statement stmt = conn.createStatement();
             ResultSet rs = stmt.executeQuery(sql)) {
            rs.next();
            return rs.getBoolean(1);
        }
    }
    ```

=== "C#"

    ```csharp
    // Asks the server whether this connection uses TLS.
    static async Task<bool> ConnectionIsEncryptedAsync(NpgsqlConnection conn)
    {
        // pg_stat_ssl has one row for each connection; pg_backend_pid()
        // identifies the one that belongs to this session. The version column
        // holds the protocol version, such as TLSv1.3.
        await using var cmd = new NpgsqlCommand(
            "SELECT ssl, version FROM pg_catalog.pg_stat_ssl " +
            "WHERE pid = pg_backend_pid()", conn);
        await using var reader = await cmd.ExecuteReaderAsync();
    
        // A boolean maps to bool.
        await reader.ReadAsync();
        return reader.GetBoolean(0);
    }
    ```

=== "Go"

    ```go
    // connectionIsEncrypted asks the server whether this connection uses TLS.
    func connectionIsEncrypted(ctx context.Context, conn *pgx.Conn) (bool, error) {
    	// pg_stat_ssl has one row for each connection; pg_backend_pid()
    	// identifies the one that belongs to this session. The version column
    	// holds the protocol version, such as TLSv1.3, and is NULL without
    	// TLS, so it scans into a pointer.
    	var ssl bool
    	var version *string
    	err := conn.QueryRow(ctx,
    		"SELECT ssl, version FROM pg_catalog.pg_stat_ssl "+
    			"WHERE pid = pg_backend_pid()",
    	).Scan(&ssl, &version)
    	if err != nil {
    		return false, fmt.Errorf("query failed: %w", err)
    	}
    	return ssl, nil
    }
    
    ```

=== "Rust"

    ```rust
    /// Asks the server whether this connection uses TLS.
    fn connection_is_encrypted(client: &mut Client) -> Result<bool, postgres::Error> {
        // pg_stat_ssl has one row for each connection; pg_backend_pid()
        // identifies the one that belongs to this session. The version column
        // holds the protocol version, such as TLSv1.3, and is NULL without
        // TLS, so it maps to an Option.
        let row = client.query_one(
            "SELECT ssl, version FROM pg_catalog.pg_stat_ssl \
             WHERE pid = pg_backend_pid()",
            &[],
        )?;
        let _version: Option<String> = row.get(1);
    
        // ssl is a boolean, which maps to bool.
        Ok(row.get(0))
    }
    ```

=== "Ruby"

    ```ruby
    # Asks the server whether this connection uses TLS.
    def connection_encrypted?(conn)
      # pg_stat_ssl has one row for each connection; pg_backend_pid()
      # identifies the one that belongs to this session. The version column
      # holds the protocol version, such as TLSv1.3.
      result = conn.exec(
        "SELECT ssl, version FROM pg_catalog.pg_stat_ssl " \
        "WHERE pid = pg_backend_pid()"
      )
    
      # Results arrive as strings; PostgreSQL writes a boolean as t or f.
      result.getvalue(0, 0) == "t"
    end
    ```

=== "C"

    ```c
    /*
     * Store in *encrypted whether the server reports this connection as using
     * TLS, and return true on success. On failure, PQerrorMessage() describes
     * the error.
     */
    static bool
    connection_is_encrypted(PGconn *conn, bool *encrypted)
    {
        /*
         * pg_stat_ssl has one row for each connection; pg_backend_pid()
         * identifies the one that belongs to this session. The version column
         * holds the protocol version, such as TLSv1.3.
         */
        PGresult *res = PQexec(conn,
                               "SELECT ssl, version FROM pg_catalog.pg_stat_ssl "
                               "WHERE pid = pg_backend_pid()");
        bool ok = PQresultStatus(res) == PGRES_TUPLES_OK && PQntuples(res) == 1;
    
        /* Results arrive as text; PostgreSQL writes a boolean as t or f. */
        if (ok)
            *encrypted = strcmp(PQgetvalue(res, 0, 0), "t") == 0;
    
        /* PQclear() frees the result, and accepts NULL. */
        PQclear(res);
        return ok;
    }
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
    def main() -> int:
        try:
            # The with block closes the connection when it exits, whether or
            # not an error occurred.
            with connect() as conn:
                encrypted = connection_is_encrypted(conn)
                print(f"Connection is encrypted: {str(encrypted).lower()}")
                # Reaching this line means that verify-full succeeded; a
                # certificate or host name mismatch raises an error instead.
                print("Server certificate verified: true")
        # psycopg.Error is the base class for every error the driver raises,
        # including connection and certificate verification failures.
        except (psycopg.Error, RuntimeError) as e:
            print(f"Database error: {e}", file=sys.stderr)
            return 1
    
        return 0
    
    
    if __name__ == "__main__":
        sys.exit(main())
    ```

=== "TypeScript"

    ```typescript
    // Returns a readable description of an error. When a host name resolves
    // to several addresses, Node reports a failure to reach all of them as an
    // AggregateError, whose own message is empty.
    function describe(err: unknown): string {
      if (err instanceof AggregateError) {
        return err.errors.map(describe).join("; ");
      }
      return err instanceof Error ? err.message : String(err);
    }
    
    async function main(): Promise<number> {
      let client: pg.Client | undefined;
      try {
        client = await connect();
        const encrypted = await connectionIsEncrypted(client);
        console.log(`Connection is encrypted: ${encrypted}`);
        // Reaching this line means that verification succeeded; a
        // certificate or host name mismatch rejects the promise instead.
        console.log("Server certificate verified: true");
        return 0;
      } catch (err) {
        // Connection, certificate, and server errors all arrive here as
        // rejected promises.
        console.error(`Database error: ${describe(err)}`);
        return 1;
      } finally {
        // The finally block runs whether or not an error occurred; client is
        // undefined if the connection attempt failed.
        await client?.end();
      }
    }
    
    process.exitCode = await main();
    ```

=== "Java"

    ```java
    public static void main(String[] args) {
        // try-with-resources closes the connection when the block exits,
        // whether or not an error occurred.
        try (Connection conn = connect()) {
            boolean encrypted = connectionIsEncrypted(conn);
            System.out.println("Connection is encrypted: " + encrypted);
            // Reaching this line means that verify-full succeeded; a
            // certificate or host name mismatch throws instead.
            System.out.println("Server certificate verified: true");
        // SQLException covers connection, certificate, and server errors;
        // IllegalStateException reports a missing PGSSLROOTCERT.
        } catch (SQLException | IllegalStateException e) {
            System.err.println("Database error: " + e.getMessage());
            System.exit(1);
        }
    }
    ```

=== "C#"

    ```csharp
    try
    {
        // await using disposes of the data source, and returns the connection
        // to the pool, when the block exits, whether or not an error occurred.
        await using var dataSource = CreateDataSource();
        await using var conn = await dataSource.OpenConnectionAsync();
    
        var encrypted = await ConnectionIsEncryptedAsync(conn);
        Console.WriteLine($"Connection is encrypted: {encrypted.ToString().ToLowerInvariant()}");
        // Reaching this line means that VerifyFull succeeded; a certificate
        // or host name mismatch throws instead.
        Console.WriteLine("Server certificate verified: true");
    }
    // NpgsqlException covers connection failures; PostgresException, which
    // derives from it, carries errors reported by the server.
    // InvalidOperationException reports a missing PGSSLROOTCERT.
    catch (Exception e) when (e is NpgsqlException or InvalidOperationException)
    {
        Console.Error.WriteLine($"Database error: {e.Message}");
        return 1;
    }
    
    return 0;
    ```

=== "Go"

    ```go
    // run connects, runs the query, and prints the result, returning any
    // error to the caller.
    func run(ctx context.Context) error {
    	conn, err := connect(ctx)
    	if err != nil {
    		return err
    	}
    	// The deferred call closes the connection when run() returns, whether
    	// or not an error occurred.
    	defer conn.Close(ctx)
    
    	encrypted, err := connectionIsEncrypted(ctx, conn)
    	if err != nil {
    		return err
    	}
    
    	fmt.Printf("Connection is encrypted: %t\n", encrypted)
    	// Reaching this line means that verify-full succeeded; a certificate
    	// or host name mismatch makes connect() return an error instead.
    	fmt.Println("Server certificate verified: true")
    	return nil
    }
    
    // main reports any error returned by run() and exits with a non-zero
    // status. Keeping the work in run() means that deferred cleanup always
    // happens before the program exits.
    func main() {
    	if err := run(context.Background()); err != nil {
    		fmt.Fprintf(os.Stderr, "Database error: %v\n", err)
    		os.Exit(1)
    	}
    }
    
    ```

=== "Rust"

    ```rust
    /// Connects, runs the query, and prints the result. The ? operator
    /// returns any error to the caller.
    fn run() -> Result<(), Box<dyn Error>> {
        let mut client = connect()?;
        let encrypted = connection_is_encrypted(&mut client)?;
        println!("Connection is encrypted: {encrypted}");
        // Reaching this line means that verification succeeded; a certificate
        // or host name mismatch makes connect() return an error instead.
        println!("Server certificate verified: true");
    
        // Dropping the client also closes the connection, including when ?
        // returns early, but close() lets us see any error that occurs while
        // doing so.
        client.close()?;
        Ok(())
    }
    
    /// Reports any error returned by run() and exits with a failure status.
    /// The top-level error is often generic ("error connecting to server"),
    /// so the chain of underlying causes is printed too.
    fn main() -> ExitCode {
        match run() {
            Ok(()) => ExitCode::SUCCESS,
            Err(e) => {
                eprintln!("Database error: {e}");
                let mut cause = e.source();
                while let Some(c) = cause {
                    eprintln!("  caused by: {c}");
                    cause = c.source();
                }
                ExitCode::FAILURE
            }
        }
    }
    ```

=== "Ruby"

    ```ruby
    begin
      conn = connect
      puts "Connection is encrypted: #{connection_encrypted?(conn)}"
      # Reaching this line means that verify-full succeeded; a certificate or
      # host name mismatch raises PG::ConnectionBad instead.
      puts "Server certificate verified: true"
    # PG::Error is the base class for every error the gem raises, including
    # connection failures and errors reported by the server.
    rescue PG::Error, ArgumentError => e
      warn "Database error: #{e.message}"
      exit 1
    # The ensure block runs whether or not an error occurred. conn is nil if
    # the connection attempt failed, hence the safe navigation operator.
    ensure
      conn&.close
    end
    ```

=== "C"

    ```c
    int
    main(void)
    {
        int status = EXIT_FAILURE;
        bool encrypted;
        PGconn *conn = connect_to_server();
    
        if (conn == NULL)
        {
            fprintf(stderr, "Database error: PGSSLROOTCERT must name the "
                            "root certificate\n");
            return status;
        }
    
        /* The || operator skips the query if the connection failed. */
        if (PQstatus(conn) != CONNECTION_OK ||
            !connection_is_encrypted(conn, &encrypted))
        {
            fprintf(stderr, "Database error: %s", PQerrorMessage(conn));
        }
        else
        {
            printf("Connection is encrypted: %s\n", encrypted ? "true" : "false");
            /*
             * Reaching this line means that verify-full succeeded; a
             * certificate or host name mismatch fails the connection instead.
             */
            printf("Server certificate verified: true\n");
            status = EXIT_SUCCESS;
        }
    
        /* Close the connection whether or not an error occurred. */
        PQfinish(conn);
        return status;
    }
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
    """
    Ellie's Postgres Cookbook
    Connecting to PostgreSQL over TLS with full verification, using psycopg 3.
    
    Copyright (c) 2026, pgEdge, Inc.
    This code is released under the PostgreSQL License.
    """
    
    import os
    import sys
    
    import psycopg
    
    
    def connection_settings() -> dict:
        """Reads the connection settings from the standard libpq environment
        variables, with defaults suitable for a local development server.
    
        The or operator treats an empty variable as unset, as libpq does, and
        a password of None is simply not sent. PGSSLROOTCERT has no default,
        because verification is meaningless without the certificate of the
        authority that signed the server certificate.
        """
        root_cert = os.environ.get("PGSSLROOTCERT")
        if not root_cert:
            raise RuntimeError("PGSSLROOTCERT must name the root certificate")
    
        return {
            "host": os.environ.get("PGHOST") or "localhost",
            "port": os.environ.get("PGPORT") or "5432",
            "dbname": os.environ.get("PGDATABASE") or "postgres",
            "user": os.environ.get("PGUSER") or "postgres",
            "password": os.environ.get("PGPASSWORD") or None,
            # verify-full checks that the certificate chains to the root
            # certificate and that it matches the host name. Weaker modes,
            # such as require, encrypt the connection without proving who is
            # on the other end.
            "sslmode": "verify-full",
            "sslrootcert": root_cert,
        }
    
    
    def connect() -> psycopg.Connection:
        """Opens a verified TLS connection with the settings from the
        environment. The connection fails if verification fails."""
        return psycopg.connect(**connection_settings())
    
    
    def connection_is_encrypted(conn: psycopg.Connection) -> bool:
        """Asks the server whether this connection uses TLS."""
        # pg_stat_ssl has one row for each connection; pg_backend_pid()
        # identifies the one that belongs to this session. The version column
        # holds the protocol version, such as TLSv1.3.
        row = conn.execute(
            "SELECT ssl, version FROM pg_catalog.pg_stat_ssl "
            "WHERE pid = pg_backend_pid()"
        ).fetchone()
        return row[0]
    
    
    def main() -> int:
        try:
            # The with block closes the connection when it exits, whether or
            # not an error occurred.
            with connect() as conn:
                encrypted = connection_is_encrypted(conn)
                print(f"Connection is encrypted: {str(encrypted).lower()}")
                # Reaching this line means that verify-full succeeded; a
                # certificate or host name mismatch raises an error instead.
                print("Server certificate verified: true")
        # psycopg.Error is the base class for every error the driver raises,
        # including connection and certificate verification failures.
        except (psycopg.Error, RuntimeError) as e:
            print(f"Database error: {e}", file=sys.stderr)
            return 1
    
        return 0
    
    
    if __name__ == "__main__":
        sys.exit(main())
    
    ```

=== "TypeScript"

    ```typescript
    /*
     * Ellie's Postgres Cookbook
     * Connecting to PostgreSQL over TLS with full verification, using
     * node-postgres.
     *
     * Copyright (c) 2026, pgEdge, Inc.
     * This code is released under the PostgreSQL License.
     */
    
    import { readFileSync } from "node:fs";
    
    import pg from "pg";
    
    // Read the connection settings from the standard libpq environment
    // variables, with defaults suitable for a local development server.
    // The || operator, unlike ??, also treats an empty variable as unset, as
    // libpq does.
    function connectionConfig(): pg.ClientConfig {
      // PGSSLROOTCERT has no default, because verification is meaningless
      // without the certificate of the authority that signed the server
      // certificate.
      const rootCert = process.env.PGSSLROOTCERT;
      if (!rootCert) {
        throw new Error("PGSSLROOTCERT must name the root certificate");
      }
    
      return {
        host: process.env.PGHOST || "localhost",
        port: Number(process.env.PGPORT || "5432"),
        database: process.env.PGDATABASE || "postgres",
        user: process.env.PGUSER || "postgres",
        password: process.env.PGPASSWORD || undefined,
        // Supplying the root certificate as ca makes Node trust only that
        // authority, and rejectUnauthorized makes Node reject a certificate
        // that does not chain to it or does not match the host name. Together
        // they are the equivalent of sslmode=verify-full.
        ssl: { ca: readFileSync(rootCert), rejectUnauthorized: true },
      };
    }
    
    // Opens a verified TLS connection with the settings from the
    // environment. The connection fails if verification fails.
    async function connect(): Promise<pg.Client> {
      const client = new pg.Client(connectionConfig());
      try {
        await client.connect();
      } catch (err) {
        // Release the client before passing the failure to the caller.
        await client.end();
        throw err;
      }
      return client;
    }
    
    // Asks the server whether this connection uses TLS.
    async function connectionIsEncrypted(client: pg.Client): Promise<boolean> {
      // pg_stat_ssl has one row for each connection; pg_backend_pid()
      // identifies the one that belongs to this session. The version column
      // holds the protocol version, such as TLSv1.3.
      const result = await client.query<{ ssl: boolean; version: string }>(
        "SELECT ssl, version FROM pg_catalog.pg_stat_ssl " +
          "WHERE pid = pg_backend_pid()",
      );
      return result.rows[0].ssl;
    }
    
    // Returns a readable description of an error. When a host name resolves
    // to several addresses, Node reports a failure to reach all of them as an
    // AggregateError, whose own message is empty.
    function describe(err: unknown): string {
      if (err instanceof AggregateError) {
        return err.errors.map(describe).join("; ");
      }
      return err instanceof Error ? err.message : String(err);
    }
    
    async function main(): Promise<number> {
      let client: pg.Client | undefined;
      try {
        client = await connect();
        const encrypted = await connectionIsEncrypted(client);
        console.log(`Connection is encrypted: ${encrypted}`);
        // Reaching this line means that verification succeeded; a
        // certificate or host name mismatch rejects the promise instead.
        console.log("Server certificate verified: true");
        return 0;
      } catch (err) {
        // Connection, certificate, and server errors all arrive here as
        // rejected promises.
        console.error(`Database error: ${describe(err)}`);
        return 1;
      } finally {
        // The finally block runs whether or not an error occurred; client is
        // undefined if the connection attempt failed.
        await client?.end();
      }
    }
    
    process.exitCode = await main();
    
    ```

=== "Java"

    ```java
    /*
     * Ellie's Postgres Cookbook
     * Connecting to PostgreSQL over TLS with full verification, using JDBC and
     * the PostgreSQL JDBC driver (pgJDBC).
     *
     * Copyright (c) 2026, pgEdge, Inc.
     * This code is released under the PostgreSQL License.
     */
    
    import java.sql.Connection;
    import java.sql.DriverManager;
    import java.sql.ResultSet;
    import java.sql.SQLException;
    import java.sql.Statement;
    import java.util.Properties;
    
    public class Main {
    
        /** Returns the value of an environment variable, or a fallback. */
        static String envOr(String name, String fallback) {
            String value = System.getenv(name);
            return (value != null && !value.isEmpty()) ? value : fallback;
        }
    
        /**
         * Returns the JDBC URL that identifies the server and database, built
         * from the standard libpq environment variables.
         */
        static String connectionUrl() {
            return "jdbc:postgresql://"
                    + envOr("PGHOST", "localhost") + ":"
                    + envOr("PGPORT", "5432") + "/"
                    + envOr("PGDATABASE", "postgres");
        }
    
        /**
         * Returns the user name, password, and TLS settings as connection
         * properties; the password is omitted if PGPASSWORD is unset or
         * empty. PGSSLROOTCERT has no default, because verification is
         * meaningless without the certificate of the authority that signed
         * the server certificate.
         */
        static Properties connectionProperties() {
            String rootCert = envOr("PGSSLROOTCERT", null);
            if (rootCert == null) {
                throw new IllegalStateException(
                        "PGSSLROOTCERT must name the root certificate");
            }
    
            Properties props = new Properties();
            props.setProperty("user", envOr("PGUSER", "postgres"));
            String password = envOr("PGPASSWORD", null);
            if (password != null) {
                props.setProperty("password", password);
            }
            // verify-full checks that the certificate chains to the root
            // certificate and that it matches the host name. Weaker modes,
            // such as require, encrypt the connection without proving who is
            // on the other end.
            props.setProperty("sslmode", "verify-full");
            props.setProperty("sslrootcert", rootCert);
            return props;
        }
    
        /**
         * Opens a verified TLS connection with the settings from the
         * environment. The connection fails if verification fails.
         */
        static Connection connect() throws SQLException {
            return DriverManager.getConnection(
                    connectionUrl(), connectionProperties());
        }
    
        /** Asks the server whether this connection uses TLS. */
        static boolean connectionIsEncrypted(Connection conn)
                throws SQLException {
            // pg_stat_ssl has one row for each connection; pg_backend_pid()
            // identifies the one that belongs to this session. The version
            // column holds the protocol version, such as TLSv1.3.
            String sql = "SELECT ssl, version FROM pg_catalog.pg_stat_ssl "
                    + "WHERE pid = pg_backend_pid()";
    
            // try-with-resources closes the statement and the result set when
            // each block exits, whether or not an error occurred.
            try (Statement stmt = conn.createStatement();
                 ResultSet rs = stmt.executeQuery(sql)) {
                rs.next();
                return rs.getBoolean(1);
            }
        }
    
        public static void main(String[] args) {
            // try-with-resources closes the connection when the block exits,
            // whether or not an error occurred.
            try (Connection conn = connect()) {
                boolean encrypted = connectionIsEncrypted(conn);
                System.out.println("Connection is encrypted: " + encrypted);
                // Reaching this line means that verify-full succeeded; a
                // certificate or host name mismatch throws instead.
                System.out.println("Server certificate verified: true");
            // SQLException covers connection, certificate, and server errors;
            // IllegalStateException reports a missing PGSSLROOTCERT.
            } catch (SQLException | IllegalStateException e) {
                System.err.println("Database error: " + e.getMessage());
                System.exit(1);
            }
        }
    }
    
    ```

=== "C#"

    ```csharp
    /*
     * Ellie's Postgres Cookbook
     * Connecting to PostgreSQL over TLS with full verification, using Npgsql.
     *
     * Copyright (c) 2026, pgEdge, Inc.
     * This code is released under the PostgreSQL License.
     */
    
    using Npgsql;
    
    // Returns the value of an environment variable, or null if the variable
    // is unset or empty; libpq also treats an empty variable as unset.
    static string? EnvValue(string name) =>
        Environment.GetEnvironmentVariable(name) is { Length: > 0 } value
            ? value
            : null;
    
    // Returns the value of an environment variable, or a fallback if unset.
    static string EnvOr(string name, string fallback) =>
        EnvValue(name) ?? fallback;
    
    // Builds a connection string from the standard libpq environment
    // variables, with defaults suitable for a local development server. The
    // builder takes care of quoting any special characters. PGSSLROOTCERT has
    // no default, because verification is meaningless without the certificate
    // of the authority that signed the server certificate.
    static string ConnectionString() =>
        new NpgsqlConnectionStringBuilder
        {
            Host = EnvOr("PGHOST", "localhost"),
            Port = int.Parse(EnvOr("PGPORT", "5432")),
            Database = EnvOr("PGDATABASE", "postgres"),
            Username = EnvOr("PGUSER", "postgres"),
            Password = EnvValue("PGPASSWORD"),
            // VerifyFull checks that the certificate chains to the root
            // certificate and that it matches the host name. Weaker modes,
            // such as Require, encrypt the connection without proving who is
            // on the other end.
            SslMode = SslMode.VerifyFull,
            RootCertificate = EnvValue("PGSSLROOTCERT")
                ?? throw new InvalidOperationException(
                    "PGSSLROOTCERT must name the root certificate"),
        }.ConnectionString;
    
    // Creates a data source with the settings from the environment. A data
    // source manages a pool of physical connections, and each call to
    // OpenConnectionAsync borrows one from the pool; the connection fails if
    // verification fails.
    static NpgsqlDataSource CreateDataSource() =>
        NpgsqlDataSource.Create(ConnectionString());
    
    // Asks the server whether this connection uses TLS.
    static async Task<bool> ConnectionIsEncryptedAsync(NpgsqlConnection conn)
    {
        // pg_stat_ssl has one row for each connection; pg_backend_pid()
        // identifies the one that belongs to this session. The version column
        // holds the protocol version, such as TLSv1.3.
        await using var cmd = new NpgsqlCommand(
            "SELECT ssl, version FROM pg_catalog.pg_stat_ssl " +
            "WHERE pid = pg_backend_pid()", conn);
        await using var reader = await cmd.ExecuteReaderAsync();
    
        // A boolean maps to bool.
        await reader.ReadAsync();
        return reader.GetBoolean(0);
    }
    
    try
    {
        // await using disposes of the data source, and returns the connection
        // to the pool, when the block exits, whether or not an error occurred.
        await using var dataSource = CreateDataSource();
        await using var conn = await dataSource.OpenConnectionAsync();
    
        var encrypted = await ConnectionIsEncryptedAsync(conn);
        Console.WriteLine($"Connection is encrypted: {encrypted.ToString().ToLowerInvariant()}");
        // Reaching this line means that VerifyFull succeeded; a certificate
        // or host name mismatch throws instead.
        Console.WriteLine("Server certificate verified: true");
    }
    // NpgsqlException covers connection failures; PostgresException, which
    // derives from it, carries errors reported by the server.
    // InvalidOperationException reports a missing PGSSLROOTCERT.
    catch (Exception e) when (e is NpgsqlException or InvalidOperationException)
    {
        Console.Error.WriteLine($"Database error: {e.Message}");
        return 1;
    }
    
    return 0;
    
    ```

=== "Go"

    ```go
    // Ellie's Postgres Cookbook
    // Connecting to PostgreSQL over TLS with full verification, using pgx.
    //
    // Copyright (c) 2026, pgEdge, Inc.
    // This code is released under the PostgreSQL License.
    
    package main
    
    import (
    	"context"
    	"errors"
    	"fmt"
    	"net"
    	"net/url"
    	"os"
    
    	"github.com/jackc/pgx/v5"
    )
    
    
    // envOr returns the value of an environment variable, or a fallback if
    // the variable is unset or empty.
    func envOr(name, fallback string) string {
    	if value := os.Getenv(name); value != "" {
    		return value
    	}
    	return fallback
    }
    
    // connString builds a postgres:// URL from the standard libpq environment
    // variables. net/url takes care of escaping any special characters in
    // the user name, password, or database name. PGSSLROOTCERT has no
    // default, because verification is meaningless without the certificate
    // of the authority that signed the server certificate.
    func connString() (string, error) {
    	rootCert := os.Getenv("PGSSLROOTCERT")
    	if rootCert == "" {
    		return "", errors.New("PGSSLROOTCERT must name the root certificate")
    	}
    
    	u := url.URL{
    		Scheme: "postgres",
    		Host:   net.JoinHostPort(envOr("PGHOST", "localhost"), envOr("PGPORT", "5432")),
    		Path:   "/" + envOr("PGDATABASE", "postgres"),
    		// verify-full checks that the certificate chains to the root
    		// certificate and that it matches the host name. Weaker modes,
    		// such as require, encrypt the connection without proving who
    		// is on the other end.
    		RawQuery: url.Values{
    			"sslmode":     {"verify-full"},
    			"sslrootcert": {rootCert},
    		}.Encode(),
    	}
    	if password := os.Getenv("PGPASSWORD"); password != "" {
    		u.User = url.UserPassword(envOr("PGUSER", "postgres"), password)
    	} else {
    		u.User = url.User(envOr("PGUSER", "postgres"))
    	}
    	return u.String(), nil
    }
    
    
    // connect opens a verified TLS connection with the settings from the
    // environment. The connection fails if verification fails.
    func connect(ctx context.Context) (*pgx.Conn, error) {
    	dsn, err := connString()
    	if err != nil {
    		return nil, err
    	}
    	conn, err := pgx.Connect(ctx, dsn)
    	if err != nil {
    		return nil, fmt.Errorf("connection failed: %w", err)
    	}
    	return conn, nil
    }
    
    
    // connectionIsEncrypted asks the server whether this connection uses TLS.
    func connectionIsEncrypted(ctx context.Context, conn *pgx.Conn) (bool, error) {
    	// pg_stat_ssl has one row for each connection; pg_backend_pid()
    	// identifies the one that belongs to this session. The version column
    	// holds the protocol version, such as TLSv1.3, and is NULL without
    	// TLS, so it scans into a pointer.
    	var ssl bool
    	var version *string
    	err := conn.QueryRow(ctx,
    		"SELECT ssl, version FROM pg_catalog.pg_stat_ssl "+
    			"WHERE pid = pg_backend_pid()",
    	).Scan(&ssl, &version)
    	if err != nil {
    		return false, fmt.Errorf("query failed: %w", err)
    	}
    	return ssl, nil
    }
    
    
    // run connects, runs the query, and prints the result, returning any
    // error to the caller.
    func run(ctx context.Context) error {
    	conn, err := connect(ctx)
    	if err != nil {
    		return err
    	}
    	// The deferred call closes the connection when run() returns, whether
    	// or not an error occurred.
    	defer conn.Close(ctx)
    
    	encrypted, err := connectionIsEncrypted(ctx, conn)
    	if err != nil {
    		return err
    	}
    
    	fmt.Printf("Connection is encrypted: %t\n", encrypted)
    	// Reaching this line means that verify-full succeeded; a certificate
    	// or host name mismatch makes connect() return an error instead.
    	fmt.Println("Server certificate verified: true")
    	return nil
    }
    
    // main reports any error returned by run() and exits with a non-zero
    // status. Keeping the work in run() means that deferred cleanup always
    // happens before the program exits.
    func main() {
    	if err := run(context.Background()); err != nil {
    		fmt.Fprintf(os.Stderr, "Database error: %v\n", err)
    		os.Exit(1)
    	}
    }
    
    
    ```

=== "Rust"

    ```rust
    // Ellie's Postgres Cookbook
    // Connecting to PostgreSQL over TLS with full verification, using the
    // postgres and postgres-openssl crates.
    //
    // Copyright (c) 2026, pgEdge, Inc.
    // This code is released under the PostgreSQL License.
    
    use std::env;
    use std::error::Error;
    use std::process::ExitCode;
    
    use openssl::ssl::{SslConnector, SslMethod};
    use openssl::x509::store::X509StoreBuilder;
    use openssl::x509::X509;
    use postgres::config::SslMode;
    use postgres::{Client, Config};
    use postgres_openssl::MakeTlsConnector;
    
    /// Returns the value of an environment variable, if it is set and not
    /// empty; libpq also treats an empty variable as unset.
    fn env_value(name: &str) -> Option<String> {
        env::var(name).ok().filter(|value| !value.is_empty())
    }
    
    /// Returns the value of an environment variable, or a fallback if the
    /// variable is unset or empty.
    fn env_or(name: &str, fallback: &str) -> String {
        env_value(name).unwrap_or_else(|| fallback.to_string())
    }
    
    /// Builds the connection configuration from the standard libpq
    /// environment variables, with defaults suitable for a local server.
    /// The default SSL mode of the crate is Prefer, which falls back to a
    /// plain connection if the server declines TLS, so Require is set
    /// explicitly. Require makes the connection fail instead; the TLS
    /// connector built below then verifies the certificate.
    fn config() -> Config {
        let mut config = Config::new();
        config
            .ssl_mode(SslMode::Require)
            .host(&env_or("PGHOST", "localhost"))
            .port(env_or("PGPORT", "5432").parse().expect("PGPORT must be a number"))
            .dbname(&env_or("PGDATABASE", "postgres"))
            .user(&env_or("PGUSER", "postgres"));
        if let Some(password) = env_value("PGPASSWORD") {
            config.password(&password);
        }
        config
    }
    
    /// Returns the path of the root certificate file. PGSSLROOTCERT has no
    /// default, because verification is meaningless without the certificate
    /// of the authority that signed the server certificate.
    fn root_cert_path() -> Result<String, Box<dyn Error>> {
        env_value("PGSSLROOTCERT").ok_or_else(|| "PGSSLROOTCERT must name the root certificate".into())
    }
    
    /// Builds a TLS connector that trusts only the given root certificate.
    /// SslConnector::builder starts with the system root certificates, so the
    /// certificate store is replaced with one that holds nothing but the
    /// certificates in the file; otherwise any publicly trusted certificate
    /// for the host name would also be accepted. The connector verifies the
    /// certificate chain and the host name by default, which together are the
    /// equivalent of sslmode=verify-full; the host name checked is the one in
    /// the Config.
    fn tls_connector(root_cert: &str) -> Result<MakeTlsConnector, Box<dyn Error>> {
        let mut store = X509StoreBuilder::new()?;
        for cert in X509::stack_from_pem(&std::fs::read(root_cert)?)? {
            store.add_cert(cert)?;
        }
    
        let mut builder = SslConnector::builder(SslMethod::tls())?;
        builder.set_cert_store(store.build());
        Ok(MakeTlsConnector::new(builder.build()))
    }
    
    /// Opens a verified TLS connection with the settings from the
    /// environment. The connection fails if verification fails.
    fn connect() -> Result<Client, Box<dyn Error>> {
        let tls = tls_connector(&root_cert_path()?)?;
        Ok(config().connect(tls)?)
    }
    
    /// Asks the server whether this connection uses TLS.
    fn connection_is_encrypted(client: &mut Client) -> Result<bool, postgres::Error> {
        // pg_stat_ssl has one row for each connection; pg_backend_pid()
        // identifies the one that belongs to this session. The version column
        // holds the protocol version, such as TLSv1.3, and is NULL without
        // TLS, so it maps to an Option.
        let row = client.query_one(
            "SELECT ssl, version FROM pg_catalog.pg_stat_ssl \
             WHERE pid = pg_backend_pid()",
            &[],
        )?;
        let _version: Option<String> = row.get(1);
    
        // ssl is a boolean, which maps to bool.
        Ok(row.get(0))
    }
    
    /// Connects, runs the query, and prints the result. The ? operator
    /// returns any error to the caller.
    fn run() -> Result<(), Box<dyn Error>> {
        let mut client = connect()?;
        let encrypted = connection_is_encrypted(&mut client)?;
        println!("Connection is encrypted: {encrypted}");
        // Reaching this line means that verification succeeded; a certificate
        // or host name mismatch makes connect() return an error instead.
        println!("Server certificate verified: true");
    
        // Dropping the client also closes the connection, including when ?
        // returns early, but close() lets us see any error that occurs while
        // doing so.
        client.close()?;
        Ok(())
    }
    
    /// Reports any error returned by run() and exits with a failure status.
    /// The top-level error is often generic ("error connecting to server"),
    /// so the chain of underlying causes is printed too.
    fn main() -> ExitCode {
        match run() {
            Ok(()) => ExitCode::SUCCESS,
            Err(e) => {
                eprintln!("Database error: {e}");
                let mut cause = e.source();
                while let Some(c) = cause {
                    eprintln!("  caused by: {c}");
                    cause = c.source();
                }
                ExitCode::FAILURE
            }
        }
    }
    
    ```

=== "Ruby"

    ```ruby
    # Ellie's Postgres Cookbook
    # Connecting to PostgreSQL over TLS with full verification, using the pg
    # gem.
    #
    # Copyright (c) 2026, pgEdge, Inc.
    # This code is released under the PostgreSQL License.
    
    require "pg"
    
    # Returns the value of an environment variable, or a fallback if the
    # variable is unset or empty; libpq also treats an empty variable as unset.
    def env_or(name, fallback)
      value = ENV[name]
      value.nil? || value.empty? ? fallback : value
    end
    
    # Returns the connection settings from the standard libpq environment
    # variables, with defaults suitable for a local development server.
    # compact removes the password if PGPASSWORD is not set.
    def connection_params
      # PGSSLROOTCERT has no default, because verification is meaningless
      # without the certificate of the authority that signed the server
      # certificate.
      root_cert = env_or("PGSSLROOTCERT", nil)
      raise ArgumentError, "PGSSLROOTCERT must name the root certificate" unless root_cert
    
      {
        host: env_or("PGHOST", "localhost"),
        port: env_or("PGPORT", "5432"),
        dbname: env_or("PGDATABASE", "postgres"),
        user: env_or("PGUSER", "postgres"),
        password: env_or("PGPASSWORD", nil),
        # verify-full checks that the certificate chains to the root
        # certificate and that it matches the host name. Weaker modes, such
        # as require, encrypt the connection without proving who is on the
        # other end.
        sslmode: "verify-full",
        sslrootcert: root_cert
      }.compact
    end
    
    # Opens a verified TLS connection with the settings from the environment.
    # The connection fails if verification fails.
    def connect
      PG.connect(connection_params)
    end
    
    # Asks the server whether this connection uses TLS.
    def connection_encrypted?(conn)
      # pg_stat_ssl has one row for each connection; pg_backend_pid()
      # identifies the one that belongs to this session. The version column
      # holds the protocol version, such as TLSv1.3.
      result = conn.exec(
        "SELECT ssl, version FROM pg_catalog.pg_stat_ssl " \
        "WHERE pid = pg_backend_pid()"
      )
    
      # Results arrive as strings; PostgreSQL writes a boolean as t or f.
      result.getvalue(0, 0) == "t"
    end
    
    begin
      conn = connect
      puts "Connection is encrypted: #{connection_encrypted?(conn)}"
      # Reaching this line means that verify-full succeeded; a certificate or
      # host name mismatch raises PG::ConnectionBad instead.
      puts "Server certificate verified: true"
    # PG::Error is the base class for every error the gem raises, including
    # connection failures and errors reported by the server.
    rescue PG::Error, ArgumentError => e
      warn "Database error: #{e.message}"
      exit 1
    # The ensure block runs whether or not an error occurred. conn is nil if
    # the connection attempt failed, hence the safe navigation operator.
    ensure
      conn&.close
    end
    
    ```

=== "C"

    ```c
    /*
     * Ellie's Postgres Cookbook
     * Connecting to PostgreSQL over TLS with full verification, using libpq.
     *
     * Copyright (c) 2026, pgEdge, Inc.
     * This code is released under the PostgreSQL License.
     */
    
    #include <stdbool.h>
    #include <stdio.h>
    #include <stdlib.h>
    #include <string.h>
    
    #include <libpq-fe.h>
    
    /* Return the value of an environment variable, or a fallback if unset. */
    static const char *
    env_or(const char *name, const char *fallback)
    {
        const char *value = getenv(name);
    
        return (value != NULL && value[0] != '\0') ? value : fallback;
    }
    
    /*
     * Connection parameters are passed to libpq as two parallel,
     * NULL-terminated arrays of keywords and values. A NULL value is ignored,
     * so the password is only sent if PGPASSWORD is set.
     */
    static const char *const keywords[] = {
        "host", "port", "dbname", "user", "password",
        "sslmode", "sslrootcert", NULL
    };
    
    /*
     * Fill in the value for each keyword from the environment, and return
     * false if PGSSLROOTCERT is missing. It has no default, because
     * verification is meaningless without the certificate of the authority
     * that signed the server certificate.
     */
    static bool
    read_settings(const char *values[])
    {
        values[0] = env_or("PGHOST", "localhost");
        values[1] = env_or("PGPORT", "5432");
        values[2] = env_or("PGDATABASE", "postgres");
        values[3] = env_or("PGUSER", "postgres");
        values[4] = env_or("PGPASSWORD", NULL);
    
        /*
         * verify-full checks that the certificate chains to the root
         * certificate and that it matches the host name. Weaker modes, such
         * as require, encrypt the connection without proving who is on the
         * other end.
         */
        values[5] = "verify-full";
        values[6] = env_or("PGSSLROOTCERT", NULL);
        values[7] = NULL;
        return values[6] != NULL;
    }
    
    /*
     * Open a verified TLS connection with the settings from the environment,
     * or return NULL if PGSSLROOTCERT is missing. libpq otherwise always
     * returns a connection object, which the caller must check with
     * PQstatus() and release with PQfinish(), even if the connection attempt
     * failed; the attempt fails if verification fails.
     */
    static PGconn *
    connect_to_server(void)
    {
        const char *values[sizeof(keywords) / sizeof(keywords[0])];
    
        if (!read_settings(values))
            return NULL;
        return PQconnectdbParams(keywords, values, 0);
    }
    
    /*
     * Store in *encrypted whether the server reports this connection as using
     * TLS, and return true on success. On failure, PQerrorMessage() describes
     * the error.
     */
    static bool
    connection_is_encrypted(PGconn *conn, bool *encrypted)
    {
        /*
         * pg_stat_ssl has one row for each connection; pg_backend_pid()
         * identifies the one that belongs to this session. The version column
         * holds the protocol version, such as TLSv1.3.
         */
        PGresult *res = PQexec(conn,
                               "SELECT ssl, version FROM pg_catalog.pg_stat_ssl "
                               "WHERE pid = pg_backend_pid()");
        bool ok = PQresultStatus(res) == PGRES_TUPLES_OK && PQntuples(res) == 1;
    
        /* Results arrive as text; PostgreSQL writes a boolean as t or f. */
        if (ok)
            *encrypted = strcmp(PQgetvalue(res, 0, 0), "t") == 0;
    
        /* PQclear() frees the result, and accepts NULL. */
        PQclear(res);
        return ok;
    }
    
    int
    main(void)
    {
        int status = EXIT_FAILURE;
        bool encrypted;
        PGconn *conn = connect_to_server();
    
        if (conn == NULL)
        {
            fprintf(stderr, "Database error: PGSSLROOTCERT must name the "
                            "root certificate\n");
            return status;
        }
    
        /* The || operator skips the query if the connection failed. */
        if (PQstatus(conn) != CONNECTION_OK ||
            !connection_is_encrypted(conn, &encrypted))
        {
            fprintf(stderr, "Database error: %s", PQerrorMessage(conn));
        }
        else
        {
            printf("Connection is encrypted: %s\n", encrypted ? "true" : "false");
            /*
             * Reaching this line means that verify-full succeeded; a
             * certificate or host name mismatch fails the connection instead.
             */
            printf("Server certificate verified: true\n");
            status = EXIT_SUCCESS;
        }
    
        /* Close the connection whether or not an error occurred. */
        PQfinish(conn);
        return status;
    }
    
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
