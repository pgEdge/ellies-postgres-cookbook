# Bulk Loading with COPY

This recipe demonstrates how an application loads many rows into a
PostgreSQL table with the `COPY` command, which is far faster than sending
one `INSERT` statement for each row. Each driver exposes `COPY ... FROM
STDIN` through its own API, and the examples stream the rows to the server
without building the whole data set in memory. Each step shows the code in
every supported language; selecting a language tab switches every tab on
the site to that language.

The example program creates a temporary table named `items`, generates
1,000 rows with the ids 1 to 1000 and the names `item 1` to `item 1000`,
and loads them with a single `COPY` command. The program then asks the
server for the number of rows in the table and the sum of their ids, which
is always 500500, so the output is easy to verify:

```text
Copied 1000 rows
Rows in table: 1000
Sum of ids: 500500
```

## Preparing the Ingredients

Each example uses the most widely adopted PostgreSQL driver for its
language; the TypeScript example adds the `pg-copy-streams` companion
library, because node-postgres has no copy support of its own. The
following table lists the API that each example uses for `COPY`:

| Language   | Copy API                                                       |
|------------|----------------------------------------------------------------|
| Python     | [psycopg 3](https://www.psycopg.org/psycopg3/) `cursor.copy()` |
| TypeScript | [pg-copy-streams](https://github.com/brianc/node-pg-copy-streams) |
| Java       | [pgJDBC](https://jdbc.postgresql.org/) `CopyManager` API       |
| C#         | [Npgsql](https://www.npgsql.org/) `BeginBinaryImport()`        |
| Go         | [pgx](https://github.com/jackc/pgx) `CopyFrom()`               |
| Rust       | [rust-postgres](https://github.com/rust-postgres/rust-postgres) `copy_in()` |
| Ruby       | [ruby-pg](https://github.com/ged/ruby-pg) `copy_data()`        |
| C          | [libpq](https://www.postgresql.org/docs/current/libpq.html) `PQputCopyData()` |

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
      "name": "bulk-copy",
      "private": true,
      "type": "module",
      "scripts": {
        "build": "tsc",
        "start": "node dist/main.js"
      },
      "dependencies": {
        "pg": "^8.23.1",
        "pg-copy-streams": "^7.0.0"
      },
      "devDependencies": {
        "@types/node": "^22.0.0",
        "@types/pg": "^8.23.1",
        "@types/pg-copy-streams": "^1.2.5",
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
    import { Readable } from "node:stream";
    import { pipeline } from "node:stream/promises";
    
    import pg from "pg";
    import { from as copyFrom } from "pg-copy-streams";
    ```

=== "Java"

    ```java
    import java.nio.charset.StandardCharsets;
    import java.sql.Connection;
    import java.sql.DriverManager;
    import java.sql.ResultSet;
    import java.sql.SQLException;
    import java.sql.Statement;
    import java.util.Properties;
    
    import org.postgresql.PGConnection;
    import org.postgresql.copy.CopyIn;
    ```

=== "C#"

    ```csharp
    using Npgsql;
    using NpgsqlTypes;
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
    use std::io::Write;
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

## Creating the Table

Each program creates the table that receives the rows. The table is
`TEMPORARY`, so only the connection that creates it can see it, and
PostgreSQL drops it when the connection closes; the example can therefore
run any number of times without leaving anything behind. The following tabs
show how each program creates the table:

=== "Python"

    ```python
    def create_table(conn: psycopg.Connection) -> None:
        """Creates a temporary table, which only this session can see and
        which PostgreSQL drops when the session ends."""
        conn.execute(
            "CREATE TEMPORARY TABLE items ("
            "id int PRIMARY KEY, name text NOT NULL)"
        )
    ```

=== "TypeScript"

    ```typescript
    // Creates a temporary table, which only this session can see and which
    // PostgreSQL drops when the session ends.
    async function createTable(client: pg.Client): Promise<void> {
      await client.query(
        "CREATE TEMPORARY TABLE items (id int PRIMARY KEY, name text NOT NULL)",
      );
    }
    ```

=== "Java"

    ```java
    /**
     * Creates a temporary table, which only this session can see and
     * which PostgreSQL drops when the session ends.
     */
    static void createTable(Connection conn) throws SQLException {
        try (Statement stmt = conn.createStatement()) {
            stmt.execute("CREATE TEMPORARY TABLE items ("
                    + "id int PRIMARY KEY, name text NOT NULL)");
        }
    }
    ```

=== "C#"

    ```csharp
    // Creates a temporary table, which only this session can see and which
    // PostgreSQL drops when the session ends.
    static async Task CreateTableAsync(NpgsqlConnection conn)
    {
        await using var cmd = new NpgsqlCommand(
            "CREATE TEMPORARY TABLE items (id int PRIMARY KEY, name text NOT NULL)",
            conn);
        await cmd.ExecuteNonQueryAsync();
    }
    ```

=== "Go"

    ```go
    // createTable creates a temporary table, which only this session can see
    // and which PostgreSQL drops when the session ends.
    func createTable(ctx context.Context, conn *pgx.Conn) error {
    	_, err := conn.Exec(ctx,
    		"CREATE TEMPORARY TABLE items (id int PRIMARY KEY, name text NOT NULL)")
    	if err != nil {
    		return fmt.Errorf("create table failed: %w", err)
    	}
    	return nil
    }
    
    ```

=== "Rust"

    ```rust
    /// Creates a temporary table, which only this session can see and which
    /// PostgreSQL drops when the session ends.
    fn create_table(client: &mut Client) -> Result<(), postgres::Error> {
        client.batch_execute(
            "CREATE TEMPORARY TABLE items (id int PRIMARY KEY, name text NOT NULL)",
        )
    }
    ```

=== "Ruby"

    ```ruby
    # Creates a temporary table, which only this session can see and which
    # PostgreSQL drops when the session ends.
    def create_table(conn)
      conn.exec("CREATE TEMPORARY TABLE items (id int PRIMARY KEY, name text NOT NULL)")
    end
    ```

=== "C"

    ```c
    /*
     * Create a temporary table, which only this session can see and which
     * PostgreSQL drops when the session ends. Return true on success.
     */
    static bool
    create_table(PGconn *conn)
    {
        PGresult *res = PQexec(conn,
                               "CREATE TEMPORARY TABLE items "
                               "(id int PRIMARY KEY, name text NOT NULL)");
        bool ok = PQresultStatus(res) == PGRES_COMMAND_OK;
    
        PQclear(res);
        return ok;
    }
    ```

## Generating the Rows

Each program produces its rows lazily, one at a time, through a generator,
an iterator, or a function that the loop calls for each id, so the program
never holds all of the rows in memory. A real application would read the
rows from a file, another database, or a network service in the same way.

The Python, Go, and C# drivers convert each row from native values to the
`COPY` format themselves; psycopg writes the text format, and pgx and
Npgsql write the binary format, so these programs need no escaping. The
other drivers send the text format as it is written, so the TypeScript,
Java, Rust, Ruby, and C programs build each line themselves. In the
`COPY` text format, a tab separates the columns, a newline ends the row,
and a backslash begins an escape sequence. A value that contains any of
those characters, or a carriage return, must therefore have each of them
replaced by `\\`, `\t`, `\n`, or `\r`, and each program does so with an
`escapeText()` or `escape_text()` function. The generated names contain
none of these characters, but the function keeps the program correct for
data that does. The following tabs show how each program generates the
rows:

=== "Python"

    ```python
    def generate_rows(count: int):
        """Yields one (id, name) tuple for each row to load. A generator
        produces the rows one at a time, so the program never needs to hold
        them all in memory."""
        for item_id in range(1, count + 1):
            yield (item_id, f"item {item_id}")
    ```

=== "TypeScript"

    ```typescript
    // Escapes a value for the COPY text format, in which a backslash, a tab,
    // a newline, and a carriage return all have a special meaning.
    function escapeText(value: string): string {
      return value
        .replaceAll("\\", "\\\\")
        .replaceAll("\t", "\\t")
        .replaceAll("\n", "\\n")
        .replaceAll("\r", "\\r");
    }
    
    // Yields one line of COPY text for each row to load: the columns are
    // separated by tabs, and each row ends with a newline. A generator
    // produces the rows one at a time, so the program never holds them all.
    function* generateRows(count: number): Generator<string> {
      for (let id = 1; id <= count; id++) {
        yield `${id}\t${escapeText(`item ${id}`)}\n`;
      }
    }
    ```

=== "Java"

    ```java
    /**
     * Escapes a value for the COPY text format, in which a backslash, a
     * tab, a newline, and a carriage return all have a special meaning.
     */
    static String escapeText(String value) {
        return value
                .replace("\\", "\\\\")
                .replace("\t", "\\t")
                .replace("\n", "\\n")
                .replace("\r", "\\r");
    }
    
    /**
     * Formats the row with the given id as one line of COPY text: the
     * columns are separated by a tab, and the row ends with a newline.
     */
    static byte[] formatRow(int id) {
        String line = id + "\t" + escapeText("item " + id) + "\n";
        return line.getBytes(StandardCharsets.UTF_8);
    }
    ```

=== "C#"

    ```csharp
    // Returns the rows to load, as (id, name) pairs. The iterator produces
    // the rows one at a time, so the program never holds them all.
    static IEnumerable<(int Id, string Name)> GenerateRows(int count)
    {
        for (var id = 1; id <= count; id++)
        {
            yield return (id, $"item {id}");
        }
    }
    ```

=== "Go"

    ```go
    // generateRows returns a source that pgx asks for one row at a time, so
    // the program never builds the whole list of rows. Each row holds the
    // values for the id and name columns.
    func generateRows(count int) pgx.CopyFromSource {
    	return pgx.CopyFromSlice(count, func(i int) ([]any, error) {
    		id := i + 1
    		return []any{id, fmt.Sprintf("item %d", id)}, nil
    	})
    }
    
    ```

=== "Rust"

    ```rust
    /// Escapes a value for the COPY text format, in which a backslash, a tab,
    /// a newline, and a carriage return all have a special meaning.
    fn escape_text(value: &str) -> String {
        value
            .replace('\\', "\\\\")
            .replace('\t', "\\t")
            .replace('\n', "\\n")
            .replace('\r', "\\r")
    }
    
    /// Returns an iterator over the rows to load, each as one line of COPY
    /// text: the columns are separated by a tab, and the row ends with a
    /// newline. The iterator produces the rows one at a time, so the program
    /// never holds them all.
    fn generate_rows(count: i32) -> impl Iterator<Item = String> {
        (1..=count).map(|id| format!("{id}\t{}\n", escape_text(&format!("item {id}"))))
    }
    ```

=== "Ruby"

    ```ruby
    # Escapes a value for the COPY text format, in which a backslash, a tab,
    # a newline, and a carriage return all have a special meaning.
    def escape_text(value)
      value.gsub("\\", "\\\\\\\\")
           .gsub("\t", "\\t")
           .gsub("\n", "\\n")
           .gsub("\r", "\\r")
    end
    
    # Returns an enumerator that yields one line of COPY text for each row to
    # load: the columns are separated by tabs, and each row ends with a
    # newline. The enumerator produces the rows one at a time, so the program
    # never holds them all.
    def generate_rows(count)
      Enumerator.new do |rows|
        (1..count).each do |id|
          rows << "#{id}\t#{escape_text("item #{id}")}\n"
        end
      end
    end
    ```

=== "C"

    ```c
    /*
     * Copy a value into out in the COPY text format, in which a backslash, a
     * tab, a newline, and a carriage return all have a special meaning. The
     * caller must provide at least twice the length of the value, plus one.
     */
    static void
    escape_text(const char *value, char *out)
    {
        for (; *value != '\0'; value++)
        {
            switch (*value)
            {
                case '\\': *out++ = '\\'; *out++ = '\\'; break;
                case '\t': *out++ = '\\'; *out++ = 't'; break;
                case '\n': *out++ = '\\'; *out++ = 'n'; break;
                case '\r': *out++ = '\\'; *out++ = 'r'; break;
                default:   *out++ = *value; break;
            }
        }
        *out = '\0';
    }
    
    /*
     * Format the row with the given id as one line of COPY text: the columns
     * are separated by a tab, and the row ends with a newline. Return the
     * length of the line.
     */
    static int
    format_row(int id, char *line, size_t size)
    {
        char name[32];
        char escaped[64];
    
        snprintf(name, sizeof(name), "item %d", id);
        escape_text(name, escaped);
        return snprintf(line, size, "%d\t%s\n", id, escaped);
    }
    ```

## Copying the Rows

Each program sends the rows with `COPY items (id, name) FROM STDIN`, which
tells the server to expect the data on the same connection. The program
writes the rows to the copy stream, and then ends the stream; the server
stores nothing until it receives the end of the stream, and discards
every row if an error occurs first. The final result reports the number of
rows that the server stored.

The details differ between drivers. The Python `with` block and the Ruby
`copy_data()` block end the copy when the block finishes, and the Ruby
method also raises an error if the server rejects the data. The pgx
`CopyFrom()` function pulls every row from the source and finishes the
copy itself. The TypeScript program uses `pipeline()` to connect a stream
of rows to the copy stream, which applies back-pressure when the server is
slower than the program. The Rust, Java, and C# programs finish the copy
explicitly with `finish()`, `endCopy()`, and `CompleteAsync()`; the Rust
and C# programs cancel the copy if they drop the writer without finishing,
and the Java program cancels an unfinished copy after an error so that the
connection remains usable. The C program ends the copy with
`PQputCopyEnd()`, and then reads the result with `PQgetResult()`. The
following tabs show how each program copies the rows:

=== "Python"

    ```python
    def copy_rows(conn: psycopg.Connection, rows) -> int:
        """Loads the rows with COPY ... FROM STDIN and returns how many rows
        the server stored."""
        with conn.cursor() as cur:
            # copy() streams data to the server, which is much faster than
            # sending one INSERT for each row. write_row() converts each tuple
            # to the COPY text format, escaping tabs, newlines, and
            # backslashes in the values for us.
            with cur.copy("COPY items (id, name) FROM STDIN") as copy:
                for row in rows:
                    copy.write_row(row)
    
            # The server reports the number of rows it stored once the copy
            # block has ended.
            return cur.rowcount
    ```

=== "TypeScript"

    ```typescript
    // Loads the rows with COPY ... FROM STDIN and returns how many rows the
    // server stored.
    async function copyRows(
      client: pg.Client,
      rows: Iterable<string>,
    ): Promise<number> {
      // copyFrom() builds a query that the client runs like any other, and
      // that behaves as a writable stream: the data goes to the server as it
      // is written, which is much faster than one INSERT for each row.
      const stream = client.query(
        copyFrom("COPY items (id, name) FROM STDIN"),
      );
    
      // pipeline() copies the rows into the stream, applies back-pressure if
      // the server is slow, and rejects if either side fails.
      await pipeline(Readable.from(rows), stream);
    
      // The stream reports the row count once the server has finished.
      return stream.rowCount;
    }
    ```

=== "Java"

    ```java
    /**
     * Loads rows with ids 1 to count using COPY ... FROM STDIN, and
     * returns how many rows the server stored.
     */
    static long copyRows(Connection conn, int count) throws SQLException {
        // The copy API belongs to the PostgreSQL driver rather than to
        // JDBC, so unwrap() reaches it from the standard Connection.
        PGConnection pgConn = conn.unwrap(PGConnection.class);
        CopyIn copy = pgConn.getCopyAPI().copyIn(
                "COPY items (id, name) FROM STDIN");
    
        try {
            // Send the rows one at a time. The driver buffers the data,
            // so this is much faster than one INSERT for each row, and
            // the program never holds more than one row.
            for (int id = 1; id <= count; id++) {
                byte[] line = formatRow(id);
                copy.writeToCopy(line, 0, line.length);
            }
    
            // endCopy() finishes the copy, and returns the row count.
            return copy.endCopy();
        } finally {
            // If an error left the copy unfinished, cancel it so that the
            // connection becomes usable again.
            if (copy.isActive()) {
                copy.cancelCopy();
            }
        }
    }
    ```

=== "C#"

    ```csharp
    // Loads the rows with COPY ... FROM STDIN and returns how many rows the
    // server stored.
    static async Task<ulong> CopyRowsAsync(
        NpgsqlConnection conn, IEnumerable<(int Id, string Name)> rows)
    {
        // BeginBinaryImport uses the binary COPY format, which sends each
        // value in its native form, so there are no tabs, newlines, or
        // backslashes to escape. COPY is much faster than one INSERT for each
        // row. Disposing of the importer without calling CompleteAsync
        // cancels the copy.
        await using var writer = await conn.BeginBinaryImportAsync(
            "COPY items (id, name) FROM STDIN (FORMAT BINARY)");
    
        foreach (var (id, name) in rows)
        {
            await writer.StartRowAsync();
            await writer.WriteAsync(id, NpgsqlDbType.Integer);
            await writer.WriteAsync(name, NpgsqlDbType.Text);
        }
    
        // CompleteAsync finishes the copy, and returns the row count.
        return await writer.CompleteAsync();
    }
    ```

=== "Go"

    ```go
    // copyRows loads the rows with COPY ... FROM STDIN and returns how many
    // rows the server stored.
    func copyRows(ctx context.Context, conn *pgx.Conn, rows pgx.CopyFromSource) (int64, error) {
    	// CopyFrom uses the binary COPY format, which sends each value in its
    	// native form, so there are no tabs, newlines, or backslashes to
    	// escape. It is much faster than one INSERT for each row.
    	copied, err := conn.CopyFrom(ctx,
    		pgx.Identifier{"items"},
    		[]string{"id", "name"},
    		rows,
    	)
    	if err != nil {
    		return 0, fmt.Errorf("copy failed: %w", err)
    	}
    	return copied, nil
    }
    
    ```

=== "Rust"

    ```rust
    /// Loads the rows with COPY ... FROM STDIN and returns how many rows the
    /// server stored.
    fn copy_rows(
        client: &mut Client,
        rows: impl Iterator<Item = String>,
    ) -> Result<u64, Box<dyn Error>> {
        // copy_in() returns a writer that streams data to the server, which
        // is much faster than one INSERT for each row. The writer buffers
        // the data, so writing one row at a time is efficient.
        let mut writer = client.copy_in("COPY items (id, name) FROM STDIN")?;
    
        for line in rows {
            writer.write_all(line.as_bytes())?;
        }
    
        // finish() ends the copy and returns the row count. Dropping the
        // writer without calling finish() would cancel the copy instead.
        Ok(writer.finish()?)
    }
    ```

=== "Ruby"

    ```ruby
    # Loads the rows with COPY ... FROM STDIN and returns how many rows the
    # server stored.
    def copy_rows(conn, rows)
      # copy_data() sends the COPY command, runs the block to supply the data,
      # and then ends the copy and checks the result, raising PG::Error if the
      # server rejected any of the data. COPY is much faster than one INSERT
      # for each row.
      result = conn.copy_data("COPY items (id, name) FROM STDIN") do
        rows.each { |line| conn.put_copy_data(line) }
      end
    
      # The result of the COPY command reports the number of rows stored.
      result.cmd_tuples
    end
    ```

=== "C"

    ```c
    /*
     * Load rows with ids 1 to count using COPY ... FROM STDIN, and store the
     * number of rows the server stored in *copied. Return true on success.
     */
    static bool
    copy_rows(PGconn *conn, int count, long long *copied)
    {
        PGresult *res = PQexec(conn, "COPY items (id, name) FROM STDIN");
        bool ok = PQresultStatus(res) == PGRES_COPY_IN;
    
        PQclear(res);
        if (!ok)
            return false;
    
        /*
         * Send the rows one at a time. libpq buffers the data and sends it
         * in large chunks, so this is much faster than one INSERT for each
         * row, and the program never holds more than one row.
         */
        for (int id = 1; id <= count; id++)
        {
            char line[128];
            int length = format_row(id, line, sizeof(line));
    
            if (PQputCopyData(conn, line, length) != 1)
                return false;
        }
    
        /*
         * A NULL error message ends the copy normally; a message would abort
         * it instead. The server's verdict arrives as the next result.
         */
        if (PQputCopyEnd(conn, NULL) != 1)
            return false;
    
        res = PQgetResult(conn);
        ok = PQresultStatus(res) == PGRES_COMMAND_OK;
        if (ok)
            *copied = strtoll(PQcmdTuples(res), NULL, 10);
        PQclear(res);
    
        /* Read until PQgetResult() returns NULL, leaving the connection idle. */
        while ((res = PQgetResult(conn)) != NULL)
            PQclear(res);
        return ok;
    }
    ```

## Checking the Result

Each program runs an ordinary query to confirm what the server stored. The
`sum()` aggregate returns a `bigint` for an `int` column, so the total fits
in a 64-bit integer; the TypeScript program receives both values as
strings, because node-postgres does not convert large integers to a
JavaScript number. The following tabs show how each program reads the
result:

=== "Python"

    ```python
    def summarise(conn: psycopg.Connection) -> tuple[int, int]:
        """Returns the number of rows in the table and the sum of their ids."""
        row = conn.execute("SELECT count(*), sum(id) FROM items").fetchone()
        return row[0], int(row[1])
    ```

=== "TypeScript"

    ```typescript
    // Returns the number of rows in the table and the sum of their ids.
    async function summarise(
      client: pg.Client,
    ): Promise<{ count: string; total: string }> {
      // count and sum of an int both return a bigint, which node-postgres
      // returns as strings because they may not fit in a JavaScript number.
      const result = await client.query<{ count: string; total: string }>(
        "SELECT count(*) AS count, sum(id) AS total FROM items",
      );
      return result.rows[0];
    }
    ```

=== "Java"

    ```java
    /**
     * Prints the number of rows in the table and the sum of their ids.
     */
    static void summarise(Connection conn) throws SQLException {
        try (Statement stmt = conn.createStatement();
             ResultSet rs = stmt.executeQuery(
                     "SELECT count(*), sum(id) FROM items")) {
            rs.next();
            System.out.println("Rows in table: " + rs.getLong(1));
            System.out.println("Sum of ids: " + rs.getLong(2));
        }
    }
    ```

=== "C#"

    ```csharp
    // Returns the number of rows in the table and the sum of their ids.
    static async Task<(long Count, long Total)> SummariseAsync(
        NpgsqlConnection conn)
    {
        await using var cmd = new NpgsqlCommand(
            "SELECT count(*), sum(id) FROM items", conn);
        await using var reader = await cmd.ExecuteReaderAsync();
        await reader.ReadAsync();
    
        // count returns a bigint, and sum of an int returns a bigint too;
        // both map to long.
        return (reader.GetInt64(0), reader.GetInt64(1));
    }
    ```

=== "Go"

    ```go
    // summarise returns the number of rows in the table and the sum of their
    // ids.
    func summarise(ctx context.Context, conn *pgx.Conn) (count, total int64, err error) {
    	// sum() of an int returns a bigint, which scans into an int64.
    	err = conn.QueryRow(ctx, "SELECT count(*), sum(id) FROM items").
    		Scan(&count, &total)
    	if err != nil {
    		return 0, 0, fmt.Errorf("query failed: %w", err)
    	}
    	return count, total, nil
    }
    
    ```

=== "Rust"

    ```rust
    /// Returns the number of rows in the table and the sum of their ids.
    fn summarise(client: &mut Client) -> Result<(i64, i64), postgres::Error> {
        let row = client.query_one("SELECT count(*), sum(id) FROM items", &[])?;
    
        // count returns a bigint, and sum of an int returns a bigint too;
        // both map to i64.
        Ok((row.get(0), row.get(1)))
    }
    ```

=== "Ruby"

    ```ruby
    # Returns the number of rows in the table and the sum of their ids.
    def summarise(conn)
      row = conn.exec("SELECT count(*), sum(id) FROM items").first
    
      # Results arrive as strings, so convert the values to Integers.
      [row["count"].to_i, row["sum"].to_i]
    end
    ```

=== "C"

    ```c
    /*
     * Store the number of rows in the table and the sum of their ids in
     * *count and *total, and return true on success.
     */
    static bool
    summarise(PGconn *conn, long long *count, long long *total)
    {
        PGresult *res = PQexec(conn, "SELECT count(*), sum(id) FROM items");
        bool ok = PQresultStatus(res) == PGRES_TUPLES_OK;
    
        /* Results arrive as text, so convert the values to numbers. */
        if (ok)
        {
            *count = strtoll(PQgetvalue(res, 0, 0), NULL, 10);
            *total = strtoll(PQgetvalue(res, 0, 1), NULL, 10);
        }
    
        /* PQclear() frees the result, and accepts NULL. */
        PQclear(res);
        return ok;
    }
    ```

## Handling Errors and Closing the Connection

The main part of each program calls the functions from the previous steps,
and prints the results. The program reports any connection or `COPY`
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
                create_table(conn)
                copied = copy_rows(conn, generate_rows(1000))
                print(f"Copied {copied} rows")
    
                count, total = summarise(conn)
                print(f"Rows in table: {count}")
                print(f"Sum of ids: {total}")
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
        await createTable(client);
    
        const copied = await copyRows(client, generateRows(1000));
        console.log(`Copied ${copied} rows`);
    
        const { count, total } = await summarise(client);
        console.log(`Rows in table: ${count}`);
        console.log(`Sum of ids: ${total}`);
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
            createTable(conn);
    
            long copied = copyRows(conn, 1000);
            System.out.println("Copied " + copied + " rows");
    
            summarise(conn);
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
    
        await CreateTableAsync(conn);
    
        var copied = await CopyRowsAsync(conn, GenerateRows(1000));
        Console.WriteLine($"Copied {copied} rows");
    
        var (count, total) = await SummariseAsync(conn);
        Console.WriteLine($"Rows in table: {count}");
        Console.WriteLine($"Sum of ids: {total}");
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
    // run connects, loads the rows, and prints the result, returning any
    // error to the caller.
    func run(ctx context.Context) error {
    	conn, err := connect(ctx)
    	if err != nil {
    		return err
    	}
    	// The deferred call closes the connection when run() returns, whether
    	// or not an error occurred.
    	defer conn.Close(ctx)
    
    	if err := createTable(ctx, conn); err != nil {
    		return err
    	}
    
    	copied, err := copyRows(ctx, conn, generateRows(1000))
    	if err != nil {
    		return err
    	}
    	fmt.Printf("Copied %d rows\n", copied)
    
    	count, total, err := summarise(ctx, conn)
    	if err != nil {
    		return err
    	}
    	fmt.Printf("Rows in table: %d\n", count)
    	fmt.Printf("Sum of ids: %d\n", total)
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
    /// Connects, loads the rows, and prints the result. The ? operator
    /// returns any error to the caller.
    fn run() -> Result<(), Box<dyn Error>> {
        let mut client = connect()?;
        create_table(&mut client)?;
    
        let copied = copy_rows(&mut client, generate_rows(1000))?;
        println!("Copied {copied} rows");
    
        let (count, total) = summarise(&mut client)?;
        println!("Rows in table: {count}");
        println!("Sum of ids: {total}");
    
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
      create_table(conn)
    
      copied = copy_rows(conn, generate_rows(1000))
      puts "Copied #{copied} rows"
    
      count, total = summarise(conn)
      puts "Rows in table: #{count}"
      puts "Sum of ids: #{total}"
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
        long long copied;
        long long count;
        long long total;
        PGconn *conn = connect_to_server();
    
        /* The || operator skips each step once a step has failed. */
        if (PQstatus(conn) != CONNECTION_OK ||
            !create_table(conn) ||
            !copy_rows(conn, 1000, &copied) ||
            !summarise(conn, &count, &total))
        {
            fprintf(stderr, "Database error: %s", PQerrorMessage(conn));
        }
        else
        {
            printf("Copied %lld rows\n", copied);
            printf("Rows in table: %lld\n", count);
            printf("Sum of ids: %lld\n", total);
            status = EXIT_SUCCESS;
        }
    
        /* Close the connection whether or not an error occurred. */
        PQfinish(conn);
        return status;
    }
    ```

## Running the Example

The complete project for each language is available in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/postgresql/bulk_copy).
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
    Loading rows in bulk with COPY, using psycopg 3.
    
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
    
    
    def create_table(conn: psycopg.Connection) -> None:
        """Creates a temporary table, which only this session can see and
        which PostgreSQL drops when the session ends."""
        conn.execute(
            "CREATE TEMPORARY TABLE items ("
            "id int PRIMARY KEY, name text NOT NULL)"
        )
    
    
    def generate_rows(count: int):
        """Yields one (id, name) tuple for each row to load. A generator
        produces the rows one at a time, so the program never needs to hold
        them all in memory."""
        for item_id in range(1, count + 1):
            yield (item_id, f"item {item_id}")
    
    
    def copy_rows(conn: psycopg.Connection, rows) -> int:
        """Loads the rows with COPY ... FROM STDIN and returns how many rows
        the server stored."""
        with conn.cursor() as cur:
            # copy() streams data to the server, which is much faster than
            # sending one INSERT for each row. write_row() converts each tuple
            # to the COPY text format, escaping tabs, newlines, and
            # backslashes in the values for us.
            with cur.copy("COPY items (id, name) FROM STDIN") as copy:
                for row in rows:
                    copy.write_row(row)
    
            # The server reports the number of rows it stored once the copy
            # block has ended.
            return cur.rowcount
    
    
    def summarise(conn: psycopg.Connection) -> tuple[int, int]:
        """Returns the number of rows in the table and the sum of their ids."""
        row = conn.execute("SELECT count(*), sum(id) FROM items").fetchone()
        return row[0], int(row[1])
    
    
    def main() -> int:
        try:
            # The with block closes the connection when it exits, whether or
            # not an error occurred.
            with connect() as conn:
                create_table(conn)
                copied = copy_rows(conn, generate_rows(1000))
                print(f"Copied {copied} rows")
    
                count, total = summarise(conn)
                print(f"Rows in table: {count}")
                print(f"Sum of ids: {total}")
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
     * Loading rows in bulk with COPY, using node-postgres and pg-copy-streams.
     *
     * Copyright (c) 2026, pgEdge, Inc.
     * This code is released under the PostgreSQL License.
     */
    
    import { Readable } from "node:stream";
    import { pipeline } from "node:stream/promises";
    
    import pg from "pg";
    import { from as copyFrom } from "pg-copy-streams";
    
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
    
    // Creates a temporary table, which only this session can see and which
    // PostgreSQL drops when the session ends.
    async function createTable(client: pg.Client): Promise<void> {
      await client.query(
        "CREATE TEMPORARY TABLE items (id int PRIMARY KEY, name text NOT NULL)",
      );
    }
    
    // Escapes a value for the COPY text format, in which a backslash, a tab,
    // a newline, and a carriage return all have a special meaning.
    function escapeText(value: string): string {
      return value
        .replaceAll("\\", "\\\\")
        .replaceAll("\t", "\\t")
        .replaceAll("\n", "\\n")
        .replaceAll("\r", "\\r");
    }
    
    // Yields one line of COPY text for each row to load: the columns are
    // separated by tabs, and each row ends with a newline. A generator
    // produces the rows one at a time, so the program never holds them all.
    function* generateRows(count: number): Generator<string> {
      for (let id = 1; id <= count; id++) {
        yield `${id}\t${escapeText(`item ${id}`)}\n`;
      }
    }
    
    // Loads the rows with COPY ... FROM STDIN and returns how many rows the
    // server stored.
    async function copyRows(
      client: pg.Client,
      rows: Iterable<string>,
    ): Promise<number> {
      // copyFrom() builds a query that the client runs like any other, and
      // that behaves as a writable stream: the data goes to the server as it
      // is written, which is much faster than one INSERT for each row.
      const stream = client.query(
        copyFrom("COPY items (id, name) FROM STDIN"),
      );
    
      // pipeline() copies the rows into the stream, applies back-pressure if
      // the server is slow, and rejects if either side fails.
      await pipeline(Readable.from(rows), stream);
    
      // The stream reports the row count once the server has finished.
      return stream.rowCount;
    }
    
    // Returns the number of rows in the table and the sum of their ids.
    async function summarise(
      client: pg.Client,
    ): Promise<{ count: string; total: string }> {
      // count and sum of an int both return a bigint, which node-postgres
      // returns as strings because they may not fit in a JavaScript number.
      const result = await client.query<{ count: string; total: string }>(
        "SELECT count(*) AS count, sum(id) AS total FROM items",
      );
      return result.rows[0];
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
        await createTable(client);
    
        const copied = await copyRows(client, generateRows(1000));
        console.log(`Copied ${copied} rows`);
    
        const { count, total } = await summarise(client);
        console.log(`Rows in table: ${count}`);
        console.log(`Sum of ids: ${total}`);
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
     * Loading rows in bulk with COPY, using JDBC and the PostgreSQL JDBC
     * driver (pgJDBC).
     *
     * Copyright (c) 2026, pgEdge, Inc.
     * This code is released under the PostgreSQL License.
     */
    
    import java.nio.charset.StandardCharsets;
    import java.sql.Connection;
    import java.sql.DriverManager;
    import java.sql.ResultSet;
    import java.sql.SQLException;
    import java.sql.Statement;
    import java.util.Properties;
    
    import org.postgresql.PGConnection;
    import org.postgresql.copy.CopyIn;
    
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
         * Creates a temporary table, which only this session can see and
         * which PostgreSQL drops when the session ends.
         */
        static void createTable(Connection conn) throws SQLException {
            try (Statement stmt = conn.createStatement()) {
                stmt.execute("CREATE TEMPORARY TABLE items ("
                        + "id int PRIMARY KEY, name text NOT NULL)");
            }
        }
    
        /**
         * Escapes a value for the COPY text format, in which a backslash, a
         * tab, a newline, and a carriage return all have a special meaning.
         */
        static String escapeText(String value) {
            return value
                    .replace("\\", "\\\\")
                    .replace("\t", "\\t")
                    .replace("\n", "\\n")
                    .replace("\r", "\\r");
        }
    
        /**
         * Formats the row with the given id as one line of COPY text: the
         * columns are separated by a tab, and the row ends with a newline.
         */
        static byte[] formatRow(int id) {
            String line = id + "\t" + escapeText("item " + id) + "\n";
            return line.getBytes(StandardCharsets.UTF_8);
        }
    
        /**
         * Loads rows with ids 1 to count using COPY ... FROM STDIN, and
         * returns how many rows the server stored.
         */
        static long copyRows(Connection conn, int count) throws SQLException {
            // The copy API belongs to the PostgreSQL driver rather than to
            // JDBC, so unwrap() reaches it from the standard Connection.
            PGConnection pgConn = conn.unwrap(PGConnection.class);
            CopyIn copy = pgConn.getCopyAPI().copyIn(
                    "COPY items (id, name) FROM STDIN");
    
            try {
                // Send the rows one at a time. The driver buffers the data,
                // so this is much faster than one INSERT for each row, and
                // the program never holds more than one row.
                for (int id = 1; id <= count; id++) {
                    byte[] line = formatRow(id);
                    copy.writeToCopy(line, 0, line.length);
                }
    
                // endCopy() finishes the copy, and returns the row count.
                return copy.endCopy();
            } finally {
                // If an error left the copy unfinished, cancel it so that the
                // connection becomes usable again.
                if (copy.isActive()) {
                    copy.cancelCopy();
                }
            }
        }
    
        /**
         * Prints the number of rows in the table and the sum of their ids.
         */
        static void summarise(Connection conn) throws SQLException {
            try (Statement stmt = conn.createStatement();
                 ResultSet rs = stmt.executeQuery(
                         "SELECT count(*), sum(id) FROM items")) {
                rs.next();
                System.out.println("Rows in table: " + rs.getLong(1));
                System.out.println("Sum of ids: " + rs.getLong(2));
            }
        }
    
        public static void main(String[] args) {
            // try-with-resources closes the connection when the block exits,
            // whether or not an error occurred.
            try (Connection conn = connect()) {
                createTable(conn);
    
                long copied = copyRows(conn, 1000);
                System.out.println("Copied " + copied + " rows");
    
                summarise(conn);
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
     * Loading rows in bulk with COPY, using Npgsql.
     *
     * Copyright (c) 2026, pgEdge, Inc.
     * This code is released under the PostgreSQL License.
     */
    
    using Npgsql;
    using NpgsqlTypes;
    
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
    
    // Creates a temporary table, which only this session can see and which
    // PostgreSQL drops when the session ends.
    static async Task CreateTableAsync(NpgsqlConnection conn)
    {
        await using var cmd = new NpgsqlCommand(
            "CREATE TEMPORARY TABLE items (id int PRIMARY KEY, name text NOT NULL)",
            conn);
        await cmd.ExecuteNonQueryAsync();
    }
    
    // Returns the rows to load, as (id, name) pairs. The iterator produces
    // the rows one at a time, so the program never holds them all.
    static IEnumerable<(int Id, string Name)> GenerateRows(int count)
    {
        for (var id = 1; id <= count; id++)
        {
            yield return (id, $"item {id}");
        }
    }
    
    // Loads the rows with COPY ... FROM STDIN and returns how many rows the
    // server stored.
    static async Task<ulong> CopyRowsAsync(
        NpgsqlConnection conn, IEnumerable<(int Id, string Name)> rows)
    {
        // BeginBinaryImport uses the binary COPY format, which sends each
        // value in its native form, so there are no tabs, newlines, or
        // backslashes to escape. COPY is much faster than one INSERT for each
        // row. Disposing of the importer without calling CompleteAsync
        // cancels the copy.
        await using var writer = await conn.BeginBinaryImportAsync(
            "COPY items (id, name) FROM STDIN (FORMAT BINARY)");
    
        foreach (var (id, name) in rows)
        {
            await writer.StartRowAsync();
            await writer.WriteAsync(id, NpgsqlDbType.Integer);
            await writer.WriteAsync(name, NpgsqlDbType.Text);
        }
    
        // CompleteAsync finishes the copy, and returns the row count.
        return await writer.CompleteAsync();
    }
    
    // Returns the number of rows in the table and the sum of their ids.
    static async Task<(long Count, long Total)> SummariseAsync(
        NpgsqlConnection conn)
    {
        await using var cmd = new NpgsqlCommand(
            "SELECT count(*), sum(id) FROM items", conn);
        await using var reader = await cmd.ExecuteReaderAsync();
        await reader.ReadAsync();
    
        // count returns a bigint, and sum of an int returns a bigint too;
        // both map to long.
        return (reader.GetInt64(0), reader.GetInt64(1));
    }
    
    try
    {
        // await using disposes of the data source, and returns the connection
        // to the pool, when the block exits, whether or not an error occurred.
        await using var dataSource = CreateDataSource();
        await using var conn = await dataSource.OpenConnectionAsync();
    
        await CreateTableAsync(conn);
    
        var copied = await CopyRowsAsync(conn, GenerateRows(1000));
        Console.WriteLine($"Copied {copied} rows");
    
        var (count, total) = await SummariseAsync(conn);
        Console.WriteLine($"Rows in table: {count}");
        Console.WriteLine($"Sum of ids: {total}");
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
    // Loading rows in bulk with COPY, using pgx.
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
    
    
    // createTable creates a temporary table, which only this session can see
    // and which PostgreSQL drops when the session ends.
    func createTable(ctx context.Context, conn *pgx.Conn) error {
    	_, err := conn.Exec(ctx,
    		"CREATE TEMPORARY TABLE items (id int PRIMARY KEY, name text NOT NULL)")
    	if err != nil {
    		return fmt.Errorf("create table failed: %w", err)
    	}
    	return nil
    }
    
    
    // generateRows returns a source that pgx asks for one row at a time, so
    // the program never builds the whole list of rows. Each row holds the
    // values for the id and name columns.
    func generateRows(count int) pgx.CopyFromSource {
    	return pgx.CopyFromSlice(count, func(i int) ([]any, error) {
    		id := i + 1
    		return []any{id, fmt.Sprintf("item %d", id)}, nil
    	})
    }
    
    
    // copyRows loads the rows with COPY ... FROM STDIN and returns how many
    // rows the server stored.
    func copyRows(ctx context.Context, conn *pgx.Conn, rows pgx.CopyFromSource) (int64, error) {
    	// CopyFrom uses the binary COPY format, which sends each value in its
    	// native form, so there are no tabs, newlines, or backslashes to
    	// escape. It is much faster than one INSERT for each row.
    	copied, err := conn.CopyFrom(ctx,
    		pgx.Identifier{"items"},
    		[]string{"id", "name"},
    		rows,
    	)
    	if err != nil {
    		return 0, fmt.Errorf("copy failed: %w", err)
    	}
    	return copied, nil
    }
    
    
    // summarise returns the number of rows in the table and the sum of their
    // ids.
    func summarise(ctx context.Context, conn *pgx.Conn) (count, total int64, err error) {
    	// sum() of an int returns a bigint, which scans into an int64.
    	err = conn.QueryRow(ctx, "SELECT count(*), sum(id) FROM items").
    		Scan(&count, &total)
    	if err != nil {
    		return 0, 0, fmt.Errorf("query failed: %w", err)
    	}
    	return count, total, nil
    }
    
    
    // run connects, loads the rows, and prints the result, returning any
    // error to the caller.
    func run(ctx context.Context) error {
    	conn, err := connect(ctx)
    	if err != nil {
    		return err
    	}
    	// The deferred call closes the connection when run() returns, whether
    	// or not an error occurred.
    	defer conn.Close(ctx)
    
    	if err := createTable(ctx, conn); err != nil {
    		return err
    	}
    
    	copied, err := copyRows(ctx, conn, generateRows(1000))
    	if err != nil {
    		return err
    	}
    	fmt.Printf("Copied %d rows\n", copied)
    
    	count, total, err := summarise(ctx, conn)
    	if err != nil {
    		return err
    	}
    	fmt.Printf("Rows in table: %d\n", count)
    	fmt.Printf("Sum of ids: %d\n", total)
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
    // Loading rows in bulk with COPY, using the postgres crate.
    //
    // Copyright (c) 2026, pgEdge, Inc.
    // This code is released under the PostgreSQL License.
    
    use std::env;
    use std::error::Error;
    use std::io::Write;
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
    
    /// Creates a temporary table, which only this session can see and which
    /// PostgreSQL drops when the session ends.
    fn create_table(client: &mut Client) -> Result<(), postgres::Error> {
        client.batch_execute(
            "CREATE TEMPORARY TABLE items (id int PRIMARY KEY, name text NOT NULL)",
        )
    }
    
    /// Escapes a value for the COPY text format, in which a backslash, a tab,
    /// a newline, and a carriage return all have a special meaning.
    fn escape_text(value: &str) -> String {
        value
            .replace('\\', "\\\\")
            .replace('\t', "\\t")
            .replace('\n', "\\n")
            .replace('\r', "\\r")
    }
    
    /// Returns an iterator over the rows to load, each as one line of COPY
    /// text: the columns are separated by a tab, and the row ends with a
    /// newline. The iterator produces the rows one at a time, so the program
    /// never holds them all.
    fn generate_rows(count: i32) -> impl Iterator<Item = String> {
        (1..=count).map(|id| format!("{id}\t{}\n", escape_text(&format!("item {id}"))))
    }
    
    /// Loads the rows with COPY ... FROM STDIN and returns how many rows the
    /// server stored.
    fn copy_rows(
        client: &mut Client,
        rows: impl Iterator<Item = String>,
    ) -> Result<u64, Box<dyn Error>> {
        // copy_in() returns a writer that streams data to the server, which
        // is much faster than one INSERT for each row. The writer buffers
        // the data, so writing one row at a time is efficient.
        let mut writer = client.copy_in("COPY items (id, name) FROM STDIN")?;
    
        for line in rows {
            writer.write_all(line.as_bytes())?;
        }
    
        // finish() ends the copy and returns the row count. Dropping the
        // writer without calling finish() would cancel the copy instead.
        Ok(writer.finish()?)
    }
    
    /// Returns the number of rows in the table and the sum of their ids.
    fn summarise(client: &mut Client) -> Result<(i64, i64), postgres::Error> {
        let row = client.query_one("SELECT count(*), sum(id) FROM items", &[])?;
    
        // count returns a bigint, and sum of an int returns a bigint too;
        // both map to i64.
        Ok((row.get(0), row.get(1)))
    }
    
    /// Connects, loads the rows, and prints the result. The ? operator
    /// returns any error to the caller.
    fn run() -> Result<(), Box<dyn Error>> {
        let mut client = connect()?;
        create_table(&mut client)?;
    
        let copied = copy_rows(&mut client, generate_rows(1000))?;
        println!("Copied {copied} rows");
    
        let (count, total) = summarise(&mut client)?;
        println!("Rows in table: {count}");
        println!("Sum of ids: {total}");
    
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
    # Loading rows in bulk with COPY, using the pg gem.
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
    
    # Creates a temporary table, which only this session can see and which
    # PostgreSQL drops when the session ends.
    def create_table(conn)
      conn.exec("CREATE TEMPORARY TABLE items (id int PRIMARY KEY, name text NOT NULL)")
    end
    
    # Escapes a value for the COPY text format, in which a backslash, a tab,
    # a newline, and a carriage return all have a special meaning.
    def escape_text(value)
      value.gsub("\\", "\\\\\\\\")
           .gsub("\t", "\\t")
           .gsub("\n", "\\n")
           .gsub("\r", "\\r")
    end
    
    # Returns an enumerator that yields one line of COPY text for each row to
    # load: the columns are separated by tabs, and each row ends with a
    # newline. The enumerator produces the rows one at a time, so the program
    # never holds them all.
    def generate_rows(count)
      Enumerator.new do |rows|
        (1..count).each do |id|
          rows << "#{id}\t#{escape_text("item #{id}")}\n"
        end
      end
    end
    
    # Loads the rows with COPY ... FROM STDIN and returns how many rows the
    # server stored.
    def copy_rows(conn, rows)
      # copy_data() sends the COPY command, runs the block to supply the data,
      # and then ends the copy and checks the result, raising PG::Error if the
      # server rejected any of the data. COPY is much faster than one INSERT
      # for each row.
      result = conn.copy_data("COPY items (id, name) FROM STDIN") do
        rows.each { |line| conn.put_copy_data(line) }
      end
    
      # The result of the COPY command reports the number of rows stored.
      result.cmd_tuples
    end
    
    # Returns the number of rows in the table and the sum of their ids.
    def summarise(conn)
      row = conn.exec("SELECT count(*), sum(id) FROM items").first
    
      # Results arrive as strings, so convert the values to Integers.
      [row["count"].to_i, row["sum"].to_i]
    end
    
    begin
      conn = connect
      create_table(conn)
    
      copied = copy_rows(conn, generate_rows(1000))
      puts "Copied #{copied} rows"
    
      count, total = summarise(conn)
      puts "Rows in table: #{count}"
      puts "Sum of ids: #{total}"
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
     * Loading rows in bulk with COPY, using libpq.
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
     * Create a temporary table, which only this session can see and which
     * PostgreSQL drops when the session ends. Return true on success.
     */
    static bool
    create_table(PGconn *conn)
    {
        PGresult *res = PQexec(conn,
                               "CREATE TEMPORARY TABLE items "
                               "(id int PRIMARY KEY, name text NOT NULL)");
        bool ok = PQresultStatus(res) == PGRES_COMMAND_OK;
    
        PQclear(res);
        return ok;
    }
    
    /*
     * Copy a value into out in the COPY text format, in which a backslash, a
     * tab, a newline, and a carriage return all have a special meaning. The
     * caller must provide at least twice the length of the value, plus one.
     */
    static void
    escape_text(const char *value, char *out)
    {
        for (; *value != '\0'; value++)
        {
            switch (*value)
            {
                case '\\': *out++ = '\\'; *out++ = '\\'; break;
                case '\t': *out++ = '\\'; *out++ = 't'; break;
                case '\n': *out++ = '\\'; *out++ = 'n'; break;
                case '\r': *out++ = '\\'; *out++ = 'r'; break;
                default:   *out++ = *value; break;
            }
        }
        *out = '\0';
    }
    
    /*
     * Format the row with the given id as one line of COPY text: the columns
     * are separated by a tab, and the row ends with a newline. Return the
     * length of the line.
     */
    static int
    format_row(int id, char *line, size_t size)
    {
        char name[32];
        char escaped[64];
    
        snprintf(name, sizeof(name), "item %d", id);
        escape_text(name, escaped);
        return snprintf(line, size, "%d\t%s\n", id, escaped);
    }
    
    /*
     * Load rows with ids 1 to count using COPY ... FROM STDIN, and store the
     * number of rows the server stored in *copied. Return true on success.
     */
    static bool
    copy_rows(PGconn *conn, int count, long long *copied)
    {
        PGresult *res = PQexec(conn, "COPY items (id, name) FROM STDIN");
        bool ok = PQresultStatus(res) == PGRES_COPY_IN;
    
        PQclear(res);
        if (!ok)
            return false;
    
        /*
         * Send the rows one at a time. libpq buffers the data and sends it
         * in large chunks, so this is much faster than one INSERT for each
         * row, and the program never holds more than one row.
         */
        for (int id = 1; id <= count; id++)
        {
            char line[128];
            int length = format_row(id, line, sizeof(line));
    
            if (PQputCopyData(conn, line, length) != 1)
                return false;
        }
    
        /*
         * A NULL error message ends the copy normally; a message would abort
         * it instead. The server's verdict arrives as the next result.
         */
        if (PQputCopyEnd(conn, NULL) != 1)
            return false;
    
        res = PQgetResult(conn);
        ok = PQresultStatus(res) == PGRES_COMMAND_OK;
        if (ok)
            *copied = strtoll(PQcmdTuples(res), NULL, 10);
        PQclear(res);
    
        /* Read until PQgetResult() returns NULL, leaving the connection idle. */
        while ((res = PQgetResult(conn)) != NULL)
            PQclear(res);
        return ok;
    }
    
    /*
     * Store the number of rows in the table and the sum of their ids in
     * *count and *total, and return true on success.
     */
    static bool
    summarise(PGconn *conn, long long *count, long long *total)
    {
        PGresult *res = PQexec(conn, "SELECT count(*), sum(id) FROM items");
        bool ok = PQresultStatus(res) == PGRES_TUPLES_OK;
    
        /* Results arrive as text, so convert the values to numbers. */
        if (ok)
        {
            *count = strtoll(PQgetvalue(res, 0, 0), NULL, 10);
            *total = strtoll(PQgetvalue(res, 0, 1), NULL, 10);
        }
    
        /* PQclear() frees the result, and accepts NULL. */
        PQclear(res);
        return ok;
    }
    
    int
    main(void)
    {
        int status = EXIT_FAILURE;
        long long copied;
        long long count;
        long long total;
        PGconn *conn = connect_to_server();
    
        /* The || operator skips each step once a step has failed. */
        if (PQstatus(conn) != CONNECTION_OK ||
            !create_table(conn) ||
            !copy_rows(conn, 1000, &copied) ||
            !summarise(conn, &count, &total))
        {
            fprintf(stderr, "Database error: %s", PQerrorMessage(conn));
        }
        else
        {
            printf("Copied %lld rows\n", copied);
            printf("Rows in table: %lld\n", count);
            printf("Sum of ids: %lld\n", total);
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

- The PostgreSQL documentation for the
  [COPY command](https://www.postgresql.org/docs/current/sql-copy.html)
  describes the text, CSV, and binary formats, and every option.
- The PostgreSQL documentation for
  [COPY operations in libpq](https://www.postgresql.org/docs/current/libpq-copy.html)
  describes the protocol that every driver uses.
- The [Contributing a Recipe](../contributing.md) page explains how to add
  a recipe or a language to the cookbook.
