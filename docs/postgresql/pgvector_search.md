# Storing and Searching Vectors with pgvector

This recipe demonstrates how an application stores vectors in PostgreSQL and
finds the rows nearest to a query vector, using the
[pgvector](https://github.com/pgvector/pgvector) extension. Vectors are the
numeric form of embeddings, which represent text, images, and other data in
a way that makes similar items lie close together. The example uses
three-dimensional vectors that hold the red, green, and blue components of
five colours, so that the nearest colours are easy to check by eye. Each
step shows the code in every supported language; selecting a language tab
switches every tab on the site to that language.

The example program stores the five colours, and then asks for the three
colours nearest to the vector `[0.9,0.7,0.2]`, which is a muddy orange. The
program prints the colours in order of increasing Euclidean distance:

```text
Colours nearest to [0.9,0.7,0.2]:
1. yellow
2. red
3. white
```

## Preparing the Ingredients

The server needs the pgvector extension installed, and the user that runs
the program needs permission to create extensions; the `pgvector/pgvector`
Docker images include the extension, and most managed PostgreSQL services
offer it. Each example uses the same driver as the
[first recipe](connect_and_query.md), and sends vectors to the server as
text, so no extra library is required. The following table lists each
language's driver, and the optional pgvector client library that converts
vectors to and from native types such as arrays:

| Language   | Driver                                          | pgvector client library |
|------------|-------------------------------------------------|-------------------------|
| Python     | [psycopg 3](https://www.psycopg.org/psycopg3/)  | [pgvector](https://github.com/pgvector/pgvector-python) |
| TypeScript | [node-postgres](https://node-postgres.com/)     | [pgvector](https://github.com/pgvector/pgvector-node) |
| Java       | [pgJDBC](https://jdbc.postgresql.org/)          | [com.pgvector:pgvector](https://github.com/pgvector/pgvector-java) |
| C#         | [Npgsql](https://www.npgsql.org/)               | [Pgvector](https://github.com/pgvector/pgvector-dotnet) |
| Go         | [pgx](https://github.com/jackc/pgx)             | [pgvector-go](https://github.com/pgvector/pgvector-go) |
| Rust       | [rust-postgres](https://github.com/rust-postgres/rust-postgres) | [pgvector](https://github.com/pgvector/pgvector-rust) |
| Ruby       | [ruby-pg](https://github.com/ged/ruby-pg)      | [pgvector](https://github.com/pgvector/pgvector-ruby) |
| C          | [libpq](https://www.postgresql.org/docs/current/libpq.html) | None; use the text format |

The dependency declarations are the same as those of the first recipe,
because the examples add no libraries. The following tabs show the
declaration from each example project:

=== "Python"

    ```text
    # psycopg 3, with the pre-built binary package that bundles libpq.
    psycopg[binary]>=3.2,<4
    ```

=== "TypeScript"

    ```json
    {
      "name": "pgvector-search",
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
variables as the first recipe: `PGHOST`, `PGPORT`, `PGDATABASE`, `PGUSER`,
and `PGPASSWORD`. Each example treats an empty variable as unset, and uses
the default instead. The following tabs show how each program assembles the
connection settings:

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

Each program opens a single connection and uses it for every step, because
a temporary table belongs to one session. The C# program creates an Npgsql
data source and borrows one connection from it. The following tabs show
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
    // OpenConnectionAsync borrows one from the pool. This program borrows a
    // single connection and uses it throughout, because a temporary table
    // belongs to one session.
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

## Creating the Schema

The program enables the extension, creates a table with a `vector(3)`
column, and builds an index on that column. The `CREATE EXTENSION IF NOT
EXISTS` statement does nothing if the extension is already present. The
number in `vector(3)` fixes the dimensions of every value in the column;
the server rejects a vector with any other number of elements. The table is
`TEMPORARY`, so it disappears when the session ends and the program can run
repeatedly.

The index uses the Hierarchical Navigable Small World (HNSW) method with the
`vector_l2_ops` operator class, which matches the `<->` operator that
measures Euclidean (L2) distance. Use `vector_cosine_ops` for cosine
distance, or `vector_ip_ops` for inner product, if the search uses the
`<=>` or `<#>` operator instead. An HNSW index is approximate: it trades a
small chance of missing a true neighbour for much faster searches on large
tables. The five rows in this example are too few for that to matter, and
the planner may simply scan the table, so the program always prints the
exact order. The following tabs show the schema statements for
each language:

=== "Python"

    ```python
    def create_schema(conn: psycopg.Connection) -> None:
        """Enables pgvector and creates a temporary table of colours."""
        conn.execute("CREATE EXTENSION IF NOT EXISTS vector")
    
        # vector(3) fixes the number of dimensions, one for each of the red,
        # green, and blue components. The temporary table disappears when the
        # session ends, so the program can run repeatedly.
        conn.execute(
            "CREATE TEMPORARY TABLE colours ("
            "name text PRIMARY KEY, rgb vector(3) NOT NULL)"
        )
    
        # An HNSW index speeds up nearest-neighbour searches; vector_l2_ops
        # matches the <-> (Euclidean distance) operator used by the search.
        conn.execute("CREATE INDEX ON colours USING hnsw (rgb vector_l2_ops)")
    ```

=== "TypeScript"

    ```typescript
    // Enables pgvector and creates a temporary table of colours.
    async function createSchema(client: pg.Client): Promise<void> {
      await client.query("CREATE EXTENSION IF NOT EXISTS vector");
    
      // vector(3) fixes the number of dimensions, one for each of the red,
      // green, and blue components. The temporary table disappears when the
      // session ends, so the program can run repeatedly.
      await client.query(
        "CREATE TEMPORARY TABLE colours (" +
          "name text PRIMARY KEY, rgb vector(3) NOT NULL)",
      );
    
      // An HNSW index speeds up nearest-neighbour searches; vector_l2_ops
      // matches the <-> (Euclidean distance) operator used by the search.
      await client.query("CREATE INDEX ON colours USING hnsw (rgb vector_l2_ops)");
    }
    ```

=== "Java"

    ```java
    /** Enables pgvector and creates a temporary table of colours. */
    static void createSchema(Connection conn) throws SQLException {
        // vector(3) fixes the number of dimensions, one for each of the
        // red, green, and blue components. The temporary table disappears
        // when the session ends, so the program can run repeatedly. An
        // HNSW index speeds up nearest-neighbour searches; vector_l2_ops
        // matches the <-> (Euclidean distance) operator used by the
        // search.
        try (Statement stmt = conn.createStatement()) {
            stmt.execute("CREATE EXTENSION IF NOT EXISTS vector");
            stmt.execute("CREATE TEMPORARY TABLE colours ("
                    + "name text PRIMARY KEY, rgb vector(3) NOT NULL)");
            stmt.execute(
                "CREATE INDEX ON colours USING hnsw (rgb vector_l2_ops)");
        }
    }
    ```

=== "C#"

    ```csharp
    // Enables pgvector and creates a temporary table of colours.
    static async Task CreateSchemaAsync(NpgsqlConnection conn)
    {
        // vector(3) fixes the number of dimensions, one for each of the red,
        // green, and blue components. The temporary table disappears when the
        // session ends, so the program can run repeatedly. An HNSW index
        // speeds up nearest-neighbour searches; vector_l2_ops matches the <->
        // (Euclidean distance) operator used by the search.
        string[] statements =
        [
            "CREATE EXTENSION IF NOT EXISTS vector",
            "CREATE TEMPORARY TABLE colours (" +
                "name text PRIMARY KEY, rgb vector(3) NOT NULL)",
            "CREATE INDEX ON colours USING hnsw (rgb vector_l2_ops)",
        ];
        foreach (var statement in statements)
        {
            await using var cmd = new NpgsqlCommand(statement, conn);
            await cmd.ExecuteNonQueryAsync();
        }
    }
    ```

=== "Go"

    ```go
    // createSchema enables pgvector and creates a temporary table of colours.
    func createSchema(ctx context.Context, conn *pgx.Conn) error {
    	// vector(3) fixes the number of dimensions, one for each of the red,
    	// green, and blue components. The temporary table disappears when the
    	// session ends, so the program can run repeatedly. An HNSW index
    	// speeds up nearest-neighbour searches; vector_l2_ops matches the <->
    	// (Euclidean distance) operator used by the search.
    	statements := []string{
    		"CREATE EXTENSION IF NOT EXISTS vector",
    		"CREATE TEMPORARY TABLE colours (" +
    			"name text PRIMARY KEY, rgb vector(3) NOT NULL)",
    		"CREATE INDEX ON colours USING hnsw (rgb vector_l2_ops)",
    	}
    	for _, statement := range statements {
    		if _, err := conn.Exec(ctx, statement); err != nil {
    			return fmt.Errorf("schema setup failed: %w", err)
    		}
    	}
    	return nil
    }
    
    ```

=== "Rust"

    ```rust
    /// Enables pgvector and creates a temporary table of colours.
    fn create_schema(client: &mut Client) -> Result<(), postgres::Error> {
        // vector(3) fixes the number of dimensions, one for each of the red,
        // green, and blue components. The temporary table disappears when the
        // session ends, so the program can run repeatedly. An HNSW index
        // speeds up nearest-neighbour searches; vector_l2_ops matches the <->
        // (Euclidean distance) operator used by the search. batch_execute runs
        // statements that take no parameters.
        client.batch_execute(
            "CREATE EXTENSION IF NOT EXISTS vector;
             CREATE TEMPORARY TABLE colours (
                 name text PRIMARY KEY, rgb vector(3) NOT NULL);
             CREATE INDEX ON colours USING hnsw (rgb vector_l2_ops)",
        )
    }
    ```

=== "Ruby"

    ```ruby
    # Enables pgvector and creates a temporary table of colours.
    def create_schema(conn)
      conn.exec("CREATE EXTENSION IF NOT EXISTS vector")
    
      # vector(3) fixes the number of dimensions, one for each of the red,
      # green, and blue components. The temporary table disappears when the
      # session ends, so the program can run repeatedly.
      conn.exec("CREATE TEMPORARY TABLE colours (" \
                "name text PRIMARY KEY, rgb vector(3) NOT NULL)")
    
      # An HNSW index speeds up nearest-neighbour searches; vector_l2_ops
      # matches the <-> (Euclidean distance) operator used by the search.
      conn.exec("CREATE INDEX ON colours USING hnsw (rgb vector_l2_ops)")
    end
    ```

=== "C"

    ```c
    /*
     * Enable pgvector and create a temporary table of colours, returning true
     * on success. vector(3) fixes the number of dimensions, one for each of
     * the red, green, and blue components. The temporary table disappears
     * when the session ends, so the program can run repeatedly. An HNSW index
     * speeds up nearest-neighbour searches; vector_l2_ops matches the <->
     * (Euclidean distance) operator used by the search.
     */
    static bool
    create_schema(PGconn *conn)
    {
        static const char *const statements[] = {
            "CREATE EXTENSION IF NOT EXISTS vector",
            "CREATE TEMPORARY TABLE colours ("
            "name text PRIMARY KEY, rgb vector(3) NOT NULL)",
            "CREATE INDEX ON colours USING hnsw (rgb vector_l2_ops)",
        };
    
        for (size_t i = 0; i < sizeof(statements) / sizeof(statements[0]); i++)
        {
            PGresult *res = PQexec(conn, statements[i]);
            bool ok = PQresultStatus(res) == PGRES_COMMAND_OK;
    
            PQclear(res);
            if (!ok)
                return false;
        }
        return true;
    }
    ```

## Inserting Vectors

Each program inserts the five colours one row at a time. A vector is
written as text in the form `[x,y,z]`, which each program passes as an
ordinary text parameter and converts on the server with a `::vector` cast.
This approach needs no pgvector client library, and the same statement
works in every language. The Rust program writes `::text::vector`, because
the rust-postgres driver checks the type of each parameter against the Rust
value and refuses to send a string as a `vector`; the `::text` cast declares
the parameter as text first. The following tabs show how each program
inserts the rows:

=== "Python"

    ```python
    def insert_colours(conn: psycopg.Connection) -> None:
        """Stores five colours, each as a vector of its RGB components."""
        colours = [
            ("red", "[1,0,0]"),
            ("green", "[0,1,0]"),
            ("blue", "[0,0,1]"),
            ("yellow", "[1,1,0]"),
            ("white", "[1,1,1]"),
        ]
        with conn.cursor() as cur:
            # A vector travels as text in pgvector's [x,y,z] format, and the
            # ::vector cast converts it on the server, so the driver needs no
            # vector-specific support.
            cur.executemany(
                "INSERT INTO colours (name, rgb) VALUES (%s, %s::vector)",
                colours,
            )
    ```

=== "TypeScript"

    ```typescript
    // Stores five colours, each as a vector of its RGB components.
    async function insertColours(client: pg.Client): Promise<void> {
      const colours: [string, string][] = [
        ["red", "[1,0,0]"],
        ["green", "[0,1,0]"],
        ["blue", "[0,0,1]"],
        ["yellow", "[1,1,0]"],
        ["white", "[1,1,1]"],
      ];
      for (const [name, rgb] of colours) {
        // A vector travels as text in pgvector's [x,y,z] format, and the
        // ::vector cast converts it on the server, so the driver needs no
        // vector-specific support.
        await client.query(
          "INSERT INTO colours (name, rgb) VALUES ($1, $2::vector)",
          [name, rgb],
        );
      }
    }
    ```

=== "Java"

    ```java
    /** Stores five colours, each as a vector of its RGB components. */
    static void insertColours(Connection conn) throws SQLException {
        String[][] colours = {
            {"red", "[1,0,0]"},
            {"green", "[0,1,0]"},
            {"blue", "[0,0,1]"},
            {"yellow", "[1,1,0]"},
            {"white", "[1,1,1]"},
        };
    
        // A vector travels as text in pgvector's [x,y,z] format, and the
        // ::vector cast converts it on the server, so the driver needs no
        // vector-specific support.
        String sql =
            "INSERT INTO colours (name, rgb) VALUES (?, ?::vector)";
        try (PreparedStatement stmt = conn.prepareStatement(sql)) {
            for (String[] colour : colours) {
                stmt.setString(1, colour[0]);
                stmt.setString(2, colour[1]);
                stmt.executeUpdate();
            }
        }
    }
    ```

=== "C#"

    ```csharp
    // Stores five colours, each as a vector of its RGB components.
    static async Task InsertColoursAsync(NpgsqlConnection conn)
    {
        (string Name, string Rgb)[] colours =
        [
            ("red", "[1,0,0]"),
            ("green", "[0,1,0]"),
            ("blue", "[0,0,1]"),
            ("yellow", "[1,1,0]"),
            ("white", "[1,1,1]"),
        ];
        foreach (var (name, rgb) in colours)
        {
            // A vector travels as text in pgvector's [x,y,z] format, and the
            // ::vector cast converts it on the server, so Npgsql needs no
            // vector-specific support. Positional parameters are written $1,
            // $2, and so on.
            await using var cmd = new NpgsqlCommand(
                "INSERT INTO colours (name, rgb) VALUES ($1, $2::vector)", conn)
            {
                Parameters = { new() { Value = name }, new() { Value = rgb } },
            };
            await cmd.ExecuteNonQueryAsync();
        }
    }
    ```

=== "Go"

    ```go
    // insertColours stores five colours, each as a vector of its RGB
    // components.
    func insertColours(ctx context.Context, conn *pgx.Conn) error {
    	colours := [][2]string{
    		{"red", "[1,0,0]"},
    		{"green", "[0,1,0]"},
    		{"blue", "[0,0,1]"},
    		{"yellow", "[1,1,0]"},
    		{"white", "[1,1,1]"},
    	}
    	for _, colour := range colours {
    		// A vector travels as text in pgvector's [x,y,z] format, and the
    		// ::vector cast converts it on the server, so the driver needs no
    		// vector-specific support.
    		_, err := conn.Exec(ctx,
    			"INSERT INTO colours (name, rgb) VALUES ($1, $2::vector)",
    			colour[0], colour[1])
    		if err != nil {
    			return fmt.Errorf("insert failed: %w", err)
    		}
    	}
    	return nil
    }
    
    ```

=== "Rust"

    ```rust
    /// Stores five colours, each as a vector of its RGB components.
    fn insert_colours(client: &mut Client) -> Result<(), postgres::Error> {
        let colours = [
            ("red", "[1,0,0]"),
            ("green", "[0,1,0]"),
            ("blue", "[0,0,1]"),
            ("yellow", "[1,1,0]"),
            ("white", "[1,1,1]"),
        ];
        for (name, rgb) in colours {
            // A vector travels as text in pgvector's [x,y,z] format, and the
            // casts convert it on the server, so the driver needs no
            // vector-specific support. The driver checks parameter types, so
            // ::text declares the parameter as text before ::vector converts
            // it.
            client.execute(
                "INSERT INTO colours (name, rgb) VALUES ($1, $2::text::vector)",
                &[&name, &rgb],
            )?;
        }
        Ok(())
    }
    ```

=== "Ruby"

    ```ruby
    # Stores five colours, each as a vector of its RGB components.
    def insert_colours(conn)
      colours = [
        ["red", "[1,0,0]"],
        ["green", "[0,1,0]"],
        ["blue", "[0,0,1]"],
        ["yellow", "[1,1,0]"],
        ["white", "[1,1,1]"]
      ]
      colours.each do |name, rgb|
        # A vector travels as text in pgvector's [x,y,z] format, and the
        # ::vector cast converts it on the server, so the gem needs no
        # vector-specific support.
        conn.exec_params(
          "INSERT INTO colours (name, rgb) VALUES ($1, $2::vector)",
          [name, rgb]
        )
      end
    end
    ```

=== "C"

    ```c
    /* Store five colours, each as a vector of its RGB components. */
    static bool
    insert_colours(PGconn *conn)
    {
        static const char *const colours[][2] = {
            {"red", "[1,0,0]"},
            {"green", "[0,1,0]"},
            {"blue", "[0,0,1]"},
            {"yellow", "[1,1,0]"},
            {"white", "[1,1,1]"},
        };
    
        for (size_t i = 0; i < sizeof(colours) / sizeof(colours[0]); i++)
        {
            /*
             * A vector travels as text in pgvector's [x,y,z] format, and the
             * ::vector cast converts it on the server, so libpq needs no
             * vector-specific support.
             */
            PGresult *res = PQexecParams(conn,
                                         "INSERT INTO colours (name, rgb) "
                                         "VALUES ($1, $2::vector)",
                                         2,     /* number of parameters */
                                         NULL,  /* let the server infer types */
                                         colours[i],
                                         NULL,  /* text parameters need no lengths */
                                         NULL,  /* all parameters are text */
                                         0);    /* ask for text results */
            bool ok = PQresultStatus(res) == PGRES_COMMAND_OK;
    
            PQclear(res);
            if (!ok)
                return false;
        }
        return true;
    }
    ```

## Searching for the Nearest Vectors

The search orders the rows by their distance from the query vector, and
returns the first three. PostgreSQL can use the HNSW index to answer a query
of this shape, which has an `ORDER BY` on the distance operator and a
`LIMIT`. The query vector is another text parameter with a `::vector` cast,
and the limit is a parameter too. The C program sends every parameter as
text, so it converts the limit to a string first. The following tabs show
how each program runs the search and reads the names in order:

=== "Python"

    ```python
    def nearest_colours(conn: psycopg.Connection, target: str,
                        count: int) -> list[str]:
        """Returns the names of the colours nearest to the target vector."""
        # <-> is the Euclidean (L2) distance operator, so ordering by it puts
        # the nearest colour first.
        rows = conn.execute(
            "SELECT name FROM colours ORDER BY rgb <-> %s::vector LIMIT %s",
            (target, count),
        ).fetchall()
        return [row[0] for row in rows]
    ```

=== "TypeScript"

    ```typescript
    // Returns the names of the colours nearest to the target vector.
    async function nearestColours(
      client: pg.Client,
      target: string,
      count: number,
    ): Promise<string[]> {
      // <-> is the Euclidean (L2) distance operator, so ordering by it puts
      // the nearest colour first.
      const result = await client.query<{ name: string }>(
        "SELECT name FROM colours ORDER BY rgb <-> $1::vector LIMIT $2",
        [target, count],
      );
      return result.rows.map((row) => row.name);
    }
    ```

=== "Java"

    ```java
    /** Returns the names of the colours nearest to the target vector. */
    static List<String> nearestColours(
            Connection conn, String target, int count) throws SQLException {
        // <-> is the Euclidean (L2) distance operator, so ordering by it
        // puts the nearest colour first.
        String sql = "SELECT name FROM colours "
                + "ORDER BY rgb <-> ?::vector LIMIT ?";
    
        // try-with-resources closes the statement and the result set when
        // each block exits, whether or not an error occurred.
        try (PreparedStatement stmt = conn.prepareStatement(sql)) {
            stmt.setString(1, target);
            stmt.setInt(2, count);
    
            try (ResultSet rs = stmt.executeQuery()) {
                List<String> names = new ArrayList<>();
                while (rs.next()) {
                    names.add(rs.getString(1));
                }
                return names;
            }
        }
    }
    ```

=== "C#"

    ```csharp
    // Returns the names of the colours nearest to the target vector.
    static async Task<List<string>> NearestColoursAsync(
        NpgsqlConnection conn, string target, int count)
    {
        // <-> is the Euclidean (L2) distance operator, so ordering by it puts
        // the nearest colour first.
        await using var cmd = new NpgsqlCommand(
            "SELECT name FROM colours ORDER BY rgb <-> $1::vector LIMIT $2",
            conn)
        {
            Parameters = { new() { Value = target }, new() { Value = count } },
        };
    
        var names = new List<string>();
        await using var reader = await cmd.ExecuteReaderAsync();
        while (await reader.ReadAsync())
        {
            names.Add(reader.GetString(0));
        }
        return names;
    }
    ```

=== "Go"

    ```go
    // nearestColours returns the names of the colours nearest to the target
    // vector.
    func nearestColours(ctx context.Context, conn *pgx.Conn, target string, count int) ([]string, error) {
    	// <-> is the Euclidean (L2) distance operator, so ordering by it puts
    	// the nearest colour first.
    	rows, err := conn.Query(ctx,
    		"SELECT name FROM colours ORDER BY rgb <-> $1::vector LIMIT $2",
    		target, count)
    	if err != nil {
    		return nil, fmt.Errorf("query failed: %w", err)
    	}
    
    	// CollectRows reads every row, and closes the result when it is done.
    	names, err := pgx.CollectRows(rows, pgx.RowTo[string])
    	if err != nil {
    		return nil, fmt.Errorf("query failed: %w", err)
    	}
    	return names, nil
    }
    
    ```

=== "Rust"

    ```rust
    /// Returns the names of the colours nearest to the target vector.
    fn nearest_colours(
        client: &mut Client,
        target: &str,
        count: i64,
    ) -> Result<Vec<String>, postgres::Error> {
        // <-> is the Euclidean (L2) distance operator, so ordering by it puts
        // the nearest colour first. As when inserting, ::text declares the
        // parameter as text before ::vector converts it. LIMIT takes a
        // bigint, which maps to i64.
        let rows = client.query(
            "SELECT name FROM colours ORDER BY rgb <-> $1::text::vector LIMIT $2",
            &[&target, &count],
        )?;
        Ok(rows.iter().map(|row| row.get(0)).collect())
    }
    ```

=== "Ruby"

    ```ruby
    # Returns the names of the colours nearest to the target vector.
    def nearest_colours(conn, target, count)
      # <-> is the Euclidean (L2) distance operator, so ordering by it puts
      # the nearest colour first.
      result = conn.exec_params(
        "SELECT name FROM colours ORDER BY rgb <-> $1::vector LIMIT $2",
        [target, count]
      )
      result.map { |row| row["name"] }
    end
    ```

=== "C"

    ```c
    /*
     * Print the names of the colours nearest to the target vector, and return
     * true on success. On failure, PQerrorMessage() describes the error.
     */
    static bool
    print_nearest_colours(PGconn *conn, const char *target, int count)
    {
        char limit[16];
        const char *params[] = {target, limit};
        PGresult *res;
        bool ok;
    
        /* Every parameter is sent as text, including the limit. */
        snprintf(limit, sizeof(limit), "%d", count);
    
        /*
         * <-> is the Euclidean (L2) distance operator, so ordering by it puts
         * the nearest colour first.
         */
        res = PQexecParams(conn,
                           "SELECT name FROM colours "
                           "ORDER BY rgb <-> $1::vector LIMIT $2",
                           2,     /* number of parameters */
                           NULL,  /* let the server infer types */
                           params,
                           NULL,  /* text parameters need no lengths */
                           NULL,  /* all parameters are text */
                           0);    /* ask for text results */
        ok = PQresultStatus(res) == PGRES_TUPLES_OK;
    
        if (ok)
        {
            printf("Colours nearest to %s:\n", target);
            for (int row = 0; row < PQntuples(res); row++)
                printf("%d. %s\n", row + 1, PQgetvalue(res, row, 0));
        }
    
        /* PQclear() frees the result, and accepts NULL. */
        PQclear(res);
        return ok;
    }
    ```

## Handling Errors and Closing the Connection

The main part of each program calls the functions from the previous steps,
and prints the colours with their rank. The program reports any connection
or query failure on `stderr`, and then exits with a non-zero status; this
includes the error that the server raises if the extension is not available.
Each program closes the connection when the work completes or fails, using
the same mechanism as the first recipe. The following tabs show the main
part of each program:

=== "Python"

    ```python
    def main() -> int:
        target = "[0.9,0.7,0.2]"
        try:
            # The with block closes the connection when it exits, whether or
            # not an error occurred.
            with connect() as conn:
                create_schema(conn)
                insert_colours(conn)
                print(f"Colours nearest to {target}:")
                for rank, name in enumerate(nearest_colours(conn, target, 3), 1):
                    print(f"{rank}. {name}")
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
      const target = "[0.9,0.7,0.2]";
      let client: pg.Client | undefined;
      try {
        client = await connect();
        await createSchema(client);
        await insertColours(client);
    
        console.log(`Colours nearest to ${target}:`);
        const names = await nearestColours(client, target, 3);
        names.forEach((name, i) => console.log(`${i + 1}. ${name}`));
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
        String target = "[0.9,0.7,0.2]";
    
        // try-with-resources closes the connection when the block exits,
        // whether or not an error occurred.
        try (Connection conn = connect()) {
            createSchema(conn);
            insertColours(conn);
    
            System.out.println("Colours nearest to " + target + ":");
            List<String> names = nearestColours(conn, target, 3);
            for (int i = 0; i < names.size(); i++) {
                System.out.println((i + 1) + ". " + names.get(i));
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
        const string target = "[0.9,0.7,0.2]";
    
        // await using disposes of the data source, and returns the connection
        // to the pool, when the block exits, whether or not an error occurred.
        await using var dataSource = CreateDataSource();
        await using var conn = await dataSource.OpenConnectionAsync();
        await CreateSchemaAsync(conn);
        await InsertColoursAsync(conn);
    
        Console.WriteLine($"Colours nearest to {target}:");
        var names = await NearestColoursAsync(conn, target, 3);
        for (var i = 0; i < names.Count; i++)
        {
            Console.WriteLine($"{i + 1}. {names[i]}");
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
    // run connects, stores the colours, searches them, and prints the result,
    // returning any error to the caller.
    func run(ctx context.Context) error {
    	conn, err := connect(ctx)
    	if err != nil {
    		return err
    	}
    	// The deferred call closes the connection when run() returns, whether
    	// or not an error occurred.
    	defer conn.Close(ctx)
    
    	if err := createSchema(ctx, conn); err != nil {
    		return err
    	}
    	if err := insertColours(ctx, conn); err != nil {
    		return err
    	}
    
    	target := "[0.9,0.7,0.2]"
    	names, err := nearestColours(ctx, conn, target, 3)
    	if err != nil {
    		return err
    	}
    
    	fmt.Printf("Colours nearest to %s:\n", target)
    	for i, name := range names {
    		fmt.Printf("%d. %s\n", i+1, name)
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
    /// Connects, stores the colours, searches them, and prints the result. The
    /// ? operator returns any error to the caller.
    fn run() -> Result<(), postgres::Error> {
        let target = "[0.9,0.7,0.2]";
        let mut client = connect()?;
        create_schema(&mut client)?;
        insert_colours(&mut client)?;
    
        println!("Colours nearest to {target}:");
        for (i, name) in nearest_colours(&mut client, target, 3)?.iter().enumerate() {
            println!("{}. {name}", i + 1);
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
      target = "[0.9,0.7,0.2]"
      conn = connect
      create_schema(conn)
      insert_colours(conn)
    
      puts "Colours nearest to #{target}:"
      nearest_colours(conn, target, 3).each_with_index do |name, i|
        puts "#{i + 1}. #{name}"
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
        PGconn *conn = connect_to_server();
    
        /* The || operator skips each step if an earlier one failed. */
        if (PQstatus(conn) != CONNECTION_OK ||
            !create_schema(conn) ||
            !insert_colours(conn) ||
            !print_nearest_colours(conn, "[0.9,0.7,0.2]", 3))
        {
            fprintf(stderr, "Database error: %s", PQerrorMessage(conn));
        }
        else
        {
            status = EXIT_SUCCESS;
        }
    
        /* Close the connection whether or not an error occurred. */
        PQfinish(conn);
        return status;
    }
    ```

## Running the Example

The complete project for each language is available in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/postgresql/pgvector_search).
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
    Storing and searching vectors with pgvector, using psycopg 3.
    
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
    
    
    def create_schema(conn: psycopg.Connection) -> None:
        """Enables pgvector and creates a temporary table of colours."""
        conn.execute("CREATE EXTENSION IF NOT EXISTS vector")
    
        # vector(3) fixes the number of dimensions, one for each of the red,
        # green, and blue components. The temporary table disappears when the
        # session ends, so the program can run repeatedly.
        conn.execute(
            "CREATE TEMPORARY TABLE colours ("
            "name text PRIMARY KEY, rgb vector(3) NOT NULL)"
        )
    
        # An HNSW index speeds up nearest-neighbour searches; vector_l2_ops
        # matches the <-> (Euclidean distance) operator used by the search.
        conn.execute("CREATE INDEX ON colours USING hnsw (rgb vector_l2_ops)")
    
    
    def insert_colours(conn: psycopg.Connection) -> None:
        """Stores five colours, each as a vector of its RGB components."""
        colours = [
            ("red", "[1,0,0]"),
            ("green", "[0,1,0]"),
            ("blue", "[0,0,1]"),
            ("yellow", "[1,1,0]"),
            ("white", "[1,1,1]"),
        ]
        with conn.cursor() as cur:
            # A vector travels as text in pgvector's [x,y,z] format, and the
            # ::vector cast converts it on the server, so the driver needs no
            # vector-specific support.
            cur.executemany(
                "INSERT INTO colours (name, rgb) VALUES (%s, %s::vector)",
                colours,
            )
    
    
    def nearest_colours(conn: psycopg.Connection, target: str,
                        count: int) -> list[str]:
        """Returns the names of the colours nearest to the target vector."""
        # <-> is the Euclidean (L2) distance operator, so ordering by it puts
        # the nearest colour first.
        rows = conn.execute(
            "SELECT name FROM colours ORDER BY rgb <-> %s::vector LIMIT %s",
            (target, count),
        ).fetchall()
        return [row[0] for row in rows]
    
    
    def main() -> int:
        target = "[0.9,0.7,0.2]"
        try:
            # The with block closes the connection when it exits, whether or
            # not an error occurred.
            with connect() as conn:
                create_schema(conn)
                insert_colours(conn)
                print(f"Colours nearest to {target}:")
                for rank, name in enumerate(nearest_colours(conn, target, 3), 1):
                    print(f"{rank}. {name}")
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
     * Storing and searching vectors with pgvector, using node-postgres.
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
    
    // Enables pgvector and creates a temporary table of colours.
    async function createSchema(client: pg.Client): Promise<void> {
      await client.query("CREATE EXTENSION IF NOT EXISTS vector");
    
      // vector(3) fixes the number of dimensions, one for each of the red,
      // green, and blue components. The temporary table disappears when the
      // session ends, so the program can run repeatedly.
      await client.query(
        "CREATE TEMPORARY TABLE colours (" +
          "name text PRIMARY KEY, rgb vector(3) NOT NULL)",
      );
    
      // An HNSW index speeds up nearest-neighbour searches; vector_l2_ops
      // matches the <-> (Euclidean distance) operator used by the search.
      await client.query("CREATE INDEX ON colours USING hnsw (rgb vector_l2_ops)");
    }
    
    // Stores five colours, each as a vector of its RGB components.
    async function insertColours(client: pg.Client): Promise<void> {
      const colours: [string, string][] = [
        ["red", "[1,0,0]"],
        ["green", "[0,1,0]"],
        ["blue", "[0,0,1]"],
        ["yellow", "[1,1,0]"],
        ["white", "[1,1,1]"],
      ];
      for (const [name, rgb] of colours) {
        // A vector travels as text in pgvector's [x,y,z] format, and the
        // ::vector cast converts it on the server, so the driver needs no
        // vector-specific support.
        await client.query(
          "INSERT INTO colours (name, rgb) VALUES ($1, $2::vector)",
          [name, rgb],
        );
      }
    }
    
    // Returns the names of the colours nearest to the target vector.
    async function nearestColours(
      client: pg.Client,
      target: string,
      count: number,
    ): Promise<string[]> {
      // <-> is the Euclidean (L2) distance operator, so ordering by it puts
      // the nearest colour first.
      const result = await client.query<{ name: string }>(
        "SELECT name FROM colours ORDER BY rgb <-> $1::vector LIMIT $2",
        [target, count],
      );
      return result.rows.map((row) => row.name);
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
      const target = "[0.9,0.7,0.2]";
      let client: pg.Client | undefined;
      try {
        client = await connect();
        await createSchema(client);
        await insertColours(client);
    
        console.log(`Colours nearest to ${target}:`);
        const names = await nearestColours(client, target, 3);
        names.forEach((name, i) => console.log(`${i + 1}. ${name}`));
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
     * Storing and searching vectors with pgvector, using JDBC and the
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
    
        /** Enables pgvector and creates a temporary table of colours. */
        static void createSchema(Connection conn) throws SQLException {
            // vector(3) fixes the number of dimensions, one for each of the
            // red, green, and blue components. The temporary table disappears
            // when the session ends, so the program can run repeatedly. An
            // HNSW index speeds up nearest-neighbour searches; vector_l2_ops
            // matches the <-> (Euclidean distance) operator used by the
            // search.
            try (Statement stmt = conn.createStatement()) {
                stmt.execute("CREATE EXTENSION IF NOT EXISTS vector");
                stmt.execute("CREATE TEMPORARY TABLE colours ("
                        + "name text PRIMARY KEY, rgb vector(3) NOT NULL)");
                stmt.execute(
                    "CREATE INDEX ON colours USING hnsw (rgb vector_l2_ops)");
            }
        }
    
        /** Stores five colours, each as a vector of its RGB components. */
        static void insertColours(Connection conn) throws SQLException {
            String[][] colours = {
                {"red", "[1,0,0]"},
                {"green", "[0,1,0]"},
                {"blue", "[0,0,1]"},
                {"yellow", "[1,1,0]"},
                {"white", "[1,1,1]"},
            };
    
            // A vector travels as text in pgvector's [x,y,z] format, and the
            // ::vector cast converts it on the server, so the driver needs no
            // vector-specific support.
            String sql =
                "INSERT INTO colours (name, rgb) VALUES (?, ?::vector)";
            try (PreparedStatement stmt = conn.prepareStatement(sql)) {
                for (String[] colour : colours) {
                    stmt.setString(1, colour[0]);
                    stmt.setString(2, colour[1]);
                    stmt.executeUpdate();
                }
            }
        }
    
        /** Returns the names of the colours nearest to the target vector. */
        static List<String> nearestColours(
                Connection conn, String target, int count) throws SQLException {
            // <-> is the Euclidean (L2) distance operator, so ordering by it
            // puts the nearest colour first.
            String sql = "SELECT name FROM colours "
                    + "ORDER BY rgb <-> ?::vector LIMIT ?";
    
            // try-with-resources closes the statement and the result set when
            // each block exits, whether or not an error occurred.
            try (PreparedStatement stmt = conn.prepareStatement(sql)) {
                stmt.setString(1, target);
                stmt.setInt(2, count);
    
                try (ResultSet rs = stmt.executeQuery()) {
                    List<String> names = new ArrayList<>();
                    while (rs.next()) {
                        names.add(rs.getString(1));
                    }
                    return names;
                }
            }
        }
    
        public static void main(String[] args) {
            String target = "[0.9,0.7,0.2]";
    
            // try-with-resources closes the connection when the block exits,
            // whether or not an error occurred.
            try (Connection conn = connect()) {
                createSchema(conn);
                insertColours(conn);
    
                System.out.println("Colours nearest to " + target + ":");
                List<String> names = nearestColours(conn, target, 3);
                for (int i = 0; i < names.size(); i++) {
                    System.out.println((i + 1) + ". " + names.get(i));
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
     * Storing and searching vectors with pgvector, using Npgsql.
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
    // OpenConnectionAsync borrows one from the pool. This program borrows a
    // single connection and uses it throughout, because a temporary table
    // belongs to one session.
    static NpgsqlDataSource CreateDataSource() =>
        NpgsqlDataSource.Create(ConnectionString());
    
    // Enables pgvector and creates a temporary table of colours.
    static async Task CreateSchemaAsync(NpgsqlConnection conn)
    {
        // vector(3) fixes the number of dimensions, one for each of the red,
        // green, and blue components. The temporary table disappears when the
        // session ends, so the program can run repeatedly. An HNSW index
        // speeds up nearest-neighbour searches; vector_l2_ops matches the <->
        // (Euclidean distance) operator used by the search.
        string[] statements =
        [
            "CREATE EXTENSION IF NOT EXISTS vector",
            "CREATE TEMPORARY TABLE colours (" +
                "name text PRIMARY KEY, rgb vector(3) NOT NULL)",
            "CREATE INDEX ON colours USING hnsw (rgb vector_l2_ops)",
        ];
        foreach (var statement in statements)
        {
            await using var cmd = new NpgsqlCommand(statement, conn);
            await cmd.ExecuteNonQueryAsync();
        }
    }
    
    // Stores five colours, each as a vector of its RGB components.
    static async Task InsertColoursAsync(NpgsqlConnection conn)
    {
        (string Name, string Rgb)[] colours =
        [
            ("red", "[1,0,0]"),
            ("green", "[0,1,0]"),
            ("blue", "[0,0,1]"),
            ("yellow", "[1,1,0]"),
            ("white", "[1,1,1]"),
        ];
        foreach (var (name, rgb) in colours)
        {
            // A vector travels as text in pgvector's [x,y,z] format, and the
            // ::vector cast converts it on the server, so Npgsql needs no
            // vector-specific support. Positional parameters are written $1,
            // $2, and so on.
            await using var cmd = new NpgsqlCommand(
                "INSERT INTO colours (name, rgb) VALUES ($1, $2::vector)", conn)
            {
                Parameters = { new() { Value = name }, new() { Value = rgb } },
            };
            await cmd.ExecuteNonQueryAsync();
        }
    }
    
    // Returns the names of the colours nearest to the target vector.
    static async Task<List<string>> NearestColoursAsync(
        NpgsqlConnection conn, string target, int count)
    {
        // <-> is the Euclidean (L2) distance operator, so ordering by it puts
        // the nearest colour first.
        await using var cmd = new NpgsqlCommand(
            "SELECT name FROM colours ORDER BY rgb <-> $1::vector LIMIT $2",
            conn)
        {
            Parameters = { new() { Value = target }, new() { Value = count } },
        };
    
        var names = new List<string>();
        await using var reader = await cmd.ExecuteReaderAsync();
        while (await reader.ReadAsync())
        {
            names.Add(reader.GetString(0));
        }
        return names;
    }
    
    try
    {
        const string target = "[0.9,0.7,0.2]";
    
        // await using disposes of the data source, and returns the connection
        // to the pool, when the block exits, whether or not an error occurred.
        await using var dataSource = CreateDataSource();
        await using var conn = await dataSource.OpenConnectionAsync();
        await CreateSchemaAsync(conn);
        await InsertColoursAsync(conn);
    
        Console.WriteLine($"Colours nearest to {target}:");
        var names = await NearestColoursAsync(conn, target, 3);
        for (var i = 0; i < names.Count; i++)
        {
            Console.WriteLine($"{i + 1}. {names[i]}");
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
    // Storing and searching vectors with pgvector, using pgx.
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
    
    
    // createSchema enables pgvector and creates a temporary table of colours.
    func createSchema(ctx context.Context, conn *pgx.Conn) error {
    	// vector(3) fixes the number of dimensions, one for each of the red,
    	// green, and blue components. The temporary table disappears when the
    	// session ends, so the program can run repeatedly. An HNSW index
    	// speeds up nearest-neighbour searches; vector_l2_ops matches the <->
    	// (Euclidean distance) operator used by the search.
    	statements := []string{
    		"CREATE EXTENSION IF NOT EXISTS vector",
    		"CREATE TEMPORARY TABLE colours (" +
    			"name text PRIMARY KEY, rgb vector(3) NOT NULL)",
    		"CREATE INDEX ON colours USING hnsw (rgb vector_l2_ops)",
    	}
    	for _, statement := range statements {
    		if _, err := conn.Exec(ctx, statement); err != nil {
    			return fmt.Errorf("schema setup failed: %w", err)
    		}
    	}
    	return nil
    }
    
    
    // insertColours stores five colours, each as a vector of its RGB
    // components.
    func insertColours(ctx context.Context, conn *pgx.Conn) error {
    	colours := [][2]string{
    		{"red", "[1,0,0]"},
    		{"green", "[0,1,0]"},
    		{"blue", "[0,0,1]"},
    		{"yellow", "[1,1,0]"},
    		{"white", "[1,1,1]"},
    	}
    	for _, colour := range colours {
    		// A vector travels as text in pgvector's [x,y,z] format, and the
    		// ::vector cast converts it on the server, so the driver needs no
    		// vector-specific support.
    		_, err := conn.Exec(ctx,
    			"INSERT INTO colours (name, rgb) VALUES ($1, $2::vector)",
    			colour[0], colour[1])
    		if err != nil {
    			return fmt.Errorf("insert failed: %w", err)
    		}
    	}
    	return nil
    }
    
    
    // nearestColours returns the names of the colours nearest to the target
    // vector.
    func nearestColours(ctx context.Context, conn *pgx.Conn, target string, count int) ([]string, error) {
    	// <-> is the Euclidean (L2) distance operator, so ordering by it puts
    	// the nearest colour first.
    	rows, err := conn.Query(ctx,
    		"SELECT name FROM colours ORDER BY rgb <-> $1::vector LIMIT $2",
    		target, count)
    	if err != nil {
    		return nil, fmt.Errorf("query failed: %w", err)
    	}
    
    	// CollectRows reads every row, and closes the result when it is done.
    	names, err := pgx.CollectRows(rows, pgx.RowTo[string])
    	if err != nil {
    		return nil, fmt.Errorf("query failed: %w", err)
    	}
    	return names, nil
    }
    
    
    // run connects, stores the colours, searches them, and prints the result,
    // returning any error to the caller.
    func run(ctx context.Context) error {
    	conn, err := connect(ctx)
    	if err != nil {
    		return err
    	}
    	// The deferred call closes the connection when run() returns, whether
    	// or not an error occurred.
    	defer conn.Close(ctx)
    
    	if err := createSchema(ctx, conn); err != nil {
    		return err
    	}
    	if err := insertColours(ctx, conn); err != nil {
    		return err
    	}
    
    	target := "[0.9,0.7,0.2]"
    	names, err := nearestColours(ctx, conn, target, 3)
    	if err != nil {
    		return err
    	}
    
    	fmt.Printf("Colours nearest to %s:\n", target)
    	for i, name := range names {
    		fmt.Printf("%d. %s\n", i+1, name)
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
    // Storing and searching vectors with pgvector, using the postgres crate.
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
    
    /// Enables pgvector and creates a temporary table of colours.
    fn create_schema(client: &mut Client) -> Result<(), postgres::Error> {
        // vector(3) fixes the number of dimensions, one for each of the red,
        // green, and blue components. The temporary table disappears when the
        // session ends, so the program can run repeatedly. An HNSW index
        // speeds up nearest-neighbour searches; vector_l2_ops matches the <->
        // (Euclidean distance) operator used by the search. batch_execute runs
        // statements that take no parameters.
        client.batch_execute(
            "CREATE EXTENSION IF NOT EXISTS vector;
             CREATE TEMPORARY TABLE colours (
                 name text PRIMARY KEY, rgb vector(3) NOT NULL);
             CREATE INDEX ON colours USING hnsw (rgb vector_l2_ops)",
        )
    }
    
    /// Stores five colours, each as a vector of its RGB components.
    fn insert_colours(client: &mut Client) -> Result<(), postgres::Error> {
        let colours = [
            ("red", "[1,0,0]"),
            ("green", "[0,1,0]"),
            ("blue", "[0,0,1]"),
            ("yellow", "[1,1,0]"),
            ("white", "[1,1,1]"),
        ];
        for (name, rgb) in colours {
            // A vector travels as text in pgvector's [x,y,z] format, and the
            // casts convert it on the server, so the driver needs no
            // vector-specific support. The driver checks parameter types, so
            // ::text declares the parameter as text before ::vector converts
            // it.
            client.execute(
                "INSERT INTO colours (name, rgb) VALUES ($1, $2::text::vector)",
                &[&name, &rgb],
            )?;
        }
        Ok(())
    }
    
    /// Returns the names of the colours nearest to the target vector.
    fn nearest_colours(
        client: &mut Client,
        target: &str,
        count: i64,
    ) -> Result<Vec<String>, postgres::Error> {
        // <-> is the Euclidean (L2) distance operator, so ordering by it puts
        // the nearest colour first. As when inserting, ::text declares the
        // parameter as text before ::vector converts it. LIMIT takes a
        // bigint, which maps to i64.
        let rows = client.query(
            "SELECT name FROM colours ORDER BY rgb <-> $1::text::vector LIMIT $2",
            &[&target, &count],
        )?;
        Ok(rows.iter().map(|row| row.get(0)).collect())
    }
    
    /// Connects, stores the colours, searches them, and prints the result. The
    /// ? operator returns any error to the caller.
    fn run() -> Result<(), postgres::Error> {
        let target = "[0.9,0.7,0.2]";
        let mut client = connect()?;
        create_schema(&mut client)?;
        insert_colours(&mut client)?;
    
        println!("Colours nearest to {target}:");
        for (i, name) in nearest_colours(&mut client, target, 3)?.iter().enumerate() {
            println!("{}. {name}", i + 1);
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
    # Storing and searching vectors with pgvector, using the pg gem.
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
    
    # Enables pgvector and creates a temporary table of colours.
    def create_schema(conn)
      conn.exec("CREATE EXTENSION IF NOT EXISTS vector")
    
      # vector(3) fixes the number of dimensions, one for each of the red,
      # green, and blue components. The temporary table disappears when the
      # session ends, so the program can run repeatedly.
      conn.exec("CREATE TEMPORARY TABLE colours (" \
                "name text PRIMARY KEY, rgb vector(3) NOT NULL)")
    
      # An HNSW index speeds up nearest-neighbour searches; vector_l2_ops
      # matches the <-> (Euclidean distance) operator used by the search.
      conn.exec("CREATE INDEX ON colours USING hnsw (rgb vector_l2_ops)")
    end
    
    # Stores five colours, each as a vector of its RGB components.
    def insert_colours(conn)
      colours = [
        ["red", "[1,0,0]"],
        ["green", "[0,1,0]"],
        ["blue", "[0,0,1]"],
        ["yellow", "[1,1,0]"],
        ["white", "[1,1,1]"]
      ]
      colours.each do |name, rgb|
        # A vector travels as text in pgvector's [x,y,z] format, and the
        # ::vector cast converts it on the server, so the gem needs no
        # vector-specific support.
        conn.exec_params(
          "INSERT INTO colours (name, rgb) VALUES ($1, $2::vector)",
          [name, rgb]
        )
      end
    end
    
    # Returns the names of the colours nearest to the target vector.
    def nearest_colours(conn, target, count)
      # <-> is the Euclidean (L2) distance operator, so ordering by it puts
      # the nearest colour first.
      result = conn.exec_params(
        "SELECT name FROM colours ORDER BY rgb <-> $1::vector LIMIT $2",
        [target, count]
      )
      result.map { |row| row["name"] }
    end
    
    begin
      target = "[0.9,0.7,0.2]"
      conn = connect
      create_schema(conn)
      insert_colours(conn)
    
      puts "Colours nearest to #{target}:"
      nearest_colours(conn, target, 3).each_with_index do |name, i|
        puts "#{i + 1}. #{name}"
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
     * Storing and searching vectors with pgvector, using libpq.
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
     * Enable pgvector and create a temporary table of colours, returning true
     * on success. vector(3) fixes the number of dimensions, one for each of
     * the red, green, and blue components. The temporary table disappears
     * when the session ends, so the program can run repeatedly. An HNSW index
     * speeds up nearest-neighbour searches; vector_l2_ops matches the <->
     * (Euclidean distance) operator used by the search.
     */
    static bool
    create_schema(PGconn *conn)
    {
        static const char *const statements[] = {
            "CREATE EXTENSION IF NOT EXISTS vector",
            "CREATE TEMPORARY TABLE colours ("
            "name text PRIMARY KEY, rgb vector(3) NOT NULL)",
            "CREATE INDEX ON colours USING hnsw (rgb vector_l2_ops)",
        };
    
        for (size_t i = 0; i < sizeof(statements) / sizeof(statements[0]); i++)
        {
            PGresult *res = PQexec(conn, statements[i]);
            bool ok = PQresultStatus(res) == PGRES_COMMAND_OK;
    
            PQclear(res);
            if (!ok)
                return false;
        }
        return true;
    }
    
    /* Store five colours, each as a vector of its RGB components. */
    static bool
    insert_colours(PGconn *conn)
    {
        static const char *const colours[][2] = {
            {"red", "[1,0,0]"},
            {"green", "[0,1,0]"},
            {"blue", "[0,0,1]"},
            {"yellow", "[1,1,0]"},
            {"white", "[1,1,1]"},
        };
    
        for (size_t i = 0; i < sizeof(colours) / sizeof(colours[0]); i++)
        {
            /*
             * A vector travels as text in pgvector's [x,y,z] format, and the
             * ::vector cast converts it on the server, so libpq needs no
             * vector-specific support.
             */
            PGresult *res = PQexecParams(conn,
                                         "INSERT INTO colours (name, rgb) "
                                         "VALUES ($1, $2::vector)",
                                         2,     /* number of parameters */
                                         NULL,  /* let the server infer types */
                                         colours[i],
                                         NULL,  /* text parameters need no lengths */
                                         NULL,  /* all parameters are text */
                                         0);    /* ask for text results */
            bool ok = PQresultStatus(res) == PGRES_COMMAND_OK;
    
            PQclear(res);
            if (!ok)
                return false;
        }
        return true;
    }
    
    /*
     * Print the names of the colours nearest to the target vector, and return
     * true on success. On failure, PQerrorMessage() describes the error.
     */
    static bool
    print_nearest_colours(PGconn *conn, const char *target, int count)
    {
        char limit[16];
        const char *params[] = {target, limit};
        PGresult *res;
        bool ok;
    
        /* Every parameter is sent as text, including the limit. */
        snprintf(limit, sizeof(limit), "%d", count);
    
        /*
         * <-> is the Euclidean (L2) distance operator, so ordering by it puts
         * the nearest colour first.
         */
        res = PQexecParams(conn,
                           "SELECT name FROM colours "
                           "ORDER BY rgb <-> $1::vector LIMIT $2",
                           2,     /* number of parameters */
                           NULL,  /* let the server infer types */
                           params,
                           NULL,  /* text parameters need no lengths */
                           NULL,  /* all parameters are text */
                           0);    /* ask for text results */
        ok = PQresultStatus(res) == PGRES_TUPLES_OK;
    
        if (ok)
        {
            printf("Colours nearest to %s:\n", target);
            for (int row = 0; row < PQntuples(res); row++)
                printf("%d. %s\n", row + 1, PQgetvalue(res, row, 0));
        }
    
        /* PQclear() frees the result, and accepts NULL. */
        PQclear(res);
        return ok;
    }
    
    int
    main(void)
    {
        int status = EXIT_FAILURE;
        PGconn *conn = connect_to_server();
    
        /* The || operator skips each step if an earlier one failed. */
        if (PQstatus(conn) != CONNECTION_OK ||
            !create_schema(conn) ||
            !insert_colours(conn) ||
            !print_nearest_colours(conn, "[0.9,0.7,0.2]", 3))
        {
            fprintf(stderr, "Database error: %s", PQerrorMessage(conn));
        }
        else
        {
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

- The [pgvector README](https://github.com/pgvector/pgvector#readme)
  describes the vector types, the distance operators, and the options for
  both the HNSW and IVFFlat indexes.
- The pgvector documentation on
  [querying](https://github.com/pgvector/pgvector#querying) explains how to
  tune `hnsw.ef_search` to trade speed for accuracy.
- The [first recipe](connect_and_query.md) explains the connection settings
  that every example uses.
