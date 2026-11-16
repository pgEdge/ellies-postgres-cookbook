# Passing a List of Values

This recipe demonstrates how an application passes a list of values to a
PostgreSQL query as a single parameter. The example finds which of four
names exist as data types in the `pg_catalog.pg_type` system catalog, by
sending all four names in one array and matching them with `= ANY(...)`.
Each step shows the code in every supported language; selecting a language
tab switches every tab on the site to that language.

The list contains `int4`, `text`, `bool`, and `no_such_type`. The first
three names exist on every PostgreSQL server and the last does not, so the
output is easy to verify:

```text
Found 3 of 4 types: bool, int4, text
```

## Choosing an Array over an IN List

A query that matches a column against a list of values often appears as
`WHERE name IN ('a', 'b', 'c')`. An application that builds that text has
to add one placeholder per value, or worse, paste the values into the SQL
string. Both approaches cause trouble: the SQL text changes with the length
of the list, so the server cannot reuse a prepared statement, and a value
pasted into the text invites SQL injection.

The `= ANY($1)` form takes the whole list as one array parameter instead.
The SQL text never changes, whatever the length of the list, and the
driver sends the values separately from the SQL, so the server never
interprets a value as SQL. The same form also works for an empty list,
which matches no rows, whereas an empty `IN ()` list is a syntax error.

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
      "name": "array-parameters",
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
    import java.sql.Array;
    import java.sql.Connection;
    import java.sql.DriverManager;
    import java.sql.PreparedStatement;
    import java.sql.ResultSet;
    import java.sql.SQLException;
    import java.util.ArrayList;
    import java.util.List;
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
    	"strings"
    
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
    #include <string.h>
    
    #include <libpq-fe.h>
    ```

## Configuring the Connection

The examples read their connection settings from the same five
environment variables as the first recipe: `PGHOST`, `PGPORT`,
`PGDATABASE`, `PGUSER`, and `PGPASSWORD`. Like libpq, each example treats
an empty variable as unset, and uses the default instead. The following
tabs show how each program assembles the connection settings:

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

## Running the Query

Each program sends the list as the only parameter of the query, and then
reads the matching names from the first column of each row. The way that
each driver turns a list into an array parameter differs:

- Python, TypeScript, C#, Go, and Rust convert a native list, array, or
  slice into a PostgreSQL array automatically.
- Java builds an array with `createArrayOf()` and passes it with
  `setArray()`, and then calls `free()` on the array when the query is
  done.
- Ruby encodes the list as the text form of an array with
  `PG::TextEncoder::Array`, which quotes each element as needed.
- C has no array type, so the program builds the text form of an array,
  such as `{"int4","text"}`, and sends it as an ordinary text parameter. The
  `$1::text[]` cast in the query tells the server to read the text as an
  array.

The C program must quote the text form itself, because the server parses
that text as an array literal. Each element is wrapped in double quotes,
and a backslash or double quote inside an element is escaped with a
backslash; without this, an element containing a comma or a brace would
split into several elements or end the array early. This quoting only
protects the array syntax: the text is still a parameter, so the server
never executes it as SQL.

The following tabs show how each program runs the query and reads the
result:

=== "Python"

    ```python
    def find_types(conn: psycopg.Connection, names: list[str]) -> list[str]:
        """Returns the names from the list that exist as data types."""
        # The whole list travels as one array parameter, so the SQL text is
        # the same however many values the list holds. psycopg converts a
        # Python list into a PostgreSQL array.
        rows = conn.execute(
            "SELECT typname FROM pg_catalog.pg_type "
            "WHERE typname = ANY(%s) ORDER BY typname",
            (names,),
        ).fetchall()
        return [row[0] for row in rows]
    ```

=== "TypeScript"

    ```typescript
    // Returns the names from the list that exist as data types.
    async function findTypes(client: pg.Client, names: string[]): Promise<string[]> {
      // The whole list travels as one array parameter, so the SQL text is the
      // same however many values the list holds. node-postgres converts a
      // JavaScript array into a PostgreSQL array.
      const result = await client.query<{ typname: string }>(
        "SELECT typname FROM pg_catalog.pg_type " +
          "WHERE typname = ANY($1) ORDER BY typname",
        [names],
      );
      return result.rows.map((row) => row.typname);
    }
    ```

=== "Java"

    ```java
    /** Returns the names from the list that exist as data types. */
    static List<String> findTypes(Connection conn, String[] names)
            throws SQLException {
        // The whole list travels as one array parameter, so the SQL text
        // is the same however many values the list holds.
        String sql = "SELECT typname FROM pg_catalog.pg_type "
                + "WHERE typname = ANY(?) ORDER BY typname";
    
        // createArrayOf builds a JDBC array of the named element type,
        // which setArray sends as a PostgreSQL array. Array is not
        // AutoCloseable, so the finally block calls free() to release it.
        Array array = conn.createArrayOf("text", names);
        try (PreparedStatement stmt = conn.prepareStatement(sql)) {
            stmt.setArray(1, array);
    
            try (ResultSet rs = stmt.executeQuery()) {
                List<String> found = new ArrayList<>();
                while (rs.next()) {
                    found.add(rs.getString(1));
                }
                return found;
            }
        } finally {
            array.free();
        }
    }
    ```

=== "C#"

    ```csharp
    // Returns the names from the list that exist as data types.
    static async Task<List<string>> FindTypesAsync(
        NpgsqlConnection conn, string[] names)
    {
        // The whole list travels as one array parameter, so the SQL text is
        // the same however many values the list holds. Npgsql converts a .NET
        // array into a PostgreSQL array.
        await using var cmd = new NpgsqlCommand(
            "SELECT typname FROM pg_catalog.pg_type " +
            "WHERE typname = ANY($1) ORDER BY typname", conn)
        {
            Parameters = { new() { Value = names } },
        };
    
        await using var reader = await cmd.ExecuteReaderAsync();
        var found = new List<string>();
        while (await reader.ReadAsync())
        {
            found.Add(reader.GetString(0));
        }
        return found;
    }
    ```

=== "Go"

    ```go
    // findTypes returns the names from the list that exist as data types.
    func findTypes(ctx context.Context, conn *pgx.Conn, names []string) ([]string, error) {
    	// The whole list travels as one array parameter, so the SQL text is
    	// the same however many values the list holds. pgx converts a Go
    	// slice into a PostgreSQL array.
    	rows, err := conn.Query(ctx,
    		"SELECT typname FROM pg_catalog.pg_type "+
    			"WHERE typname = ANY($1) ORDER BY typname",
    		names,
    	)
    	if err != nil {
    		return nil, fmt.Errorf("query failed: %w", err)
    	}
    
    	// CollectRows reads every row, closes the rows, and reports any error.
    	found, err := pgx.CollectRows(rows, pgx.RowTo[string])
    	if err != nil {
    		return nil, fmt.Errorf("query failed: %w", err)
    	}
    	return found, nil
    }
    
    ```

=== "Rust"

    ```rust
    /// Returns the names from the list that exist as data types.
    fn find_types(client: &mut Client, names: &[&str]) -> Result<Vec<String>, postgres::Error> {
        // The whole list travels as one array parameter, so the SQL text is
        // the same however many values the list holds. The driver converts a
        // slice into a PostgreSQL array.
        let rows = client.query(
            "SELECT typname FROM pg_catalog.pg_type \
             WHERE typname = ANY($1) ORDER BY typname",
            &[&names],
        )?;
    
        Ok(rows.iter().map(|row| row.get(0)).collect())
    }
    ```

=== "Ruby"

    ```ruby
    # Returns the names from the list that exist as data types.
    def find_types(conn, names)
      # The whole list travels as one array parameter, so the SQL text is the
      # same however many values the list holds. PG::TextEncoder::Array turns
      # a Ruby array into the text form of a PostgreSQL array, quoting each
      # element as needed.
      encoder = PG::TextEncoder::Array.new
      result = conn.exec_params(
        "SELECT typname FROM pg_catalog.pg_type " \
        "WHERE typname = ANY($1) ORDER BY typname",
        [encoder.encode(names)]
      )
    
      result.column_values(0)
    end
    ```

=== "C"

    ```c
    /*
     * Build the text form of a PostgreSQL array from a list of strings, such
     * as {"int4","text"}. Every element is wrapped in double quotes, and any
     * backslash or double quote inside an element is escaped with a
     * backslash, so no element can end early or add elements. The caller
     * frees the result with free(); NULL means that memory ran out.
     */
    static char *
    array_literal(const char *const *names, int count)
    {
        size_t size = 3;    /* braces and the terminating NUL */
        char *literal;
        char *out;
    
        /* Worst case, every character needs a backslash, plus two quotes and
         * a comma for each element. */
        for (int i = 0; i < count; i++)
            size += 2 * strlen(names[i]) + 3;
    
        literal = malloc(size);
        if (literal == NULL)
            return NULL;
    
        out = literal;
        *out++ = '{';
        for (int i = 0; i < count; i++)
        {
            if (i > 0)
                *out++ = ',';
            *out++ = '"';
            for (const char *p = names[i]; *p != '\0'; p++)
            {
                if (*p == '"' || *p == '\\')
                    *out++ = '\\';
                *out++ = *p;
            }
            *out++ = '"';
        }
        *out++ = '}';
        *out = '\0';
        return literal;
    }
    
    /*
     * Print the names from the list that exist as data types, in the format
     * of the expected output, and return true on success. On failure,
     * PQerrorMessage() describes the error.
     */
    static bool
    find_types(PGconn *conn, const char *const *names, int count)
    {
        /*
         * The whole list travels as one array parameter, so the SQL text is
         * the same however many values the list holds. libpq has no array
         * type of its own, so the parameter is the text form of an array, and
         * the cast tells the server how to read it.
         */
        char *literal = array_literal(names, count);
        const char *params[1];
        PGresult *res;
        bool ok;
    
        if (literal == NULL)
            return false;
        params[0] = literal;
    
        res = PQexecParams(conn,
                           "SELECT typname FROM pg_catalog.pg_type "
                           "WHERE typname = ANY($1::text[]) ORDER BY typname",
                           1,       /* number of parameters */
                           NULL,    /* let the server infer types */
                           params,
                           NULL,    /* text parameters need no lengths */
                           NULL,    /* all parameters are text */
                           0);      /* ask for text results */
        ok = PQresultStatus(res) == PGRES_TUPLES_OK;
    
        if (ok)
        {
            int found = PQntuples(res);
    
            printf("Found %d of %d types: ", found, count);
            for (int i = 0; i < found; i++)
                printf("%s%s", i > 0 ? ", " : "", PQgetvalue(res, i, 0));
            printf("\n");
        }
    
        /* PQclear() frees the result, and accepts NULL. */
        PQclear(res);
        free(literal);
        return ok;
    }
    ```

## Handling Errors and Closing the Connection

The main part of each program calls the functions from the previous steps,
and prints the result. The program reports any connection or query failure
on `stderr`, and then exits with a non-zero status. The program also
closes the connection when the work completes or fails, using the same
mechanism as the first recipe in each language. The following tabs show
the main part of each program:

=== "Python"

    ```python
    def main() -> int:
        wanted = ["int4", "text", "bool", "no_such_type"]
        try:
            # The with block closes the connection when it exits, whether or
            # not an error occurred.
            with connect() as conn:
                found = find_types(conn, wanted)
                print(f"Found {len(found)} of {len(wanted)} types: "
                      f"{', '.join(found)}")
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
      const wanted = ["int4", "text", "bool", "no_such_type"];
      let client: pg.Client | undefined;
      try {
        client = await connect();
        const found = await findTypes(client, wanted);
        console.log(
          `Found ${found.length} of ${wanted.length} types: ${found.join(", ")}`,
        );
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
        String[] wanted = {"int4", "text", "bool", "no_such_type"};
    
        // try-with-resources closes the connection when the block exits,
        // whether or not an error occurred.
        try (Connection conn = connect()) {
            List<String> found = findTypes(conn, wanted);
            System.out.println("Found " + found.size() + " of "
                    + wanted.length + " types: " + String.join(", ", found));
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
        string[] wanted = ["int4", "text", "bool", "no_such_type"];
    
        // await using disposes of the data source, and returns the connection
        // to the pool, when the block exits, whether or not an error occurred.
        await using var dataSource = CreateDataSource();
        await using var conn = await dataSource.OpenConnectionAsync();
    
        var found = await FindTypesAsync(conn, wanted);
        Console.WriteLine(
            $"Found {found.Count} of {wanted.Length} types: " +
            string.Join(", ", found));
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
    	wanted := []string{"int4", "text", "bool", "no_such_type"}
    
    	conn, err := connect(ctx)
    	if err != nil {
    		return err
    	}
    	// The deferred call closes the connection when run() returns, whether
    	// or not an error occurred.
    	defer conn.Close(ctx)
    
    	found, err := findTypes(ctx, conn, wanted)
    	if err != nil {
    		return err
    	}
    
    	fmt.Printf("Found %d of %d types: %s\n",
    		len(found), len(wanted), strings.Join(found, ", "))
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
        let wanted = ["int4", "text", "bool", "no_such_type"];
    
        let mut client = connect()?;
        let found = find_types(&mut client, &wanted)?;
        println!(
            "Found {} of {} types: {}",
            found.len(),
            wanted.len(),
            found.join(", ")
        );
    
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
    wanted = ["int4", "text", "bool", "no_such_type"]
    
    begin
      conn = connect
      found = find_types(conn, wanted)
      puts "Found #{found.length} of #{wanted.length} types: #{found.join(', ')}"
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
        const char *const wanted[] = {"int4", "text", "bool", "no_such_type"};
        int status = EXIT_FAILURE;
        PGconn *conn = connect_to_server();
    
        /* The || operator skips the query if the connection failed. */
        if (PQstatus(conn) != CONNECTION_OK ||
            !find_types(conn, wanted, 4))
            fprintf(stderr, "Database error: %s", PQerrorMessage(conn));
        else
            status = EXIT_SUCCESS;
    
        /* Close the connection whether or not an error occurred. */
        PQfinish(conn);
        return status;
    }
    ```

## Running the Example

The complete project for each language is available in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/postgresql/array_parameters).
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
    Passing a list of values as a single array parameter, using psycopg 3.
    
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
    
    
    def find_types(conn: psycopg.Connection, names: list[str]) -> list[str]:
        """Returns the names from the list that exist as data types."""
        # The whole list travels as one array parameter, so the SQL text is
        # the same however many values the list holds. psycopg converts a
        # Python list into a PostgreSQL array.
        rows = conn.execute(
            "SELECT typname FROM pg_catalog.pg_type "
            "WHERE typname = ANY(%s) ORDER BY typname",
            (names,),
        ).fetchall()
        return [row[0] for row in rows]
    
    
    def main() -> int:
        wanted = ["int4", "text", "bool", "no_such_type"]
        try:
            # The with block closes the connection when it exits, whether or
            # not an error occurred.
            with connect() as conn:
                found = find_types(conn, wanted)
                print(f"Found {len(found)} of {len(wanted)} types: "
                      f"{', '.join(found)}")
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
     * Passing a list of values as a single array parameter, using
     * node-postgres.
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
    
    // Returns the names from the list that exist as data types.
    async function findTypes(client: pg.Client, names: string[]): Promise<string[]> {
      // The whole list travels as one array parameter, so the SQL text is the
      // same however many values the list holds. node-postgres converts a
      // JavaScript array into a PostgreSQL array.
      const result = await client.query<{ typname: string }>(
        "SELECT typname FROM pg_catalog.pg_type " +
          "WHERE typname = ANY($1) ORDER BY typname",
        [names],
      );
      return result.rows.map((row) => row.typname);
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
      const wanted = ["int4", "text", "bool", "no_such_type"];
      let client: pg.Client | undefined;
      try {
        client = await connect();
        const found = await findTypes(client, wanted);
        console.log(
          `Found ${found.length} of ${wanted.length} types: ${found.join(", ")}`,
        );
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
     * Passing a list of values as a single array parameter, using JDBC and
     * the PostgreSQL JDBC driver (pgJDBC).
     *
     * Copyright (c) 2026, pgEdge, Inc.
     * This code is released under the PostgreSQL License.
     */
    
    import java.sql.Array;
    import java.sql.Connection;
    import java.sql.DriverManager;
    import java.sql.PreparedStatement;
    import java.sql.ResultSet;
    import java.sql.SQLException;
    import java.util.ArrayList;
    import java.util.List;
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
    
        /** Returns the names from the list that exist as data types. */
        static List<String> findTypes(Connection conn, String[] names)
                throws SQLException {
            // The whole list travels as one array parameter, so the SQL text
            // is the same however many values the list holds.
            String sql = "SELECT typname FROM pg_catalog.pg_type "
                    + "WHERE typname = ANY(?) ORDER BY typname";
    
            // createArrayOf builds a JDBC array of the named element type,
            // which setArray sends as a PostgreSQL array. Array is not
            // AutoCloseable, so the finally block calls free() to release it.
            Array array = conn.createArrayOf("text", names);
            try (PreparedStatement stmt = conn.prepareStatement(sql)) {
                stmt.setArray(1, array);
    
                try (ResultSet rs = stmt.executeQuery()) {
                    List<String> found = new ArrayList<>();
                    while (rs.next()) {
                        found.add(rs.getString(1));
                    }
                    return found;
                }
            } finally {
                array.free();
            }
        }
    
        public static void main(String[] args) {
            String[] wanted = {"int4", "text", "bool", "no_such_type"};
    
            // try-with-resources closes the connection when the block exits,
            // whether or not an error occurred.
            try (Connection conn = connect()) {
                List<String> found = findTypes(conn, wanted);
                System.out.println("Found " + found.size() + " of "
                        + wanted.length + " types: " + String.join(", ", found));
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
     * Passing a list of values as a single array parameter, using Npgsql.
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
    
    // Returns the names from the list that exist as data types.
    static async Task<List<string>> FindTypesAsync(
        NpgsqlConnection conn, string[] names)
    {
        // The whole list travels as one array parameter, so the SQL text is
        // the same however many values the list holds. Npgsql converts a .NET
        // array into a PostgreSQL array.
        await using var cmd = new NpgsqlCommand(
            "SELECT typname FROM pg_catalog.pg_type " +
            "WHERE typname = ANY($1) ORDER BY typname", conn)
        {
            Parameters = { new() { Value = names } },
        };
    
        await using var reader = await cmd.ExecuteReaderAsync();
        var found = new List<string>();
        while (await reader.ReadAsync())
        {
            found.Add(reader.GetString(0));
        }
        return found;
    }
    
    try
    {
        string[] wanted = ["int4", "text", "bool", "no_such_type"];
    
        // await using disposes of the data source, and returns the connection
        // to the pool, when the block exits, whether or not an error occurred.
        await using var dataSource = CreateDataSource();
        await using var conn = await dataSource.OpenConnectionAsync();
    
        var found = await FindTypesAsync(conn, wanted);
        Console.WriteLine(
            $"Found {found.Count} of {wanted.Length} types: " +
            string.Join(", ", found));
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
    // Passing a list of values as a single array parameter, using pgx.
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
    	"strings"
    
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
    
    
    // findTypes returns the names from the list that exist as data types.
    func findTypes(ctx context.Context, conn *pgx.Conn, names []string) ([]string, error) {
    	// The whole list travels as one array parameter, so the SQL text is
    	// the same however many values the list holds. pgx converts a Go
    	// slice into a PostgreSQL array.
    	rows, err := conn.Query(ctx,
    		"SELECT typname FROM pg_catalog.pg_type "+
    			"WHERE typname = ANY($1) ORDER BY typname",
    		names,
    	)
    	if err != nil {
    		return nil, fmt.Errorf("query failed: %w", err)
    	}
    
    	// CollectRows reads every row, closes the rows, and reports any error.
    	found, err := pgx.CollectRows(rows, pgx.RowTo[string])
    	if err != nil {
    		return nil, fmt.Errorf("query failed: %w", err)
    	}
    	return found, nil
    }
    
    
    // run connects, runs the query, and prints the result, returning any
    // error to the caller.
    func run(ctx context.Context) error {
    	wanted := []string{"int4", "text", "bool", "no_such_type"}
    
    	conn, err := connect(ctx)
    	if err != nil {
    		return err
    	}
    	// The deferred call closes the connection when run() returns, whether
    	// or not an error occurred.
    	defer conn.Close(ctx)
    
    	found, err := findTypes(ctx, conn, wanted)
    	if err != nil {
    		return err
    	}
    
    	fmt.Printf("Found %d of %d types: %s\n",
    		len(found), len(wanted), strings.Join(found, ", "))
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
    // Passing a list of values as a single array parameter, using the postgres
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
    
    /// Returns the names from the list that exist as data types.
    fn find_types(client: &mut Client, names: &[&str]) -> Result<Vec<String>, postgres::Error> {
        // The whole list travels as one array parameter, so the SQL text is
        // the same however many values the list holds. The driver converts a
        // slice into a PostgreSQL array.
        let rows = client.query(
            "SELECT typname FROM pg_catalog.pg_type \
             WHERE typname = ANY($1) ORDER BY typname",
            &[&names],
        )?;
    
        Ok(rows.iter().map(|row| row.get(0)).collect())
    }
    
    /// Connects, runs the query, and prints the result. The ? operator
    /// returns any error to the caller.
    fn run() -> Result<(), postgres::Error> {
        let wanted = ["int4", "text", "bool", "no_such_type"];
    
        let mut client = connect()?;
        let found = find_types(&mut client, &wanted)?;
        println!(
            "Found {} of {} types: {}",
            found.len(),
            wanted.len(),
            found.join(", ")
        );
    
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
    # Passing a list of values as a single array parameter, using the pg gem.
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
    
    # Returns the names from the list that exist as data types.
    def find_types(conn, names)
      # The whole list travels as one array parameter, so the SQL text is the
      # same however many values the list holds. PG::TextEncoder::Array turns
      # a Ruby array into the text form of a PostgreSQL array, quoting each
      # element as needed.
      encoder = PG::TextEncoder::Array.new
      result = conn.exec_params(
        "SELECT typname FROM pg_catalog.pg_type " \
        "WHERE typname = ANY($1) ORDER BY typname",
        [encoder.encode(names)]
      )
    
      result.column_values(0)
    end
    
    wanted = ["int4", "text", "bool", "no_such_type"]
    
    begin
      conn = connect
      found = find_types(conn, wanted)
      puts "Found #{found.length} of #{wanted.length} types: #{found.join(', ')}"
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
     * Passing a list of values as a single array parameter, using libpq.
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
     * Build the text form of a PostgreSQL array from a list of strings, such
     * as {"int4","text"}. Every element is wrapped in double quotes, and any
     * backslash or double quote inside an element is escaped with a
     * backslash, so no element can end early or add elements. The caller
     * frees the result with free(); NULL means that memory ran out.
     */
    static char *
    array_literal(const char *const *names, int count)
    {
        size_t size = 3;    /* braces and the terminating NUL */
        char *literal;
        char *out;
    
        /* Worst case, every character needs a backslash, plus two quotes and
         * a comma for each element. */
        for (int i = 0; i < count; i++)
            size += 2 * strlen(names[i]) + 3;
    
        literal = malloc(size);
        if (literal == NULL)
            return NULL;
    
        out = literal;
        *out++ = '{';
        for (int i = 0; i < count; i++)
        {
            if (i > 0)
                *out++ = ',';
            *out++ = '"';
            for (const char *p = names[i]; *p != '\0'; p++)
            {
                if (*p == '"' || *p == '\\')
                    *out++ = '\\';
                *out++ = *p;
            }
            *out++ = '"';
        }
        *out++ = '}';
        *out = '\0';
        return literal;
    }
    
    /*
     * Print the names from the list that exist as data types, in the format
     * of the expected output, and return true on success. On failure,
     * PQerrorMessage() describes the error.
     */
    static bool
    find_types(PGconn *conn, const char *const *names, int count)
    {
        /*
         * The whole list travels as one array parameter, so the SQL text is
         * the same however many values the list holds. libpq has no array
         * type of its own, so the parameter is the text form of an array, and
         * the cast tells the server how to read it.
         */
        char *literal = array_literal(names, count);
        const char *params[1];
        PGresult *res;
        bool ok;
    
        if (literal == NULL)
            return false;
        params[0] = literal;
    
        res = PQexecParams(conn,
                           "SELECT typname FROM pg_catalog.pg_type "
                           "WHERE typname = ANY($1::text[]) ORDER BY typname",
                           1,       /* number of parameters */
                           NULL,    /* let the server infer types */
                           params,
                           NULL,    /* text parameters need no lengths */
                           NULL,    /* all parameters are text */
                           0);      /* ask for text results */
        ok = PQresultStatus(res) == PGRES_TUPLES_OK;
    
        if (ok)
        {
            int found = PQntuples(res);
    
            printf("Found %d of %d types: ", found, count);
            for (int i = 0; i < found; i++)
                printf("%s%s", i > 0 ? ", " : "", PQgetvalue(res, i, 0));
            printf("\n");
        }
    
        /* PQclear() frees the result, and accepts NULL. */
        PQclear(res);
        free(literal);
        return ok;
    }
    
    int
    main(void)
    {
        const char *const wanted[] = {"int4", "text", "bool", "no_such_type"};
        int status = EXIT_FAILURE;
        PGconn *conn = connect_to_server();
    
        /* The || operator skips the query if the connection failed. */
        if (PQstatus(conn) != CONNECTION_OK ||
            !find_types(conn, wanted, 4))
            fprintf(stderr, "Database error: %s", PQerrorMessage(conn));
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
  recipe explains the connection settings and the parameter syntax of each
  driver.
- The PostgreSQL documentation for
  [row and array comparisons](https://www.postgresql.org/docs/current/functions-comparisons.html)
  describes `ANY` and `ALL`.
- The PostgreSQL documentation for
  [array input and output syntax](https://www.postgresql.org/docs/current/arrays.html#ARRAYS-IO)
  describes the quoting rules that the C program follows.
