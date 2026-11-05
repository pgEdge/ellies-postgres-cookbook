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

Two details matter when writing the code. First, a notification is delivered
when the sending transaction commits, and a listener hears only notifications
sent after its `LISTEN` took effect, so each example runs `LISTEN` and `NOTIFY`
outside an explicit transaction, where each statement commits as soon as it
completes. The listener is therefore subscribed before the sender sends.
Second, a notification reaches the program only when the driver reads from the
connection, and each driver offers its own way of doing so. Some drivers read
when the program asks them to wait for a notification, and node-postgres reads
in the background and emits an event when a notification arrives.

## Preparing the Ingredients

This recipe uses the same drivers as the
[first recipe](connect_and_query.md), and the C and Ruby examples need
libpq, as before. The following tabs show the dependency declaration from
each example project:

=== "Python"

    ```text
    # psycopg 3, with the pre-built binary package that bundles libpq.
    psycopg[binary]>=3.2,<4
    ```

=== "TypeScript"

    ```json
    {
      "name": "listen-notify",
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
    import java.sql.SQLException;
    import java.sql.Statement;
    import java.util.Properties;
    
    import org.postgresql.PGConnection;
    import org.postgresql.PGNotification;
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
    use std::time::Duration;
    
    use postgres::fallible_iterator::FallibleIterator;
    use postgres::{Client, Config, NoTls, Notification};
    ```

=== "Ruby"

    ```ruby
    require "pg"
    ```

=== "C"

    ```c
    #include <errno.h>
    #include <poll.h>
    #include <stdbool.h>
    #include <stdio.h>
    #include <stdlib.h>
    #include <string.h>
    #include <time.h>
    
    #include <libpq-fe.h>
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
    CHANNEL = "cookbook_listen_notify"
    TIMEOUT_SECONDS = 5
    
    
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
    const CHANNEL = "cookbook_listen_notify";
    const TIMEOUT_MS = 5000;
    
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
    static final String CHANNEL = "cookbook_listen_notify";
    static final int TIMEOUT_MILLIS = 5000;
    
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
    const string Channel = "cookbook_listen_notify";
    var timeout = TimeSpan.FromSeconds(5);
    
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
    const (
    	channel = "cookbook_listen_notify"
    	timeout = 5 * time.Second
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
    const CHANNEL: &str = "cookbook_listen_notify";
    const TIMEOUT: Duration = Duration::from_secs(5);
    
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
    CHANNEL = "cookbook_listen_notify"
    TIMEOUT_SECONDS = 5
    
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
    #define CHANNEL "cookbook_listen_notify"
    #define TIMEOUT_MS 5000
    
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
    def connect() -> psycopg.Connection:
        """Opens a connection with the settings from the environment.
    
        Autocommit mode matters here: without it, psycopg would open a
        transaction around LISTEN, and the subscription would not take effect
        until that transaction committed. A transaction around NOTIFY would
        likewise hold the notification back until the commit.
        """
        return psycopg.connect(**connection_settings(), autocommit=True)
    ```

=== "TypeScript"

    ```typescript
    // Opens a connection with the settings from the environment. node-postgres
    // runs each query in autocommit mode unless the program sends BEGIN, so
    // LISTEN takes effect, and NOTIFY is delivered, as soon as it completes.
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
     * Opens a connection with the settings from the environment. JDBC
     * connections start in autocommit mode, so LISTEN takes effect, and
     * NOTIFY is delivered, as soon as each statement completes.
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
    // OpenConnectionAsync borrows one from the pool, so the two calls below
    // get two separate connections. Npgsql runs each command in autocommit
    // mode unless the program starts a transaction, so LISTEN takes effect,
    // and NOTIFY is delivered, as soon as the command completes.
    static NpgsqlDataSource CreateDataSource() =>
        NpgsqlDataSource.Create(ConnectionString());
    ```

=== "Go"

    ```go
    // connect opens a connection with the settings from the environment. pgx
    // runs each statement in autocommit mode unless the program begins a
    // transaction, so LISTEN takes effect, and NOTIFY is delivered, as soon as
    // the statement completes.
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
    /// connections over an untrusted network should use TLS. The client runs
    /// each statement in autocommit mode unless the program begins a
    /// transaction, so LISTEN takes effect, and NOTIFY is delivered, as soon
    /// as the statement completes.
    fn connect() -> Result<Client, postgres::Error> {
        config().connect(NoTls)
    }
    ```

=== "Ruby"

    ```ruby
    # Opens a connection with the settings from the environment. libpq runs
    # each statement in autocommit mode unless the program sends BEGIN, so
    # LISTEN takes effect, and NOTIFY is delivered, as soon as the statement
    # completes.
    def connect
      PG.connect(connection_params)
    end
    ```

=== "C"

    ```c
    /*
     * Open a connection with the settings from the environment. libpq always
     * returns a connection object, which the caller must check with PQstatus()
     * and release with PQfinish(), even if the connection attempt failed.
     * libpq runs each command in autocommit mode unless the program sends
     * BEGIN, so LISTEN takes effect, and NOTIFY is delivered, as soon as the
     * command completes.
     */
    static PGconn *
    connect_to_server(void)
    {
        const char *values[sizeof(keywords) / sizeof(keywords[0])];
    
        read_settings(values);
        return PQconnectdbParams(keywords, values, 0);
    }
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
    def listen(conn: psycopg.Connection, channel: str) -> None:
        """Subscribes the connection to a channel."""
        # LISTEN takes an identifier rather than a value, so it cannot use a
        # parameter; psycopg.sql.Identifier quotes the name safely.
        conn.execute(psycopg.sql.SQL("LISTEN {}").format(
            psycopg.sql.Identifier(channel)))
    ```

=== "TypeScript"

    ```typescript
    // Subscribes the connection to a channel.
    async function listen(client: pg.Client, channel: string): Promise<void> {
      // LISTEN takes an identifier rather than a value, so it cannot use a
      // parameter; escapeIdentifier quotes the name safely.
      await client.query(`LISTEN ${client.escapeIdentifier(channel)}`);
    }
    ```

=== "Java"

    ```java
    /** Subscribes the connection to a channel. */
    static void listen(Connection conn, String channel)
            throws SQLException {
        try (Statement stmt = conn.createStatement()) {
            // LISTEN takes an identifier rather than a value, so it cannot
            // use a parameter; enquoteIdentifier quotes the name safely.
            stmt.execute("LISTEN " + stmt.enquoteIdentifier(channel, true));
        }
    }
    ```

=== "C#"

    ```csharp
    // Subscribes the connection to a channel.
    static async Task ListenAsync(NpgsqlConnection conn, string channel)
    {
        // LISTEN takes an identifier rather than a value, so it cannot use a
        // parameter; QuoteIdentifier quotes the name safely.
        await using var cmd = new NpgsqlCommand(
            $"LISTEN {new NpgsqlCommandBuilder().QuoteIdentifier(channel)}", conn);
        await cmd.ExecuteNonQueryAsync();
    }
    ```

