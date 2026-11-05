# Reading Large Results in Batches

This recipe demonstrates how an application reads a query result that is
too large to hold in memory. By default, most drivers transfer the whole
result to the client before the program sees the first row, so a query
that returns millions of rows can exhaust the memory of the application.
Each driver offers a way to read the result as a stream, or in batches,
and the examples show the idiomatic approach for each language. Each step
shows the code in every supported language; selecting a language tab
switches every tab on the site to that language.

The example program runs `SELECT g FROM generate_series(1, 100000) AS g`,
which returns the integers 1 to 100000, reads every row without holding
the whole result at once, and adds up the values. The sum of the first
100,000 integers is always 5000050000, so the output is easy to verify:

```text
Rows read: 100000
Sum of values: 5000050000
```

## Preparing the Ingredients

Each example uses the most widely adopted PostgreSQL driver for its
language; the TypeScript example adds the `pg-cursor` companion library,
because node-postgres needs it to read a result in batches. The following
table lists the driver that each example uses:

| Language   | Driver                                                 |
|------------|--------------------------------------------------------|
| Python     | [psycopg 3](https://www.psycopg.org/psycopg3/)         |
| TypeScript | [node-postgres](https://node-postgres.com/) with [pg-cursor](https://github.com/brianc/node-postgres/tree/master/packages/pg-cursor) |
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
      "name": "large-results",
      "private": true,
      "type": "module",
      "scripts": {
        "build": "tsc",
        "start": "node dist/main.js"
      },
      "dependencies": {
        "pg": "^8.23.1",
        "pg-cursor": "^2.22.1"
      },
      "devDependencies": {
        "@types/node": "^22.0.0",
        "@types/pg": "^8.23.1",
        "@types/pg-cursor": "^2.7.2",
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
    import Cursor from "pg-cursor";
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
variables that libpq and `psql` use: `PGHOST`, `PGPORT`, `PGDATABASE`,
`PGUSER`, and `PGPASSWORD`. Like libpq, each example treats an empty
variable as unset, and uses a default suitable for a local server instead.
The [first recipe](connect_and_query.md) describes the variables in
detail. The following tabs show how each program assembles the connection
settings:

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
one. The following tabs show how each program opens the connection:

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

## Reading the Result in Batches

Each program runs the query and reads the rows without loading the whole
result into memory. The drivers use two different approaches, and the
approach decides what a batch size means.

Most drivers use a cursor, which makes the server keep the result and send
rows only when the program asks for them. A cursor exists only inside a
transaction, which some drivers start implicitly: the Python and
TypeScript programs rely on the transaction that psycopg and the
PostgreSQL protocol open for them, and the other programs start one
explicitly. The Python program names its
cursor, which makes psycopg create a server-side cursor, and calls
`fetchmany(1000)` for each batch. The TypeScript program runs a `pg-cursor`
query, and calls `read(1000)` for each batch. The Java program turns off
autocommit and sets a fetch size of 1,000, and the driver then fetches
each batch when `next()` reaches the end of the previous one; with
autocommit on, pgJDBC ignores the fetch size and loads the whole result.
The Rust program binds the query to a portal, which is the protocol name
for a cursor, and calls `query_portal()` for each batch. The Ruby and C
programs declare a cursor with `DECLARE` and read each batch with
`FETCH 1000`. A cursor name cannot be a query parameter, so those two
programs write it into the SQL as a fixed string rather than as
application data.

The Go and C# drivers instead read rows from the network as the program
consumes them. A pgx `Rows` object and an Npgsql `NpgsqlDataReader` hold
only the rows that have arrived in the connection's read buffer, so the
program never has the whole result in memory, but there is no batch size
to set. The loop reads one row at a time, and the Go program checks
`rows.Err()` afterwards because `Next()` returns false both at the end of
the result and after an error. The following tabs show how each program
reads the result:

=== "Python"

    ```python
    BATCH_SIZE = 1000
    
    
    def read_in_batches(conn: psycopg.Connection) -> tuple[int, int]:
        """Reads every row of a large result, one batch at a time, and
        returns the number of rows and the sum of their values."""
        rows_read = 0
        total = 0
    
        # Giving the cursor a name makes it a server-side cursor: the server
        # keeps the result and sends rows only as the program asks for them.
        # An ordinary cursor would transfer all 100,000 rows to the client
        # before the first fetch. The cursor lives inside the transaction
        # that psycopg opens for us, and the with block closes it.
        with conn.cursor(name="large_results") as cur:
            cur.execute("SELECT g FROM generate_series(1, 100000) AS g")
    
            while True:
                # fetchmany() asks the server for the next batch, and returns
                # an empty list once the result is exhausted.
                batch = cur.fetchmany(BATCH_SIZE)
                if not batch:
                    break
    
                for (value,) in batch:
                    rows_read += 1
                    total += value
    
        return rows_read, total
    ```

=== "TypeScript"

    ```typescript
    const BATCH_SIZE = 1000;
    
    // Reads every row of a large result, one batch at a time, and returns the
    // number of rows and the sum of their values.
    async function readInBatches(
      client: pg.Client,
    ): Promise<{ rowsRead: number; total: number }> {
      let rowsRead = 0;
      let total = 0;
    
      // A Cursor is a query that the client runs like any other, but that
      // fetches rows only when the program calls read(). The driver declares
      // a portal on the server, so the client never holds the whole result.
      const cursor = client.query(
        new Cursor<{ g: number }>(
          "SELECT g FROM generate_series(1, 100000) AS g",
        ),
      );
    
      try {
        while (true) {
          // read() resolves with up to BATCH_SIZE rows, and with an empty
          // array once the result is exhausted.
          const batch = await cursor.read(BATCH_SIZE);
          if (batch.length === 0) {
            break;
          }
    
          for (const row of batch) {
            rowsRead += 1;
            total += row.g;
          }
        }
      } finally {
        // Closing the cursor releases the portal, even after an error.
        await cursor.close();
      }
    
      return { rowsRead, total };
    }
    ```

=== "Java"

    ```java
    static final int BATCH_SIZE = 1000;
    
    /**
     * Reads every row of a large result, one batch at a time, and prints
     * the number of rows and the sum of their values.
     */
    static void readInBatches(Connection conn) throws SQLException {
        long rowsRead = 0;
        long total = 0;
    
        // The driver streams a result only inside a transaction, so turn
        // off autocommit. With autocommit on, the driver ignores the
        // fetch size and loads all 100,000 rows into memory.
        conn.setAutoCommit(false);
    
        try (Statement stmt = conn.createStatement()) {
            // The fetch size makes the driver ask the server for 1,000
            // rows at a time, through a cursor that it manages for us.
            stmt.setFetchSize(BATCH_SIZE);
    
            try (ResultSet rs = stmt.executeQuery(
                    "SELECT g FROM generate_series(1, 100000) AS g")) {
                // next() fetches the following batch whenever the
                // current one has been read.
                while (rs.next()) {
                    rowsRead++;
                    total += rs.getLong(1);
                }
            }
        }
    
        // End the transaction, which also releases the cursor.
        conn.commit();
    
        System.out.println("Rows read: " + rowsRead);
        System.out.println("Sum of values: " + total);
    }
    ```

=== "C#"

    ```csharp
    // Reads every row of a large result, and returns the number of rows and
    // the sum of their values.
    static async Task<(long RowsRead, long Total)> ReadRowsAsync(
        NpgsqlConnection conn)
    {
        long rowsRead = 0;
        long total = 0;
    
        await using var cmd = new NpgsqlCommand(
            "SELECT g FROM generate_series(1, 100000) AS g", conn);
    
        // ExecuteReaderAsync does not load the result into memory. Npgsql
        // reads rows from the network as ReadAsync asks for them, so the
        // program holds one row at a time; there is no batch size to set,
        // because the connection's read buffer takes the place of the batch.
        await using var reader = await cmd.ExecuteReaderAsync();
    
        // ReadAsync returns false once the result is exhausted.
        while (await reader.ReadAsync())
        {
            rowsRead++;
            total += reader.GetInt32(0);
        }
    
        return (rowsRead, total);
    }
    ```

=== "Go"

    ```go
    // readRows reads every row of a large result, and returns the number of
    // rows and the sum of their values.
    func readRows(ctx context.Context, conn *pgx.Conn) (rowsRead, total int64, err error) {
    	// Query does not load the result into memory. pgx reads rows from the
    	// network as the loop asks for them, so the program holds one row at
    	// a time; pgx has no batch size to set, because the connection's
    	// buffer takes the place of the batch.
    	rows, err := conn.Query(ctx, "SELECT g FROM generate_series(1, 100000) AS g")
    	if err != nil {
    		return 0, 0, fmt.Errorf("query failed: %w", err)
    	}
    	// Close releases the connection for further use, even if the loop
    	// stops early.
    	defer rows.Close()
    
    	for rows.Next() {
    		var value int32
    		if err := rows.Scan(&value); err != nil {
    			return 0, 0, fmt.Errorf("scan failed: %w", err)
    		}
    		rowsRead++
    		total += int64(value)
    	}
    
    	// Next returns false at the end of the result and after an error, so
    	// the program checks Err to tell the two apart.
    	if err := rows.Err(); err != nil {
    		return 0, 0, fmt.Errorf("read failed: %w", err)
    	}
    	return rowsRead, total, nil
    }
    
    ```

=== "Rust"

    ```rust
    const BATCH_SIZE: i32 = 1000;
    
    /// Reads every row of a large result, one batch at a time, and returns
    /// the number of rows and the sum of their values.
    fn read_in_batches(client: &mut Client) -> Result<(u64, i64), postgres::Error> {
        let mut rows_read = 0;
        let mut total = 0;
    
        // A portal, which holds a partly read result on the server, exists
        // only inside a transaction.
        let mut transaction = client.transaction()?;
        let portal = transaction.bind("SELECT g FROM generate_series(1, 100000) AS g", &[])?;
    
        loop {
            // query_portal() returns up to BATCH_SIZE rows, and an empty
            // list once the result is exhausted.
            let batch = transaction.query_portal(&portal, BATCH_SIZE)?;
            if batch.is_empty() {
                break;
            }
    
            for row in &batch {
                // generate_series over int literals produces an integer,
                // which maps to i32.
                let value: i32 = row.get(0);
                rows_read += 1;
                total += i64::from(value);
            }
        }
    
        // End the transaction, which also releases the portal.
        transaction.commit()?;
        Ok((rows_read, total))
    }
    ```

=== "Ruby"

    ```ruby
    BATCH_SIZE = 1000
    
    # Reads every row of a large result, one batch at a time, and returns the
    # number of rows and the sum of their values.
    def read_in_batches(conn)
      rows_read = 0
      total = 0
    
      # A cursor lives only inside a transaction, and the transaction method
      # commits when the block ends, or rolls back if the block raises.
      conn.transaction do
        # DECLARE makes the server hold the result and hand out rows only on
        # request. The pg gem would otherwise copy all 100,000 rows into
        # memory before exec returns. A cursor name cannot be a parameter,
        # but this one is a fixed string, not application data.
        conn.exec("DECLARE large_results CURSOR FOR " \
                  "SELECT g FROM generate_series(1, 100000) AS g")
    
        loop do
          # FETCH returns the next batch, and an empty result at the end.
          batch = conn.exec("FETCH #{BATCH_SIZE} FROM large_results")
          break if batch.ntuples.zero?
    
          batch.each_row do |(value)|
            rows_read += 1
            total += value.to_i
          end
        end
    
        conn.exec("CLOSE large_results")
      end
    
      [rows_read, total]
    end
    ```

=== "C"

    ```c
    #define BATCH_SIZE 1000
    
    /* Run a command that returns no rows, and return true on success. */
    static bool
    run_command(PGconn *conn, const char *sql)
    {
        PGresult *res = PQexec(conn, sql);
        bool ok = PQresultStatus(res) == PGRES_COMMAND_OK;
    
        PQclear(res);
        return ok;
    }
    
    /*
     * Read every row of a large result, one batch at a time, and store the
     * number of rows and the sum of their values in *rows_read and *total.
     * Return true on success.
     */
    static bool
    read_in_batches(PGconn *conn, long long *rows_read, long long *total)
    {
        char fetch[64];
        bool ok;
    
        *rows_read = 0;
        *total = 0;
    
        /* The batch size is a constant, so it is safe to put in the SQL. */
        snprintf(fetch, sizeof(fetch), "FETCH %d FROM large_results", BATCH_SIZE);
    
        /*
         * PQexec() would copy the whole result into memory. A cursor, which
         * lives only inside a transaction, makes the server hold the result
         * and hand out rows on request instead. The cursor name is a fixed
         * string, not application data, because a name cannot be a parameter.
         */
        ok = run_command(conn, "BEGIN") &&
             run_command(conn,
                         "DECLARE large_results CURSOR FOR "
                         "SELECT g FROM generate_series(1, 100000) AS g");
    
        while (ok)
        {
            /* FETCH returns the next batch, and no rows at the end. */
            PGresult *res = PQexec(conn, fetch);
            int rows;
    
            if (PQresultStatus(res) != PGRES_TUPLES_OK)
            {
                PQclear(res);
                ok = false;
                break;
            }
    
            rows = PQntuples(res);
            for (int row = 0; row < rows; row++)
            {
                /* Results arrive as text, so convert the value to a number. */
                *rows_read += 1;
                *total += strtoll(PQgetvalue(res, row, 0), NULL, 10);
            }
            PQclear(res);
    
            if (rows == 0)
                break;
        }
    
        /*
         * Ending the transaction also closes the cursor. COMMIT after an
         * error is harmless, because the server then rolls back.
         */
        return run_command(conn, "COMMIT") && ok;
    }
    ```

## Handling Errors and Closing the Connection

The main part of each program calls the function from the previous step,
and prints the results. The program reports any connection or query
failure on `stderr`, and then exits with a non-zero status, and it closes
the connection when the work completes or fails. The error handling and
the cleanup follow the pattern of the
[first recipe](connect_and_query.md). The following tabs show the main part
of each program:

=== "Python"

    ```python
    def main() -> int:
        try:
            # The with block closes the connection when it exits, whether or
            # not an error occurred.
            with connect() as conn:
                rows_read, total = read_in_batches(conn)
                print(f"Rows read: {rows_read}")
                print(f"Sum of values: {total}")
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
        const { rowsRead, total } = await readInBatches(client);
        console.log(`Rows read: ${rowsRead}`);
        console.log(`Sum of values: ${total}`);
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
            readInBatches(conn);
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
    
        var (rowsRead, total) = await ReadRowsAsync(conn);
        Console.WriteLine($"Rows read: {rowsRead}");
        Console.WriteLine($"Sum of values: {total}");
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
    // run connects, reads the rows, and prints the result, returning any
    // error to the caller.
    func run(ctx context.Context) error {
    	conn, err := connect(ctx)
    	if err != nil {
    		return err
    	}
    	// The deferred call closes the connection when run() returns, whether
    	// or not an error occurred.
    	defer conn.Close(ctx)
    
    	rowsRead, total, err := readRows(ctx, conn)
    	if err != nil {
    		return err
    	}
    
    	fmt.Printf("Rows read: %d\n", rowsRead)
    	fmt.Printf("Sum of values: %d\n", total)
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
    /// Connects, reads the rows, and prints the result. The ? operator
    /// returns any error to the caller.
    fn run() -> Result<(), postgres::Error> {
        let mut client = connect()?;
        let (rows_read, total) = read_in_batches(&mut client)?;
        println!("Rows read: {rows_read}");
        println!("Sum of values: {total}");
    
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
      rows_read, total = read_in_batches(conn)
      puts "Rows read: #{rows_read}"
      puts "Sum of values: #{total}"
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
        long long rows_read;
        long long total;
        PGconn *conn = connect_to_server();
    
        /* The || operator skips the read if the connection failed. */
        if (PQstatus(conn) != CONNECTION_OK ||
            !read_in_batches(conn, &rows_read, &total))
        {
            fprintf(stderr, "Database error: %s", PQerrorMessage(conn));
        }
        else
        {
            printf("Rows read: %lld\n", rows_read);
            printf("Sum of values: %lld\n", total);
            status = EXIT_SUCCESS;
        }
    
        /* Close the connection whether or not an error occurred. */
        PQfinish(conn);
        return status;
    }
    ```

## Running the Example

The complete project for each language is available in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/postgresql/large_results).
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
    Reading a large result in batches, using psycopg 3.
    
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
    
    
    BATCH_SIZE = 1000
    
    
    def read_in_batches(conn: psycopg.Connection) -> tuple[int, int]:
        """Reads every row of a large result, one batch at a time, and
        returns the number of rows and the sum of their values."""
        rows_read = 0
        total = 0
    
        # Giving the cursor a name makes it a server-side cursor: the server
        # keeps the result and sends rows only as the program asks for them.
        # An ordinary cursor would transfer all 100,000 rows to the client
        # before the first fetch. The cursor lives inside the transaction
        # that psycopg opens for us, and the with block closes it.
        with conn.cursor(name="large_results") as cur:
            cur.execute("SELECT g FROM generate_series(1, 100000) AS g")
    
            while True:
                # fetchmany() asks the server for the next batch, and returns
                # an empty list once the result is exhausted.
                batch = cur.fetchmany(BATCH_SIZE)
                if not batch:
                    break
    
                for (value,) in batch:
                    rows_read += 1
                    total += value
    
        return rows_read, total
    
    
    def main() -> int:
        try:
            # The with block closes the connection when it exits, whether or
            # not an error occurred.
            with connect() as conn:
                rows_read, total = read_in_batches(conn)
                print(f"Rows read: {rows_read}")
                print(f"Sum of values: {total}")
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
     * Reading a large result in batches, using node-postgres and pg-cursor.
     *
     * Copyright (c) 2026, pgEdge, Inc.
     * This code is released under the PostgreSQL License.
     */
    
    import pg from "pg";
    import Cursor from "pg-cursor";
    
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
    
    const BATCH_SIZE = 1000;
    
    // Reads every row of a large result, one batch at a time, and returns the
    // number of rows and the sum of their values.
    async function readInBatches(
      client: pg.Client,
    ): Promise<{ rowsRead: number; total: number }> {
      let rowsRead = 0;
      let total = 0;
    
      // A Cursor is a query that the client runs like any other, but that
      // fetches rows only when the program calls read(). The driver declares
      // a portal on the server, so the client never holds the whole result.
      const cursor = client.query(
        new Cursor<{ g: number }>(
          "SELECT g FROM generate_series(1, 100000) AS g",
        ),
      );
    
      try {
        while (true) {
          // read() resolves with up to BATCH_SIZE rows, and with an empty
          // array once the result is exhausted.
          const batch = await cursor.read(BATCH_SIZE);
          if (batch.length === 0) {
            break;
          }
    
          for (const row of batch) {
            rowsRead += 1;
            total += row.g;
          }
        }
      } finally {
        // Closing the cursor releases the portal, even after an error.
        await cursor.close();
      }
    
      return { rowsRead, total };
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
        const { rowsRead, total } = await readInBatches(client);
        console.log(`Rows read: ${rowsRead}`);
        console.log(`Sum of values: ${total}`);
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
     * Reading a large result in batches, using JDBC and the PostgreSQL JDBC
     * driver (pgJDBC).
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
    
        static final int BATCH_SIZE = 1000;
    
        /**
         * Reads every row of a large result, one batch at a time, and prints
         * the number of rows and the sum of their values.
         */
        static void readInBatches(Connection conn) throws SQLException {
            long rowsRead = 0;
            long total = 0;
    
            // The driver streams a result only inside a transaction, so turn
            // off autocommit. With autocommit on, the driver ignores the
            // fetch size and loads all 100,000 rows into memory.
            conn.setAutoCommit(false);
    
            try (Statement stmt = conn.createStatement()) {
                // The fetch size makes the driver ask the server for 1,000
                // rows at a time, through a cursor that it manages for us.
                stmt.setFetchSize(BATCH_SIZE);
    
                try (ResultSet rs = stmt.executeQuery(
                        "SELECT g FROM generate_series(1, 100000) AS g")) {
                    // next() fetches the following batch whenever the
                    // current one has been read.
                    while (rs.next()) {
                        rowsRead++;
                        total += rs.getLong(1);
                    }
                }
            }
    
            // End the transaction, which also releases the cursor.
            conn.commit();
    
            System.out.println("Rows read: " + rowsRead);
            System.out.println("Sum of values: " + total);
        }
    
        public static void main(String[] args) {
            // try-with-resources closes the connection when the block exits,
            // whether or not an error occurred.
            try (Connection conn = connect()) {
                readInBatches(conn);
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
     * Reading a large result in batches, using Npgsql.
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
    
    // Reads every row of a large result, and returns the number of rows and
    // the sum of their values.
    static async Task<(long RowsRead, long Total)> ReadRowsAsync(
        NpgsqlConnection conn)
    {
        long rowsRead = 0;
        long total = 0;
    
        await using var cmd = new NpgsqlCommand(
            "SELECT g FROM generate_series(1, 100000) AS g", conn);
    
        // ExecuteReaderAsync does not load the result into memory. Npgsql
        // reads rows from the network as ReadAsync asks for them, so the
        // program holds one row at a time; there is no batch size to set,
        // because the connection's read buffer takes the place of the batch.
        await using var reader = await cmd.ExecuteReaderAsync();
    
        // ReadAsync returns false once the result is exhausted.
        while (await reader.ReadAsync())
        {
            rowsRead++;
            total += reader.GetInt32(0);
        }
    
        return (rowsRead, total);
    }
    
    try
    {
        // await using disposes of the data source, and returns the connection
        // to the pool, when the block exits, whether or not an error occurred.
        await using var dataSource = CreateDataSource();
        await using var conn = await dataSource.OpenConnectionAsync();
    
        var (rowsRead, total) = await ReadRowsAsync(conn);
        Console.WriteLine($"Rows read: {rowsRead}");
        Console.WriteLine($"Sum of values: {total}");
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
    // Reading a large result in batches, using pgx.
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
    
    
    // readRows reads every row of a large result, and returns the number of
    // rows and the sum of their values.
    func readRows(ctx context.Context, conn *pgx.Conn) (rowsRead, total int64, err error) {
    	// Query does not load the result into memory. pgx reads rows from the
    	// network as the loop asks for them, so the program holds one row at
    	// a time; pgx has no batch size to set, because the connection's
    	// buffer takes the place of the batch.
    	rows, err := conn.Query(ctx, "SELECT g FROM generate_series(1, 100000) AS g")
    	if err != nil {
    		return 0, 0, fmt.Errorf("query failed: %w", err)
    	}
    	// Close releases the connection for further use, even if the loop
    	// stops early.
    	defer rows.Close()
    
    	for rows.Next() {
    		var value int32
    		if err := rows.Scan(&value); err != nil {
    			return 0, 0, fmt.Errorf("scan failed: %w", err)
    		}
    		rowsRead++
    		total += int64(value)
    	}
    
    	// Next returns false at the end of the result and after an error, so
    	// the program checks Err to tell the two apart.
    	if err := rows.Err(); err != nil {
    		return 0, 0, fmt.Errorf("read failed: %w", err)
    	}
    	return rowsRead, total, nil
    }
    
    
    // run connects, reads the rows, and prints the result, returning any
    // error to the caller.
    func run(ctx context.Context) error {
    	conn, err := connect(ctx)
    	if err != nil {
    		return err
    	}
    	// The deferred call closes the connection when run() returns, whether
    	// or not an error occurred.
    	defer conn.Close(ctx)
    
    	rowsRead, total, err := readRows(ctx, conn)
    	if err != nil {
    		return err
    	}
    
    	fmt.Printf("Rows read: %d\n", rowsRead)
    	fmt.Printf("Sum of values: %d\n", total)
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
    // Reading a large result in batches, using the postgres crate.
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
    
    const BATCH_SIZE: i32 = 1000;
    
    /// Reads every row of a large result, one batch at a time, and returns
    /// the number of rows and the sum of their values.
    fn read_in_batches(client: &mut Client) -> Result<(u64, i64), postgres::Error> {
        let mut rows_read = 0;
        let mut total = 0;
    
        // A portal, which holds a partly read result on the server, exists
        // only inside a transaction.
        let mut transaction = client.transaction()?;
        let portal = transaction.bind("SELECT g FROM generate_series(1, 100000) AS g", &[])?;
    
        loop {
            // query_portal() returns up to BATCH_SIZE rows, and an empty
            // list once the result is exhausted.
            let batch = transaction.query_portal(&portal, BATCH_SIZE)?;
            if batch.is_empty() {
                break;
            }
    
            for row in &batch {
                // generate_series over int literals produces an integer,
                // which maps to i32.
                let value: i32 = row.get(0);
                rows_read += 1;
                total += i64::from(value);
            }
        }
    
        // End the transaction, which also releases the portal.
        transaction.commit()?;
        Ok((rows_read, total))
    }
    
    /// Connects, reads the rows, and prints the result. The ? operator
    /// returns any error to the caller.
    fn run() -> Result<(), postgres::Error> {
        let mut client = connect()?;
        let (rows_read, total) = read_in_batches(&mut client)?;
        println!("Rows read: {rows_read}");
        println!("Sum of values: {total}");
    
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
    # Reading a large result in batches, using the pg gem.
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
    
    BATCH_SIZE = 1000
    
    # Reads every row of a large result, one batch at a time, and returns the
    # number of rows and the sum of their values.
    def read_in_batches(conn)
      rows_read = 0
      total = 0
    
      # A cursor lives only inside a transaction, and the transaction method
      # commits when the block ends, or rolls back if the block raises.
      conn.transaction do
        # DECLARE makes the server hold the result and hand out rows only on
        # request. The pg gem would otherwise copy all 100,000 rows into
        # memory before exec returns. A cursor name cannot be a parameter,
        # but this one is a fixed string, not application data.
        conn.exec("DECLARE large_results CURSOR FOR " \
                  "SELECT g FROM generate_series(1, 100000) AS g")
    
        loop do
          # FETCH returns the next batch, and an empty result at the end.
          batch = conn.exec("FETCH #{BATCH_SIZE} FROM large_results")
          break if batch.ntuples.zero?
    
          batch.each_row do |(value)|
            rows_read += 1
            total += value.to_i
          end
        end
    
        conn.exec("CLOSE large_results")
      end
    
      [rows_read, total]
    end
    
    begin
      conn = connect
      rows_read, total = read_in_batches(conn)
      puts "Rows read: #{rows_read}"
      puts "Sum of values: #{total}"
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
     * Reading a large result in batches, using libpq.
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
    
    #define BATCH_SIZE 1000
    
    /* Run a command that returns no rows, and return true on success. */
    static bool
    run_command(PGconn *conn, const char *sql)
    {
        PGresult *res = PQexec(conn, sql);
        bool ok = PQresultStatus(res) == PGRES_COMMAND_OK;
    
        PQclear(res);
        return ok;
    }
    
    /*
     * Read every row of a large result, one batch at a time, and store the
     * number of rows and the sum of their values in *rows_read and *total.
     * Return true on success.
     */
    static bool
    read_in_batches(PGconn *conn, long long *rows_read, long long *total)
    {
        char fetch[64];
        bool ok;
    
        *rows_read = 0;
        *total = 0;
    
        /* The batch size is a constant, so it is safe to put in the SQL. */
        snprintf(fetch, sizeof(fetch), "FETCH %d FROM large_results", BATCH_SIZE);
    
        /*
         * PQexec() would copy the whole result into memory. A cursor, which
         * lives only inside a transaction, makes the server hold the result
         * and hand out rows on request instead. The cursor name is a fixed
         * string, not application data, because a name cannot be a parameter.
         */
        ok = run_command(conn, "BEGIN") &&
             run_command(conn,
                         "DECLARE large_results CURSOR FOR "
                         "SELECT g FROM generate_series(1, 100000) AS g");
    
        while (ok)
        {
            /* FETCH returns the next batch, and no rows at the end. */
            PGresult *res = PQexec(conn, fetch);
            int rows;
    
            if (PQresultStatus(res) != PGRES_TUPLES_OK)
            {
                PQclear(res);
                ok = false;
                break;
            }
    
            rows = PQntuples(res);
            for (int row = 0; row < rows; row++)
            {
                /* Results arrive as text, so convert the value to a number. */
                *rows_read += 1;
                *total += strtoll(PQgetvalue(res, row, 0), NULL, 10);
            }
            PQclear(res);
    
            if (rows == 0)
                break;
        }
    
        /*
         * Ending the transaction also closes the cursor. COMMIT after an
         * error is harmless, because the server then rolls back.
         */
        return run_command(conn, "COMMIT") && ok;
    }
    
    int
    main(void)
    {
        int status = EXIT_FAILURE;
        long long rows_read;
        long long total;
        PGconn *conn = connect_to_server();
    
        /* The || operator skips the read if the connection failed. */
        if (PQstatus(conn) != CONNECTION_OK ||
            !read_in_batches(conn, &rows_read, &total))
        {
            fprintf(stderr, "Database error: %s", PQerrorMessage(conn));
        }
        else
        {
            printf("Rows read: %lld\n", rows_read);
            printf("Sum of values: %lld\n", total);
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

- The PostgreSQL documentation for
  [DECLARE](https://www.postgresql.org/docs/current/sql-declare.html)
  and [FETCH](https://www.postgresql.org/docs/current/sql-fetch.html)
  describes server-side cursors.
- The PostgreSQL documentation for
  [retrieving query results row by row](https://www.postgresql.org/docs/current/libpq-single-row-mode.html)
  describes the single-row mode that libpq offers as an alternative to a
  cursor.
- The [Contributing a Recipe](../contributing.md) page explains how to add
  a recipe or a language to the cookbook.
