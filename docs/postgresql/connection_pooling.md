# Using a Connection Pool

This recipe demonstrates how an application shares a small, fixed number of
database connections between many queries by using a connection pool.
Opening a connection to PostgreSQL is slow, because it involves a network
handshake, authentication, and the start of a server process, and each
connection also holds memory on the server. A pool opens the connections
once, lends one to each caller that needs it, and takes it back afterwards;
callers that arrive when every connection is busy wait for a free one.
Each step shows the code in every supported language; selecting a language
tab switches every tab on the site to that language.

The example program creates a pool of at most two connections, and then
starts five queries at once. Each query is `SELECT $1::int`, which returns
one of the numbers 1 to 5 that the program sends as a parameter. The pool
runs at most two of the queries at any moment, and the program adds up the
five results and closes the pool. The output is the same on every run:

```text
Ran 5 queries through a pool of at most 2 connections
Sum of results: 15
```

!!! note

    libpq, the C client library, has no connection pool, so this recipe has
    no C program. The C tab in each step explains the alternative: a
    separate pooling server such as [PgBouncer](https://www.pgbouncer.org/)
    pools connections for any client, whatever language the client uses.

## Preparing the Ingredients

Each example uses the pool that is most widely adopted for its language,
and the pool comes from a separate package in several languages. The
following table lists the driver and the pool that each example uses:

| Language   | Driver                                          | Pool |
|------------|-------------------------------------------------|------|
| Python     | [psycopg 3](https://www.psycopg.org/psycopg3/)  | [psycopg_pool](https://www.psycopg.org/psycopg3/docs/advanced/pool.html) |
| TypeScript | [node-postgres](https://node-postgres.com/)     | [pg.Pool](https://node-postgres.com/apis/pool), part of node-postgres |
| Java       | [pgJDBC](https://jdbc.postgresql.org/)          | [HikariCP](https://github.com/brettwooldridge/HikariCP) |
| C#         | [Npgsql](https://www.npgsql.org/)               | [NpgsqlDataSource](https://www.npgsql.org/doc/basic-usage.html), part of Npgsql |
| Go         | [pgx](https://github.com/jackc/pgx)             | [pgxpool](https://pkg.go.dev/github.com/jackc/pgx/v5/pgxpool), part of pgx |
| Rust       | [rust-postgres](https://github.com/rust-postgres/rust-postgres) | [r2d2_postgres](https://github.com/rust-postgres/r2d2-postgres) |
| Ruby       | [ruby-pg](https://github.com/ged/ruby-pg)      | [connection_pool](https://github.com/mperham/connection_pool) |
| C          | [libpq](https://www.postgresql.org/docs/current/libpq.html) | None; use [PgBouncer](https://www.pgbouncer.org/) |

The Rust example uses r2d2 because it works with the synchronous
`postgres` crate that the first recipe uses; an asynchronous program would
use a pool such as `deadpool-postgres` instead. The following tabs show the
dependency declaration from each example project:

=== "Python"

    ```text
    # psycopg 3, with the pre-built binary package that bundles libpq, and
    # its connection pool package.
    psycopg[binary]>=3.2,<4
    psycopg-pool>=3.2,<4
    ```

=== "TypeScript"

    ```json
    {
      "name": "connection-pooling",
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
      <!-- HikariCP, a JDBC connection pool. -->
      <dependency>
        <groupId>com.zaxxer</groupId>
        <artifactId>HikariCP</artifactId>
        <version>6.3.0</version>
      </dependency>
      <!--
        HikariCP logs through SLF4J 1.7, and prints a warning on standard
        output if no logging implementation is present. This one discards
        the log messages; use a real implementation in an application.
      -->
      <dependency>
        <groupId>org.slf4j</groupId>
        <artifactId>slf4j-nop</artifactId>
        <version>1.7.36</version>
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
    // pgx is a pure Go driver and toolkit for PostgreSQL; its pgxpool
    // package provides the connection pool.
    require github.com/jackc/pgx/v5 v5.12.0
    
    require (
    	github.com/jackc/pgpassfile v1.0.0 // indirect
    	github.com/jackc/pgservicefile v0.0.0-20240606120523-5a60cdf6a761 // indirect
    	github.com/jackc/puddle/v2 v2.2.3 // indirect
    	golang.org/x/sync v0.22.0 // indirect
    	golang.org/x/text v0.41.0 // indirect
    )
    
    ```

=== "Rust"

    ```toml
    [dependencies]
    # The r2d2 connection pool, with its adapter for the synchronous postgres
    # crate. The adapter re-exports both the pool and the client crate.
    r2d2_postgres = "0.18"
    ```

=== "Ruby"

    ```ruby
    source "https://rubygems.org"
    
    # The pg gem wraps libpq, so libpq and its headers must be installed.
    gem "pg", "~> 1.6"
    
    # The connection_pool gem is a general-purpose, thread-safe pool.
    gem "connection_pool", "~> 3.0"
    ```

=== "C"

    There is no C example, because libpq has no built-in connection pool, so
    there are no dependencies to declare. A C application that needs pooling
    normally connects through [PgBouncer](https://www.pgbouncer.org/), a
    separate pooling server that runs between the application and PostgreSQL.

## Importing the Libraries

Each program begins by importing the driver and its pool, along with any
standard library modules that the program uses to run queries at the same
time. The following tabs show the imports for each language:

=== "Python"

    ```python
    import os
    import sys
    from concurrent.futures import ThreadPoolExecutor
    
    import psycopg
    from psycopg_pool import ConnectionPool
    ```

=== "TypeScript"

    ```typescript
    import pg from "pg";
    ```

=== "Java"

    ```java
    import com.zaxxer.hikari.HikariConfig;
    import com.zaxxer.hikari.HikariDataSource;
    import com.zaxxer.hikari.pool.HikariPool.PoolInitializationException;
    
    import java.sql.Connection;
    import java.sql.PreparedStatement;
    import java.sql.ResultSet;
    import java.sql.SQLException;
    import java.util.ArrayList;
    import java.util.List;
    import java.util.concurrent.ExecutionException;
    import java.util.concurrent.ExecutorService;
    import java.util.concurrent.Executors;
    import java.util.concurrent.Future;
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
    	"sync"
    
    	"github.com/jackc/pgx/v5/pgxpool"
    )
    
    ```

=== "Rust"

    ```rust
    use std::env;
    use std::error::Error;
    use std::process::ExitCode;
    use std::thread;
    use std::time::Duration;
    
    use r2d2_postgres::postgres::{Config, NoTls};
    use r2d2_postgres::{r2d2, PostgresConnectionManager};
    ```

=== "Ruby"

    ```ruby
    require "connection_pool"
    require "pg"
    ```

=== "C"

    A C application needs no pool library, because libpq has no connection pool
    and this recipe has no C program. [PgBouncer](https://www.pgbouncer.org/)
    provides pooling outside the application, and the application connects to
    it with the ordinary libpq calls.

## Configuring the Connection and the Pool

The examples read their connection settings from the same environment
variables as the first recipe: `PGHOST`, `PGPORT`, `PGDATABASE`, `PGUSER`,
and `PGPASSWORD`. Each example treats an empty variable as unset, and uses
the default instead. Each program also fixes the size of the pool at two
connections in one place, so that the size appears in the pool settings and
in the output. The following tabs show how each program assembles its
settings:

=== "Python"

    ```python
    # The most connections that the pool opens at any one time.
    POOL_SIZE = 2
    
    
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
    // The most connections that the pool opens at any one time.
    const POOL_SIZE = 2;
    
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
    /** The most connections that the pool opens at any one time. */
    static final int POOL_SIZE = 2;
    
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
    ```

=== "C#"

    ```csharp
    // The most connections that the pool opens at any one time.
    const int PoolSize = 2;
    
    // Returns the value of an environment variable, or null if the variable
    // is unset or empty; libpq also treats an empty variable as unset.
    static string? EnvValue(string name) =>
        Environment.GetEnvironmentVariable(name) is { Length: > 0 } value
            ? value
            : null;
    
    // Returns the value of an environment variable, or a fallback if unset.
    static string EnvOr(string name, string fallback) =>
        EnvValue(name) ?? fallback;
    ```

=== "Go"

    ```go
    // poolSize is the most connections that the pool opens at any one time.
    const poolSize = 2
    
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
    /// The most connections that the pool opens at any one time.
    const POOL_SIZE: u32 = 2;
    
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
    # The most connections that the pool opens at any one time.
    POOL_SIZE = 2
    
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

    The settings in a C application that uses PgBouncer are the usual libpq
    settings, with `PGHOST` and `PGPORT` pointing at PgBouncer instead of the
    PostgreSQL server. This recipe has no C program.

## Creating the Pool

Each program creates one pool when it starts, and shares the pool between
every query; an application would normally do the same, and create the pool
once per process rather than once per request. The program sets the maximum
size of the pool to two connections, and sets a five-second timeout, so that
a caller that waits too long for a connection receives an error instead of
waiting forever.

Pools differ in when they connect. The Python, Java, and Rust pools open a
connection while they are created, so the program fails there if the server
is unreachable. The Go program calls `Ping()` to force the first connection,
and the TypeScript, C#, and Ruby pools open their connections when the first
query asks for one. In every language, the failure reaches the error
handling in the main part of the program. The following tabs show how each
program creates the pool:

=== "Python"

    ```python
    def create_pool() -> ConnectionPool:
        """Creates a pool that holds at most POOL_SIZE connections."""
        # The pool opens its connections in background threads. A request for
        # a connection waits for up to timeout seconds when both connections
        # are busy, and then raises an error rather than waiting forever.
        pool = ConnectionPool(
            kwargs=connection_settings(),
            min_size=1,
            max_size=POOL_SIZE,
            timeout=5,
            open=True,
        )
    
        # wait() blocks until the pool has opened its first connection, and
        # raises an error if that takes longer than the timeout, for example
        # because the server is unreachable. Close the pool before re-raising,
        # so that its background threads stop.
        try:
            pool.wait(timeout=5)
        except psycopg.Error:
            pool.close()
            raise
        return pool
    ```

=== "TypeScript"

    ```typescript
    // Creates a pool that holds at most POOL_SIZE connections.
    function createPool(): pg.Pool {
      const pool = new pg.Pool({
        ...config,
        max: POOL_SIZE,
        // A request fails after this many milliseconds if the pool can
        // neither lend an idle connection nor open a new one.
        connectionTimeoutMillis: 5000,
      });
    
      // An idle connection can fail while it waits in the pool, for example
      // if the server restarts. The pool emits an error event for it, and
      // Node terminates the process if nothing handles the event.
      pool.on("error", (err) => {
        console.error(`Idle connection error: ${err.message}`);
      });
      return pool;
    }
    ```

=== "Java"

    ```java
    /** Creates a pool that holds at most POOL_SIZE connections. */
    static HikariDataSource createPool() {
        HikariConfig config = new HikariConfig();
        config.setJdbcUrl(connectionUrl());
        config.setUsername(envOr("PGUSER", "postgres"));
    
        // The password is omitted if PGPASSWORD is unset or empty.
        String password = envOr("PGPASSWORD", null);
        if (password != null) {
            config.setPassword(password);
        }
    
        config.setMaximumPoolSize(POOL_SIZE);
    
        // A request for a connection fails after this many milliseconds
        // if the pool can neither lend an idle connection nor open a new
        // one.
        config.setConnectionTimeout(5000);
    
        // The constructor opens the first connection, and throws a
        // PoolInitializationException if the server is unreachable.
        return new HikariDataSource(config);
    }
    ```

=== "C#"

    ```csharp
    // Creates a data source, which owns a pool that holds at most PoolSize
    // connections. Npgsql pools connections by default; the connection string
    // builder sets the limits and takes care of quoting any special
    // characters in the settings.
    static NpgsqlDataSource CreatePool() =>
        NpgsqlDataSource.Create(new NpgsqlConnectionStringBuilder
        {
            Host = EnvOr("PGHOST", "localhost"),
            Port = int.Parse(EnvOr("PGPORT", "5432")),
            Database = EnvOr("PGDATABASE", "postgres"),
            Username = EnvOr("PGUSER", "postgres"),
            Password = EnvValue("PGPASSWORD"),
            MaxPoolSize = PoolSize,
    
            // A request for a connection fails after this many seconds if
            // the pool can neither lend an idle connection nor open a new one.
            Timeout = 5,
        }.ConnectionString);
    ```

=== "Go"

    ```go
    // createPool creates a pool that holds at most poolSize connections.
    func createPool(ctx context.Context) (*pgxpool.Pool, error) {
    	config, err := pgxpool.ParseConfig(connString())
    	if err != nil {
    		return nil, fmt.Errorf("invalid settings: %w", err)
    	}
    	config.MaxConns = poolSize
    
    	pool, err := pgxpool.NewWithConfig(ctx, config)
    	if err != nil {
    		return nil, fmt.Errorf("pool creation failed: %w", err)
    	}
    
    	// The pool opens connections on demand, so creating it never fails
    	// because of an unreachable server. Ping borrows a connection, which
    	// opens the first one and reports any problem straight away.
    	if err := pool.Ping(ctx); err != nil {
    		pool.Close()
    		return nil, fmt.Errorf("connection failed: %w", err)
    	}
    	return pool, nil
    }
    
    ```

=== "Rust"

    ```rust
    /// A pool of connections made by the postgres crate.
    type Pool = r2d2::Pool<PostgresConnectionManager<NoTls>>;
    
    /// Creates a pool that holds at most POOL_SIZE connections. NoTls
    /// disables TLS, which keeps this example free of certificate set-up;
    /// connections over an untrusted network should use TLS.
    fn create_pool() -> Result<Pool, r2d2::Error> {
        let manager = PostgresConnectionManager::new(config(), NoTls);
        Pool::builder()
            .max_size(POOL_SIZE)
            // A request for a connection fails after this long if the pool
            // can neither lend an idle connection nor open a new one.
            .connection_timeout(Duration::from_secs(5))
            // build() opens the connections up front, and returns an error if
            // it cannot, for example because the server is unreachable.
            .build(manager)
    }
    ```

=== "Ruby"

    ```ruby
    # Creates a pool that holds at most POOL_SIZE connections.
    def create_pool
      # The block opens a new connection, and the pool calls it on demand, at
      # most POOL_SIZE times. A request for a connection waits for up to
      # timeout seconds when both connections are busy, and then raises
      # ConnectionPool::TimeoutError.
      ConnectionPool.new(size: POOL_SIZE, timeout: 5) do
        PG.connect(connection_params)
      end
    end
    ```

=== "C"

    libpq has no connection pool, so there is no pool to create in C. Install
    [PgBouncer](https://www.pgbouncer.org/), set its `default_pool_size` to the
    number of server connections that it may open, and let the C application
    connect to PgBouncer.

## Running a Query Through the Pool

Each program runs the query in a function that takes the pool and a number,
borrows a connection, sends the number to the server as a parameter, and
reads the single value that comes back. The function returns the connection
to the pool when it finishes, and does not disconnect it from the server, so
the next query can reuse it. The `::int` cast gives the parameter a type,
because the server cannot infer one from `SELECT $1` alone. The TypeScript
program calls `pool.query()`, and the Go program calls `pool.QueryRow()`;
both borrow and return a connection automatically. The following tabs show
how each program runs the query:

=== "Python"

    ```python
    def run_query(pool: ConnectionPool, number: int) -> int:
        """Borrows a connection from the pool, and returns the number back."""
        # The with block borrows a connection and returns it to the pool when
        # it exits, whether or not an error occurred; it does not close it.
        with pool.connection() as conn:
            # Pass values as parameters rather than formatting them into the
            # SQL string. The cast gives the parameter a type, which the
            # server cannot infer from SELECT $1 alone.
            row = conn.execute("SELECT %s::int", (number,)).fetchone()
            return row[0]
    ```

=== "TypeScript"

    ```typescript
    // Borrows a connection from the pool, and returns the number back.
    async function runQuery(pool: pg.Pool, n: number): Promise<number> {
      // pool.query borrows a connection, runs the statement, and returns the
      // connection to the pool, whether or not an error occurred. Pass values
      // as parameters rather than building them into the SQL string. The cast
      // gives the parameter a type, which the server cannot infer from
      // SELECT $1 alone.
      const result = await pool.query<{ n: number }>("SELECT $1::int AS n", [n]);
      return result.rows[0].n;
    }
    ```

=== "Java"

    ```java
    /** Borrows a connection from the pool, and returns the number back. */
    static int runQuery(HikariDataSource pool, int number)
            throws SQLException {
        // Pass values as parameters rather than concatenating them into
        // the SQL string. The cast gives the parameter a type, which the
        // server cannot infer from SELECT ? alone.
        String sql = "SELECT ?::int";
    
        // try-with-resources returns the connection to the pool when the
        // block exits, whether or not an error occurred; closing a pooled
        // connection does not disconnect it from the server.
        try (Connection conn = pool.getConnection();
             PreparedStatement stmt = conn.prepareStatement(sql)) {
            stmt.setInt(1, number);
    
            try (ResultSet rs = stmt.executeQuery()) {
                rs.next();
                return rs.getInt(1);
            }
        }
    }
    ```

=== "C#"

    ```csharp
    // Borrows a connection from the pool, and returns the number back.
    static async Task<int> RunQueryAsync(NpgsqlDataSource pool, int number)
    {
        // await using returns the connection to the pool when the method
        // exits, whether or not an error occurred; disposing of a pooled
        // connection does not disconnect it from the server.
        await using var conn = await pool.OpenConnectionAsync();
    
        // Pass values as parameters rather than building them into the SQL
        // string. Positional parameters are written $1, $2, and so on. The
        // cast gives the parameter a type, which the server cannot infer from
        // SELECT $1 alone.
        await using var cmd = new NpgsqlCommand("SELECT $1::int", conn)
        {
            Parameters = { new() { Value = number } },
        };
        return (int)(await cmd.ExecuteScalarAsync())!;
    }
    ```

=== "Go"

    ```go
    // runQuery borrows a connection from the pool, and returns the number
    // back.
    func runQuery(ctx context.Context, pool *pgxpool.Pool, number int32) (int32, error) {
    	// pool.QueryRow borrows a connection, runs the statement, and returns
    	// the connection to the pool once Scan has read the row. Pass values
    	// as parameters rather than building them into the SQL string. The
    	// cast gives the parameter a type, which the server cannot infer from
    	// SELECT $1 alone.
    	var result int32
    	err := pool.QueryRow(ctx, "SELECT $1::int", number).Scan(&result)
    	if err != nil {
    		return 0, fmt.Errorf("query failed: %w", err)
    	}
    	return result, nil
    }
    
    ```

=== "Rust"

    ```rust
    /// Borrows a connection from the pool, and returns the number back.
    fn run_query(pool: &Pool, number: i32) -> Result<i32, Box<dyn Error + Send + Sync>> {
        // get() lends a connection, which returns to the pool when it goes out
        // of scope, whether or not an error occurred; dropping a pooled
        // connection does not disconnect it from the server.
        let mut client = pool.get()?;
    
        // Pass values as parameters rather than building them into the SQL
        // string. The cast gives the parameter a type, which the server cannot
        // infer from SELECT $1 alone.
        let row = client.query_one("SELECT $1::int", &[&number])?;
        Ok(row.get(0))
    }
    ```

=== "Ruby"

    ```ruby
    # Borrows a connection from the pool, and returns the number back.
    def run_query(pool, number)
      # The with block borrows a connection and returns it to the pool when it
      # exits, whether or not an error occurred; it does not close it. Pass
      # values as parameters rather than interpolating them into the SQL
      # string. The cast gives the parameter a type, which the server cannot
      # infer from SELECT $1 alone.
      pool.with do |conn|
        conn.exec_params("SELECT $1::int", [number]).getvalue(0, 0).to_i
      end
    end
    ```

=== "C"

    In C, an application opens a connection with `PQconnectdbParams()` as in
    the first recipe, and runs queries on it with `PQexecParams()`. When the
    connection goes to PgBouncer, which holds the pooled server connections,
    the application needs no pool-specific code.

## Handling Errors and Closing the Pool

The main part of each program starts the five queries at the same time,
using threads in Python, Java, Rust, and Ruby, goroutines in Go, and
promises or tasks in TypeScript and C#. Only two queries run at any
moment, and the others wait for a connection. The program then adds up the
results and prints them.

The program reports any connection or query failure on `stderr`, and then
exits with a non-zero status. Closing the pool closes every connection that
it opened, and the program does so whether or not an error occurred: the
Python `with` block, the Java `try`-with-resources statement, and the C#
`await using` declaration close the pool automatically at the end of a
block. The TypeScript and Ruby programs close the pool in a `finally` block
and an `ensure` block, the Go program in a deferred call, and the Rust
program by dropping the pool. The following tabs show the main part of each
program:

=== "Python"

    ```python
    def main() -> int:
        try:
            # The with block closes the pool, and every connection in it,
            # when it exits.
            with create_pool() as pool:
                # Five threads ask for a connection at once, but the pool has
                # only two, so the other threads wait their turn.
                with ThreadPoolExecutor(max_workers=5) as executor:
                    results = list(
                        executor.map(lambda n: run_query(pool, n), range(1, 6))
                    )
            print(f"Ran {len(results)} queries through a pool of at most "
                  f"{POOL_SIZE} connections")
            print(f"Sum of results: {sum(results)}")
        # psycopg.Error is the base class for every error the driver raises,
        # including connection failures and errors reported by the server. The
        # pool raises PoolTimeout, a subclass, when it cannot supply a
        # connection in time.
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
      const pool = createPool();
      try {
        // All five queries start at once, but the pool has only two
        // connections, so the others wait their turn.
        const results = await Promise.all(
          [1, 2, 3, 4, 5].map((n) => runQuery(pool, n)),
        );
        const sum = results.reduce((total, n) => total + n, 0);
    
        console.log(
          `Ran ${results.length} queries through a pool of at most ` +
            `${POOL_SIZE} connections`,
        );
        console.log(`Sum of results: ${sum}`);
        return 0;
      } catch (err) {
        // Connection failures and errors reported by the server both arrive
        // here as rejected promises.
        console.error(`Database error: ${describe(err)}`);
        return 1;
      } finally {
        // The finally block runs whether or not an error occurred; end()
        // closes every connection in the pool.
        await pool.end();
      }
    }
    
    process.exitCode = await main();
    ```

=== "Java"

    ```java
    public static void main(String[] args) {
        // try-with-resources closes the pool, and every connection in it,
        // when the block exits, whether or not an error occurred.
        try (HikariDataSource pool = createPool()) {
            // Five threads ask for a connection at once, but the pool has
            // only two, so the other threads wait their turn.
            ExecutorService executor = Executors.newFixedThreadPool(5);
            List<Future<Integer>> futures = new ArrayList<>();
            try {
                for (int n = 1; n <= 5; n++) {
                    int number = n;
                    futures.add(
                        executor.submit(() -> runQuery(pool, number)));
                }
    
                int sum = 0;
                for (Future<Integer> future : futures) {
                    sum += future.get();
                }
                System.out.println("Ran " + futures.size()
                        + " queries through a pool of at most "
                        + POOL_SIZE + " connections");
                System.out.println("Sum of results: " + sum);
            } finally {
                executor.shutdown();
            }
        // A query that fails inside a thread arrives wrapped in an
        // ExecutionException. The pool throws PoolInitializationException
        // if it cannot open its first connection.
        } catch (ExecutionException e) {
            System.err.println("Database error: " + e.getCause().getMessage());
            System.exit(1);
        } catch (PoolInitializationException | InterruptedException e) {
            System.err.println("Database error: " + e.getMessage());
            System.exit(1);
        }
    }
    ```

=== "C#"

    ```csharp
    try
    {
        // await using closes the pool, and every connection in it, when the
        // block exits, whether or not an error occurred.
        await using var pool = CreatePool();
    
        // Five tasks ask for a connection at once, but the pool has only two,
        // so the other tasks wait their turn.
        var results = await Task.WhenAll(
            Enumerable.Range(1, 5).Select(n => RunQueryAsync(pool, n)));
    
        Console.WriteLine($"Ran {results.Length} queries through a pool of " +
                          $"at most {PoolSize} connections");
        Console.WriteLine($"Sum of results: {results.Sum()}");
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
    // run creates the pool, runs five queries through it at once, and prints
    // the sum, returning any error to the caller.
    func run(ctx context.Context) error {
    	pool, err := createPool(ctx)
    	if err != nil {
    		return err
    	}
    	// The deferred call closes the pool, and every connection in it, when
    	// run() returns, whether or not an error occurred.
    	defer pool.Close()
    
    	// Five goroutines ask for a connection at once, but the pool has only
    	// two, so the others wait their turn. Each goroutine writes only to
    	// its own element of the slices, so no further locking is needed.
    	const queries = 5
    	results := make([]int32, queries)
    	errs := make([]error, queries)
    	var wg sync.WaitGroup
    	for i := range queries {
    		wg.Add(1)
    		go func() {
    			defer wg.Done()
    			results[i], errs[i] = runQuery(ctx, pool, int32(i+1))
    		}()
    	}
    	wg.Wait()
    
    	if err := errors.Join(errs...); err != nil {
    		return err
    	}
    
    	var sum int32
    	for _, result := range results {
    		sum += result
    	}
    	fmt.Printf("Ran %d queries through a pool of at most %d connections\n", queries, poolSize)
    	fmt.Printf("Sum of results: %d\n", sum)
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
    /// Creates the pool, runs five queries through it at once, and prints the
    /// sum. The ? operator returns any error to the caller.
    fn run() -> Result<(), Box<dyn Error + Send + Sync>> {
        let pool = create_pool()?;
    
        // Five threads ask for a connection at once, but the pool has only
        // two, so the other threads wait their turn. Cloning a pool is cheap,
        // because every clone shares the same connections.
        let handles: Vec<_> = (1..=5)
            .map(|number| {
                let pool = pool.clone();
                thread::spawn(move || run_query(&pool, number))
            })
            .collect();
    
        let mut results = Vec::new();
        for handle in handles {
            results.push(handle.join().map_err(|_| "a query thread panicked")??);
        }
    
        println!(
            "Ran {} queries through a pool of at most {POOL_SIZE} connections",
            results.len()
        );
        println!("Sum of results: {}", results.iter().sum::<i32>());
    
        // Dropping the pool closes every connection in it.
        Ok(())
    }
    
    /// Reports any error returned by run() and exits with a failure status.
    /// The top-level error is often generic, so the chain of underlying
    /// causes is printed too.
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
    # Ruby prints a stack trace when a thread fails. Thread#value raises the
    # same error again in the main thread, where the rescue clause reports it,
    # so switch off the duplicate trace.
    Thread.report_on_exception = false
    
    begin
      pool = create_pool
    
      # Five threads ask for a connection at once, but the pool has only two,
      # so the other threads wait their turn. Thread#value waits for a thread
      # to finish and raises any error that the thread raised.
      threads = (1..5).map { |n| Thread.new { run_query(pool, n) } }
      results = threads.map(&:value)
    
      puts "Ran #{results.size} queries through a pool of at most " \
           "#{POOL_SIZE} connections"
      puts "Sum of results: #{results.sum}"
    # PG::Error is the base class for every error the gem raises, including
    # connection failures and errors reported by the server.
    rescue PG::Error => e
      warn "Database error: #{e.message}"
      exit 1
    # The pool raises its own error, which is not a PG::Error, when no
    # connection becomes free within the timeout.
    rescue ConnectionPool::TimeoutError => e
      warn "Database error: #{e.message}"
      exit 1
    # The ensure block runs whether or not an error occurred. pool is nil if
    # it could not be created, and shutdown closes every connection that the
    # pool opened.
    ensure
      pool&.shutdown { |conn| conn.close }
    end
    ```

=== "C"

    A C application closes each connection with `PQfinish()`, as in the first
    recipe; when the connection goes to PgBouncer, closing it lets PgBouncer
    reuse the server connection for another client. This recipe has no C
    program.

## Running the Example

The complete project for each language is available in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/postgresql/connection_pooling).
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

    There is no C program to run. To pool connections for a C application,
    install [PgBouncer](https://www.pgbouncer.org/) and point the libpq
    settings at it.

## Viewing the Complete Program

The following tabs show the complete program for each language:

=== "Python"

    ```python
    """
    Ellie's Postgres Cookbook
    Using a connection pool, with psycopg 3 and psycopg_pool.
    
    Copyright (c) 2026, pgEdge, Inc.
    This code is released under the PostgreSQL License.
    """
    
    import os
    import sys
    from concurrent.futures import ThreadPoolExecutor
    
    import psycopg
    from psycopg_pool import ConnectionPool
    
    
    # The most connections that the pool opens at any one time.
    POOL_SIZE = 2
    
    
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
    
    
    def create_pool() -> ConnectionPool:
        """Creates a pool that holds at most POOL_SIZE connections."""
        # The pool opens its connections in background threads. A request for
        # a connection waits for up to timeout seconds when both connections
        # are busy, and then raises an error rather than waiting forever.
        pool = ConnectionPool(
            kwargs=connection_settings(),
            min_size=1,
            max_size=POOL_SIZE,
            timeout=5,
            open=True,
        )
    
        # wait() blocks until the pool has opened its first connection, and
        # raises an error if that takes longer than the timeout, for example
        # because the server is unreachable. Close the pool before re-raising,
        # so that its background threads stop.
        try:
            pool.wait(timeout=5)
        except psycopg.Error:
            pool.close()
            raise
        return pool
    
    
    def run_query(pool: ConnectionPool, number: int) -> int:
        """Borrows a connection from the pool, and returns the number back."""
        # The with block borrows a connection and returns it to the pool when
        # it exits, whether or not an error occurred; it does not close it.
        with pool.connection() as conn:
            # Pass values as parameters rather than formatting them into the
            # SQL string. The cast gives the parameter a type, which the
            # server cannot infer from SELECT $1 alone.
            row = conn.execute("SELECT %s::int", (number,)).fetchone()
            return row[0]
    
    
    def main() -> int:
        try:
            # The with block closes the pool, and every connection in it,
            # when it exits.
            with create_pool() as pool:
                # Five threads ask for a connection at once, but the pool has
                # only two, so the other threads wait their turn.
                with ThreadPoolExecutor(max_workers=5) as executor:
                    results = list(
                        executor.map(lambda n: run_query(pool, n), range(1, 6))
                    )
            print(f"Ran {len(results)} queries through a pool of at most "
                  f"{POOL_SIZE} connections")
            print(f"Sum of results: {sum(results)}")
        # psycopg.Error is the base class for every error the driver raises,
        # including connection failures and errors reported by the server. The
        # pool raises PoolTimeout, a subclass, when it cannot supply a
        # connection in time.
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
     * Using a connection pool, with node-postgres.
     *
     * Copyright (c) 2026, pgEdge, Inc.
     * This code is released under the PostgreSQL License.
     */
    
    import pg from "pg";
    
    // The most connections that the pool opens at any one time.
    const POOL_SIZE = 2;
    
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
    
    // Creates a pool that holds at most POOL_SIZE connections.
    function createPool(): pg.Pool {
      const pool = new pg.Pool({
        ...config,
        max: POOL_SIZE,
        // A request fails after this many milliseconds if the pool can
        // neither lend an idle connection nor open a new one.
        connectionTimeoutMillis: 5000,
      });
    
      // An idle connection can fail while it waits in the pool, for example
      // if the server restarts. The pool emits an error event for it, and
      // Node terminates the process if nothing handles the event.
      pool.on("error", (err) => {
        console.error(`Idle connection error: ${err.message}`);
      });
      return pool;
    }
    
    // Borrows a connection from the pool, and returns the number back.
    async function runQuery(pool: pg.Pool, n: number): Promise<number> {
      // pool.query borrows a connection, runs the statement, and returns the
      // connection to the pool, whether or not an error occurred. Pass values
      // as parameters rather than building them into the SQL string. The cast
      // gives the parameter a type, which the server cannot infer from
      // SELECT $1 alone.
      const result = await pool.query<{ n: number }>("SELECT $1::int AS n", [n]);
      return result.rows[0].n;
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
      const pool = createPool();
      try {
        // All five queries start at once, but the pool has only two
        // connections, so the others wait their turn.
        const results = await Promise.all(
          [1, 2, 3, 4, 5].map((n) => runQuery(pool, n)),
        );
        const sum = results.reduce((total, n) => total + n, 0);
    
        console.log(
          `Ran ${results.length} queries through a pool of at most ` +
            `${POOL_SIZE} connections`,
        );
        console.log(`Sum of results: ${sum}`);
        return 0;
      } catch (err) {
        // Connection failures and errors reported by the server both arrive
        // here as rejected promises.
        console.error(`Database error: ${describe(err)}`);
        return 1;
      } finally {
        // The finally block runs whether or not an error occurred; end()
        // closes every connection in the pool.
        await pool.end();
      }
    }
    
    process.exitCode = await main();
    
    ```

=== "Java"

    ```java
    /*
     * Ellie's Postgres Cookbook
     * Using a connection pool, with JDBC and HikariCP.
     *
     * Copyright (c) 2026, pgEdge, Inc.
     * This code is released under the PostgreSQL License.
     */
    
    import com.zaxxer.hikari.HikariConfig;
    import com.zaxxer.hikari.HikariDataSource;
    import com.zaxxer.hikari.pool.HikariPool.PoolInitializationException;
    
    import java.sql.Connection;
    import java.sql.PreparedStatement;
    import java.sql.ResultSet;
    import java.sql.SQLException;
    import java.util.ArrayList;
    import java.util.List;
    import java.util.concurrent.ExecutionException;
    import java.util.concurrent.ExecutorService;
    import java.util.concurrent.Executors;
    import java.util.concurrent.Future;
    
    public class Main {
    
        /** The most connections that the pool opens at any one time. */
        static final int POOL_SIZE = 2;
    
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
    
        /** Creates a pool that holds at most POOL_SIZE connections. */
        static HikariDataSource createPool() {
            HikariConfig config = new HikariConfig();
            config.setJdbcUrl(connectionUrl());
            config.setUsername(envOr("PGUSER", "postgres"));
    
            // The password is omitted if PGPASSWORD is unset or empty.
            String password = envOr("PGPASSWORD", null);
            if (password != null) {
                config.setPassword(password);
            }
    
            config.setMaximumPoolSize(POOL_SIZE);
    
            // A request for a connection fails after this many milliseconds
            // if the pool can neither lend an idle connection nor open a new
            // one.
            config.setConnectionTimeout(5000);
    
            // The constructor opens the first connection, and throws a
            // PoolInitializationException if the server is unreachable.
            return new HikariDataSource(config);
        }
    
        /** Borrows a connection from the pool, and returns the number back. */
        static int runQuery(HikariDataSource pool, int number)
                throws SQLException {
            // Pass values as parameters rather than concatenating them into
            // the SQL string. The cast gives the parameter a type, which the
            // server cannot infer from SELECT ? alone.
            String sql = "SELECT ?::int";
    
            // try-with-resources returns the connection to the pool when the
            // block exits, whether or not an error occurred; closing a pooled
            // connection does not disconnect it from the server.
            try (Connection conn = pool.getConnection();
                 PreparedStatement stmt = conn.prepareStatement(sql)) {
                stmt.setInt(1, number);
    
                try (ResultSet rs = stmt.executeQuery()) {
                    rs.next();
                    return rs.getInt(1);
                }
            }
        }
    
        public static void main(String[] args) {
            // try-with-resources closes the pool, and every connection in it,
            // when the block exits, whether or not an error occurred.
            try (HikariDataSource pool = createPool()) {
                // Five threads ask for a connection at once, but the pool has
                // only two, so the other threads wait their turn.
                ExecutorService executor = Executors.newFixedThreadPool(5);
                List<Future<Integer>> futures = new ArrayList<>();
                try {
                    for (int n = 1; n <= 5; n++) {
                        int number = n;
                        futures.add(
                            executor.submit(() -> runQuery(pool, number)));
                    }
    
                    int sum = 0;
                    for (Future<Integer> future : futures) {
                        sum += future.get();
                    }
                    System.out.println("Ran " + futures.size()
                            + " queries through a pool of at most "
                            + POOL_SIZE + " connections");
                    System.out.println("Sum of results: " + sum);
                } finally {
                    executor.shutdown();
                }
            // A query that fails inside a thread arrives wrapped in an
            // ExecutionException. The pool throws PoolInitializationException
            // if it cannot open its first connection.
            } catch (ExecutionException e) {
                System.err.println("Database error: " + e.getCause().getMessage());
                System.exit(1);
            } catch (PoolInitializationException | InterruptedException e) {
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
     * Using a connection pool, with Npgsql.
     *
     * Copyright (c) 2026, pgEdge, Inc.
     * This code is released under the PostgreSQL License.
     */
    
    using Npgsql;
    
    // The most connections that the pool opens at any one time.
    const int PoolSize = 2;
    
    // Returns the value of an environment variable, or null if the variable
    // is unset or empty; libpq also treats an empty variable as unset.
    static string? EnvValue(string name) =>
        Environment.GetEnvironmentVariable(name) is { Length: > 0 } value
            ? value
            : null;
    
    // Returns the value of an environment variable, or a fallback if unset.
    static string EnvOr(string name, string fallback) =>
        EnvValue(name) ?? fallback;
    
    // Creates a data source, which owns a pool that holds at most PoolSize
    // connections. Npgsql pools connections by default; the connection string
    // builder sets the limits and takes care of quoting any special
    // characters in the settings.
    static NpgsqlDataSource CreatePool() =>
        NpgsqlDataSource.Create(new NpgsqlConnectionStringBuilder
        {
            Host = EnvOr("PGHOST", "localhost"),
            Port = int.Parse(EnvOr("PGPORT", "5432")),
            Database = EnvOr("PGDATABASE", "postgres"),
            Username = EnvOr("PGUSER", "postgres"),
            Password = EnvValue("PGPASSWORD"),
            MaxPoolSize = PoolSize,
    
            // A request for a connection fails after this many seconds if
            // the pool can neither lend an idle connection nor open a new one.
            Timeout = 5,
        }.ConnectionString);
    
    // Borrows a connection from the pool, and returns the number back.
    static async Task<int> RunQueryAsync(NpgsqlDataSource pool, int number)
    {
        // await using returns the connection to the pool when the method
        // exits, whether or not an error occurred; disposing of a pooled
        // connection does not disconnect it from the server.
        await using var conn = await pool.OpenConnectionAsync();
    
        // Pass values as parameters rather than building them into the SQL
        // string. Positional parameters are written $1, $2, and so on. The
        // cast gives the parameter a type, which the server cannot infer from
        // SELECT $1 alone.
        await using var cmd = new NpgsqlCommand("SELECT $1::int", conn)
        {
            Parameters = { new() { Value = number } },
        };
        return (int)(await cmd.ExecuteScalarAsync())!;
    }
    
    try
    {
        // await using closes the pool, and every connection in it, when the
        // block exits, whether or not an error occurred.
        await using var pool = CreatePool();
    
        // Five tasks ask for a connection at once, but the pool has only two,
        // so the other tasks wait their turn.
        var results = await Task.WhenAll(
            Enumerable.Range(1, 5).Select(n => RunQueryAsync(pool, n)));
    
        Console.WriteLine($"Ran {results.Length} queries through a pool of " +
                          $"at most {PoolSize} connections");
        Console.WriteLine($"Sum of results: {results.Sum()}");
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
    // Using a connection pool, with pgx and pgxpool.
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
    	"sync"
    
    	"github.com/jackc/pgx/v5/pgxpool"
    )
    
    
    // poolSize is the most connections that the pool opens at any one time.
    const poolSize = 2
    
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
    
    
    // createPool creates a pool that holds at most poolSize connections.
    func createPool(ctx context.Context) (*pgxpool.Pool, error) {
    	config, err := pgxpool.ParseConfig(connString())
    	if err != nil {
    		return nil, fmt.Errorf("invalid settings: %w", err)
    	}
    	config.MaxConns = poolSize
    
    	pool, err := pgxpool.NewWithConfig(ctx, config)
    	if err != nil {
    		return nil, fmt.Errorf("pool creation failed: %w", err)
    	}
    
    	// The pool opens connections on demand, so creating it never fails
    	// because of an unreachable server. Ping borrows a connection, which
    	// opens the first one and reports any problem straight away.
    	if err := pool.Ping(ctx); err != nil {
    		pool.Close()
    		return nil, fmt.Errorf("connection failed: %w", err)
    	}
    	return pool, nil
    }
    
    
    // runQuery borrows a connection from the pool, and returns the number
    // back.
    func runQuery(ctx context.Context, pool *pgxpool.Pool, number int32) (int32, error) {
    	// pool.QueryRow borrows a connection, runs the statement, and returns
    	// the connection to the pool once Scan has read the row. Pass values
    	// as parameters rather than building them into the SQL string. The
    	// cast gives the parameter a type, which the server cannot infer from
    	// SELECT $1 alone.
    	var result int32
    	err := pool.QueryRow(ctx, "SELECT $1::int", number).Scan(&result)
    	if err != nil {
    		return 0, fmt.Errorf("query failed: %w", err)
    	}
    	return result, nil
    }
    
    
    // run creates the pool, runs five queries through it at once, and prints
    // the sum, returning any error to the caller.
    func run(ctx context.Context) error {
    	pool, err := createPool(ctx)
    	if err != nil {
    		return err
    	}
    	// The deferred call closes the pool, and every connection in it, when
    	// run() returns, whether or not an error occurred.
    	defer pool.Close()
    
    	// Five goroutines ask for a connection at once, but the pool has only
    	// two, so the others wait their turn. Each goroutine writes only to
    	// its own element of the slices, so no further locking is needed.
    	const queries = 5
    	results := make([]int32, queries)
    	errs := make([]error, queries)
    	var wg sync.WaitGroup
    	for i := range queries {
    		wg.Add(1)
    		go func() {
    			defer wg.Done()
    			results[i], errs[i] = runQuery(ctx, pool, int32(i+1))
    		}()
    	}
    	wg.Wait()
    
    	if err := errors.Join(errs...); err != nil {
    		return err
    	}
    
    	var sum int32
    	for _, result := range results {
    		sum += result
    	}
    	fmt.Printf("Ran %d queries through a pool of at most %d connections\n", queries, poolSize)
    	fmt.Printf("Sum of results: %d\n", sum)
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
    // Using a connection pool, with the r2d2_postgres crate.
    //
    // Copyright (c) 2026, pgEdge, Inc.
    // This code is released under the PostgreSQL License.
    
    use std::env;
    use std::error::Error;
    use std::process::ExitCode;
    use std::thread;
    use std::time::Duration;
    
    use r2d2_postgres::postgres::{Config, NoTls};
    use r2d2_postgres::{r2d2, PostgresConnectionManager};
    
    /// The most connections that the pool opens at any one time.
    const POOL_SIZE: u32 = 2;
    
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
    
    /// A pool of connections made by the postgres crate.
    type Pool = r2d2::Pool<PostgresConnectionManager<NoTls>>;
    
    /// Creates a pool that holds at most POOL_SIZE connections. NoTls
    /// disables TLS, which keeps this example free of certificate set-up;
    /// connections over an untrusted network should use TLS.
    fn create_pool() -> Result<Pool, r2d2::Error> {
        let manager = PostgresConnectionManager::new(config(), NoTls);
        Pool::builder()
            .max_size(POOL_SIZE)
            // A request for a connection fails after this long if the pool
            // can neither lend an idle connection nor open a new one.
            .connection_timeout(Duration::from_secs(5))
            // build() opens the connections up front, and returns an error if
            // it cannot, for example because the server is unreachable.
            .build(manager)
    }
    
    /// Borrows a connection from the pool, and returns the number back.
    fn run_query(pool: &Pool, number: i32) -> Result<i32, Box<dyn Error + Send + Sync>> {
        // get() lends a connection, which returns to the pool when it goes out
        // of scope, whether or not an error occurred; dropping a pooled
        // connection does not disconnect it from the server.
        let mut client = pool.get()?;
    
        // Pass values as parameters rather than building them into the SQL
        // string. The cast gives the parameter a type, which the server cannot
        // infer from SELECT $1 alone.
        let row = client.query_one("SELECT $1::int", &[&number])?;
        Ok(row.get(0))
    }
    
    /// Creates the pool, runs five queries through it at once, and prints the
    /// sum. The ? operator returns any error to the caller.
    fn run() -> Result<(), Box<dyn Error + Send + Sync>> {
        let pool = create_pool()?;
    
        // Five threads ask for a connection at once, but the pool has only
        // two, so the other threads wait their turn. Cloning a pool is cheap,
        // because every clone shares the same connections.
        let handles: Vec<_> = (1..=5)
            .map(|number| {
                let pool = pool.clone();
                thread::spawn(move || run_query(&pool, number))
            })
            .collect();
    
        let mut results = Vec::new();
        for handle in handles {
            results.push(handle.join().map_err(|_| "a query thread panicked")??);
        }
    
        println!(
            "Ran {} queries through a pool of at most {POOL_SIZE} connections",
            results.len()
        );
        println!("Sum of results: {}", results.iter().sum::<i32>());
    
        // Dropping the pool closes every connection in it.
        Ok(())
    }
    
    /// Reports any error returned by run() and exits with a failure status.
    /// The top-level error is often generic, so the chain of underlying
    /// causes is printed too.
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
    # Using a connection pool, with the pg and connection_pool gems.
    #
    # Copyright (c) 2026, pgEdge, Inc.
    # This code is released under the PostgreSQL License.
    
    require "connection_pool"
    require "pg"
    
    # The most connections that the pool opens at any one time.
    POOL_SIZE = 2
    
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
    
    # Creates a pool that holds at most POOL_SIZE connections.
    def create_pool
      # The block opens a new connection, and the pool calls it on demand, at
      # most POOL_SIZE times. A request for a connection waits for up to
      # timeout seconds when both connections are busy, and then raises
      # ConnectionPool::TimeoutError.
      ConnectionPool.new(size: POOL_SIZE, timeout: 5) do
        PG.connect(connection_params)
      end
    end
    
    # Borrows a connection from the pool, and returns the number back.
    def run_query(pool, number)
      # The with block borrows a connection and returns it to the pool when it
      # exits, whether or not an error occurred; it does not close it. Pass
      # values as parameters rather than interpolating them into the SQL
      # string. The cast gives the parameter a type, which the server cannot
      # infer from SELECT $1 alone.
      pool.with do |conn|
        conn.exec_params("SELECT $1::int", [number]).getvalue(0, 0).to_i
      end
    end
    
    # Ruby prints a stack trace when a thread fails. Thread#value raises the
    # same error again in the main thread, where the rescue clause reports it,
    # so switch off the duplicate trace.
    Thread.report_on_exception = false
    
    begin
      pool = create_pool
    
      # Five threads ask for a connection at once, but the pool has only two,
      # so the other threads wait their turn. Thread#value waits for a thread
      # to finish and raises any error that the thread raised.
      threads = (1..5).map { |n| Thread.new { run_query(pool, n) } }
      results = threads.map(&:value)
    
      puts "Ran #{results.size} queries through a pool of at most " \
           "#{POOL_SIZE} connections"
      puts "Sum of results: #{results.sum}"
    # PG::Error is the base class for every error the gem raises, including
    # connection failures and errors reported by the server.
    rescue PG::Error => e
      warn "Database error: #{e.message}"
      exit 1
    # The pool raises its own error, which is not a PG::Error, when no
    # connection becomes free within the timeout.
    rescue ConnectionPool::TimeoutError => e
      warn "Database error: #{e.message}"
      exit 1
    # The ensure block runs whether or not an error occurred. pool is nil if
    # it could not be created, and shutdown closes every connection that the
    # pool opened.
    ensure
      pool&.shutdown { |conn| conn.close }
    end
    
    ```

=== "C"

    This recipe has no C program, because libpq has no connection pool. Use
    [PgBouncer](https://www.pgbouncer.org/) to pool connections for a C
    application.

## Next Steps

The following resources provide more information about the topics in this
recipe:

- The [PgBouncer documentation](https://www.pgbouncer.org/config.html)
  describes the three pooling modes, and the settings that size the pool.
- The [psycopg pool documentation](https://www.psycopg.org/psycopg3/docs/advanced/pool.html)
  explains how a pool grows and shrinks between its minimum and maximum
  sizes.
- The [first recipe](connect_and_query.md) explains the connection settings
  that every example uses.