=== "Go"

    ```go
    // listen subscribes the connection to a channel.
    func listen(ctx context.Context, conn *pgx.Conn, channel string) error {
    	// LISTEN takes an identifier rather than a value, so it cannot use a
    	// parameter; pgx.Identifier quotes the name safely.
    	_, err := conn.Exec(ctx, "LISTEN "+pgx.Identifier{channel}.Sanitize())
    	if err != nil {
    		return fmt.Errorf("listen failed: %w", err)
    	}
    	return nil
    }
    
    ```

=== "Rust"

    ```rust
    /// Subscribes the connection to a channel.
    fn listen(client: &mut Client, channel: &str) -> Result<(), postgres::Error> {
        // LISTEN takes an identifier rather than a value, so it cannot use a
        // parameter. The crate has no identifier quoting function, so this
        // quotes the name by hand: it wraps the name in double quotes and
        // doubles any double quote inside it.
        let identifier = format!("\"{}\"", channel.replace('"', "\"\""));
        client.batch_execute(&format!("LISTEN {identifier}"))
    }
    ```

=== "Ruby"

    ```ruby
    # Subscribes the connection to a channel.
    def listen(conn, channel)
      # LISTEN takes an identifier rather than a value, so it cannot use a
      # parameter; escape_identifier quotes the name safely.
      conn.exec("LISTEN #{conn.escape_identifier(channel)}")
    end
    ```

=== "C"

    ```c
    /*
     * Subscribe the connection to a channel, and return true on success. On
     * failure, PQerrorMessage() describes the error.
     */
    static bool
    listen_on(PGconn *conn, const char *channel)
    {
        /*
         * LISTEN takes an identifier rather than a value, so it cannot use a
         * parameter; PQescapeIdentifier() quotes the name safely.
         */
        char *identifier = PQescapeIdentifier(conn, channel, strlen(channel));
        char *sql;
        PGresult *res;
        bool ok;
    
        if (identifier == NULL)
            return false;
    
        sql = malloc(strlen(identifier) + sizeof("LISTEN "));
        if (sql == NULL)
        {
            PQfreemem(identifier);
            return false;
        }
        sprintf(sql, "LISTEN %s", identifier);
        PQfreemem(identifier);
    
        res = PQexec(conn, sql);
        ok = PQresultStatus(res) == PGRES_COMMAND_OK;
    
        /* PQclear() frees the result, and accepts NULL. */
        PQclear(res);
        free(sql);
        return ok;
    }
    ```

## Sending a Notification

The sending connection calls the `pg_notify()` function, which takes the
channel and the payload as ordinary parameters. The `NOTIFY` command does
the same work, but takes literal text, so the function is the better choice
for an application. The following tabs show how each program sends the
notification:

=== "Python"

    ```python
    def notify(conn: psycopg.Connection, channel: str, payload: str) -> None:
        """Sends a notification to every connection listening on a channel."""
        # pg_notify() takes the channel and payload as ordinary parameters,
        # unlike the NOTIFY command.
        conn.execute("SELECT pg_notify(%s, %s)", (channel, payload))
    ```

=== "TypeScript"

    ```typescript
    // Sends a notification to every connection listening on a channel.
    async function notify(
      client: pg.Client,
      channel: string,
      payload: string,
    ): Promise<void> {
      // pg_notify() takes the channel and payload as ordinary parameters,
      // unlike the NOTIFY command.
      await client.query("SELECT pg_notify($1, $2)", [channel, payload]);
    }
    ```

=== "Java"

    ```java
    /** Sends a notification to every connection listening on a channel. */
    static void notify(Connection conn, String channel, String payload)
            throws SQLException {
        // pg_notify() takes the channel and payload as ordinary
        // parameters, unlike the NOTIFY command.
        try (PreparedStatement stmt =
                conn.prepareStatement("SELECT pg_notify(?, ?)")) {
            stmt.setString(1, channel);
            stmt.setString(2, payload);
            stmt.execute();
        }
    }
    ```

=== "C#"

    ```csharp
    // Sends a notification to every connection listening on a channel.
    static async Task NotifyAsync(
        NpgsqlConnection conn, string channel, string payload)
    {
        // pg_notify() takes the channel and payload as ordinary parameters,
        // unlike the NOTIFY command. Positional parameters are written $1, $2,
        // and so on.
        await using var cmd = new NpgsqlCommand("SELECT pg_notify($1, $2)", conn)
        {
            Parameters = { new() { Value = channel }, new() { Value = payload } },
        };
        await cmd.ExecuteNonQueryAsync();
    }
    ```

=== "Go"

    ```go
    // notify sends a notification to every connection listening on a channel.
    func notify(ctx context.Context, conn *pgx.Conn, channel, payload string) error {
    	// pg_notify() takes the channel and payload as ordinary parameters,
    	// unlike the NOTIFY command.
    	_, err := conn.Exec(ctx, "SELECT pg_notify($1, $2)", channel, payload)
    	if err != nil {
    		return fmt.Errorf("notify failed: %w", err)
    	}
    	return nil
    }
    
    ```

=== "Rust"

    ```rust
    /// Sends a notification to every connection listening on a channel.
    fn notify(client: &mut Client, channel: &str, payload: &str) -> Result<(), postgres::Error> {
        // pg_notify() takes the channel and payload as ordinary parameters,
        // unlike the NOTIFY command.
        client.execute("SELECT pg_notify($1, $2)", &[&channel, &payload])?;
        Ok(())
    }
    ```

=== "Ruby"

    ```ruby
    # Sends a notification to every connection listening on a channel.
    def notify(conn, channel, payload)
      # pg_notify() takes the channel and payload as ordinary parameters,
      # unlike the NOTIFY command.
      conn.exec_params("SELECT pg_notify($1, $2)", [channel, payload])
    end
    ```

=== "C"

    ```c
    /*
     * Send a notification to every connection listening on a channel, and
     * return true on success.
     */
    static bool
    send_notification(PGconn *conn, const char *channel, const char *payload)
    {
        /*
         * pg_notify() takes the channel and payload as ordinary parameters,
         * unlike the NOTIFY command, so libpq sends them separately.
         */
        const char *params[] = {channel, payload};
        PGresult *res = PQexecParams(conn, "SELECT pg_notify($1, $2)",
                                     2,     /* number of parameters */
                                     NULL,  /* let the server infer types */
                                     params,
                                     NULL,  /* text parameters need no lengths */
                                     NULL,  /* all parameters are text */
                                     0);    /* ask for text results */
        bool ok = PQresultStatus(res) == PGRES_TUPLES_OK;
    
        PQclear(res);
        return ok;
    }
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
    def wait_for_notification(conn: psycopg.Connection, timeout: float):
        """Waits for one notification, and returns it, or None on timeout."""
        # notifies() yields notifications as they arrive, and ends when the
        # timeout passes without one. stop_after ends it after the first.
        for notification in conn.notifies(timeout=timeout, stop_after=1):
            return notification
        return None
    ```

