# Connecting to a Database

This recipe asks a pgEdge Control Plane server where a database's instances
listen, and then connects to one of them with an ordinary PostgreSQL driver.
The Control Plane chooses the address and port of each instance, so a client
that reads them from the API keeps working when a database moves or gains a
node. Each step shows the code in every supported language; selecting a
language tab switches every tab on the site to that language.

These examples are for the Control Plane v0.11.0.

The program prints the following output for the cookbook database:

```text
Connecting to node n1
Connected to database cookbook
Spock: 5.0.12
```

## Preparing the Ingredients

The examples assume a running Control Plane server with an available database,
and a database user with the `LOGIN` attribute. The
`scripts/start_control_plane.sh` script in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook)
starts a server in Docker and creates a database with the ID `cookbook` and a
`cookbook` user, and prints the password that it generated for that user.

The program reads the database with a `GET /v1/databases/{id}` request. Each
entry in the `instances` array of the reply runs one node of the database,
and has a `state`, a `node_name`, and a `connection_info` object that holds
the `addresses` and `port` that clients use. The `spec` of the database holds
its `database_name`. The Control Plane never returns a password, so the
program reads the password from the environment.

The following table lists the PostgreSQL driver that each example uses
alongside its HTTP client:

| Language   | PostgreSQL driver                                               |
|------------|-----------------------------------------------------------------|
| Python     | [psycopg](https://www.psycopg.org/psycopg3/)                    |
| TypeScript | [node-postgres](https://node-postgres.com/)                     |
| Java       | [pgJDBC](https://jdbc.postgresql.org/)                          |
| C#         | [Npgsql](https://www.npgsql.org/)                               |
| Go         | [pgx](https://github.com/jackc/pgx)                             |
| Rust       | [rust-postgres](https://github.com/rust-postgres/rust-postgres) |
| Ruby       | [ruby-pg](https://github.com/ged/ruby-pg)                       |
| curl       | [psql](https://www.postgresql.org/docs/current/app-psql.html)   |

The following tabs show the dependency declaration from each example project:

=== "Python"

    ```text
    # httpx, an HTTP client with a requests-like API.
    httpx>=0.28,<1
    # psycopg 3, with the pre-built binary package that bundles libpq.
    psycopg[binary]>=3.2,<4
    ```

=== "TypeScript"

    ```json
    {
      "name": "connect-database",
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

Each program begins by importing its HTTP client, its JSON library and its
PostgreSQL driver. The curl script checks that `curl`, `jq` and `psql` are
installed. The following tabs show the imports for each language:

=== "Python"

    ```python
    import os
    import sys
    
    import httpx
    import psycopg
    ```

=== "TypeScript"

    ```typescript
    // Node.js provides fetch and AbortSignal as globals; pg is node-postgres.
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
    import java.sql.ResultSet;
    import java.sql.SQLException;
    import java.sql.Statement;
    import java.time.Duration;
    import java.util.Properties;
    import java.util.concurrent.CompletableFuture;
    import java.util.concurrent.ExecutionException;
    import java.util.concurrent.TimeUnit;
    import java.util.concurrent.TimeoutException;
    
    import tools.jackson.core.JacksonException;
    import tools.jackson.databind.JsonNode;
    import tools.jackson.databind.ObjectMapper;
    import tools.jackson.databind.json.JsonMapper;
    ```

=== "C#"

    ```csharp
    using System.Text.Json;
    using System.Text.Json.Nodes;
    using Npgsql;
    ```

=== "Go"

    ```go
    import (
    	"context"
    	"encoding/json"
    	"errors"
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
    
    use postgres::{Config, NoTls};
    use reqwest::blocking::Client;
    use serde_json::Value;
    ```

=== "Ruby"

    ```ruby
    require "json"
    require "net/http"
    require "pg"
    require "uri"
    ```

=== "curl"

    ```bash
    # Stop at the first failed command or unset variable, and treat a failure
    # anywhere in a pipeline as a failure of the whole pipeline.
    set -euo pipefail
    
    for tool in curl jq psql; do
        command -v "$tool" >/dev/null || { echo "Control Plane error: $tool is required" >&2; exit 1; }
    done
    ```

## Configuring the Program

The examples read their settings from environment variables, and treat an
empty value as unset. Each request, and the connection to the database, may
take up to 30 seconds. The following table describes the environment
variables:

| Variable                          | Default                 | Description                        |
|-----------------------------------|-------------------------|------------------------------------|
| `CONTROL_PLANE_URL`               | `http://localhost:3000` | The base URL of the Control Plane. |
| `CONTROL_PLANE_DATABASE_ID`       | `cookbook`              | The ID of the database.            |
| `CONTROL_PLANE_DATABASE_USER`     | `cookbook`              | The database user to connect as.   |
| `CONTROL_PLANE_DATABASE_PASSWORD` | None                    | The password of the database user. |

The following tabs show how each program reads its settings, and how it fetches
a path from the server:

=== "Python"

    ```python
    # The or operator treats an empty variable as unset. The password has no
    # default; the Control Plane never returns it, so it comes from whoever
    # created the database user.
    BASE_URL = (os.environ.get("CONTROL_PLANE_URL") or "http://localhost:3000").rstrip("/")
    DATABASE_ID = os.environ.get("CONTROL_PLANE_DATABASE_ID") or "cookbook"
    DATABASE_USER = os.environ.get("CONTROL_PLANE_DATABASE_USER") or "cookbook"
    DATABASE_PASSWORD = os.environ.get("CONTROL_PLANE_DATABASE_PASSWORD") or None
    
    TIMEOUT_SECONDS = 30
    
    
    class ControlPlaneError(Exception):
        """Raised when the Control Plane rejects a request or replies oddly."""
    
    
    def get(client: httpx.Client, path: str) -> dict:
        """Fetches a path from the server, and returns the decoded reply."""
        response = client.get(path)
        if response.is_error:
            raise ControlPlaneError(f"HTTP {response.status_code}, {response.text[:200]}")
        try:
            body = response.json()
            if isinstance(body, dict):
                return body
        except ValueError:
            pass
        raise ControlPlaneError(f"Unexpected response: {response.text[:200]}")
    ```

=== "TypeScript"

    ```typescript
    // The || operator, unlike ??, also treats an empty variable as unset. The
    // password has no default; the Control Plane never returns it, so it
    // comes from whoever created the database user.
    const baseUrl = (process.env.CONTROL_PLANE_URL || "http://localhost:3000").replace(/\/+$/, "");
    const databaseId = process.env.CONTROL_PLANE_DATABASE_ID || "cookbook";
    const databaseUser = process.env.CONTROL_PLANE_DATABASE_USER || "cookbook";
    const databasePassword = process.env.CONTROL_PLANE_DATABASE_PASSWORD || undefined;
    
    const timeoutMs = 30_000;
    
    // Fetches a path from the server, and returns the decoded reply.
    async function get<T>(path: string): Promise<T> {
      const response = await fetch(`${baseUrl}${path}`, {
        signal: AbortSignal.timeout(timeoutMs),
      });
    
      // fetch only rejects when it cannot reach the server; an error status
      // is a normal response, so check it explicitly.
      if (!response.ok) {
        const text = await response.text();
        throw new Error(`HTTP ${response.status}, ${text.slice(0, 200) || response.statusText}`);
      }
      return (await response.json()) as T;
    }
    ```

=== "Java"

    ```java
    /** Returns the value of an environment variable, or a fallback. */
    static String envOr(String name, String fallback) {
        String value = System.getenv(name);
        return (value != null && !value.isEmpty()) ? value : fallback;
    }
    
    // The password has no default; the Control Plane never returns it, so
    // it comes from whoever created the database user.
    static final String BASE_URL =
            envOr("CONTROL_PLANE_URL", "http://localhost:3000")
                    .replaceAll("/+$", "");
    static final String DATABASE_ID = envOr("CONTROL_PLANE_DATABASE_ID", "cookbook");
    static final String DATABASE_USER = envOr("CONTROL_PLANE_DATABASE_USER", "cookbook");
    static final String DATABASE_PASSWORD = envOr("CONTROL_PLANE_DATABASE_PASSWORD", null);
    
    static final Duration TIMEOUT = Duration.ofSeconds(30);
    
    /** Thrown when the Control Plane rejects a request or replies oddly. */
    static class ControlPlaneException extends Exception {
        ControlPlaneException(String message) {
            super(message);
        }
    }
    
    // A mapper is safe to share, so the program creates only one.
    static final ObjectMapper MAPPER = JsonMapper.builder().build();
    
    /** Returns at most the first 200 characters of a reply. */
    static String shorten(String text) {
        return text.length() > 200 ? text.substring(0, 200) : text;
    }
    
    /**
     * Sends a request and returns the response with its whole body. The
     * request timeout stops applying once the headers arrive, so a server
     * that stalls part of the way through the body would hang send(); this
     * applies the same timeout to the whole exchange instead.
     */
    static HttpResponse<String> send(HttpClient client, HttpRequest request)
            throws IOException, InterruptedException {
        CompletableFuture<HttpResponse<String>> pending =
                client.sendAsync(request, HttpResponse.BodyHandlers.ofString());
        try {
            return pending.get(TIMEOUT.toMillis(), TimeUnit.MILLISECONDS);
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
    
    /** Fetches a path from the server, and returns the decoded reply. */
    static JsonNode get(HttpClient client, String path)
            throws IOException, InterruptedException, ControlPlaneException {
        HttpRequest request = HttpRequest.newBuilder(URI.create(BASE_URL + path))
                .timeout(TIMEOUT)
                .GET()
                .build();
        HttpResponse<String> response = send(client, request);
        if (response.statusCode() >= 400) {
            throw new ControlPlaneException("HTTP " + response.statusCode()
                    + ", " + shorten(response.body()));
        }
        try {
            JsonNode body = MAPPER.readTree(response.body());
            if (body.isObject()) {
                return body;
            }
        } catch (JacksonException e) {
            // The body is not JSON; report it below.
        }
        throw new ControlPlaneException(
                "Unexpected response: " + shorten(response.body()));
    }
    ```

=== "C#"

    ```csharp
    // Returns the value of an environment variable, or a fallback if the
    // variable is unset or empty.
    static string? EnvOr(string name, string? fallback) =>
        Environment.GetEnvironmentVariable(name) is { Length: > 0 } value
            ? value
            : fallback;
    
    static string BaseUrl() =>
        EnvOr("CONTROL_PLANE_URL", "http://localhost:3000")!.TrimEnd('/');
    
    // The password has no default; the Control Plane never returns it, so it
    // comes from whoever created the database user.
    static string DatabaseId() => EnvOr("CONTROL_PLANE_DATABASE_ID", "cookbook")!;
    static string DatabaseUser() => EnvOr("CONTROL_PLANE_DATABASE_USER", "cookbook")!;
    static string? DatabasePassword() => EnvOr("CONTROL_PLANE_DATABASE_PASSWORD", null);
    
    const int TimeoutSeconds = 30;
    
    // Returns at most the first 200 characters of a reply.
    static string Shorten(string text) =>
        text.Length > 200 ? text[..200] : text;
    
    // Fetches a path from the server, and returns the decoded reply.
    static async Task<JsonObject> GetAsync(HttpClient client, string path)
    {
        using var response = await client.GetAsync(BaseUrl() + path);
        var body = await response.Content.ReadAsStringAsync();
        if (!response.IsSuccessStatusCode)
        {
            throw new ControlPlaneException(
                $"HTTP {(int)response.StatusCode}, {Shorten(body)}");
        }
        try
        {
            if (JsonNode.Parse(body) is JsonObject reply)
            {
                return reply;
            }
        }
        catch (JsonException)
        {
            // The body is not JSON; report it below.
        }
        throw new ControlPlaneException($"Unexpected response: {Shorten(body)}");
    }
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
    
    // The password has no default; the Control Plane never returns it, so it
    // comes from whoever created the database user.
    var (
    	baseURL          = strings.TrimRight(envOr("CONTROL_PLANE_URL", "http://localhost:3000"), "/")
    	databaseID       = envOr("CONTROL_PLANE_DATABASE_ID", "cookbook")
    	databaseUser     = envOr("CONTROL_PLANE_DATABASE_USER", "cookbook")
    	databasePassword = os.Getenv("CONTROL_PLANE_DATABASE_PASSWORD")
    )
    
    const timeout = 30 * time.Second
    
    // get fetches a path from the server, and decodes the reply into out.
    func get(client *http.Client, path string, out any) error {
    	response, err := client.Get(baseURL + path)
    	if err != nil {
    		return err
    	}
    	defer response.Body.Close()
    
    	body, err := io.ReadAll(response.Body)
    	if err != nil {
    		return err
    	}
    
    	// Go treats an error status as a normal response, so check it here.
    	if response.StatusCode != http.StatusOK {
    		return fmt.Errorf("HTTP %d, %.200s", response.StatusCode, strings.TrimSpace(string(body)))
    	}
    	if err := json.Unmarshal(body, out); err != nil {
    		return fmt.Errorf("unexpected response: %.200s", body)
    	}
    	return nil
    }
    
    ```

=== "Rust"

    ```rust
    /// Returns the value of an environment variable, or None if the variable
    /// is unset or empty.
    fn env_value(name: &str) -> Option<String> {
        env::var(name).ok().filter(|value| !value.is_empty())
    }
    
    /// Returns the value of an environment variable, or a fallback.
    fn env_or(name: &str, fallback: &str) -> String {
        env_value(name).unwrap_or_else(|| fallback.to_string())
    }
    
    fn base_url() -> String {
        env_or("CONTROL_PLANE_URL", "http://localhost:3000")
            .trim_end_matches('/')
            .to_string()
    }
    
    // The password has no default; the Control Plane never returns it, so it
    // comes from whoever created the database user.
    fn database_id() -> String {
        env_or("CONTROL_PLANE_DATABASE_ID", "cookbook")
    }
    
    const TIMEOUT: Duration = Duration::from_secs(30);
    
    /// The errors that the functions below return; a string converts into one
    /// with the ? operator or into().
    type BoxError = Box<dyn Error>;
    
    /// Returns at most the first 200 characters of a reply.
    fn shorten(text: &str) -> String {
        text.chars().take(200).collect()
    }
    
    /// Fetches a path from the server, and returns the decoded reply.
    fn get(client: &Client, path: &str) -> Result<Value, BoxError> {
        let response = client.get(format!("{}{path}", base_url())).send()?;
        let status = response.status();
        let body = response.text()?;
        if !status.is_success() {
            return Err(format!("HTTP {}, {}", status.as_u16(), shorten(&body)).into());
        }
        match serde_json::from_str::<Value>(&body) {
            Ok(reply) if reply.is_object() => Ok(reply),
            _ => Err(format!("Unexpected response: {}", shorten(&body)).into()),
        }
    }
    ```

=== "Ruby"

    ```ruby
    # Returns the value of an environment variable, or a fallback if the
    # variable is unset or empty.
    def env_or(name, fallback)
      value = ENV[name]
      value.nil? || value.empty? ? fallback : value
    end
    
    # The password has no default; the Control Plane never returns it, so it
    # comes from whoever created the database user.
    BASE_URL = env_or("CONTROL_PLANE_URL", "http://localhost:3000").sub(%r{/+\z}, "")
    DATABASE_ID = env_or("CONTROL_PLANE_DATABASE_ID", "cookbook")
    DATABASE_USER = env_or("CONTROL_PLANE_DATABASE_USER", "cookbook")
    DATABASE_PASSWORD = env_or("CONTROL_PLANE_DATABASE_PASSWORD", nil)
    
    TIMEOUT_SECONDS = 30
    
    # Raised when the Control Plane rejects a request or replies oddly.
    class ControlPlaneError < StandardError; end
    
    # Fetches a path from the server, and returns the decoded reply.
    def get(http, path)
      response = http.request(Net::HTTP::Get.new(URI("#{BASE_URL}#{path}")))
      unless response.is_a?(Net::HTTPSuccess)
        raise ControlPlaneError, "HTTP #{response.code}, #{response.body.to_s[0, 200]}"
      end
    
      begin
        body = JSON.parse(response.body.to_s)
        return body if body.is_a?(Hash)
      rescue JSON::ParserError
        # The body is not JSON; report it below.
      end
      raise ControlPlaneError, "Unexpected response: #{response.body.to_s[0, 200]}"
    end
    ```

=== "curl"

    ```bash
    # The :- operator treats an empty variable as unset. The password has no
    # default; the Control Plane never returns it, so it comes from whoever
    # created the database user.
    CONTROL_PLANE_URL="${CONTROL_PLANE_URL:-http://localhost:3000}"
    CONTROL_PLANE_URL="${CONTROL_PLANE_URL%/}"
    DATABASE_ID="${CONTROL_PLANE_DATABASE_ID:-cookbook}"
    DATABASE_USER="${CONTROL_PLANE_DATABASE_USER:-cookbook}"
    DATABASE_PASSWORD="${CONTROL_PLANE_DATABASE_PASSWORD:-}"
    
    TIMEOUT_SECONDS=30
    
    # Fetches a path from the server and prints the JSON reply. With
    # --fail-with-body, curl exits non-zero on an HTTP error status but still
    # prints the body, which carries the server's explanation.
    get() {
        curl --silent --show-error --fail-with-body \
            --max-time "$TIMEOUT_SECONDS" "$CONTROL_PLANE_URL$1"
    }
    ```

## Finding an Instance

Each program reads the database and picks the first instance that is
`available` and has an address. The following tabs show how each program finds
the instance:

=== "Python"

    ```python
    def find_instance(client: httpx.Client) -> dict:
        """Returns the connection settings for the first instance of the
        database that is available. Each instance runs one node of the
        database, and its connection_info holds the addresses and port that
        clients use."""
        database = get(client, f"/v1/databases/{DATABASE_ID}")
        for instance in database.get("instances") or []:
            info = instance.get("connection_info") or {}
            if instance.get("state") == "available" and info.get("addresses"):
                return {
                    "node": instance.get("node_name"),
                    "host": info["addresses"][0],
                    "port": info.get("port"),
                    "dbname": (database.get("spec") or {}).get("database_name"),
                }
        raise ControlPlaneError(f"no available instance of {DATABASE_ID}")
    ```

=== "TypeScript"

    ```typescript
    interface Database {
      spec?: { database_name?: string };
      instances?: {
        node_name?: string;
        state?: string;
        connection_info?: { addresses?: string[]; port?: number };
      }[];
    }
    
    interface Instance {
      node?: string;
      host: string;
      port?: number;
      database?: string;
    }
    
    // Returns the connection settings for the first instance of the database
    // that is available. Each instance runs one node of the database, and its
    // connection_info holds the addresses and port that clients use.
    async function findInstance(): Promise<Instance> {
      const database = await get<Database>(`/v1/databases/${databaseId}`);
      for (const instance of database.instances ?? []) {
        const info = instance.connection_info;
        if (instance.state === "available" && info?.addresses?.length) {
          return {
            node: instance.node_name,
            host: info.addresses[0],
            port: info.port,
            database: database.spec?.database_name,
          };
        }
      }
      throw new Error(`no available instance of ${databaseId}`);
    }
    ```

=== "Java"

    ```java
    /** The settings for connecting to one instance. */
    record Instance(String node, String host, int port, String database) {
    }
    
    /**
     * Returns the connection settings for the first instance of the
     * database that is available. Each instance runs one node of the
     * database, and its connection_info holds the addresses and port that
     * clients use.
     */
    static Instance findInstance(HttpClient client)
            throws IOException, InterruptedException, ControlPlaneException {
        JsonNode database = get(client, "/v1/databases/" + DATABASE_ID);
        for (JsonNode instance : database.path("instances")) {
            JsonNode info = instance.path("connection_info");
            if (instance.path("state").asString("").equals("available")
                    && info.path("addresses").size() > 0) {
                return new Instance(
                        instance.path("node_name").asString(),
                        info.path("addresses").get(0).asString(),
                        info.path("port").asInt(),
                        database.path("spec").path("database_name").asString());
            }
        }
        throw new ControlPlaneException("no available instance of " + DATABASE_ID);
    }
    ```

=== "C#"

    ```csharp
    // Returns the connection settings for the first instance of the database
    // that is available. Each instance runs one node of the database, and its
    // connection_info holds the addresses and port that clients use.
    static async Task<Instance> FindInstanceAsync(HttpClient client)
    {
        var database = await GetAsync(client, $"/v1/databases/{DatabaseId()}");
        if (database["instances"] is JsonArray instances)
        {
            foreach (var instance in instances)
            {
                var info = instance?["connection_info"];
                if (instance?["state"]?.ToString() == "available" &&
                    info?["addresses"] is JsonArray { Count: > 0 } addresses)
                {
                    return new Instance(
                        instance["node_name"]?.ToString() ?? "",
                        addresses[0]!.ToString(),
                        info["port"]?.GetValue<int>() ?? 0,
                        database["spec"]?["database_name"]?.ToString() ?? "");
                }
            }
        }
        throw new ControlPlaneException($"no available instance of {DatabaseId()}");
    }
    ```

=== "Go"

    ```go
    // instance holds the settings for connecting to one instance.
    type instance struct {
    	Node     string
    	Host     string
    	Port     int
    	Database string
    }
    
    // findInstance returns the connection settings for the first instance of
    // the database that is available. Each instance runs one node of the
    // database, and its connection_info holds the addresses and port that
    // clients use.
    func findInstance(client *http.Client) (*instance, error) {
    	var database struct {
    		Spec struct {
    			DatabaseName string `json:"database_name"`
    		} `json:"spec"`
    		Instances []struct {
    			NodeName       string `json:"node_name"`
    			State          string `json:"state"`
    			ConnectionInfo struct {
    				Addresses []string `json:"addresses"`
    				Port      int      `json:"port"`
    			} `json:"connection_info"`
    		} `json:"instances"`
    	}
    	if err := get(client, "/v1/databases/"+databaseID, &database); err != nil {
    		return nil, err
    	}
    	for _, i := range database.Instances {
    		if i.State == "available" && len(i.ConnectionInfo.Addresses) > 0 {
    			return &instance{
    				Node:     i.NodeName,
    				Host:     i.ConnectionInfo.Addresses[0],
    				Port:     i.ConnectionInfo.Port,
    				Database: database.Spec.DatabaseName,
    			}, nil
    		}
    	}
    	return nil, fmt.Errorf("no available instance of %s", databaseID)
    }
    
    ```

=== "Rust"

    ```rust
    /// The settings for connecting to one instance.
    struct Instance {
        node: String,
        host: String,
        port: u16,
        database: String,
    }
    
    /// Returns the connection settings for the first instance of the database
    /// that is available. Each instance runs one node of the database, and
    /// its connection_info holds the addresses and port that clients use.
    fn find_instance(client: &Client) -> Result<Instance, BoxError> {
        let database = get(client, &format!("/v1/databases/{}", database_id()))?;
        // as_array() gives None when the reply lists no instances.
        for instance in database["instances"].as_array().into_iter().flatten() {
            let info = &instance["connection_info"];
            if let (Some("available"), Some(address)) =
                (instance["state"].as_str(), info["addresses"][0].as_str())
            {
                return Ok(Instance {
                    node: instance["node_name"].as_str().unwrap_or("").to_string(),
                    host: address.to_string(),
                    port: info["port"].as_u64().unwrap_or(0).try_into()?,
                    database: database["spec"]["database_name"]
                        .as_str()
                        .unwrap_or("")
                        .to_string(),
                });
            }
        }
        Err(format!("no available instance of {}", database_id()).into())
    }
    ```

=== "Ruby"

    ```ruby
    # Returns the connection settings for the first instance of the database
    # that is available. Each instance runs one node of the database, and its
    # connection_info holds the addresses and port that clients use.
    def find_instance(http)
      database = get(http, "/v1/databases/#{DATABASE_ID}")
      (database["instances"] || []).each do |instance|
        info = instance["connection_info"] || {}
        next unless instance["state"] == "available" && !(info["addresses"] || []).empty?
    
        return {
          node: instance["node_name"],
          host: info["addresses"].first,
          port: info["port"],
          dbname: (database["spec"] || {})["database_name"]
        }
      end
      raise ControlPlaneError, "no available instance of #{DATABASE_ID}"
    end
    ```

=== "curl"

    ```bash
    # Prints the database name, node name, address and port of the first
    # instance of the database that is available, separated by spaces. Each
    # instance runs one node of the database, and its connection_info holds
    # the addresses and port that clients use.
    find_instance() {
        local response
        response="$(get "/v1/databases/$DATABASE_ID")" || {
            echo "Control Plane error: $response" >&2
            return 1
        }
        jq -er '
            .spec.database_name as $name
            | first(.instances[]?
                    | select(.state == "available"
                             and (.connection_info.addresses | length) > 0))
            | "\($name) \(.node_name) \(.connection_info.addresses[0]) \(.connection_info.port)"
            ' <<<"$response" || {
            echo "Control Plane error: no available instance of $DATABASE_ID" >&2
            return 1
        }
    }
    ```

## Connecting to the Instance

Each program connects to the instance with its PostgreSQL driver, then asks for
the name of the database and the version of the Spock extension, if it is
installed. The following tabs show the connection and the queries:

=== "Python"

    ```python
    def query(instance: dict) -> tuple[str, str]:
        """Connects to the instance, and returns the name of the database and
        the version of the Spock extension."""
        # The with block closes the connection when it exits, whether or not
        # an error occurred.
        with psycopg.connect(
            host=instance["host"],
            port=instance["port"],
            dbname=instance["dbname"],
            user=DATABASE_USER,
            password=DATABASE_PASSWORD,
            connect_timeout=TIMEOUT_SECONDS,
        ) as conn:
            database = conn.execute("SELECT current_database()").fetchone()[0]
            row = conn.execute(
                "SELECT extversion FROM pg_extension WHERE extname = 'spock'"
            ).fetchone()
        return database, row[0] if row else "not installed"
    ```

=== "TypeScript"

    ```typescript
    // Connects to the instance, and returns the name of the database and the
    // version of the Spock extension.
    async function query(instance: Instance): Promise<[string, string]> {
      const client = new pg.Client({
        host: instance.host,
        port: instance.port,
        database: instance.database,
        user: databaseUser,
        password: databasePassword,
        connectionTimeoutMillis: timeoutMs,
      });
      await client.connect();
      try {
        const database = await client.query<{ current_database: string }>(
          "SELECT current_database()",
        );
        const spock = await client.query<{ extversion: string }>(
          "SELECT extversion FROM pg_extension WHERE extname = 'spock'",
        );
        return [database.rows[0].current_database, spock.rows[0]?.extversion ?? "not installed"];
      } finally {
        // Close the connection whether or not a query failed.
        await client.end();
      }
    }
    ```

=== "Java"

    ```java
    /**
     * Connects to the instance, and returns the name of the database and
     * the version of the Spock extension.
     */
    static String[] query(Instance instance) throws SQLException {
        Properties props = new Properties();
        props.setProperty("user", DATABASE_USER);
        props.setProperty("password", DATABASE_PASSWORD);
        props.setProperty("connectTimeout", String.valueOf(TIMEOUT.toSeconds()));
        props.setProperty("loginTimeout", String.valueOf(TIMEOUT.toSeconds()));
        String url = "jdbc:postgresql://" + instance.host() + ":"
                + instance.port() + "/" + instance.database();
    
        // try-with-resources closes the connection and statement when the
        // block exits, whether or not a query failed.
        try (Connection conn = DriverManager.getConnection(url, props);
             Statement stmt = conn.createStatement()) {
            String database;
            try (ResultSet rs = stmt.executeQuery("SELECT current_database()")) {
                rs.next();
                database = rs.getString(1);
            }
            try (ResultSet rs = stmt.executeQuery(
                    "SELECT extversion FROM pg_extension WHERE extname = 'spock'")) {
                return new String[] {
                    database, rs.next() ? rs.getString(1) : "not installed"
                };
            }
        }
    }
    ```

=== "C#"

    ```csharp
    // Connects to the instance, and returns the name of the database and the
    // version of the Spock extension. The builder takes care of quoting any
    // special characters.
    static async Task<(string Database, string Spock)> QueryAsync(Instance instance)
    {
        var connectionString = new NpgsqlConnectionStringBuilder
        {
            Host = instance.Host,
            Port = instance.Port,
            Database = instance.Database,
            Username = DatabaseUser(),
            Password = DatabasePassword(),
            Timeout = TimeoutSeconds,
        }.ConnectionString;
    
        // await using closes the connection and commands when the block
        // exits, whether or not a query failed.
        await using var conn = new NpgsqlConnection(connectionString);
        await conn.OpenAsync();
    
        await using var databaseCmd = new NpgsqlCommand("SELECT current_database()", conn);
        var database = (string)(await databaseCmd.ExecuteScalarAsync())!;
    
        await using var spockCmd = new NpgsqlCommand(
            "SELECT extversion FROM pg_extension WHERE extname = 'spock'", conn);
        var spock = await spockCmd.ExecuteScalarAsync() as string ?? "not installed";
        return (database, spock);
    }
    ```

=== "Go"

    ```go
    // query connects to the instance, and returns the name of the database
    // and the version of the Spock extension.
    func query(ctx context.Context, i *instance) (database, spock string, err error) {
    	// net/url takes care of escaping any special characters in the user
    	// name, password, or database name.
    	u := url.URL{
    		Scheme:   "postgres",
    		User:     url.UserPassword(databaseUser, databasePassword),
    		Host:     net.JoinHostPort(i.Host, strconv.Itoa(i.Port)),
    		Path:     "/" + i.Database,
    		RawQuery: "connect_timeout=30",
    	}
    
    	conn, err := pgx.Connect(ctx, u.String())
    	if err != nil {
    		return "", "", err
    	}
    	// Close the connection when the function returns, whether or not a
    	// query failed.
    	defer conn.Close(ctx)
    
    	if err := conn.QueryRow(ctx, "SELECT current_database()").Scan(&database); err != nil {
    		return "", "", err
    	}
    	err = conn.QueryRow(ctx,
    		"SELECT extversion FROM pg_extension WHERE extname = 'spock'").Scan(&spock)
    	if errors.Is(err, pgx.ErrNoRows) {
    		return database, "not installed", nil
    	}
    	return database, spock, err
    }
    
    ```

=== "Rust"

    ```rust
    /// Connects to the instance, and returns the name of the database and the
    /// version of the Spock extension. NoTls disables TLS, which keeps this
    /// example free of certificate set-up; connections over an untrusted
    /// network should use TLS.
    fn query(instance: &Instance, password: &str) -> Result<(String, String), postgres::Error> {
        let mut client = Config::new()
            .host(&instance.host)
            .port(instance.port)
            .dbname(&instance.database)
            .user(&env_or("CONTROL_PLANE_DATABASE_USER", "cookbook"))
            .password(password)
            .connect_timeout(TIMEOUT)
            .connect(NoTls)?;
    
        let database: String = client.query_one("SELECT current_database()", &[])?.get(0);
        // query_opt returns None when no row matches.
        let spock = client
            .query_opt("SELECT extversion FROM pg_extension WHERE extname = 'spock'", &[])?
            .map(|row| row.get(0))
            .unwrap_or_else(|| "not installed".to_string());
        // The client closes its connection when it goes out of scope.
        Ok((database, spock))
    }
    ```

=== "Ruby"

    ```ruby
    # Connects to the instance, and returns the name of the database and the
    # version of the Spock extension.
    def query(instance)
      conn = PG.connect(
        host: instance[:host], port: instance[:port], dbname: instance[:dbname],
        user: DATABASE_USER, password: DATABASE_PASSWORD,
        connect_timeout: TIMEOUT_SECONDS
      )
      begin
        database = conn.exec("SELECT current_database()").getvalue(0, 0)
        spock = conn.exec("SELECT extversion FROM pg_extension WHERE extname = 'spock'")
        [database, spock.ntuples.zero? ? "not installed" : spock.getvalue(0, 0)]
      ensure
        # Close the connection whether or not a query failed.
        conn.close
      end
    end
    ```

=== "curl"

    ```bash
    # Connects with psql and runs the two queries. PGPASSWORD passes the
    # password through the environment, so it never appears in the process
    # list. The -X option skips any .psqlrc, -A and -t print bare values, and
    # ON_ERROR_STOP makes psql exit non-zero if a query fails.
    query() {
        local name="$1" address="$2" port="$3"
        PGPASSWORD="$DATABASE_PASSWORD" PGCONNECT_TIMEOUT="$TIMEOUT_SECONDS" \
            psql -X -A -t -v ON_ERROR_STOP=1 \
            --host "$address" --port "$port" \
            --username "$DATABASE_USER" --dbname "$name" \
            -c "SELECT current_database()" \
            -c "SELECT coalesce((SELECT extversion FROM pg_extension
                                 WHERE extname = 'spock'), 'not installed')"
    }
    ```

## Handling Errors

The main part of each program finds the instance and then connects to it. It
reports a failure to reach the Control Plane with the prefix `Control Plane
error:` and a failure to connect or query with the prefix `Database error:`,
so that the message shows which side failed. The following tabs show the main
part of each program:

=== "Python"

    ```python
    def main() -> int:
        if DATABASE_PASSWORD is None:
            print("CONTROL_PLANE_DATABASE_PASSWORD must be set", file=sys.stderr)
            return 1
    
        try:
            with httpx.Client(base_url=BASE_URL, timeout=TIMEOUT_SECONDS) as client:
                instance = find_instance(client)
        # httpx.HTTPError is the base class for failures to reach the server,
        # such as a refused connection or a timeout.
        except (httpx.HTTPError, ControlPlaneError) as e:
            print(f"Control Plane error: {e}", file=sys.stderr)
            return 1
        print(f"Connecting to node {instance['node']}")
    
        try:
            database, spock = query(instance)
        # psycopg.Error is the base class for the driver's errors, including
        # connection failures and errors reported by the server.
        except psycopg.Error as e:
            print(f"Database error: {e}", file=sys.stderr)
            return 1
        print(f"Connected to database {database}")
        print(f"Spock: {spock}")
        return 0
    
    
    if __name__ == "__main__":
        sys.exit(main())
    ```

=== "TypeScript"

    ```typescript
    // Returns a readable description of an error. fetch reports a connection
    // failure as a TypeError with the cause (often an AggregateError, whose
    // own message is empty) attached.
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
      if (databasePassword === undefined) {
        console.error("CONTROL_PLANE_DATABASE_PASSWORD must be set");
        return 1;
      }
    
      let instance: Instance;
      try {
        instance = await findInstance();
      } catch (err) {
        console.error(`Control Plane error: ${describe(err)}`);
        return 1;
      }
      console.log(`Connecting to node ${instance.node}`);
    
      try {
        const [database, spock] = await query(instance);
        console.log(`Connected to database ${database}`);
        console.log(`Spock: ${spock}`);
        return 0;
      } catch (err) {
        console.error(`Database error: ${describe(err)}`);
        return 1;
      }
    }
    
    process.exitCode = await main();
    ```

=== "Java"

    ```java
    public static void main(String[] args) {
        if (DATABASE_PASSWORD == null) {
            System.err.println("CONTROL_PLANE_DATABASE_PASSWORD must be set");
            System.exit(1);
        }
    
        Instance instance;
        try {
            instance = findInstance(HttpClient.newHttpClient());
        // IOException covers failures to reach the server, such as a
        // refused connection or a timeout. The message of a refused
        // connection can be empty, so print the exception itself, which
        // includes its type.
        } catch (IOException | InterruptedException e) {
            System.err.println("Control Plane error: " + e);
            System.exit(1);
            return;
        } catch (ControlPlaneException e) {
            System.err.println("Control Plane error: " + e.getMessage());
            System.exit(1);
            return;
        }
        System.out.println("Connecting to node " + instance.node());
    
        try {
            String[] result = query(instance);
            System.out.println("Connected to database " + result[0]);
            System.out.println("Spock: " + result[1]);
        } catch (SQLException e) {
            System.err.println("Database error: " + e.getMessage());
            System.exit(1);
        }
    }
    ```

=== "C#"

    ```csharp
    if (DatabasePassword() is null)
    {
        Console.Error.WriteLine("CONTROL_PLANE_DATABASE_PASSWORD must be set");
        return 1;
    }
    
    Instance found;
    try
    {
        // using disposes of the client, and closes its connections, when the
        // block exits, whether or not an error occurred.
        using var client = new HttpClient
        {
            Timeout = TimeSpan.FromSeconds(TimeoutSeconds),
        };
        found = await FindInstanceAsync(client);
    }
    // HttpRequestException covers failures to reach the server, such as a
    // refused connection, and TaskCanceledException covers a timeout.
    catch (Exception e) when (
        e is HttpRequestException or TaskCanceledException or ControlPlaneException)
    {
        Console.Error.WriteLine($"Control Plane error: {e.Message}");
        return 1;
    }
    Console.WriteLine($"Connecting to node {found.Node}");
    
    try
    {
        var (database, spock) = await QueryAsync(found);
        Console.WriteLine($"Connected to database {database}");
        Console.WriteLine($"Spock: {spock}");
    }
    // NpgsqlException is the base class for the driver's errors, including
    // connection failures and errors reported by the server.
    catch (NpgsqlException e)
    {
        Console.Error.WriteLine($"Database error: {e.Message}");
        return 1;
    }
    return 0;
    
    // C# requires type declarations to follow the top-level statements, so
    // the settings for one instance, and the exception that the program
    // throws for an error reply, are declared here, at the end.
    record Instance(string Node, string Host, int Port, string Database);
    
    class ControlPlaneException(string message) : Exception(message);
    ```

=== "Go"

    ```go
    func main() {
    	if databasePassword == "" {
    		fmt.Fprintln(os.Stderr, "CONTROL_PLANE_DATABASE_PASSWORD must be set")
    		os.Exit(1)
    	}
    
    	i, err := findInstance(&http.Client{Timeout: timeout})
    	if err != nil {
    		fmt.Fprintf(os.Stderr, "Control Plane error: %v\n", err)
    		os.Exit(1)
    	}
    	fmt.Printf("Connecting to node %s\n", i.Node)
    
    	database, spock, err := query(context.Background(), i)
    	if err != nil {
    		fmt.Fprintf(os.Stderr, "Database error: %v\n", err)
    		os.Exit(1)
    	}
    	fmt.Printf("Connected to database %s\n", database)
    	fmt.Printf("Spock: %s\n", spock)
    }
    
    ```

=== "Rust"

    ```rust
    /// Prints an error with the chain of underlying causes, since the
    /// top-level error is often generic ("error sending request").
    fn report(prefix: &str, e: &dyn Error) {
        eprintln!("{prefix}: {e}");
        let mut cause = e.source();
        while let Some(c) = cause {
            eprintln!("  caused by: {c}");
            cause = c.source();
        }
    }
    
    fn main() -> ExitCode {
        let Some(password) = env_value("CONTROL_PLANE_DATABASE_PASSWORD") else {
            eprintln!("CONTROL_PLANE_DATABASE_PASSWORD must be set");
            return ExitCode::FAILURE;
        };
    
        let instance = match Client::builder()
            .timeout(TIMEOUT)
            .build()
            .map_err(BoxError::from)
            .and_then(|client| find_instance(&client))
        {
            Ok(instance) => instance,
            Err(e) => {
                report("Control Plane error", e.as_ref());
                return ExitCode::FAILURE;
            }
        };
        println!("Connecting to node {}", instance.node);
    
        match query(&instance, &password) {
            Ok((database, spock)) => {
                println!("Connected to database {database}");
                println!("Spock: {spock}");
                ExitCode::SUCCESS
            }
            Err(e) => {
                report("Database error", &e);
                ExitCode::FAILURE
            }
        }
    }
    ```

=== "Ruby"

    ```ruby
    if DATABASE_PASSWORD.nil?
      warn "CONTROL_PLANE_DATABASE_PASSWORD must be set"
      exit 1
    end
    
    begin
      uri = URI(BASE_URL)
      # start opens a connection, and closes it when the block exits, whether
      # or not an error occurred.
      instance = Net::HTTP.start(
        uri.host, uri.port,
        use_ssl: uri.scheme == "https",
        open_timeout: TIMEOUT_SECONDS, read_timeout: TIMEOUT_SECONDS
      ) { |http| find_instance(http) }
    # SystemCallError covers a refused connection, Timeout::Error covers the
    # connection and read timeouts, and SocketError covers an unknown host.
    rescue ControlPlaneError, SystemCallError, Timeout::Error, SocketError, IOError => e
      warn "Control Plane error: #{e.message}"
      exit 1
    end
    puts "Connecting to node #{instance[:node]}"
    
    begin
      database, spock = query(instance)
    # PG::Error is the base class for every error the gem raises, including
    # connection failures and errors reported by the server.
    rescue PG::Error => e
      warn "Database error: #{e.message}"
      exit 1
    end
    puts "Connected to database #{database}"
    puts "Spock: #{spock}"
    ```

=== "curl"

    ```bash
    main() {
        local instance name node address port result database spock
    
        if [[ -z "$DATABASE_PASSWORD" ]]; then
            echo "CONTROL_PLANE_DATABASE_PASSWORD must be set" >&2
            exit 1
        fi
    
        instance="$(find_instance)" || exit 1
        read -r name node address port <<<"$instance"
        echo "Connecting to node $node"
    
        result="$(query "$name" "$address" "$port")" || {
            echo "Database error: could not query $name" >&2
            exit 1
        }
        # psql prints the result of each query on a line of its own.
        { read -r database; read -r spock; } <<<"$result"
        echo "Connected to database $database"
        echo "Spock: $spock"
    }
    
    main
    ```

## Running the Example

The complete project for each language is available in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/control_plane/connect_database).
Set the environment variables for your Control Plane and database user, and
then run the command for your language from the corresponding project
directory. The following tabs show the commands that build and run each
example:

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

=== "curl"

    ```bash
    bash main.sh
    ```

## Viewing the Complete Program

The following tabs show the complete program for each language:

=== "Python"

    ```python
    """
    Ellie's Postgres Cookbook
    Finding the address of a pgEdge Control Plane database and connecting to
    it, using httpx and psycopg.
    
    These examples are for the Control Plane v0.11.0.
    
    Copyright (c) 2026, pgEdge, Inc.
    This code is released under the PostgreSQL License.
    """
    
    import os
    import sys
    
    import httpx
    import psycopg
    
    
    # The or operator treats an empty variable as unset. The password has no
    # default; the Control Plane never returns it, so it comes from whoever
    # created the database user.
    BASE_URL = (os.environ.get("CONTROL_PLANE_URL") or "http://localhost:3000").rstrip("/")
    DATABASE_ID = os.environ.get("CONTROL_PLANE_DATABASE_ID") or "cookbook"
    DATABASE_USER = os.environ.get("CONTROL_PLANE_DATABASE_USER") or "cookbook"
    DATABASE_PASSWORD = os.environ.get("CONTROL_PLANE_DATABASE_PASSWORD") or None
    
    TIMEOUT_SECONDS = 30
    
    
    class ControlPlaneError(Exception):
        """Raised when the Control Plane rejects a request or replies oddly."""
    
    
    def get(client: httpx.Client, path: str) -> dict:
        """Fetches a path from the server, and returns the decoded reply."""
        response = client.get(path)
        if response.is_error:
            raise ControlPlaneError(f"HTTP {response.status_code}, {response.text[:200]}")
        try:
            body = response.json()
            if isinstance(body, dict):
                return body
        except ValueError:
            pass
        raise ControlPlaneError(f"Unexpected response: {response.text[:200]}")
    
    
    def find_instance(client: httpx.Client) -> dict:
        """Returns the connection settings for the first instance of the
        database that is available. Each instance runs one node of the
        database, and its connection_info holds the addresses and port that
        clients use."""
        database = get(client, f"/v1/databases/{DATABASE_ID}")
        for instance in database.get("instances") or []:
            info = instance.get("connection_info") or {}
            if instance.get("state") == "available" and info.get("addresses"):
                return {
                    "node": instance.get("node_name"),
                    "host": info["addresses"][0],
                    "port": info.get("port"),
                    "dbname": (database.get("spec") or {}).get("database_name"),
                }
        raise ControlPlaneError(f"no available instance of {DATABASE_ID}")
    
    
    def query(instance: dict) -> tuple[str, str]:
        """Connects to the instance, and returns the name of the database and
        the version of the Spock extension."""
        # The with block closes the connection when it exits, whether or not
        # an error occurred.
        with psycopg.connect(
            host=instance["host"],
            port=instance["port"],
            dbname=instance["dbname"],
            user=DATABASE_USER,
            password=DATABASE_PASSWORD,
            connect_timeout=TIMEOUT_SECONDS,
        ) as conn:
            database = conn.execute("SELECT current_database()").fetchone()[0]
            row = conn.execute(
                "SELECT extversion FROM pg_extension WHERE extname = 'spock'"
            ).fetchone()
        return database, row[0] if row else "not installed"
    
    
    def main() -> int:
        if DATABASE_PASSWORD is None:
            print("CONTROL_PLANE_DATABASE_PASSWORD must be set", file=sys.stderr)
            return 1
    
        try:
            with httpx.Client(base_url=BASE_URL, timeout=TIMEOUT_SECONDS) as client:
                instance = find_instance(client)
        # httpx.HTTPError is the base class for failures to reach the server,
        # such as a refused connection or a timeout.
        except (httpx.HTTPError, ControlPlaneError) as e:
            print(f"Control Plane error: {e}", file=sys.stderr)
            return 1
        print(f"Connecting to node {instance['node']}")
    
        try:
            database, spock = query(instance)
        # psycopg.Error is the base class for the driver's errors, including
        # connection failures and errors reported by the server.
        except psycopg.Error as e:
            print(f"Database error: {e}", file=sys.stderr)
            return 1
        print(f"Connected to database {database}")
        print(f"Spock: {spock}")
        return 0
    
    
    if __name__ == "__main__":
        sys.exit(main())
    
    ```

=== "TypeScript"

    ```typescript
    /*
     * Ellie's Postgres Cookbook
     * Finding the address of a pgEdge Control Plane database and connecting
     * to it, using the built-in fetch and node-postgres.
     *
     * These examples are for the Control Plane v0.11.0.
     *
     * Copyright (c) 2026, pgEdge, Inc.
     * This code is released under the PostgreSQL License.
     */
    
    // Node.js provides fetch and AbortSignal as globals; pg is node-postgres.
    import pg from "pg";
    
    // The || operator, unlike ??, also treats an empty variable as unset. The
    // password has no default; the Control Plane never returns it, so it
    // comes from whoever created the database user.
    const baseUrl = (process.env.CONTROL_PLANE_URL || "http://localhost:3000").replace(/\/+$/, "");
    const databaseId = process.env.CONTROL_PLANE_DATABASE_ID || "cookbook";
    const databaseUser = process.env.CONTROL_PLANE_DATABASE_USER || "cookbook";
    const databasePassword = process.env.CONTROL_PLANE_DATABASE_PASSWORD || undefined;
    
    const timeoutMs = 30_000;
    
    // Fetches a path from the server, and returns the decoded reply.
    async function get<T>(path: string): Promise<T> {
      const response = await fetch(`${baseUrl}${path}`, {
        signal: AbortSignal.timeout(timeoutMs),
      });
    
      // fetch only rejects when it cannot reach the server; an error status
      // is a normal response, so check it explicitly.
      if (!response.ok) {
        const text = await response.text();
        throw new Error(`HTTP ${response.status}, ${text.slice(0, 200) || response.statusText}`);
      }
      return (await response.json()) as T;
    }
    
    interface Database {
      spec?: { database_name?: string };
      instances?: {
        node_name?: string;
        state?: string;
        connection_info?: { addresses?: string[]; port?: number };
      }[];
    }
    
    interface Instance {
      node?: string;
      host: string;
      port?: number;
      database?: string;
    }
    
    // Returns the connection settings for the first instance of the database
    // that is available. Each instance runs one node of the database, and its
    // connection_info holds the addresses and port that clients use.
    async function findInstance(): Promise<Instance> {
      const database = await get<Database>(`/v1/databases/${databaseId}`);
      for (const instance of database.instances ?? []) {
        const info = instance.connection_info;
        if (instance.state === "available" && info?.addresses?.length) {
          return {
            node: instance.node_name,
            host: info.addresses[0],
            port: info.port,
            database: database.spec?.database_name,
          };
        }
      }
      throw new Error(`no available instance of ${databaseId}`);
    }
    
    // Connects to the instance, and returns the name of the database and the
    // version of the Spock extension.
    async function query(instance: Instance): Promise<[string, string]> {
      const client = new pg.Client({
        host: instance.host,
        port: instance.port,
        database: instance.database,
        user: databaseUser,
        password: databasePassword,
        connectionTimeoutMillis: timeoutMs,
      });
      await client.connect();
      try {
        const database = await client.query<{ current_database: string }>(
          "SELECT current_database()",
        );
        const spock = await client.query<{ extversion: string }>(
          "SELECT extversion FROM pg_extension WHERE extname = 'spock'",
        );
        return [database.rows[0].current_database, spock.rows[0]?.extversion ?? "not installed"];
      } finally {
        // Close the connection whether or not a query failed.
        await client.end();
      }
    }
    
    // Returns a readable description of an error. fetch reports a connection
    // failure as a TypeError with the cause (often an AggregateError, whose
    // own message is empty) attached.
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
      if (databasePassword === undefined) {
        console.error("CONTROL_PLANE_DATABASE_PASSWORD must be set");
        return 1;
      }
    
      let instance: Instance;
      try {
        instance = await findInstance();
      } catch (err) {
        console.error(`Control Plane error: ${describe(err)}`);
        return 1;
      }
      console.log(`Connecting to node ${instance.node}`);
    
      try {
        const [database, spock] = await query(instance);
        console.log(`Connected to database ${database}`);
        console.log(`Spock: ${spock}`);
        return 0;
      } catch (err) {
        console.error(`Database error: ${describe(err)}`);
        return 1;
      }
    }
    
    process.exitCode = await main();
    
    ```

=== "Java"

    ```java
    /*
     * Ellie's Postgres Cookbook
     * Finding the address of a pgEdge Control Plane database and connecting
     * to it, using java.net.http, Jackson and pgJDBC.
     *
     * These examples are for the Control Plane v0.11.0.
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
    import java.sql.ResultSet;
    import java.sql.SQLException;
    import java.sql.Statement;
    import java.time.Duration;
    import java.util.Properties;
    import java.util.concurrent.CompletableFuture;
    import java.util.concurrent.ExecutionException;
    import java.util.concurrent.TimeUnit;
    import java.util.concurrent.TimeoutException;
    
    import tools.jackson.core.JacksonException;
    import tools.jackson.databind.JsonNode;
    import tools.jackson.databind.ObjectMapper;
    import tools.jackson.databind.json.JsonMapper;
    
    public class Main {
    
        /** Returns the value of an environment variable, or a fallback. */
        static String envOr(String name, String fallback) {
            String value = System.getenv(name);
            return (value != null && !value.isEmpty()) ? value : fallback;
        }
    
        // The password has no default; the Control Plane never returns it, so
        // it comes from whoever created the database user.
        static final String BASE_URL =
                envOr("CONTROL_PLANE_URL", "http://localhost:3000")
                        .replaceAll("/+$", "");
        static final String DATABASE_ID = envOr("CONTROL_PLANE_DATABASE_ID", "cookbook");
        static final String DATABASE_USER = envOr("CONTROL_PLANE_DATABASE_USER", "cookbook");
        static final String DATABASE_PASSWORD = envOr("CONTROL_PLANE_DATABASE_PASSWORD", null);
    
        static final Duration TIMEOUT = Duration.ofSeconds(30);
    
        /** Thrown when the Control Plane rejects a request or replies oddly. */
        static class ControlPlaneException extends Exception {
            ControlPlaneException(String message) {
                super(message);
            }
        }
    
        // A mapper is safe to share, so the program creates only one.
        static final ObjectMapper MAPPER = JsonMapper.builder().build();
    
        /** Returns at most the first 200 characters of a reply. */
        static String shorten(String text) {
            return text.length() > 200 ? text.substring(0, 200) : text;
        }
    
        /**
         * Sends a request and returns the response with its whole body. The
         * request timeout stops applying once the headers arrive, so a server
         * that stalls part of the way through the body would hang send(); this
         * applies the same timeout to the whole exchange instead.
         */
        static HttpResponse<String> send(HttpClient client, HttpRequest request)
                throws IOException, InterruptedException {
            CompletableFuture<HttpResponse<String>> pending =
                    client.sendAsync(request, HttpResponse.BodyHandlers.ofString());
            try {
                return pending.get(TIMEOUT.toMillis(), TimeUnit.MILLISECONDS);
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
    
        /** Fetches a path from the server, and returns the decoded reply. */
        static JsonNode get(HttpClient client, String path)
                throws IOException, InterruptedException, ControlPlaneException {
            HttpRequest request = HttpRequest.newBuilder(URI.create(BASE_URL + path))
                    .timeout(TIMEOUT)
                    .GET()
                    .build();
            HttpResponse<String> response = send(client, request);
            if (response.statusCode() >= 400) {
                throw new ControlPlaneException("HTTP " + response.statusCode()
                        + ", " + shorten(response.body()));
            }
            try {
                JsonNode body = MAPPER.readTree(response.body());
                if (body.isObject()) {
                    return body;
                }
            } catch (JacksonException e) {
                // The body is not JSON; report it below.
            }
            throw new ControlPlaneException(
                    "Unexpected response: " + shorten(response.body()));
        }
    
        /** The settings for connecting to one instance. */
        record Instance(String node, String host, int port, String database) {
        }
    
        /**
         * Returns the connection settings for the first instance of the
         * database that is available. Each instance runs one node of the
         * database, and its connection_info holds the addresses and port that
         * clients use.
         */
        static Instance findInstance(HttpClient client)
                throws IOException, InterruptedException, ControlPlaneException {
            JsonNode database = get(client, "/v1/databases/" + DATABASE_ID);
            for (JsonNode instance : database.path("instances")) {
                JsonNode info = instance.path("connection_info");
                if (instance.path("state").asString("").equals("available")
                        && info.path("addresses").size() > 0) {
                    return new Instance(
                            instance.path("node_name").asString(),
                            info.path("addresses").get(0).asString(),
                            info.path("port").asInt(),
                            database.path("spec").path("database_name").asString());
                }
            }
            throw new ControlPlaneException("no available instance of " + DATABASE_ID);
        }
    
        /**
         * Connects to the instance, and returns the name of the database and
         * the version of the Spock extension.
         */
        static String[] query(Instance instance) throws SQLException {
            Properties props = new Properties();
            props.setProperty("user", DATABASE_USER);
            props.setProperty("password", DATABASE_PASSWORD);
            props.setProperty("connectTimeout", String.valueOf(TIMEOUT.toSeconds()));
            props.setProperty("loginTimeout", String.valueOf(TIMEOUT.toSeconds()));
            String url = "jdbc:postgresql://" + instance.host() + ":"
                    + instance.port() + "/" + instance.database();
    
            // try-with-resources closes the connection and statement when the
            // block exits, whether or not a query failed.
            try (Connection conn = DriverManager.getConnection(url, props);
                 Statement stmt = conn.createStatement()) {
                String database;
                try (ResultSet rs = stmt.executeQuery("SELECT current_database()")) {
                    rs.next();
                    database = rs.getString(1);
                }
                try (ResultSet rs = stmt.executeQuery(
                        "SELECT extversion FROM pg_extension WHERE extname = 'spock'")) {
                    return new String[] {
                        database, rs.next() ? rs.getString(1) : "not installed"
                    };
                }
            }
        }
    
        public static void main(String[] args) {
            if (DATABASE_PASSWORD == null) {
                System.err.println("CONTROL_PLANE_DATABASE_PASSWORD must be set");
                System.exit(1);
            }
    
            Instance instance;
            try {
                instance = findInstance(HttpClient.newHttpClient());
            // IOException covers failures to reach the server, such as a
            // refused connection or a timeout. The message of a refused
            // connection can be empty, so print the exception itself, which
            // includes its type.
            } catch (IOException | InterruptedException e) {
                System.err.println("Control Plane error: " + e);
                System.exit(1);
                return;
            } catch (ControlPlaneException e) {
                System.err.println("Control Plane error: " + e.getMessage());
                System.exit(1);
                return;
            }
            System.out.println("Connecting to node " + instance.node());
    
            try {
                String[] result = query(instance);
                System.out.println("Connected to database " + result[0]);
                System.out.println("Spock: " + result[1]);
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
     * Finding the address of a pgEdge Control Plane database and connecting
     * to it, using HttpClient, System.Text.Json and Npgsql.
     *
     * These examples are for the Control Plane v0.11.0.
     *
     * Copyright (c) 2026, pgEdge, Inc.
     * This code is released under the PostgreSQL License.
     */
    
    using System.Text.Json;
    using System.Text.Json.Nodes;
    using Npgsql;
    
    // Returns the value of an environment variable, or a fallback if the
    // variable is unset or empty.
    static string? EnvOr(string name, string? fallback) =>
        Environment.GetEnvironmentVariable(name) is { Length: > 0 } value
            ? value
            : fallback;
    
    static string BaseUrl() =>
        EnvOr("CONTROL_PLANE_URL", "http://localhost:3000")!.TrimEnd('/');
    
    // The password has no default; the Control Plane never returns it, so it
    // comes from whoever created the database user.
    static string DatabaseId() => EnvOr("CONTROL_PLANE_DATABASE_ID", "cookbook")!;
    static string DatabaseUser() => EnvOr("CONTROL_PLANE_DATABASE_USER", "cookbook")!;
    static string? DatabasePassword() => EnvOr("CONTROL_PLANE_DATABASE_PASSWORD", null);
    
    const int TimeoutSeconds = 30;
    
    // Returns at most the first 200 characters of a reply.
    static string Shorten(string text) =>
        text.Length > 200 ? text[..200] : text;
    
    // Fetches a path from the server, and returns the decoded reply.
    static async Task<JsonObject> GetAsync(HttpClient client, string path)
    {
        using var response = await client.GetAsync(BaseUrl() + path);
        var body = await response.Content.ReadAsStringAsync();
        if (!response.IsSuccessStatusCode)
        {
            throw new ControlPlaneException(
                $"HTTP {(int)response.StatusCode}, {Shorten(body)}");
        }
        try
        {
            if (JsonNode.Parse(body) is JsonObject reply)
            {
                return reply;
            }
        }
        catch (JsonException)
        {
            // The body is not JSON; report it below.
        }
        throw new ControlPlaneException($"Unexpected response: {Shorten(body)}");
    }
    
    // Returns the connection settings for the first instance of the database
    // that is available. Each instance runs one node of the database, and its
    // connection_info holds the addresses and port that clients use.
    static async Task<Instance> FindInstanceAsync(HttpClient client)
    {
        var database = await GetAsync(client, $"/v1/databases/{DatabaseId()}");
        if (database["instances"] is JsonArray instances)
        {
            foreach (var instance in instances)
            {
                var info = instance?["connection_info"];
                if (instance?["state"]?.ToString() == "available" &&
                    info?["addresses"] is JsonArray { Count: > 0 } addresses)
                {
                    return new Instance(
                        instance["node_name"]?.ToString() ?? "",
                        addresses[0]!.ToString(),
                        info["port"]?.GetValue<int>() ?? 0,
                        database["spec"]?["database_name"]?.ToString() ?? "");
                }
            }
        }
        throw new ControlPlaneException($"no available instance of {DatabaseId()}");
    }
    
    // Connects to the instance, and returns the name of the database and the
    // version of the Spock extension. The builder takes care of quoting any
    // special characters.
    static async Task<(string Database, string Spock)> QueryAsync(Instance instance)
    {
        var connectionString = new NpgsqlConnectionStringBuilder
        {
            Host = instance.Host,
            Port = instance.Port,
            Database = instance.Database,
            Username = DatabaseUser(),
            Password = DatabasePassword(),
            Timeout = TimeoutSeconds,
        }.ConnectionString;
    
        // await using closes the connection and commands when the block
        // exits, whether or not a query failed.
        await using var conn = new NpgsqlConnection(connectionString);
        await conn.OpenAsync();
    
        await using var databaseCmd = new NpgsqlCommand("SELECT current_database()", conn);
        var database = (string)(await databaseCmd.ExecuteScalarAsync())!;
    
        await using var spockCmd = new NpgsqlCommand(
            "SELECT extversion FROM pg_extension WHERE extname = 'spock'", conn);
        var spock = await spockCmd.ExecuteScalarAsync() as string ?? "not installed";
        return (database, spock);
    }
    
    if (DatabasePassword() is null)
    {
        Console.Error.WriteLine("CONTROL_PLANE_DATABASE_PASSWORD must be set");
        return 1;
    }
    
    Instance found;
    try
    {
        // using disposes of the client, and closes its connections, when the
        // block exits, whether or not an error occurred.
        using var client = new HttpClient
        {
            Timeout = TimeSpan.FromSeconds(TimeoutSeconds),
        };
        found = await FindInstanceAsync(client);
    }
    // HttpRequestException covers failures to reach the server, such as a
    // refused connection, and TaskCanceledException covers a timeout.
    catch (Exception e) when (
        e is HttpRequestException or TaskCanceledException or ControlPlaneException)
    {
        Console.Error.WriteLine($"Control Plane error: {e.Message}");
        return 1;
    }
    Console.WriteLine($"Connecting to node {found.Node}");
    
    try
    {
        var (database, spock) = await QueryAsync(found);
        Console.WriteLine($"Connected to database {database}");
        Console.WriteLine($"Spock: {spock}");
    }
    // NpgsqlException is the base class for the driver's errors, including
    // connection failures and errors reported by the server.
    catch (NpgsqlException e)
    {
        Console.Error.WriteLine($"Database error: {e.Message}");
        return 1;
    }
    return 0;
    
    // C# requires type declarations to follow the top-level statements, so
    // the settings for one instance, and the exception that the program
    // throws for an error reply, are declared here, at the end.
    record Instance(string Node, string Host, int Port, string Database);
    
    class ControlPlaneException(string message) : Exception(message);
    
    ```

=== "Go"

    ```go
    // Ellie's Postgres Cookbook
    // Finding the address of a pgEdge Control Plane database and connecting
    // to it, using net/http and pgx.
    //
    // These examples are for the Control Plane v0.11.0.
    //
    // Copyright (c) 2026, pgEdge, Inc.
    // This code is released under the PostgreSQL License.
    
    package main
    
    import (
    	"context"
    	"encoding/json"
    	"errors"
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
    
    // The password has no default; the Control Plane never returns it, so it
    // comes from whoever created the database user.
    var (
    	baseURL          = strings.TrimRight(envOr("CONTROL_PLANE_URL", "http://localhost:3000"), "/")
    	databaseID       = envOr("CONTROL_PLANE_DATABASE_ID", "cookbook")
    	databaseUser     = envOr("CONTROL_PLANE_DATABASE_USER", "cookbook")
    	databasePassword = os.Getenv("CONTROL_PLANE_DATABASE_PASSWORD")
    )
    
    const timeout = 30 * time.Second
    
    // get fetches a path from the server, and decodes the reply into out.
    func get(client *http.Client, path string, out any) error {
    	response, err := client.Get(baseURL + path)
    	if err != nil {
    		return err
    	}
    	defer response.Body.Close()
    
    	body, err := io.ReadAll(response.Body)
    	if err != nil {
    		return err
    	}
    
    	// Go treats an error status as a normal response, so check it here.
    	if response.StatusCode != http.StatusOK {
    		return fmt.Errorf("HTTP %d, %.200s", response.StatusCode, strings.TrimSpace(string(body)))
    	}
    	if err := json.Unmarshal(body, out); err != nil {
    		return fmt.Errorf("unexpected response: %.200s", body)
    	}
    	return nil
    }
    
    
    // instance holds the settings for connecting to one instance.
    type instance struct {
    	Node     string
    	Host     string
    	Port     int
    	Database string
    }
    
    // findInstance returns the connection settings for the first instance of
    // the database that is available. Each instance runs one node of the
    // database, and its connection_info holds the addresses and port that
    // clients use.
    func findInstance(client *http.Client) (*instance, error) {
    	var database struct {
    		Spec struct {
    			DatabaseName string `json:"database_name"`
    		} `json:"spec"`
    		Instances []struct {
    			NodeName       string `json:"node_name"`
    			State          string `json:"state"`
    			ConnectionInfo struct {
    				Addresses []string `json:"addresses"`
    				Port      int      `json:"port"`
    			} `json:"connection_info"`
    		} `json:"instances"`
    	}
    	if err := get(client, "/v1/databases/"+databaseID, &database); err != nil {
    		return nil, err
    	}
    	for _, i := range database.Instances {
    		if i.State == "available" && len(i.ConnectionInfo.Addresses) > 0 {
    			return &instance{
    				Node:     i.NodeName,
    				Host:     i.ConnectionInfo.Addresses[0],
    				Port:     i.ConnectionInfo.Port,
    				Database: database.Spec.DatabaseName,
    			}, nil
    		}
    	}
    	return nil, fmt.Errorf("no available instance of %s", databaseID)
    }
    
    
    // query connects to the instance, and returns the name of the database
    // and the version of the Spock extension.
    func query(ctx context.Context, i *instance) (database, spock string, err error) {
    	// net/url takes care of escaping any special characters in the user
    	// name, password, or database name.
    	u := url.URL{
    		Scheme:   "postgres",
    		User:     url.UserPassword(databaseUser, databasePassword),
    		Host:     net.JoinHostPort(i.Host, strconv.Itoa(i.Port)),
    		Path:     "/" + i.Database,
    		RawQuery: "connect_timeout=30",
    	}
    
    	conn, err := pgx.Connect(ctx, u.String())
    	if err != nil {
    		return "", "", err
    	}
    	// Close the connection when the function returns, whether or not a
    	// query failed.
    	defer conn.Close(ctx)
    
    	if err := conn.QueryRow(ctx, "SELECT current_database()").Scan(&database); err != nil {
    		return "", "", err
    	}
    	err = conn.QueryRow(ctx,
    		"SELECT extversion FROM pg_extension WHERE extname = 'spock'").Scan(&spock)
    	if errors.Is(err, pgx.ErrNoRows) {
    		return database, "not installed", nil
    	}
    	return database, spock, err
    }
    
    
    func main() {
    	if databasePassword == "" {
    		fmt.Fprintln(os.Stderr, "CONTROL_PLANE_DATABASE_PASSWORD must be set")
    		os.Exit(1)
    	}
    
    	i, err := findInstance(&http.Client{Timeout: timeout})
    	if err != nil {
    		fmt.Fprintf(os.Stderr, "Control Plane error: %v\n", err)
    		os.Exit(1)
    	}
    	fmt.Printf("Connecting to node %s\n", i.Node)
    
    	database, spock, err := query(context.Background(), i)
    	if err != nil {
    		fmt.Fprintf(os.Stderr, "Database error: %v\n", err)
    		os.Exit(1)
    	}
    	fmt.Printf("Connected to database %s\n", database)
    	fmt.Printf("Spock: %s\n", spock)
    }
    
    
    ```

=== "Rust"

    ```rust
    // Ellie's Postgres Cookbook
    // Finding the address of a pgEdge Control Plane database and connecting
    // to it, using reqwest, serde_json and the postgres crate.
    //
    // These examples are for the Control Plane v0.11.0.
    //
    // Copyright (c) 2026, pgEdge, Inc.
    // This code is released under the PostgreSQL License.
    
    use std::env;
    use std::error::Error;
    use std::process::ExitCode;
    use std::time::Duration;
    
    use postgres::{Config, NoTls};
    use reqwest::blocking::Client;
    use serde_json::Value;
    
    /// Returns the value of an environment variable, or None if the variable
    /// is unset or empty.
    fn env_value(name: &str) -> Option<String> {
        env::var(name).ok().filter(|value| !value.is_empty())
    }
    
    /// Returns the value of an environment variable, or a fallback.
    fn env_or(name: &str, fallback: &str) -> String {
        env_value(name).unwrap_or_else(|| fallback.to_string())
    }
    
    fn base_url() -> String {
        env_or("CONTROL_PLANE_URL", "http://localhost:3000")
            .trim_end_matches('/')
            .to_string()
    }
    
    // The password has no default; the Control Plane never returns it, so it
    // comes from whoever created the database user.
    fn database_id() -> String {
        env_or("CONTROL_PLANE_DATABASE_ID", "cookbook")
    }
    
    const TIMEOUT: Duration = Duration::from_secs(30);
    
    /// The errors that the functions below return; a string converts into one
    /// with the ? operator or into().
    type BoxError = Box<dyn Error>;
    
    /// Returns at most the first 200 characters of a reply.
    fn shorten(text: &str) -> String {
        text.chars().take(200).collect()
    }
    
    /// Fetches a path from the server, and returns the decoded reply.
    fn get(client: &Client, path: &str) -> Result<Value, BoxError> {
        let response = client.get(format!("{}{path}", base_url())).send()?;
        let status = response.status();
        let body = response.text()?;
        if !status.is_success() {
            return Err(format!("HTTP {}, {}", status.as_u16(), shorten(&body)).into());
        }
        match serde_json::from_str::<Value>(&body) {
            Ok(reply) if reply.is_object() => Ok(reply),
            _ => Err(format!("Unexpected response: {}", shorten(&body)).into()),
        }
    }
    
    /// The settings for connecting to one instance.
    struct Instance {
        node: String,
        host: String,
        port: u16,
        database: String,
    }
    
    /// Returns the connection settings for the first instance of the database
    /// that is available. Each instance runs one node of the database, and
    /// its connection_info holds the addresses and port that clients use.
    fn find_instance(client: &Client) -> Result<Instance, BoxError> {
        let database = get(client, &format!("/v1/databases/{}", database_id()))?;
        // as_array() gives None when the reply lists no instances.
        for instance in database["instances"].as_array().into_iter().flatten() {
            let info = &instance["connection_info"];
            if let (Some("available"), Some(address)) =
                (instance["state"].as_str(), info["addresses"][0].as_str())
            {
                return Ok(Instance {
                    node: instance["node_name"].as_str().unwrap_or("").to_string(),
                    host: address.to_string(),
                    port: info["port"].as_u64().unwrap_or(0).try_into()?,
                    database: database["spec"]["database_name"]
                        .as_str()
                        .unwrap_or("")
                        .to_string(),
                });
            }
        }
        Err(format!("no available instance of {}", database_id()).into())
    }
    
    /// Connects to the instance, and returns the name of the database and the
    /// version of the Spock extension. NoTls disables TLS, which keeps this
    /// example free of certificate set-up; connections over an untrusted
    /// network should use TLS.
    fn query(instance: &Instance, password: &str) -> Result<(String, String), postgres::Error> {
        let mut client = Config::new()
            .host(&instance.host)
            .port(instance.port)
            .dbname(&instance.database)
            .user(&env_or("CONTROL_PLANE_DATABASE_USER", "cookbook"))
            .password(password)
            .connect_timeout(TIMEOUT)
            .connect(NoTls)?;
    
        let database: String = client.query_one("SELECT current_database()", &[])?.get(0);
        // query_opt returns None when no row matches.
        let spock = client
            .query_opt("SELECT extversion FROM pg_extension WHERE extname = 'spock'", &[])?
            .map(|row| row.get(0))
            .unwrap_or_else(|| "not installed".to_string());
        // The client closes its connection when it goes out of scope.
        Ok((database, spock))
    }
    
    /// Prints an error with the chain of underlying causes, since the
    /// top-level error is often generic ("error sending request").
    fn report(prefix: &str, e: &dyn Error) {
        eprintln!("{prefix}: {e}");
        let mut cause = e.source();
        while let Some(c) = cause {
            eprintln!("  caused by: {c}");
            cause = c.source();
        }
    }
    
    fn main() -> ExitCode {
        let Some(password) = env_value("CONTROL_PLANE_DATABASE_PASSWORD") else {
            eprintln!("CONTROL_PLANE_DATABASE_PASSWORD must be set");
            return ExitCode::FAILURE;
        };
    
        let instance = match Client::builder()
            .timeout(TIMEOUT)
            .build()
            .map_err(BoxError::from)
            .and_then(|client| find_instance(&client))
        {
            Ok(instance) => instance,
            Err(e) => {
                report("Control Plane error", e.as_ref());
                return ExitCode::FAILURE;
            }
        };
        println!("Connecting to node {}", instance.node);
    
        match query(&instance, &password) {
            Ok((database, spock)) => {
                println!("Connected to database {database}");
                println!("Spock: {spock}");
                ExitCode::SUCCESS
            }
            Err(e) => {
                report("Database error", &e);
                ExitCode::FAILURE
            }
        }
    }
    
    ```

=== "Ruby"

    ```ruby
    # Ellie's Postgres Cookbook
    # Finding the address of a pgEdge Control Plane database and connecting
    # to it, using Net::HTTP and the pg gem.
    #
    # These examples are for the Control Plane v0.11.0.
    #
    # Copyright (c) 2026, pgEdge, Inc.
    # This code is released under the PostgreSQL License.
    
    require "json"
    require "net/http"
    require "pg"
    require "uri"
    
    # Returns the value of an environment variable, or a fallback if the
    # variable is unset or empty.
    def env_or(name, fallback)
      value = ENV[name]
      value.nil? || value.empty? ? fallback : value
    end
    
    # The password has no default; the Control Plane never returns it, so it
    # comes from whoever created the database user.
    BASE_URL = env_or("CONTROL_PLANE_URL", "http://localhost:3000").sub(%r{/+\z}, "")
    DATABASE_ID = env_or("CONTROL_PLANE_DATABASE_ID", "cookbook")
    DATABASE_USER = env_or("CONTROL_PLANE_DATABASE_USER", "cookbook")
    DATABASE_PASSWORD = env_or("CONTROL_PLANE_DATABASE_PASSWORD", nil)
    
    TIMEOUT_SECONDS = 30
    
    # Raised when the Control Plane rejects a request or replies oddly.
    class ControlPlaneError < StandardError; end
    
    # Fetches a path from the server, and returns the decoded reply.
    def get(http, path)
      response = http.request(Net::HTTP::Get.new(URI("#{BASE_URL}#{path}")))
      unless response.is_a?(Net::HTTPSuccess)
        raise ControlPlaneError, "HTTP #{response.code}, #{response.body.to_s[0, 200]}"
      end
    
      begin
        body = JSON.parse(response.body.to_s)
        return body if body.is_a?(Hash)
      rescue JSON::ParserError
        # The body is not JSON; report it below.
      end
      raise ControlPlaneError, "Unexpected response: #{response.body.to_s[0, 200]}"
    end
    
    # Returns the connection settings for the first instance of the database
    # that is available. Each instance runs one node of the database, and its
    # connection_info holds the addresses and port that clients use.
    def find_instance(http)
      database = get(http, "/v1/databases/#{DATABASE_ID}")
      (database["instances"] || []).each do |instance|
        info = instance["connection_info"] || {}
        next unless instance["state"] == "available" && !(info["addresses"] || []).empty?
    
        return {
          node: instance["node_name"],
          host: info["addresses"].first,
          port: info["port"],
          dbname: (database["spec"] || {})["database_name"]
        }
      end
      raise ControlPlaneError, "no available instance of #{DATABASE_ID}"
    end
    
    # Connects to the instance, and returns the name of the database and the
    # version of the Spock extension.
    def query(instance)
      conn = PG.connect(
        host: instance[:host], port: instance[:port], dbname: instance[:dbname],
        user: DATABASE_USER, password: DATABASE_PASSWORD,
        connect_timeout: TIMEOUT_SECONDS
      )
      begin
        database = conn.exec("SELECT current_database()").getvalue(0, 0)
        spock = conn.exec("SELECT extversion FROM pg_extension WHERE extname = 'spock'")
        [database, spock.ntuples.zero? ? "not installed" : spock.getvalue(0, 0)]
      ensure
        # Close the connection whether or not a query failed.
        conn.close
      end
    end
    
    if DATABASE_PASSWORD.nil?
      warn "CONTROL_PLANE_DATABASE_PASSWORD must be set"
      exit 1
    end
    
    begin
      uri = URI(BASE_URL)
      # start opens a connection, and closes it when the block exits, whether
      # or not an error occurred.
      instance = Net::HTTP.start(
        uri.host, uri.port,
        use_ssl: uri.scheme == "https",
        open_timeout: TIMEOUT_SECONDS, read_timeout: TIMEOUT_SECONDS
      ) { |http| find_instance(http) }
    # SystemCallError covers a refused connection, Timeout::Error covers the
    # connection and read timeouts, and SocketError covers an unknown host.
    rescue ControlPlaneError, SystemCallError, Timeout::Error, SocketError, IOError => e
      warn "Control Plane error: #{e.message}"
      exit 1
    end
    puts "Connecting to node #{instance[:node]}"
    
    begin
      database, spock = query(instance)
    # PG::Error is the base class for every error the gem raises, including
    # connection failures and errors reported by the server.
    rescue PG::Error => e
      warn "Database error: #{e.message}"
      exit 1
    end
    puts "Connected to database #{database}"
    puts "Spock: #{spock}"
    
    ```

=== "curl"

    ```bash
    #!/usr/bin/env bash
    #
    # Ellie's Postgres Cookbook
    # Finding the address of a pgEdge Control Plane database and connecting
    # to it, using curl, jq and psql.
    #
    # These examples are for the Control Plane v0.11.0.
    #
    # Copyright (c) 2026, pgEdge, Inc.
    # This code is released under the PostgreSQL License.
    
    # Stop at the first failed command or unset variable, and treat a failure
    # anywhere in a pipeline as a failure of the whole pipeline.
    set -euo pipefail
    
    for tool in curl jq psql; do
        command -v "$tool" >/dev/null || { echo "Control Plane error: $tool is required" >&2; exit 1; }
    done
    
    # The :- operator treats an empty variable as unset. The password has no
    # default; the Control Plane never returns it, so it comes from whoever
    # created the database user.
    CONTROL_PLANE_URL="${CONTROL_PLANE_URL:-http://localhost:3000}"
    CONTROL_PLANE_URL="${CONTROL_PLANE_URL%/}"
    DATABASE_ID="${CONTROL_PLANE_DATABASE_ID:-cookbook}"
    DATABASE_USER="${CONTROL_PLANE_DATABASE_USER:-cookbook}"
    DATABASE_PASSWORD="${CONTROL_PLANE_DATABASE_PASSWORD:-}"
    
    TIMEOUT_SECONDS=30
    
    # Fetches a path from the server and prints the JSON reply. With
    # --fail-with-body, curl exits non-zero on an HTTP error status but still
    # prints the body, which carries the server's explanation.
    get() {
        curl --silent --show-error --fail-with-body \
            --max-time "$TIMEOUT_SECONDS" "$CONTROL_PLANE_URL$1"
    }
    
    # Prints the database name, node name, address and port of the first
    # instance of the database that is available, separated by spaces. Each
    # instance runs one node of the database, and its connection_info holds
    # the addresses and port that clients use.
    find_instance() {
        local response
        response="$(get "/v1/databases/$DATABASE_ID")" || {
            echo "Control Plane error: $response" >&2
            return 1
        }
        jq -er '
            .spec.database_name as $name
            | first(.instances[]?
                    | select(.state == "available"
                             and (.connection_info.addresses | length) > 0))
            | "\($name) \(.node_name) \(.connection_info.addresses[0]) \(.connection_info.port)"
            ' <<<"$response" || {
            echo "Control Plane error: no available instance of $DATABASE_ID" >&2
            return 1
        }
    }
    
    # Connects with psql and runs the two queries. PGPASSWORD passes the
    # password through the environment, so it never appears in the process
    # list. The -X option skips any .psqlrc, -A and -t print bare values, and
    # ON_ERROR_STOP makes psql exit non-zero if a query fails.
    query() {
        local name="$1" address="$2" port="$3"
        PGPASSWORD="$DATABASE_PASSWORD" PGCONNECT_TIMEOUT="$TIMEOUT_SECONDS" \
            psql -X -A -t -v ON_ERROR_STOP=1 \
            --host "$address" --port "$port" \
            --username "$DATABASE_USER" --dbname "$name" \
            -c "SELECT current_database()" \
            -c "SELECT coalesce((SELECT extversion FROM pg_extension
                                 WHERE extname = 'spock'), 'not installed')"
    }
    
    main() {
        local instance name node address port result database spock
    
        if [[ -z "$DATABASE_PASSWORD" ]]; then
            echo "CONTROL_PLANE_DATABASE_PASSWORD must be set" >&2
            exit 1
        fi
    
        instance="$(find_instance)" || exit 1
        read -r name node address port <<<"$instance"
        echo "Connecting to node $node"
    
        result="$(query "$name" "$address" "$port")" || {
            echo "Database error: could not query $name" >&2
            exit 1
        }
        # psql prints the result of each query on a line of its own.
        { read -r database; read -r spock; } <<<"$result"
        echo "Connected to database $database"
        echo "Spock: $spock"
    }
    
    main
    
    ```

## Next Steps

The following resources provide more information about the topics in this
recipe:

- The [Changing a Database's Settings](update_database.md) recipe shows how to
  change a Postgres setting through the Control Plane, and check it over a
  connection.
- The [Creating a Database](create_database.md) recipe shows how to create a
  database to connect to.
- The
  [pgEdge Control Plane documentation](https://docs.pgedge.com/control-plane/v0-11/)
  describes every endpoint and setting.
- The [Contributing a Recipe](../contributing.md) page explains how to add a
  recipe or a language to the cookbook.
