# Connecting to PostgreSQL and Running a Query

This recipe demonstrates how an application connects to a PostgreSQL server
and runs a query that returns a single value. The example passes a value to
the query as a parameter, which is the safe way to send application data to
the database server. Each step shows the code in every supported language;
selecting a language tab switches every tab on the site to that language.

The example program counts the rows in the `pg_catalog.pg_type` system
catalog that describe the `int4` data type. The query always returns the
value 1 on any PostgreSQL server, which makes the output easy to verify:

```text
Number of types named 'int4': 1
```

## Preparing the Ingredients

Each example uses the most widely adopted PostgreSQL driver for its
language. The following table lists the driver that each example uses:

| Language   | Driver                                                 |
|------------|--------------------------------------------------------|
| Python     | [psycopg 3](https://www.psycopg.org/psycopg3/)         |
| TypeScript | [node-postgres](https://node-postgres.com/)            |
| Java       | [pgJDBC](https://jdbc.postgresql.org/)                 |
| C#         | [Npgsql](https://www.npgsql.org/)                      |
| Go         | [pgx](https://github.com/jackc/pgx)                    |
| Rust       | [rust-postgres](https://github.com/rust-postgres/rust-postgres) |
| Ruby       | [ruby-pg](https://github.com/ged/ruby-pg)              |
| C          | [libpq](https://www.postgresql.org/docs/current/libpq.html) |

The C example links against libpq, so the example requires the libpq
client library and headers; on Debian and Ubuntu, the `libpq-dev` package
provides both. The Ruby gem also uses libpq, and may require the same
package on platforms without a pre-built gem. The following tabs show the
dependency declaration from each example project:

=== "Python"

    ```text
    # psycopg 3, with the pre-built binary package that bundles libpq.
    psycopg[binary]>=3.2,<4
    ```

=== "TypeScript"

    ```json
    {
      "name": "connect-and-query",
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
    
    #include <libpq-fe.h>
    ```

## Configuring the Connection

The examples read their connection settings from the same environment
variables that libpq and `psql` use, so a single set of variables
configures every example. The examples read only the five variables in the
table, and expect a TCP host name or IPv4 address in `PGHOST`. Like libpq,
each example treats an empty variable as unset, and uses the default
instead. The following table describes the environment variables that the
examples read:

| Variable     | Default     | Description                                    |
|--------------|-------------|------------------------------------------------|
| `PGHOST`     | `localhost` | The host name or IP address of the server.     |
| `PGPORT`     | `5432`      | The TCP port on which the server listens.      |
| `PGDATABASE` | `postgres`  | The name of the database to connect to.        |
| `PGUSER`     | `postgres`  | The user name to connect as.                   |
| `PGPASSWORD` | None        | The password; omitted if unset or empty.       |

!!! note

    Production applications should not store passwords in environment
    variables or source code. The
    [password file](https://www.postgresql.org/docs/current/libpq-pgpass.html)
    or a secrets manager provides a safer alternative.

The following tabs show how each program assembles the connection settings:

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
previous step. The C# program creates an Npgsql data source instead, which
lends out pooled connections when the main part of the program asks for
one. The driver reports a failure if the server is unreachable or rejects
the credentials; the Handling Errors and Closing the Connection section
describes how each program reports the failure. The following tabs show
how each program opens the connection:

=== "Python"

    ```python
    def connect() -> psycopg.Connection:
        """Opens a connection with the settings from the environment."""
        return psycopg.connect(**connection_settings())
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
    // creates one data source at start-up and shares it.
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

## Running the Query

Each program runs the query in a function that takes the type name, sends
the name to the server as a parameter, and then reads the single value
from the first column of the first row. Each driver sends parameters
separately from the SQL text, so the server never interprets a parameter
as SQL; this approach eliminates SQL injection attacks. The placeholder
syntax differs between drivers.

The following table shows the placeholder syntax that each driver uses:

| Language   | Placeholder syntax |
|------------|--------------------|
| Python     | `%s`               |
| TypeScript | `$1`, `$2`, ...    |
| Java       | `?`                |
| C#         | `$1`, `$2`, ...    |
| Go         | `$1`, `$2`, ...    |
| Rust       | `$1`, `$2`, ...    |
| Ruby       | `$1`, `$2`, ...    |
| C          | `$1`, `$2`, ...    |

The `count(*)` aggregate returns a `bigint`. The C and Ruby drivers return
every value as text, so those programs convert the value to an integer;
node-postgres returns a `bigint` as a string because the value may exceed
the range of a JavaScript number. The other drivers return a native 64-bit
integer. The following tabs show how each program runs the query and reads
the result:

=== "Python"

    ```python
    def count_types(conn: psycopg.Connection, name: str) -> int:
        """Returns the number of data types with the given name."""
        # Always pass values as parameters rather than formatting them into
        # the SQL string; psycopg sends them separately, which prevents SQL
        # injection.
        row = conn.execute(
            "SELECT count(*) FROM pg_catalog.pg_type WHERE typname = %s",
            (name,),
        ).fetchone()
        return row[0]
    ```

=== "TypeScript"

    ```typescript
    // Returns the number of data types with the given name.
    async function countTypes(client: pg.Client, name: string): Promise<bigint> {
      // Always pass values as parameters rather than building them into the
      // SQL string; node-postgres sends them separately, which prevents SQL
      // injection.
      const result = await client.query<{ count: string }>(
        "SELECT count(*) FROM pg_catalog.pg_type WHERE typname = $1",
        [name],
      );
    
      // count(*) returns a bigint, which node-postgres returns as a string
      // because it may not fit in a JavaScript number.
      return BigInt(result.rows[0].count);
    }
    ```

=== "Java"

    ```java
    /** Returns the number of data types with the given name. */
    static long countTypes(Connection conn, String name)
            throws SQLException {
        // Always pass values as parameters rather than concatenating them
        // into the SQL string; the driver sends them separately, which
        // prevents SQL injection.
        String sql =
            "SELECT count(*) FROM pg_catalog.pg_type WHERE typname = ?";
    
        // try-with-resources closes the statement and the result set when
        // each block exits, whether or not an error occurred.
        try (PreparedStatement stmt = conn.prepareStatement(sql)) {
            stmt.setString(1, name);
    
            try (ResultSet rs = stmt.executeQuery()) {
                rs.next();
                return rs.getLong(1);
            }
        }
    }
    ```

=== "C#"

    ```csharp
    // Returns the number of data types with the given name.
    static async Task<long> CountTypesAsync(NpgsqlConnection conn, string name)
    {
        // Always pass values as parameters rather than building them into the
        // SQL string; Npgsql sends them separately, which prevents SQL
        // injection. Positional parameters are written $1, $2, and so on.
        await using var cmd = new NpgsqlCommand(
            "SELECT count(*) FROM pg_catalog.pg_type WHERE typname = $1", conn)
        {
            Parameters = { new() { Value = name } },
        };
    
        // ExecuteScalarAsync returns the first column of the first row. A
        // bigint maps to long.
        return (long)(await cmd.ExecuteScalarAsync())!;
    }
    ```

=== "Go"

    ```go
    // countTypes returns the number of data types with the given name.
    func countTypes(ctx context.Context, conn *pgx.Conn, name string) (int64, error) {
    	// Always pass values as parameters rather than building them into the
    	// SQL string; pgx sends them separately, which prevents SQL injection.
    	var count int64
    	err := conn.QueryRow(ctx,
    		"SELECT count(*) FROM pg_catalog.pg_type WHERE typname = $1",
    		name,
    	).Scan(&count)
    	if err != nil {
    		return 0, fmt.Errorf("query failed: %w", err)
    	}
    	return count, nil
    }
    
    ```

=== "Rust"

    ```rust
    /// Returns the number of data types with the given name.
    fn count_types(client: &mut Client, name: &str) -> Result<i64, postgres::Error> {
        // Always pass values as parameters rather than building them into the
        // SQL string; the driver sends them separately, which prevents SQL
        // injection.
        let row = client.query_one(
            "SELECT count(*) FROM pg_catalog.pg_type WHERE typname = $1",
            &[&name],
        )?;
    
        // count(*) returns a bigint, which maps to i64.
        Ok(row.get(0))
    }
    ```

=== "Ruby"

    ```ruby
    # Returns the number of data types with the given name.
    def count_types(conn, name)
      # Always pass values as parameters rather than interpolating them into
      # the SQL string; the pg gem sends them separately, which prevents SQL
      # injection.
      result = conn.exec_params(
        "SELECT count(*) FROM pg_catalog.pg_type WHERE typname = $1",
        [name]
      )
    
      # Results arrive as strings, so convert the value to an Integer.
      result.getvalue(0, 0).to_i
    end
    ```

=== "C"

    ```c
    /*
     * Store the number of data types with the given name in *count, and
     * return true on success. On failure, PQerrorMessage() describes the
     * error.
     */
    static bool
    count_types(PGconn *conn, const char *name, long long *count)
    {
        /*
         * Always pass values as parameters rather than building them into
         * the SQL string; libpq sends them separately, so no quoting or
         * escaping is needed and SQL injection is impossible.
         */
        const char *params[] = {name};
        PGresult *res = PQexecParams(conn,
                                     "SELECT count(*) FROM pg_catalog.pg_type "
                                     "WHERE typname = $1",
                                     1,     /* number of parameters */
                                     NULL,  /* let the server infer types */
                                     params,
                                     NULL,  /* text parameters need no lengths */
                                     NULL,  /* all parameters are text */
                                     0);    /* ask for text results */
        bool ok = PQresultStatus(res) == PGRES_TUPLES_OK;
    
        /* Results arrive as text, so convert the value to a number. */
        if (ok)
            *count = strtoll(PQgetvalue(res, 0, 0), NULL, 10);
    
        /* PQclear() frees the result, and accepts NULL. */
        PQclear(res);
        return ok;
    }
    ```

## Handling Errors and Closing the Connection

The main part of each program calls the functions from the previous steps,
and prints the result. The program reports any connection or query failure
on `stderr`, and then exits with a non-zero status. The Python, C#, and
Ruby programs catch the base error class of the driver, and the Java
program catches the JDBC `SQLException` class; the TypeScript program
catches any rejected promise. The Go and Rust programs return each
error from a `run()` function to `main()`, and the C program checks the
result of each call.

The program also closes the connection when the work completes or fails, so
the server can release the resources that the connection holds. The Python
`with` block, the Java `try`-with-resources statement, and the C# `await
using` declaration close the connection automatically at the end of a
block. The TypeScript, Ruby, and Go programs close the connection in a
`finally` block, an `ensure` block, or a deferred call, and the C program
calls `PQfinish()` on both paths. The Rust program closes the connection
explicitly on success, and drops the client to close the connection after
an error. The following tabs show the main part of each program:

=== "Python"

    ```python
    def main() -> int:
        try:
            # The with block closes the connection when it exits, whether or
            # not an error occurred.
            with connect() as conn:
                count = count_types(conn, "int4")
                print(f"Number of types named 'int4': {count}")
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
        const count = await countTypes(client, "int4");
        console.log(`Number of types named 'int4': ${count}`);
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
            long count = countTypes(conn, "int4");
            System.out.println("Number of types named 'int4': " + count);
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
    
        var count = await CountTypesAsync(conn, "int4");
        Console.WriteLine($"Number of types named 'int4': {count}");
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
    
    	count, err := countTypes(ctx, conn, "int4")
    	if err != nil {
    		return err
    	}
    
    	fmt.Printf("Number of types named 'int4': %d\n", count)
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
    fn run() -> Result<(), postgres::Error> {
        let mut client = connect()?;
        let count = count_types(&mut client, "int4")?;
        println!("Number of types named 'int4': {count}");
    
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
      count = count_types(conn, "int4")
      puts "Number of types named 'int4': #{count}"
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
        long long count;
        PGconn *conn = connect_to_server();
    
        /* The || operator skips the query if the connection failed. */
        if (PQstatus(conn) != CONNECTION_OK ||
            !count_types(conn, "int4", &count))
        {
            fprintf(stderr, "Database error: %s", PQerrorMessage(conn));
        }
        else
        {
            printf("Number of types named 'int4': %lld\n", count);
            status = EXIT_SUCCESS;
        }
    
        /* Close the connection whether or not an error occurred. */
        PQfinish(conn);
        return status;
    }
    ```

## Running the Example

The complete project for each language is available in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/postgresql/connect_and_query).
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
    Connecting to PostgreSQL and running a scalar query, using psycopg 3.
    
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
        """Opens a connection with the settings from the environment."""
        return psycopg.connect(**connection_settings())
    
    
    def count_types(conn: psycopg.Connection, name: str) -> int:
        """Returns the number of data types with the given name."""
        # Always pass values as parameters rather than formatting them into
        # the SQL string; psycopg sends them separately, which prevents SQL
        # injection.
        row = conn.execute(
            "SELECT count(*) FROM pg_catalog.pg_type WHERE typname = %s",
            (name,),
        ).fetchone()
        return row[0]
    
    
    def main() -> int:
        try:
            # The with block closes the connection when it exits, whether or
            # not an error occurred.
            with connect() as conn:
                count = count_types(conn, "int4")
                print(f"Number of types named 'int4': {count}")
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
     * Connecting to PostgreSQL and running a scalar query, using node-postgres.
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
    
    // Returns the number of data types with the given name.
    async function countTypes(client: pg.Client, name: string): Promise<bigint> {
      // Always pass values as parameters rather than building them into the
      // SQL string; node-postgres sends them separately, which prevents SQL
      // injection.
      const result = await client.query<{ count: string }>(
        "SELECT count(*) FROM pg_catalog.pg_type WHERE typname = $1",
        [name],
      );
    
      // count(*) returns a bigint, which node-postgres returns as a string
      // because it may not fit in a JavaScript number.
      return BigInt(result.rows[0].count);
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
        const count = await countTypes(client, "int4");
        console.log(`Number of types named 'int4': ${count}`);
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
     * Connecting to PostgreSQL and running a scalar query, using JDBC and
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
    
        /** Returns the number of data types with the given name. */
        static long countTypes(Connection conn, String name)
                throws SQLException {
            // Always pass values as parameters rather than concatenating them
            // into the SQL string; the driver sends them separately, which
            // prevents SQL injection.
            String sql =
                "SELECT count(*) FROM pg_catalog.pg_type WHERE typname = ?";
    
            // try-with-resources closes the statement and the result set when
            // each block exits, whether or not an error occurred.
            try (PreparedStatement stmt = conn.prepareStatement(sql)) {
                stmt.setString(1, name);
    
                try (ResultSet rs = stmt.executeQuery()) {
                    rs.next();
                    return rs.getLong(1);
                }
            }
        }
    
        public static void main(String[] args) {
            // try-with-resources closes the connection when the block exits,
            // whether or not an error occurred.
            try (Connection conn = connect()) {
                long count = countTypes(conn, "int4");
                System.out.println("Number of types named 'int4': " + count);
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
     * Connecting to PostgreSQL and running a scalar query, using Npgsql.
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
    // creates one data source at start-up and shares it.
    static NpgsqlDataSource CreateDataSource() =>
        NpgsqlDataSource.Create(ConnectionString());
    
    // Returns the number of data types with the given name.
    static async Task<long> CountTypesAsync(NpgsqlConnection conn, string name)
    {
        // Always pass values as parameters rather than building them into the
        // SQL string; Npgsql sends them separately, which prevents SQL
        // injection. Positional parameters are written $1, $2, and so on.
        await using var cmd = new NpgsqlCommand(
            "SELECT count(*) FROM pg_catalog.pg_type WHERE typname = $1", conn)
        {
            Parameters = { new() { Value = name } },
        };
    
        // ExecuteScalarAsync returns the first column of the first row. A
        // bigint maps to long.
        return (long)(await cmd.ExecuteScalarAsync())!;
    }
    
    try
    {
        // await using disposes of the data source, and returns the connection
        // to the pool, when the block exits, whether or not an error occurred.
        await using var dataSource = CreateDataSource();
        await using var conn = await dataSource.OpenConnectionAsync();
    
        var count = await CountTypesAsync(conn, "int4");
        Console.WriteLine($"Number of types named 'int4': {count}");
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
    // Connecting to PostgreSQL and running a scalar query, using pgx.
    //
    // Copyright (c) 2026, pgEdge, Inc.
    // This code is released under the PostgreSQL License.
    
    package main
    
    import (
    	"context"
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
    
    
    // countTypes returns the number of data types with the given name.
    func countTypes(ctx context.Context, conn *pgx.Conn, name string) (int64, error) {
    	// Always pass values as parameters rather than building them into the
    	// SQL string; pgx sends them separately, which prevents SQL injection.
    	var count int64
    	err := conn.QueryRow(ctx,
    		"SELECT count(*) FROM pg_catalog.pg_type WHERE typname = $1",
    		name,
    	).Scan(&count)
    	if err != nil {
    		return 0, fmt.Errorf("query failed: %w", err)
    	}
    	return count, nil
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
    
    	count, err := countTypes(ctx, conn, "int4")
    	if err != nil {
    		return err
    	}
    
    	fmt.Printf("Number of types named 'int4': %d\n", count)
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
    // Connecting to PostgreSQL and running a scalar query, using the postgres
    // crate.
    //
    // Copyright (c) 2026, pgEdge, Inc.
    // This code is released under the PostgreSQL License.
    
    use std::env;
    use std::error::Error;
    use std::process::ExitCode;
    
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
    
    /// Returns the number of data types with the given name.
    fn count_types(client: &mut Client, name: &str) -> Result<i64, postgres::Error> {
        // Always pass values as parameters rather than building them into the
        // SQL string; the driver sends them separately, which prevents SQL
        // injection.
        let row = client.query_one(
            "SELECT count(*) FROM pg_catalog.pg_type WHERE typname = $1",
            &[&name],
        )?;
    
        // count(*) returns a bigint, which maps to i64.
        Ok(row.get(0))
    }
    
    /// Connects, runs the query, and prints the result. The ? operator
    /// returns any error to the caller.
    fn run() -> Result<(), postgres::Error> {
        let mut client = connect()?;
        let count = count_types(&mut client, "int4")?;
        println!("Number of types named 'int4': {count}");
    
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
    # Connecting to PostgreSQL and running a scalar query, using the pg gem.
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
    
    # Returns the number of data types with the given name.
    def count_types(conn, name)
      # Always pass values as parameters rather than interpolating them into
      # the SQL string; the pg gem sends them separately, which prevents SQL
      # injection.
      result = conn.exec_params(
        "SELECT count(*) FROM pg_catalog.pg_type WHERE typname = $1",
        [name]
      )
    
      # Results arrive as strings, so convert the value to an Integer.
      result.getvalue(0, 0).to_i
    end
    
    begin
      conn = connect
      count = count_types(conn, "int4")
      puts "Number of types named 'int4': #{count}"
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
     * Connecting to PostgreSQL and running a scalar query, using libpq.
     *
     * Copyright (c) 2026, pgEdge, Inc.
     * This code is released under the PostgreSQL License.
     */
    
    #include <stdbool.h>
    #include <stdio.h>
    #include <stdlib.h>
    
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
     * Store the number of data types with the given name in *count, and
     * return true on success. On failure, PQerrorMessage() describes the
     * error.
     */
    static bool
    count_types(PGconn *conn, const char *name, long long *count)
    {
        /*
         * Always pass values as parameters rather than building them into
         * the SQL string; libpq sends them separately, so no quoting or
         * escaping is needed and SQL injection is impossible.
         */
        const char *params[] = {name};
        PGresult *res = PQexecParams(conn,
                                     "SELECT count(*) FROM pg_catalog.pg_type "
                                     "WHERE typname = $1",
                                     1,     /* number of parameters */
                                     NULL,  /* let the server infer types */
                                     params,
                                     NULL,  /* text parameters need no lengths */
                                     NULL,  /* all parameters are text */
                                     0);    /* ask for text results */
        bool ok = PQresultStatus(res) == PGRES_TUPLES_OK;
    
        /* Results arrive as text, so convert the value to a number. */
        if (ok)
            *count = strtoll(PQgetvalue(res, 0, 0), NULL, 10);
    
        /* PQclear() frees the result, and accepts NULL. */
        PQclear(res);
        return ok;
    }
    
    int
    main(void)
    {
        int status = EXIT_FAILURE;
        long long count;
        PGconn *conn = connect_to_server();
    
        /* The || operator skips the query if the connection failed. */
        if (PQstatus(conn) != CONNECTION_OK ||
            !count_types(conn, "int4", &count))
        {
            fprintf(stderr, "Database error: %s", PQerrorMessage(conn));
        }
        else
        {
            printf("Number of types named 'int4': %lld\n", count);
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

- The [Contributing a Recipe](../contributing.md) page explains how to add
  a recipe or a language to the cookbook.
- The PostgreSQL documentation for
  [environment variables](https://www.postgresql.org/docs/current/libpq-envars.html)
  describes every variable that libpq recognises.
- The PostgreSQL documentation for
  [connection strings](https://www.postgresql.org/docs/current/libpq-connect.html#LIBPQ-CONNSTRING)
  describes the full set of connection parameters.