=== "TypeScript"

    ```typescript
    // Starts waiting for one notification. The promise resolves with the
    // notification, or rejects if none arrives within the timeout. Call this
    // before sending the notification: node-postgres emits a notification as
    // soon as it arrives, and an event with no listener is lost. Calling
    // cancel() stops the timer and the listener, which lets the program exit
    // at once if it gives up waiting.
    function waitForNotification(
      client: pg.Client,
      timeoutMs: number,
    ): { promise: Promise<pg.Notification>; cancel: () => void } {
      let cancel = (): void => {};
      const promise = new Promise<pg.Notification>((resolve, reject) => {
        const timer = setTimeout(() => {
          client.removeListener("notification", onNotification);
          reject(new Error(`No notification within ${timeoutMs / 1000} seconds`));
        }, timeoutMs);
    
        function onNotification(message: pg.Notification): void {
          clearTimeout(timer);
          resolve(message);
        }
    
        client.once("notification", onNotification);
        cancel = () => {
          clearTimeout(timer);
          client.removeListener("notification", onNotification);
        };
      });
      return { promise, cancel };
    }
    ```

=== "Java"

    ```java
    /**
     * Waits for a notification, and returns it, or null on timeout.
     * PGConnection is the pgJDBC extension interface, which unwrap()
     * returns from the standard Connection.
     */
    static PGNotification waitForNotification(Connection conn,
                                              int timeoutMillis)
            throws SQLException {
        PGNotification[] received =
                conn.unwrap(PGConnection.class).getNotifications(timeoutMillis);
        return (received == null || received.length == 0) ? null : received[0];
    }
    ```

=== "C#"

    ```csharp
    // Waits for a notification, and returns it, or null on timeout. Npgsql
    // reads from the socket only while a command or WaitAsync is running, and
    // raises the Notification event from there.
    static async Task<NpgsqlNotificationEventArgs?> WaitForNotificationAsync(
        NpgsqlConnection conn, TimeSpan timeout)
    {
        NpgsqlNotificationEventArgs? received = null;
        conn.Notification += (_, e) => received = e;
    
        using var cts = new CancellationTokenSource(timeout);
        try
        {
            // WaitAsync returns after any message from the server, so keep
            // waiting until the event has fired.
            while (received is null)
            {
                await conn.WaitAsync(cts.Token);
            }
        }
        catch (OperationCanceledException)
        {
            // The timeout passed with no notification.
        }
        return received;
    }
    ```

=== "Go"

    ```go
    // waitForNotification waits for one notification, and returns it. It
    // returns an error if none arrives within the timeout.
    func waitForNotification(ctx context.Context, conn *pgx.Conn, timeout time.Duration) (*pgconn.Notification, error) {
    	// WaitForNotification blocks until a notification arrives or the
    	// context ends, so a context with a deadline provides the timeout.
    	ctx, cancel := context.WithTimeout(ctx, timeout)
    	defer cancel()
    
    	message, err := conn.WaitForNotification(ctx)
    	if errors.Is(err, context.DeadlineExceeded) {
    		return nil, fmt.Errorf("no notification within %v", timeout)
    	}
    	if err != nil {
    		return nil, fmt.Errorf("wait failed: %w", err)
    	}
    	return message, nil
    }
    
    ```

=== "Rust"

    ```rust
    /// Waits for one notification, and returns it, or None on timeout.
    fn wait_for_notification(
        client: &mut Client,
        timeout: Duration,
    ) -> Result<Option<Notification>, postgres::Error> {
        // timeout_iter() yields notifications as they arrive, and ends when
        // the timeout passes without one.
        client.notifications().timeout_iter(timeout).next()
    }
    ```

=== "Ruby"

    ```ruby
    # Waits for one notification, and returns its channel and payload, or nil
    # on timeout.
    def wait_for_notification(conn, timeout)
      received = nil
      # wait_for_notify blocks until a notification arrives or the timeout (in
      # seconds) passes, yields the notification to the block, and returns nil
      # on timeout.
      conn.wait_for_notify(timeout) do |channel, _pid, payload|
        received = [channel, payload]
      end
      received
    end
    ```

=== "C"

    ```c
    /* Return the milliseconds from start to now, using a clock that never
     * goes backwards. */
    static long
    elapsed_ms(const struct timespec *start)
    {
        struct timespec now;
    
        clock_gettime(CLOCK_MONOTONIC, &now);
        return (now.tv_sec - start->tv_sec) * 1000 +
               (now.tv_nsec - start->tv_nsec) / 1000000;
    }
    
    /*
     * Wait for a notification, and return it. The caller frees the
     * notification with PQfreemem(). On failure the function returns NULL and
     * sets *problem to NULL for a timeout, or to a message that describes an
     * error.
     *
     * libpq never reads from the socket by itself while the program is idle.
     * The loop therefore asks poll() to wait until the socket is readable,
     * calls PQconsumeInput() to read what arrived, and then asks PQnotifies()
     * for the next queued notification.
     */
    static PGnotify *
    wait_for_notification(PGconn *conn, int timeout_ms, const char **problem)
    {
        struct timespec start;
        struct pollfd pfd;
    
        clock_gettime(CLOCK_MONOTONIC, &start);
        pfd.fd = PQsocket(conn);
        pfd.events = POLLIN;
        *problem = NULL;
    
        for (;;)
        {
            PGnotify *message;
            long remaining;
            int ready;
    
            if (!PQconsumeInput(conn))
            {
                *problem = PQerrorMessage(conn);
                return NULL;
            }
    
            message = PQnotifies(conn);
            if (message != NULL)
                return message;
    
            remaining = timeout_ms - elapsed_ms(&start);
            if (remaining <= 0)
                return NULL;
    
            ready = poll(&pfd, 1, (int) remaining);
            if (ready == 0)
                return NULL;
    
            /*
             * A signal can interrupt poll() with EINTR; the loop then works
             * out the remaining time again and retries. Any other failure is
             * an error, not a timeout.
             */
            if (ready < 0 && errno != EINTR)
            {
                *problem = strerror(errno);
                return NULL;
            }
        }
    }
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
    def main() -> int:
        try:
            # Each with block closes its connection when it exits, whether or
            # not an error occurred.
            with connect() as listener, connect() as sender:
                listen(listener, CHANNEL)
                print(f"Listening on channel '{CHANNEL}'")
    
                notify(sender, CHANNEL, "Hello from connection B")
    
                notification = wait_for_notification(listener, TIMEOUT_SECONDS)
                if notification is None:
                    print(f"No notification within {TIMEOUT_SECONDS} seconds",
                          file=sys.stderr)
                    return 1
                print(f"Received notification on '{notification.channel}': "
                      f"{notification.payload}")
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
      let listener: pg.Client | undefined;
      let sender: pg.Client | undefined;
      try {
        listener = await connect();
        sender = await connect();
    
        await listen(listener, CHANNEL);
        console.log(`Listening on channel '${CHANNEL}'`);
    
        const pending = waitForNotification(listener, TIMEOUT_MS);
        try {
          await notify(sender, CHANNEL, "Hello from connection B");
        } catch (err) {
          // Stop the timer, so the program does not wait for it, and mark the
          // promise as handled, so Node does not report it as unhandled.
          pending.cancel();
          pending.promise.catch(() => {});
          throw err;
        }
    
        const message = await pending.promise;
        console.log(
          `Received notification on '${message.channel}': ${message.payload}`,
        );
        return 0;
      } catch (err) {
        // Connection failures, errors reported by the server, and the
        // notification timeout all arrive here as rejected promises.
        console.error(`Error: ${describe(err)}`);
        return 1;
      } finally {
        // The finally block runs whether or not an error occurred; a client is
        // undefined if its connection attempt failed.
        await listener?.end();
        await sender?.end();
      }
    }
    
    process.exitCode = await main();
    ```

