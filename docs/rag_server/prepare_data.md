# Preparing Data for the RAG Server

This recipe stores a few documents in PostgreSQL together with their
embeddings, which is the table layout that a pgEdge RAG Server pipeline
reads. The program asks Ollama to turn each document into an embedding, a
list of numbers that captures its meaning, and stores both in a table with a
[pgvector](https://github.com/pgvector/pgvector) column. Each step shows the
code in every supported language; selecting a language tab switches every
tab on the site to that language.

These examples are for pgEdge RAG Server 2.0.0.

The program ends by printing a summary, and then drops its table, so that it
leaves nothing behind:

```text
Embedded 3 documents with nomic-embed-text
Stored 3 rows with 768-dimension embeddings in cookbook_prepare_data
```

## Preparing the Ingredients

The examples need a PostgreSQL server with the pgvector extension installed
(each program runs `CREATE EXTENSION IF NOT EXISTS vector`, which needs a
user with the privilege to create it), and an
[Ollama](https://ollama.com/) server with an embedding model, which you can
fetch with `ollama pull nomic-embed-text`. The documents describe the
fictional Acme Gadget.

The following table lists the library that each example uses to reach
PostgreSQL, and the one that it uses to reach Ollama:

| Language   | PostgreSQL driver                                               | HTTP client                                                                         |
|------------|-----------------------------------------------------------------|-------------------------------------------------------------------------------------|
| Python     | [psycopg](https://www.psycopg.org/psycopg3/)                    | [httpx](https://www.python-httpx.org/)                                              |
| TypeScript | [node-postgres](https://node-postgres.com/)                     | The `fetch` function from Node.js                                                   |
| Java       | [pgJDBC](https://jdbc.postgresql.org/)                          | The `java.net.http` package, with [Jackson](https://github.com/FasterXML/jackson)   |
| C#         | [Npgsql](https://www.npgsql.org/)                               | `HttpClient` and `System.Text.Json` from .NET                                       |
| Go         | [pgx](https://github.com/jackc/pgx)                             | The `net/http` package                                                              |
| Rust       | [rust-postgres](https://github.com/rust-postgres/rust-postgres) | [reqwest](https://docs.rs/reqwest/), with [serde_json](https://docs.rs/serde_json/) |
| Ruby       | [ruby-pg](https://github.com/ged/ruby-pg)                       | `Net::HTTP` and `json` from the standard library                                    |

The following tabs show the dependency declaration from each example
project:

=== "Python"

    ```text
    # httpx for the Ollama API, and psycopg 3 with the pre-built binary
    # package that bundles libpq.
    httpx>=0.28,<1
    psycopg[binary]>=3.2,<4
    ```

=== "TypeScript"

    ```json
    {
      "name": "prepare-data",
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
      <!-- Jackson, for reading and writing JSON; the HTTP client is part of
           the JDK. -->
      <dependency>
        <groupId>tools.jackson.core</groupId>
        <artifactId>jackson-databind</artifactId>
        <version>3.2.4</version>
      </dependency>
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
      <!-- Npgsql, the ADO.NET data provider for PostgreSQL. HttpClient and
           System.Text.Json are part of .NET. -->
      <PackageReference Include="Npgsql" Version="10.0.3" />
    </ItemGroup>
    ```

=== "Go"

    ```text
    // pgx is a pure Go driver and toolkit for PostgreSQL; the Ollama API
    // needs only the standard library.
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
    # The blocking client, with TLS from rustls and request and response bodies
    # as JSON; the default features add HTTP/2 and other things this example
    # does not use.
    reqwest = { version = "0.13", default-features = false, features = ["blocking", "json", "rustls"] }
    serde_json = "1"
    # The synchronous PostgreSQL client; tokio-postgres is the asynchronous
    # equivalent.
    postgres = "0.19"
    ```

=== "Ruby"

    ```ruby
    source "https://rubygems.org"
    
    # Net::HTTP and json are part of the standard library. The pg gem wraps
    # libpq, so libpq and its headers must be installed.
    gem "pg", "~> 1.6"
    ```

## Importing the Libraries

Each program begins by importing the database driver, the HTTP client, and
any standard library modules that it uses. The following tabs show the
imports for each language:

=== "Python"

    ```python
    import os
    import sys
    
    import httpx
    import psycopg
    ```

=== "TypeScript"

    ```typescript
    import pg from "pg";
    ```

=== "Java"

    ```java
    import java.io.IOException;
    import java.net.URI;
    import java.net.http.HttpClient;
    import java.net.http.HttpRequest;
    import java.net.http.HttpResponse;
    import java.net.http.HttpTimeoutException;
    import java.sql.Connection;
    import java.sql.DriverManager;
    import java.sql.PreparedStatement;
    import java.sql.ResultSet;
    import java.sql.SQLException;
    import java.sql.Statement;
    import java.time.Duration;
    import java.util.ArrayList;
    import java.util.List;
    import java.util.Properties;
    import java.util.StringJoiner;
    import java.util.concurrent.CompletableFuture;
    import java.util.concurrent.ExecutionException;
    import java.util.concurrent.TimeUnit;
    import java.util.concurrent.TimeoutException;
    
    import tools.jackson.core.JacksonException;
    import tools.jackson.databind.JsonNode;
    import tools.jackson.databind.ObjectMapper;
    import tools.jackson.databind.json.JsonMapper;
    import tools.jackson.databind.node.ObjectNode;
    ```

=== "C#"

    ```csharp
    using System.Globalization;
    using System.Net.Http.Json;
    using System.Text.Json;
    using Npgsql;
    ```

=== "Go"

    ```go
    import (
    	"bytes"
    	"context"
    	"encoding/json"
    	"fmt"
    	"io"
    	"net"
    	"net/http"
    	"net/url"
    	"os"
    	"strconv"
    	"strings"
    	"time"
    
    	"github.com/jackc/pgx/v5"
    )
    
    ```

=== "Rust"

    ```rust
    use std::env;
    use std::error::Error;
    use std::process::ExitCode;
    use std::time::Duration;
    
    use postgres::{Client, Config, NoTls, Transaction};
    use serde_json::{json, Value};
    ```

=== "Ruby"

    ```ruby
    require "json"
    require "net/http"
    require "pg"
    require "uri"
    ```

## Configuring the Program

The programs read the connection settings from the standard PostgreSQL
environment variables, and the Ollama settings from two more. Each program
treats an empty variable as unset, and uses the default instead. The
following table describes the environment variables:

| Variable      | Default                  | Description                        |
|---------------|--------------------------|------------------------------------|
| `PGHOST`      | `localhost`              | The PostgreSQL host name.          |
| `PGPORT`      | `5432`                   | The PostgreSQL port.               |
| `PGDATABASE`  | `postgres`               | The database name.                 |
| `PGUSER`      | `postgres`               | The database user.                 |
| `PGPASSWORD`  | none                     | The database password.             |
| `OLLAMA_URL`  | `http://localhost:11434` | The base URL of the Ollama server. |
| `EMBED_MODEL` | `nomic-embed-text`       | The embedding model.               |

The programs store three short documents in a table named
`cookbook_prepare_data`. The programs use their own table so that they never
disturb the table that a running pipeline reads. The following tabs show the
settings and the documents:

=== "Python"

    ```python
    # The or operator treats an empty variable as unset, as libpq does.
    OLLAMA_URL = (os.environ.get("OLLAMA_URL") or "http://localhost:11434").rstrip("/")
    EMBED_MODEL = os.environ.get("EMBED_MODEL") or "nomic-embed-text"
    
    # This recipe uses its own table, so that it never disturbs the table that
    # a running pipeline reads.
    TABLE = "cookbook_prepare_data"
    
    # The documents to store; in a real application they come from your own
    # data. The text is fictional.
    DOCUMENTS = [
        (1, "Charging the Acme Gadget",
         "The Acme Gadget charges through its USB-C port. A full charge takes "
         "two hours, and a fully charged Acme Gadget runs for ten hours."),
        (2, "Resetting the Acme Gadget",
         "To reset the Acme Gadget to its factory settings, hold down the "
         "power button for eight seconds until the status light flashes red."),
        (3, "Warranty for the Acme Gadget",
         "The Acme Gadget comes with a two-year warranty that covers "
         "manufacturing defects but not accidental damage."),
    ]
    
    
    def connection_settings() -> dict:
        """Reads the connection settings from the standard libpq environment
        variables, with defaults suitable for a local development server."""
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
    // The || operator, unlike ??, also treats an empty variable as unset, as
    // libpq does.
    const ollamaUrl = (process.env.OLLAMA_URL || "http://localhost:11434").replace(/\/+$/, "");
    const embedModel = process.env.EMBED_MODEL || "nomic-embed-text";
    
    // This recipe uses its own table, so that it never disturbs the table that
    // a running pipeline reads.
    const table = "cookbook_prepare_data";
    
    // The documents to store; in a real application they come from your own
    // data. The text is fictional.
    const documents = [
      {
        id: 1,
        title: "Charging the Acme Gadget",
        content:
          "The Acme Gadget charges through its USB-C port. A full charge takes " +
          "two hours, and a fully charged Acme Gadget runs for ten hours.",
      },
      {
        id: 2,
        title: "Resetting the Acme Gadget",
        content:
          "To reset the Acme Gadget to its factory settings, hold down the " +
          "power button for eight seconds until the status light flashes red.",
      },
      {
        id: 3,
        title: "Warranty for the Acme Gadget",
        content:
          "The Acme Gadget comes with a two-year warranty that covers " +
          "manufacturing defects but not accidental damage.",
      },
    ];
    
    const dbConfig: pg.ClientConfig = {
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
    
    static final String OLLAMA_URL =
            envOr("OLLAMA_URL", "http://localhost:11434").replaceAll("/+$", "");
    static final String EMBED_MODEL = envOr("EMBED_MODEL", "nomic-embed-text");
    
    // This recipe uses its own table, so that it never disturbs the table
    // that a running pipeline reads.
    static final String TABLE = "cookbook_prepare_data";
    
    /** A row to store. */
    record Document(int id, String title, String content) {}
    
    // The documents to store; in a real application they come from your
    // own data. The text is fictional.
    static final List<Document> DOCUMENTS = List.of(
            new Document(1, "Charging the Acme Gadget",
                    "The Acme Gadget charges through its USB-C port. A full charge takes "
                    + "two hours, and a fully charged Acme Gadget runs for ten hours."),
            new Document(2, "Resetting the Acme Gadget",
                    "To reset the Acme Gadget to its factory settings, hold down the "
                    + "power button for eight seconds until the status light flashes red."),
            new Document(3, "Warranty for the Acme Gadget",
                    "The Acme Gadget comes with a two-year warranty that covers "
                    + "manufacturing defects but not accidental damage."));
    
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
    
    static string OllamaUrl() =>
        EnvOr("OLLAMA_URL", "http://localhost:11434").TrimEnd('/');
    static string EmbedModel() => EnvOr("EMBED_MODEL", "nomic-embed-text");
    
    // This recipe uses its own table, so that it never disturbs the table that
    // a running pipeline reads.
    const string Table = "cookbook_prepare_data";
    
    // The documents to store; in a real application they come from your own
    // data. The text is fictional.
    Document[] documents =
    [
        new(1, "Charging the Acme Gadget",
            "The Acme Gadget charges through its USB-C port. A full charge takes " +
            "two hours, and a fully charged Acme Gadget runs for ten hours."),
        new(2, "Resetting the Acme Gadget",
            "To reset the Acme Gadget to its factory settings, hold down the " +
            "power button for eight seconds until the status light flashes red."),
        new(3, "Warranty for the Acme Gadget",
            "The Acme Gadget comes with a two-year warranty that covers " +
            "manufacturing defects but not accidental damage."),
    ];
    
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
    
    var (
    	ollamaURL  = strings.TrimRight(envOr("OLLAMA_URL", "http://localhost:11434"), "/")
    	embedModel = envOr("EMBED_MODEL", "nomic-embed-text")
    )
    
    // This recipe uses its own table, so that it never disturbs the table that
    // a running pipeline reads.
    const table = "cookbook_prepare_data"
    
    // document is a row to store. The text is fictional; in a real
    // application the documents come from your own data.
    type document struct {
    	ID      int
    	Title   string
    	Content string
    }
    
    var documents = []document{
    	{1, "Charging the Acme Gadget",
    		"The Acme Gadget charges through its USB-C port. A full charge takes " +
    			"two hours, and a fully charged Acme Gadget runs for ten hours."},
    	{2, "Resetting the Acme Gadget",
    		"To reset the Acme Gadget to its factory settings, hold down the " +
    			"power button for eight seconds until the status light flashes red."},
    	{3, "Warranty for the Acme Gadget",
    		"The Acme Gadget comes with a two-year warranty that covers " +
    			"manufacturing defects but not accidental damage."},
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
    
    fn ollama_url() -> String {
        env_or("OLLAMA_URL", "http://localhost:11434")
            .trim_end_matches('/')
            .to_string()
    }
    
    fn embed_model() -> String {
        env_or("EMBED_MODEL", "nomic-embed-text")
    }
    
    /// This recipe uses its own table, so that it never disturbs the table
    /// that a running pipeline reads.
    const TABLE: &str = "cookbook_prepare_data";
    
    /// The documents to store, as (id, title, content); in a real application
    /// they come from your own data. The text is fictional.
    const DOCUMENTS: [(i32, &str, &str); 3] = [
        (
            1,
            "Charging the Acme Gadget",
            "The Acme Gadget charges through its USB-C port. A full charge takes \
             two hours, and a fully charged Acme Gadget runs for ten hours.",
        ),
        (
            2,
            "Resetting the Acme Gadget",
            "To reset the Acme Gadget to its factory settings, hold down the \
             power button for eight seconds until the status light flashes red.",
        ),
        (
            3,
            "Warranty for the Acme Gadget",
            "The Acme Gadget comes with a two-year warranty that covers \
             manufacturing defects but not accidental damage.",
        ),
    ];
    
    /// The errors that the functions below return; a string converts into one
    /// with the ? operator or into().
    type BoxError = Box<dyn Error>;
    
    /// Builds the connection configuration from the standard libpq
    /// environment variables, with defaults suitable for a local server.
    fn config() -> Result<Config, BoxError> {
        let mut config = Config::new();
        config
            .host(&env_or("PGHOST", "localhost"))
            .port(env_or("PGPORT", "5432").parse()?)
            .dbname(&env_or("PGDATABASE", "postgres"))
            .user(&env_or("PGUSER", "postgres"));
        if let Some(password) = env_value("PGPASSWORD") {
            config.password(&password);
        }
        Ok(config)
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
    
    OLLAMA_URL = env_or("OLLAMA_URL", "http://localhost:11434").sub(%r{/+\z}, "")
    EMBED_MODEL = env_or("EMBED_MODEL", "nomic-embed-text")
    
    # This recipe uses its own table, so that it never disturbs the table that
    # a running pipeline reads.
    TABLE = "cookbook_prepare_data"
    
    # The documents to store, as [id, title, content]; in a real application
    # they come from your own data. The text is fictional.
    DOCUMENTS = [
      [1, "Charging the Acme Gadget",
       "The Acme Gadget charges through its USB-C port. A full charge takes " \
       "two hours, and a fully charged Acme Gadget runs for ten hours."],
      [2, "Resetting the Acme Gadget",
       "To reset the Acme Gadget to its factory settings, hold down the " \
       "power button for eight seconds until the status light flashes red."],
      [3, "Warranty for the Acme Gadget",
       "The Acme Gadget comes with a two-year warranty that covers " \
       "manufacturing defects but not accidental damage."]
    ].freeze
    
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

## Creating the Embeddings

Ollama turns text into embeddings with a `POST` request to `/api/embed`,
whose body names the model and lists the texts:

```json
{"model": "nomic-embed-text", "input": ["first text", "second text"]}
```

The reply holds one embedding for each text, in the same order, in an
`embeddings` array. A single request embeds every document. The programs
check that the reply holds one embedding for each document, and exit with an
error when it does not. The following tabs show the request:

=== "Python"

    ```python
    def embed(texts: list[str]) -> list[list[float]]:
        """Asks Ollama for the embedding of each text, in the same order."""
        # The embed endpoint accepts a list of texts, so one request embeds
        # every document.
        response = httpx.post(
            f"{OLLAMA_URL}/api/embed",
            json={"model": EMBED_MODEL, "input": texts},
            timeout=300.0,
        )
        response.raise_for_status()
    
        embeddings = response.json()["embeddings"]
        if len(embeddings) != len(texts):
            raise ValueError(
                f"Expected {len(texts)} embeddings, got {len(embeddings)}")
        return embeddings
    ```

=== "TypeScript"

    ```typescript
    // Asks Ollama for the embedding of each text, in the same order.
    async function embed(texts: string[]): Promise<number[][]> {
      // The embed endpoint accepts a list of texts, so one request embeds
      // every document.
      const response = await fetch(`${ollamaUrl}/api/embed`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ model: embedModel, input: texts }),
        signal: AbortSignal.timeout(300_000),
      });
      // fetch only rejects when it cannot reach the server, so check the
      // status explicitly.
      if (!response.ok) {
        throw new Error(`Ollama returned HTTP ${response.status}: ${(await response.text()).slice(0, 200)}`);
      }
    
      const { embeddings } = (await response.json()) as { embeddings?: number[][] };
      if (!Array.isArray(embeddings) || embeddings.length !== texts.length) {
        throw new Error(`Expected ${texts.length} embeddings from Ollama`);
      }
      return embeddings;
    }
    ```

=== "Java"

    ```java
    // A mapper is safe to share, so the program creates only one.
    static final ObjectMapper MAPPER = JsonMapper.builder().build();
    
    /** Thrown when Ollama rejects a request or returns an unexpected reply. */
    static class EmbedException extends Exception {
        EmbedException(String message) {
            super(message);
        }
    }
    
    /**
     * Sends a request and returns the response with its whole body. The
     * request timeout stops applying once the headers arrive, so a server
     * that stalls part of the way through the body would hang send(); this
     * applies the same timeout to the whole exchange instead.
     */
    static HttpResponse<String> send(HttpClient client, HttpRequest request)
            throws IOException, InterruptedException {
        Duration timeout = request.timeout().orElseThrow();
        CompletableFuture<HttpResponse<String>> pending =
                client.sendAsync(request, HttpResponse.BodyHandlers.ofString());
        try {
            return pending.get(timeout.toMillis(), TimeUnit.MILLISECONDS);
        } catch (TimeoutException e) {
            pending.cancel(true);
            throw new HttpTimeoutException("request timed out");
        } catch (ExecutionException e) {
            if (e.getCause() instanceof IOException cause) {
                throw cause;
            }
            throw new IOException(e.getCause());
        }
    }
    
    /**
     * Asks Ollama for the embedding of each text, in the same order.
     * pgvector stores single-precision values, so a float loses nothing
     * that the table would keep.
     */
    static List<float[]> embed(List<String> texts)
            throws IOException, InterruptedException, EmbedException {
        // The embed endpoint accepts a list of texts, so one request embeds
        // every document.
        ObjectNode payload = MAPPER.createObjectNode().put("model", EMBED_MODEL);
        texts.forEach(payload.putArray("input")::add);
    
        HttpRequest request = HttpRequest.newBuilder(URI.create(OLLAMA_URL + "/api/embed"))
                .timeout(Duration.ofSeconds(300))
                .header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString(MAPPER.writeValueAsString(payload)))
                .build();
        HttpResponse<String> response = send(HttpClient.newHttpClient(), request);
    
        // The client treats an error status as a normal response, so check
        // it here.
        if (response.statusCode() != 200) {
            String body = response.body().strip();
            throw new EmbedException("Ollama returned HTTP " + response.statusCode()
                    + ": " + body.substring(0, Math.min(body.length(), 200)));
        }
    
        // path() returns a missing node, rather than null, for a field that
        // is not there, and a missing node holds no elements.
        List<float[]> embeddings = new ArrayList<>();
        for (JsonNode node : MAPPER.readTree(response.body()).path("embeddings")) {
            float[] embedding = new float[node.size()];
            for (int i = 0; i < embedding.length; i++) {
                embedding[i] = node.get(i).floatValue();
            }
            embeddings.add(embedding);
        }
        if (embeddings.size() != texts.size()) {
            throw new EmbedException("Expected " + texts.size()
                    + " embeddings, got " + embeddings.size());
        }
        return embeddings;
    }
    ```

=== "C#"

    ```csharp
    // Asks Ollama for the embedding of each text, in the same order. pgvector
    // stores single-precision values, so a float loses nothing that the table
    // would keep.
    static async Task<float[][]> EmbedAsync(string[] texts)
    {
        using var client = new HttpClient { Timeout = TimeSpan.FromSeconds(300) };
        // The embed endpoint accepts a list of texts, so one request embeds
        // every document.
        using var response = await client.PostAsJsonAsync(
            $"{OllamaUrl()}/api/embed", new { model = EmbedModel(), input = texts });
    
        // HttpClient treats an error status as a normal response, so check it
        // here.
        if (!response.IsSuccessStatusCode)
        {
            var body = (await response.Content.ReadAsStringAsync()).Trim();
            throw new EmbedException(
                $"Ollama returned HTTP {(int)response.StatusCode}: " +
                body[..Math.Min(body.Length, 200)]);
        }
    
        // ReadFromJsonAsync matches the embeddings field to the Embeddings
        // property without regard to case, and leaves it null if it is missing.
        var reply = await response.Content.ReadFromJsonAsync<EmbedReply>();
        if (reply?.Embeddings is not { } embeddings || embeddings.Length != texts.Length)
        {
            throw new EmbedException(
                $"Expected {texts.Length} embeddings, got {reply?.Embeddings?.Length ?? 0}");
        }
        return embeddings;
    }
    ```

=== "Go"

    ```go
    // embed asks Ollama for the embedding of each text, in the same order.
    func embed(texts []string) ([][]float32, error) {
    	// The embed endpoint accepts a list of texts, so one request embeds
    	// every document.
    	payload, err := json.Marshal(map[string]any{"model": embedModel, "input": texts})
    	if err != nil {
    		return nil, err
    	}
    
    	client := &http.Client{Timeout: 300 * time.Second}
    	response, err := client.Post(ollamaURL+"/api/embed", "application/json", bytes.NewReader(payload))
    	if err != nil {
    		return nil, err
    	}
    	defer response.Body.Close()
    
    	body, err := io.ReadAll(response.Body)
    	if err != nil {
    		return nil, err
    	}
    	// Go treats an error status as a normal response, so check it here.
    	if response.StatusCode != http.StatusOK {
    		return nil, fmt.Errorf("ollama returned HTTP %d: %.200s", response.StatusCode, body)
    	}
    
    	var result struct {
    		Embeddings [][]float32 `json:"embeddings"`
    	}
    	if err := json.Unmarshal(body, &result); err != nil {
    		return nil, fmt.Errorf("unexpected response from ollama: %w", err)
    	}
    	if len(result.Embeddings) != len(texts) {
    		return nil, fmt.Errorf("expected %d embeddings, got %d", len(texts), len(result.Embeddings))
    	}
    	return result.Embeddings, nil
    }
    
    ```

=== "Rust"

    ```rust
    /// Asks Ollama for the embedding of each text, in the same order.
    /// pgvector stores single-precision values, so f32 loses nothing that the
    /// table would keep.
    fn embed(texts: &[&str]) -> Result<Vec<Vec<f32>>, BoxError> {
        let client = reqwest::blocking::Client::builder()
            .timeout(Duration::from_secs(300))
            .build()?;
        // The embed endpoint accepts a list of texts, so one request embeds
        // every document.
        let response = client
            .post(format!("{}/api/embed", ollama_url()))
            .json(&json!({ "model": embed_model(), "input": texts }))
            .send()?;
    
        // reqwest treats an error status as a normal response, so check it
        // here.
        let status = response.status();
        if !status.is_success() {
            let body = response.text()?;
            let body: String = body.trim().chars().take(200).collect();
            return Err(format!("Ollama returned HTTP {}: {body}", status.as_u16()).into());
        }
    
        let mut reply: Value = response.json()?;
        let embeddings: Vec<Vec<f32>> = serde_json::from_value(reply["embeddings"].take())?;
        if embeddings.len() != texts.len() {
            return Err(format!("Expected {} embeddings, got {}", texts.len(), embeddings.len()).into());
        }
        Ok(embeddings)
    }
    ```

=== "Ruby"

    ```ruby
    # Raised when Ollama rejects a request or returns an unexpected reply.
    class EmbedError < StandardError; end
    
    # Asks Ollama for the embedding of each text, in the same order.
    def embed(texts)
      uri = URI("#{OLLAMA_URL}/api/embed")
      request = Net::HTTP::Post.new(uri, "Content-Type" => "application/json")
      # The embed endpoint accepts a list of texts, so one request embeds
      # every document.
      request.body = JSON.generate({ model: EMBED_MODEL, input: texts })
    
      # start opens a connection, and closes it when the block exits, whether
      # or not an error occurred.
      response = Net::HTTP.start(
        uri.host, uri.port,
        use_ssl: uri.scheme == "https", open_timeout: 300, read_timeout: 300
      ) { |http| http.request(request) }
      # Net::HTTP treats an error status as a normal response, so check it
      # here.
      unless response.is_a?(Net::HTTPSuccess)
        raise EmbedError, "Ollama returned HTTP #{response.code}: #{response.body.to_s.strip[0, 200]}"
      end
    
      # fetch raises KeyError if the reply has no embeddings.
      embeddings = JSON.parse(response.body).fetch("embeddings")
      unless embeddings.is_a?(Array) && embeddings.length == texts.length
        raise EmbedError, "Expected #{texts.length} embeddings, got #{embeddings.inspect[0, 200]}"
      end
    
      embeddings
    end
    ```

## Creating the Table

The table has an integer primary key, a title, the document text, and an
embedding column of type `vector(N)`, where `N` is the number of dimensions
of the embeddings. The programs take `N` from the length of the first
embedding, rather than fix it in the code, because each embedding model
produces a different length (the `nomic-embed-text` model produces 768).
The table is dropped first, so that a rerun starts clean. The following tabs
show how each program creates the table:

=== "Python"

    ```python
    def create_table(conn: psycopg.Connection, dimensions: int) -> None:
        """Creates the table, replacing any earlier copy. The vector column
        must have the same number of dimensions as the embedding model."""
        conn.execute("CREATE EXTENSION IF NOT EXISTS vector")
        conn.execute(f"DROP TABLE IF EXISTS {TABLE}")
        # The table name is a constant and the dimensions are an integer, so
        # building them into the statement is safe; a statement cannot take
        # either as a parameter.
        conn.execute(
            f"""
            CREATE TABLE {TABLE} (
                id        integer PRIMARY KEY,
                title     text NOT NULL,
                content   text NOT NULL,
                embedding vector({int(dimensions)}) NOT NULL
            )
            """
        )
    ```

=== "TypeScript"

    ```typescript
    // Creates the table, replacing any earlier copy. The vector column must
    // have the same number of dimensions as the embedding model.
    async function createTable(client: pg.Client, dimensions: number): Promise<void> {
      await client.query("CREATE EXTENSION IF NOT EXISTS vector");
      await client.query(`DROP TABLE IF EXISTS ${table}`);
      // The table name is a constant and the dimensions are an integer, so
      // building them into the statement is safe; a statement cannot take
      // either as a parameter.
      await client.query(`
        CREATE TABLE ${table} (
          id        integer PRIMARY KEY,
          title     text NOT NULL,
          content   text NOT NULL,
          embedding vector(${Math.trunc(dimensions)}) NOT NULL
        )`);
    }
    ```

=== "Java"

    ```java
    /**
     * Creates the table, replacing any earlier copy. The vector column
     * must have the same number of dimensions as the embedding model.
     */
    static void createTable(Connection conn, int dimensions) throws SQLException {
        try (Statement stmt = conn.createStatement()) {
            stmt.execute("CREATE EXTENSION IF NOT EXISTS vector");
            stmt.execute("DROP TABLE IF EXISTS " + TABLE);
            // The table name is a constant and the dimensions are an int,
            // so building them into the statement is safe; a statement
            // cannot take either as a parameter.
            stmt.execute("""
                    CREATE TABLE %s (
                        id        integer PRIMARY KEY,
                        title     text NOT NULL,
                        content   text NOT NULL,
                        embedding vector(%d) NOT NULL
                    )""".formatted(TABLE, dimensions));
        }
    }
    ```

=== "C#"

    ```csharp
    // Creates the table, replacing any earlier copy. The vector column must
    // have the same number of dimensions as the embedding model.
    static async Task CreateTableAsync(NpgsqlConnection conn, int dimensions)
    {
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = "CREATE EXTENSION IF NOT EXISTS vector";
        await cmd.ExecuteNonQueryAsync();
        cmd.CommandText = $"DROP TABLE IF EXISTS {Table}";
        await cmd.ExecuteNonQueryAsync();
        // The table name is a constant and the dimensions are an int, so
        // building them into the statement is safe; a statement cannot take
        // either as a parameter.
        cmd.CommandText = $"""
            CREATE TABLE {Table} (
                id        integer PRIMARY KEY,
                title     text NOT NULL,
                content   text NOT NULL,
                embedding vector({dimensions}) NOT NULL
            )
            """;
        await cmd.ExecuteNonQueryAsync();
    }
    ```

=== "Go"

    ```go
    // createTable creates the table, replacing any earlier copy. The vector
    // column must have the same number of dimensions as the embedding model.
    func createTable(ctx context.Context, tx pgx.Tx, dimensions int) error {
    	if _, err := tx.Exec(ctx, "CREATE EXTENSION IF NOT EXISTS vector"); err != nil {
    		return err
    	}
    	if _, err := tx.Exec(ctx, "DROP TABLE IF EXISTS "+table); err != nil {
    		return err
    	}
    	// The table name is a constant and the dimensions are an integer, so
    	// building them into the statement is safe; a statement cannot take
    	// either as a parameter.
    	_, err := tx.Exec(ctx, `
    		CREATE TABLE `+table+` (
    			id        integer PRIMARY KEY,
    			title     text NOT NULL,
    			content   text NOT NULL,
    			embedding vector(`+strconv.Itoa(dimensions)+`) NOT NULL
    		)`)
    	return err
    }
    
    ```

=== "Rust"

    ```rust
    /// Creates the table, replacing any earlier copy. The vector column must
    /// have the same number of dimensions as the embedding model.
    fn create_table(tx: &mut Transaction, dimensions: usize) -> Result<(), postgres::Error> {
        tx.batch_execute("CREATE EXTENSION IF NOT EXISTS vector")?;
        tx.batch_execute(&format!("DROP TABLE IF EXISTS {TABLE}"))?;
        // The table name is a constant and the dimensions are an integer, so
        // building them into the statement is safe; a statement cannot take
        // either as a parameter.
        tx.batch_execute(&format!(
            "CREATE TABLE {TABLE} (
                id        integer PRIMARY KEY,
                title     text NOT NULL,
                content   text NOT NULL,
                embedding vector({dimensions}) NOT NULL
            )"
        ))
    }
    ```

=== "Ruby"

    ```ruby
    # Creates the table, replacing any earlier copy. The vector column must
    # have the same number of dimensions as the embedding model.
    def create_table(conn, dimensions)
      conn.exec("CREATE EXTENSION IF NOT EXISTS vector")
      conn.exec("DROP TABLE IF EXISTS #{TABLE}")
      # The table name is a constant and Integer() accepts only an integer, so
      # building them into the statement is safe; a statement cannot take
      # either as a parameter.
      conn.exec(<<~SQL)
        CREATE TABLE #{TABLE} (
            id        integer PRIMARY KEY,
            title     text NOT NULL,
            content   text NOT NULL,
            embedding vector(#{Integer(dimensions)}) NOT NULL
        )
      SQL
    end
    ```

## Inserting the Documents

Each program inserts the documents inside a transaction, so that a failure
leaves no partial data. The programs pass each embedding as text, such as
`[0.1,0.2,0.3]`, and cast the parameter to `vector` in the `INSERT` statement,
which works with any driver and needs no extra type registration. The Rust
program declares the parameter as text first (`$4::text::vector`), because the
postgres crate checks each Rust value against the type that the server expects,
and will not send a string as a `vector`. The following tabs show how each
program inserts the rows:

=== "Python"

    ```python
    def insert_documents(conn: psycopg.Connection,
                         embeddings: list[list[float]]) -> None:
        """Stores each document with its embedding."""
        rows = []
        for (doc_id, title, content), embedding in zip(DOCUMENTS, embeddings):
            # pgvector reads a vector from text such as '[0.1,0.2,0.3]', and
            # the cast tells the server how to interpret the parameter.
            vector = "[" + ",".join(str(value) for value in embedding) + "]"
            rows.append((doc_id, title, content, vector))
    
        with conn.cursor() as cur:
            cur.executemany(
                f"INSERT INTO {TABLE} (id, title, content, embedding) "
                "VALUES (%s, %s, %s, %s::vector)",
                rows,
            )
    ```

=== "TypeScript"

    ```typescript
    // Stores each document with its embedding.
    async function insertDocuments(client: pg.Client, embeddings: number[][]): Promise<void> {
      for (const [i, doc] of documents.entries()) {
        // pgvector reads a vector from text such as '[0.1,0.2,0.3]', and the
        // cast tells the server how to interpret the parameter.
        const vector = `[${embeddings[i].join(",")}]`;
        await client.query(
          `INSERT INTO ${table} (id, title, content, embedding)
           VALUES ($1, $2, $3, $4::vector)`,
          [doc.id, doc.title, doc.content, vector],
        );
      }
    }
    ```

=== "Java"

    ```java
    /** Stores each document with its embedding, in a single batch. */
    static void insertDocuments(Connection conn, List<float[]> embeddings)
            throws SQLException {
        String sql = "INSERT INTO " + TABLE + " (id, title, content, embedding) "
                + "VALUES (?, ?, ?, ?::vector)";
        try (PreparedStatement stmt = conn.prepareStatement(sql)) {
            for (int i = 0; i < DOCUMENTS.size(); i++) {
                Document doc = DOCUMENTS.get(i);
                // pgvector reads a vector from text such as
                // '[0.1,0.2,0.3]', and the cast tells the server how to
                // interpret the parameter.
                StringJoiner vector = new StringJoiner(",", "[", "]");
                for (float value : embeddings.get(i)) {
                    vector.add(Float.toString(value));
                }
                stmt.setInt(1, doc.id());
                stmt.setString(2, doc.title());
                stmt.setString(3, doc.content());
                stmt.setString(4, vector.toString());
                stmt.addBatch();
            }
            stmt.executeBatch();
        }
    }
    ```

=== "C#"

    ```csharp
    // Stores each document with its embedding.
    static async Task InsertDocumentsAsync(
        NpgsqlConnection conn, Document[] documents, float[][] embeddings)
    {
        for (var i = 0; i < documents.Length; i++)
        {
            // pgvector reads a vector from text such as '[0.1,0.2,0.3]'. The
            // invariant culture always writes a full stop as the decimal
            // separator, and the cast tells the server how to interpret the
            // parameter.
            var vector = "[" + string.Join(",", embeddings[i].Select(
                value => value.ToString(CultureInfo.InvariantCulture))) + "]";
            await using var cmd = new NpgsqlCommand(
                $"INSERT INTO {Table} (id, title, content, embedding) " +
                "VALUES ($1, $2, $3, $4::vector)", conn)
            {
                Parameters =
                {
                    new() { Value = documents[i].Id },
                    new() { Value = documents[i].Title },
                    new() { Value = documents[i].Content },
                    new() { Value = vector },
                },
            };
            await cmd.ExecuteNonQueryAsync();
        }
    }
    ```

=== "Go"

    ```go
    // vectorText formats an embedding as the text that pgvector reads, such as
    // '[0.1,0.2,0.3]'.
    func vectorText(embedding []float32) string {
    	parts := make([]string, len(embedding))
    	for i, value := range embedding {
    		parts[i] = strconv.FormatFloat(float64(value), 'g', -1, 32)
    	}
    	return "[" + strings.Join(parts, ",") + "]"
    }
    
    // insertDocuments stores each document with its embedding.
    func insertDocuments(ctx context.Context, tx pgx.Tx, embeddings [][]float32) error {
    	for i, doc := range documents {
    		// The cast tells the server how to interpret the text parameter.
    		_, err := tx.Exec(ctx,
    			"INSERT INTO "+table+" (id, title, content, embedding) VALUES ($1, $2, $3, $4::vector)",
    			doc.ID, doc.Title, doc.Content, vectorText(embeddings[i]))
    		if err != nil {
    			return err
    		}
    	}
    	return nil
    }
    
    ```

=== "Rust"

    ```rust
    /// Stores each document with its embedding.
    fn insert_documents(tx: &mut Transaction, embeddings: &[Vec<f32>]) -> Result<(), postgres::Error> {
        // The driver checks each value against the type the server expects,
        // and a Rust string cannot be sent as a vector, so the parameter is
        // declared as text and then cast to a vector.
        let statement = tx.prepare(&format!(
            "INSERT INTO {TABLE} (id, title, content, embedding) \
             VALUES ($1, $2, $3, $4::text::vector)"
        ))?;
        for ((id, title, content), embedding) in DOCUMENTS.iter().zip(embeddings) {
            // pgvector reads a vector from text such as '[0.1,0.2,0.3]'.
            let values: Vec<String> = embedding.iter().map(|value| value.to_string()).collect();
            let vector = format!("[{}]", values.join(","));
            tx.execute(&statement, &[id, title, content, &vector])?;
        }
        Ok(())
    }
    ```

=== "Ruby"

    ```ruby
    # Stores each document with its embedding.
    def insert_documents(conn, embeddings)
      DOCUMENTS.zip(embeddings).each do |(id, title, content), embedding|
        # pgvector reads a vector from text such as '[0.1,0.2,0.3]', and the
        # cast tells the server how to interpret the parameter.
        vector = "[#{embedding.join(",")}]"
        conn.exec_params(
          "INSERT INTO #{TABLE} (id, title, content, embedding) " \
          "VALUES ($1, $2, $3, $4::vector)",
          [id, title, content, vector]
        )
      end
    end
    ```

## Verifying the Rows

After the insert, each program asks the database how many rows it stored and
how many dimensions their embeddings have, using the pgvector
`vector_dims()` function. The following tabs show the query:

=== "Python"

    ```python
    def describe_table(conn: psycopg.Connection) -> tuple[int, int]:
        """Returns the number of rows, and the number of dimensions of their
        embeddings."""
        row = conn.execute(
            f"SELECT count(*), max(vector_dims(embedding)) FROM {TABLE}"
        ).fetchone()
        return row[0], row[1]
    ```

=== "TypeScript"

    ```typescript
    // Returns the number of rows, and the number of dimensions of their
    // embeddings.
    async function describeTable(client: pg.Client): Promise<{ rows: number; dimensions: number }> {
      const result = await client.query<{ rows: string; dimensions: number }>(
        `SELECT count(*) AS rows, max(vector_dims(embedding)) AS dimensions FROM ${table}`,
      );
      // count(*) is a bigint, which node-postgres returns as a string.
      return { rows: Number(result.rows[0].rows), dimensions: result.rows[0].dimensions };
    }
    ```

=== "Java"

    ```java
    /**
     * Returns the number of rows, and the number of dimensions of their
     * embeddings.
     */
    static long[] describeTable(Connection conn) throws SQLException {
        try (Statement stmt = conn.createStatement();
             ResultSet rs = stmt.executeQuery(
                     "SELECT count(*), max(vector_dims(embedding)) FROM " + TABLE)) {
            rs.next();
            return new long[] {rs.getLong(1), rs.getLong(2)};
        }
    }
    ```

=== "C#"

    ```csharp
    // Returns the number of rows, and the number of dimensions of their
    // embeddings. count(*) returns a bigint, which maps to long, and
    // vector_dims() returns an integer, which maps to int.
    static async Task<(long Rows, int Dimensions)> DescribeTableAsync(NpgsqlConnection conn)
    {
        await using var cmd = new NpgsqlCommand(
            $"SELECT count(*), max(vector_dims(embedding)) FROM {Table}", conn);
        await using var reader = await cmd.ExecuteReaderAsync();
        await reader.ReadAsync();
        return (reader.GetInt64(0), reader.GetInt32(1));
    }
    ```

=== "Go"

    ```go
    // describeTable returns the number of rows, and the number of dimensions
    // of their embeddings.
    func describeTable(ctx context.Context, conn *pgx.Conn) (rows, dimensions int, err error) {
    	err = conn.QueryRow(ctx,
    		"SELECT count(*), max(vector_dims(embedding)) FROM "+table,
    	).Scan(&rows, &dimensions)
    	return rows, dimensions, err
    }
    
    ```

=== "Rust"

    ```rust
    /// Returns the number of rows, and the number of dimensions of their
    /// embeddings. count(*) returns a bigint, which maps to i64, and
    /// vector_dims() returns an integer, which maps to i32.
    fn describe_table(client: &mut Client) -> Result<(i64, i32), postgres::Error> {
        let row = client.query_one(
            &format!("SELECT count(*), max(vector_dims(embedding)) FROM {TABLE}"),
            &[],
        )?;
        Ok((row.get(0), row.get(1)))
    }
    ```

=== "Ruby"

    ```ruby
    # Returns the number of rows, and the number of dimensions of their
    # embeddings. Results arrive as strings, so convert them to Integers.
    def describe_table(conn)
      row = conn.exec("SELECT count(*), max(vector_dims(embedding)) FROM #{TABLE}")[0]
      [row["count"].to_i, row["max"].to_i]
    end
    ```

## Cleaning Up

A real application keeps its table, so that the RAG Server can read it. The
programs in this recipe drop the table when they finish, whether or not an
earlier step failed, so that running the recipe repeatedly never leaves
data behind. Remove the cleanup step, and the call to it, when you want to
keep the table. The following tabs show the cleanup:

=== "Python"

    ```python
    def drop_table(conn: psycopg.Connection) -> None:
        """Removes the table. A real application keeps it, so that the RAG
        Server can read it."""
        conn.execute(f"DROP TABLE IF EXISTS {TABLE}")
    ```

=== "TypeScript"

    ```typescript
    // Removes the table. A real application keeps it, so that the RAG Server
    // can read it.
    async function dropTable(client: pg.Client): Promise<void> {
      await client.query(`DROP TABLE IF EXISTS ${table}`);
    }
    ```

=== "Java"

    ```java
    /**
     * Removes the table. A real application keeps it, so that the RAG
     * Server can read it.
     */
    static void dropTable(Connection conn) throws SQLException {
        try (Statement stmt = conn.createStatement()) {
            stmt.execute("DROP TABLE IF EXISTS " + TABLE);
        }
    }
    ```

=== "C#"

    ```csharp
    // Removes the table. A real application keeps it, so that the RAG Server
    // can read it.
    static async Task DropTableAsync(NpgsqlConnection conn)
    {
        await using var cmd = new NpgsqlCommand($"DROP TABLE IF EXISTS {Table}", conn);
        await cmd.ExecuteNonQueryAsync();
    }
    ```

=== "Go"

    ```go
    // dropTable removes the table. A real application keeps it, so that the
    // RAG Server can read it.
    func dropTable(ctx context.Context, conn *pgx.Conn) error {
    	_, err := conn.Exec(ctx, "DROP TABLE IF EXISTS "+table)
    	return err
    }
    
    ```

=== "Rust"

    ```rust
    /// Removes the table. A real application keeps it, so that the RAG Server
    /// can read it.
    fn drop_table(client: &mut Client) -> Result<(), postgres::Error> {
        client.batch_execute(&format!("DROP TABLE IF EXISTS {TABLE}"))
    }
    ```

=== "Ruby"

    ```ruby
    # Removes the table. A real application keeps it, so that the RAG Server
    # can read it.
    def drop_table(conn)
      conn.exec("DROP TABLE IF EXISTS #{TABLE}")
    end
    ```

## Running the Program

The main part of each program creates the embeddings, stores them, prints
the summary, and removes the table. The program reports any failure on
`stderr` and exits with a non-zero status. The following tabs show the main
part of each program:

=== "Python"

    ```python
    def main() -> int:
        cleanup_failed = False
        try:
            embeddings = embed([content for _, _, content in DOCUMENTS])
            print(f"Embedded {len(embeddings)} documents with {EMBED_MODEL}")
    
            # Autocommit makes each statement take effect at once, so that the
            # transaction block below is the only place that groups them.
            with psycopg.connect(**connection_settings(), autocommit=True) as conn:
                try:
                    with conn.transaction():
                        create_table(conn, len(embeddings[0]))
                        insert_documents(conn, embeddings)
    
                    rows, dimensions = describe_table(conn)
                    print(f"Stored {rows} rows with {dimensions}-dimension "
                          f"embeddings in {TABLE}")
                finally:
                    # Remove the table whether or not a step failed. A failure
                    # here is reported on its own, so that it cannot hide the
                    # error that came first.
                    try:
                        drop_table(conn)
                    except psycopg.Error as e:
                        print(f"Cleanup error: {e}", file=sys.stderr)
                        cleanup_failed = True
        # httpx.HTTPError covers a failure to reach Ollama or an error status,
        # and psycopg.Error covers every error from the database driver.
        except (httpx.HTTPError, psycopg.Error, KeyError, ValueError) as e:
            print(f"Error: {e}", file=sys.stderr)
            return 1
    
        return 1 if cleanup_failed else 0
    
    
    if __name__ == "__main__":
        sys.exit(main())
    ```

=== "TypeScript"

    ```typescript
    // Returns a readable description of an error. When a host name resolves
    // to several addresses, Node reports a failure to reach all of them as an
    // AggregateError, whose own message is empty; fetch attaches the cause of
    // a connection failure to a TypeError.
    function describe(err: unknown): string {
      if (err instanceof AggregateError) {
        return err.errors.map(describe).join("; ");
      }
      if (err instanceof Error) {
        return err.cause ? `${err.message}: ${describe(err.cause)}` : err.message;
      }
      return String(err);
    }
    
    async function main(): Promise<number> {
      let client: pg.Client | undefined;
      let cleanupFailed = false;
      try {
        const embeddings = await embed(documents.map((doc) => doc.content));
        console.log(`Embedded ${embeddings.length} documents with ${embedModel}`);
    
        client = new pg.Client(dbConfig);
        await client.connect();
        try {
          await client.query("BEGIN");
          await createTable(client, embeddings[0].length);
          await insertDocuments(client, embeddings);
          await client.query("COMMIT");
    
          const { rows, dimensions } = await describeTable(client);
          console.log(`Stored ${rows} rows with ${dimensions}-dimension embeddings in ${table}`);
        } finally {
          // Roll back anything unfinished (a no-op after a commit), and remove
          // the table whether or not a step failed. A failure here is reported
          // on its own, so that it cannot hide the error that came first.
          try {
            await client.query("ROLLBACK");
            await dropTable(client);
          } catch (cleanupErr) {
            console.error(`Cleanup error: ${describe(cleanupErr)}`);
            cleanupFailed = true;
          }
        }
        return cleanupFailed ? 1 : 0;
      } catch (err) {
        console.error(`Error: ${describe(err)}`);
        return 1;
      } finally {
        // client is undefined if the program failed before it connected.
        await client?.end();
      }
    }
    
    process.exitCode = await main();
    ```

=== "Java"

    ```java
    /**
     * Creates the table and inserts the documents in one transaction,
     * rolling it back if a step fails.
     */
    static void store(Connection conn, List<float[]> embeddings) throws SQLException {
        conn.setAutoCommit(false);
        try {
            createTable(conn, embeddings.get(0).length);
            insertDocuments(conn, embeddings);
            conn.commit();
        } catch (SQLException e) {
            // Attach any failure to roll back to the first error, rather
            // than letting it replace that error.
            try {
                conn.rollback();
            } catch (SQLException rollbackError) {
                e.addSuppressed(rollbackError);
            }
            throw e;
        } finally {
            conn.setAutoCommit(true);
        }
    }
    
    public static void main(String[] args) {
        boolean cleanupFailed = false;
        try {
            List<float[]> embeddings =
                    embed(DOCUMENTS.stream().map(Document::content).toList());
            System.out.println("Embedded " + embeddings.size()
                    + " documents with " + EMBED_MODEL);
    
            // try-with-resources closes the connection when the block
            // exits, whether or not an error occurred.
            try (Connection conn = DriverManager.getConnection(
                    connectionUrl(), connectionProperties())) {
                try {
                    store(conn, embeddings);
                    long[] summary = describeTable(conn);
                    System.out.println("Stored " + summary[0] + " rows with "
                            + summary[1] + "-dimension embeddings in " + TABLE);
                } finally {
                    // Remove the table whether or not a step failed. A
                    // failure here is reported on its own, so that it
                    // cannot hide the error that came first.
                    try {
                        dropTable(conn);
                    } catch (SQLException e) {
                        System.err.println("Cleanup error: " + e.getMessage());
                        cleanupFailed = true;
                    }
                }
            }
        // IOException covers failures to reach Ollama, such as a refused
        // connection or a timeout. The message of a refused connection can
        // be empty, so print the exception itself, which includes its type.
        } catch (IOException | InterruptedException e) {
            System.err.println("Error: " + e);
            System.exit(1);
        // SQLException covers connection failures and errors reported by
        // the server, and JacksonException covers a reply that is not JSON.
        } catch (SQLException | EmbedException | JacksonException e) {
            System.err.println("Error: " + e.getMessage());
            System.exit(1);
        }
        if (cleanupFailed) {
            System.exit(1);
        }
    }
    ```

=== "C#"

    ```csharp
    var cleanupFailed = false;
    try
    {
        var embeddings = await EmbedAsync([.. documents.Select(doc => doc.Content)]);
        Console.WriteLine($"Embedded {embeddings.Length} documents with {EmbedModel()}");
    
        // await using disposes of the data source and the connection when the
        // block exits, whether or not an error occurred.
        await using var dataSource = NpgsqlDataSource.Create(ConnectionString());
        await using var conn = await dataSource.OpenConnectionAsync();
        try
        {
            // Disposing of a transaction that has not been committed rolls it
            // back, so a failed step undoes every step before it.
            await using (var tx = await conn.BeginTransactionAsync())
            {
                await CreateTableAsync(conn, embeddings[0].Length);
                await InsertDocumentsAsync(conn, documents, embeddings);
                await tx.CommitAsync();
            }
    
            var (rows, dimensions) = await DescribeTableAsync(conn);
            Console.WriteLine(
                $"Stored {rows} rows with {dimensions}-dimension embeddings in {Table}");
        }
        finally
        {
            // Remove the table whether or not a step failed. A failure here is
            // reported on its own, so that it cannot hide the error that came
            // first.
            try
            {
                await DropTableAsync(conn);
            }
            catch (NpgsqlException e)
            {
                Console.Error.WriteLine($"Cleanup error: {e.Message}");
                cleanupFailed = true;
            }
        }
    }
    // HttpRequestException covers failures to reach Ollama, such as a refused
    // connection, TaskCanceledException covers a timeout, JsonException covers
    // a reply that is not JSON, and NpgsqlException covers connection failures
    // and errors reported by the server.
    catch (Exception e) when (e is HttpRequestException or TaskCanceledException
        or JsonException or NpgsqlException or EmbedException)
    {
        Console.Error.WriteLine($"Error: {e.Message}");
        return 1;
    }
    
    return cleanupFailed ? 1 : 0;
    
    // C# requires type declarations to follow the top-level statements, so the
    // types that the program uses are declared here, at the end.
    
    // A row to store.
    record Document(int Id, string Title, string Content);
    
    // The part of Ollama's reply that the program reads.
    record EmbedReply(float[][]? Embeddings);
    
    // Thrown when Ollama rejects a request or returns an unexpected reply.
    class EmbedException(string message) : Exception(message);
    ```

=== "Go"

    ```go
    // store creates the table and inserts the documents in one transaction.
    func store(ctx context.Context, conn *pgx.Conn, embeddings [][]float32) error {
    	tx, err := conn.Begin(ctx)
    	if err != nil {
    		return err
    	}
    	// Rollback does nothing after a successful commit, so the deferred
    	// call only matters when a step fails.
    	defer tx.Rollback(ctx)
    
    	if err := createTable(ctx, tx, len(embeddings[0])); err != nil {
    		return err
    	}
    	if err := insertDocuments(ctx, tx, embeddings); err != nil {
    		return err
    	}
    	return tx.Commit(ctx)
    }
    
    // run embeds the documents, stores them, and reports what the table
    // holds, returning any error to the caller.
    func run(ctx context.Context) (err error) {
    	texts := make([]string, len(documents))
    	for i, doc := range documents {
    		texts[i] = doc.Content
    	}
    	embeddings, err := embed(texts)
    	if err != nil {
    		return fmt.Errorf("embedding failed: %w", err)
    	}
    	fmt.Printf("Embedded %d documents with %s\n", len(embeddings), embedModel)
    
    	conn, err := pgx.Connect(ctx, connString())
    	if err != nil {
    		return fmt.Errorf("connection failed: %w", err)
    	}
    	defer conn.Close(ctx)
    
    	// Remove the table whether or not a step failed. A failure to remove it
    	// becomes the returned error only when there is no earlier error, and
    	// is printed on its own otherwise, so that it cannot hide the first.
    	defer func() {
    		if dropErr := dropTable(ctx, conn); dropErr != nil {
    			if err == nil {
    				err = dropErr
    			} else {
    				fmt.Fprintf(os.Stderr, "Cleanup error: %v\n", dropErr)
    			}
    		}
    	}()
    
    	if err := store(ctx, conn, embeddings); err != nil {
    		return fmt.Errorf("storing the documents failed: %w", err)
    	}
    
    	rows, dimensions, err := describeTable(ctx, conn)
    	if err != nil {
    		return fmt.Errorf("query failed: %w", err)
    	}
    	fmt.Printf("Stored %d rows with %d-dimension embeddings in %s\n", rows, dimensions, table)
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
    /// Creates the table and inserts the documents in one transaction, then
    /// reports what the table holds.
    fn store(client: &mut Client, embeddings: &[Vec<f32>]) -> Result<(), BoxError> {
        // Dropping a transaction without committing it rolls it back, so a ?
        // that returns early undoes every step.
        let mut tx = client.transaction()?;
        create_table(&mut tx, embeddings[0].len())?;
        insert_documents(&mut tx, embeddings)?;
        tx.commit()?;
    
        let (rows, dimensions) = describe_table(client)?;
        println!("Stored {rows} rows with {dimensions}-dimension embeddings in {TABLE}");
        Ok(())
    }
    
    /// Embeds the documents, stores them, and removes the table again. The ?
    /// operator returns any error to the caller.
    fn run() -> Result<(), BoxError> {
        let texts: Vec<&str> = DOCUMENTS.iter().map(|(_, _, content)| *content).collect();
        let embeddings = embed(&texts)?;
        println!("Embedded {} documents with {}", embeddings.len(), embed_model());
    
        // NoTls disables TLS, which keeps this example free of certificate
        // set-up; connections over an untrusted network should use TLS.
        let mut client = config()?.connect(NoTls)?;
        let result = store(&mut client, &embeddings);
    
        // Remove the table whether or not a step failed. A failure to remove
        // it becomes the returned error only when there is no earlier error,
        // and is printed on its own otherwise, so that it cannot hide the
        // first.
        match (result, drop_table(&mut client)) {
            (Ok(()), Err(e)) => Err(format!("Cleanup error: {e}").into()),
            (Err(e), Err(cleanup)) => {
                eprintln!("Cleanup error: {cleanup}");
                Err(e)
            }
            (result, Ok(())) => result,
        }
    }
    
    /// Reports any error returned by run() and exits with a failure status.
    /// The top-level error is often generic ("error sending request"), so the
    /// chain of underlying causes is printed too.
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
    cleanup_failed = false
    begin
      embeddings = embed(DOCUMENTS.map { |_, _, content| content })
      puts "Embedded #{embeddings.length} documents with #{EMBED_MODEL}"
    
      conn = PG.connect(connection_params)
      begin
        # transaction commits when the block finishes, and rolls back and
        # raises the error again if the block raises one.
        conn.transaction do
          create_table(conn, embeddings[0].length)
          insert_documents(conn, embeddings)
        end
    
        rows, dimensions = describe_table(conn)
        puts "Stored #{rows} rows with #{dimensions}-dimension embeddings in #{TABLE}"
      ensure
        # Remove the table whether or not a step failed. A failure here is
        # reported on its own, so that it cannot hide the error that came
        # first.
        begin
          drop_table(conn)
        rescue PG::Error => e
          warn "Cleanup error: #{e.message}"
          cleanup_failed = true
        end
      end
    # SystemCallError covers a refused connection to Ollama, Timeout::Error
    # covers its timeouts, SocketError covers an unknown host, JSON::ParserError
    # and KeyError cover a reply that is not what Ollama sends, and PG::Error
    # covers every error from the database.
    rescue EmbedError, SystemCallError, Timeout::Error, SocketError, IOError,
           JSON::ParserError, KeyError, PG::Error => e
      warn "Error: #{e.message}"
      exit 1
    # The ensure block runs whether or not an error occurred. conn is nil if
    # the connection attempt failed, hence the safe navigation operator.
    ensure
      conn&.close
    end
    
    exit 1 if cleanup_failed
    ```

## Running the Example

The complete project for each language is available in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/rag_server/prepare_data).
Set the environment variables for your servers, and then run the command
for your language from the corresponding project directory. The following
tabs show the commands that build and run each example:

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

## Configuring the Pipeline

To let a RAG Server answer questions from a table like this one, add a
pipeline to its configuration file that names the table and its columns.
The following configuration describes a pipeline for the table in this
recipe, and you should adjust the connection details for your servers:

```yaml
pipelines:
  - name: "gadget"
    description: "Questions about the Acme Gadget"
    database:
      host: "localhost"
      port: 5432
      database: "postgres"
      username: "postgres"
      password: ""
      ssl_mode: "prefer"
    tables:
      - table: "cookbook_prepare_data"
        text_column: "content"
        vector_column: "embedding"
        id_column: "id"
    embedding_llm:
      provider: "ollama"
      model: "nomic-embed-text"
      base_url: "http://localhost:11434"
    rag_llm:
      provider: "ollama"
      model: "qwen2.5:1.5b"
      base_url: "http://localhost:11434"
    token_budget: 2000
    top_n: 3

```

The `embedding_llm` section must name the same model that created the
embeddings, because the server embeds each question with it before searching
for similar documents; a different model produces vectors that cannot be
compared. To keep the table for the pipeline, remove the cleanup step first.

## Viewing the Complete Program

The following tabs show the complete program for each language:

=== "Python"

    ```python
    """
    Ellie's Postgres Cookbook
    Preparing documents for the pgEdge RAG Server: embedding them with Ollama
    and storing them in a pgvector table, using httpx and psycopg 3.
    
    These examples are for pgEdge RAG Server 2.0.0.
    
    Copyright (c) 2026, pgEdge, Inc.
    This code is released under the PostgreSQL License.
    """
    
    import os
    import sys
    
    import httpx
    import psycopg
    
    
    # The or operator treats an empty variable as unset, as libpq does.
    OLLAMA_URL = (os.environ.get("OLLAMA_URL") or "http://localhost:11434").rstrip("/")
    EMBED_MODEL = os.environ.get("EMBED_MODEL") or "nomic-embed-text"
    
    # This recipe uses its own table, so that it never disturbs the table that
    # a running pipeline reads.
    TABLE = "cookbook_prepare_data"
    
    # The documents to store; in a real application they come from your own
    # data. The text is fictional.
    DOCUMENTS = [
        (1, "Charging the Acme Gadget",
         "The Acme Gadget charges through its USB-C port. A full charge takes "
         "two hours, and a fully charged Acme Gadget runs for ten hours."),
        (2, "Resetting the Acme Gadget",
         "To reset the Acme Gadget to its factory settings, hold down the "
         "power button for eight seconds until the status light flashes red."),
        (3, "Warranty for the Acme Gadget",
         "The Acme Gadget comes with a two-year warranty that covers "
         "manufacturing defects but not accidental damage."),
    ]
    
    
    def connection_settings() -> dict:
        """Reads the connection settings from the standard libpq environment
        variables, with defaults suitable for a local development server."""
        return {
            "host": os.environ.get("PGHOST") or "localhost",
            "port": os.environ.get("PGPORT") or "5432",
            "dbname": os.environ.get("PGDATABASE") or "postgres",
            "user": os.environ.get("PGUSER") or "postgres",
            "password": os.environ.get("PGPASSWORD") or None,
        }
    
    
    def embed(texts: list[str]) -> list[list[float]]:
        """Asks Ollama for the embedding of each text, in the same order."""
        # The embed endpoint accepts a list of texts, so one request embeds
        # every document.
        response = httpx.post(
            f"{OLLAMA_URL}/api/embed",
            json={"model": EMBED_MODEL, "input": texts},
            timeout=300.0,
        )
        response.raise_for_status()
    
        embeddings = response.json()["embeddings"]
        if len(embeddings) != len(texts):
            raise ValueError(
                f"Expected {len(texts)} embeddings, got {len(embeddings)}")
        return embeddings
    
    
    def create_table(conn: psycopg.Connection, dimensions: int) -> None:
        """Creates the table, replacing any earlier copy. The vector column
        must have the same number of dimensions as the embedding model."""
        conn.execute("CREATE EXTENSION IF NOT EXISTS vector")
        conn.execute(f"DROP TABLE IF EXISTS {TABLE}")
        # The table name is a constant and the dimensions are an integer, so
        # building them into the statement is safe; a statement cannot take
        # either as a parameter.
        conn.execute(
            f"""
            CREATE TABLE {TABLE} (
                id        integer PRIMARY KEY,
                title     text NOT NULL,
                content   text NOT NULL,
                embedding vector({int(dimensions)}) NOT NULL
            )
            """
        )
    
    
    def insert_documents(conn: psycopg.Connection,
                         embeddings: list[list[float]]) -> None:
        """Stores each document with its embedding."""
        rows = []
        for (doc_id, title, content), embedding in zip(DOCUMENTS, embeddings):
            # pgvector reads a vector from text such as '[0.1,0.2,0.3]', and
            # the cast tells the server how to interpret the parameter.
            vector = "[" + ",".join(str(value) for value in embedding) + "]"
            rows.append((doc_id, title, content, vector))
    
        with conn.cursor() as cur:
            cur.executemany(
                f"INSERT INTO {TABLE} (id, title, content, embedding) "
                "VALUES (%s, %s, %s, %s::vector)",
                rows,
            )
    
    
    def describe_table(conn: psycopg.Connection) -> tuple[int, int]:
        """Returns the number of rows, and the number of dimensions of their
        embeddings."""
        row = conn.execute(
            f"SELECT count(*), max(vector_dims(embedding)) FROM {TABLE}"
        ).fetchone()
        return row[0], row[1]
    
    
    def drop_table(conn: psycopg.Connection) -> None:
        """Removes the table. A real application keeps it, so that the RAG
        Server can read it."""
        conn.execute(f"DROP TABLE IF EXISTS {TABLE}")
    
    
    def main() -> int:
        cleanup_failed = False
        try:
            embeddings = embed([content for _, _, content in DOCUMENTS])
            print(f"Embedded {len(embeddings)} documents with {EMBED_MODEL}")
    
            # Autocommit makes each statement take effect at once, so that the
            # transaction block below is the only place that groups them.
            with psycopg.connect(**connection_settings(), autocommit=True) as conn:
                try:
                    with conn.transaction():
                        create_table(conn, len(embeddings[0]))
                        insert_documents(conn, embeddings)
    
                    rows, dimensions = describe_table(conn)
                    print(f"Stored {rows} rows with {dimensions}-dimension "
                          f"embeddings in {TABLE}")
                finally:
                    # Remove the table whether or not a step failed. A failure
                    # here is reported on its own, so that it cannot hide the
                    # error that came first.
                    try:
                        drop_table(conn)
                    except psycopg.Error as e:
                        print(f"Cleanup error: {e}", file=sys.stderr)
                        cleanup_failed = True
        # httpx.HTTPError covers a failure to reach Ollama or an error status,
        # and psycopg.Error covers every error from the database driver.
        except (httpx.HTTPError, psycopg.Error, KeyError, ValueError) as e:
            print(f"Error: {e}", file=sys.stderr)
            return 1
    
        return 1 if cleanup_failed else 0
    
    
    if __name__ == "__main__":
        sys.exit(main())
    
    ```

=== "TypeScript"

    ```typescript
    /*
     * Ellie's Postgres Cookbook
     * Preparing documents for the pgEdge RAG Server: embedding them with
     * Ollama and storing them in a pgvector table, using fetch and
     * node-postgres.
     *
     * These examples are for pgEdge RAG Server 2.0.0.
     *
     * Copyright (c) 2026, pgEdge, Inc.
     * This code is released under the PostgreSQL License.
     */
    
    import pg from "pg";
    
    // The || operator, unlike ??, also treats an empty variable as unset, as
    // libpq does.
    const ollamaUrl = (process.env.OLLAMA_URL || "http://localhost:11434").replace(/\/+$/, "");
    const embedModel = process.env.EMBED_MODEL || "nomic-embed-text";
    
    // This recipe uses its own table, so that it never disturbs the table that
    // a running pipeline reads.
    const table = "cookbook_prepare_data";
    
    // The documents to store; in a real application they come from your own
    // data. The text is fictional.
    const documents = [
      {
        id: 1,
        title: "Charging the Acme Gadget",
        content:
          "The Acme Gadget charges through its USB-C port. A full charge takes " +
          "two hours, and a fully charged Acme Gadget runs for ten hours.",
      },
      {
        id: 2,
        title: "Resetting the Acme Gadget",
        content:
          "To reset the Acme Gadget to its factory settings, hold down the " +
          "power button for eight seconds until the status light flashes red.",
      },
      {
        id: 3,
        title: "Warranty for the Acme Gadget",
        content:
          "The Acme Gadget comes with a two-year warranty that covers " +
          "manufacturing defects but not accidental damage.",
      },
    ];
    
    const dbConfig: pg.ClientConfig = {
      host: process.env.PGHOST || "localhost",
      port: Number(process.env.PGPORT || "5432"),
      database: process.env.PGDATABASE || "postgres",
      user: process.env.PGUSER || "postgres",
      password: process.env.PGPASSWORD || undefined,
    };
    
    // Asks Ollama for the embedding of each text, in the same order.
    async function embed(texts: string[]): Promise<number[][]> {
      // The embed endpoint accepts a list of texts, so one request embeds
      // every document.
      const response = await fetch(`${ollamaUrl}/api/embed`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ model: embedModel, input: texts }),
        signal: AbortSignal.timeout(300_000),
      });
      // fetch only rejects when it cannot reach the server, so check the
      // status explicitly.
      if (!response.ok) {
        throw new Error(`Ollama returned HTTP ${response.status}: ${(await response.text()).slice(0, 200)}`);
      }
    
      const { embeddings } = (await response.json()) as { embeddings?: number[][] };
      if (!Array.isArray(embeddings) || embeddings.length !== texts.length) {
        throw new Error(`Expected ${texts.length} embeddings from Ollama`);
      }
      return embeddings;
    }
    
    // Creates the table, replacing any earlier copy. The vector column must
    // have the same number of dimensions as the embedding model.
    async function createTable(client: pg.Client, dimensions: number): Promise<void> {
      await client.query("CREATE EXTENSION IF NOT EXISTS vector");
      await client.query(`DROP TABLE IF EXISTS ${table}`);
      // The table name is a constant and the dimensions are an integer, so
      // building them into the statement is safe; a statement cannot take
      // either as a parameter.
      await client.query(`
        CREATE TABLE ${table} (
          id        integer PRIMARY KEY,
          title     text NOT NULL,
          content   text NOT NULL,
          embedding vector(${Math.trunc(dimensions)}) NOT NULL
        )`);
    }
    
    // Stores each document with its embedding.
    async function insertDocuments(client: pg.Client, embeddings: number[][]): Promise<void> {
      for (const [i, doc] of documents.entries()) {
        // pgvector reads a vector from text such as '[0.1,0.2,0.3]', and the
        // cast tells the server how to interpret the parameter.
        const vector = `[${embeddings[i].join(",")}]`;
        await client.query(
          `INSERT INTO ${table} (id, title, content, embedding)
           VALUES ($1, $2, $3, $4::vector)`,
          [doc.id, doc.title, doc.content, vector],
        );
      }
    }
    
    // Returns the number of rows, and the number of dimensions of their
    // embeddings.
    async function describeTable(client: pg.Client): Promise<{ rows: number; dimensions: number }> {
      const result = await client.query<{ rows: string; dimensions: number }>(
        `SELECT count(*) AS rows, max(vector_dims(embedding)) AS dimensions FROM ${table}`,
      );
      // count(*) is a bigint, which node-postgres returns as a string.
      return { rows: Number(result.rows[0].rows), dimensions: result.rows[0].dimensions };
    }
    
    // Removes the table. A real application keeps it, so that the RAG Server
    // can read it.
    async function dropTable(client: pg.Client): Promise<void> {
      await client.query(`DROP TABLE IF EXISTS ${table}`);
    }
    
    // Returns a readable description of an error. When a host name resolves
    // to several addresses, Node reports a failure to reach all of them as an
    // AggregateError, whose own message is empty; fetch attaches the cause of
    // a connection failure to a TypeError.
    function describe(err: unknown): string {
      if (err instanceof AggregateError) {
        return err.errors.map(describe).join("; ");
      }
      if (err instanceof Error) {
        return err.cause ? `${err.message}: ${describe(err.cause)}` : err.message;
      }
      return String(err);
    }
    
    async function main(): Promise<number> {
      let client: pg.Client | undefined;
      let cleanupFailed = false;
      try {
        const embeddings = await embed(documents.map((doc) => doc.content));
        console.log(`Embedded ${embeddings.length} documents with ${embedModel}`);
    
        client = new pg.Client(dbConfig);
        await client.connect();
        try {
          await client.query("BEGIN");
          await createTable(client, embeddings[0].length);
          await insertDocuments(client, embeddings);
          await client.query("COMMIT");
    
          const { rows, dimensions } = await describeTable(client);
          console.log(`Stored ${rows} rows with ${dimensions}-dimension embeddings in ${table}`);
        } finally {
          // Roll back anything unfinished (a no-op after a commit), and remove
          // the table whether or not a step failed. A failure here is reported
          // on its own, so that it cannot hide the error that came first.
          try {
            await client.query("ROLLBACK");
            await dropTable(client);
          } catch (cleanupErr) {
            console.error(`Cleanup error: ${describe(cleanupErr)}`);
            cleanupFailed = true;
          }
        }
        return cleanupFailed ? 1 : 0;
      } catch (err) {
        console.error(`Error: ${describe(err)}`);
        return 1;
      } finally {
        // client is undefined if the program failed before it connected.
        await client?.end();
      }
    }
    
    process.exitCode = await main();
    
    ```

=== "Java"

    ```java
    /*
     * Ellie's Postgres Cookbook
     * Preparing documents for the pgEdge RAG Server: embedding them with
     * Ollama and storing them in a pgvector table, using java.net.http,
     * Jackson and the PostgreSQL JDBC driver (pgJDBC).
     *
     * These examples are for pgEdge RAG Server 2.0.0.
     *
     * Copyright (c) 2026, pgEdge, Inc.
     * This code is released under the PostgreSQL License.
     */
    
    import java.io.IOException;
    import java.net.URI;
    import java.net.http.HttpClient;
    import java.net.http.HttpRequest;
    import java.net.http.HttpResponse;
    import java.net.http.HttpTimeoutException;
    import java.sql.Connection;
    import java.sql.DriverManager;
    import java.sql.PreparedStatement;
    import java.sql.ResultSet;
    import java.sql.SQLException;
    import java.sql.Statement;
    import java.time.Duration;
    import java.util.ArrayList;
    import java.util.List;
    import java.util.Properties;
    import java.util.StringJoiner;
    import java.util.concurrent.CompletableFuture;
    import java.util.concurrent.ExecutionException;
    import java.util.concurrent.TimeUnit;
    import java.util.concurrent.TimeoutException;
    
    import tools.jackson.core.JacksonException;
    import tools.jackson.databind.JsonNode;
    import tools.jackson.databind.ObjectMapper;
    import tools.jackson.databind.json.JsonMapper;
    import tools.jackson.databind.node.ObjectNode;
    
    public class Main {
    
        /** Returns the value of an environment variable, or a fallback. */
        static String envOr(String name, String fallback) {
            String value = System.getenv(name);
            return (value != null && !value.isEmpty()) ? value : fallback;
        }
    
        static final String OLLAMA_URL =
                envOr("OLLAMA_URL", "http://localhost:11434").replaceAll("/+$", "");
        static final String EMBED_MODEL = envOr("EMBED_MODEL", "nomic-embed-text");
    
        // This recipe uses its own table, so that it never disturbs the table
        // that a running pipeline reads.
        static final String TABLE = "cookbook_prepare_data";
    
        /** A row to store. */
        record Document(int id, String title, String content) {}
    
        // The documents to store; in a real application they come from your
        // own data. The text is fictional.
        static final List<Document> DOCUMENTS = List.of(
                new Document(1, "Charging the Acme Gadget",
                        "The Acme Gadget charges through its USB-C port. A full charge takes "
                        + "two hours, and a fully charged Acme Gadget runs for ten hours."),
                new Document(2, "Resetting the Acme Gadget",
                        "To reset the Acme Gadget to its factory settings, hold down the "
                        + "power button for eight seconds until the status light flashes red."),
                new Document(3, "Warranty for the Acme Gadget",
                        "The Acme Gadget comes with a two-year warranty that covers "
                        + "manufacturing defects but not accidental damage."));
    
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
    
        // A mapper is safe to share, so the program creates only one.
        static final ObjectMapper MAPPER = JsonMapper.builder().build();
    
        /** Thrown when Ollama rejects a request or returns an unexpected reply. */
        static class EmbedException extends Exception {
            EmbedException(String message) {
                super(message);
            }
        }
    
        /**
         * Sends a request and returns the response with its whole body. The
         * request timeout stops applying once the headers arrive, so a server
         * that stalls part of the way through the body would hang send(); this
         * applies the same timeout to the whole exchange instead.
         */
        static HttpResponse<String> send(HttpClient client, HttpRequest request)
                throws IOException, InterruptedException {
            Duration timeout = request.timeout().orElseThrow();
            CompletableFuture<HttpResponse<String>> pending =
                    client.sendAsync(request, HttpResponse.BodyHandlers.ofString());
            try {
                return pending.get(timeout.toMillis(), TimeUnit.MILLISECONDS);
            } catch (TimeoutException e) {
                pending.cancel(true);
                throw new HttpTimeoutException("request timed out");
            } catch (ExecutionException e) {
                if (e.getCause() instanceof IOException cause) {
                    throw cause;
                }
                throw new IOException(e.getCause());
            }
        }
    
        /**
         * Asks Ollama for the embedding of each text, in the same order.
         * pgvector stores single-precision values, so a float loses nothing
         * that the table would keep.
         */
        static List<float[]> embed(List<String> texts)
                throws IOException, InterruptedException, EmbedException {
            // The embed endpoint accepts a list of texts, so one request embeds
            // every document.
            ObjectNode payload = MAPPER.createObjectNode().put("model", EMBED_MODEL);
            texts.forEach(payload.putArray("input")::add);
    
            HttpRequest request = HttpRequest.newBuilder(URI.create(OLLAMA_URL + "/api/embed"))
                    .timeout(Duration.ofSeconds(300))
                    .header("Content-Type", "application/json")
                    .POST(HttpRequest.BodyPublishers.ofString(MAPPER.writeValueAsString(payload)))
                    .build();
            HttpResponse<String> response = send(HttpClient.newHttpClient(), request);
    
            // The client treats an error status as a normal response, so check
            // it here.
            if (response.statusCode() != 200) {
                String body = response.body().strip();
                throw new EmbedException("Ollama returned HTTP " + response.statusCode()
                        + ": " + body.substring(0, Math.min(body.length(), 200)));
            }
    
            // path() returns a missing node, rather than null, for a field that
            // is not there, and a missing node holds no elements.
            List<float[]> embeddings = new ArrayList<>();
            for (JsonNode node : MAPPER.readTree(response.body()).path("embeddings")) {
                float[] embedding = new float[node.size()];
                for (int i = 0; i < embedding.length; i++) {
                    embedding[i] = node.get(i).floatValue();
                }
                embeddings.add(embedding);
            }
            if (embeddings.size() != texts.size()) {
                throw new EmbedException("Expected " + texts.size()
                        + " embeddings, got " + embeddings.size());
            }
            return embeddings;
        }
    
        /**
         * Creates the table, replacing any earlier copy. The vector column
         * must have the same number of dimensions as the embedding model.
         */
        static void createTable(Connection conn, int dimensions) throws SQLException {
            try (Statement stmt = conn.createStatement()) {
                stmt.execute("CREATE EXTENSION IF NOT EXISTS vector");
                stmt.execute("DROP TABLE IF EXISTS " + TABLE);
                // The table name is a constant and the dimensions are an int,
                // so building them into the statement is safe; a statement
                // cannot take either as a parameter.
                stmt.execute("""
                        CREATE TABLE %s (
                            id        integer PRIMARY KEY,
                            title     text NOT NULL,
                            content   text NOT NULL,
                            embedding vector(%d) NOT NULL
                        )""".formatted(TABLE, dimensions));
            }
        }
    
        /** Stores each document with its embedding, in a single batch. */
        static void insertDocuments(Connection conn, List<float[]> embeddings)
                throws SQLException {
            String sql = "INSERT INTO " + TABLE + " (id, title, content, embedding) "
                    + "VALUES (?, ?, ?, ?::vector)";
            try (PreparedStatement stmt = conn.prepareStatement(sql)) {
                for (int i = 0; i < DOCUMENTS.size(); i++) {
                    Document doc = DOCUMENTS.get(i);
                    // pgvector reads a vector from text such as
                    // '[0.1,0.2,0.3]', and the cast tells the server how to
                    // interpret the parameter.
                    StringJoiner vector = new StringJoiner(",", "[", "]");
                    for (float value : embeddings.get(i)) {
                        vector.add(Float.toString(value));
                    }
                    stmt.setInt(1, doc.id());
                    stmt.setString(2, doc.title());
                    stmt.setString(3, doc.content());
                    stmt.setString(4, vector.toString());
                    stmt.addBatch();
                }
                stmt.executeBatch();
            }
        }
    
        /**
         * Returns the number of rows, and the number of dimensions of their
         * embeddings.
         */
        static long[] describeTable(Connection conn) throws SQLException {
            try (Statement stmt = conn.createStatement();
                 ResultSet rs = stmt.executeQuery(
                         "SELECT count(*), max(vector_dims(embedding)) FROM " + TABLE)) {
                rs.next();
                return new long[] {rs.getLong(1), rs.getLong(2)};
            }
        }
    
        /**
         * Removes the table. A real application keeps it, so that the RAG
         * Server can read it.
         */
        static void dropTable(Connection conn) throws SQLException {
            try (Statement stmt = conn.createStatement()) {
                stmt.execute("DROP TABLE IF EXISTS " + TABLE);
            }
        }
    
        /**
         * Creates the table and inserts the documents in one transaction,
         * rolling it back if a step fails.
         */
        static void store(Connection conn, List<float[]> embeddings) throws SQLException {
            conn.setAutoCommit(false);
            try {
                createTable(conn, embeddings.get(0).length);
                insertDocuments(conn, embeddings);
                conn.commit();
            } catch (SQLException e) {
                // Attach any failure to roll back to the first error, rather
                // than letting it replace that error.
                try {
                    conn.rollback();
                } catch (SQLException rollbackError) {
                    e.addSuppressed(rollbackError);
                }
                throw e;
            } finally {
                conn.setAutoCommit(true);
            }
        }
    
        public static void main(String[] args) {
            boolean cleanupFailed = false;
            try {
                List<float[]> embeddings =
                        embed(DOCUMENTS.stream().map(Document::content).toList());
                System.out.println("Embedded " + embeddings.size()
                        + " documents with " + EMBED_MODEL);
    
                // try-with-resources closes the connection when the block
                // exits, whether or not an error occurred.
                try (Connection conn = DriverManager.getConnection(
                        connectionUrl(), connectionProperties())) {
                    try {
                        store(conn, embeddings);
                        long[] summary = describeTable(conn);
                        System.out.println("Stored " + summary[0] + " rows with "
                                + summary[1] + "-dimension embeddings in " + TABLE);
                    } finally {
                        // Remove the table whether or not a step failed. A
                        // failure here is reported on its own, so that it
                        // cannot hide the error that came first.
                        try {
                            dropTable(conn);
                        } catch (SQLException e) {
                            System.err.println("Cleanup error: " + e.getMessage());
                            cleanupFailed = true;
                        }
                    }
                }
            // IOException covers failures to reach Ollama, such as a refused
            // connection or a timeout. The message of a refused connection can
            // be empty, so print the exception itself, which includes its type.
            } catch (IOException | InterruptedException e) {
                System.err.println("Error: " + e);
                System.exit(1);
            // SQLException covers connection failures and errors reported by
            // the server, and JacksonException covers a reply that is not JSON.
            } catch (SQLException | EmbedException | JacksonException e) {
                System.err.println("Error: " + e.getMessage());
                System.exit(1);
            }
            if (cleanupFailed) {
                System.exit(1);
            }
        }
    }
    
    ```

=== "C#"

    ```csharp
    /*
     * Ellie's Postgres Cookbook
     * Preparing documents for the pgEdge RAG Server: embedding them with
     * Ollama and storing them in a pgvector table, using HttpClient,
     * System.Text.Json and Npgsql.
     *
     * These examples are for pgEdge RAG Server 2.0.0.
     *
     * Copyright (c) 2026, pgEdge, Inc.
     * This code is released under the PostgreSQL License.
     */
    
    using System.Globalization;
    using System.Net.Http.Json;
    using System.Text.Json;
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
    
    static string OllamaUrl() =>
        EnvOr("OLLAMA_URL", "http://localhost:11434").TrimEnd('/');
    static string EmbedModel() => EnvOr("EMBED_MODEL", "nomic-embed-text");
    
    // This recipe uses its own table, so that it never disturbs the table that
    // a running pipeline reads.
    const string Table = "cookbook_prepare_data";
    
    // The documents to store; in a real application they come from your own
    // data. The text is fictional.
    Document[] documents =
    [
        new(1, "Charging the Acme Gadget",
            "The Acme Gadget charges through its USB-C port. A full charge takes " +
            "two hours, and a fully charged Acme Gadget runs for ten hours."),
        new(2, "Resetting the Acme Gadget",
            "To reset the Acme Gadget to its factory settings, hold down the " +
            "power button for eight seconds until the status light flashes red."),
        new(3, "Warranty for the Acme Gadget",
            "The Acme Gadget comes with a two-year warranty that covers " +
            "manufacturing defects but not accidental damage."),
    ];
    
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
    
    // Asks Ollama for the embedding of each text, in the same order. pgvector
    // stores single-precision values, so a float loses nothing that the table
    // would keep.
    static async Task<float[][]> EmbedAsync(string[] texts)
    {
        using var client = new HttpClient { Timeout = TimeSpan.FromSeconds(300) };
        // The embed endpoint accepts a list of texts, so one request embeds
        // every document.
        using var response = await client.PostAsJsonAsync(
            $"{OllamaUrl()}/api/embed", new { model = EmbedModel(), input = texts });
    
        // HttpClient treats an error status as a normal response, so check it
        // here.
        if (!response.IsSuccessStatusCode)
        {
            var body = (await response.Content.ReadAsStringAsync()).Trim();
            throw new EmbedException(
                $"Ollama returned HTTP {(int)response.StatusCode}: " +
                body[..Math.Min(body.Length, 200)]);
        }
    
        // ReadFromJsonAsync matches the embeddings field to the Embeddings
        // property without regard to case, and leaves it null if it is missing.
        var reply = await response.Content.ReadFromJsonAsync<EmbedReply>();
        if (reply?.Embeddings is not { } embeddings || embeddings.Length != texts.Length)
        {
            throw new EmbedException(
                $"Expected {texts.Length} embeddings, got {reply?.Embeddings?.Length ?? 0}");
        }
        return embeddings;
    }
    
    // Creates the table, replacing any earlier copy. The vector column must
    // have the same number of dimensions as the embedding model.
    static async Task CreateTableAsync(NpgsqlConnection conn, int dimensions)
    {
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = "CREATE EXTENSION IF NOT EXISTS vector";
        await cmd.ExecuteNonQueryAsync();
        cmd.CommandText = $"DROP TABLE IF EXISTS {Table}";
        await cmd.ExecuteNonQueryAsync();
        // The table name is a constant and the dimensions are an int, so
        // building them into the statement is safe; a statement cannot take
        // either as a parameter.
        cmd.CommandText = $"""
            CREATE TABLE {Table} (
                id        integer PRIMARY KEY,
                title     text NOT NULL,
                content   text NOT NULL,
                embedding vector({dimensions}) NOT NULL
            )
            """;
        await cmd.ExecuteNonQueryAsync();
    }
    
    // Stores each document with its embedding.
    static async Task InsertDocumentsAsync(
        NpgsqlConnection conn, Document[] documents, float[][] embeddings)
    {
        for (var i = 0; i < documents.Length; i++)
        {
            // pgvector reads a vector from text such as '[0.1,0.2,0.3]'. The
            // invariant culture always writes a full stop as the decimal
            // separator, and the cast tells the server how to interpret the
            // parameter.
            var vector = "[" + string.Join(",", embeddings[i].Select(
                value => value.ToString(CultureInfo.InvariantCulture))) + "]";
            await using var cmd = new NpgsqlCommand(
                $"INSERT INTO {Table} (id, title, content, embedding) " +
                "VALUES ($1, $2, $3, $4::vector)", conn)
            {
                Parameters =
                {
                    new() { Value = documents[i].Id },
                    new() { Value = documents[i].Title },
                    new() { Value = documents[i].Content },
                    new() { Value = vector },
                },
            };
            await cmd.ExecuteNonQueryAsync();
        }
    }
    
    // Returns the number of rows, and the number of dimensions of their
    // embeddings. count(*) returns a bigint, which maps to long, and
    // vector_dims() returns an integer, which maps to int.
    static async Task<(long Rows, int Dimensions)> DescribeTableAsync(NpgsqlConnection conn)
    {
        await using var cmd = new NpgsqlCommand(
            $"SELECT count(*), max(vector_dims(embedding)) FROM {Table}", conn);
        await using var reader = await cmd.ExecuteReaderAsync();
        await reader.ReadAsync();
        return (reader.GetInt64(0), reader.GetInt32(1));
    }
    
    // Removes the table. A real application keeps it, so that the RAG Server
    // can read it.
    static async Task DropTableAsync(NpgsqlConnection conn)
    {
        await using var cmd = new NpgsqlCommand($"DROP TABLE IF EXISTS {Table}", conn);
        await cmd.ExecuteNonQueryAsync();
    }
    
    var cleanupFailed = false;
    try
    {
        var embeddings = await EmbedAsync([.. documents.Select(doc => doc.Content)]);
        Console.WriteLine($"Embedded {embeddings.Length} documents with {EmbedModel()}");
    
        // await using disposes of the data source and the connection when the
        // block exits, whether or not an error occurred.
        await using var dataSource = NpgsqlDataSource.Create(ConnectionString());
        await using var conn = await dataSource.OpenConnectionAsync();
        try
        {
            // Disposing of a transaction that has not been committed rolls it
            // back, so a failed step undoes every step before it.
            await using (var tx = await conn.BeginTransactionAsync())
            {
                await CreateTableAsync(conn, embeddings[0].Length);
                await InsertDocumentsAsync(conn, documents, embeddings);
                await tx.CommitAsync();
            }
    
            var (rows, dimensions) = await DescribeTableAsync(conn);
            Console.WriteLine(
                $"Stored {rows} rows with {dimensions}-dimension embeddings in {Table}");
        }
        finally
        {
            // Remove the table whether or not a step failed. A failure here is
            // reported on its own, so that it cannot hide the error that came
            // first.
            try
            {
                await DropTableAsync(conn);
            }
            catch (NpgsqlException e)
            {
                Console.Error.WriteLine($"Cleanup error: {e.Message}");
                cleanupFailed = true;
            }
        }
    }
    // HttpRequestException covers failures to reach Ollama, such as a refused
    // connection, TaskCanceledException covers a timeout, JsonException covers
    // a reply that is not JSON, and NpgsqlException covers connection failures
    // and errors reported by the server.
    catch (Exception e) when (e is HttpRequestException or TaskCanceledException
        or JsonException or NpgsqlException or EmbedException)
    {
        Console.Error.WriteLine($"Error: {e.Message}");
        return 1;
    }
    
    return cleanupFailed ? 1 : 0;
    
    // C# requires type declarations to follow the top-level statements, so the
    // types that the program uses are declared here, at the end.
    
    // A row to store.
    record Document(int Id, string Title, string Content);
    
    // The part of Ollama's reply that the program reads.
    record EmbedReply(float[][]? Embeddings);
    
    // Thrown when Ollama rejects a request or returns an unexpected reply.
    class EmbedException(string message) : Exception(message);
    
    ```

=== "Go"

    ```go
    // Ellie's Postgres Cookbook
    // Preparing documents for the pgEdge RAG Server: embedding them with
    // Ollama and storing them in a pgvector table, using net/http and pgx.
    //
    // These examples are for pgEdge RAG Server 2.0.0.
    //
    // Copyright (c) 2026, pgEdge, Inc.
    // This code is released under the PostgreSQL License.
    
    package main
    
    import (
    	"bytes"
    	"context"
    	"encoding/json"
    	"fmt"
    	"io"
    	"net"
    	"net/http"
    	"net/url"
    	"os"
    	"strconv"
    	"strings"
    	"time"
    
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
    
    var (
    	ollamaURL  = strings.TrimRight(envOr("OLLAMA_URL", "http://localhost:11434"), "/")
    	embedModel = envOr("EMBED_MODEL", "nomic-embed-text")
    )
    
    // This recipe uses its own table, so that it never disturbs the table that
    // a running pipeline reads.
    const table = "cookbook_prepare_data"
    
    // document is a row to store. The text is fictional; in a real
    // application the documents come from your own data.
    type document struct {
    	ID      int
    	Title   string
    	Content string
    }
    
    var documents = []document{
    	{1, "Charging the Acme Gadget",
    		"The Acme Gadget charges through its USB-C port. A full charge takes " +
    			"two hours, and a fully charged Acme Gadget runs for ten hours."},
    	{2, "Resetting the Acme Gadget",
    		"To reset the Acme Gadget to its factory settings, hold down the " +
    			"power button for eight seconds until the status light flashes red."},
    	{3, "Warranty for the Acme Gadget",
    		"The Acme Gadget comes with a two-year warranty that covers " +
    			"manufacturing defects but not accidental damage."},
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
    
    
    // embed asks Ollama for the embedding of each text, in the same order.
    func embed(texts []string) ([][]float32, error) {
    	// The embed endpoint accepts a list of texts, so one request embeds
    	// every document.
    	payload, err := json.Marshal(map[string]any{"model": embedModel, "input": texts})
    	if err != nil {
    		return nil, err
    	}
    
    	client := &http.Client{Timeout: 300 * time.Second}
    	response, err := client.Post(ollamaURL+"/api/embed", "application/json", bytes.NewReader(payload))
    	if err != nil {
    		return nil, err
    	}
    	defer response.Body.Close()
    
    	body, err := io.ReadAll(response.Body)
    	if err != nil {
    		return nil, err
    	}
    	// Go treats an error status as a normal response, so check it here.
    	if response.StatusCode != http.StatusOK {
    		return nil, fmt.Errorf("ollama returned HTTP %d: %.200s", response.StatusCode, body)
    	}
    
    	var result struct {
    		Embeddings [][]float32 `json:"embeddings"`
    	}
    	if err := json.Unmarshal(body, &result); err != nil {
    		return nil, fmt.Errorf("unexpected response from ollama: %w", err)
    	}
    	if len(result.Embeddings) != len(texts) {
    		return nil, fmt.Errorf("expected %d embeddings, got %d", len(texts), len(result.Embeddings))
    	}
    	return result.Embeddings, nil
    }
    
    
    // createTable creates the table, replacing any earlier copy. The vector
    // column must have the same number of dimensions as the embedding model.
    func createTable(ctx context.Context, tx pgx.Tx, dimensions int) error {
    	if _, err := tx.Exec(ctx, "CREATE EXTENSION IF NOT EXISTS vector"); err != nil {
    		return err
    	}
    	if _, err := tx.Exec(ctx, "DROP TABLE IF EXISTS "+table); err != nil {
    		return err
    	}
    	// The table name is a constant and the dimensions are an integer, so
    	// building them into the statement is safe; a statement cannot take
    	// either as a parameter.
    	_, err := tx.Exec(ctx, `
    		CREATE TABLE `+table+` (
    			id        integer PRIMARY KEY,
    			title     text NOT NULL,
    			content   text NOT NULL,
    			embedding vector(`+strconv.Itoa(dimensions)+`) NOT NULL
    		)`)
    	return err
    }
    
    
    // vectorText formats an embedding as the text that pgvector reads, such as
    // '[0.1,0.2,0.3]'.
    func vectorText(embedding []float32) string {
    	parts := make([]string, len(embedding))
    	for i, value := range embedding {
    		parts[i] = strconv.FormatFloat(float64(value), 'g', -1, 32)
    	}
    	return "[" + strings.Join(parts, ",") + "]"
    }
    
    // insertDocuments stores each document with its embedding.
    func insertDocuments(ctx context.Context, tx pgx.Tx, embeddings [][]float32) error {
    	for i, doc := range documents {
    		// The cast tells the server how to interpret the text parameter.
    		_, err := tx.Exec(ctx,
    			"INSERT INTO "+table+" (id, title, content, embedding) VALUES ($1, $2, $3, $4::vector)",
    			doc.ID, doc.Title, doc.Content, vectorText(embeddings[i]))
    		if err != nil {
    			return err
    		}
    	}
    	return nil
    }
    
    
    // describeTable returns the number of rows, and the number of dimensions
    // of their embeddings.
    func describeTable(ctx context.Context, conn *pgx.Conn) (rows, dimensions int, err error) {
    	err = conn.QueryRow(ctx,
    		"SELECT count(*), max(vector_dims(embedding)) FROM "+table,
    	).Scan(&rows, &dimensions)
    	return rows, dimensions, err
    }
    
    
    // dropTable removes the table. A real application keeps it, so that the
    // RAG Server can read it.
    func dropTable(ctx context.Context, conn *pgx.Conn) error {
    	_, err := conn.Exec(ctx, "DROP TABLE IF EXISTS "+table)
    	return err
    }
    
    
    // store creates the table and inserts the documents in one transaction.
    func store(ctx context.Context, conn *pgx.Conn, embeddings [][]float32) error {
    	tx, err := conn.Begin(ctx)
    	if err != nil {
    		return err
    	}
    	// Rollback does nothing after a successful commit, so the deferred
    	// call only matters when a step fails.
    	defer tx.Rollback(ctx)
    
    	if err := createTable(ctx, tx, len(embeddings[0])); err != nil {
    		return err
    	}
    	if err := insertDocuments(ctx, tx, embeddings); err != nil {
    		return err
    	}
    	return tx.Commit(ctx)
    }
    
    // run embeds the documents, stores them, and reports what the table
    // holds, returning any error to the caller.
    func run(ctx context.Context) (err error) {
    	texts := make([]string, len(documents))
    	for i, doc := range documents {
    		texts[i] = doc.Content
    	}
    	embeddings, err := embed(texts)
    	if err != nil {
    		return fmt.Errorf("embedding failed: %w", err)
    	}
    	fmt.Printf("Embedded %d documents with %s\n", len(embeddings), embedModel)
    
    	conn, err := pgx.Connect(ctx, connString())
    	if err != nil {
    		return fmt.Errorf("connection failed: %w", err)
    	}
    	defer conn.Close(ctx)
    
    	// Remove the table whether or not a step failed. A failure to remove it
    	// becomes the returned error only when there is no earlier error, and
    	// is printed on its own otherwise, so that it cannot hide the first.
    	defer func() {
    		if dropErr := dropTable(ctx, conn); dropErr != nil {
    			if err == nil {
    				err = dropErr
    			} else {
    				fmt.Fprintf(os.Stderr, "Cleanup error: %v\n", dropErr)
    			}
    		}
    	}()
    
    	if err := store(ctx, conn, embeddings); err != nil {
    		return fmt.Errorf("storing the documents failed: %w", err)
    	}
    
    	rows, dimensions, err := describeTable(ctx, conn)
    	if err != nil {
    		return fmt.Errorf("query failed: %w", err)
    	}
    	fmt.Printf("Stored %d rows with %d-dimension embeddings in %s\n", rows, dimensions, table)
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
    // Preparing documents for the pgEdge RAG Server: embedding them with
    // Ollama and storing them in a pgvector table, using reqwest, serde_json
    // and the postgres crate.
    //
    // These examples are for pgEdge RAG Server 2.0.0.
    //
    // Copyright (c) 2026, pgEdge, Inc.
    // This code is released under the PostgreSQL License.
    
    use std::env;
    use std::error::Error;
    use std::process::ExitCode;
    use std::time::Duration;
    
    use postgres::{Client, Config, NoTls, Transaction};
    use serde_json::{json, Value};
    
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
    
    fn ollama_url() -> String {
        env_or("OLLAMA_URL", "http://localhost:11434")
            .trim_end_matches('/')
            .to_string()
    }
    
    fn embed_model() -> String {
        env_or("EMBED_MODEL", "nomic-embed-text")
    }
    
    /// This recipe uses its own table, so that it never disturbs the table
    /// that a running pipeline reads.
    const TABLE: &str = "cookbook_prepare_data";
    
    /// The documents to store, as (id, title, content); in a real application
    /// they come from your own data. The text is fictional.
    const DOCUMENTS: [(i32, &str, &str); 3] = [
        (
            1,
            "Charging the Acme Gadget",
            "The Acme Gadget charges through its USB-C port. A full charge takes \
             two hours, and a fully charged Acme Gadget runs for ten hours.",
        ),
        (
            2,
            "Resetting the Acme Gadget",
            "To reset the Acme Gadget to its factory settings, hold down the \
             power button for eight seconds until the status light flashes red.",
        ),
        (
            3,
            "Warranty for the Acme Gadget",
            "The Acme Gadget comes with a two-year warranty that covers \
             manufacturing defects but not accidental damage.",
        ),
    ];
    
    /// The errors that the functions below return; a string converts into one
    /// with the ? operator or into().
    type BoxError = Box<dyn Error>;
    
    /// Builds the connection configuration from the standard libpq
    /// environment variables, with defaults suitable for a local server.
    fn config() -> Result<Config, BoxError> {
        let mut config = Config::new();
        config
            .host(&env_or("PGHOST", "localhost"))
            .port(env_or("PGPORT", "5432").parse()?)
            .dbname(&env_or("PGDATABASE", "postgres"))
            .user(&env_or("PGUSER", "postgres"));
        if let Some(password) = env_value("PGPASSWORD") {
            config.password(&password);
        }
        Ok(config)
    }
    
    /// Asks Ollama for the embedding of each text, in the same order.
    /// pgvector stores single-precision values, so f32 loses nothing that the
    /// table would keep.
    fn embed(texts: &[&str]) -> Result<Vec<Vec<f32>>, BoxError> {
        let client = reqwest::blocking::Client::builder()
            .timeout(Duration::from_secs(300))
            .build()?;
        // The embed endpoint accepts a list of texts, so one request embeds
        // every document.
        let response = client
            .post(format!("{}/api/embed", ollama_url()))
            .json(&json!({ "model": embed_model(), "input": texts }))
            .send()?;
    
        // reqwest treats an error status as a normal response, so check it
        // here.
        let status = response.status();
        if !status.is_success() {
            let body = response.text()?;
            let body: String = body.trim().chars().take(200).collect();
            return Err(format!("Ollama returned HTTP {}: {body}", status.as_u16()).into());
        }
    
        let mut reply: Value = response.json()?;
        let embeddings: Vec<Vec<f32>> = serde_json::from_value(reply["embeddings"].take())?;
        if embeddings.len() != texts.len() {
            return Err(format!("Expected {} embeddings, got {}", texts.len(), embeddings.len()).into());
        }
        Ok(embeddings)
    }
    
    /// Creates the table, replacing any earlier copy. The vector column must
    /// have the same number of dimensions as the embedding model.
    fn create_table(tx: &mut Transaction, dimensions: usize) -> Result<(), postgres::Error> {
        tx.batch_execute("CREATE EXTENSION IF NOT EXISTS vector")?;
        tx.batch_execute(&format!("DROP TABLE IF EXISTS {TABLE}"))?;
        // The table name is a constant and the dimensions are an integer, so
        // building them into the statement is safe; a statement cannot take
        // either as a parameter.
        tx.batch_execute(&format!(
            "CREATE TABLE {TABLE} (
                id        integer PRIMARY KEY,
                title     text NOT NULL,
                content   text NOT NULL,
                embedding vector({dimensions}) NOT NULL
            )"
        ))
    }
    
    /// Stores each document with its embedding.
    fn insert_documents(tx: &mut Transaction, embeddings: &[Vec<f32>]) -> Result<(), postgres::Error> {
        // The driver checks each value against the type the server expects,
        // and a Rust string cannot be sent as a vector, so the parameter is
        // declared as text and then cast to a vector.
        let statement = tx.prepare(&format!(
            "INSERT INTO {TABLE} (id, title, content, embedding) \
             VALUES ($1, $2, $3, $4::text::vector)"
        ))?;
        for ((id, title, content), embedding) in DOCUMENTS.iter().zip(embeddings) {
            // pgvector reads a vector from text such as '[0.1,0.2,0.3]'.
            let values: Vec<String> = embedding.iter().map(|value| value.to_string()).collect();
            let vector = format!("[{}]", values.join(","));
            tx.execute(&statement, &[id, title, content, &vector])?;
        }
        Ok(())
    }
    
    /// Returns the number of rows, and the number of dimensions of their
    /// embeddings. count(*) returns a bigint, which maps to i64, and
    /// vector_dims() returns an integer, which maps to i32.
    fn describe_table(client: &mut Client) -> Result<(i64, i32), postgres::Error> {
        let row = client.query_one(
            &format!("SELECT count(*), max(vector_dims(embedding)) FROM {TABLE}"),
            &[],
        )?;
        Ok((row.get(0), row.get(1)))
    }
    
    /// Removes the table. A real application keeps it, so that the RAG Server
    /// can read it.
    fn drop_table(client: &mut Client) -> Result<(), postgres::Error> {
        client.batch_execute(&format!("DROP TABLE IF EXISTS {TABLE}"))
    }
    
    /// Creates the table and inserts the documents in one transaction, then
    /// reports what the table holds.
    fn store(client: &mut Client, embeddings: &[Vec<f32>]) -> Result<(), BoxError> {
        // Dropping a transaction without committing it rolls it back, so a ?
        // that returns early undoes every step.
        let mut tx = client.transaction()?;
        create_table(&mut tx, embeddings[0].len())?;
        insert_documents(&mut tx, embeddings)?;
        tx.commit()?;
    
        let (rows, dimensions) = describe_table(client)?;
        println!("Stored {rows} rows with {dimensions}-dimension embeddings in {TABLE}");
        Ok(())
    }
    
    /// Embeds the documents, stores them, and removes the table again. The ?
    /// operator returns any error to the caller.
    fn run() -> Result<(), BoxError> {
        let texts: Vec<&str> = DOCUMENTS.iter().map(|(_, _, content)| *content).collect();
        let embeddings = embed(&texts)?;
        println!("Embedded {} documents with {}", embeddings.len(), embed_model());
    
        // NoTls disables TLS, which keeps this example free of certificate
        // set-up; connections over an untrusted network should use TLS.
        let mut client = config()?.connect(NoTls)?;
        let result = store(&mut client, &embeddings);
    
        // Remove the table whether or not a step failed. A failure to remove
        // it becomes the returned error only when there is no earlier error,
        // and is printed on its own otherwise, so that it cannot hide the
        // first.
        match (result, drop_table(&mut client)) {
            (Ok(()), Err(e)) => Err(format!("Cleanup error: {e}").into()),
            (Err(e), Err(cleanup)) => {
                eprintln!("Cleanup error: {cleanup}");
                Err(e)
            }
            (result, Ok(())) => result,
        }
    }
    
    /// Reports any error returned by run() and exits with a failure status.
    /// The top-level error is often generic ("error sending request"), so the
    /// chain of underlying causes is printed too.
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
    # Preparing documents for the pgEdge RAG Server: embedding them with Ollama
    # and storing them in a pgvector table, using Net::HTTP and the pg gem.
    #
    # These examples are for pgEdge RAG Server 2.0.0.
    #
    # Copyright (c) 2026, pgEdge, Inc.
    # This code is released under the PostgreSQL License.
    
    require "json"
    require "net/http"
    require "pg"
    require "uri"
    
    # Returns the value of an environment variable, or a fallback if the
    # variable is unset or empty; libpq also treats an empty variable as unset.
    def env_or(name, fallback)
      value = ENV[name]
      value.nil? || value.empty? ? fallback : value
    end
    
    OLLAMA_URL = env_or("OLLAMA_URL", "http://localhost:11434").sub(%r{/+\z}, "")
    EMBED_MODEL = env_or("EMBED_MODEL", "nomic-embed-text")
    
    # This recipe uses its own table, so that it never disturbs the table that
    # a running pipeline reads.
    TABLE = "cookbook_prepare_data"
    
    # The documents to store, as [id, title, content]; in a real application
    # they come from your own data. The text is fictional.
    DOCUMENTS = [
      [1, "Charging the Acme Gadget",
       "The Acme Gadget charges through its USB-C port. A full charge takes " \
       "two hours, and a fully charged Acme Gadget runs for ten hours."],
      [2, "Resetting the Acme Gadget",
       "To reset the Acme Gadget to its factory settings, hold down the " \
       "power button for eight seconds until the status light flashes red."],
      [3, "Warranty for the Acme Gadget",
       "The Acme Gadget comes with a two-year warranty that covers " \
       "manufacturing defects but not accidental damage."]
    ].freeze
    
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
    
    # Raised when Ollama rejects a request or returns an unexpected reply.
    class EmbedError < StandardError; end
    
    # Asks Ollama for the embedding of each text, in the same order.
    def embed(texts)
      uri = URI("#{OLLAMA_URL}/api/embed")
      request = Net::HTTP::Post.new(uri, "Content-Type" => "application/json")
      # The embed endpoint accepts a list of texts, so one request embeds
      # every document.
      request.body = JSON.generate({ model: EMBED_MODEL, input: texts })
    
      # start opens a connection, and closes it when the block exits, whether
      # or not an error occurred.
      response = Net::HTTP.start(
        uri.host, uri.port,
        use_ssl: uri.scheme == "https", open_timeout: 300, read_timeout: 300
      ) { |http| http.request(request) }
      # Net::HTTP treats an error status as a normal response, so check it
      # here.
      unless response.is_a?(Net::HTTPSuccess)
        raise EmbedError, "Ollama returned HTTP #{response.code}: #{response.body.to_s.strip[0, 200]}"
      end
    
      # fetch raises KeyError if the reply has no embeddings.
      embeddings = JSON.parse(response.body).fetch("embeddings")
      unless embeddings.is_a?(Array) && embeddings.length == texts.length
        raise EmbedError, "Expected #{texts.length} embeddings, got #{embeddings.inspect[0, 200]}"
      end
    
      embeddings
    end
    
    # Creates the table, replacing any earlier copy. The vector column must
    # have the same number of dimensions as the embedding model.
    def create_table(conn, dimensions)
      conn.exec("CREATE EXTENSION IF NOT EXISTS vector")
      conn.exec("DROP TABLE IF EXISTS #{TABLE}")
      # The table name is a constant and Integer() accepts only an integer, so
      # building them into the statement is safe; a statement cannot take
      # either as a parameter.
      conn.exec(<<~SQL)
        CREATE TABLE #{TABLE} (
            id        integer PRIMARY KEY,
            title     text NOT NULL,
            content   text NOT NULL,
            embedding vector(#{Integer(dimensions)}) NOT NULL
        )
      SQL
    end
    
    # Stores each document with its embedding.
    def insert_documents(conn, embeddings)
      DOCUMENTS.zip(embeddings).each do |(id, title, content), embedding|
        # pgvector reads a vector from text such as '[0.1,0.2,0.3]', and the
        # cast tells the server how to interpret the parameter.
        vector = "[#{embedding.join(",")}]"
        conn.exec_params(
          "INSERT INTO #{TABLE} (id, title, content, embedding) " \
          "VALUES ($1, $2, $3, $4::vector)",
          [id, title, content, vector]
        )
      end
    end
    
    # Returns the number of rows, and the number of dimensions of their
    # embeddings. Results arrive as strings, so convert them to Integers.
    def describe_table(conn)
      row = conn.exec("SELECT count(*), max(vector_dims(embedding)) FROM #{TABLE}")[0]
      [row["count"].to_i, row["max"].to_i]
    end
    
    # Removes the table. A real application keeps it, so that the RAG Server
    # can read it.
    def drop_table(conn)
      conn.exec("DROP TABLE IF EXISTS #{TABLE}")
    end
    
    cleanup_failed = false
    begin
      embeddings = embed(DOCUMENTS.map { |_, _, content| content })
      puts "Embedded #{embeddings.length} documents with #{EMBED_MODEL}"
    
      conn = PG.connect(connection_params)
      begin
        # transaction commits when the block finishes, and rolls back and
        # raises the error again if the block raises one.
        conn.transaction do
          create_table(conn, embeddings[0].length)
          insert_documents(conn, embeddings)
        end
    
        rows, dimensions = describe_table(conn)
        puts "Stored #{rows} rows with #{dimensions}-dimension embeddings in #{TABLE}"
      ensure
        # Remove the table whether or not a step failed. A failure here is
        # reported on its own, so that it cannot hide the error that came
        # first.
        begin
          drop_table(conn)
        rescue PG::Error => e
          warn "Cleanup error: #{e.message}"
          cleanup_failed = true
        end
      end
    # SystemCallError covers a refused connection to Ollama, Timeout::Error
    # covers its timeouts, SocketError covers an unknown host, JSON::ParserError
    # and KeyError cover a reply that is not what Ollama sends, and PG::Error
    # covers every error from the database.
    rescue EmbedError, SystemCallError, Timeout::Error, SocketError, IOError,
           JSON::ParserError, KeyError, PG::Error => e
      warn "Error: #{e.message}"
      exit 1
    # The ensure block runs whether or not an error occurred. conn is nil if
    # the connection attempt failed, hence the safe navigation operator.
    ensure
      conn&.close
    end
    
    exit 1 if cleanup_failed
    
    ```

## Next Steps

The following resources provide more information about the topics in this
recipe:

- The [Asking a Question](ask_question.md) recipe sends a question to a
  pipeline.
- The [Streaming an Answer](stream_answer.md) recipe displays an answer as
  the model writes it.
- The [Showing the Sources of an Answer](include_sources.md) recipe lists the
  documents that an answer came from.
- The
  [pgEdge RAG Server documentation](https://docs.pgedge.com/pgedge-rag-server/)
  describes the API and the pipeline configuration.
- The [Contributing a Recipe](../contributing.md) page explains how to add
  a recipe or a language to the cookbook.
