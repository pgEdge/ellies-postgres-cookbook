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
    # psycopg 3, with the pre-built binary package that bundles libpq.
    psycopg[binary]>=3.2,<4
    ```

=== "TypeScript"

    ```json
    {
      "name": "retry-transactions",
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
library modules that the program uses. The following tabs show the imports
for each language:

=== "Python"

    ```python
    import os
    import sys
    import time
    
    import psycopg
    ```

=== "TypeScript"

    ```typescript
    import { setTimeout as sleep } from "node:timers/promises";
    
    import pg from "pg";
    ```

=== "Java"

    ```java
    import java.sql.Connection;
    import java.sql.DriverManager;
    import java.sql.PreparedStatement;
    import java.sql.ResultSet;
    import java.sql.SQLException;
    import java.sql.Statement;
    import java.util.Properties;
    import java.util.Set;
    ```

=== "C#"

    ```csharp
    using System.Data;
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
    	"time"
    
    	"github.com/jackc/pgx/v5"
    	"github.com/jackc/pgx/v5/pgconn"
    )
    
    ```

=== "Rust"

    ```rust
    use std::env;
    use std::error::Error;
    use std::process::ExitCode;
    use std::thread::sleep;
    use std::time::Duration;
    
    use postgres::error::SqlState;
    use postgres::{Client, Config, IsolationLevel, NoTls, Transaction};
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
    #include <time.h>
    
    #include <libpq-fe.h>
    ```

## Configuring the Connection

The examples read their connection settings from the same environment
variables that libpq and `psql` use, and treat an empty variable as unset,
as the [first recipe](connect_and_query.md) describes. This step also
defines the two SQLSTATE codes that trigger a retry, and the maximum number
of attempts. The following tabs show the configuration for each language:

=== "Python"

    ```python
    # The SQLSTATE codes that mean "run the transaction again": 40001 is a
    # serialisation failure and 40P01 is a deadlock.
    RETRYABLE = {"40001", "40P01"}
    MAX_ATTEMPTS = 5
    
    
    def connection_settings() -> dict:
        """Reads the connection settings from the standard libpq environment
        variables, with defaults suitable for a local development server.
    
        The or operator treats an empty variable as unset, as libpq does, and
        a password of None is simply not sent.
        """
        return {
            "host": os.environ.get("PGHOST") or "localhost",
            "port": os.environ.get("PGPORT") or "5432",
            "dbname": os.environ.get("PGDATABASE") or "postgres",
            "user": os.environ.get("PGUSER") or "postgres",
            "password": os.environ.get("PGPASSWORD") or None,
        }
    ```

=== "TypeScript"

    ```typescript
    // The SQLSTATE codes that mean "run the transaction again": 40001 is a
    // serialisation failure and 40P01 is a deadlock.
    const RETRYABLE = new Set(["40001", "40P01"]);
    const MAX_ATTEMPTS = 5;
    
    // Read the connection settings from the standard libpq environment
    // variables, with defaults suitable for a local development server.
    // The || operator, unlike ??, also treats an empty variable as unset, as
    // libpq does.
    const config: pg.ClientConfig = {
      host: process.env.PGHOST || "localhost",
      port: Number(process.env.PGPORT || "5432"),
      database: process.env.PGDATABASE || "postgres",
      user: process.env.PGUSER || "postgres",
      password: process.env.PGPASSWORD || undefined,
    };
    ```

=== "Java"

    ```java
    /**
     * The SQLSTATE codes that mean "run the transaction again": 40001 is
     * a serialisation failure and 40P01 is a deadlock.
     */
    static final Set<String> RETRYABLE = Set.of("40001", "40P01");
    static final int MAX_ATTEMPTS = 5;
    
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
     * Returns the user name and password as connection properties; the
     * password is omitted if PGPASSWORD is unset or empty.
     */
    static Properties connectionProperties() {
        Properties props = new Properties();
        props.setProperty("user", envOr("PGUSER", "postgres"));
        String password = envOr("PGPASSWORD", null);
        if (password != null) {
            props.setProperty("password", password);
        }
        return props;
    }
    ```

=== "C#"

    ```csharp
    const int MaxAttempts = 5;
    
    // Returns true if a SQLSTATE code means "run the transaction again": 40001
    // is a serialisation failure and 40P01 is a deadlock.
    static bool IsRetryable(string? sqlState) => sqlState is "40001" or "40P01";
    
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
    // builder takes care of quoting any special characters.
    static string ConnectionString() =>
        new NpgsqlConnectionStringBuilder
        {
            Host = EnvOr("PGHOST", "localhost"),
            Port = int.Parse(EnvOr("PGPORT", "5432")),
            Database = EnvOr("PGDATABASE", "postgres"),
            Username = EnvOr("PGUSER", "postgres"),
            Password = EnvValue("PGPASSWORD"),
        }.ConnectionString;
    ```

=== "Go"

    ```go
    // maxAttempts is the number of times the transaction runs before the
    // program gives up.
    const maxAttempts = 5
    
    // isRetryable reports whether err carries a SQLSTATE code that means "run
    // the transaction again": 40001 is a serialisation failure and 40P01 is a
    // deadlock.
    func isRetryable(err error) bool {
    	var pgErr *pgconn.PgError
    	return errors.As(err, &pgErr) &&
    		(pgErr.Code == "40001" || pgErr.Code == "40P01")
    }
    
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
    // the user name, password, or database name.
    func connString() string {
    	u := url.URL{
    		Scheme: "postgres",
    		Host:   net.JoinHostPort(envOr("PGHOST", "localhost"), envOr("PGPORT", "5432")),
    		Path:   "/" + envOr("PGDATABASE", "postgres"),
    	}
    	if password := os.Getenv("PGPASSWORD"); password != "" {
    		u.User = url.UserPassword(envOr("PGUSER", "postgres"), password)
    	} else {
    		u.User = url.User(envOr("PGUSER", "postgres"))
    	}
    	return u.String()
    }
    
    ```

=== "Rust"

    ```rust
    const MAX_ATTEMPTS: u32 = 5;
    
    /// Returns true if the error carries a SQLSTATE code that means "run the
    /// transaction again": a serialisation failure or a deadlock.
    fn is_retryable(error: &postgres::Error) -> bool {
        matches!(
            error.code(),
            Some(code) if *code == SqlState::T_R_SERIALIZATION_FAILURE
                || *code == SqlState::T_R_DEADLOCK_DETECTED
        )
    }
    
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
    fn config() -> Config {
        let mut config = Config::new();
        config
            .host(&env_or("PGHOST", "localhost"))
            .port(env_or("PGPORT", "5432").parse().expect("PGPORT must be a number"))
            .dbname(&env_or("PGDATABASE", "postgres"))
            .user(&env_or("PGUSER", "postgres"));
        if let Some(password) = env_value("PGPASSWORD") {
            config.password(&password);
        }
        config
    }
    ```

=== "Ruby"

    ```ruby
    # The SQLSTATE codes that mean "run the transaction again": 40001 is a
    # serialisation failure and 40P01 is a deadlock.
    RETRYABLE = %w[40001 40P01].freeze
    MAX_ATTEMPTS = 5
    
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
      {
        host: env_or("PGHOST", "localhost"),
        port: env_or("PGPORT", "5432"),
        dbname: env_or("PGDATABASE", "postgres"),
        user: env_or("PGUSER", "postgres"),
        password: env_or("PGPASSWORD", nil)
      }.compact
    end
    ```

=== "C"

    ```c
    #define MAX_ATTEMPTS 5
    
    /*
     * Return true if a SQLSTATE code means "run the transaction again": 40001
     * is a serialisation failure and 40P01 is a deadlock.
     */
    static bool
    is_retryable(const char *sqlstate)
    {
        return strcmp(sqlstate, "40001") == 0 || strcmp(sqlstate, "40P01") == 0;
    }
    
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
        "host", "port", "dbname", "user", "password", NULL
    };
    
    /* Fill in the value for each keyword from the environment. */
    static void
    read_settings(const char *values[])
    {
        values[0] = env_or("PGHOST", "localhost");
        values[1] = env_or("PGPORT", "5432");
        values[2] = env_or("PGDATABASE", "postgres");
        values[3] = env_or("PGUSER", "postgres");
        values[4] = env_or("PGPASSWORD", NULL);
        values[5] = NULL;
    }
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
    def connect() -> psycopg.Connection:
        """Opens a connection with the settings from the environment.
    
        Autocommit mode means that the program, rather than the driver,
        decides where each transaction begins and ends.
        """
        return psycopg.connect(**connection_settings(), autocommit=True)
    ```

=== "TypeScript"

    ```typescript
    // Opens a connection with the settings from the environment. The driver
    // runs each statement in its own transaction unless the program sends
    // BEGIN, so the program decides where each transaction starts and ends.
    async function connect(): Promise<pg.Client> {
      const client = new pg.Client(config);
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
     * Opens a connection with the settings from the environment. The
     * connection starts in autocommit mode, where each statement is its
     * own transaction.
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
    // OpenConnectionAsync borrows one from the pool, which also gives the
    // program a second connection when it needs one. A connection runs each
    // statement in its own transaction unless the program begins one.
    static NpgsqlDataSource CreateDataSource() =>
        NpgsqlDataSource.Create(ConnectionString());
    ```

=== "Go"

    ```go
    // connect opens a connection with the settings from the environment.
    func connect(ctx context.Context) (*pgx.Conn, error) {
    	conn, err := pgx.Connect(ctx, connString())
    	if err != nil {
    		return nil, fmt.Errorf("connection failed: %w", err)
    	}
    	return conn, nil
    }
    
    ```

=== "Rust"

    ```rust
    /// Opens a connection with the settings from the environment. NoTls
    /// disables TLS, which keeps this example free of certificate set-up;
    /// connections over an untrusted network should use TLS. The server runs
    /// each statement in its own transaction unless the program begins one, so
    /// the program decides where each transaction starts and ends.
    fn connect() -> Result<Client, postgres::Error> {
        config().connect(NoTls)
    }
    ```

=== "Ruby"

    ```ruby
    # Opens a connection with the settings from the environment. The server
    # runs each statement in its own transaction unless the program sends
    # BEGIN, so the program decides where each transaction starts and ends.
    def connect
      PG.connect(connection_params)
    end
    ```

=== "C"

    ```c
    /*
     * Open a connection with the settings from the environment. libpq always
     * returns a connection object, which the caller must check with PQstatus()
     * and release with PQfinish(), even if the connection attempt failed. The
     * server runs each statement in its own transaction unless the program
     * sends BEGIN, so the program decides where each transaction starts and
     * ends.
     */
    static PGconn *
    connect_to_server(void)
    {
        const char *values[sizeof(keywords) / sizeof(keywords[0])];
    
        read_settings(values);
        return PQconnectdbParams(keywords, values, 0);
    }
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
    def create_table(conn: psycopg.Connection) -> None:
        """Creates the shared counter table, with a single row set to zero.
    
        The table must be visible to a second connection, so it cannot be
        temporary; the name is specific to this recipe, and any earlier copy
        is dropped first.
        """
        drop_table(conn)
        conn.execute(
            "CREATE TABLE cookbook_retry_transactions "
            "(id int PRIMARY KEY, value int NOT NULL)"
        )
        conn.execute(
            "INSERT INTO cookbook_retry_transactions (id, value) VALUES (%s, %s)",
            (1, 0),
        )
    
    
    def drop_table(conn: psycopg.Connection) -> None:
        """Drops the shared counter table if it exists."""
        conn.execute("DROP TABLE IF EXISTS cookbook_retry_transactions")
    ```

=== "TypeScript"

    ```typescript
    // Drops the shared counter table if it exists.
    async function dropTable(client: pg.Client): Promise<void> {
      await client.query("DROP TABLE IF EXISTS cookbook_retry_transactions");
    }
    
    // Creates the shared counter table, with a single row set to zero. The
    // table must be visible to a second connection, so it cannot be
    // temporary; the name is specific to this recipe, and any earlier copy is
    // dropped first.
    async function createTable(client: pg.Client): Promise<void> {
      await dropTable(client);
      await client.query(
        "CREATE TABLE cookbook_retry_transactions " +
          "(id int PRIMARY KEY, value int NOT NULL)",
      );
      await client.query(
        "INSERT INTO cookbook_retry_transactions (id, value) VALUES ($1, $2)",
        [1, 0],
      );
    }
    ```

=== "Java"

    ```java
    /** Drops the shared counter table if it exists. */
    static void dropTable(Connection conn) throws SQLException {
        try (Statement stmt = conn.createStatement()) {
            stmt.execute("DROP TABLE IF EXISTS cookbook_retry_transactions");
        }
    }
    
    /**
     * Creates the shared counter table, with a single row set to zero.
     * The table must be visible to a second connection, so it cannot be
     * temporary; the name is specific to this recipe, and any earlier
     * copy is dropped first.
     */
    static void createTable(Connection conn) throws SQLException {
        dropTable(conn);
        try (Statement stmt = conn.createStatement()) {
            stmt.execute("CREATE TABLE cookbook_retry_transactions "
                    + "(id int PRIMARY KEY, value int NOT NULL)");
        }
        try (PreparedStatement stmt = conn.prepareStatement(
                "INSERT INTO cookbook_retry_transactions (id, value) "
                + "VALUES (?, ?)")) {
            stmt.setInt(1, 1);
            stmt.setInt(2, 0);
            stmt.executeUpdate();
        }
    }
    ```

=== "C#"

    ```csharp
    // Drops the shared counter table if it exists.
    static async Task DropTableAsync(NpgsqlConnection conn)
    {
        await using var cmd = new NpgsqlCommand(
            "DROP TABLE IF EXISTS cookbook_retry_transactions", conn);
        await cmd.ExecuteNonQueryAsync();
    }
    
    // Creates the shared counter table, with a single row set to zero. The
    // table must be visible to a second connection, so it cannot be
    // temporary; the name is specific to this recipe, and any earlier copy is
    // dropped first.
    static async Task CreateTableAsync(NpgsqlConnection conn)
    {
        await DropTableAsync(conn);
    
        await using var create = new NpgsqlCommand(
            "CREATE TABLE cookbook_retry_transactions " +
            "(id int PRIMARY KEY, value int NOT NULL)", conn);
        await create.ExecuteNonQueryAsync();
    
        await using var insert = new NpgsqlCommand(
            "INSERT INTO cookbook_retry_transactions (id, value) " +
            "VALUES ($1, $2)", conn)
        {
            Parameters = { new() { Value = 1 }, new() { Value = 0 } },
        };
        await insert.ExecuteNonQueryAsync();
    }
    ```

=== "Go"

    ```go
    // dropTable drops the shared counter table if it exists.
    func dropTable(ctx context.Context, conn *pgx.Conn) error {
    	_, err := conn.Exec(ctx, "DROP TABLE IF EXISTS cookbook_retry_transactions")
    	return err
    }
    
    // createTable creates the shared counter table, with a single row set to
    // zero. The table must be visible to a second connection, so it cannot be
    // temporary; the name is specific to this recipe, and any earlier copy is
    // dropped first.
    func createTable(ctx context.Context, conn *pgx.Conn) error {
    	if err := dropTable(ctx, conn); err != nil {
    		return err
    	}
    	_, err := conn.Exec(ctx,
    		"CREATE TABLE cookbook_retry_transactions "+
    			"(id int PRIMARY KEY, value int NOT NULL)")
    	if err != nil {
    		return err
    	}
    	_, err = conn.Exec(ctx,
    		"INSERT INTO cookbook_retry_transactions (id, value) VALUES ($1, $2)",
    		1, 0)
    	return err
    }
    
    ```

=== "Rust"

    ```rust
    /// Drops the shared counter table if it exists.
    fn drop_table(client: &mut Client) -> Result<(), postgres::Error> {
        client.batch_execute("DROP TABLE IF EXISTS cookbook_retry_transactions")
    }
    
    /// Creates the shared counter table, with a single row set to zero. The
    /// table must be visible to a second connection, so it cannot be
    /// temporary; the name is specific to this recipe, and any earlier copy is
    /// dropped first.
    fn create_table(client: &mut Client) -> Result<(), postgres::Error> {
        drop_table(client)?;
        client.batch_execute(
            "CREATE TABLE cookbook_retry_transactions \
             (id int PRIMARY KEY, value int NOT NULL)",
        )?;
        client.execute(
            "INSERT INTO cookbook_retry_transactions (id, value) VALUES ($1, $2)",
            &[&1_i32, &0_i32],
        )?;
        Ok(())
    }
    ```

=== "Ruby"

    ```ruby
    # Drops the shared counter table if it exists.
    def drop_table(conn)
      conn.exec("DROP TABLE IF EXISTS cookbook_retry_transactions")
    end
    
    # Creates the shared counter table, with a single row set to zero. The
    # table must be visible to a second connection, so it cannot be
    # temporary; the name is specific to this recipe, and any earlier copy is
    # dropped first.
    def create_table(conn)
      drop_table(conn)
      conn.exec("CREATE TABLE cookbook_retry_transactions " \
                "(id int PRIMARY KEY, value int NOT NULL)")
      conn.exec_params(
        "INSERT INTO cookbook_retry_transactions (id, value) VALUES ($1, $2)",
        [1, 0]
      )
    end
    ```

=== "C"

    ```c
    /*
     * Run a statement with optional text parameters, and return true if it
     * succeeded. The five-character SQLSTATE code of a failure is copied into
     * sqlstate, which is empty if the statement succeeded or the failure has
     * no code (for example, a lost connection). If value is not NULL, the
     * first column of the first row is copied into it, up to size bytes.
     */
    static bool
    run_sql(PGconn *conn, const char *sql, int nparams, const char *const *params,
            char *sqlstate, char *value, size_t size)
    {
        PGresult *res = PQexecParams(conn, sql, nparams, NULL, params, NULL,
                                     NULL, 0);
        ExecStatusType status = PQresultStatus(res);
        bool ok = status == PGRES_COMMAND_OK || status == PGRES_TUPLES_OK;
        const char *code = PQresultErrorField(res, PG_DIAG_SQLSTATE);
    
        snprintf(sqlstate, 6, "%s", code != NULL ? code : "");
        if (ok && value != NULL)
            snprintf(value, size, "%s", PQgetvalue(res, 0, 0));
    
        /* PQclear() frees the result, and accepts NULL. */
        PQclear(res);
        return ok;
    }
    
    /* Drop the shared counter table if it exists. */
    static bool
    drop_table(PGconn *conn)
    {
        char sqlstate[6];
    
        return run_sql(conn, "DROP TABLE IF EXISTS cookbook_retry_transactions",
                       0, NULL, sqlstate, NULL, 0);
    }
    
    /*
     * Create the shared counter table, with a single row set to zero. The
     * table must be visible to a second connection, so it cannot be
     * temporary; the name is specific to this recipe, and any earlier copy is
     * dropped first.
     */
    static bool
    create_table(PGconn *conn)
    {
        const char *params[] = {"1", "0"};
        char sqlstate[6];
    
        return drop_table(conn) &&
            run_sql(conn,
                    "CREATE TABLE cookbook_retry_transactions "
                    "(id int PRIMARY KEY, value int NOT NULL)",
                    0, NULL, sqlstate, NULL, 0) &&
            run_sql(conn,
                    "INSERT INTO cookbook_retry_transactions (id, value) "
                    "VALUES ($1, $2)",
                    2, params, sqlstate, NULL, 0);
    }
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
    def increment_counter(conn: psycopg.Connection, attempt: int) -> None:
        """Reads the counter and writes back the value plus one."""
        value = conn.execute(
            "SELECT value FROM cookbook_retry_transactions WHERE id = %s",
            (1,),
        ).fetchone()[0]
    
        # Simulate another client by updating the row from a second
        # connection, after this transaction has read the row but before it
        # writes. This happens on the first attempt only.
        if attempt == 1:
            with connect() as other:
                other.execute(
                    "UPDATE cookbook_retry_transactions "
                    "SET value = value + 1 WHERE id = %s",
                    (1,),
                )
    
        # Under REPEATABLE READ, updating a row that another transaction
        # changed and committed since this transaction's snapshot was taken
        # fails with SQLSTATE 40001.
        conn.execute(
            "UPDATE cookbook_retry_transactions SET value = %s WHERE id = %s",
            (value + 1, 1),
        )
    
    
    def read_counter(conn: psycopg.Connection) -> int:
        """Returns the current value of the counter."""
        row = conn.execute(
            "SELECT value FROM cookbook_retry_transactions WHERE id = %s",
            (1,),
        ).fetchone()
        return row[0]
    ```

=== "TypeScript"

    ```typescript
    // Reads the counter and writes back the value plus one.
    async function incrementCounter(
      client: pg.Client,
      attempt: number,
    ): Promise<void> {
      const result = await client.query<{ value: number }>(
        "SELECT value FROM cookbook_retry_transactions WHERE id = $1",
        [1],
      );
      const value = result.rows[0].value;
    
      // Simulate another client by updating the row from a second
      // connection, after this transaction has read the row but before it
      // writes. This happens on the first attempt only.
      if (attempt === 1) {
        const other = await connect();
        try {
          await other.query(
            "UPDATE cookbook_retry_transactions SET value = value + 1 " +
              "WHERE id = $1",
            [1],
          );
        } finally {
          await other.end();
        }
      }
    
      // Under REPEATABLE READ, updating a row that another transaction
      // changed and committed since this transaction's snapshot was taken
      // fails with SQLSTATE 40001.
      await client.query(
        "UPDATE cookbook_retry_transactions SET value = $1 WHERE id = $2",
        [value + 1, 1],
      );
    }
    
    // Returns the current value of the counter.
    async function readCounter(client: pg.Client): Promise<number> {
      const result = await client.query<{ value: number }>(
        "SELECT value FROM cookbook_retry_transactions WHERE id = $1",
        [1],
      );
      return result.rows[0].value;
    }
    ```

=== "Java"

    ```java
    /** The work done inside one transaction. */
    interface Work {
        void run(Connection conn, int attempt) throws SQLException;
    }
    
    /** Reads the counter and writes back the value plus one. */
    static void incrementCounter(Connection conn, int attempt)
            throws SQLException {
        int value = readCounter(conn);
    
        // Simulate another client by updating the row from a second
        // connection, after this transaction has read the row but before
        // it writes. This happens on the first attempt only.
        if (attempt == 1) {
            try (Connection other = connect();
                 PreparedStatement stmt = other.prepareStatement(
                    "UPDATE cookbook_retry_transactions "
                    + "SET value = value + 1 WHERE id = ?")) {
                stmt.setInt(1, 1);
                stmt.executeUpdate();
            }
        }
    
        // Under REPEATABLE READ, updating a row that another transaction
        // changed and committed since this transaction's snapshot was
        // taken fails with SQLSTATE 40001.
        try (PreparedStatement stmt = conn.prepareStatement(
                "UPDATE cookbook_retry_transactions SET value = ? "
                + "WHERE id = ?")) {
            stmt.setInt(1, value + 1);
            stmt.setInt(2, 1);
            stmt.executeUpdate();
        }
    }
    
    /** Returns the current value of the counter. */
    static int readCounter(Connection conn) throws SQLException {
        try (PreparedStatement stmt = conn.prepareStatement(
                "SELECT value FROM cookbook_retry_transactions "
                + "WHERE id = ?")) {
            stmt.setInt(1, 1);
            try (ResultSet rs = stmt.executeQuery()) {
                rs.next();
                return rs.getInt(1);
            }
        }
    }
    ```

=== "C#"

    ```csharp
    // Reads the counter and writes back the value plus one.
    static async Task IncrementCounterAsync(
        NpgsqlDataSource dataSource, NpgsqlConnection conn, int attempt)
    {
        var value = await ReadCounterAsync(conn);
    
        // Simulate another client by updating the row from a second
        // connection, after this transaction has read the row but before it
        // writes. This happens on the first attempt only.
        if (attempt == 1)
        {
            await using var other = await dataSource.OpenConnectionAsync();
            await using var cmd = new NpgsqlCommand(
                "UPDATE cookbook_retry_transactions SET value = value + 1 " +
                "WHERE id = $1", other)
            {
                Parameters = { new() { Value = 1 } },
            };
            await cmd.ExecuteNonQueryAsync();
        }
    
        // Under REPEATABLE READ, updating a row that another transaction
        // changed and committed since this transaction's snapshot was taken
        // fails with SQLSTATE 40001.
        await using var update = new NpgsqlCommand(
            "UPDATE cookbook_retry_transactions SET value = $1 WHERE id = $2",
            conn)
        {
            Parameters = { new() { Value = value + 1 }, new() { Value = 1 } },
        };
        await update.ExecuteNonQueryAsync();
    }
    
    // Returns the current value of the counter.
    static async Task<int> ReadCounterAsync(NpgsqlConnection conn)
    {
        await using var cmd = new NpgsqlCommand(
            "SELECT value FROM cookbook_retry_transactions WHERE id = $1", conn)
        {
            Parameters = { new() { Value = 1 } },
        };
        return (int)(await cmd.ExecuteScalarAsync())!;
    }
    ```

=== "Go"

    ```go
    // incrementCounter reads the counter and writes back the value plus one.
    func incrementCounter(ctx context.Context, tx pgx.Tx, attempt int) error {
    	var value int
    	err := tx.QueryRow(ctx,
    		"SELECT value FROM cookbook_retry_transactions WHERE id = $1",
    		1).Scan(&value)
    	if err != nil {
    		return err
    	}
    
    	// Simulate another client by updating the row from a second
    	// connection, after this transaction has read the row but before it
    	// writes. This happens on the first attempt only.
    	if attempt == 1 {
    		if err := updateFromOtherConnection(ctx); err != nil {
    			return err
    		}
    	}
    
    	// Under REPEATABLE READ, updating a row that another transaction
    	// changed and committed since this transaction's snapshot was taken
    	// fails with SQLSTATE 40001.
    	_, err = tx.Exec(ctx,
    		"UPDATE cookbook_retry_transactions SET value = $1 WHERE id = $2",
    		value+1, 1)
    	return err
    }
    
    // updateFromOtherConnection increments the counter on a second connection,
    // which commits straight away because it has no open transaction.
    func updateFromOtherConnection(ctx context.Context) error {
    	other, err := connect(ctx)
    	if err != nil {
    		return err
    	}
    	defer other.Close(ctx)
    
    	_, err = other.Exec(ctx,
    		"UPDATE cookbook_retry_transactions SET value = value + 1 "+
    			"WHERE id = $1", 1)
    	return err
    }
    
    // readCounter returns the current value of the counter.
    func readCounter(ctx context.Context, conn *pgx.Conn) (int, error) {
    	var value int
    	err := conn.QueryRow(ctx,
    		"SELECT value FROM cookbook_retry_transactions WHERE id = $1",
    		1).Scan(&value)
    	return value, err
    }
    
    ```

=== "Rust"

    ```rust
    /// Reads the counter and writes back the value plus one.
    fn increment_counter(
        tx: &mut Transaction,
        attempt: u32,
    ) -> Result<(), postgres::Error> {
        let row = tx.query_one(
            "SELECT value FROM cookbook_retry_transactions WHERE id = $1",
            &[&1_i32],
        )?;
        let value: i32 = row.get(0);
    
        // Simulate another client by updating the row from a second
        // connection, after this transaction has read the row but before it
        // writes. This happens on the first attempt only.
        if attempt == 1 {
            let mut other = connect()?;
            other.execute(
                "UPDATE cookbook_retry_transactions SET value = value + 1 \
                 WHERE id = $1",
                &[&1_i32],
            )?;
        }
    
        // Under REPEATABLE READ, updating a row that another transaction
        // changed and committed since this transaction's snapshot was taken
        // fails with SQLSTATE 40001.
        tx.execute(
            "UPDATE cookbook_retry_transactions SET value = $1 WHERE id = $2",
            &[&(value + 1), &1_i32],
        )?;
        Ok(())
    }
    
    /// Returns the current value of the counter.
    fn read_counter(client: &mut Client) -> Result<i32, postgres::Error> {
        let row = client.query_one(
            "SELECT value FROM cookbook_retry_transactions WHERE id = $1",
            &[&1_i32],
        )?;
        Ok(row.get(0))
    }
    ```

=== "Ruby"

    ```ruby
    # Reads the counter and writes back the value plus one.
    def increment_counter(conn, attempt)
      value = read_counter(conn)
    
      # Simulate another client by updating the row from a second connection,
      # after this transaction has read the row but before it writes. This
      # happens on the first attempt only.
      if attempt == 1
        other = connect
        begin
          other.exec_params(
            "UPDATE cookbook_retry_transactions SET value = value + 1 " \
            "WHERE id = $1",
            [1]
          )
        ensure
          other.close
        end
      end
    
      # Under REPEATABLE READ, updating a row that another transaction
      # changed and committed since this transaction's snapshot was taken
      # fails with SQLSTATE 40001.
      conn.exec_params(
        "UPDATE cookbook_retry_transactions SET value = $1 WHERE id = $2",
        [value + 1, 1]
      )
    end
    
    # Returns the current value of the counter. Results arrive as strings, so
    # the value is converted to an Integer.
    def read_counter(conn)
      conn.exec_params(
        "SELECT value FROM cookbook_retry_transactions WHERE id = $1", [1]
      ).getvalue(0, 0).to_i
    end
    ```

=== "C"

    ```c
    /* Read the current value of the counter into *counter. */
    static bool
    read_counter(PGconn *conn, int *counter, char *sqlstate)
    {
        const char *params[] = {"1"};
        char text[32];
    
        if (!run_sql(conn,
                     "SELECT value FROM cookbook_retry_transactions "
                     "WHERE id = $1",
                     1, params, sqlstate, text, sizeof(text)))
            return false;
    
        /* Results arrive as text, so convert the value to a number. */
        *counter = atoi(text);
        return true;
    }
    
    /*
     * Simulate another client by incrementing the counter on a second
     * connection, which commits straight away because it has no open
     * transaction. On failure, the SQLSTATE code and error message of the
     * second connection are copied into the caller's buffers.
     */
    static bool
    update_from_other_connection(char *sqlstate, char *message, size_t size)
    {
        const char *params[] = {"1"};
        PGconn *other = connect_to_server();
        bool ok = PQstatus(other) == CONNECTION_OK &&
            run_sql(other,
                    "UPDATE cookbook_retry_transactions SET value = value + 1 "
                    "WHERE id = $1",
                    1, params, sqlstate, NULL, 0);
    
        if (!ok)
            snprintf(message, size, "%s", PQerrorMessage(other));
        PQfinish(other);
        return ok;
    }
    
    /*
     * Read the counter and write back the value plus one. A failure on conn
     * leaves message empty, because PQerrorMessage(conn) describes it.
     */
    static bool
    increment_counter(PGconn *conn, int attempt, char *sqlstate,
                      char *message, size_t size)
    {
        int counter;
        char next[32];
        const char *params[2];
    
        if (!read_counter(conn, &counter, sqlstate))
            return false;
    
        /*
         * Simulate another client by updating the row from a second
         * connection, after this transaction has read the row but before it
         * writes. This happens on the first attempt only.
         */
        if (attempt == 1 &&
            !update_from_other_connection(sqlstate, message, size))
            return false;
    
        /*
         * Under REPEATABLE READ, updating a row that another transaction
         * changed and committed since this transaction's snapshot was taken
         * fails with SQLSTATE 40001.
         */
        snprintf(next, sizeof(next), "%d", counter + 1);
        params[0] = next;
        params[1] = "1";
        return run_sql(conn,
                       "UPDATE cookbook_retry_transactions SET value = $1 "
                       "WHERE id = $2",
                       2, params, sqlstate, NULL, 0);
    }
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
    def run_with_retry(conn: psycopg.Connection, work) -> None:
        """Runs work(conn, attempt) in a REPEATABLE READ transaction, and runs
        it again if the server reports a serialisation failure or a deadlock.
        """
        conn.isolation_level = psycopg.IsolationLevel.REPEATABLE_READ
    
        for attempt in range(1, MAX_ATTEMPTS + 1):
            try:
                # The transaction block commits when it exits normally, and
                # rolls back if an exception escapes it.
                with conn.transaction():
                    work(conn, attempt)
            except psycopg.Error as e:
                # Any other error, or running out of attempts, is a real
                # failure that the caller must handle.
                if e.sqlstate not in RETRYABLE or attempt == MAX_ATTEMPTS:
                    raise
                print(f"Attempt {attempt}: serialisation failure, retrying")
                # A short, growing pause gives the competing transaction time
                # to finish.
                time.sleep(0.05 * attempt)
            else:
                print(f"Attempt {attempt}: committed")
                return
    ```

=== "TypeScript"

    ```typescript
    // Runs work(client, attempt) in a REPEATABLE READ transaction, and runs
    // it again if the server reports a serialisation failure or a deadlock.
    async function runWithRetry(
      client: pg.Client,
      work: (client: pg.Client, attempt: number) => Promise<void>,
    ): Promise<void> {
      for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt++) {
        try {
          await client.query("BEGIN ISOLATION LEVEL REPEATABLE READ");
          await work(client, attempt);
          await client.query("COMMIT");
          console.log(`Attempt ${attempt}: committed`);
          return;
        } catch (err) {
          // End the failed transaction so that the session can start another.
          // If the connection is lost the rollback fails too, and that error
          // must not hide the original one.
          await client.query("ROLLBACK").catch(() => undefined);
    
          // Any other error, or running out of attempts, is a real failure
          // that the caller must handle.
          const code = (err as pg.DatabaseError).code;
          if (code === undefined || !RETRYABLE.has(code) ||
              attempt === MAX_ATTEMPTS) {
            throw err;
          }
          console.log(`Attempt ${attempt}: serialisation failure, retrying`);
          // A short, growing pause gives the competing transaction time to
          // finish.
          await sleep(50 * attempt);
        }
      }
    }
    ```

=== "Java"

    ```java
    /**
     * Runs the work in a REPEATABLE READ transaction, and runs it again
     * if the server reports a serialisation failure or a deadlock.
     */
    static void runWithRetry(Connection conn, Work work)
            throws SQLException, InterruptedException {
        // Turning autocommit off makes the driver start a transaction
        // with the first statement, and end it at commit() or rollback().
        conn.setAutoCommit(false);
        conn.setTransactionIsolation(Connection.TRANSACTION_REPEATABLE_READ);
        try {
            for (int attempt = 1; attempt <= MAX_ATTEMPTS; attempt++) {
                try {
                    work.run(conn, attempt);
                    conn.commit();
                    System.out.println("Attempt " + attempt + ": committed");
                    return;
                } catch (SQLException e) {
                    // End the failed transaction so that the session can
                    // start another. If the connection is lost the
                    // rollback fails too, and that error must not hide
                    // the original one, so it is attached to it instead.
                    try {
                        conn.rollback();
                    } catch (SQLException rollbackError) {
                        e.addSuppressed(rollbackError);
                    }
    
                    // Any other error, or running out of attempts, is a
                    // real failure that the caller must handle.
                    if (!RETRYABLE.contains(e.getSQLState())
                            || attempt == MAX_ATTEMPTS) {
                        throw e;
                    }
                    System.out.println("Attempt " + attempt
                            + ": serialisation failure, retrying");
                    // A short, growing pause gives the competing
                    // transaction time to finish.
                    Thread.sleep(50L * attempt);
                }
            }
        } finally {
            // Restoring autocommit fails only if the connection is already
            // broken. That error must not replace the one in flight, and
            // closing the connection discards the session anyway.
            try {
                conn.setAutoCommit(true);
            } catch (SQLException ignored) {
                // Nothing useful can be done with a broken connection.
            }
        }
    }
    ```

=== "C#"

    ```csharp
    // Runs work(conn, attempt) in a REPEATABLE READ transaction, and runs it
    // again if the server reports a serialisation failure or a deadlock.
    static async Task RunWithRetryAsync(
        NpgsqlConnection conn, Func<NpgsqlConnection, int, Task> work)
    {
        for (var attempt = 1; attempt <= MaxAttempts; attempt++)
        {
            try
            {
                // Disposing the transaction without committing rolls it
                // back, so an error from the work leaves nothing behind.
                await using var tx = await conn.BeginTransactionAsync(
                    IsolationLevel.RepeatableRead);
                await work(conn, attempt);
                await tx.CommitAsync();
    
                Console.WriteLine($"Attempt {attempt}: committed");
                return;
            }
            // Any other error, or running out of attempts, is a real failure
            // that the caller must handle, so the filter lets it through.
            catch (PostgresException e)
                when (IsRetryable(e.SqlState) && attempt < MaxAttempts)
            {
                Console.WriteLine(
                    $"Attempt {attempt}: serialisation failure, retrying");
                // A short, growing pause gives the competing transaction time
                // to finish.
                await Task.Delay(50 * attempt);
            }
        }
    }
    ```

=== "Go"

    ```go
    // runOnce runs work in a single REPEATABLE READ transaction.
    func runOnce(ctx context.Context, conn *pgx.Conn, attempt int,
    	work func(context.Context, pgx.Tx, int) error) error {
    	tx, err := conn.BeginTx(ctx, pgx.TxOptions{IsoLevel: pgx.RepeatableRead})
    	if err != nil {
    		return err
    	}
    	// The deferred rollback undoes the work if it fails; after a
    	// successful commit it does nothing.
    	defer tx.Rollback(ctx)
    
    	if err := work(ctx, tx, attempt); err != nil {
    		return err
    	}
    	return tx.Commit(ctx)
    }
    
    // runWithRetry runs work in a REPEATABLE READ transaction, and runs it
    // again if the server reports a serialisation failure or a deadlock.
    func runWithRetry(ctx context.Context, conn *pgx.Conn,
    	work func(context.Context, pgx.Tx, int) error) error {
    	for attempt := 1; attempt <= maxAttempts; attempt++ {
    		err := runOnce(ctx, conn, attempt, work)
    		if err == nil {
    			fmt.Printf("Attempt %d: committed\n", attempt)
    			return nil
    		}
    
    		// Any other error, or running out of attempts, is a real failure
    		// that the caller must handle.
    		if !isRetryable(err) || attempt == maxAttempts {
    			return err
    		}
    		fmt.Printf("Attempt %d: serialisation failure, retrying\n", attempt)
    		// A short, growing pause gives the competing transaction time to
    		// finish.
    		time.Sleep(time.Duration(attempt) * 50 * time.Millisecond)
    	}
    	return nil
    }
    
    ```

=== "Rust"

    ```rust
    /// The type of a function that does the work of one transaction.
    type Work = fn(&mut Transaction, u32) -> Result<(), postgres::Error>;
    
    /// Runs the work in a single REPEATABLE READ transaction. Dropping the
    /// transaction without committing rolls it back, so an error from the
    /// work or from the commit leaves nothing behind.
    fn run_once(
        client: &mut Client,
        attempt: u32,
        work: Work,
    ) -> Result<(), postgres::Error> {
        let mut tx = client
            .build_transaction()
            .isolation_level(IsolationLevel::RepeatableRead)
            .start()?;
        work(&mut tx, attempt)?;
        tx.commit()
    }
    
    /// Runs the work in a REPEATABLE READ transaction, and runs it again if
    /// the server reports a serialisation failure or a deadlock.
    fn run_with_retry(client: &mut Client, work: Work) -> Result<(), postgres::Error> {
        for attempt in 1..=MAX_ATTEMPTS {
            match run_once(client, attempt, work) {
                Ok(()) => {
                    println!("Attempt {attempt}: committed");
                    return Ok(());
                }
                // Any other error, or running out of attempts, is a real
                // failure that the caller must handle.
                Err(e) if !is_retryable(&e) || attempt == MAX_ATTEMPTS => {
                    return Err(e);
                }
                Err(_) => {
                    println!("Attempt {attempt}: serialisation failure, retrying");
                    // A short, growing pause gives the competing transaction
                    // time to finish.
                    sleep(Duration::from_millis(50 * u64::from(attempt)));
                }
            }
        }
        unreachable!("the final attempt returns above")
    }
    ```

=== "Ruby"

    ```ruby
    # Returns the SQLSTATE code of an error reported by the server, or nil for
    # errors such as a lost connection that have no result.
    def sqlstate(error)
      error.result&.error_field(PG::PG_DIAG_SQLSTATE)
    end
    
    # Yields the connection and the attempt number inside a REPEATABLE READ
    # transaction, and runs the block again if the server reports a
    # serialisation failure or a deadlock.
    def run_with_retry(conn)
      (1..MAX_ATTEMPTS).each do |attempt|
        begin
          conn.exec("BEGIN ISOLATION LEVEL REPEATABLE READ")
          yield conn, attempt
          conn.exec("COMMIT")
          puts "Attempt #{attempt}: committed"
          return
        rescue PG::Error => e
          # End the failed transaction so that the session can start another.
          # If the connection is lost the rollback fails too, and that error
          # must not hide the original one.
          begin
            conn.exec("ROLLBACK")
          rescue PG::Error
            nil
          end
    
          # Any other error, or running out of attempts, is a real failure
          # that the caller must handle.
          raise unless RETRYABLE.include?(sqlstate(e)) && attempt < MAX_ATTEMPTS
    
          puts "Attempt #{attempt}: serialisation failure, retrying"
          # A short, growing pause gives the competing transaction time to
          # finish.
          sleep(0.05 * attempt)
        end
      end
    end
    ```

=== "C"

    ```c
    /* The type of a function that does the work of one transaction. */
    typedef bool (*work_fn)(PGconn *conn, int attempt, char *sqlstate,
                            char *message, size_t size);
    
    /* Sleep for the given number of milliseconds. */
    static void
    pause_ms(long ms)
    {
        struct timespec ts = {ms / 1000, (ms % 1000) * 1000000L};
    
        nanosleep(&ts, NULL);
    }
    
    /*
     * Run work() in a REPEATABLE READ transaction, and run it again if the
     * server reports a serialisation failure or a deadlock. Return true if a
     * transaction committed. On failure, print the saved error message to
     * stderr, because the caller cannot recover it from the connection.
     */
    static bool
    run_with_retry(PGconn *conn, work_fn work)
    {
        char sqlstate[6];
        char message[512];
    
        for (int attempt = 1; attempt <= MAX_ATTEMPTS; attempt++)
        {
            bool ok;
    
            message[0] = '\0';
            ok = run_sql(conn, "BEGIN ISOLATION LEVEL REPEATABLE READ",
                         0, NULL, sqlstate, NULL, 0) &&
                work(conn, attempt, sqlstate, message, sizeof(message)) &&
                run_sql(conn, "COMMIT", 0, NULL, sqlstate, NULL, 0);
    
            if (ok)
            {
                printf("Attempt %d: committed\n", attempt);
                return true;
            }
    
            /*
             * End the failed transaction so that the session can start
             * another. The error message is kept, because the ROLLBACK
             * would otherwise replace it; the work may already have supplied
             * a message from another connection.
             */
            char ignored[6];
    
            if (message[0] == '\0')
                snprintf(message, sizeof(message), "%s", PQerrorMessage(conn));
            run_sql(conn, "ROLLBACK", 0, NULL, ignored, NULL, 0);
    
            /*
             * Any other error, or running out of attempts, is a real failure
             * that the caller must report.
             */
            if (!is_retryable(sqlstate) || attempt == MAX_ATTEMPTS)
            {
                fprintf(stderr, "Database error: %s", message);
                return false;
            }
    
            printf("Attempt %d: serialisation failure, retrying\n", attempt);
            /* A short, growing pause gives the competing transaction time. */
            pause_ms(50L * attempt);
        }
        return false;
    }
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
    def main() -> int:
        try:
            # The with block closes the connection when it exits, whether or
            # not an error occurred.
            with connect() as conn:
                try:
                    create_table(conn)
                    run_with_retry(conn, increment_counter)
                    print(f"Counter value: {read_counter(conn)}")
                finally:
                    # Drop the shared table even if the work failed.
                    drop_table(conn)
        # psycopg.Error is the base class for every error the driver raises,
        # including connection failures and errors reported by the server.
        except psycopg.Error as e:
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
        try {
          await createTable(client);
          await runWithRetry(client, incrementCounter);
          console.log(`Counter value: ${await readCounter(client)}`);
        } finally {
          // Drop the shared table even if the work failed.
          await dropTable(client);
        }
        return 0;
      } catch (err) {
        // Connection failures and errors reported by the server both arrive
        // here as rejected promises.
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
            try {
                createTable(conn);
                runWithRetry(conn, Main::incrementCounter);
                System.out.println("Counter value: " + readCounter(conn));
            } finally {
                // Drop the shared table even if the work failed.
                dropTable(conn);
            }
        // SQLException covers connection failures and errors reported by
        // the server.
        } catch (SQLException e) {
            System.err.println("Database error: " + e.getMessage());
            System.exit(1);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            System.err.println("Interrupted while waiting to retry");
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
    
        try
        {
            await CreateTableAsync(conn);
            await RunWithRetryAsync(
                conn, (c, attempt) => IncrementCounterAsync(dataSource, c, attempt));
            Console.WriteLine($"Counter value: {await ReadCounterAsync(conn)}");
        }
        finally
        {
            // Drop the shared table even if the work failed.
            await DropTableAsync(conn);
        }
    }
    // NpgsqlException covers connection failures; PostgresException, which
    // derives from it, carries errors reported by the server.
    catch (NpgsqlException e)
    {
        Console.Error.WriteLine($"Database error: {e.Message}");
        return 1;
    }
    
    return 0;
    ```

=== "Go"

    ```go
    // run connects, runs the transaction with retries, and prints the result,
    // returning any error to the caller.
    func run(ctx context.Context) error {
    	conn, err := connect(ctx)
    	if err != nil {
    		return err
    	}
    	// The deferred call closes the connection when run() returns, whether
    	// or not an error occurred.
    	defer conn.Close(ctx)
    
    	// Drop the shared table when the work is done, even if it failed.
    	defer dropTable(ctx, conn)
    
    	if err := createTable(ctx, conn); err != nil {
    		return err
    	}
    	if err := runWithRetry(ctx, conn, incrementCounter); err != nil {
    		return err
    	}
    
    	value, err := readCounter(ctx, conn)
    	if err != nil {
    		return err
    	}
    	fmt.Printf("Counter value: %d\n", value)
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
    /// Connects, runs the transaction with retries, and prints the result.
    /// The ? operator returns any error to the caller.
    fn run() -> Result<(), postgres::Error> {
        let mut client = connect()?;
    
        let result = create_table(&mut client)
            .and_then(|()| run_with_retry(&mut client, increment_counter))
            .and_then(|()| read_counter(&mut client));
    
        // Drop the shared table even if the work failed, but report the error
        // from the work first.
        let dropped = drop_table(&mut client);
        let counter = result?;
        dropped?;
        println!("Counter value: {counter}");
    
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
      begin
        create_table(conn)
        run_with_retry(conn) { |c, attempt| increment_counter(c, attempt) }
        puts "Counter value: #{read_counter(conn)}"
      ensure
        # Drop the shared table even if the work failed.
        drop_table(conn)
      end
    # PG::Error is the base class for every error the gem raises, including
    # connection failures and errors reported by the server.
    rescue PG::Error => e
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
        int counter;
        char sqlstate[6];
        PGconn *conn = connect_to_server();
    
        if (PQstatus(conn) != CONNECTION_OK)
        {
            fprintf(stderr, "Database error: %s", PQerrorMessage(conn));
        }
        else
        {
            if (!create_table(conn))
                fprintf(stderr, "Database error: %s", PQerrorMessage(conn));
            else if (run_with_retry(conn, increment_counter))
            {
                if (read_counter(conn, &counter, sqlstate))
                {
                    printf("Counter value: %d\n", counter);
                    status = EXIT_SUCCESS;
                }
                else
                    fprintf(stderr, "Database error: %s",
                            PQerrorMessage(conn));
            }
    
            /* Drop the shared table even if the work failed. */
            drop_table(conn);
        }
    
        /* Close the connection whether or not an error occurred. */
        PQfinish(conn);
        return status;
    }
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
    """
    Ellie's Postgres Cookbook
    Retrying a transaction after a serialisation failure, using psycopg 3.
    
    Copyright (c) 2026, pgEdge, Inc.
    This code is released under the PostgreSQL License.
    """
    
    import os
    import sys
    import time
    
    import psycopg
    
    
    # The SQLSTATE codes that mean "run the transaction again": 40001 is a
    # serialisation failure and 40P01 is a deadlock.
    RETRYABLE = {"40001", "40P01"}
    MAX_ATTEMPTS = 5
    
    
    def connection_settings() -> dict:
        """Reads the connection settings from the standard libpq environment
        variables, with defaults suitable for a local development server.
    
        The or operator treats an empty variable as unset, as libpq does, and
        a password of None is simply not sent.
        """
        return {
            "host": os.environ.get("PGHOST") or "localhost",
            "port": os.environ.get("PGPORT") or "5432",
            "dbname": os.environ.get("PGDATABASE") or "postgres",
            "user": os.environ.get("PGUSER") or "postgres",
            "password": os.environ.get("PGPASSWORD") or None,
        }
    
    
    def connect() -> psycopg.Connection:
        """Opens a connection with the settings from the environment.
    
        Autocommit mode means that the program, rather than the driver,
        decides where each transaction begins and ends.
        """
        return psycopg.connect(**connection_settings(), autocommit=True)
    
    
    def create_table(conn: psycopg.Connection) -> None:
        """Creates the shared counter table, with a single row set to zero.
    
        The table must be visible to a second connection, so it cannot be
        temporary; the name is specific to this recipe, and any earlier copy
        is dropped first.
        """
        drop_table(conn)
        conn.execute(
            "CREATE TABLE cookbook_retry_transactions "
            "(id int PRIMARY KEY, value int NOT NULL)"
        )
        conn.execute(
            "INSERT INTO cookbook_retry_transactions (id, value) VALUES (%s, %s)",
            (1, 0),
        )
    
    
    def drop_table(conn: psycopg.Connection) -> None:
        """Drops the shared counter table if it exists."""
        conn.execute("DROP TABLE IF EXISTS cookbook_retry_transactions")
    
    
    def increment_counter(conn: psycopg.Connection, attempt: int) -> None:
        """Reads the counter and writes back the value plus one."""
        value = conn.execute(
            "SELECT value FROM cookbook_retry_transactions WHERE id = %s",
            (1,),
        ).fetchone()[0]
    
        # Simulate another client by updating the row from a second
        # connection, after this transaction has read the row but before it
        # writes. This happens on the first attempt only.
        if attempt == 1:
            with connect() as other:
                other.execute(
                    "UPDATE cookbook_retry_transactions "
                    "SET value = value + 1 WHERE id = %s",
                    (1,),
                )
    
        # Under REPEATABLE READ, updating a row that another transaction
        # changed and committed since this transaction's snapshot was taken
        # fails with SQLSTATE 40001.
        conn.execute(
            "UPDATE cookbook_retry_transactions SET value = %s WHERE id = %s",
            (value + 1, 1),
        )
    
    
    def read_counter(conn: psycopg.Connection) -> int:
        """Returns the current value of the counter."""
        row = conn.execute(
            "SELECT value FROM cookbook_retry_transactions WHERE id = %s",
            (1,),
        ).fetchone()
        return row[0]
    
    
    def run_with_retry(conn: psycopg.Connection, work) -> None:
        """Runs work(conn, attempt) in a REPEATABLE READ transaction, and runs
        it again if the server reports a serialisation failure or a deadlock.
        """
        conn.isolation_level = psycopg.IsolationLevel.REPEATABLE_READ
    
        for attempt in range(1, MAX_ATTEMPTS + 1):
            try:
                # The transaction block commits when it exits normally, and
                # rolls back if an exception escapes it.
                with conn.transaction():
                    work(conn, attempt)
            except psycopg.Error as e:
                # Any other error, or running out of attempts, is a real
                # failure that the caller must handle.
                if e.sqlstate not in RETRYABLE or attempt == MAX_ATTEMPTS:
                    raise
                print(f"Attempt {attempt}: serialisation failure, retrying")
                # A short, growing pause gives the competing transaction time
                # to finish.
                time.sleep(0.05 * attempt)
            else:
                print(f"Attempt {attempt}: committed")
                return
    
    
    def main() -> int:
        try:
            # The with block closes the connection when it exits, whether or
            # not an error occurred.
            with connect() as conn:
                try:
                    create_table(conn)
                    run_with_retry(conn, increment_counter)
                    print(f"Counter value: {read_counter(conn)}")
                finally:
                    # Drop the shared table even if the work failed.
                    drop_table(conn)
        # psycopg.Error is the base class for every error the driver raises,
        # including connection failures and errors reported by the server.
        except psycopg.Error as e:
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
     * Retrying a transaction after a serialisation failure, using
     * node-postgres.
     *
     * Copyright (c) 2026, pgEdge, Inc.
     * This code is released under the PostgreSQL License.
     */
    
    import { setTimeout as sleep } from "node:timers/promises";
    
    import pg from "pg";
    
    // The SQLSTATE codes that mean "run the transaction again": 40001 is a
    // serialisation failure and 40P01 is a deadlock.
    const RETRYABLE = new Set(["40001", "40P01"]);
    const MAX_ATTEMPTS = 5;
    
    // Read the connection settings from the standard libpq environment
    // variables, with defaults suitable for a local development server.
    // The || operator, unlike ??, also treats an empty variable as unset, as
    // libpq does.
    const config: pg.ClientConfig = {
      host: process.env.PGHOST || "localhost",
      port: Number(process.env.PGPORT || "5432"),
      database: process.env.PGDATABASE || "postgres",
      user: process.env.PGUSER || "postgres",
      password: process.env.PGPASSWORD || undefined,
    };
    
    // Opens a connection with the settings from the environment. The driver
    // runs each statement in its own transaction unless the program sends
    // BEGIN, so the program decides where each transaction starts and ends.
    async function connect(): Promise<pg.Client> {
      const client = new pg.Client(config);
      try {
        await client.connect();
      } catch (err) {
        // Release the client before passing the failure to the caller.
        await client.end();
        throw err;
      }
      return client;
    }
    
    // Drops the shared counter table if it exists.
    async function dropTable(client: pg.Client): Promise<void> {
      await client.query("DROP TABLE IF EXISTS cookbook_retry_transactions");
    }
    
    // Creates the shared counter table, with a single row set to zero. The
    // table must be visible to a second connection, so it cannot be
    // temporary; the name is specific to this recipe, and any earlier copy is
    // dropped first.
    async function createTable(client: pg.Client): Promise<void> {
      await dropTable(client);
      await client.query(
        "CREATE TABLE cookbook_retry_transactions " +
          "(id int PRIMARY KEY, value int NOT NULL)",
      );
      await client.query(
        "INSERT INTO cookbook_retry_transactions (id, value) VALUES ($1, $2)",
        [1, 0],
      );
    }
    
    // Reads the counter and writes back the value plus one.
    async function incrementCounter(
      client: pg.Client,
      attempt: number,
    ): Promise<void> {
      const result = await client.query<{ value: number }>(
        "SELECT value FROM cookbook_retry_transactions WHERE id = $1",
        [1],
      );
      const value = result.rows[0].value;
    
      // Simulate another client by updating the row from a second
      // connection, after this transaction has read the row but before it
      // writes. This happens on the first attempt only.
      if (attempt === 1) {
        const other = await connect();
        try {
          await other.query(
            "UPDATE cookbook_retry_transactions SET value = value + 1 " +
              "WHERE id = $1",
            [1],
          );
        } finally {
          await other.end();
        }
      }
    
      // Under REPEATABLE READ, updating a row that another transaction
      // changed and committed since this transaction's snapshot was taken
      // fails with SQLSTATE 40001.
      await client.query(
        "UPDATE cookbook_retry_transactions SET value = $1 WHERE id = $2",
        [value + 1, 1],
      );
    }
    
    // Returns the current value of the counter.
    async function readCounter(client: pg.Client): Promise<number> {
      const result = await client.query<{ value: number }>(
        "SELECT value FROM cookbook_retry_transactions WHERE id = $1",
        [1],
      );
      return result.rows[0].value;
    }
    
    // Runs work(client, attempt) in a REPEATABLE READ transaction, and runs
    // it again if the server reports a serialisation failure or a deadlock.
    async function runWithRetry(
      client: pg.Client,
      work: (client: pg.Client, attempt: number) => Promise<void>,
    ): Promise<void> {
      for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt++) {
        try {
          await client.query("BEGIN ISOLATION LEVEL REPEATABLE READ");
          await work(client, attempt);
          await client.query("COMMIT");
          console.log(`Attempt ${attempt}: committed`);
          return;
        } catch (err) {
          // End the failed transaction so that the session can start another.
          // If the connection is lost the rollback fails too, and that error
          // must not hide the original one.
          await client.query("ROLLBACK").catch(() => undefined);
    
          // Any other error, or running out of attempts, is a real failure
          // that the caller must handle.
          const code = (err as pg.DatabaseError).code;
          if (code === undefined || !RETRYABLE.has(code) ||
              attempt === MAX_ATTEMPTS) {
            throw err;
          }
          console.log(`Attempt ${attempt}: serialisation failure, retrying`);
          // A short, growing pause gives the competing transaction time to
          // finish.
          await sleep(50 * attempt);
        }
      }
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
        try {
          await createTable(client);
          await runWithRetry(client, incrementCounter);
          console.log(`Counter value: ${await readCounter(client)}`);
        } finally {
          // Drop the shared table even if the work failed.
          await dropTable(client);
        }
        return 0;
      } catch (err) {
        // Connection failures and errors reported by the server both arrive
        // here as rejected promises.
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
     * Retrying a transaction after a serialisation failure, using JDBC and
     * the PostgreSQL JDBC driver (pgJDBC).
     *
     * Copyright (c) 2026, pgEdge, Inc.
     * This code is released under the PostgreSQL License.
     */
    
    import java.sql.Connection;
    import java.sql.DriverManager;
    import java.sql.PreparedStatement;
    import java.sql.ResultSet;
    import java.sql.SQLException;
    import java.sql.Statement;
    import java.util.Properties;
    import java.util.Set;
    
    public class Main {
    
        /**
         * The SQLSTATE codes that mean "run the transaction again": 40001 is
         * a serialisation failure and 40P01 is a deadlock.
         */
        static final Set<String> RETRYABLE = Set.of("40001", "40P01");
        static final int MAX_ATTEMPTS = 5;
    
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
         * Returns the user name and password as connection properties; the
         * password is omitted if PGPASSWORD is unset or empty.
         */
        static Properties connectionProperties() {
            Properties props = new Properties();
            props.setProperty("user", envOr("PGUSER", "postgres"));
            String password = envOr("PGPASSWORD", null);
            if (password != null) {
                props.setProperty("password", password);
            }
            return props;
        }
    
        /**
         * Opens a connection with the settings from the environment. The
         * connection starts in autocommit mode, where each statement is its
         * own transaction.
         */
        static Connection connect() throws SQLException {
            return DriverManager.getConnection(
                    connectionUrl(), connectionProperties());
        }
    
        /** Drops the shared counter table if it exists. */
        static void dropTable(Connection conn) throws SQLException {
            try (Statement stmt = conn.createStatement()) {
                stmt.execute("DROP TABLE IF EXISTS cookbook_retry_transactions");
            }
        }
    
        /**
         * Creates the shared counter table, with a single row set to zero.
         * The table must be visible to a second connection, so it cannot be
         * temporary; the name is specific to this recipe, and any earlier
         * copy is dropped first.
         */
        static void createTable(Connection conn) throws SQLException {
            dropTable(conn);
            try (Statement stmt = conn.createStatement()) {
                stmt.execute("CREATE TABLE cookbook_retry_transactions "
                        + "(id int PRIMARY KEY, value int NOT NULL)");
            }
            try (PreparedStatement stmt = conn.prepareStatement(
                    "INSERT INTO cookbook_retry_transactions (id, value) "
                    + "VALUES (?, ?)")) {
                stmt.setInt(1, 1);
                stmt.setInt(2, 0);
                stmt.executeUpdate();
            }
        }
    
        /** The work done inside one transaction. */
        interface Work {
            void run(Connection conn, int attempt) throws SQLException;
        }
    
        /** Reads the counter and writes back the value plus one. */
        static void incrementCounter(Connection conn, int attempt)
                throws SQLException {
            int value = readCounter(conn);
    
            // Simulate another client by updating the row from a second
            // connection, after this transaction has read the row but before
            // it writes. This happens on the first attempt only.
            if (attempt == 1) {
                try (Connection other = connect();
                     PreparedStatement stmt = other.prepareStatement(
                        "UPDATE cookbook_retry_transactions "
                        + "SET value = value + 1 WHERE id = ?")) {
                    stmt.setInt(1, 1);
                    stmt.executeUpdate();
                }
            }
    
            // Under REPEATABLE READ, updating a row that another transaction
            // changed and committed since this transaction's snapshot was
            // taken fails with SQLSTATE 40001.
            try (PreparedStatement stmt = conn.prepareStatement(
                    "UPDATE cookbook_retry_transactions SET value = ? "
                    + "WHERE id = ?")) {
                stmt.setInt(1, value + 1);
                stmt.setInt(2, 1);
                stmt.executeUpdate();
            }
        }
    
        /** Returns the current value of the counter. */
        static int readCounter(Connection conn) throws SQLException {
            try (PreparedStatement stmt = conn.prepareStatement(
                    "SELECT value FROM cookbook_retry_transactions "
                    + "WHERE id = ?")) {
                stmt.setInt(1, 1);
                try (ResultSet rs = stmt.executeQuery()) {
                    rs.next();
                    return rs.getInt(1);
                }
            }
        }
    
        /**
         * Runs the work in a REPEATABLE READ transaction, and runs it again
         * if the server reports a serialisation failure or a deadlock.
         */
        static void runWithRetry(Connection conn, Work work)
                throws SQLException, InterruptedException {
            // Turning autocommit off makes the driver start a transaction
            // with the first statement, and end it at commit() or rollback().
            conn.setAutoCommit(false);
            conn.setTransactionIsolation(Connection.TRANSACTION_REPEATABLE_READ);
            try {
                for (int attempt = 1; attempt <= MAX_ATTEMPTS; attempt++) {
                    try {
                        work.run(conn, attempt);
                        conn.commit();
                        System.out.println("Attempt " + attempt + ": committed");
                        return;
                    } catch (SQLException e) {
                        // End the failed transaction so that the session can
                        // start another. If the connection is lost the
                        // rollback fails too, and that error must not hide
                        // the original one, so it is attached to it instead.
                        try {
                            conn.rollback();
                        } catch (SQLException rollbackError) {
                            e.addSuppressed(rollbackError);
                        }
    
                        // Any other error, or running out of attempts, is a
                        // real failure that the caller must handle.
                        if (!RETRYABLE.contains(e.getSQLState())
                                || attempt == MAX_ATTEMPTS) {
                            throw e;
                        }
                        System.out.println("Attempt " + attempt
                                + ": serialisation failure, retrying");
                        // A short, growing pause gives the competing
                        // transaction time to finish.
                        Thread.sleep(50L * attempt);
                    }
                }
            } finally {
                // Restoring autocommit fails only if the connection is already
                // broken. That error must not replace the one in flight, and
                // closing the connection discards the session anyway.
                try {
                    conn.setAutoCommit(true);
                } catch (SQLException ignored) {
                    // Nothing useful can be done with a broken connection.
                }
            }
        }
    
        public static void main(String[] args) {
            // try-with-resources closes the connection when the block exits,
            // whether or not an error occurred.
            try (Connection conn = connect()) {
                try {
                    createTable(conn);
                    runWithRetry(conn, Main::incrementCounter);
                    System.out.println("Counter value: " + readCounter(conn));
                } finally {
                    // Drop the shared table even if the work failed.
                    dropTable(conn);
                }
            // SQLException covers connection failures and errors reported by
            // the server.
            } catch (SQLException e) {
                System.err.println("Database error: " + e.getMessage());
                System.exit(1);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                System.err.println("Interrupted while waiting to retry");
                System.exit(1);
            }
        }
    }
    
    ```

=== "C#"

    ```csharp
    /*
     * Ellie's Postgres Cookbook
     * Retrying a transaction after a serialisation failure, using Npgsql.
     *
     * Copyright (c) 2026, pgEdge, Inc.
     * This code is released under the PostgreSQL License.
     */
    
    using System.Data;
    using Npgsql;
    
    const int MaxAttempts = 5;
    
    // Returns true if a SQLSTATE code means "run the transaction again": 40001
    // is a serialisation failure and 40P01 is a deadlock.
    static bool IsRetryable(string? sqlState) => sqlState is "40001" or "40P01";
    
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
    // builder takes care of quoting any special characters.
    static string ConnectionString() =>
        new NpgsqlConnectionStringBuilder
        {
            Host = EnvOr("PGHOST", "localhost"),
            Port = int.Parse(EnvOr("PGPORT", "5432")),
            Database = EnvOr("PGDATABASE", "postgres"),
            Username = EnvOr("PGUSER", "postgres"),
            Password = EnvValue("PGPASSWORD"),
        }.ConnectionString;
    
    // Creates a data source with the settings from the environment. A data
    // source manages a pool of physical connections, and each call to
    // OpenConnectionAsync borrows one from the pool, which also gives the
    // program a second connection when it needs one. A connection runs each
    // statement in its own transaction unless the program begins one.
    static NpgsqlDataSource CreateDataSource() =>
        NpgsqlDataSource.Create(ConnectionString());
    
    // Drops the shared counter table if it exists.
    static async Task DropTableAsync(NpgsqlConnection conn)
    {
        await using var cmd = new NpgsqlCommand(
            "DROP TABLE IF EXISTS cookbook_retry_transactions", conn);
        await cmd.ExecuteNonQueryAsync();
    }
    
    // Creates the shared counter table, with a single row set to zero. The
    // table must be visible to a second connection, so it cannot be
    // temporary; the name is specific to this recipe, and any earlier copy is
    // dropped first.
    static async Task CreateTableAsync(NpgsqlConnection conn)
    {
        await DropTableAsync(conn);
    
        await using var create = new NpgsqlCommand(
            "CREATE TABLE cookbook_retry_transactions " +
            "(id int PRIMARY KEY, value int NOT NULL)", conn);
        await create.ExecuteNonQueryAsync();
    
        await using var insert = new NpgsqlCommand(
            "INSERT INTO cookbook_retry_transactions (id, value) " +
            "VALUES ($1, $2)", conn)
        {
            Parameters = { new() { Value = 1 }, new() { Value = 0 } },
        };
        await insert.ExecuteNonQueryAsync();
    }
    
    // Reads the counter and writes back the value plus one.
    static async Task IncrementCounterAsync(
        NpgsqlDataSource dataSource, NpgsqlConnection conn, int attempt)
    {
        var value = await ReadCounterAsync(conn);
    
        // Simulate another client by updating the row from a second
        // connection, after this transaction has read the row but before it
        // writes. This happens on the first attempt only.
        if (attempt == 1)
        {
            await using var other = await dataSource.OpenConnectionAsync();
            await using var cmd = new NpgsqlCommand(
                "UPDATE cookbook_retry_transactions SET value = value + 1 " +
                "WHERE id = $1", other)
            {
                Parameters = { new() { Value = 1 } },
            };
            await cmd.ExecuteNonQueryAsync();
        }
    
        // Under REPEATABLE READ, updating a row that another transaction
        // changed and committed since this transaction's snapshot was taken
        // fails with SQLSTATE 40001.
        await using var update = new NpgsqlCommand(
            "UPDATE cookbook_retry_transactions SET value = $1 WHERE id = $2",
            conn)
        {
            Parameters = { new() { Value = value + 1 }, new() { Value = 1 } },
        };
        await update.ExecuteNonQueryAsync();
    }
    
    // Returns the current value of the counter.
    static async Task<int> ReadCounterAsync(NpgsqlConnection conn)
    {
        await using var cmd = new NpgsqlCommand(
            "SELECT value FROM cookbook_retry_transactions WHERE id = $1", conn)
        {
            Parameters = { new() { Value = 1 } },
        };
        return (int)(await cmd.ExecuteScalarAsync())!;
    }
    
    // Runs work(conn, attempt) in a REPEATABLE READ transaction, and runs it
    // again if the server reports a serialisation failure or a deadlock.
    static async Task RunWithRetryAsync(
        NpgsqlConnection conn, Func<NpgsqlConnection, int, Task> work)
    {
        for (var attempt = 1; attempt <= MaxAttempts; attempt++)
        {
            try
            {
                // Disposing the transaction without committing rolls it
                // back, so an error from the work leaves nothing behind.
                await using var tx = await conn.BeginTransactionAsync(
                    IsolationLevel.RepeatableRead);
                await work(conn, attempt);
                await tx.CommitAsync();
    
                Console.WriteLine($"Attempt {attempt}: committed");
                return;
            }
            // Any other error, or running out of attempts, is a real failure
            // that the caller must handle, so the filter lets it through.
            catch (PostgresException e)
                when (IsRetryable(e.SqlState) && attempt < MaxAttempts)
            {
                Console.WriteLine(
                    $"Attempt {attempt}: serialisation failure, retrying");
                // A short, growing pause gives the competing transaction time
                // to finish.
                await Task.Delay(50 * attempt);
            }
        }
    }
    
    try
    {
        // await using disposes of the data source, and returns the connection
        // to the pool, when the block exits, whether or not an error occurred.
        await using var dataSource = CreateDataSource();
        await using var conn = await dataSource.OpenConnectionAsync();
    
        try
        {
            await CreateTableAsync(conn);
            await RunWithRetryAsync(
                conn, (c, attempt) => IncrementCounterAsync(dataSource, c, attempt));
            Console.WriteLine($"Counter value: {await ReadCounterAsync(conn)}");
        }
        finally
        {
            // Drop the shared table even if the work failed.
            await DropTableAsync(conn);
        }
    }
    // NpgsqlException covers connection failures; PostgresException, which
    // derives from it, carries errors reported by the server.
    catch (NpgsqlException e)
    {
        Console.Error.WriteLine($"Database error: {e.Message}");
        return 1;
    }
    
    return 0;
    
    ```

=== "Go"

    ```go
    // Ellie's Postgres Cookbook
    // Retrying a transaction after a serialisation failure, using pgx.
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
    	"time"
    
    	"github.com/jackc/pgx/v5"
    	"github.com/jackc/pgx/v5/pgconn"
    )
    
    
    // maxAttempts is the number of times the transaction runs before the
    // program gives up.
    const maxAttempts = 5
    
    // isRetryable reports whether err carries a SQLSTATE code that means "run
    // the transaction again": 40001 is a serialisation failure and 40P01 is a
    // deadlock.
    func isRetryable(err error) bool {
    	var pgErr *pgconn.PgError
    	return errors.As(err, &pgErr) &&
    		(pgErr.Code == "40001" || pgErr.Code == "40P01")
    }
    
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
    // the user name, password, or database name.
    func connString() string {
    	u := url.URL{
    		Scheme: "postgres",
    		Host:   net.JoinHostPort(envOr("PGHOST", "localhost"), envOr("PGPORT", "5432")),
    		Path:   "/" + envOr("PGDATABASE", "postgres"),
    	}
    	if password := os.Getenv("PGPASSWORD"); password != "" {
    		u.User = url.UserPassword(envOr("PGUSER", "postgres"), password)
    	} else {
    		u.User = url.User(envOr("PGUSER", "postgres"))
    	}
    	return u.String()
    }
    
    
    // connect opens a connection with the settings from the environment.
    func connect(ctx context.Context) (*pgx.Conn, error) {
    	conn, err := pgx.Connect(ctx, connString())
    	if err != nil {
    		return nil, fmt.Errorf("connection failed: %w", err)
    	}
    	return conn, nil
    }
    
    
    // dropTable drops the shared counter table if it exists.
    func dropTable(ctx context.Context, conn *pgx.Conn) error {
    	_, err := conn.Exec(ctx, "DROP TABLE IF EXISTS cookbook_retry_transactions")
    	return err
    }
    
    // createTable creates the shared counter table, with a single row set to
    // zero. The table must be visible to a second connection, so it cannot be
    // temporary; the name is specific to this recipe, and any earlier copy is
    // dropped first.
    func createTable(ctx context.Context, conn *pgx.Conn) error {
    	if err := dropTable(ctx, conn); err != nil {
    		return err
    	}
    	_, err := conn.Exec(ctx,
    		"CREATE TABLE cookbook_retry_transactions "+
    			"(id int PRIMARY KEY, value int NOT NULL)")
    	if err != nil {
    		return err
    	}
    	_, err = conn.Exec(ctx,
    		"INSERT INTO cookbook_retry_transactions (id, value) VALUES ($1, $2)",
    		1, 0)
    	return err
    }
    
    
    // incrementCounter reads the counter and writes back the value plus one.
    func incrementCounter(ctx context.Context, tx pgx.Tx, attempt int) error {
    	var value int
    	err := tx.QueryRow(ctx,
    		"SELECT value FROM cookbook_retry_transactions WHERE id = $1",
    		1).Scan(&value)
    	if err != nil {
    		return err
    	}
    
    	// Simulate another client by updating the row from a second
    	// connection, after this transaction has read the row but before it
    	// writes. This happens on the first attempt only.
    	if attempt == 1 {
    		if err := updateFromOtherConnection(ctx); err != nil {
    			return err
    		}
    	}
    
    	// Under REPEATABLE READ, updating a row that another transaction
    	// changed and committed since this transaction's snapshot was taken
    	// fails with SQLSTATE 40001.
    	_, err = tx.Exec(ctx,
    		"UPDATE cookbook_retry_transactions SET value = $1 WHERE id = $2",
    		value+1, 1)
    	return err
    }
    
    // updateFromOtherConnection increments the counter on a second connection,
    // which commits straight away because it has no open transaction.
    func updateFromOtherConnection(ctx context.Context) error {
    	other, err := connect(ctx)
    	if err != nil {
    		return err
    	}
    	defer other.Close(ctx)
    
    	_, err = other.Exec(ctx,
    		"UPDATE cookbook_retry_transactions SET value = value + 1 "+
    			"WHERE id = $1", 1)
    	return err
    }
    
    // readCounter returns the current value of the counter.
    func readCounter(ctx context.Context, conn *pgx.Conn) (int, error) {
    	var value int
    	err := conn.QueryRow(ctx,
    		"SELECT value FROM cookbook_retry_transactions WHERE id = $1",
    		1).Scan(&value)
    	return value, err
    }
    
    
    // runOnce runs work in a single REPEATABLE READ transaction.
    func runOnce(ctx context.Context, conn *pgx.Conn, attempt int,
    	work func(context.Context, pgx.Tx, int) error) error {
    	tx, err := conn.BeginTx(ctx, pgx.TxOptions{IsoLevel: pgx.RepeatableRead})
    	if err != nil {
    		return err
    	}
    	// The deferred rollback undoes the work if it fails; after a
    	// successful commit it does nothing.
    	defer tx.Rollback(ctx)
    
    	if err := work(ctx, tx, attempt); err != nil {
    		return err
    	}
    	return tx.Commit(ctx)
    }
    
    // runWithRetry runs work in a REPEATABLE READ transaction, and runs it
    // again if the server reports a serialisation failure or a deadlock.
    func runWithRetry(ctx context.Context, conn *pgx.Conn,
    	work func(context.Context, pgx.Tx, int) error) error {
    	for attempt := 1; attempt <= maxAttempts; attempt++ {
    		err := runOnce(ctx, conn, attempt, work)
    		if err == nil {
    			fmt.Printf("Attempt %d: committed\n", attempt)
    			return nil
    		}
    
    		// Any other error, or running out of attempts, is a real failure
    		// that the caller must handle.
    		if !isRetryable(err) || attempt == maxAttempts {
    			return err
    		}
    		fmt.Printf("Attempt %d: serialisation failure, retrying\n", attempt)
    		// A short, growing pause gives the competing transaction time to
    		// finish.
    		time.Sleep(time.Duration(attempt) * 50 * time.Millisecond)
    	}
    	return nil
    }
    
    
    // run connects, runs the transaction with retries, and prints the result,
    // returning any error to the caller.
    func run(ctx context.Context) error {
    	conn, err := connect(ctx)
    	if err != nil {
    		return err
    	}
    	// The deferred call closes the connection when run() returns, whether
    	// or not an error occurred.
    	defer conn.Close(ctx)
    
    	// Drop the shared table when the work is done, even if it failed.
    	defer dropTable(ctx, conn)
    
    	if err := createTable(ctx, conn); err != nil {
    		return err
    	}
    	if err := runWithRetry(ctx, conn, incrementCounter); err != nil {
    		return err
    	}
    
    	value, err := readCounter(ctx, conn)
    	if err != nil {
    		return err
    	}
    	fmt.Printf("Counter value: %d\n", value)
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
    // Retrying a transaction after a serialisation failure, using the postgres
    // crate.
    //
    // Copyright (c) 2026, pgEdge, Inc.
    // This code is released under the PostgreSQL License.
    
    use std::env;
    use std::error::Error;
    use std::process::ExitCode;
    use std::thread::sleep;
    use std::time::Duration;
    
    use postgres::error::SqlState;
    use postgres::{Client, Config, IsolationLevel, NoTls, Transaction};
    
    const MAX_ATTEMPTS: u32 = 5;
    
    /// Returns true if the error carries a SQLSTATE code that means "run the
    /// transaction again": a serialisation failure or a deadlock.
    fn is_retryable(error: &postgres::Error) -> bool {
        matches!(
            error.code(),
            Some(code) if *code == SqlState::T_R_SERIALIZATION_FAILURE
                || *code == SqlState::T_R_DEADLOCK_DETECTED
        )
    }
    
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
    fn config() -> Config {
        let mut config = Config::new();
        config
            .host(&env_or("PGHOST", "localhost"))
            .port(env_or("PGPORT", "5432").parse().expect("PGPORT must be a number"))
            .dbname(&env_or("PGDATABASE", "postgres"))
            .user(&env_or("PGUSER", "postgres"));
        if let Some(password) = env_value("PGPASSWORD") {
            config.password(&password);
        }
        config
    }
    
    /// Opens a connection with the settings from the environment. NoTls
    /// disables TLS, which keeps this example free of certificate set-up;
    /// connections over an untrusted network should use TLS. The server runs
    /// each statement in its own transaction unless the program begins one, so
    /// the program decides where each transaction starts and ends.
    fn connect() -> Result<Client, postgres::Error> {
        config().connect(NoTls)
    }
    
    /// Drops the shared counter table if it exists.
    fn drop_table(client: &mut Client) -> Result<(), postgres::Error> {
        client.batch_execute("DROP TABLE IF EXISTS cookbook_retry_transactions")
    }
    
    /// Creates the shared counter table, with a single row set to zero. The
    /// table must be visible to a second connection, so it cannot be
    /// temporary; the name is specific to this recipe, and any earlier copy is
    /// dropped first.
    fn create_table(client: &mut Client) -> Result<(), postgres::Error> {
        drop_table(client)?;
        client.batch_execute(
            "CREATE TABLE cookbook_retry_transactions \
             (id int PRIMARY KEY, value int NOT NULL)",
        )?;
        client.execute(
            "INSERT INTO cookbook_retry_transactions (id, value) VALUES ($1, $2)",
            &[&1_i32, &0_i32],
        )?;
        Ok(())
    }
    
    /// Reads the counter and writes back the value plus one.
    fn increment_counter(
        tx: &mut Transaction,
        attempt: u32,
    ) -> Result<(), postgres::Error> {
        let row = tx.query_one(
            "SELECT value FROM cookbook_retry_transactions WHERE id = $1",
            &[&1_i32],
        )?;
        let value: i32 = row.get(0);
    
        // Simulate another client by updating the row from a second
        // connection, after this transaction has read the row but before it
        // writes. This happens on the first attempt only.
        if attempt == 1 {
            let mut other = connect()?;
            other.execute(
                "UPDATE cookbook_retry_transactions SET value = value + 1 \
                 WHERE id = $1",
                &[&1_i32],
            )?;
        }
    
        // Under REPEATABLE READ, updating a row that another transaction
        // changed and committed since this transaction's snapshot was taken
        // fails with SQLSTATE 40001.
        tx.execute(
            "UPDATE cookbook_retry_transactions SET value = $1 WHERE id = $2",
            &[&(value + 1), &1_i32],
        )?;
        Ok(())
    }
    
    /// Returns the current value of the counter.
    fn read_counter(client: &mut Client) -> Result<i32, postgres::Error> {
        let row = client.query_one(
            "SELECT value FROM cookbook_retry_transactions WHERE id = $1",
            &[&1_i32],
        )?;
        Ok(row.get(0))
    }
    
    /// The type of a function that does the work of one transaction.
    type Work = fn(&mut Transaction, u32) -> Result<(), postgres::Error>;
    
    /// Runs the work in a single REPEATABLE READ transaction. Dropping the
    /// transaction without committing rolls it back, so an error from the
    /// work or from the commit leaves nothing behind.
    fn run_once(
        client: &mut Client,
        attempt: u32,
        work: Work,
    ) -> Result<(), postgres::Error> {
        let mut tx = client
            .build_transaction()
            .isolation_level(IsolationLevel::RepeatableRead)
            .start()?;
        work(&mut tx, attempt)?;
        tx.commit()
    }
    
    /// Runs the work in a REPEATABLE READ transaction, and runs it again if
    /// the server reports a serialisation failure or a deadlock.
    fn run_with_retry(client: &mut Client, work: Work) -> Result<(), postgres::Error> {
        for attempt in 1..=MAX_ATTEMPTS {
            match run_once(client, attempt, work) {
                Ok(()) => {
                    println!("Attempt {attempt}: committed");
                    return Ok(());
                }
                // Any other error, or running out of attempts, is a real
                // failure that the caller must handle.
                Err(e) if !is_retryable(&e) || attempt == MAX_ATTEMPTS => {
                    return Err(e);
                }
                Err(_) => {
                    println!("Attempt {attempt}: serialisation failure, retrying");
                    // A short, growing pause gives the competing transaction
                    // time to finish.
                    sleep(Duration::from_millis(50 * u64::from(attempt)));
                }
            }
        }
        unreachable!("the final attempt returns above")
    }
    
    /// Connects, runs the transaction with retries, and prints the result.
    /// The ? operator returns any error to the caller.
    fn run() -> Result<(), postgres::Error> {
        let mut client = connect()?;
    
        let result = create_table(&mut client)
            .and_then(|()| run_with_retry(&mut client, increment_counter))
            .and_then(|()| read_counter(&mut client));
    
        // Drop the shared table even if the work failed, but report the error
        // from the work first.
        let dropped = drop_table(&mut client);
        let counter = result?;
        dropped?;
        println!("Counter value: {counter}");
    
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
    # Retrying a transaction after a serialisation failure, using the pg gem.
    #
    # Copyright (c) 2026, pgEdge, Inc.
    # This code is released under the PostgreSQL License.
    
    require "pg"
    
    # The SQLSTATE codes that mean "run the transaction again": 40001 is a
    # serialisation failure and 40P01 is a deadlock.
    RETRYABLE = %w[40001 40P01].freeze
    MAX_ATTEMPTS = 5
    
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
      {
        host: env_or("PGHOST", "localhost"),
        port: env_or("PGPORT", "5432"),
        dbname: env_or("PGDATABASE", "postgres"),
        user: env_or("PGUSER", "postgres"),
        password: env_or("PGPASSWORD", nil)
      }.compact
    end
    
    # Opens a connection with the settings from the environment. The server
    # runs each statement in its own transaction unless the program sends
    # BEGIN, so the program decides where each transaction starts and ends.
    def connect
      PG.connect(connection_params)
    end
    
    # Drops the shared counter table if it exists.
    def drop_table(conn)
      conn.exec("DROP TABLE IF EXISTS cookbook_retry_transactions")
    end
    
    # Creates the shared counter table, with a single row set to zero. The
    # table must be visible to a second connection, so it cannot be
    # temporary; the name is specific to this recipe, and any earlier copy is
    # dropped first.
    def create_table(conn)
      drop_table(conn)
      conn.exec("CREATE TABLE cookbook_retry_transactions " \
                "(id int PRIMARY KEY, value int NOT NULL)")
      conn.exec_params(
        "INSERT INTO cookbook_retry_transactions (id, value) VALUES ($1, $2)",
        [1, 0]
      )
    end
    
    # Reads the counter and writes back the value plus one.
    def increment_counter(conn, attempt)
      value = read_counter(conn)
    
      # Simulate another client by updating the row from a second connection,
      # after this transaction has read the row but before it writes. This
      # happens on the first attempt only.
      if attempt == 1
        other = connect
        begin
          other.exec_params(
            "UPDATE cookbook_retry_transactions SET value = value + 1 " \
            "WHERE id = $1",
            [1]
          )
        ensure
          other.close
        end
      end
    
      # Under REPEATABLE READ, updating a row that another transaction
      # changed and committed since this transaction's snapshot was taken
      # fails with SQLSTATE 40001.
      conn.exec_params(
        "UPDATE cookbook_retry_transactions SET value = $1 WHERE id = $2",
        [value + 1, 1]
      )
    end
    
    # Returns the current value of the counter. Results arrive as strings, so
    # the value is converted to an Integer.
    def read_counter(conn)
      conn.exec_params(
        "SELECT value FROM cookbook_retry_transactions WHERE id = $1", [1]
      ).getvalue(0, 0).to_i
    end
    
    # Returns the SQLSTATE code of an error reported by the server, or nil for
    # errors such as a lost connection that have no result.
    def sqlstate(error)
      error.result&.error_field(PG::PG_DIAG_SQLSTATE)
    end
    
    # Yields the connection and the attempt number inside a REPEATABLE READ
    # transaction, and runs the block again if the server reports a
    # serialisation failure or a deadlock.
    def run_with_retry(conn)
      (1..MAX_ATTEMPTS).each do |attempt|
        begin
          conn.exec("BEGIN ISOLATION LEVEL REPEATABLE READ")
          yield conn, attempt
          conn.exec("COMMIT")
          puts "Attempt #{attempt}: committed"
          return
        rescue PG::Error => e
          # End the failed transaction so that the session can start another.
          # If the connection is lost the rollback fails too, and that error
          # must not hide the original one.
          begin
            conn.exec("ROLLBACK")
          rescue PG::Error
            nil
          end
    
          # Any other error, or running out of attempts, is a real failure
          # that the caller must handle.
          raise unless RETRYABLE.include?(sqlstate(e)) && attempt < MAX_ATTEMPTS
    
          puts "Attempt #{attempt}: serialisation failure, retrying"
          # A short, growing pause gives the competing transaction time to
          # finish.
          sleep(0.05 * attempt)
        end
      end
    end
    
    begin
      conn = connect
      begin
        create_table(conn)
        run_with_retry(conn) { |c, attempt| increment_counter(c, attempt) }
        puts "Counter value: #{read_counter(conn)}"
      ensure
        # Drop the shared table even if the work failed.
        drop_table(conn)
      end
    # PG::Error is the base class for every error the gem raises, including
    # connection failures and errors reported by the server.
    rescue PG::Error => e
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
     * Retrying a transaction after a serialisation failure, using libpq.
     *
     * Copyright (c) 2026, pgEdge, Inc.
     * This code is released under the PostgreSQL License.
     */
    
    #include <stdbool.h>
    #include <stdio.h>
    #include <stdlib.h>
    #include <string.h>
    #include <time.h>
    
    #include <libpq-fe.h>
    
    #define MAX_ATTEMPTS 5
    
    /*
     * Return true if a SQLSTATE code means "run the transaction again": 40001
     * is a serialisation failure and 40P01 is a deadlock.
     */
    static bool
    is_retryable(const char *sqlstate)
    {
        return strcmp(sqlstate, "40001") == 0 || strcmp(sqlstate, "40P01") == 0;
    }
    
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
        "host", "port", "dbname", "user", "password", NULL
    };
    
    /* Fill in the value for each keyword from the environment. */
    static void
    read_settings(const char *values[])
    {
        values[0] = env_or("PGHOST", "localhost");
        values[1] = env_or("PGPORT", "5432");
        values[2] = env_or("PGDATABASE", "postgres");
        values[3] = env_or("PGUSER", "postgres");
        values[4] = env_or("PGPASSWORD", NULL);
        values[5] = NULL;
    }
    
    /*
     * Open a connection with the settings from the environment. libpq always
     * returns a connection object, which the caller must check with PQstatus()
     * and release with PQfinish(), even if the connection attempt failed. The
     * server runs each statement in its own transaction unless the program
     * sends BEGIN, so the program decides where each transaction starts and
     * ends.
     */
    static PGconn *
    connect_to_server(void)
    {
        const char *values[sizeof(keywords) / sizeof(keywords[0])];
    
        read_settings(values);
        return PQconnectdbParams(keywords, values, 0);
    }
    
    /*
     * Run a statement with optional text parameters, and return true if it
     * succeeded. The five-character SQLSTATE code of a failure is copied into
     * sqlstate, which is empty if the statement succeeded or the failure has
     * no code (for example, a lost connection). If value is not NULL, the
     * first column of the first row is copied into it, up to size bytes.
     */
    static bool
    run_sql(PGconn *conn, const char *sql, int nparams, const char *const *params,
            char *sqlstate, char *value, size_t size)
    {
        PGresult *res = PQexecParams(conn, sql, nparams, NULL, params, NULL,
                                     NULL, 0);
        ExecStatusType status = PQresultStatus(res);
        bool ok = status == PGRES_COMMAND_OK || status == PGRES_TUPLES_OK;
        const char *code = PQresultErrorField(res, PG_DIAG_SQLSTATE);
    
        snprintf(sqlstate, 6, "%s", code != NULL ? code : "");
        if (ok && value != NULL)
            snprintf(value, size, "%s", PQgetvalue(res, 0, 0));
    
        /* PQclear() frees the result, and accepts NULL. */
        PQclear(res);
        return ok;
    }
    
    /* Drop the shared counter table if it exists. */
    static bool
    drop_table(PGconn *conn)
    {
        char sqlstate[6];
    
        return run_sql(conn, "DROP TABLE IF EXISTS cookbook_retry_transactions",
                       0, NULL, sqlstate, NULL, 0);
    }
    
    /*
     * Create the shared counter table, with a single row set to zero. The
     * table must be visible to a second connection, so it cannot be
     * temporary; the name is specific to this recipe, and any earlier copy is
     * dropped first.
     */
    static bool
    create_table(PGconn *conn)
    {
        const char *params[] = {"1", "0"};
        char sqlstate[6];
    
        return drop_table(conn) &&
            run_sql(conn,
                    "CREATE TABLE cookbook_retry_transactions "
                    "(id int PRIMARY KEY, value int NOT NULL)",
                    0, NULL, sqlstate, NULL, 0) &&
            run_sql(conn,
                    "INSERT INTO cookbook_retry_transactions (id, value) "
                    "VALUES ($1, $2)",
                    2, params, sqlstate, NULL, 0);
    }
    
    /* Read the current value of the counter into *counter. */
    static bool
    read_counter(PGconn *conn, int *counter, char *sqlstate)
    {
        const char *params[] = {"1"};
        char text[32];
    
        if (!run_sql(conn,
                     "SELECT value FROM cookbook_retry_transactions "
                     "WHERE id = $1",
                     1, params, sqlstate, text, sizeof(text)))
            return false;
    
        /* Results arrive as text, so convert the value to a number. */
        *counter = atoi(text);
        return true;
    }
    
    /*
     * Simulate another client by incrementing the counter on a second
     * connection, which commits straight away because it has no open
     * transaction. On failure, the SQLSTATE code and error message of the
     * second connection are copied into the caller's buffers.
     */
    static bool
    update_from_other_connection(char *sqlstate, char *message, size_t size)
    {
        const char *params[] = {"1"};
        PGconn *other = connect_to_server();
        bool ok = PQstatus(other) == CONNECTION_OK &&
            run_sql(other,
                    "UPDATE cookbook_retry_transactions SET value = value + 1 "
                    "WHERE id = $1",
                    1, params, sqlstate, NULL, 0);
    
        if (!ok)
            snprintf(message, size, "%s", PQerrorMessage(other));
        PQfinish(other);
        return ok;
    }
    
    /*
     * Read the counter and write back the value plus one. A failure on conn
     * leaves message empty, because PQerrorMessage(conn) describes it.
     */
    static bool
    increment_counter(PGconn *conn, int attempt, char *sqlstate,
                      char *message, size_t size)
    {
        int counter;
        char next[32];
        const char *params[2];
    
        if (!read_counter(conn, &counter, sqlstate))
            return false;
    
        /*
         * Simulate another client by updating the row from a second
         * connection, after this transaction has read the row but before it
         * writes. This happens on the first attempt only.
         */
        if (attempt == 1 &&
            !update_from_other_connection(sqlstate, message, size))
            return false;
    
        /*
         * Under REPEATABLE READ, updating a row that another transaction
         * changed and committed since this transaction's snapshot was taken
         * fails with SQLSTATE 40001.
         */
        snprintf(next, sizeof(next), "%d", counter + 1);
        params[0] = next;
        params[1] = "1";
        return run_sql(conn,
                       "UPDATE cookbook_retry_transactions SET value = $1 "
                       "WHERE id = $2",
                       2, params, sqlstate, NULL, 0);
    }
    
    /* The type of a function that does the work of one transaction. */
    typedef bool (*work_fn)(PGconn *conn, int attempt, char *sqlstate,
                            char *message, size_t size);
    
    /* Sleep for the given number of milliseconds. */
    static void
    pause_ms(long ms)
    {
        struct timespec ts = {ms / 1000, (ms % 1000) * 1000000L};
    
        nanosleep(&ts, NULL);
    }
    
    /*
     * Run work() in a REPEATABLE READ transaction, and run it again if the
     * server reports a serialisation failure or a deadlock. Return true if a
     * transaction committed. On failure, print the saved error message to
     * stderr, because the caller cannot recover it from the connection.
     */
    static bool
    run_with_retry(PGconn *conn, work_fn work)
    {
        char sqlstate[6];
        char message[512];
    
        for (int attempt = 1; attempt <= MAX_ATTEMPTS; attempt++)
        {
            bool ok;
    
            message[0] = '\0';
            ok = run_sql(conn, "BEGIN ISOLATION LEVEL REPEATABLE READ",
                         0, NULL, sqlstate, NULL, 0) &&
                work(conn, attempt, sqlstate, message, sizeof(message)) &&
                run_sql(conn, "COMMIT", 0, NULL, sqlstate, NULL, 0);
    
            if (ok)
            {
                printf("Attempt %d: committed\n", attempt);
                return true;
            }
    
            /*
             * End the failed transaction so that the session can start
             * another. The error message is kept, because the ROLLBACK
             * would otherwise replace it; the work may already have supplied
             * a message from another connection.
             */
            char ignored[6];
    
            if (message[0] == '\0')
                snprintf(message, sizeof(message), "%s", PQerrorMessage(conn));
            run_sql(conn, "ROLLBACK", 0, NULL, ignored, NULL, 0);
    
            /*
             * Any other error, or running out of attempts, is a real failure
             * that the caller must report.
             */
            if (!is_retryable(sqlstate) || attempt == MAX_ATTEMPTS)
            {
                fprintf(stderr, "Database error: %s", message);
                return false;
            }
    
            printf("Attempt %d: serialisation failure, retrying\n", attempt);
            /* A short, growing pause gives the competing transaction time. */
            pause_ms(50L * attempt);
        }
        return false;
    }
    
    int
    main(void)
    {
        int status = EXIT_FAILURE;
        int counter;
        char sqlstate[6];
        PGconn *conn = connect_to_server();
    
        if (PQstatus(conn) != CONNECTION_OK)
        {
            fprintf(stderr, "Database error: %s", PQerrorMessage(conn));
        }
        else
        {
            if (!create_table(conn))
                fprintf(stderr, "Database error: %s", PQerrorMessage(conn));
            else if (run_with_retry(conn, increment_counter))
            {
                if (read_counter(conn, &counter, sqlstate))
                {
                    printf("Counter value: %d\n", counter);
                    status = EXIT_SUCCESS;
                }
                else
                    fprintf(stderr, "Database error: %s",
                            PQerrorMessage(conn));
            }
    
            /* Drop the shared table even if the work failed. */
            drop_table(conn);
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