=== "Java"

    ```java
    public static void main(String[] args) {
        // try-with-resources closes both connections when the block exits,
        // whether or not an error occurred.
        try (Connection listener = connect(); Connection sender = connect()) {
            listen(listener, CHANNEL);
            System.out.println("Listening on channel '" + CHANNEL + "'");
    
            notify(sender, CHANNEL, "Hello from connection B");
    
            PGNotification message =
                    waitForNotification(listener, TIMEOUT_MILLIS);
            if (message == null) {
                System.err.println("No notification within "
                        + TIMEOUT_MILLIS / 1000 + " seconds");
                System.exit(1);
            }
            System.out.println("Received notification on '"
                    + message.getName() + "': " + message.getParameter());
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
        // await using disposes of the data source, and returns the connections
        // to the pool, when the block exits, whether or not an error occurred.
        await using var dataSource = CreateDataSource();
        await using var listener = await dataSource.OpenConnectionAsync();
        await using var sender = await dataSource.OpenConnectionAsync();
    
        await ListenAsync(listener, Channel);
        Console.WriteLine($"Listening on channel '{Channel}'");
    
        await NotifyAsync(sender, Channel, "Hello from connection B");
    
        var message = await WaitForNotificationAsync(listener, timeout);
        if (message is null)
        {
            Console.Error.WriteLine(
                $"No notification within {timeout.TotalSeconds} seconds");
            return 1;
        }
        Console.WriteLine(
            $"Received notification on '{message.Channel}': {message.Payload}");
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
    // run opens two connections, listens on one, notifies from the other, and
    // prints the notification, returning any error to the caller.
    func run(ctx context.Context) error {
    	listener, err := connect(ctx)
    	if err != nil {
    		return err
    	}
    	// The deferred calls close the connections when run() returns, whether
    	// or not an error occurred.
    	defer listener.Close(ctx)
    
    	sender, err := connect(ctx)
    	if err != nil {
    		return err
    	}
    	defer sender.Close(ctx)
    
    	if err := listen(ctx, listener, channel); err != nil {
    		return err
    	}
    	fmt.Printf("Listening on channel '%s'\n", channel)
    
    	if err := notify(ctx, sender, channel, "Hello from connection B"); err != nil {
    		return err
    	}
    
    	message, err := waitForNotification(ctx, listener, timeout)
    	if err != nil {
    		return err
    	}
    	fmt.Printf("Received notification on '%s': %s\n", message.Channel, message.Payload)
    	return nil
    }
    
    // main reports any error returned by run() and exits with a non-zero
    // status. Keeping the work in run() means that deferred cleanup always
    // happens before the program exits.
    func main() {
    	if err := run(context.Background()); err != nil {
    		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
    		os.Exit(1)
    	}
    }
    
    ```

=== "Rust"

    ```rust
    /// Opens two connections, listens on one, notifies from the other, and
    /// prints the notification. The ? operator returns any error to the
    /// caller.
    fn run() -> Result<(), Box<dyn Error>> {
        // Dropping a client closes its connection, including when ? returns
        // early.
        let mut listener = connect()?;
        let mut sender = connect()?;
    
        listen(&mut listener, CHANNEL)?;
        println!("Listening on channel '{CHANNEL}'");
    
        notify(&mut sender, CHANNEL, "Hello from connection B")?;
    
        let message = wait_for_notification(&mut listener, TIMEOUT)?
            .ok_or(format!("no notification within {} seconds", TIMEOUT.as_secs()))?;
        println!(
            "Received notification on '{}': {}",
            message.channel(),
            message.payload()
        );
        Ok(())
    }
    
    /// Reports any error returned by run() and exits with a failure status.
    /// The top-level error is often generic ("error connecting to server"),
    /// so the chain of underlying causes is printed too.
    fn main() -> ExitCode {
        match run() {
            Ok(()) => ExitCode::SUCCESS,
            Err(e) => {
                eprintln!("Error: {e}");
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
      listener = connect
      sender = connect
    
      listen(listener, CHANNEL)
      puts "Listening on channel '#{CHANNEL}'"
    
      notify(sender, CHANNEL, "Hello from connection B")
    
      channel, payload = wait_for_notification(listener, TIMEOUT_SECONDS)
      if channel.nil?
        warn "No notification within #{TIMEOUT_SECONDS} seconds"
        exit 1
      end
      puts "Received notification on '#{channel}': #{payload}"
    # PG::Error is the base class for every error the gem raises, including
    # connection failures and errors reported by the server.
    rescue PG::Error => e
      warn "Database error: #{e.message}"
      exit 1
    # The ensure block runs whether or not an error occurred. A connection is
    # nil if its connection attempt failed, hence the safe navigation operator.
    ensure
      listener&.close
      sender&.close
    end
    ```

