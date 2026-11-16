# Using Transactions

This recipe demonstrates how an application groups several SQL statements
into a transaction, so that the database server applies either all of them
or none of them. The example moves money between two accounts, which needs
two updates that must succeed or fail together. Each step shows the code in
every supported language; selecting a language tab switches every tab on
the site to that language.

The example program creates a temporary table of two accounts, with
balances of 100 and 50. The program moves 30 from the first account to the
second, and then tries to move 500, which the table rejects because a
balance may not go below zero. The following output shows the result:

```text
Transferred 30 from account 1 to account 2
Transfer of 500 from account 1 to account 2 failed and was rolled back
Account 1 balance: 70
Account 2 balance: 80
```

## Preparing the Ingredients

Each example uses the most widely adopted PostgreSQL driver for its
language, as in the
[first recipe](connect_and_query.md). The C example links against libpq,
so it requires the libpq client library and headers; on Debian and Ubuntu,
the `libpq-dev` package provides both. The following tabs show the
dependency declaration from each example project:

=== "Python"

    ```text
    # psycopg 3, with the pre-built binary package that bundles libpq.
    psycopg[binary]>=3.2,<4
    ```

=== "TypeScript"

    ```json
    {
      "name": "transactions",
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
library modules that the program uses. The Python, Go, and Rust programs
also import the type that identifies a particular server error. The
following tabs show the imports for each language:

=== "Python"

    ```python
    import os
    import sys
    
    import psycopg
    from psycopg import errors
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
variables as the first recipe, and treat an empty variable as unset, as
libpq does. The variables are `PGHOST`, `PGPORT`, `PGDATABASE`, `PGUSER`,
and `PGPASSWORD`, with the defaults `localhost`, `5432`, `postgres`,
`postgres`, and no password. The following tabs show how each program
assembles the connection settings:

=== "Python"

    ```python
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

Each program opens a connection to the server with the settings from the
previous step. A transaction belongs to one connection, and so does a
temporary table, so every statement in this example runs on the same
connection. The C# program borrows one connection from an Npgsql data
source and keeps it for the whole run. The Python program also turns on
autocommit mode, in which each statement commits by itself, because
psycopg otherwise opens a transaction before the first statement and
holds it open until the program commits; the program then chooses exactly
where each transaction begins and ends. The other drivers commit each
statement by itself until the program starts a transaction. The following
tabs show how each program opens the connection:

=== "Python"

    ```python
    def connect() -> psycopg.Connection:
        """Opens a connection with the settings from the environment.
    
        By default psycopg opens a transaction before the first statement and
        keeps it open until the program commits. Autocommit mode turns that
        off, so that each statement commits by itself and the program decides
        exactly where each transaction begins and ends.
        """
        return psycopg.connect(**connection_settings(), autocommit=True)
    ```

=== "TypeScript"

    ```typescript
    // Opens a connection with the settings from the environment.
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
    /** Opens a connection with the settings from the environment. */
    static Connection connect() throws SQLException {
        return DriverManager.getConnection(
                connectionUrl(), connectionProperties());
    }
    ```

=== "C#"

    ```csharp
    // Creates a data source with the settings from the environment. A data
    // source manages a pool of physical connections, and each call to
    // OpenConnectionAsync borrows one from the pool; an application normally
    // creates one data source at start-up and shares it. A temporary table
    // belongs to one physical connection, so this program borrows a single
    // connection and uses it throughout.
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
    /// connections over an untrusted network should use TLS.
    fn connect() -> Result<Client, postgres::Error> {
        config().connect(NoTls)
    }
    ```

=== "Ruby"

    ```ruby
    # Opens a connection with the settings from the environment.
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
     */
    static PGconn *
    connect_to_server(void)
    {
        const char *values[sizeof(keywords) / sizeof(keywords[0])];
    
        read_settings(values);
        return PQconnectdbParams(keywords, values, 0);
    }
    ```

## Creating the Accounts

Each program creates a temporary table named `accounts`, and inserts the
two accounts. A temporary table is private to the connection and vanishes
when the connection closes, so the example leaves nothing behind and can
run again straight away. The `CHECK (balance >= 0)` constraint makes the
server reject any change that would leave a balance below zero; that
rejection is what makes the second transfer fail. The following tabs show
how each program creates the table:

=== "Python"

    ```python
    def create_accounts(conn: psycopg.Connection) -> None:
        """Creates a temporary table of two accounts. The CHECK constraint
        stops any balance from going below zero."""
        conn.execute(
            "CREATE TEMPORARY TABLE accounts ("
            "id int PRIMARY KEY, "
            "balance int NOT NULL CHECK (balance >= 0))"
        )
        conn.execute("INSERT INTO accounts VALUES (1, 100), (2, 50)")
    ```

=== "TypeScript"

    ```typescript
    // Creates a temporary table of two accounts. The CHECK constraint stops
    // any balance from going below zero.
    async function createAccounts(client: pg.Client): Promise<void> {
      await client.query(
        "CREATE TEMPORARY TABLE accounts (" +
          "id int PRIMARY KEY, " +
          "balance int NOT NULL CHECK (balance >= 0))",
      );
      await client.query("INSERT INTO accounts VALUES (1, 100), (2, 50)");
    }
    ```

=== "Java"

    ```java
    /**
     * Creates a temporary table of two accounts. The CHECK constraint
     * stops any balance from going below zero.
     */
    static void createAccounts(Connection conn) throws SQLException {
        // The connection is in autocommit mode here, so each statement
        // commits by itself.
        try (Statement stmt = conn.createStatement()) {
            stmt.execute("CREATE TEMPORARY TABLE accounts ("
                    + "id int PRIMARY KEY, "
                    + "balance int NOT NULL CHECK (balance >= 0))");
            stmt.execute("INSERT INTO accounts VALUES (1, 100), (2, 50)");
        }
    }
    ```

=== "C#"

    ```csharp
    // Creates a temporary table of two accounts. The CHECK constraint stops
    // any balance from going below zero.
    static async Task CreateAccountsAsync(NpgsqlConnection conn)
    {
        await using var cmd = new NpgsqlCommand(
            "CREATE TEMPORARY TABLE accounts (" +
            "id int PRIMARY KEY, " +
            "balance int NOT NULL CHECK (balance >= 0)); " +
            "INSERT INTO accounts VALUES (1, 100), (2, 50)", conn);
        await cmd.ExecuteNonQueryAsync();
    }
    ```

=== "Go"

    ```go
    // createAccounts creates a temporary table of two accounts. The CHECK
    // constraint stops any balance from going below zero.
    func createAccounts(ctx context.Context, conn *pgx.Conn) error {
    	_, err := conn.Exec(ctx,
    		"CREATE TEMPORARY TABLE accounts ("+
    			"id int PRIMARY KEY, "+
    			"balance int NOT NULL CHECK (balance >= 0))")
    	if err != nil {
    		return fmt.Errorf("create table failed: %w", err)
    	}
    	_, err = conn.Exec(ctx, "INSERT INTO accounts VALUES (1, 100), (2, 50)")
    	if err != nil {
    		return fmt.Errorf("insert failed: %w", err)
    	}
    	return nil
    }
    
    ```

=== "Rust"

    ```rust
    /// Creates a temporary table of two accounts. The CHECK constraint stops
    /// any balance from going below zero. batch_execute runs statements that
    /// take no parameters.
    fn create_accounts(client: &mut Client) -> Result<(), postgres::Error> {
        client.batch_execute(
            "CREATE TEMPORARY TABLE accounts (
                 id int PRIMARY KEY,
                 balance int NOT NULL CHECK (balance >= 0));
             INSERT INTO accounts VALUES (1, 100), (2, 50)",
        )
    }
    ```

=== "Ruby"

    ```ruby
    # Creates a temporary table of two accounts. The CHECK constraint stops
    # any balance from going below zero.
    def create_accounts(conn)
      conn.exec(
        "CREATE TEMPORARY TABLE accounts (" \
        "id int PRIMARY KEY, " \
        "balance int NOT NULL CHECK (balance >= 0))"
      )
      conn.exec("INSERT INTO accounts VALUES (1, 100), (2, 50)")
    end
    ```

=== "C"

    ```c
    /*
     * Create a temporary table of two accounts, and return true on success.
     * The CHECK constraint stops any balance from going below zero. PQexec()
     * runs both statements, which need no parameters, in a single call.
     */
    static bool
    create_accounts(PGconn *conn)
    {
        PGresult *res = PQexec(conn,
                               "CREATE TEMPORARY TABLE accounts ("
                               "id int PRIMARY KEY, "
                               "balance int NOT NULL CHECK (balance >= 0)); "
                               "INSERT INTO accounts VALUES (1, 100), (2, 50)");
        bool ok = PQresultStatus(res) == PGRES_COMMAND_OK;
    
        PQclear(res);
        return ok;
    }
    ```

## Making a Transfer

Each program moves money in a function that credits the target account and
then debits the source account, both inside one transaction. The function
sends the amount and the account numbers as parameters, so the server never
interprets them as SQL. If both updates succeed, the function commits the
transaction and both changes become visible at once. If either update
fails, the function rolls the transaction back, and the server discards
every change made since the transaction began.

The function credits the target first on purpose. When the debit fails
because of the check constraint, the credit has already happened inside the
transaction, so the unchanged balances at the end of the program prove that
the rollback undid it.

The drivers differ in how much of this they do for the program:

- The Python `transaction()` block and the Ruby `transaction` method
  commit when the work ends normally and roll back when an error leaves
  it.
- The Go `Begin()`, C# `BeginTransactionAsync()`, and Rust `transaction()`
  calls return a transaction object that rolls back if the program never
  commits it, so each program calls `commit()` explicitly. The Go program
  defers a `Rollback()` call, which does nothing after a commit, the C#
  program disposes of the object with `await using`, and the Rust program
  drops the object when the `?` operator returns an error.
- The Java program turns off autocommit, commits explicitly, rolls back if
  any exception occurs, and turns autocommit back on in a `finally` block.
- The TypeScript and C programs send `BEGIN`, `COMMIT`, and `ROLLBACK`
  themselves, because node-postgres and libpq have no transaction object.

The following tabs show how each program makes a transfer:

=== "Python"

    ```python
    def transfer(conn: psycopg.Connection, source: int, target: int,
                 amount: int) -> None:
        """Moves money between two accounts in a single transaction."""
        # The with block begins a transaction, commits it when the block ends
        # normally, and rolls it back if an exception leaves the block.
        with conn.transaction():
            # Credit the target first, so that a failure of the debit shows
            # that the rollback undoes the credit as well.
            conn.execute(
                "UPDATE accounts SET balance = balance + %s WHERE id = %s",
                (amount, target),
            )
            conn.execute(
                "UPDATE accounts SET balance = balance - %s WHERE id = %s",
                (amount, source),
            )
    ```

=== "TypeScript"

    ```typescript
    // Moves money between two accounts in a single transaction.
    async function transfer(
      client: pg.Client,
      source: number,
      target: number,
      amount: number,
    ): Promise<void> {
      // node-postgres has no transaction object, so the program sends BEGIN,
      // COMMIT, and ROLLBACK itself. Everything sent on this client between
      // BEGIN and COMMIT belongs to the transaction.
      await client.query("BEGIN");
      try {
        // Credit the target first, so that a failure of the debit shows that
        // the rollback undoes the credit as well.
        await client.query(
          "UPDATE accounts SET balance = balance + $1 WHERE id = $2",
          [amount, target],
        );
        await client.query(
          "UPDATE accounts SET balance = balance - $1 WHERE id = $2",
          [amount, source],
        );
        await client.query("COMMIT");
      } catch (err) {
        // Undo the work, then pass the original error to the caller. If the
        // rollback fails too (for example, because the connection has gone),
        // ignore that failure so that it does not hide the original error.
        await client.query("ROLLBACK").catch(() => {});
        throw err;
      }
    }
    ```

=== "Java"

    ```java
    /** Moves money between two accounts in a single transaction. */
    static void transfer(Connection conn, int source, int target, int amount)
            throws SQLException {
        // JDBC starts in autocommit mode. Turning it off makes the driver
        // open a transaction that lasts until commit() or rollback().
        conn.setAutoCommit(false);
        try {
            // Credit the target first, so that a failure of the debit
            // shows that the rollback undoes the credit as well.
            update(conn,
                    "UPDATE accounts SET balance = balance + ? WHERE id = ?",
                    amount, target);
            update(conn,
                    "UPDATE accounts SET balance = balance - ? WHERE id = ?",
                    amount, source);
            conn.commit();
        } catch (Exception e) {
            // Undo the work, then pass the original error to the caller.
            // If the rollback fails too, attach that failure to the
            // original rather than letting it hide the cause.
            try {
                conn.rollback();
            } catch (SQLException rollbackError) {
                e.addSuppressed(rollbackError);
            }
            throw e;
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
    
    /** Runs an UPDATE statement that takes two integer parameters. */
    static void update(Connection conn, String sql, int first, int second)
            throws SQLException {
        try (PreparedStatement stmt = conn.prepareStatement(sql)) {
            stmt.setInt(1, first);
            stmt.setInt(2, second);
            stmt.executeUpdate();
        }
    }
    ```

=== "C#"

    ```csharp
    // Moves money between two accounts in a single transaction.
    static async Task TransferAsync(
        NpgsqlConnection conn, int source, int target, int amount)
    {
        // BeginTransactionAsync sends BEGIN. Disposing of the transaction
        // without committing it rolls the transaction back, so an exception
        // thrown below undoes the work.
        await using var tx = await conn.BeginTransactionAsync();
    
        // Credit the target first, so that a failure of the debit shows that
        // the rollback undoes the credit as well. Positional parameters are
        // written $1, $2, and so on.
        await using (var credit = new NpgsqlCommand(
            "UPDATE accounts SET balance = balance + $1 WHERE id = $2", conn, tx)
        {
            Parameters = { new() { Value = amount }, new() { Value = target } },
        })
        {
            await credit.ExecuteNonQueryAsync();
        }
    
        await using (var debit = new NpgsqlCommand(
            "UPDATE accounts SET balance = balance - $1 WHERE id = $2", conn, tx)
        {
            Parameters = { new() { Value = amount }, new() { Value = source } },
        })
        {
            await debit.ExecuteNonQueryAsync();
        }
    
        await tx.CommitAsync();
    }
    ```

=== "Go"

    ```go
    // transfer moves money between two accounts in a single transaction.
    func transfer(ctx context.Context, conn *pgx.Conn, source, target, amount int) error {
    	tx, err := conn.Begin(ctx)
    	if err != nil {
    		return fmt.Errorf("begin failed: %w", err)
    	}
    	// Rollback does nothing once the transaction has committed, so the
    	// deferred call undoes the work only if a statement fails first.
    	defer tx.Rollback(ctx)
    
    	// Credit the target first, so that a failure of the debit shows that
    	// the rollback undoes the credit as well.
    	_, err = tx.Exec(ctx,
    		"UPDATE accounts SET balance = balance + $1 WHERE id = $2",
    		amount, target)
    	if err != nil {
    		return fmt.Errorf("credit failed: %w", err)
    	}
    	_, err = tx.Exec(ctx,
    		"UPDATE accounts SET balance = balance - $1 WHERE id = $2",
    		amount, source)
    	if err != nil {
    		return fmt.Errorf("debit failed: %w", err)
    	}
    
    	if err := tx.Commit(ctx); err != nil {
    		return fmt.Errorf("commit failed: %w", err)
    	}
    	return nil
    }
    
    ```

=== "Rust"

    ```rust
    /// Moves money between two accounts in a single transaction.
    fn transfer(
        client: &mut Client,
        source: i32,
        target: i32,
        amount: i32,
    ) -> Result<(), postgres::Error> {
        // transaction() sends BEGIN. Dropping the transaction without calling
        // commit() rolls it back, so the ? operator that returns an error from
        // this function also undoes the work.
        let mut tx = client.transaction()?;
    
        // Credit the target first, so that a failure of the debit shows that
        // the rollback undoes the credit as well.
        tx.execute(
            "UPDATE accounts SET balance = balance + $1 WHERE id = $2",
            &[&amount, &target],
        )?;
        tx.execute(
            "UPDATE accounts SET balance = balance - $1 WHERE id = $2",
            &[&amount, &source],
        )?;
    
        tx.commit()
    }
    ```

=== "Ruby"

    ```ruby
    # Moves money between two accounts in a single transaction.
    def transfer(conn, source, target, amount)
      # The transaction method sends BEGIN, then COMMIT when the block ends
      # normally, or ROLLBACK if an exception leaves the block.
      conn.transaction do |tx|
        # Credit the target first, so that a failure of the debit shows that
        # the rollback undoes the credit as well.
        tx.exec_params(
          "UPDATE accounts SET balance = balance + $1 WHERE id = $2",
          [amount, target]
        )
        tx.exec_params(
          "UPDATE accounts SET balance = balance - $1 WHERE id = $2",
          [amount, source]
        )
      end
    end
    ```

=== "C"

    ```c
    /* The SQLSTATE and message of the statement that failed. */
    typedef struct
    {
        char sqlstate[6];
        char message[256];
    } Failure;
    
    /*
     * Run one statement with the given text parameters, and return true on
     * success. On failure, store the SQLSTATE and the message in *failure,
     * because the next command on the connection overwrites them.
     */
    static bool
    run_statement(PGconn *conn, const char *sql, int nparams,
                  const char *const *params, Failure *failure)
    {
        PGresult *res = PQexecParams(conn, sql, nparams, NULL, params,
                                     NULL, NULL, 0);
        ExecStatusType status = PQresultStatus(res);
        bool ok = status == PGRES_COMMAND_OK || status == PGRES_TUPLES_OK;
    
        if (!ok)
        {
            const char *state = PQresultErrorField(res, PG_DIAG_SQLSTATE);
    
            /* Connection failures carry no SQLSTATE, so store an empty one. */
            snprintf(failure->sqlstate, sizeof(failure->sqlstate), "%s",
                     state != NULL ? state : "");
            snprintf(failure->message, sizeof(failure->message), "%s",
                     PQerrorMessage(conn));
        }
        PQclear(res);
        return ok;
    }
    
    /*
     * Move money between two accounts in a single transaction, and return
     * true on success. On failure, the transaction has been rolled back and
     * *failure says why.
     */
    static bool
    transfer(PGconn *conn, int source, int target, int amount,
             Failure *failure)
    {
        char amount_text[16], source_text[16], target_text[16];
        const char *credit[2] = {amount_text, target_text};
        const char *debit[2] = {amount_text, source_text};
        bool ok;
    
        snprintf(amount_text, sizeof(amount_text), "%d", amount);
        snprintf(source_text, sizeof(source_text), "%d", source);
        snprintf(target_text, sizeof(target_text), "%d", target);
    
        /*
         * libpq has no transaction object, so the program sends BEGIN, COMMIT,
         * and ROLLBACK itself. Credit the target first, so that a failure of
         * the debit shows that the rollback undoes the credit as well.
         */
        ok = run_statement(conn, "BEGIN", 0, NULL, failure) &&
             run_statement(conn,
                           "UPDATE accounts SET balance = balance + $1 "
                           "WHERE id = $2", 2, credit, failure) &&
             run_statement(conn,
                           "UPDATE accounts SET balance = balance - $1 "
                           "WHERE id = $2", 2, debit, failure);
    
        if (ok)
            return run_statement(conn, "COMMIT", 0, NULL, failure);
    
        /*
         * Roll back, but keep the original failure. A ROLLBACK sent when BEGIN
         * itself failed does no harm, so no special case is needed.
         */
        PQclear(PQexec(conn, "ROLLBACK"));
        return false;
    }
    ```

## Reading the Balances

Each program reads a balance with a parameterised query, after the
transfers, to show the state that the server kept. The C and Ruby drivers
return every value as text, so those programs convert the value to an
integer. The following tabs show how each program reads a balance:

=== "Python"

    ```python
    def get_balance(conn: psycopg.Connection, account: int) -> int:
        """Returns the balance of the given account."""
        row = conn.execute(
            "SELECT balance FROM accounts WHERE id = %s", (account,)
        ).fetchone()
        return row[0]
    ```

=== "TypeScript"

    ```typescript
    // Returns the balance of the given account.
    async function getBalance(client: pg.Client, account: number): Promise<number> {
      const result = await client.query<{ balance: number }>(
        "SELECT balance FROM accounts WHERE id = $1",
        [account],
      );
      return result.rows[0].balance;
    }
    ```

=== "Java"

    ```java
    /** Returns the balance of the given account. */
    static int getBalance(Connection conn, int account) throws SQLException {
        String sql = "SELECT balance FROM accounts WHERE id = ?";
    
        // try-with-resources closes the statement and the result set when
        // each block exits, whether or not an error occurred.
        try (PreparedStatement stmt = conn.prepareStatement(sql)) {
            stmt.setInt(1, account);
    
            try (ResultSet rs = stmt.executeQuery()) {
                rs.next();
                return rs.getInt(1);
            }
        }
    }
    ```

=== "C#"

    ```csharp
    // Returns the balance of the given account.
    static async Task<int> GetBalanceAsync(NpgsqlConnection conn, int account)
    {
        await using var cmd = new NpgsqlCommand(
            "SELECT balance FROM accounts WHERE id = $1", conn)
        {
            Parameters = { new() { Value = account } },
        };
    
        // ExecuteScalarAsync returns the first column of the first row. An
        // int maps to int.
        return (int)(await cmd.ExecuteScalarAsync())!;
    }
    ```

=== "Go"

    ```go
    // getBalance returns the balance of the given account.
    func getBalance(ctx context.Context, conn *pgx.Conn, account int) (int, error) {
    	var balance int
    	err := conn.QueryRow(ctx,
    		"SELECT balance FROM accounts WHERE id = $1", account,
    	).Scan(&balance)
    	if err != nil {
    		return 0, fmt.Errorf("query failed: %w", err)
    	}
    	return balance, nil
    }
    
    ```

=== "Rust"

    ```rust
    /// Returns the balance of the given account.
    fn get_balance(client: &mut Client, account: i32) -> Result<i32, postgres::Error> {
        let row = client.query_one(
            "SELECT balance FROM accounts WHERE id = $1",
            &[&account],
        )?;
    
        // An int column maps to i32.
        Ok(row.get(0))
    }
    ```

=== "Ruby"

    ```ruby
    # Returns the balance of the given account.
    def get_balance(conn, account)
      result = conn.exec_params(
        "SELECT balance FROM accounts WHERE id = $1",
        [account]
      )
    
      # Results arrive as strings, so convert the value to an Integer.
      result.getvalue(0, 0).to_i
    end
    ```

=== "C"

    ```c
    /*
     * Store the balance of the given account in *balance, and return true on
     * success. On failure, PQerrorMessage() describes the error.
     */
    static bool
    get_balance(PGconn *conn, int account, int *balance)
    {
        char account_text[16];
        const char *params[] = {account_text};
        PGresult *res;
        bool ok;
    
        snprintf(account_text, sizeof(account_text), "%d", account);
        res = PQexecParams(conn, "SELECT balance FROM accounts WHERE id = $1",
                           1, NULL, params, NULL, NULL, 0);
        ok = PQresultStatus(res) == PGRES_TUPLES_OK;
    
        /* Results arrive as text, so convert the value to a number. */
        if (ok)
            *balance = atoi(PQgetvalue(res, 0, 0));
    
        PQclear(res);
        return ok;
    }
    ```

## Handling Errors and Closing the Connection

The main part of each program creates the accounts, makes the transfer of
30, and then attempts the transfer of 500. A check constraint violation
has the SQLSTATE code `23514`, and the program treats that single error as
an expected outcome: it reports that the transfer was rolled back and
carries on. Any other error is unexpected, so the program reports it on
`stderr` and exits with a non-zero status, as does a failure to connect.

The Python, Ruby, and C# programs catch a specific error class for the
constraint violation (`CheckViolation` in Python and Ruby, and a
`PostgresException` filtered on its SQLSTATE in C#). The TypeScript, Java,
and C programs compare the SQLSTATE code with `23514`, and the Go and Rust
programs do the same through the error types of their drivers. The program
also closes the connection when the work completes or fails, in the same
way as the first recipe. The following tabs show the main part of each
program:

=== "Python"

    ```python
    def main() -> int:
        try:
            # The with block closes the connection when it exits, whether or
            # not an error occurred.
            with connect() as conn:
                create_accounts(conn)
    
                transfer(conn, 1, 2, 30)
                print("Transferred 30 from account 1 to account 2")
    
                try:
                    transfer(conn, 1, 2, 500)
                    print("Transferred 500 from account 1 to account 2")
                # CheckViolation is SQLSTATE 23514. The transaction has already
                # been rolled back, so this is an expected outcome; any other
                # error is not, and reaches the handler below.
                except errors.CheckViolation:
                    print("Transfer of 500 from account 1 to account 2 "
                          "failed and was rolled back")
    
                for account in (1, 2):
                    print(f"Account {account} balance: "
                          f"{get_balance(conn, account)}")
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
    
    // Returns true for a check constraint violation, which is SQLSTATE 23514.
    function isCheckViolation(err: unknown): boolean {
      return err instanceof pg.DatabaseError && err.code === "23514";
    }
    
    async function main(): Promise<number> {
      let client: pg.Client | undefined;
      try {
        client = await connect();
        await createAccounts(client);
    
        await transfer(client, 1, 2, 30);
        console.log("Transferred 30 from account 1 to account 2");
    
        try {
          await transfer(client, 1, 2, 500);
          console.log("Transferred 500 from account 1 to account 2");
        } catch (err) {
          // The transaction has already been rolled back, so a check violation
          // is an expected outcome; any other error is not, and reaches the
          // handler below.
          if (!isCheckViolation(err)) {
            throw err;
          }
          console.log(
            "Transfer of 500 from account 1 to account 2 " +
              "failed and was rolled back",
          );
        }
    
        for (const account of [1, 2]) {
          console.log(`Account ${account} balance: ${await getBalance(client, account)}`);
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
            createAccounts(conn);
    
            transfer(conn, 1, 2, 30);
            System.out.println("Transferred 30 from account 1 to account 2");
    
            try {
                transfer(conn, 1, 2, 500);
                System.out.println(
                        "Transferred 500 from account 1 to account 2");
            } catch (SQLException e) {
                // SQLSTATE 23514 is a check constraint violation. The
                // transaction has already been rolled back, so this is an
                // expected outcome; any other error is not, and reaches
                // the handler below.
                if (!"23514".equals(e.getSQLState())) {
                    throw e;
                }
                System.out.println("Transfer of 500 from account 1 to "
                        + "account 2 failed and was rolled back");
            }
    
            for (int account = 1; account <= 2; account++) {
                System.out.println("Account " + account + " balance: "
                        + getBalance(conn, account));
            }
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
    
        await CreateAccountsAsync(conn);
    
        await TransferAsync(conn, 1, 2, 30);
        Console.WriteLine("Transferred 30 from account 1 to account 2");
    
        try
        {
            await TransferAsync(conn, 1, 2, 500);
            Console.WriteLine("Transferred 500 from account 1 to account 2");
        }
        // SQLSTATE 23514 is a check constraint violation. The transaction has
        // already been rolled back, so this is an expected outcome; any other
        // error is not, and reaches the handler below.
        catch (PostgresException e) when (
            e.SqlState == PostgresErrorCodes.CheckViolation)
        {
            Console.WriteLine(
                "Transfer of 500 from account 1 to account 2 " +
                "failed and was rolled back");
        }
    
        foreach (var account in new[] { 1, 2 })
        {
            Console.WriteLine(
                $"Account {account} balance: {await GetBalanceAsync(conn, account)}");
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
    // isCheckViolation reports whether err is a check constraint violation,
    // which is SQLSTATE 23514.
    func isCheckViolation(err error) bool {
    	var pgErr *pgconn.PgError
    	return errors.As(err, &pgErr) && pgErr.Code == "23514"
    }
    
    // run connects, makes the transfers, and prints the balances, returning
    // any error to the caller.
    func run(ctx context.Context) error {
    	conn, err := connect(ctx)
    	if err != nil {
    		return err
    	}
    	// The deferred call closes the connection when run() returns, whether
    	// or not an error occurred.
    	defer conn.Close(ctx)
    
    	if err := createAccounts(ctx, conn); err != nil {
    		return err
    	}
    
    	if err := transfer(ctx, conn, 1, 2, 30); err != nil {
    		return err
    	}
    	fmt.Println("Transferred 30 from account 1 to account 2")
    
    	// The transaction has already been rolled back, so a check violation
    	// is an expected outcome; any other error is not, and is returned.
    	err = transfer(ctx, conn, 1, 2, 500)
    	switch {
    	case err == nil:
    		fmt.Println("Transferred 500 from account 1 to account 2")
    	case isCheckViolation(err):
    		fmt.Println("Transfer of 500 from account 1 to account 2 failed and was rolled back")
    	default:
    		return err
    	}
    
    	for _, account := range []int{1, 2} {
    		balance, err := getBalance(ctx, conn, account)
    		if err != nil {
    			return err
    		}
    		fmt.Printf("Account %d balance: %d\n", account, balance)
    	}
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
    /// Connects, makes the transfers, and prints the balances. The ? operator
    /// returns any error to the caller.
    fn run() -> Result<(), postgres::Error> {
        let mut client = connect()?;
        create_accounts(&mut client)?;
    
        transfer(&mut client, 1, 2, 30)?;
        println!("Transferred 30 from account 1 to account 2");
    
        // A check constraint violation is an expected outcome, because the
        // transaction has already been rolled back; any other error is not,
        // and is returned.
        match transfer(&mut client, 1, 2, 500) {
            Ok(()) => println!("Transferred 500 from account 1 to account 2"),
            Err(e) if e.code() == Some(&SqlState::CHECK_VIOLATION) => {
                println!("Transfer of 500 from account 1 to account 2 failed and was rolled back");
            }
            Err(e) => return Err(e),
        }
    
        for account in [1, 2] {
            println!("Account {account} balance: {}", get_balance(&mut client, account)?);
        }
    
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
      create_accounts(conn)
    
      transfer(conn, 1, 2, 30)
      puts "Transferred 30 from account 1 to account 2"
    
      begin
        transfer(conn, 1, 2, 500)
        puts "Transferred 500 from account 1 to account 2"
      # PG::CheckViolation is SQLSTATE 23514. The transaction has already been
      # rolled back, so this is an expected outcome; any other error is not,
      # and reaches the handler below.
      rescue PG::CheckViolation
        puts "Transfer of 500 from account 1 to account 2 " \
             "failed and was rolled back"
      end
    
      [1, 2].each do |account|
        puts "Account #{account} balance: #{get_balance(conn, account)}"
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
     * Make the transfers and print the balances, and return true on success.
     * On failure, *failure holds the message to report.
     */
    static bool
    run_example(PGconn *conn, Failure *failure)
    {
        int account, balance;
    
        if (!create_accounts(conn))
        {
            snprintf(failure->message, sizeof(failure->message), "%s",
                     PQerrorMessage(conn));
            return false;
        }
    
        if (!transfer(conn, 1, 2, 30, failure))
            return false;
        printf("Transferred 30 from account 1 to account 2\n");
    
        /*
         * SQLSTATE 23514 is a check constraint violation. The transaction has
         * already been rolled back, so this is an expected outcome; any other
         * error is not, and is reported as a failure.
         */
        if (transfer(conn, 1, 2, 500, failure))
            printf("Transferred 500 from account 1 to account 2\n");
        else if (strcmp(failure->sqlstate, "23514") == 0)
            printf("Transfer of 500 from account 1 to account 2 "
                   "failed and was rolled back\n");
        else
            return false;
    
        for (account = 1; account <= 2; account++)
        {
            if (!get_balance(conn, account, &balance))
            {
                snprintf(failure->message, sizeof(failure->message), "%s",
                         PQerrorMessage(conn));
                return false;
            }
            printf("Account %d balance: %d\n", account, balance);
        }
        return true;
    }
    
    int
    main(void)
    {
        int status = EXIT_FAILURE;
        Failure failure = {"", ""};
        PGconn *conn = connect_to_server();
    
        if (PQstatus(conn) != CONNECTION_OK)
            fprintf(stderr, "Database error: %s", PQerrorMessage(conn));
        else if (!run_example(conn, &failure))
            fprintf(stderr, "Database error: %s", failure.message);
        else
            status = EXIT_SUCCESS;
    
        /* Close the connection whether or not an error occurred. */
        PQfinish(conn);
        return status;
    }
    ```

## Running the Example

The complete project for each language is available in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/postgresql/transactions).
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
    Using transactions to move money between accounts, using psycopg 3.
    
    Copyright (c) 2026, pgEdge, Inc.
    This code is released under the PostgreSQL License.
    """
    
    import os
    import sys
    
    import psycopg
    from psycopg import errors
    
    
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
    
        By default psycopg opens a transaction before the first statement and
        keeps it open until the program commits. Autocommit mode turns that
        off, so that each statement commits by itself and the program decides
        exactly where each transaction begins and ends.
        """
        return psycopg.connect(**connection_settings(), autocommit=True)
    
    
    def create_accounts(conn: psycopg.Connection) -> None:
        """Creates a temporary table of two accounts. The CHECK constraint
        stops any balance from going below zero."""
        conn.execute(
            "CREATE TEMPORARY TABLE accounts ("
            "id int PRIMARY KEY, "
            "balance int NOT NULL CHECK (balance >= 0))"
        )
        conn.execute("INSERT INTO accounts VALUES (1, 100), (2, 50)")
    
    
    def transfer(conn: psycopg.Connection, source: int, target: int,
                 amount: int) -> None:
        """Moves money between two accounts in a single transaction."""
        # The with block begins a transaction, commits it when the block ends
        # normally, and rolls it back if an exception leaves the block.
        with conn.transaction():
            # Credit the target first, so that a failure of the debit shows
            # that the rollback undoes the credit as well.
            conn.execute(
                "UPDATE accounts SET balance = balance + %s WHERE id = %s",
                (amount, target),
            )
            conn.execute(
                "UPDATE accounts SET balance = balance - %s WHERE id = %s",
                (amount, source),
            )
    
    
    def get_balance(conn: psycopg.Connection, account: int) -> int:
        """Returns the balance of the given account."""
        row = conn.execute(
            "SELECT balance FROM accounts WHERE id = %s", (account,)
        ).fetchone()
        return row[0]
    
    
    def main() -> int:
        try:
            # The with block closes the connection when it exits, whether or
            # not an error occurred.
            with connect() as conn:
                create_accounts(conn)
    
                transfer(conn, 1, 2, 30)
                print("Transferred 30 from account 1 to account 2")
    
                try:
                    transfer(conn, 1, 2, 500)
                    print("Transferred 500 from account 1 to account 2")
                # CheckViolation is SQLSTATE 23514. The transaction has already
                # been rolled back, so this is an expected outcome; any other
                # error is not, and reaches the handler below.
                except errors.CheckViolation:
                    print("Transfer of 500 from account 1 to account 2 "
                          "failed and was rolled back")
    
                for account in (1, 2):
                    print(f"Account {account} balance: "
                          f"{get_balance(conn, account)}")
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
     * Using transactions to move money between accounts, using node-postgres.
     *
     * Copyright (c) 2026, pgEdge, Inc.
     * This code is released under the PostgreSQL License.
     */
    
    import pg from "pg";
    
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
    
    // Opens a connection with the settings from the environment.
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
    
    // Creates a temporary table of two accounts. The CHECK constraint stops
    // any balance from going below zero.
    async function createAccounts(client: pg.Client): Promise<void> {
      await client.query(
        "CREATE TEMPORARY TABLE accounts (" +
          "id int PRIMARY KEY, " +
          "balance int NOT NULL CHECK (balance >= 0))",
      );
      await client.query("INSERT INTO accounts VALUES (1, 100), (2, 50)");
    }
    
    // Moves money between two accounts in a single transaction.
    async function transfer(
      client: pg.Client,
      source: number,
      target: number,
      amount: number,
    ): Promise<void> {
      // node-postgres has no transaction object, so the program sends BEGIN,
      // COMMIT, and ROLLBACK itself. Everything sent on this client between
      // BEGIN and COMMIT belongs to the transaction.
      await client.query("BEGIN");
      try {
        // Credit the target first, so that a failure of the debit shows that
        // the rollback undoes the credit as well.
        await client.query(
          "UPDATE accounts SET balance = balance + $1 WHERE id = $2",
          [amount, target],
        );
        await client.query(
          "UPDATE accounts SET balance = balance - $1 WHERE id = $2",
          [amount, source],
        );
        await client.query("COMMIT");
      } catch (err) {
        // Undo the work, then pass the original error to the caller. If the
        // rollback fails too (for example, because the connection has gone),
        // ignore that failure so that it does not hide the original error.
        await client.query("ROLLBACK").catch(() => {});
        throw err;
      }
    }
    
    // Returns the balance of the given account.
    async function getBalance(client: pg.Client, account: number): Promise<number> {
      const result = await client.query<{ balance: number }>(
        "SELECT balance FROM accounts WHERE id = $1",
        [account],
      );
      return result.rows[0].balance;
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
    
    // Returns true for a check constraint violation, which is SQLSTATE 23514.
    function isCheckViolation(err: unknown): boolean {
      return err instanceof pg.DatabaseError && err.code === "23514";
    }
    
    async function main(): Promise<number> {
      let client: pg.Client | undefined;
      try {
        client = await connect();
        await createAccounts(client);
    
        await transfer(client, 1, 2, 30);
        console.log("Transferred 30 from account 1 to account 2");
    
        try {
          await transfer(client, 1, 2, 500);
          console.log("Transferred 500 from account 1 to account 2");
        } catch (err) {
          // The transaction has already been rolled back, so a check violation
          // is an expected outcome; any other error is not, and reaches the
          // handler below.
          if (!isCheckViolation(err)) {
            throw err;
          }
          console.log(
            "Transfer of 500 from account 1 to account 2 " +
              "failed and was rolled back",
          );
        }
    
        for (const account of [1, 2]) {
          console.log(`Account ${account} balance: ${await getBalance(client, account)}`);
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
     * Using transactions to move money between accounts, using JDBC and the
     * PostgreSQL JDBC driver (pgJDBC).
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
    
        /** Opens a connection with the settings from the environment. */
        static Connection connect() throws SQLException {
            return DriverManager.getConnection(
                    connectionUrl(), connectionProperties());
        }
    
        /**
         * Creates a temporary table of two accounts. The CHECK constraint
         * stops any balance from going below zero.
         */
        static void createAccounts(Connection conn) throws SQLException {
            // The connection is in autocommit mode here, so each statement
            // commits by itself.
            try (Statement stmt = conn.createStatement()) {
                stmt.execute("CREATE TEMPORARY TABLE accounts ("
                        + "id int PRIMARY KEY, "
                        + "balance int NOT NULL CHECK (balance >= 0))");
                stmt.execute("INSERT INTO accounts VALUES (1, 100), (2, 50)");
            }
        }
    
        /** Moves money between two accounts in a single transaction. */
        static void transfer(Connection conn, int source, int target, int amount)
                throws SQLException {
            // JDBC starts in autocommit mode. Turning it off makes the driver
            // open a transaction that lasts until commit() or rollback().
            conn.setAutoCommit(false);
            try {
                // Credit the target first, so that a failure of the debit
                // shows that the rollback undoes the credit as well.
                update(conn,
                        "UPDATE accounts SET balance = balance + ? WHERE id = ?",
                        amount, target);
                update(conn,
                        "UPDATE accounts SET balance = balance - ? WHERE id = ?",
                        amount, source);
                conn.commit();
            } catch (Exception e) {
                // Undo the work, then pass the original error to the caller.
                // If the rollback fails too, attach that failure to the
                // original rather than letting it hide the cause.
                try {
                    conn.rollback();
                } catch (SQLException rollbackError) {
                    e.addSuppressed(rollbackError);
                }
                throw e;
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
    
        /** Runs an UPDATE statement that takes two integer parameters. */
        static void update(Connection conn, String sql, int first, int second)
                throws SQLException {
            try (PreparedStatement stmt = conn.prepareStatement(sql)) {
                stmt.setInt(1, first);
                stmt.setInt(2, second);
                stmt.executeUpdate();
            }
        }
    
        /** Returns the balance of the given account. */
        static int getBalance(Connection conn, int account) throws SQLException {
            String sql = "SELECT balance FROM accounts WHERE id = ?";
    
            // try-with-resources closes the statement and the result set when
            // each block exits, whether or not an error occurred.
            try (PreparedStatement stmt = conn.prepareStatement(sql)) {
                stmt.setInt(1, account);
    
                try (ResultSet rs = stmt.executeQuery()) {
                    rs.next();
                    return rs.getInt(1);
                }
            }
        }
    
        public static void main(String[] args) {
            // try-with-resources closes the connection when the block exits,
            // whether or not an error occurred.
            try (Connection conn = connect()) {
                createAccounts(conn);
    
                transfer(conn, 1, 2, 30);
                System.out.println("Transferred 30 from account 1 to account 2");
    
                try {
                    transfer(conn, 1, 2, 500);
                    System.out.println(
                            "Transferred 500 from account 1 to account 2");
                } catch (SQLException e) {
                    // SQLSTATE 23514 is a check constraint violation. The
                    // transaction has already been rolled back, so this is an
                    // expected outcome; any other error is not, and reaches
                    // the handler below.
                    if (!"23514".equals(e.getSQLState())) {
                        throw e;
                    }
                    System.out.println("Transfer of 500 from account 1 to "
                            + "account 2 failed and was rolled back");
                }
    
                for (int account = 1; account <= 2; account++) {
                    System.out.println("Account " + account + " balance: "
                            + getBalance(conn, account));
                }
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
     * Using transactions to move money between accounts, using Npgsql.
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
    // OpenConnectionAsync borrows one from the pool; an application normally
    // creates one data source at start-up and shares it. A temporary table
    // belongs to one physical connection, so this program borrows a single
    // connection and uses it throughout.
    static NpgsqlDataSource CreateDataSource() =>
        NpgsqlDataSource.Create(ConnectionString());
    
    // Creates a temporary table of two accounts. The CHECK constraint stops
    // any balance from going below zero.
    static async Task CreateAccountsAsync(NpgsqlConnection conn)
    {
        await using var cmd = new NpgsqlCommand(
            "CREATE TEMPORARY TABLE accounts (" +
            "id int PRIMARY KEY, " +
            "balance int NOT NULL CHECK (balance >= 0)); " +
            "INSERT INTO accounts VALUES (1, 100), (2, 50)", conn);
        await cmd.ExecuteNonQueryAsync();
    }
    
    // Moves money between two accounts in a single transaction.
    static async Task TransferAsync(
        NpgsqlConnection conn, int source, int target, int amount)
    {
        // BeginTransactionAsync sends BEGIN. Disposing of the transaction
        // without committing it rolls the transaction back, so an exception
        // thrown below undoes the work.
        await using var tx = await conn.BeginTransactionAsync();
    
        // Credit the target first, so that a failure of the debit shows that
        // the rollback undoes the credit as well. Positional parameters are
        // written $1, $2, and so on.
        await using (var credit = new NpgsqlCommand(
            "UPDATE accounts SET balance = balance + $1 WHERE id = $2", conn, tx)
        {
            Parameters = { new() { Value = amount }, new() { Value = target } },
        })
        {
            await credit.ExecuteNonQueryAsync();
        }
    
        await using (var debit = new NpgsqlCommand(
            "UPDATE accounts SET balance = balance - $1 WHERE id = $2", conn, tx)
        {
            Parameters = { new() { Value = amount }, new() { Value = source } },
        })
        {
            await debit.ExecuteNonQueryAsync();
        }
    
        await tx.CommitAsync();
    }
    
    // Returns the balance of the given account.
    static async Task<int> GetBalanceAsync(NpgsqlConnection conn, int account)
    {
        await using var cmd = new NpgsqlCommand(
            "SELECT balance FROM accounts WHERE id = $1", conn)
        {
            Parameters = { new() { Value = account } },
        };
    
        // ExecuteScalarAsync returns the first column of the first row. An
        // int maps to int.
        return (int)(await cmd.ExecuteScalarAsync())!;
    }
    
    try
    {
        // await using disposes of the data source, and returns the connection
        // to the pool, when the block exits, whether or not an error occurred.
        await using var dataSource = CreateDataSource();
        await using var conn = await dataSource.OpenConnectionAsync();
    
        await CreateAccountsAsync(conn);
    
        await TransferAsync(conn, 1, 2, 30);
        Console.WriteLine("Transferred 30 from account 1 to account 2");
    
        try
        {
            await TransferAsync(conn, 1, 2, 500);
            Console.WriteLine("Transferred 500 from account 1 to account 2");
        }
        // SQLSTATE 23514 is a check constraint violation. The transaction has
        // already been rolled back, so this is an expected outcome; any other
        // error is not, and reaches the handler below.
        catch (PostgresException e) when (
            e.SqlState == PostgresErrorCodes.CheckViolation)
        {
            Console.WriteLine(
                "Transfer of 500 from account 1 to account 2 " +
                "failed and was rolled back");
        }
    
        foreach (var account in new[] { 1, 2 })
        {
            Console.WriteLine(
                $"Account {account} balance: {await GetBalanceAsync(conn, account)}");
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
    // Using transactions to move money between accounts, using pgx.
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
    
    
    // createAccounts creates a temporary table of two accounts. The CHECK
    // constraint stops any balance from going below zero.
    func createAccounts(ctx context.Context, conn *pgx.Conn) error {
    	_, err := conn.Exec(ctx,
    		"CREATE TEMPORARY TABLE accounts ("+
    			"id int PRIMARY KEY, "+
    			"balance int NOT NULL CHECK (balance >= 0))")
    	if err != nil {
    		return fmt.Errorf("create table failed: %w", err)
    	}
    	_, err = conn.Exec(ctx, "INSERT INTO accounts VALUES (1, 100), (2, 50)")
    	if err != nil {
    		return fmt.Errorf("insert failed: %w", err)
    	}
    	return nil
    }
    
    
    // transfer moves money between two accounts in a single transaction.
    func transfer(ctx context.Context, conn *pgx.Conn, source, target, amount int) error {
    	tx, err := conn.Begin(ctx)
    	if err != nil {
    		return fmt.Errorf("begin failed: %w", err)
    	}
    	// Rollback does nothing once the transaction has committed, so the
    	// deferred call undoes the work only if a statement fails first.
    	defer tx.Rollback(ctx)
    
    	// Credit the target first, so that a failure of the debit shows that
    	// the rollback undoes the credit as well.
    	_, err = tx.Exec(ctx,
    		"UPDATE accounts SET balance = balance + $1 WHERE id = $2",
    		amount, target)
    	if err != nil {
    		return fmt.Errorf("credit failed: %w", err)
    	}
    	_, err = tx.Exec(ctx,
    		"UPDATE accounts SET balance = balance - $1 WHERE id = $2",
    		amount, source)
    	if err != nil {
    		return fmt.Errorf("debit failed: %w", err)
    	}
    
    	if err := tx.Commit(ctx); err != nil {
    		return fmt.Errorf("commit failed: %w", err)
    	}
    	return nil
    }
    
    
    // getBalance returns the balance of the given account.
    func getBalance(ctx context.Context, conn *pgx.Conn, account int) (int, error) {
    	var balance int
    	err := conn.QueryRow(ctx,
    		"SELECT balance FROM accounts WHERE id = $1", account,
    	).Scan(&balance)
    	if err != nil {
    		return 0, fmt.Errorf("query failed: %w", err)
    	}
    	return balance, nil
    }
    
    
    // isCheckViolation reports whether err is a check constraint violation,
    // which is SQLSTATE 23514.
    func isCheckViolation(err error) bool {
    	var pgErr *pgconn.PgError
    	return errors.As(err, &pgErr) && pgErr.Code == "23514"
    }
    
    // run connects, makes the transfers, and prints the balances, returning
    // any error to the caller.
    func run(ctx context.Context) error {
    	conn, err := connect(ctx)
    	if err != nil {
    		return err
    	}
    	// The deferred call closes the connection when run() returns, whether
    	// or not an error occurred.
    	defer conn.Close(ctx)
    
    	if err := createAccounts(ctx, conn); err != nil {
    		return err
    	}
    
    	if err := transfer(ctx, conn, 1, 2, 30); err != nil {
    		return err
    	}
    	fmt.Println("Transferred 30 from account 1 to account 2")
    
    	// The transaction has already been rolled back, so a check violation
    	// is an expected outcome; any other error is not, and is returned.
    	err = transfer(ctx, conn, 1, 2, 500)
    	switch {
    	case err == nil:
    		fmt.Println("Transferred 500 from account 1 to account 2")
    	case isCheckViolation(err):
    		fmt.Println("Transfer of 500 from account 1 to account 2 failed and was rolled back")
    	default:
    		return err
    	}
    
    	for _, account := range []int{1, 2} {
    		balance, err := getBalance(ctx, conn, account)
    		if err != nil {
    			return err
    		}
    		fmt.Printf("Account %d balance: %d\n", account, balance)
    	}
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
    // Using transactions to move money between accounts, using the postgres
    // crate.
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
    /// connections over an untrusted network should use TLS.
    fn connect() -> Result<Client, postgres::Error> {
        config().connect(NoTls)
    }
    
    /// Creates a temporary table of two accounts. The CHECK constraint stops
    /// any balance from going below zero. batch_execute runs statements that
    /// take no parameters.
    fn create_accounts(client: &mut Client) -> Result<(), postgres::Error> {
        client.batch_execute(
            "CREATE TEMPORARY TABLE accounts (
                 id int PRIMARY KEY,
                 balance int NOT NULL CHECK (balance >= 0));
             INSERT INTO accounts VALUES (1, 100), (2, 50)",
        )
    }
    
    /// Moves money between two accounts in a single transaction.
    fn transfer(
        client: &mut Client,
        source: i32,
        target: i32,
        amount: i32,
    ) -> Result<(), postgres::Error> {
        // transaction() sends BEGIN. Dropping the transaction without calling
        // commit() rolls it back, so the ? operator that returns an error from
        // this function also undoes the work.
        let mut tx = client.transaction()?;
    
        // Credit the target first, so that a failure of the debit shows that
        // the rollback undoes the credit as well.
        tx.execute(
            "UPDATE accounts SET balance = balance + $1 WHERE id = $2",
            &[&amount, &target],
        )?;
        tx.execute(
            "UPDATE accounts SET balance = balance - $1 WHERE id = $2",
            &[&amount, &source],
        )?;
    
        tx.commit()
    }
    
    /// Returns the balance of the given account.
    fn get_balance(client: &mut Client, account: i32) -> Result<i32, postgres::Error> {
        let row = client.query_one(
            "SELECT balance FROM accounts WHERE id = $1",
            &[&account],
        )?;
    
        // An int column maps to i32.
        Ok(row.get(0))
    }
    
    /// Connects, makes the transfers, and prints the balances. The ? operator
    /// returns any error to the caller.
    fn run() -> Result<(), postgres::Error> {
        let mut client = connect()?;
        create_accounts(&mut client)?;
    
        transfer(&mut client, 1, 2, 30)?;
        println!("Transferred 30 from account 1 to account 2");
    
        // A check constraint violation is an expected outcome, because the
        // transaction has already been rolled back; any other error is not,
        // and is returned.
        match transfer(&mut client, 1, 2, 500) {
            Ok(()) => println!("Transferred 500 from account 1 to account 2"),
            Err(e) if e.code() == Some(&SqlState::CHECK_VIOLATION) => {
                println!("Transfer of 500 from account 1 to account 2 failed and was rolled back");
            }
            Err(e) => return Err(e),
        }
    
        for account in [1, 2] {
            println!("Account {account} balance: {}", get_balance(&mut client, account)?);
        }
    
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
    # Using transactions to move money between accounts, using the pg gem.
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
      {
        host: env_or("PGHOST", "localhost"),
        port: env_or("PGPORT", "5432"),
        dbname: env_or("PGDATABASE", "postgres"),
        user: env_or("PGUSER", "postgres"),
        password: env_or("PGPASSWORD", nil)
      }.compact
    end
    
    # Opens a connection with the settings from the environment.
    def connect
      PG.connect(connection_params)
    end
    
    # Creates a temporary table of two accounts. The CHECK constraint stops
    # any balance from going below zero.
    def create_accounts(conn)
      conn.exec(
        "CREATE TEMPORARY TABLE accounts (" \
        "id int PRIMARY KEY, " \
        "balance int NOT NULL CHECK (balance >= 0))"
      )
      conn.exec("INSERT INTO accounts VALUES (1, 100), (2, 50)")
    end
    
    # Moves money between two accounts in a single transaction.
    def transfer(conn, source, target, amount)
      # The transaction method sends BEGIN, then COMMIT when the block ends
      # normally, or ROLLBACK if an exception leaves the block.
      conn.transaction do |tx|
        # Credit the target first, so that a failure of the debit shows that
        # the rollback undoes the credit as well.
        tx.exec_params(
          "UPDATE accounts SET balance = balance + $1 WHERE id = $2",
          [amount, target]
        )
        tx.exec_params(
          "UPDATE accounts SET balance = balance - $1 WHERE id = $2",
          [amount, source]
        )
      end
    end
    
    # Returns the balance of the given account.
    def get_balance(conn, account)
      result = conn.exec_params(
        "SELECT balance FROM accounts WHERE id = $1",
        [account]
      )
    
      # Results arrive as strings, so convert the value to an Integer.
      result.getvalue(0, 0).to_i
    end
    
    begin
      conn = connect
      create_accounts(conn)
    
      transfer(conn, 1, 2, 30)
      puts "Transferred 30 from account 1 to account 2"
    
      begin
        transfer(conn, 1, 2, 500)
        puts "Transferred 500 from account 1 to account 2"
      # PG::CheckViolation is SQLSTATE 23514. The transaction has already been
      # rolled back, so this is an expected outcome; any other error is not,
      # and reaches the handler below.
      rescue PG::CheckViolation
        puts "Transfer of 500 from account 1 to account 2 " \
             "failed and was rolled back"
      end
    
      [1, 2].each do |account|
        puts "Account #{account} balance: #{get_balance(conn, account)}"
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
     * Using transactions to move money between accounts, using libpq.
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
     */
    static PGconn *
    connect_to_server(void)
    {
        const char *values[sizeof(keywords) / sizeof(keywords[0])];
    
        read_settings(values);
        return PQconnectdbParams(keywords, values, 0);
    }
    
    /*
     * Create a temporary table of two accounts, and return true on success.
     * The CHECK constraint stops any balance from going below zero. PQexec()
     * runs both statements, which need no parameters, in a single call.
     */
    static bool
    create_accounts(PGconn *conn)
    {
        PGresult *res = PQexec(conn,
                               "CREATE TEMPORARY TABLE accounts ("
                               "id int PRIMARY KEY, "
                               "balance int NOT NULL CHECK (balance >= 0)); "
                               "INSERT INTO accounts VALUES (1, 100), (2, 50)");
        bool ok = PQresultStatus(res) == PGRES_COMMAND_OK;
    
        PQclear(res);
        return ok;
    }
    
    /* The SQLSTATE and message of the statement that failed. */
    typedef struct
    {
        char sqlstate[6];
        char message[256];
    } Failure;
    
    /*
     * Run one statement with the given text parameters, and return true on
     * success. On failure, store the SQLSTATE and the message in *failure,
     * because the next command on the connection overwrites them.
     */
    static bool
    run_statement(PGconn *conn, const char *sql, int nparams,
                  const char *const *params, Failure *failure)
    {
        PGresult *res = PQexecParams(conn, sql, nparams, NULL, params,
                                     NULL, NULL, 0);
        ExecStatusType status = PQresultStatus(res);
        bool ok = status == PGRES_COMMAND_OK || status == PGRES_TUPLES_OK;
    
        if (!ok)
        {
            const char *state = PQresultErrorField(res, PG_DIAG_SQLSTATE);
    
            /* Connection failures carry no SQLSTATE, so store an empty one. */
            snprintf(failure->sqlstate, sizeof(failure->sqlstate), "%s",
                     state != NULL ? state : "");
            snprintf(failure->message, sizeof(failure->message), "%s",
                     PQerrorMessage(conn));
        }
        PQclear(res);
        return ok;
    }
    
    /*
     * Move money between two accounts in a single transaction, and return
     * true on success. On failure, the transaction has been rolled back and
     * *failure says why.
     */
    static bool
    transfer(PGconn *conn, int source, int target, int amount,
             Failure *failure)
    {
        char amount_text[16], source_text[16], target_text[16];
        const char *credit[2] = {amount_text, target_text};
        const char *debit[2] = {amount_text, source_text};
        bool ok;
    
        snprintf(amount_text, sizeof(amount_text), "%d", amount);
        snprintf(source_text, sizeof(source_text), "%d", source);
        snprintf(target_text, sizeof(target_text), "%d", target);
    
        /*
         * libpq has no transaction object, so the program sends BEGIN, COMMIT,
         * and ROLLBACK itself. Credit the target first, so that a failure of
         * the debit shows that the rollback undoes the credit as well.
         */
        ok = run_statement(conn, "BEGIN", 0, NULL, failure) &&
             run_statement(conn,
                           "UPDATE accounts SET balance = balance + $1 "
                           "WHERE id = $2", 2, credit, failure) &&
             run_statement(conn,
                           "UPDATE accounts SET balance = balance - $1 "
                           "WHERE id = $2", 2, debit, failure);
    
        if (ok)
            return run_statement(conn, "COMMIT", 0, NULL, failure);
    
        /*
         * Roll back, but keep the original failure. A ROLLBACK sent when BEGIN
         * itself failed does no harm, so no special case is needed.
         */
        PQclear(PQexec(conn, "ROLLBACK"));
        return false;
    }
    
    /*
     * Store the balance of the given account in *balance, and return true on
     * success. On failure, PQerrorMessage() describes the error.
     */
    static bool
    get_balance(PGconn *conn, int account, int *balance)
    {
        char account_text[16];
        const char *params[] = {account_text};
        PGresult *res;
        bool ok;
    
        snprintf(account_text, sizeof(account_text), "%d", account);
        res = PQexecParams(conn, "SELECT balance FROM accounts WHERE id = $1",
                           1, NULL, params, NULL, NULL, 0);
        ok = PQresultStatus(res) == PGRES_TUPLES_OK;
    
        /* Results arrive as text, so convert the value to a number. */
        if (ok)
            *balance = atoi(PQgetvalue(res, 0, 0));
    
        PQclear(res);
        return ok;
    }
    
    /*
     * Make the transfers and print the balances, and return true on success.
     * On failure, *failure holds the message to report.
     */
    static bool
    run_example(PGconn *conn, Failure *failure)
    {
        int account, balance;
    
        if (!create_accounts(conn))
        {
            snprintf(failure->message, sizeof(failure->message), "%s",
                     PQerrorMessage(conn));
            return false;
        }
    
        if (!transfer(conn, 1, 2, 30, failure))
            return false;
        printf("Transferred 30 from account 1 to account 2\n");
    
        /*
         * SQLSTATE 23514 is a check constraint violation. The transaction has
         * already been rolled back, so this is an expected outcome; any other
         * error is not, and is reported as a failure.
         */
        if (transfer(conn, 1, 2, 500, failure))
            printf("Transferred 500 from account 1 to account 2\n");
        else if (strcmp(failure->sqlstate, "23514") == 0)
            printf("Transfer of 500 from account 1 to account 2 "
                   "failed and was rolled back\n");
        else
            return false;
    
        for (account = 1; account <= 2; account++)
        {
            if (!get_balance(conn, account, &balance))
            {
                snprintf(failure->message, sizeof(failure->message), "%s",
                         PQerrorMessage(conn));
                return false;
            }
            printf("Account %d balance: %d\n", account, balance);
        }
        return true;
    }
    
    int
    main(void)
    {
        int status = EXIT_FAILURE;
        Failure failure = {"", ""};
        PGconn *conn = connect_to_server();
    
        if (PQstatus(conn) != CONNECTION_OK)
            fprintf(stderr, "Database error: %s", PQerrorMessage(conn));
        else if (!run_example(conn, &failure))
            fprintf(stderr, "Database error: %s", failure.message);
        else
            status = EXIT_SUCCESS;
    
        /* Close the connection whether or not an error occurred. */
        PQfinish(conn);
        return status;
    }
    
    ```

## Next Steps

The following resources provide more information about the topics in this
recipe:

- The [Connecting to PostgreSQL and Running a Query](connect_and_query.md)
  recipe explains the connection settings in more detail.
- The PostgreSQL documentation for
  [transactions](https://www.postgresql.org/docs/current/tutorial-transactions.html)
  introduces the concept with an example.
- The PostgreSQL documentation for
  [error codes](https://www.postgresql.org/docs/current/errcodes-appendix.html)
  lists every SQLSTATE code, including `23514`.
- The PostgreSQL documentation for
  [constraints](https://www.postgresql.org/docs/current/ddl-constraints.html)
  describes check constraints and the other kinds.
