# Inserting Rows and Reading Generated Keys

This recipe demonstrates how an application inserts a row and learns the
key that the database server generated for it. The example uses the
`RETURNING` clause, which makes an `INSERT` statement send back values from
the new row, so the program needs no second query to find the key. Each
step shows the code in every supported language; selecting a language tab
switches every tab on the site to that language.

The example program creates a temporary table of people, in which the
server assigns each `id` from an identity column. The program inserts three
people and prints the id that the server chose for each one:

```text
Inserted 'Jane Doe' with id 1
Inserted 'John Smith' with id 2
Inserted 'Alex Example' with id 3
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
      "name": "insert-returning",
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
previous step. A temporary table belongs to one connection, so every
statement in this example runs on the same connection. The C# program
borrows one connection from an Npgsql data source and keeps it for the
whole run. The following tabs show how each program opens the connection:

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

## Creating the Table

Each program creates a temporary table named `people`. A temporary table is
private to the connection and vanishes when the connection closes, so the
example leaves nothing behind and can run again straight away. The `id`
column is declared `GENERATED ALWAYS AS IDENTITY`, which makes the server
take each value from an internal sequence and refuse any attempt to supply
one. The following tabs show how each program creates the table:

=== "Python"

    ```python
    def create_people(conn: psycopg.Connection) -> None:
        """Creates a temporary table whose id column the server fills in.
    
        GENERATED ALWAYS AS IDENTITY makes the server assign each id from a
        sequence, and refuses any attempt to supply one.
        """
        conn.execute(
            "CREATE TEMPORARY TABLE people ("
            "id int GENERATED ALWAYS AS IDENTITY PRIMARY KEY, "
            "name text NOT NULL)"
        )
    ```

=== "TypeScript"

    ```typescript
    // Creates a temporary table whose id column the server fills in.
    // GENERATED ALWAYS AS IDENTITY makes the server assign each id from a
    // sequence, and refuses any attempt to supply one.
    async function createPeople(client: pg.Client): Promise<void> {
      await client.query(
        "CREATE TEMPORARY TABLE people (" +
          "id int GENERATED ALWAYS AS IDENTITY PRIMARY KEY, " +
          "name text NOT NULL)",
      );
    }
    ```

=== "Java"

    ```java
    /**
     * Creates a temporary table whose id column the server fills in.
     * GENERATED ALWAYS AS IDENTITY makes the server assign each id from a
     * sequence, and refuses any attempt to supply one.
     */
    static void createPeople(Connection conn) throws SQLException {
        try (Statement stmt = conn.createStatement()) {
            stmt.execute("CREATE TEMPORARY TABLE people ("
                    + "id int GENERATED ALWAYS AS IDENTITY PRIMARY KEY, "
                    + "name text NOT NULL)");
        }
    }
    ```

=== "C#"

    ```csharp
    // Creates a temporary table whose id column the server fills in.
    // GENERATED ALWAYS AS IDENTITY makes the server assign each id from a
    // sequence, and refuses any attempt to supply one.
    static async Task CreatePeopleAsync(NpgsqlConnection conn)
    {
        await using var cmd = new NpgsqlCommand(
            "CREATE TEMPORARY TABLE people (" +
            "id int GENERATED ALWAYS AS IDENTITY PRIMARY KEY, " +
            "name text NOT NULL)", conn);
        await cmd.ExecuteNonQueryAsync();
    }
    ```

=== "Go"

    ```go
    // createPeople creates a temporary table whose id column the server fills
    // in. GENERATED ALWAYS AS IDENTITY makes the server assign each id from a
    // sequence, and refuses any attempt to supply one.
    func createPeople(ctx context.Context, conn *pgx.Conn) error {
    	_, err := conn.Exec(ctx,
    		"CREATE TEMPORARY TABLE people ("+
    			"id int GENERATED ALWAYS AS IDENTITY PRIMARY KEY, "+
    			"name text NOT NULL)")
    	if err != nil {
    		return fmt.Errorf("create table failed: %w", err)
    	}
    	return nil
    }
    
    ```

=== "Rust"

    ```rust
    /// Creates a temporary table whose id column the server fills in.
    /// GENERATED ALWAYS AS IDENTITY makes the server assign each id from a
    /// sequence, and refuses any attempt to supply one. batch_execute runs
    /// statements that take no parameters.
    fn create_people(client: &mut Client) -> Result<(), postgres::Error> {
        client.batch_execute(
            "CREATE TEMPORARY TABLE people (
                 id int GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
                 name text NOT NULL)",
        )
    }
    ```

=== "Ruby"

    ```ruby
    # Creates a temporary table whose id column the server fills in.
    # GENERATED ALWAYS AS IDENTITY makes the server assign each id from a
    # sequence, and refuses any attempt to supply one.
    def create_people(conn)
      conn.exec(
        "CREATE TEMPORARY TABLE people (" \
        "id int GENERATED ALWAYS AS IDENTITY PRIMARY KEY, " \
        "name text NOT NULL)"
      )
    end
    ```

=== "C"

    ```c
    /*
     * Create a temporary table whose id column the server fills in, and
     * return true on success. GENERATED ALWAYS AS IDENTITY makes the server
     * assign each id from a sequence, and refuses any attempt to supply one.
     */
    static bool
    create_people(PGconn *conn)
    {
        PGresult *res = PQexec(conn,
                               "CREATE TEMPORARY TABLE people ("
                               "id int GENERATED ALWAYS AS IDENTITY "
                               "PRIMARY KEY, "
                               "name text NOT NULL)");
        bool ok = PQresultStatus(res) == PGRES_COMMAND_OK;
    
        PQclear(res);
        return ok;
    }
    ```

## Inserting a Row and Reading Its Key

Each program inserts a row in a function that takes the name of the person
and returns the new id. The statement ends with `RETURNING id`, which turns
the `INSERT` into a statement that produces a result set with one row, in
the same way as a `SELECT`. The program therefore sends the statement as a
query and reads the id from the first column of the first row. Reading the
key this way is safe when several sessions insert at the same time, because
the server returns the value that it assigned to this row, whereas a
separate query for the largest id could return a row from another session.

The function sends the name as a parameter, so the server never interprets
it as SQL. The drivers differ slightly in how they run a statement that
returns rows:

- The Java program calls `executeQuery()` rather than `executeUpdate()`,
  because JDBC rejects a result set from an update call.
- The Python, TypeScript, Go, Rust, and Ruby programs use their ordinary
  query calls, and the C# program calls `ExecuteScalarAsync()`.
- The C program calls `PQexecParams()` and expects `PGRES_TUPLES_OK`,
  rather than the `PGRES_COMMAND_OK` that a plain `INSERT` returns. The C
  and Ruby drivers return the id as text, so those programs convert it to an
  integer.

The following tabs show how each program inserts a row:

=== "Python"

    ```python
    def add_person(conn: psycopg.Connection, name: str) -> int:
        """Inserts a row and returns the id that the server generated."""
        # RETURNING makes the INSERT produce a result row, like a SELECT, so
        # the program learns the new id without a second query. The name is a
        # parameter, which psycopg sends separately from the SQL text.
        row = conn.execute(
            "INSERT INTO people (name) VALUES (%s) RETURNING id",
            (name,),
        ).fetchone()
        return row[0]
    ```

=== "TypeScript"

    ```typescript
    // Inserts a row and returns the id that the server generated.
    async function addPerson(client: pg.Client, name: string): Promise<number> {
      // RETURNING makes the INSERT produce a result row, like a SELECT, so the
      // program learns the new id without a second query. The name is a
      // parameter, which node-postgres sends separately from the SQL text.
      const result = await client.query<{ id: number }>(
        "INSERT INTO people (name) VALUES ($1) RETURNING id",
        [name],
      );
    
      // An int column arrives as a JavaScript number.
      return result.rows[0].id;
    }
    ```

=== "Java"

    ```java
    /** Inserts a row and returns the id that the server generated. */
    static int addPerson(Connection conn, String name) throws SQLException {
        // RETURNING makes the INSERT produce a result row, like a SELECT,
        // so the program learns the new id without a second query. The
        // name is a parameter, which the driver sends separately from the
        // SQL text. Because the statement returns rows, the program runs
        // it with executeQuery() rather than executeUpdate().
        String sql = "INSERT INTO people (name) VALUES (?) RETURNING id";
    
        // try-with-resources closes the statement and the result set when
        // each block exits, whether or not an error occurred.
        try (PreparedStatement stmt = conn.prepareStatement(sql)) {
            stmt.setString(1, name);
    
            try (ResultSet rs = stmt.executeQuery()) {
                rs.next();
                return rs.getInt(1);
            }
        }
    }
    ```

=== "C#"

    ```csharp
    // Inserts a row and returns the id that the server generated.
    static async Task<int> AddPersonAsync(NpgsqlConnection conn, string name)
    {
        // RETURNING makes the INSERT produce a result row, like a SELECT, so
        // the program learns the new id without a second query. The name is a
        // parameter, which Npgsql sends separately from the SQL text.
        // Positional parameters are written $1, $2, and so on.
        await using var cmd = new NpgsqlCommand(
            "INSERT INTO people (name) VALUES ($1) RETURNING id", conn)
        {
            Parameters = { new() { Value = name } },
        };
    
        // ExecuteScalarAsync returns the first column of the first row. An
        // int maps to int.
        return (int)(await cmd.ExecuteScalarAsync())!;
    }
    ```

=== "Go"

    ```go
    // addPerson inserts a row and returns the id that the server generated.
    func addPerson(ctx context.Context, conn *pgx.Conn, name string) (int, error) {
    	// RETURNING makes the INSERT produce a result row, like a SELECT, so
    	// the program learns the new id without a second query. The name is a
    	// parameter, which pgx sends separately from the SQL text.
    	var id int
    	err := conn.QueryRow(ctx,
    		"INSERT INTO people (name) VALUES ($1) RETURNING id",
    		name,
    	).Scan(&id)
    	if err != nil {
    		return 0, fmt.Errorf("insert failed: %w", err)
    	}
    	return id, nil
    }
    
    ```

=== "Rust"

    ```rust
    /// Inserts a row and returns the id that the server generated.
    fn add_person(client: &mut Client, name: &str) -> Result<i32, postgres::Error> {
        // RETURNING makes the INSERT produce a result row, like a SELECT, so
        // the program learns the new id without a second query. The name is a
        // parameter, which the driver sends separately from the SQL text.
        let row = client.query_one(
            "INSERT INTO people (name) VALUES ($1) RETURNING id",
            &[&name],
        )?;
    
        // An int column maps to i32.
        Ok(row.get(0))
    }
    ```

=== "Ruby"

    ```ruby
    # Inserts a row and returns the id that the server generated.
    def add_person(conn, name)
      # RETURNING makes the INSERT produce a result row, like a SELECT, so the
      # program learns the new id without a second query. The name is a
      # parameter, which the pg gem sends separately from the SQL text.
      result = conn.exec_params(
        "INSERT INTO people (name) VALUES ($1) RETURNING id",
        [name]
      )
    
      # Results arrive as strings, so convert the value to an Integer.
      result.getvalue(0, 0).to_i
    end
    ```

=== "C"

    ```c
    /*
     * Insert a row and store the id that the server generated in *id, and
     * return true on success. On failure, PQerrorMessage() describes the
     * error.
     */
    static bool
    add_person(PGconn *conn, const char *name, int *id)
    {
        /*
         * RETURNING makes the INSERT produce a result row, like a SELECT, so
         * the program learns the new id without a second query. The name is a
         * parameter, which libpq sends separately from the SQL text.
         */
        const char *params[] = {name};
        PGresult *res = PQexecParams(conn,
                                     "INSERT INTO people (name) VALUES ($1) "
                                     "RETURNING id",
                                     1,     /* number of parameters */
                                     NULL,  /* let the server infer types */
                                     params,
                                     NULL,  /* text parameters need no lengths */
                                     NULL,  /* all parameters are text */
                                     0);    /* ask for text results */
        bool ok = PQresultStatus(res) == PGRES_TUPLES_OK;
    
        /* Results arrive as text, so convert the value to a number. */
        if (ok)
            *id = atoi(PQgetvalue(res, 0, 0));
    
        /* PQclear() frees the result, and accepts NULL. */
        PQclear(res);
        return ok;
    }
    ```

## Handling Errors and Closing the Connection

The main part of each program creates the table, inserts the three people,
and prints the id of each one. The program reports any connection or query
failure on `stderr`, and then exits with a non-zero status. It also closes
the connection when the work completes or fails, in the same way as the
first recipe. The following tabs show the main part of each program:

=== "Python"

    ```python
    def main() -> int:
        try:
            # The with block commits the transaction and closes the connection
            # when it exits normally, and rolls back if an error occurred.
            with connect() as conn:
                create_people(conn)
                for name in ("Jane Doe", "John Smith", "Alex Example"):
                    person_id = add_person(conn, name)
                    print(f"Inserted '{name}' with id {person_id}")
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
        await createPeople(client);
        for (const name of ["Jane Doe", "John Smith", "Alex Example"]) {
          const id = await addPerson(client, name);
          console.log(`Inserted '${name}' with id ${id}`);
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
            createPeople(conn);
            for (String name : new String[] {
                    "Jane Doe", "John Smith", "Alex Example"}) {
                int id = addPerson(conn, name);
                System.out.println("Inserted '" + name + "' with id " + id);
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
    
        await CreatePeopleAsync(conn);
        foreach (var name in new[] { "Jane Doe", "John Smith", "Alex Example" })
        {
            var id = await AddPersonAsync(conn, name);
            Console.WriteLine($"Inserted '{name}' with id {id}");
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
    // run connects, inserts the rows, and prints their ids, returning any
    // error to the caller.
    func run(ctx context.Context) error {
    	conn, err := connect(ctx)
    	if err != nil {
    		return err
    	}
    	// The deferred call closes the connection when run() returns, whether
    	// or not an error occurred.
    	defer conn.Close(ctx)
    
    	if err := createPeople(ctx, conn); err != nil {
    		return err
    	}
    	for _, name := range []string{"Jane Doe", "John Smith", "Alex Example"} {
    		id, err := addPerson(ctx, conn, name)
    		if err != nil {
    			return err
    		}
    		fmt.Printf("Inserted '%s' with id %d\n", name, id)
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
    /// Connects, inserts the rows, and prints their ids. The ? operator
    /// returns any error to the caller.
    fn run() -> Result<(), postgres::Error> {
        let mut client = connect()?;
        create_people(&mut client)?;
        for name in ["Jane Doe", "John Smith", "Alex Example"] {
            let id = add_person(&mut client, name)?;
            println!("Inserted '{name}' with id {id}");
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
      create_people(conn)
      ["Jane Doe", "John Smith", "Alex Example"].each do |name|
        id = add_person(conn, name)
        puts "Inserted '#{name}' with id #{id}"
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
        static const char *const names[] = {
            "Jane Doe", "John Smith", "Alex Example"
        };
        int status = EXIT_FAILURE;
        int id;
        size_t i;
        PGconn *conn = connect_to_server();
    
        if (PQstatus(conn) != CONNECTION_OK || !create_people(conn))
        {
            fprintf(stderr, "Database error: %s", PQerrorMessage(conn));
            PQfinish(conn);
            return status;
        }
    
        status = EXIT_SUCCESS;
        for (i = 0; i < sizeof(names) / sizeof(names[0]); i++)
        {
            if (!add_person(conn, names[i], &id))
            {
                fprintf(stderr, "Database error: %s", PQerrorMessage(conn));
                status = EXIT_FAILURE;
                break;
            }
            printf("Inserted '%s' with id %d\n", names[i], id);
        }
    
        /* Close the connection whether or not an error occurred. */
        PQfinish(conn);
        return status;
    }
    ```

## Running the Example

The complete project for each language is available in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/postgresql/insert_returning).
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
    Inserting rows and reading generated keys, using psycopg 3.
    
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
    
    
    def create_people(conn: psycopg.Connection) -> None:
        """Creates a temporary table whose id column the server fills in.
    
        GENERATED ALWAYS AS IDENTITY makes the server assign each id from a
        sequence, and refuses any attempt to supply one.
        """
        conn.execute(
            "CREATE TEMPORARY TABLE people ("
            "id int GENERATED ALWAYS AS IDENTITY PRIMARY KEY, "
            "name text NOT NULL)"
        )
    
    
    def add_person(conn: psycopg.Connection, name: str) -> int:
        """Inserts a row and returns the id that the server generated."""
        # RETURNING makes the INSERT produce a result row, like a SELECT, so
        # the program learns the new id without a second query. The name is a
        # parameter, which psycopg sends separately from the SQL text.
        row = conn.execute(
            "INSERT INTO people (name) VALUES (%s) RETURNING id",
            (name,),
        ).fetchone()
        return row[0]
    
    
    def main() -> int:
        try:
            # The with block commits the transaction and closes the connection
            # when it exits normally, and rolls back if an error occurred.
            with connect() as conn:
                create_people(conn)
                for name in ("Jane Doe", "John Smith", "Alex Example"):
                    person_id = add_person(conn, name)
                    print(f"Inserted '{name}' with id {person_id}")
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
     * Inserting rows and reading generated keys, using node-postgres.
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
    
    // Creates a temporary table whose id column the server fills in.
    // GENERATED ALWAYS AS IDENTITY makes the server assign each id from a
    // sequence, and refuses any attempt to supply one.
    async function createPeople(client: pg.Client): Promise<void> {
      await client.query(
        "CREATE TEMPORARY TABLE people (" +
          "id int GENERATED ALWAYS AS IDENTITY PRIMARY KEY, " +
          "name text NOT NULL)",
      );
    }
    
    // Inserts a row and returns the id that the server generated.
    async function addPerson(client: pg.Client, name: string): Promise<number> {
      // RETURNING makes the INSERT produce a result row, like a SELECT, so the
      // program learns the new id without a second query. The name is a
      // parameter, which node-postgres sends separately from the SQL text.
      const result = await client.query<{ id: number }>(
        "INSERT INTO people (name) VALUES ($1) RETURNING id",
        [name],
      );
    
      // An int column arrives as a JavaScript number.
      return result.rows[0].id;
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
        await createPeople(client);
        for (const name of ["Jane Doe", "John Smith", "Alex Example"]) {
          const id = await addPerson(client, name);
          console.log(`Inserted '${name}' with id ${id}`);
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
     * Inserting rows and reading generated keys, using JDBC and the
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
         * Creates a temporary table whose id column the server fills in.
         * GENERATED ALWAYS AS IDENTITY makes the server assign each id from a
         * sequence, and refuses any attempt to supply one.
         */
        static void createPeople(Connection conn) throws SQLException {
            try (Statement stmt = conn.createStatement()) {
                stmt.execute("CREATE TEMPORARY TABLE people ("
                        + "id int GENERATED ALWAYS AS IDENTITY PRIMARY KEY, "
                        + "name text NOT NULL)");
            }
        }
    
        /** Inserts a row and returns the id that the server generated. */
        static int addPerson(Connection conn, String name) throws SQLException {
            // RETURNING makes the INSERT produce a result row, like a SELECT,
            // so the program learns the new id without a second query. The
            // name is a parameter, which the driver sends separately from the
            // SQL text. Because the statement returns rows, the program runs
            // it with executeQuery() rather than executeUpdate().
            String sql = "INSERT INTO people (name) VALUES (?) RETURNING id";
    
            // try-with-resources closes the statement and the result set when
            // each block exits, whether or not an error occurred.
            try (PreparedStatement stmt = conn.prepareStatement(sql)) {
                stmt.setString(1, name);
    
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
                createPeople(conn);
                for (String name : new String[] {
                        "Jane Doe", "John Smith", "Alex Example"}) {
                    int id = addPerson(conn, name);
                    System.out.println("Inserted '" + name + "' with id " + id);
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
     * Inserting rows and reading generated keys, using Npgsql.
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
    
    // Creates a temporary table whose id column the server fills in.
    // GENERATED ALWAYS AS IDENTITY makes the server assign each id from a
    // sequence, and refuses any attempt to supply one.
    static async Task CreatePeopleAsync(NpgsqlConnection conn)
    {
        await using var cmd = new NpgsqlCommand(
            "CREATE TEMPORARY TABLE people (" +
            "id int GENERATED ALWAYS AS IDENTITY PRIMARY KEY, " +
            "name text NOT NULL)", conn);
        await cmd.ExecuteNonQueryAsync();
    }
    
    // Inserts a row and returns the id that the server generated.
    static async Task<int> AddPersonAsync(NpgsqlConnection conn, string name)
    {
        // RETURNING makes the INSERT produce a result row, like a SELECT, so
        // the program learns the new id without a second query. The name is a
        // parameter, which Npgsql sends separately from the SQL text.
        // Positional parameters are written $1, $2, and so on.
        await using var cmd = new NpgsqlCommand(
            "INSERT INTO people (name) VALUES ($1) RETURNING id", conn)
        {
            Parameters = { new() { Value = name } },
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
    
        await CreatePeopleAsync(conn);
        foreach (var name in new[] { "Jane Doe", "John Smith", "Alex Example" })
        {
            var id = await AddPersonAsync(conn, name);
            Console.WriteLine($"Inserted '{name}' with id {id}");
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
    // Inserting rows and reading generated keys, using pgx.
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
    
    
    // createPeople creates a temporary table whose id column the server fills
    // in. GENERATED ALWAYS AS IDENTITY makes the server assign each id from a
    // sequence, and refuses any attempt to supply one.
    func createPeople(ctx context.Context, conn *pgx.Conn) error {
    	_, err := conn.Exec(ctx,
    		"CREATE TEMPORARY TABLE people ("+
    			"id int GENERATED ALWAYS AS IDENTITY PRIMARY KEY, "+
    			"name text NOT NULL)")
    	if err != nil {
    		return fmt.Errorf("create table failed: %w", err)
    	}
    	return nil
    }
    
    
    // addPerson inserts a row and returns the id that the server generated.
    func addPerson(ctx context.Context, conn *pgx.Conn, name string) (int, error) {
    	// RETURNING makes the INSERT produce a result row, like a SELECT, so
    	// the program learns the new id without a second query. The name is a
    	// parameter, which pgx sends separately from the SQL text.
    	var id int
    	err := conn.QueryRow(ctx,
    		"INSERT INTO people (name) VALUES ($1) RETURNING id",
    		name,
    	).Scan(&id)
    	if err != nil {
    		return 0, fmt.Errorf("insert failed: %w", err)
    	}
    	return id, nil
    }
    
    
    // run connects, inserts the rows, and prints their ids, returning any
    // error to the caller.
    func run(ctx context.Context) error {
    	conn, err := connect(ctx)
    	if err != nil {
    		return err
    	}
    	// The deferred call closes the connection when run() returns, whether
    	// or not an error occurred.
    	defer conn.Close(ctx)
    
    	if err := createPeople(ctx, conn); err != nil {
    		return err
    	}
    	for _, name := range []string{"Jane Doe", "John Smith", "Alex Example"} {
    		id, err := addPerson(ctx, conn, name)
    		if err != nil {
    			return err
    		}
    		fmt.Printf("Inserted '%s' with id %d\n", name, id)
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
    // Inserting rows and reading generated keys, using the postgres crate.
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
    
    /// Creates a temporary table whose id column the server fills in.
    /// GENERATED ALWAYS AS IDENTITY makes the server assign each id from a
    /// sequence, and refuses any attempt to supply one. batch_execute runs
    /// statements that take no parameters.
    fn create_people(client: &mut Client) -> Result<(), postgres::Error> {
        client.batch_execute(
            "CREATE TEMPORARY TABLE people (
                 id int GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
                 name text NOT NULL)",
        )
    }
    
    /// Inserts a row and returns the id that the server generated.
    fn add_person(client: &mut Client, name: &str) -> Result<i32, postgres::Error> {
        // RETURNING makes the INSERT produce a result row, like a SELECT, so
        // the program learns the new id without a second query. The name is a
        // parameter, which the driver sends separately from the SQL text.
        let row = client.query_one(
            "INSERT INTO people (name) VALUES ($1) RETURNING id",
            &[&name],
        )?;
    
        // An int column maps to i32.
        Ok(row.get(0))
    }
    
    /// Connects, inserts the rows, and prints their ids. The ? operator
    /// returns any error to the caller.
    fn run() -> Result<(), postgres::Error> {
        let mut client = connect()?;
        create_people(&mut client)?;
        for name in ["Jane Doe", "John Smith", "Alex Example"] {
            let id = add_person(&mut client, name)?;
            println!("Inserted '{name}' with id {id}");
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
    # Inserting rows and reading generated keys, using the pg gem.
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
    
    # Creates a temporary table whose id column the server fills in.
    # GENERATED ALWAYS AS IDENTITY makes the server assign each id from a
    # sequence, and refuses any attempt to supply one.
    def create_people(conn)
      conn.exec(
        "CREATE TEMPORARY TABLE people (" \
        "id int GENERATED ALWAYS AS IDENTITY PRIMARY KEY, " \
        "name text NOT NULL)"
      )
    end
    
    # Inserts a row and returns the id that the server generated.
    def add_person(conn, name)
      # RETURNING makes the INSERT produce a result row, like a SELECT, so the
      # program learns the new id without a second query. The name is a
      # parameter, which the pg gem sends separately from the SQL text.
      result = conn.exec_params(
        "INSERT INTO people (name) VALUES ($1) RETURNING id",
        [name]
      )
    
      # Results arrive as strings, so convert the value to an Integer.
      result.getvalue(0, 0).to_i
    end
    
    begin
      conn = connect
      create_people(conn)
      ["Jane Doe", "John Smith", "Alex Example"].each do |name|
        id = add_person(conn, name)
        puts "Inserted '#{name}' with id #{id}"
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
     * Inserting rows and reading generated keys, using libpq.
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
     * Create a temporary table whose id column the server fills in, and
     * return true on success. GENERATED ALWAYS AS IDENTITY makes the server
     * assign each id from a sequence, and refuses any attempt to supply one.
     */
    static bool
    create_people(PGconn *conn)
    {
        PGresult *res = PQexec(conn,
                               "CREATE TEMPORARY TABLE people ("
                               "id int GENERATED ALWAYS AS IDENTITY "
                               "PRIMARY KEY, "
                               "name text NOT NULL)");
        bool ok = PQresultStatus(res) == PGRES_COMMAND_OK;
    
        PQclear(res);
        return ok;
    }
    
    /*
     * Insert a row and store the id that the server generated in *id, and
     * return true on success. On failure, PQerrorMessage() describes the
     * error.
     */
    static bool
    add_person(PGconn *conn, const char *name, int *id)
    {
        /*
         * RETURNING makes the INSERT produce a result row, like a SELECT, so
         * the program learns the new id without a second query. The name is a
         * parameter, which libpq sends separately from the SQL text.
         */
        const char *params[] = {name};
        PGresult *res = PQexecParams(conn,
                                     "INSERT INTO people (name) VALUES ($1) "
                                     "RETURNING id",
                                     1,     /* number of parameters */
                                     NULL,  /* let the server infer types */
                                     params,
                                     NULL,  /* text parameters need no lengths */
                                     NULL,  /* all parameters are text */
                                     0);    /* ask for text results */
        bool ok = PQresultStatus(res) == PGRES_TUPLES_OK;
    
        /* Results arrive as text, so convert the value to a number. */
        if (ok)
            *id = atoi(PQgetvalue(res, 0, 0));
    
        /* PQclear() frees the result, and accepts NULL. */
        PQclear(res);
        return ok;
    }
    
    int
    main(void)
    {
        static const char *const names[] = {
            "Jane Doe", "John Smith", "Alex Example"
        };
        int status = EXIT_FAILURE;
        int id;
        size_t i;
        PGconn *conn = connect_to_server();
    
        if (PQstatus(conn) != CONNECTION_OK || !create_people(conn))
        {
            fprintf(stderr, "Database error: %s", PQerrorMessage(conn));
            PQfinish(conn);
            return status;
        }
    
        status = EXIT_SUCCESS;
        for (i = 0; i < sizeof(names) / sizeof(names[0]); i++)
        {
            if (!add_person(conn, names[i], &id))
            {
                fprintf(stderr, "Database error: %s", PQerrorMessage(conn));
                status = EXIT_FAILURE;
                break;
            }
            printf("Inserted '%s' with id %d\n", names[i], id);
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
  recipe explains the connection settings in more detail.
- The PostgreSQL documentation for
  [`RETURNING`](https://www.postgresql.org/docs/current/dml-returning.html)
  describes how to return data from `INSERT`, `UPDATE`, and `DELETE`.
- The PostgreSQL documentation for
  [identity columns](https://www.postgresql.org/docs/current/ddl-identity-columns.html)
  explains `GENERATED ALWAYS` and `GENERATED BY DEFAULT`.