=== "C"

    ```c
    int
    main(void)
    {
        int status = EXIT_FAILURE;
        PGconn *listener = connect_to_server();
        PGconn *sender = connect_to_server();
        PGnotify *message;
        const char *problem;
    
        if (PQstatus(listener) != CONNECTION_OK)
            fprintf(stderr, "Database error: %s", PQerrorMessage(listener));
        else if (PQstatus(sender) != CONNECTION_OK)
            fprintf(stderr, "Database error: %s", PQerrorMessage(sender));
        else if (!listen_on(listener, CHANNEL))
            fprintf(stderr, "Database error: %s", PQerrorMessage(listener));
        else
        {
            printf("Listening on channel '%s'\n", CHANNEL);
            fflush(stdout);
    
            if (!send_notification(sender, CHANNEL, "Hello from connection B"))
                fprintf(stderr, "Database error: %s", PQerrorMessage(sender));
            else if ((message = wait_for_notification(listener, TIMEOUT_MS,
                                                      &problem)) == NULL)
            {
                if (problem == NULL)
                    fprintf(stderr, "No notification within %d seconds\n",
                            TIMEOUT_MS / 1000);
                else
                    fprintf(stderr, "Wait failed: %s\n", problem);
            }
            else
            {
                printf("Received notification on '%s': %s\n",
                       message->relname, message->extra);
                PQfreemem(message);
                status = EXIT_SUCCESS;
            }
        }
    
        /* Close both connections whether or not an error occurred. */
        PQfinish(listener);
        PQfinish(sender);
        return status;
    }
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
    """
    Ellie's Postgres Cookbook
    Listening for notifications with LISTEN and NOTIFY, using psycopg 3.
    
    Copyright (c) 2026, pgEdge, Inc.
    This code is released under the PostgreSQL License.
    """
    
    import os
    import sys
    
    import psycopg
    
    
    CHANNEL = "cookbook_listen_notify"
    TIMEOUT_SECONDS = 5
    
    
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
    
        Autocommit mode matters here: without it, psycopg would open a
        transaction around LISTEN, and the subscription would not take effect
        until that transaction committed. A transaction around NOTIFY would
        likewise hold the notification back until the commit.
        """
        return psycopg.connect(**connection_settings(), autocommit=True)
    
    
    def listen(conn: psycopg.Connection, channel: str) -> None:
        """Subscribes the connection to a channel."""
        # LISTEN takes an identifier rather than a value, so it cannot use a
        # parameter; psycopg.sql.Identifier quotes the name safely.
        conn.execute(psycopg.sql.SQL("LISTEN {}").format(
            psycopg.sql.Identifier(channel)))
    
    
    def notify(conn: psycopg.Connection, channel: str, payload: str) -> None:
        """Sends a notification to every connection listening on a channel."""
        # pg_notify() takes the channel and payload as ordinary parameters,
        # unlike the NOTIFY command.
        conn.execute("SELECT pg_notify(%s, %s)", (channel, payload))
    
    
    def wait_for_notification(conn: psycopg.Connection, timeout: float):
        """Waits for one notification, and returns it, or None on timeout."""
        # notifies() yields notifications as they arrive, and ends when the
        # timeout passes without one. stop_after ends it after the first.
        for notification in conn.notifies(timeout=timeout, stop_after=1):
            return notification
        return None
    
    
    def main() -> int:
        try:
            # Each with block closes its connection when it exits, whether or
            # not an error occurred.
            with connect() as listener, connect() as sender:
                listen(listener, CHANNEL)
                print(f"Listening on channel '{CHANNEL}'")
    
                notify(sender, CHANNEL, "Hello from connection B")
    
                notification = wait_for_notification(listener, TIMEOUT_SECONDS)
                if notification is None:
                    print(f"No notification within {TIMEOUT_SECONDS} seconds",
                          file=sys.stderr)
                    return 1
                print(f"Received notification on '{notification.channel}': "
                      f"{notification.payload}")
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
     * Listening for notifications with LISTEN and NOTIFY, using node-postgres.
     *
     * Copyright (c) 2026, pgEdge, Inc.
     * This code is released under the PostgreSQL License.
     */
    
    import pg from "pg";
    
    const CHANNEL = "cookbook_listen_notify";
    const TIMEOUT_MS = 5000;
    
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
    
    // Opens a connection with the settings from the environment. node-postgres
    // runs each query in autocommit mode unless the program sends BEGIN, so
    // LISTEN takes effect, and NOTIFY is delivered, as soon as it completes.
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
    
    // Subscribes the connection to a channel.
    async function listen(client: pg.Client, channel: string): Promise<void> {
      // LISTEN takes an identifier rather than a value, so it cannot use a
      // parameter; escapeIdentifier quotes the name safely.
      await client.query(`LISTEN ${client.escapeIdentifier(channel)}`);
    }
    
    // Sends a notification to every connection listening on a channel.
    async function notify(
      client: pg.Client,
      channel: string,
      payload: string,
    ): Promise<void> {
      // pg_notify() takes the channel and payload as ordinary parameters,
      // unlike the NOTIFY command.
      await client.query("SELECT pg_notify($1, $2)", [channel, payload]);
    }
    
    // Starts waiting for one notification. The promise resolves with the
    // notification, or rejects if none arrives within the timeout. Call this
    // before sending the notification: node-postgres emits a notification as
    // soon as it arrives, and an event with no listener is lost. Calling
    // cancel() stops the timer and the listener, which lets the program exit
    // at once if it gives up waiting.
    function waitForNotification(
      client: pg.Client,
      timeoutMs: number,
    ): { promise: Promise<pg.Notification>; cancel: () => void } {
      let cancel = (): void => {};
      const promise = new Promise<pg.Notification>((resolve, reject) => {
        const timer = setTimeout(() => {
          client.removeListener("notification", onNotification);
          reject(new Error(`No notification within ${timeoutMs / 1000} seconds`));
        }, timeoutMs);
    
        function onNotification(message: pg.Notification): void {
          clearTimeout(timer);
          resolve(message);
        }
    
        client.once("notification", onNotification);
        cancel = () => {
          clearTimeout(timer);
          client.removeListener("notification", onNotification);
        };
      });
      return { promise, cancel };
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
      let listener: pg.Client | undefined;
      let sender: pg.Client | undefined;
      try {
        listener = await connect();
        sender = await connect();
    
        await listen(listener, CHANNEL);
        console.log(`Listening on channel '${CHANNEL}'`);
    
        const pending = waitForNotification(listener, TIMEOUT_MS);
        try {
          await notify(sender, CHANNEL, "Hello from connection B");
        } catch (err) {
          // Stop the timer, so the program does not wait for it, and mark the
          // promise as handled, so Node does not report it as unhandled.
          pending.cancel();
          pending.promise.catch(() => {});
          throw err;
        }
    
        const message = await pending.promise;
        console.log(
          `Received notification on '${message.channel}': ${message.payload}`,
        );
        return 0;
      } catch (err) {
        // Connection failures, errors reported by the server, and the
        // notification timeout all arrive here as rejected promises.
        console.error(`Error: ${describe(err)}`);
        return 1;
      } finally {
        // The finally block runs whether or not an error occurred; a client is
        // undefined if its connection attempt failed.
        await listener?.end();
        await sender?.end();
      }
    }
    
    process.exitCode = await main();
    
    ```

