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
    # psycopg 3, with the pre-built binary package that bundles libpq.
    psycopg[binary]>=3.2,<4
    ```

=== "TypeScript"

    ```json
    {
      "name": "statement-timeout",
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
    
    import psycopg
    ```

=== "TypeScript"

    ```typescript
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
    	"github.com/jackc/pgx/v5/pgconn"
    )
    
    ```

=== "Rust"

    ```rust
    use std::env;
    use std::error::Error;
    use std::process::ExitCode;
    
    use postgres::error::SqlState;
    use postgres::{Client, Config, NoTls};
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
variables that libpq and `psql` use, and treat an empty variable as unset,
as the [first recipe](connect_and_query.md) describes. This step also
defines the SQLSTATE code that identifies a cancelled statement. The
following tabs show the configuration for each language:

=== "Python"

    ```python
    # The SQLSTATE code that the server reports when it cancels a statement,
    # whether because of a timeout or because a client asked for the cancel.
    QUERY_CANCELED = "57014"
    
    
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
    // The SQLSTATE code that the server reports when it cancels a statement,
    // whether because of a timeout or because a client asked for the cancel.
    const QUERY_CANCELED = "57014";
    
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
     * The SQLSTATE code that the server reports when it cancels a
     * statement, whether because of a timeout or because a client asked
     * for the cancel.
     */
    static final String QUERY_CANCELED = "57014";
    
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
    // The SQLSTATE code that the server reports when it cancels a statement,
    // whether because of a timeout or because a client asked for the cancel.
    const string QueryCanceled = "57014";
    
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
    // queryCanceled is the SQLSTATE code that the server reports when it
    // cancels a statement, whether because of a timeout or because a client
    // asked for the cancel.
    const queryCanceled = "57014"
    
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
    # The SQLSTATE code that the server reports when it cancels a statement,
    # whether because of a timeout or because a client asked for the cancel.
    QUERY_CANCELED = "57014"
    
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
    /*
     * The SQLSTATE code that the server reports when it cancels a statement,
     * whether because of a timeout or because a client asked for the cancel.
     */
    #define QUERY_CANCELED "57014"
    
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
The connection runs each statement in its own transaction until the
program asks for a transaction explicitly; the Python program sets
autocommit mode to get this behaviour, and the other drivers do this by
default. This matters because a statement that fails inside a transaction
leaves the transaction in a failed state, and the session would then
reject the follow-up query. The following tabs show how each program
opens the connection:

=== "Python"

    ```python
    def connect() -> psycopg.Connection:
        """Opens a connection with the settings from the environment.
    
        Autocommit mode keeps each statement in its own transaction, so a
        cancelled statement does not leave the session in a failed
        transaction.
        """
        return psycopg.connect(**connection_settings(), autocommit=True)
    ```

=== "TypeScript"

    ```typescript
    // Opens a connection with the settings from the environment. The driver
    // runs each statement in its own transaction unless the program sends
    // BEGIN, so a cancelled statement does not leave the session in a failed
    // transaction.
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
     * own transaction, so a cancelled statement does not leave the
     * session in a failed transaction.
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
    // OpenConnectionAsync borrows one from the pool. A connection runs each
    // statement in its own transaction unless the program begins one, so a
    // cancelled statement does not leave the session in a failed transaction.
    static NpgsqlDataSource CreateDataSource() =>
        NpgsqlDataSource.Create(ConnectionString());
    ```

=== "Go"

    ```go
    // connect opens a connection with the settings from the environment. pgx
    // runs each statement in its own transaction unless the program begins
    // one, so a cancelled statement does not leave the session in a failed
    // transaction.
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
    /// a cancelled statement does not leave the session in a failed
    /// transaction.
    fn connect() -> Result<Client, postgres::Error> {
        config().connect(NoTls)
    }
    ```

=== "Ruby"

    ```ruby
    # Opens a connection with the settings from the environment. The server
    # runs each statement in its own transaction unless the program sends
    # BEGIN, so a cancelled statement does not leave the session in a failed
    # transaction.
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
     * sends BEGIN, so a cancelled statement does not leave the session in a
     * failed transaction.
     */
    static PGconn *
    connect_to_server(void)
    {
        const char *values[sizeof(keywords) / sizeof(keywords[0])];
    
        read_settings(values);
        return PQconnectdbParams(keywords, values, 0);
    }
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
    def set_statement_timeout(conn: psycopg.Connection, timeout: str) -> None:
        """Sets the statement timeout for the rest of the session."""
        # SET cannot take a parameter, but set_config() is an ordinary
        # function, so the value can be sent safely. The final argument,
        # false, makes the setting last for the session rather than for the
        # current transaction.
        conn.execute(
            "SELECT set_config('statement_timeout', %s, false)", (timeout,)
        )
    
    
    def sleep_exceeds_timeout(conn: psycopg.Connection) -> bool:
        """Runs a statement that outlasts the timeout, and returns True if
        the server cancelled it."""
        try:
            conn.execute("SELECT pg_sleep(5)")
        except psycopg.Error as e:
            # Only a cancelled statement is expected here; any other error
            # is a real failure, so it is raised again.
            if e.sqlstate != QUERY_CANCELED:
                raise
            return True
        return False
    
    
    def is_usable(conn: psycopg.Connection) -> bool:
        """Returns True if the session can still run a statement."""
        return conn.execute("SELECT 1").fetchone()[0] == 1
    ```

=== "TypeScript"

    ```typescript
    // Sets the statement timeout for the rest of the session.
    async function setStatementTimeout(
      client: pg.Client,
      timeout: string,
    ): Promise<void> {
      // SET cannot take a parameter, but set_config() is an ordinary
      // function, so the value can be sent safely. The final argument, false,
      // makes the setting last for the session rather than for the current
      // transaction.
      await client.query("SELECT set_config('statement_timeout', $1, false)", [
        timeout,
      ]);
    }
    
    // Runs a statement that outlasts the timeout, and returns true if the
    // server cancelled it.
    async function sleepExceedsTimeout(client: pg.Client): Promise<boolean> {
      try {
        await client.query("SELECT pg_sleep(5)");
      } catch (err) {
        // Only a cancelled statement is expected here; any other error is a
        // real failure, so it is thrown again.
        if ((err as pg.DatabaseError).code !== QUERY_CANCELED) {
          throw err;
        }
        return true;
      }
      return false;
    }
    
    // Returns true if the session can still run a statement.
    async function isUsable(client: pg.Client): Promise<boolean> {
      const result = await client.query<{ one: number }>("SELECT 1 AS one");
      return result.rows[0].one === 1;
    }
    ```

=== "Java"

    ```java
    /** Sets the statement timeout for the rest of the session. */
    static void setStatementTimeout(Connection conn, String timeout)
            throws SQLException {
        // SET cannot take a parameter, but set_config() is an ordinary
        // function, so the value can be sent safely. The final argument,
        // false, makes the setting last for the session rather than for
        // the current transaction.
        try (PreparedStatement stmt = conn.prepareStatement(
                "SELECT set_config('statement_timeout', ?, false)")) {
            stmt.setString(1, timeout);
            stmt.execute();
        }
    }
    
    /**
     * Runs a statement that outlasts the timeout, and returns true if the
     * server cancelled it.
     */
    static boolean sleepExceedsTimeout(Connection conn)
            throws SQLException {
        try (Statement stmt = conn.createStatement()) {
            stmt.execute("SELECT pg_sleep(5)");
        } catch (SQLException e) {
            // Only a cancelled statement is expected here; any other
            // error is a real failure, so it is thrown again.
            if (!QUERY_CANCELED.equals(e.getSQLState())) {
                throw e;
            }
            return true;
        }
        return false;
    }
    
    /** Returns true if the session can still run a statement. */
    static boolean isUsable(Connection conn) throws SQLException {
        try (Statement stmt = conn.createStatement();
             ResultSet rs = stmt.executeQuery("SELECT 1")) {
            rs.next();
            return rs.getInt(1) == 1;
        }
    }
    ```

=== "C#"

    ```csharp
    // Sets the statement timeout for the rest of the session.
    static async Task SetStatementTimeoutAsync(NpgsqlConnection conn, string timeout)
    {
        // SET cannot take a parameter, but set_config() is an ordinary
        // function, so the value can be sent safely. The final argument,
        // false, makes the setting last for the session rather than for the
        // current transaction.
        await using var cmd = new NpgsqlCommand(
            "SELECT set_config('statement_timeout', $1, false)", conn)
        {
            Parameters = { new() { Value = timeout } },
        };
        await cmd.ExecuteNonQueryAsync();
    }
    
    // Runs a statement that outlasts the timeout, and returns true if the
    // server cancelled it.
    static async Task<bool> SleepExceedsTimeoutAsync(NpgsqlConnection conn)
    {
        try
        {
            await using var cmd = new NpgsqlCommand("SELECT pg_sleep(5)", conn);
            await cmd.ExecuteNonQueryAsync();
            return false;
        }
        // Only a cancelled statement is expected here; the filter lets any
        // other error through to the caller.
        catch (PostgresException e) when (e.SqlState == QueryCanceled)
        {
            return true;
        }
    }
    
    // Returns true if the session can still run a statement.
    static async Task<bool> IsUsableAsync(NpgsqlConnection conn)
    {
        await using var cmd = new NpgsqlCommand("SELECT 1", conn);
        return (int)(await cmd.ExecuteScalarAsync())! == 1;
    }
    ```

=== "Go"

    ```go
    // setStatementTimeout sets the statement timeout for the rest of the
    // session.
    func setStatementTimeout(ctx context.Context, conn *pgx.Conn, timeout string) error {
    	// SET cannot take a parameter, but set_config() is an ordinary
    	// function, so the value can be sent safely. The final argument,
    	// false, makes the setting last for the session rather than for the
    	// current transaction.
    	_, err := conn.Exec(ctx,
    		"SELECT set_config('statement_timeout', $1, false)", timeout)
    	return err
    }
    
    // sleepExceedsTimeout runs a statement that outlasts the timeout, and
    // returns true if the server cancelled it.
    func sleepExceedsTimeout(ctx context.Context, conn *pgx.Conn) (bool, error) {
    	_, err := conn.Exec(ctx, "SELECT pg_sleep(5)")
    	var pgErr *pgconn.PgError
    	if errors.As(err, &pgErr) && pgErr.Code == queryCanceled {
    		return true, nil
    	}
    	// Only a cancelled statement is expected here; any other error is a
    	// real failure, so it is returned.
    	return false, err
    }
    
    // isUsable returns true if the session can still run a statement.
    func isUsable(ctx context.Context, conn *pgx.Conn) (bool, error) {
    	var one int
    	err := conn.QueryRow(ctx, "SELECT 1").Scan(&one)
    	return one == 1, err
    }
    
    ```

=== "Rust"

    ```rust
    /// Sets the statement timeout for the rest of the session.
    fn set_statement_timeout(
        client: &mut Client,
        timeout: &str,
    ) -> Result<(), postgres::Error> {
        // SET cannot take a parameter, but set_config() is an ordinary
        // function, so the value can be sent safely. The final argument,
        // false, makes the setting last for the session rather than for the
        // current transaction.
        client.execute(
            "SELECT set_config('statement_timeout', $1, false)",
            &[&timeout],
        )?;
        Ok(())
    }
    
    /// Runs a statement that outlasts the timeout, and returns true if the
    /// server cancelled it.
    fn sleep_exceeds_timeout(client: &mut Client) -> Result<bool, postgres::Error> {
        match client.batch_execute("SELECT pg_sleep(5)") {
            Ok(()) => Ok(false),
            Err(e) if e.code() == Some(&SqlState::QUERY_CANCELED) => Ok(true),
            // Only a cancelled statement is expected here; any other error
            // is a real failure, so it is returned.
            Err(e) => Err(e),
        }
    }
    
    /// Returns true if the session can still run a statement.
    fn is_usable(client: &mut Client) -> Result<bool, postgres::Error> {
        let row = client.query_one("SELECT 1", &[])?;
        let one: i32 = row.get(0);
        Ok(one == 1)
    }
    ```

=== "Ruby"

    ```ruby
    # Sets the statement timeout for the rest of the session.
    def set_statement_timeout(conn, timeout)
      # SET cannot take a parameter, but set_config() is an ordinary
      # function, so the value can be sent safely. The final argument, false,
      # makes the setting last for the session rather than for the current
      # transaction.
      conn.exec_params("SELECT set_config('statement_timeout', $1, false)",
                       [timeout])
    end
    
    # Runs a statement that outlasts the timeout, and returns true if the
    # server cancelled it.
    def sleep_exceeds_timeout?(conn)
      conn.exec("SELECT pg_sleep(5)")
      false
    rescue PG::Error => e
      # Only a cancelled statement is expected here; any other error is a
      # real failure, so it is raised again.
      raise unless e.result&.error_field(PG::PG_DIAG_SQLSTATE) == QUERY_CANCELED
    
      true
    end
    
    # Returns true if the session can still run a statement.
    def usable?(conn)
      conn.exec("SELECT 1").getvalue(0, 0).to_i == 1
    end
    ```

=== "C"

    ```c
    /*
     * Set the statement timeout for the rest of the session, and return true
     * on success.
     */
    static bool
    set_statement_timeout(PGconn *conn, const char *timeout)
    {
        /*
         * SET cannot take a parameter, but set_config() is an ordinary
         * function, so the value can be sent safely. The final argument,
         * false, makes the setting last for the session rather than for the
         * current transaction.
         */
        const char *params[] = {timeout};
        PGresult *res = PQexecParams(conn,
                                     "SELECT set_config('statement_timeout', "
                                     "$1, false)",
                                     1, NULL, params, NULL, NULL, 0);
        bool ok = PQresultStatus(res) == PGRES_TUPLES_OK;
    
        PQclear(res);
        return ok;
    }
    
    /*
     * Run a statement that outlasts the timeout. Return true if the statement
     * was cancelled, which is the expected outcome. Return false for any other
     * result, in which case *failed is set if the statement raised an error.
     */
    static bool
    sleep_exceeds_timeout(PGconn *conn, bool *failed)
    {
        PGresult *res = PQexec(conn, "SELECT pg_sleep(5)");
        const char *code = PQresultErrorField(res, PG_DIAG_SQLSTATE);
        bool cancelled = code != NULL && strcmp(code, QUERY_CANCELED) == 0;
    
        /*
         * Only a cancelled statement is expected here; any other error is a
         * real failure, which the caller reports.
         */
        *failed = PQresultStatus(res) != PGRES_TUPLES_OK && !cancelled;
    
        PQclear(res);
        return cancelled;
    }
    
    /* Return true if the session can still run a statement. */
    static bool
    is_usable(PGconn *conn)
    {
        PGresult *res = PQexec(conn, "SELECT 1");
        bool usable = PQresultStatus(res) == PGRES_TUPLES_OK &&
            strcmp(PQgetvalue(res, 0, 0), "1") == 0;
    
        PQclear(res);
        return usable;
    }
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
    def main() -> int:
        try:
            # The with block closes the connection when it exits, whether or
            # not an error occurred.
            with connect() as conn:
                set_statement_timeout(conn, "100ms")
                if sleep_exceeds_timeout(conn):
                    print("Query cancelled after exceeding the statement "
                          "timeout")
                print(f"Connection still usable: {str(is_usable(conn)).lower()}")
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
        await setStatementTimeout(client, "100ms");
        if (await sleepExceedsTimeout(client)) {
          console.log("Query cancelled after exceeding the statement timeout");
        }
        console.log(`Connection still usable: ${await isUsable(client)}`);
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
            setStatementTimeout(conn, "100ms");
            if (sleepExceedsTimeout(conn)) {
                System.out.println(
                    "Query cancelled after exceeding the statement timeout");
            }
            System.out.println("Connection still usable: " + isUsable(conn));
        // SQLException covers connection failures and errors reported by
        // the server.
        } catch (SQLException e) {
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
    
        await SetStatementTimeoutAsync(conn, "100ms");
        if (await SleepExceedsTimeoutAsync(conn))
        {
            Console.WriteLine("Query cancelled after exceeding the statement timeout");
        }
    
        var usable = await IsUsableAsync(conn);
        Console.WriteLine($"Connection still usable: {usable.ToString().ToLowerInvariant()}");
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
    // run connects, sets the timeout, runs the slow statement, and prints the
    // results, returning any error to the caller.
    func run(ctx context.Context) error {
    	conn, err := connect(ctx)
    	if err != nil {
    		return err
    	}
    	// The deferred call closes the connection when run() returns, whether
    	// or not an error occurred.
    	defer conn.Close(ctx)
    
    	if err := setStatementTimeout(ctx, conn, "100ms"); err != nil {
    		return err
    	}
    
    	cancelled, err := sleepExceedsTimeout(ctx, conn)
    	if err != nil {
    		return err
    	}
    	if cancelled {
    		fmt.Println("Query cancelled after exceeding the statement timeout")
    	}
    
    	usable, err := isUsable(ctx, conn)
    	if err != nil {
    		return err
    	}
    	fmt.Printf("Connection still usable: %t\n", usable)
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
    /// Connects, sets the timeout, runs the slow statement, and prints the
    /// results. The ? operator returns any error to the caller.
    fn run() -> Result<(), postgres::Error> {
        let mut client = connect()?;
        set_statement_timeout(&mut client, "100ms")?;
    
        if sleep_exceeds_timeout(&mut client)? {
            println!("Query cancelled after exceeding the statement timeout");
        }
        println!("Connection still usable: {}", is_usable(&mut client)?);
    
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
      set_statement_timeout(conn, "100ms")
      if sleep_exceeds_timeout?(conn)
        puts "Query cancelled after exceeding the statement timeout"
      end
      puts "Connection still usable: #{usable?(conn)}"
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
        bool failed;
        PGconn *conn = connect_to_server();
    
        if (PQstatus(conn) != CONNECTION_OK ||
            !set_statement_timeout(conn, "100ms"))
        {
            fprintf(stderr, "Database error: %s", PQerrorMessage(conn));
        }
        else
        {
            if (sleep_exceeds_timeout(conn, &failed))
                printf("Query cancelled after exceeding the statement "
                       "timeout\n");
    
            if (failed)
                fprintf(stderr, "Database error: %s", PQerrorMessage(conn));
            else
            {
                printf("Connection still usable: %s\n",
                       is_usable(conn) ? "true" : "false");
                status = EXIT_SUCCESS;
            }
        }
    
        /* Close the connection whether or not an error occurred. */
        PQfinish(conn);
        return status;
    }
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
    """
    Ellie's Postgres Cookbook
    Setting a server-side statement timeout, using psycopg 3.
    
    Copyright (c) 2026, pgEdge, Inc.
    This code is released under the PostgreSQL License.
    """
    
    import os
    import sys
    
    import psycopg
    
    
    # The SQLSTATE code that the server reports when it cancels a statement,
    # whether because of a timeout or because a client asked for the cancel.
    QUERY_CANCELED = "57014"
    
    
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
    
        Autocommit mode keeps each statement in its own transaction, so a
        cancelled statement does not leave the session in a failed
        transaction.
        """
        return psycopg.connect(**connection_settings(), autocommit=True)
    
    
    def set_statement_timeout(conn: psycopg.Connection, timeout: str) -> None:
        """Sets the statement timeout for the rest of the session."""
        # SET cannot take a parameter, but set_config() is an ordinary
        # function, so the value can be sent safely. The final argument,
        # false, makes the setting last for the session rather than for the
        # current transaction.
        conn.execute(
            "SELECT set_config('statement_timeout', %s, false)", (timeout,)
        )
    
    
    def sleep_exceeds_timeout(conn: psycopg.Connection) -> bool:
        """Runs a statement that outlasts the timeout, and returns True if
        the server cancelled it."""
        try:
            conn.execute("SELECT pg_sleep(5)")
        except psycopg.Error as e:
            # Only a cancelled statement is expected here; any other error
            # is a real failure, so it is raised again.
            if e.sqlstate != QUERY_CANCELED:
                raise
            return True
        return False
    
    
    def is_usable(conn: psycopg.Connection) -> bool:
        """Returns True if the session can still run a statement."""
        return conn.execute("SELECT 1").fetchone()[0] == 1
    
    
    def main() -> int:
        try:
            # The with block closes the connection when it exits, whether or
            # not an error occurred.
            with connect() as conn:
                set_statement_timeout(conn, "100ms")
                if sleep_exceeds_timeout(conn):
                    print("Query cancelled after exceeding the statement "
                          "timeout")
                print(f"Connection still usable: {str(is_usable(conn)).lower()}")
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
     * Setting a server-side statement timeout, using node-postgres.
     *
     * Copyright (c) 2026, pgEdge, Inc.
     * This code is released under the PostgreSQL License.
     */
    
    import pg from "pg";
    
    // The SQLSTATE code that the server reports when it cancels a statement,
    // whether because of a timeout or because a client asked for the cancel.
    const QUERY_CANCELED = "57014";
    
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
    // BEGIN, so a cancelled statement does not leave the session in a failed
    // transaction.
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
    
    // Sets the statement timeout for the rest of the session.
    async function setStatementTimeout(
      client: pg.Client,
      timeout: string,
    ): Promise<void> {
      // SET cannot take a parameter, but set_config() is an ordinary
      // function, so the value can be sent safely. The final argument, false,
      // makes the setting last for the session rather than for the current
      // transaction.
      await client.query("SELECT set_config('statement_timeout', $1, false)", [
        timeout,
      ]);
    }
    
    // Runs a statement that outlasts the timeout, and returns true if the
    // server cancelled it.
    async function sleepExceedsTimeout(client: pg.Client): Promise<boolean> {
      try {
        await client.query("SELECT pg_sleep(5)");
      } catch (err) {
        // Only a cancelled statement is expected here; any other error is a
        // real failure, so it is thrown again.
        if ((err as pg.DatabaseError).code !== QUERY_CANCELED) {
          throw err;
        }
        return true;
      }
      return false;
    }
    
    // Returns true if the session can still run a statement.
    async function isUsable(client: pg.Client): Promise<boolean> {
      const result = await client.query<{ one: number }>("SELECT 1 AS one");
      return result.rows[0].one === 1;
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
        await setStatementTimeout(client, "100ms");
        if (await sleepExceedsTimeout(client)) {
          console.log("Query cancelled after exceeding the statement timeout");
        }
        console.log(`Connection still usable: ${await isUsable(client)}`);
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
     * Setting a server-side statement timeout, using JDBC and the PostgreSQL
     * JDBC driver (pgJDBC).
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
    
    public class Main {
    
        /**
         * The SQLSTATE code that the server reports when it cancels a
         * statement, whether because of a timeout or because a client asked
         * for the cancel.
         */
        static final String QUERY_CANCELED = "57014";
    
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
         * own transaction, so a cancelled statement does not leave the
         * session in a failed transaction.
         */
        static Connection connect() throws SQLException {
            return DriverManager.getConnection(
                    connectionUrl(), connectionProperties());
        }
    
        /** Sets the statement timeout for the rest of the session. */
        static void setStatementTimeout(Connection conn, String timeout)
                throws SQLException {
            // SET cannot take a parameter, but set_config() is an ordinary
            // function, so the value can be sent safely. The final argument,
            // false, makes the setting last for the session rather than for
            // the current transaction.
            try (PreparedStatement stmt = conn.prepareStatement(
                    "SELECT set_config('statement_timeout', ?, false)")) {
                stmt.setString(1, timeout);
                stmt.execute();
            }
        }
    
        /**
         * Runs a statement that outlasts the timeout, and returns true if the
         * server cancelled it.
         */
        static boolean sleepExceedsTimeout(Connection conn)
                throws SQLException {
            try (Statement stmt = conn.createStatement()) {
                stmt.execute("SELECT pg_sleep(5)");
            } catch (SQLException e) {
                // Only a cancelled statement is expected here; any other
                // error is a real failure, so it is thrown again.
                if (!QUERY_CANCELED.equals(e.getSQLState())) {
                    throw e;
                }
                return true;
            }
            return false;
        }
    
        /** Returns true if the session can still run a statement. */
        static boolean isUsable(Connection conn) throws SQLException {
            try (Statement stmt = conn.createStatement();
                 ResultSet rs = stmt.executeQuery("SELECT 1")) {
                rs.next();
                return rs.getInt(1) == 1;
            }
        }
    
        public static void main(String[] args) {
            // try-with-resources closes the connection when the block exits,
            // whether or not an error occurred.
            try (Connection conn = connect()) {
                setStatementTimeout(conn, "100ms");
                if (sleepExceedsTimeout(conn)) {
                    System.out.println(
                        "Query cancelled after exceeding the statement timeout");
                }
                System.out.println("Connection still usable: " + isUsable(conn));
            // SQLException covers connection failures and errors reported by
            // the server.
            } catch (SQLException e) {
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
     * Setting a server-side statement timeout, using Npgsql.
     *
     * Copyright (c) 2026, pgEdge, Inc.
     * This code is released under the PostgreSQL License.
     */
    
    using Npgsql;
    
    // The SQLSTATE code that the server reports when it cancels a statement,
    // whether because of a timeout or because a client asked for the cancel.
    const string QueryCanceled = "57014";
    
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
    // OpenConnectionAsync borrows one from the pool. A connection runs each
    // statement in its own transaction unless the program begins one, so a
    // cancelled statement does not leave the session in a failed transaction.
    static NpgsqlDataSource CreateDataSource() =>
        NpgsqlDataSource.Create(ConnectionString());
    
    // Sets the statement timeout for the rest of the session.
    static async Task SetStatementTimeoutAsync(NpgsqlConnection conn, string timeout)
    {
        // SET cannot take a parameter, but set_config() is an ordinary
        // function, so the value can be sent safely. The final argument,
        // false, makes the setting last for the session rather than for the
        // current transaction.
        await using var cmd = new NpgsqlCommand(
            "SELECT set_config('statement_timeout', $1, false)", conn)
        {
            Parameters = { new() { Value = timeout } },
        };
        await cmd.ExecuteNonQueryAsync();
    }
    
    // Runs a statement that outlasts the timeout, and returns true if the
    // server cancelled it.
    static async Task<bool> SleepExceedsTimeoutAsync(NpgsqlConnection conn)
    {
        try
        {
            await using var cmd = new NpgsqlCommand("SELECT pg_sleep(5)", conn);
            await cmd.ExecuteNonQueryAsync();
            return false;
        }
        // Only a cancelled statement is expected here; the filter lets any
        // other error through to the caller.
        catch (PostgresException e) when (e.SqlState == QueryCanceled)
        {
            return true;
        }
    }
    
    // Returns true if the session can still run a statement.
    static async Task<bool> IsUsableAsync(NpgsqlConnection conn)
    {
        await using var cmd = new NpgsqlCommand("SELECT 1", conn);
        return (int)(await cmd.ExecuteScalarAsync())! == 1;
    }
    
    try
    {
        // await using disposes of the data source, and returns the connection
        // to the pool, when the block exits, whether or not an error occurred.
        await using var dataSource = CreateDataSource();
        await using var conn = await dataSource.OpenConnectionAsync();
    
        await SetStatementTimeoutAsync(conn, "100ms");
        if (await SleepExceedsTimeoutAsync(conn))
        {
            Console.WriteLine("Query cancelled after exceeding the statement timeout");
        }
    
        var usable = await IsUsableAsync(conn);
        Console.WriteLine($"Connection still usable: {usable.ToString().ToLowerInvariant()}");
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
    // Setting a server-side statement timeout, using pgx.
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
    	"github.com/jackc/pgx/v5/pgconn"
    )
    
    
    // queryCanceled is the SQLSTATE code that the server reports when it
    // cancels a statement, whether because of a timeout or because a client
    // asked for the cancel.
    const queryCanceled = "57014"
    
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
    
    
    // connect opens a connection with the settings from the environment. pgx
    // runs each statement in its own transaction unless the program begins
    // one, so a cancelled statement does not leave the session in a failed
    // transaction.
    func connect(ctx context.Context) (*pgx.Conn, error) {
    	conn, err := pgx.Connect(ctx, connString())
    	if err != nil {
    		return nil, fmt.Errorf("connection failed: %w", err)
    	}
    	return conn, nil
    }
    
    
    // setStatementTimeout sets the statement timeout for the rest of the
    // session.
    func setStatementTimeout(ctx context.Context, conn *pgx.Conn, timeout string) error {
    	// SET cannot take a parameter, but set_config() is an ordinary
    	// function, so the value can be sent safely. The final argument,
    	// false, makes the setting last for the session rather than for the
    	// current transaction.
    	_, err := conn.Exec(ctx,
    		"SELECT set_config('statement_timeout', $1, false)", timeout)
    	return err
    }
    
    // sleepExceedsTimeout runs a statement that outlasts the timeout, and
    // returns true if the server cancelled it.
    func sleepExceedsTimeout(ctx context.Context, conn *pgx.Conn) (bool, error) {
    	_, err := conn.Exec(ctx, "SELECT pg_sleep(5)")
    	var pgErr *pgconn.PgError
    	if errors.As(err, &pgErr) && pgErr.Code == queryCanceled {
    		return true, nil
    	}
    	// Only a cancelled statement is expected here; any other error is a
    	// real failure, so it is returned.
    	return false, err
    }
    
    // isUsable returns true if the session can still run a statement.
    func isUsable(ctx context.Context, conn *pgx.Conn) (bool, error) {
    	var one int
    	err := conn.QueryRow(ctx, "SELECT 1").Scan(&one)
    	return one == 1, err
    }
    
    
    // run connects, sets the timeout, runs the slow statement, and prints the
    // results, returning any error to the caller.
    func run(ctx context.Context) error {
    	conn, err := connect(ctx)
    	if err != nil {
    		return err
    	}
    	// The deferred call closes the connection when run() returns, whether
    	// or not an error occurred.
    	defer conn.Close(ctx)
    
    	if err := setStatementTimeout(ctx, conn, "100ms"); err != nil {
    		return err
    	}
    
    	cancelled, err := sleepExceedsTimeout(ctx, conn)
    	if err != nil {
    		return err
    	}
    	if cancelled {
    		fmt.Println("Query cancelled after exceeding the statement timeout")
    	}
    
    	usable, err := isUsable(ctx, conn)
    	if err != nil {
    		return err
    	}
    	fmt.Printf("Connection still usable: %t\n", usable)
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
    // Setting a server-side statement timeout, using the postgres crate.
    //
    // Copyright (c) 2026, pgEdge, Inc.
    // This code is released under the PostgreSQL License.
    
    use std::env;
    use std::error::Error;
    use std::process::ExitCode;
    
    use postgres::error::SqlState;
    use postgres::{Client, Config, NoTls};
    
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
    /// a cancelled statement does not leave the session in a failed
    /// transaction.
    fn connect() -> Result<Client, postgres::Error> {
        config().connect(NoTls)
    }
    
    /// Sets the statement timeout for the rest of the session.
    fn set_statement_timeout(
        client: &mut Client,
        timeout: &str,
    ) -> Result<(), postgres::Error> {
        // SET cannot take a parameter, but set_config() is an ordinary
        // function, so the value can be sent safely. The final argument,
        // false, makes the setting last for the session rather than for the
        // current transaction.
        client.execute(
            "SELECT set_config('statement_timeout', $1, false)",
            &[&timeout],
        )?;
        Ok(())
    }
    
    /// Runs a statement that outlasts the timeout, and returns true if the
    /// server cancelled it.
    fn sleep_exceeds_timeout(client: &mut Client) -> Result<bool, postgres::Error> {
        match client.batch_execute("SELECT pg_sleep(5)") {
            Ok(()) => Ok(false),
            Err(e) if e.code() == Some(&SqlState::QUERY_CANCELED) => Ok(true),
            // Only a cancelled statement is expected here; any other error
            // is a real failure, so it is returned.
            Err(e) => Err(e),
        }
    }
    
    /// Returns true if the session can still run a statement.
    fn is_usable(client: &mut Client) -> Result<bool, postgres::Error> {
        let row = client.query_one("SELECT 1", &[])?;
        let one: i32 = row.get(0);
        Ok(one == 1)
    }
    
    /// Connects, sets the timeout, runs the slow statement, and prints the
    /// results. The ? operator returns any error to the caller.
    fn run() -> Result<(), postgres::Error> {
        let mut client = connect()?;
        set_statement_timeout(&mut client, "100ms")?;
    
        if sleep_exceeds_timeout(&mut client)? {
            println!("Query cancelled after exceeding the statement timeout");
        }
        println!("Connection still usable: {}", is_usable(&mut client)?);
    
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
    # Setting a server-side statement timeout, using the pg gem.
    #
    # Copyright (c) 2026, pgEdge, Inc.
    # This code is released under the PostgreSQL License.
    
    require "pg"
    
    # The SQLSTATE code that the server reports when it cancels a statement,
    # whether because of a timeout or because a client asked for the cancel.
    QUERY_CANCELED = "57014"
    
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
    # BEGIN, so a cancelled statement does not leave the session in a failed
    # transaction.
    def connect
      PG.connect(connection_params)
    end
    
    # Sets the statement timeout for the rest of the session.
    def set_statement_timeout(conn, timeout)
      # SET cannot take a parameter, but set_config() is an ordinary
      # function, so the value can be sent safely. The final argument, false,
      # makes the setting last for the session rather than for the current
      # transaction.
      conn.exec_params("SELECT set_config('statement_timeout', $1, false)",
                       [timeout])
    end
    
    # Runs a statement that outlasts the timeout, and returns true if the
    # server cancelled it.
    def sleep_exceeds_timeout?(conn)
      conn.exec("SELECT pg_sleep(5)")
      false
    rescue PG::Error => e
      # Only a cancelled statement is expected here; any other error is a
      # real failure, so it is raised again.
      raise unless e.result&.error_field(PG::PG_DIAG_SQLSTATE) == QUERY_CANCELED
    
      true
    end
    
    # Returns true if the session can still run a statement.
    def usable?(conn)
      conn.exec("SELECT 1").getvalue(0, 0).to_i == 1
    end
    
    begin
      conn = connect
      set_statement_timeout(conn, "100ms")
      if sleep_exceeds_timeout?(conn)
        puts "Query cancelled after exceeding the statement timeout"
      end
      puts "Connection still usable: #{usable?(conn)}"
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
     * Setting a server-side statement timeout, using libpq.
     *
     * Copyright (c) 2026, pgEdge, Inc.
     * This code is released under the PostgreSQL License.
     */
    
    #include <stdbool.h>
    #include <stdio.h>
    #include <stdlib.h>
    #include <string.h>
    
    #include <libpq-fe.h>
    
    /*
     * The SQLSTATE code that the server reports when it cancels a statement,
     * whether because of a timeout or because a client asked for the cancel.
     */
    #define QUERY_CANCELED "57014"
    
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
     * sends BEGIN, so a cancelled statement does not leave the session in a
     * failed transaction.
     */
    static PGconn *
    connect_to_server(void)
    {
        const char *values[sizeof(keywords) / sizeof(keywords[0])];
    
        read_settings(values);
        return PQconnectdbParams(keywords, values, 0);
    }
    
    /*
     * Set the statement timeout for the rest of the session, and return true
     * on success.
     */
    static bool
    set_statement_timeout(PGconn *conn, const char *timeout)
    {
        /*
         * SET cannot take a parameter, but set_config() is an ordinary
         * function, so the value can be sent safely. The final argument,
         * false, makes the setting last for the session rather than for the
         * current transaction.
         */
        const char *params[] = {timeout};
        PGresult *res = PQexecParams(conn,
                                     "SELECT set_config('statement_timeout', "
                                     "$1, false)",
                                     1, NULL, params, NULL, NULL, 0);
        bool ok = PQresultStatus(res) == PGRES_TUPLES_OK;
    
        PQclear(res);
        return ok;
    }
    
    /*
     * Run a statement that outlasts the timeout. Return true if the statement
     * was cancelled, which is the expected outcome. Return false for any other
     * result, in which case *failed is set if the statement raised an error.
     */
    static bool
    sleep_exceeds_timeout(PGconn *conn, bool *failed)
    {
        PGresult *res = PQexec(conn, "SELECT pg_sleep(5)");
        const char *code = PQresultErrorField(res, PG_DIAG_SQLSTATE);
        bool cancelled = code != NULL && strcmp(code, QUERY_CANCELED) == 0;
    
        /*
         * Only a cancelled statement is expected here; any other error is a
         * real failure, which the caller reports.
         */
        *failed = PQresultStatus(res) != PGRES_TUPLES_OK && !cancelled;
    
        PQclear(res);
        return cancelled;
    }
    
    /* Return true if the session can still run a statement. */
    static bool
    is_usable(PGconn *conn)
    {
        PGresult *res = PQexec(conn, "SELECT 1");
        bool usable = PQresultStatus(res) == PGRES_TUPLES_OK &&
            strcmp(PQgetvalue(res, 0, 0), "1") == 0;
    
        PQclear(res);
        return usable;
    }
    
    int
    main(void)
    {
        int status = EXIT_FAILURE;
        bool failed;
        PGconn *conn = connect_to_server();
    
        if (PQstatus(conn) != CONNECTION_OK ||
            !set_statement_timeout(conn, "100ms"))
        {
            fprintf(stderr, "Database error: %s", PQerrorMessage(conn));
        }
        else
        {
            if (sleep_exceeds_timeout(conn, &failed))
                printf("Query cancelled after exceeding the statement "
                       "timeout\n");
    
            if (failed)
                fprintf(stderr, "Database error: %s", PQerrorMessage(conn));
            else
            {
                printf("Connection still usable: %s\n",
                       is_usable(conn) ? "true" : "false");
                status = EXIT_SUCCESS;
            }
        }
    
        /* Close the connection whether or not an error occurred. */
        PQfinish(conn);
        return status;
    }
    
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