=== "Java"

    ```java
    /*
     * Ellie's Postgres Cookbook
     * Listening for notifications with LISTEN and NOTIFY, using JDBC and the
     * PostgreSQL JDBC driver (pgJDBC).
     *
     * Copyright (c) 2026, pgEdge, Inc.
     * This code is released under the PostgreSQL License.
     */
    
    import java.sql.Connection;
    import java.sql.DriverManager;
    import java.sql.PreparedStatement;
    import java.sql.SQLException;
    import java.sql.Statement;
    import java.util.Properties;
    
    import org.postgresql.PGConnection;
    import org.postgresql.PGNotification;
    
    public class Main {
    
        static final String CHANNEL = "cookbook_listen_notify";
        static final int TIMEOUT_MILLIS = 5000;
    
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
         * Opens a connection with the settings from the environment. JDBC
         * connections start in autocommit mode, so LISTEN takes effect, and
         * NOTIFY is delivered, as soon as each statement completes.
         */
        static Connection connect() throws SQLException {
            return DriverManager.getConnection(
                    connectionUrl(), connectionProperties());
        }
    
        /** Subscribes the connection to a channel. */
        static void listen(Connection conn, String channel)
                throws SQLException {
            try (Statement stmt = conn.createStatement()) {
                // LISTEN takes an identifier rather than a value, so it cannot
                // use a parameter; enquoteIdentifier quotes the name safely.
                stmt.execute("LISTEN " + stmt.enquoteIdentifier(channel, true));
            }
        }
    
        /** Sends a notification to every connection listening on a channel. */
        static void notify(Connection conn, String channel, String payload)
                throws SQLException {
            // pg_notify() takes the channel and payload as ordinary
            // parameters, unlike the NOTIFY command.
            try (PreparedStatement stmt =
                    conn.prepareStatement("SELECT pg_notify(?, ?)")) {
                stmt.setString(1, channel);
                stmt.setString(2, payload);
                stmt.execute();
            }
        }
    
        /**
         * Waits for a notification, and returns it, or null on timeout.
         * PGConnection is the pgJDBC extension interface, which unwrap()
         * returns from the standard Connection.
         */
        static PGNotification waitForNotification(Connection conn,
                                                  int timeoutMillis)
                throws SQLException {
            PGNotification[] received =
                    conn.unwrap(PGConnection.class).getNotifications(timeoutMillis);
            return (received == null || received.length == 0) ? null : received[0];
        }
    
        public static void main(String[] args) {
            // try-with-resources closes both connections when the block exits,
            // whether or not an error occurred.
            try (Connection listener = connect(); Connection sender = connect()) {
                listen(listener, CHANNEL);
                System.out.println("Listening on channel '" + CHANNEL + "'");
    
                notify(sender, CHANNEL, "Hello from connection B");
    
                PGNotification message =
                        waitForNotification(listener, TIMEOUT_MILLIS);
                if (message == null) {
                    System.err.println("No notification within "
                            + TIMEOUT_MILLIS / 1000 + " seconds");
                    System.exit(1);
                }
                System.out.println("Received notification on '"
                        + message.getName() + "': " + message.getParameter());
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
     * Listening for notifications with LISTEN and NOTIFY, using Npgsql.
     *
     * Copyright (c) 2026, pgEdge, Inc.
     * This code is released under the PostgreSQL License.
     */
    
    using Npgsql;
    
    const string Channel = "cookbook_listen_notify";
    var timeout = TimeSpan.FromSeconds(5);
    
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
    // OpenConnectionAsync borrows one from the pool, so the two calls below
    // get two separate connections. Npgsql runs each command in autocommit
    // mode unless the program starts a transaction, so LISTEN takes effect,
    // and NOTIFY is delivered, as soon as the command completes.
    static NpgsqlDataSource CreateDataSource() =>
        NpgsqlDataSource.Create(ConnectionString());
    
    // Subscribes the connection to a channel.
    static async Task ListenAsync(NpgsqlConnection conn, string channel)
    {
        // LISTEN takes an identifier rather than a value, so it cannot use a
        // parameter; QuoteIdentifier quotes the name safely.
        await using var cmd = new NpgsqlCommand(
            $"LISTEN {new NpgsqlCommandBuilder().QuoteIdentifier(channel)}", conn);
        await cmd.ExecuteNonQueryAsync();
    }
    
    // Sends a notification to every connection listening on a channel.
    static async Task NotifyAsync(
        NpgsqlConnection conn, string channel, string payload)
    {
        // pg_notify() takes the channel and payload as ordinary parameters,
        // unlike the NOTIFY command. Positional parameters are written $1, $2,
        // and so on.
        await using var cmd = new NpgsqlCommand("SELECT pg_notify($1, $2)", conn)
        {
            Parameters = { new() { Value = channel }, new() { Value = payload } },
        };
        await cmd.ExecuteNonQueryAsync();
    }
    
    // Waits for a notification, and returns it, or null on timeout. Npgsql
    // reads from the socket only while a command or WaitAsync is running, and
    // raises the Notification event from there.
    static async Task<NpgsqlNotificationEventArgs?> WaitForNotificationAsync(
        NpgsqlConnection conn, TimeSpan timeout)
    {
        NpgsqlNotificationEventArgs? received = null;
        conn.Notification += (_, e) => received = e;
    
        using var cts = new CancellationTokenSource(timeout);
        try
        {
            // WaitAsync returns after any message from the server, so keep
            // waiting until the event has fired.
            while (received is null)
            {
                await conn.WaitAsync(cts.Token);
            }
        }
        catch (OperationCanceledException)
        {
            // The timeout passed with no notification.
        }
        return received;
    }
    
    try
    {
        // await using disposes of the data source, and returns the connections
        // to the pool, when the block exits, whether or not an error occurred.
        await using var dataSource = CreateDataSource();
        await using var listener = await dataSource.OpenConnectionAsync();
        await using var sender = await dataSource.OpenConnectionAsync();
    
        await ListenAsync(listener, Channel);
        Console.WriteLine($"Listening on channel '{Channel}'");
    
        await NotifyAsync(sender, Channel, "Hello from connection B");
    
        var message = await WaitForNotificationAsync(listener, timeout);
        if (message is null)
        {
            Console.Error.WriteLine(
                $"No notification within {timeout.TotalSeconds} seconds");
            return 1;
        }
        Console.WriteLine(
            $"Received notification on '{message.Channel}': {message.Payload}");
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
    // Listening for notifications with LISTEN and NOTIFY, using pgx.
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
    
    
    const (
    	channel = "cookbook_listen_notify"
    	timeout = 5 * time.Second
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
    // runs each statement in autocommit mode unless the program begins a
    // transaction, so LISTEN takes effect, and NOTIFY is delivered, as soon as
    // the statement completes.
    func connect(ctx context.Context) (*pgx.Conn, error) {
    	conn, err := pgx.Connect(ctx, connString())
    	if err != nil {
    		return nil, fmt.Errorf("connection failed: %w", err)
    	}
    	return conn, nil
    }
    
    
    // listen subscribes the connection to a channel.
    func listen(ctx context.Context, conn *pgx.Conn, channel string) error {
    	// LISTEN takes an identifier rather than a value, so it cannot use a
    	// parameter; pgx.Identifier quotes the name safely.
    	_, err := conn.Exec(ctx, "LISTEN "+pgx.Identifier{channel}.Sanitize())
    	if err != nil {
    		return fmt.Errorf("listen failed: %w", err)
    	}
    	return nil
    }
    
    
    // notify sends a notification to every connection listening on a channel.
    func notify(ctx context.Context, conn *pgx.Conn, channel, payload string) error {
    	// pg_notify() takes the channel and payload as ordinary parameters,
    	// unlike the NOTIFY command.
    	_, err := conn.Exec(ctx, "SELECT pg_notify($1, $2)", channel, payload)
    	if err != nil {
    		return fmt.Errorf("notify failed: %w", err)
    	}
    	return nil
    }
    
    
    // waitForNotification waits for one notification, and returns it. It
    // returns an error if none arrives within the timeout.
    func waitForNotification(ctx context.Context, conn *pgx.Conn, timeout time.Duration) (*pgconn.Notification, error) {
    	// WaitForNotification blocks until a notification arrives or the
    	// context ends, so a context with a deadline provides the timeout.
    	ctx, cancel := context.WithTimeout(ctx, timeout)
    	defer cancel()
    
    	message, err := conn.WaitForNotification(ctx)
    	if errors.Is(err, context.DeadlineExceeded) {
    		return nil, fmt.Errorf("no notification within %v", timeout)
    	}
    	if err != nil {
    		return nil, fmt.Errorf("wait failed: %w", err)
    	}
    	return message, nil
    }
    
    
    // run opens two connections, listens on one, notifies from the other, and
    // prints the notification, returning any error to the caller.
    func run(ctx context.Context) error {
    	listener, err := connect(ctx)
    	if err != nil {
    		return err
    	}
    	// The deferred calls close the connections when run() returns, whether
    	// or not an error occurred.
    	defer listener.Close(ctx)
    
    	sender, err := connect(ctx)
    	if err != nil {
    		return err
    	}
    	defer sender.Close(ctx)
    
    	if err := listen(ctx, listener, channel); err != nil {
    		return err
    	}
    	fmt.Printf("Listening on channel '%s'\n", channel)
    
    	if err := notify(ctx, sender, channel, "Hello from connection B"); err != nil {
    		return err
    	}
    
    	message, err := waitForNotification(ctx, listener, timeout)
    	if err != nil {
    		return err
    	}
    	fmt.Printf("Received notification on '%s': %s\n", message.Channel, message.Payload)
    	return nil
    }
    
    // main reports any error returned by run() and exits with a non-zero
    // status. Keeping the work in run() means that deferred cleanup always
    // happens before the program exits.
    func main() {
    	if err := run(context.Background()); err != nil {
    		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
    		os.Exit(1)
    	}
    }
    
    
    ```

=== "Rust"

    ```rust
    // Ellie's Postgres Cookbook
    // Listening for notifications with LISTEN and NOTIFY, using the postgres
    // crate.
    //
    // Copyright (c) 2026, pgEdge, Inc.
    // This code is released under the PostgreSQL License.
    
    use std::env;
    use std::error::Error;
    use std::process::ExitCode;
    use std::time::Duration;
    
    use postgres::fallible_iterator::FallibleIterator;
    use postgres::{Client, Config, NoTls, Notification};
    
    const CHANNEL: &str = "cookbook_listen_notify";
    const TIMEOUT: Duration = Duration::from_secs(5);
    
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
    /// connections over an untrusted network should use TLS. The client runs
    /// each statement in autocommit mode unless the program begins a
    /// transaction, so LISTEN takes effect, and NOTIFY is delivered, as soon
    /// as the statement completes.
    fn connect() -> Result<Client, postgres::Error> {
        config().connect(NoTls)
    }
    
    /// Subscribes the connection to a channel.
    fn listen(client: &mut Client, channel: &str) -> Result<(), postgres::Error> {
        // LISTEN takes an identifier rather than a value, so it cannot use a
        // parameter. The crate has no identifier quoting function, so this
        // quotes the name by hand: it wraps the name in double quotes and
        // doubles any double quote inside it.
        let identifier = format!("\"{}\"", channel.replace('"', "\"\""));
        client.batch_execute(&format!("LISTEN {identifier}"))
    }
    
    /// Sends a notification to every connection listening on a channel.
    fn notify(client: &mut Client, channel: &str, payload: &str) -> Result<(), postgres::Error> {
        // pg_notify() takes the channel and payload as ordinary parameters,
        // unlike the NOTIFY command.
        client.execute("SELECT pg_notify($1, $2)", &[&channel, &payload])?;
        Ok(())
    }
    
    /// Waits for one notification, and returns it, or None on timeout.
    fn wait_for_notification(
        client: &mut Client,
        timeout: Duration,
    ) -> Result<Option<Notification>, postgres::Error> {
        // timeout_iter() yields notifications as they arrive, and ends when
        // the timeout passes without one.
        client.notifications().timeout_iter(timeout).next()
    }
    
    /// Opens two connections, listens on one, notifies from the other, and
    /// prints the notification. The ? operator returns any error to the
    /// caller.
    fn run() -> Result<(), Box<dyn Error>> {
        // Dropping a client closes its connection, including when ? returns
        // early.
        let mut listener = connect()?;
        let mut sender = connect()?;
    
        listen(&mut listener, CHANNEL)?;
        println!("Listening on channel '{CHANNEL}'");
    
        notify(&mut sender, CHANNEL, "Hello from connection B")?;
    
        let message = wait_for_notification(&mut listener, TIMEOUT)?
            .ok_or(format!("no notification within {} seconds", TIMEOUT.as_secs()))?;
        println!(
            "Received notification on '{}': {}",
            message.channel(),
            message.payload()
        );
        Ok(())
    }
    
    /// Reports any error returned by run() and exits with a failure status.
    /// The top-level error is often generic ("error connecting to server"),
    /// so the chain of underlying causes is printed too.
    fn main() -> ExitCode {
        match run() {
            Ok(()) => ExitCode::SUCCESS,
            Err(e) => {
                eprintln!("Error: {e}");
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
    # Listening for notifications with LISTEN and NOTIFY, using the pg gem.
    #
    # Copyright (c) 2026, pgEdge, Inc.
    # This code is released under the PostgreSQL License.
    
    require "pg"
    
    CHANNEL = "cookbook_listen_notify"
    TIMEOUT_SECONDS = 5
    
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
    
    # Opens a connection with the settings from the environment. libpq runs
    # each statement in autocommit mode unless the program sends BEGIN, so
    # LISTEN takes effect, and NOTIFY is delivered, as soon as the statement
    # completes.
    def connect
      PG.connect(connection_params)
    end
    
    # Subscribes the connection to a channel.
    def listen(conn, channel)
      # LISTEN takes an identifier rather than a value, so it cannot use a
      # parameter; escape_identifier quotes the name safely.
      conn.exec("LISTEN #{conn.escape_identifier(channel)}")
    end
    
    # Sends a notification to every connection listening on a channel.
    def notify(conn, channel, payload)
      # pg_notify() takes the channel and payload as ordinary parameters,
      # unlike the NOTIFY command.
      conn.exec_params("SELECT pg_notify($1, $2)", [channel, payload])
    end
    
    # Waits for one notification, and returns its channel and payload, or nil
    # on timeout.
    def wait_for_notification(conn, timeout)
      received = nil
      # wait_for_notify blocks until a notification arrives or the timeout (in
      # seconds) passes, yields the notification to the block, and returns nil
      # on timeout.
      conn.wait_for_notify(timeout) do |channel, _pid, payload|
        received = [channel, payload]
      end
      received
    end
    
    begin
      listener = connect
      sender = connect
    
      listen(listener, CHANNEL)
      puts "Listening on channel '#{CHANNEL}'"
    
      notify(sender, CHANNEL, "Hello from connection B")
    
      channel, payload = wait_for_notification(listener, TIMEOUT_SECONDS)
      if channel.nil?
        warn "No notification within #{TIMEOUT_SECONDS} seconds"
        exit 1
      end
      puts "Received notification on '#{channel}': #{payload}"
    # PG::Error is the base class for every error the gem raises, including
    # connection failures and errors reported by the server.
    rescue PG::Error => e
      warn "Database error: #{e.message}"
      exit 1
    # The ensure block runs whether or not an error occurred. A connection is
    # nil if its connection attempt failed, hence the safe navigation operator.
    ensure
      listener&.close
      sender&.close
    end
    
    ```

=== "C"

    ```c
    /*
     * Ellie's Postgres Cookbook
     * Listening for notifications with LISTEN and NOTIFY, using libpq.
     *
     * Copyright (c) 2026, pgEdge, Inc.
     * This code is released under the PostgreSQL License.
     */
    
    #include <errno.h>
    #include <poll.h>
    #include <stdbool.h>
    #include <stdio.h>
    #include <stdlib.h>
    #include <string.h>
    #include <time.h>
    
    #include <libpq-fe.h>
    
    #define CHANNEL "cookbook_listen_notify"
    #define TIMEOUT_MS 5000
    
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
     * and release with PQfinish(), even if the connection attempt failed.
     * libpq runs each command in autocommit mode unless the program sends
     * BEGIN, so LISTEN takes effect, and NOTIFY is delivered, as soon as the
     * command completes.
     */
    static PGconn *
    connect_to_server(void)
    {
        const char *values[sizeof(keywords) / sizeof(keywords[0])];
    
        read_settings(values);
        return PQconnectdbParams(keywords, values, 0);
    }
    
    /*
     * Subscribe the connection to a channel, and return true on success. On
     * failure, PQerrorMessage() describes the error.
     */
    static bool
    listen_on(PGconn *conn, const char *channel)
    {
        /*
         * LISTEN takes an identifier rather than a value, so it cannot use a
         * parameter; PQescapeIdentifier() quotes the name safely.
         */
        char *identifier = PQescapeIdentifier(conn, channel, strlen(channel));
        char *sql;
        PGresult *res;
        bool ok;
    
        if (identifier == NULL)
            return false;
    
        sql = malloc(strlen(identifier) + sizeof("LISTEN "));
        if (sql == NULL)
        {
            PQfreemem(identifier);
            return false;
        }
        sprintf(sql, "LISTEN %s", identifier);
        PQfreemem(identifier);
    
        res = PQexec(conn, sql);
        ok = PQresultStatus(res) == PGRES_COMMAND_OK;
    
        /* PQclear() frees the result, and accepts NULL. */
        PQclear(res);
        free(sql);
        return ok;
    }
    
    /*
     * Send a notification to every connection listening on a channel, and
     * return true on success.
     */
    static bool
    send_notification(PGconn *conn, const char *channel, const char *payload)
    {
        /*
         * pg_notify() takes the channel and payload as ordinary parameters,
         * unlike the NOTIFY command, so libpq sends them separately.
         */
        const char *params[] = {channel, payload};
        PGresult *res = PQexecParams(conn, "SELECT pg_notify($1, $2)",
                                     2,     /* number of parameters */
                                     NULL,  /* let the server infer types */
                                     params,
                                     NULL,  /* text parameters need no lengths */
                                     NULL,  /* all parameters are text */
                                     0);    /* ask for text results */
        bool ok = PQresultStatus(res) == PGRES_TUPLES_OK;
    
        PQclear(res);
        return ok;
    }
    
    /* Return the milliseconds from start to now, using a clock that never
     * goes backwards. */
    static long
    elapsed_ms(const struct timespec *start)
    {
        struct timespec now;
    
        clock_gettime(CLOCK_MONOTONIC, &now);
        return (now.tv_sec - start->tv_sec) * 1000 +
               (now.tv_nsec - start->tv_nsec) / 1000000;
    }
    
    /*
     * Wait for a notification, and return it. The caller frees the
     * notification with PQfreemem(). On failure the function returns NULL and
     * sets *problem to NULL for a timeout, or to a message that describes an
     * error.
     *
     * libpq never reads from the socket by itself while the program is idle.
     * The loop therefore asks poll() to wait until the socket is readable,
     * calls PQconsumeInput() to read what arrived, and then asks PQnotifies()
     * for the next queued notification.
     */
    static PGnotify *
    wait_for_notification(PGconn *conn, int timeout_ms, const char **problem)
    {
        struct timespec start;
        struct pollfd pfd;
    
        clock_gettime(CLOCK_MONOTONIC, &start);
        pfd.fd = PQsocket(conn);
        pfd.events = POLLIN;
        *problem = NULL;
    
        for (;;)
        {
            PGnotify *message;
            long remaining;
            int ready;
    
            if (!PQconsumeInput(conn))
            {
                *problem = PQerrorMessage(conn);
                return NULL;
            }
    
            message = PQnotifies(conn);
            if (message != NULL)
                return message;
    
            remaining = timeout_ms - elapsed_ms(&start);
            if (remaining <= 0)
                return NULL;
    
            ready = poll(&pfd, 1, (int) remaining);
            if (ready == 0)
                return NULL;
    
            /*
             * A signal can interrupt poll() with EINTR; the loop then works
             * out the remaining time again and retries. Any other failure is
             * an error, not a timeout.
             */
            if (ready < 0 && errno != EINTR)
            {
                *problem = strerror(errno);
                return NULL;
            }
        }
    }
    
    int
    main(void)
    {
        int status = EXIT_FAILURE;
        PGconn *listener = connect_to_server();
        PGconn *sender = connect_to_server();
        PGnotify *message;
        const char *problem;
    
        if (PQstatus(listener) != CONNECTION_OK)
            fprintf(stderr, "Database error: %s", PQerrorMessage(listener));
        else if (PQstatus(sender) != CONNECTION_OK)
            fprintf(stderr, "Database error: %s", PQerrorMessage(sender));
        else if (!listen_on(listener, CHANNEL))
            fprintf(stderr, "Database error: %s", PQerrorMessage(listener));
        else
        {
            printf("Listening on channel '%s'\n", CHANNEL);
            fflush(stdout);
    
            if (!send_notification(sender, CHANNEL, "Hello from connection B"))
                fprintf(stderr, "Database error: %s", PQerrorMessage(sender));
            else if ((message = wait_for_notification(listener, TIMEOUT_MS,
                                                      &problem)) == NULL)
            {
                if (problem == NULL)
                    fprintf(stderr, "No notification within %d seconds\n",
                            TIMEOUT_MS / 1000);
                else
                    fprintf(stderr, "Wait failed: %s\n", problem);
            }
            else
            {
                printf("Received notification on '%s': %s\n",
                       message->relname, message->extra);
                PQfreemem(message);
                status = EXIT_SUCCESS;
            }
        }
    
        /* Close both connections whether or not an error occurred. */
        PQfinish(listener);
        PQfinish(sender);
        return status;
    }
    
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
