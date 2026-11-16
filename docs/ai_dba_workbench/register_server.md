# Registering a Server with the AI DBA Workbench API

This recipe shows how a program registers a PostgreSQL server for monitoring
with the pgEdge AI DBA Workbench API, finds it in the list of connections, and
deletes it again. These examples are for AI DBA Workbench 1.0.0. Each step
shows the code in every supported language; selecting a language tab switches
every tab on the site to that language.

The example program registers a second connection to the same PostgreSQL server
that an existing connection monitors, so that it needs no other server. It logs
in, reads the address of the existing connection, registers a new connection
called `cookbook-register-server`, checks that the new connection appears in
the list, and then deletes it. The program deletes the connection even when a
step in the middle fails, so a failed run does not leave a monitored server
behind. The output has the following form:

```text
Registered the server 'cookbook-register-server'
Found 'cookbook-register-server' in the list (monitored: true)
Deleted the connection
The connection is no longer in the list
```

## Preparing the Ingredients

The `scripts/start_workbench.sh` script in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook)
starts a test Workbench in Docker. The script creates a `cookbook` user and an
API token, registers a test PostgreSQL server as a monitored connection, and
prints the `WORKBENCH_URL`, `WORKBENCH_TOKEN`, `WORKBENCH_USERNAME`,
`WORKBENCH_PASSWORD`, and `WORKBENCH_CONNECTION_ID` values that the examples
read from the environment.

The examples need a running Workbench server, a user that can log in, and the
ID of an existing connection. The following table lists the HTTP client and the
JSON library that each example uses:

| Language   | HTTP client and JSON library                                   |
|------------|----------------------------------------------------------------|
| Python     | [httpx](https://www.python-httpx.org/) and the `json` module   |
| TypeScript | The `fetch` function that Node.js provides                     |
| Java       | The `java.net.http` client and [Jackson](https://github.com/FasterXML/jackson) |
| C#         | `HttpClient` and `System.Text.Json`, which are part of .NET    |
| Go         | The `net/http` and `encoding/json` standard library packages   |
| Rust       | [reqwest](https://docs.rs/reqwest) and [serde_json](https://docs.rs/serde_json) |
| Ruby       | `Net::HTTP` and `json`, which come with Ruby                   |

The curl example is a bash script that uses [jq](https://jqlang.org/) to read
the JSON replies. The following tabs show the dependency declaration from each
example project:

=== "Python"

    ```text
    # httpx, an HTTP client with a requests-like interface.
    httpx>=0.28,<1
    ```

=== "TypeScript"

    ```json
    {
      "name": "register_server",
      "private": true,
      "type": "module",
      "scripts": {
        "build": "tsc",
        "start": "node dist/main.js"
      },
      "devDependencies": {
        "@types/node": "^22.0.0",
        "typescript": "^5.9.0"
      }
    }
    
    ```

=== "Java"

    ```xml
    <dependencies>
      <!-- Jackson, for JSON; the HTTP client is part of the JDK. -->
      <dependency>
        <groupId>tools.jackson.core</groupId>
        <artifactId>jackson-databind</artifactId>
        <version>3.2.4</version>
      </dependency>
    </dependencies>
    ```

=== "C#"

    ```xml
    <!-- The program uses only HttpClient and System.Text.Json, which are
         part of .NET, so it needs no packages. -->
    ```

=== "Go"

    ```text
    // The program uses only the Go standard library, so it needs no modules.
    go 1.25.0
    
    ```

=== "Rust"

    ```toml
    [dependencies]
    # The blocking client of reqwest, with rustls for TLS and JSON bodies.
    reqwest = { version = "0.13", default-features = false, features = ["blocking", "json", "rustls"] }
    serde_json = "1"
    ```

=== "Ruby"

    ```ruby
    source "https://rubygems.org"
    
    # The program uses only Net::HTTP and JSON, which come with Ruby, so it
    # needs no gems.
    ```

## Importing the Libraries

Each program begins by importing the modules that it uses. The following tabs
show the imports for each language:

=== "Python"

    ```python
    import os
    import sys
    
    import httpx
    ```

=== "TypeScript"

    ```typescript
    // The program needs no imports: fetch and process are built in to Node.js.
    ```

=== "Java"

    ```java
    import java.io.IOException;
    import java.net.URI;
    import java.net.http.HttpClient;
    import java.net.http.HttpRequest;
    import java.net.http.HttpResponse;
    import java.net.http.HttpTimeoutException;
    import java.time.Duration;
    import java.util.Map;
    import java.util.Objects;
    import java.util.concurrent.CompletableFuture;
    import java.util.concurrent.ExecutionException;
    import java.util.concurrent.TimeUnit;
    import java.util.concurrent.TimeoutException;
    import java.util.regex.Matcher;
    import java.util.regex.Pattern;
    import tools.jackson.core.JacksonException;
    import tools.jackson.databind.JsonNode;
    import tools.jackson.databind.ObjectMapper;
    import tools.jackson.databind.node.ObjectNode;
    ```

=== "C#"

    ```csharp
    using System.Net.Http.Headers;
    using System.Net.Http.Json;
    using System.Text.Json;
    using System.Text.Json.Nodes;
    using System.Text.RegularExpressions;
    ```

=== "Go"

    ```go
    import (
    	"bytes"
    	"encoding/json"
    	"errors"
    	"fmt"
    	"io"
    	"net/http"
    	"os"
    	"strings"
    	"time"
    )
    
    ```

=== "Rust"

    ```rust
    use std::env;
    use std::error::Error;
    use std::process::ExitCode;
    use std::sync::LazyLock;
    use std::time::Duration;
    
    use reqwest::blocking::{Client, Response};
    use reqwest::Method;
    use serde_json::{json, Value};
    ```

=== "Ruby"

    ```ruby
    require "json"
    require "net/http"
    ```

=== "curl"

    ```bash
    # Stop at the first failing command, treat an unset variable as an error,
    # and fail a pipeline when any command in it fails.
    set -euo pipefail
    
    # The script needs curl to make the requests and jq to read the replies.
    for tool in curl jq; do
        command -v "$tool" >/dev/null || { echo "$tool is required" >&2; exit 1; }
    done
    ```

## Configuring the Connection

The examples read their settings from environment variables, and treat an empty
variable as unset. The following table describes the variables that the
examples read:

| Variable                  | Description                                   |
|---------------------------|-----------------------------------------------|
| `WORKBENCH_URL`           | The base URL; default `http://localhost:8080` |
| `WORKBENCH_USERNAME`      | The user to log in as.                        |
| `WORKBENCH_PASSWORD`      | The password of that user.                    |
| `WORKBENCH_CONNECTION_ID` | An existing connection to copy.               |
| `PGPASSWORD`              | The new connection password (optional).       |

The new connection uses the password in `PGPASSWORD`, which is the variable
that `psql` reads, so the example works against the same server as the other
recipes. The Workbench 1.0.0 server rejects a connection with an empty
password, even when the monitored server uses trust authentication and ignores
the password. When `PGPASSWORD` is not set, the examples send a placeholder
password instead. The placeholder works only with trust authentication: for a
server that checks passwords, the registration succeeds, but the collector then
fails to connect, so set `PGPASSWORD` to the real password.

If a run is killed without a chance to clean up (with `kill -9`, for example),
the connection `cookbook-register-server` stays registered, and the next run
registers a second one with the same name. To remove the leftover, find its ID
in the reply to `GET /api/v1/connections`, and send `DELETE
/api/v1/connections/{id}` with a session token, or delete it in the Workbench
web interface.

!!! note

    Production applications should not store passwords in environment
    variables or source code. A secrets manager provides a safer
    alternative.

The following tabs show how each program reads the settings and stops with an
error when a required variable is missing:

=== "Python"

    ```python
    SERVER_NAME = "cookbook-register-server"
    
    
    def settings() -> dict:
        """Reads the settings from the environment.
    
        The or operator treats an empty variable as unset.
        """
        username = os.environ.get("WORKBENCH_USERNAME") or ""
        password = os.environ.get("WORKBENCH_PASSWORD") or ""
        connection_id = os.environ.get("WORKBENCH_CONNECTION_ID") or ""
        if not (username and password and connection_id):
            raise RuntimeError(
                "WORKBENCH_USERNAME, WORKBENCH_PASSWORD, and "
                "WORKBENCH_CONNECTION_ID must be set"
            )
        return {
            "base_url": (
                os.environ.get("WORKBENCH_URL") or "http://localhost:8080"
            ).rstrip("/"),
            "username": username,
            "password": password,
            "connection_id": connection_id,
            # The Workbench refuses to register a server without a password,
            # even one that uses trust authentication, so fall back to a
            # placeholder.
            "server_password": (
                os.environ.get("PGPASSWORD") or "unused-with-trust-authentication"
            ),
        }
    ```

=== "TypeScript"

    ```typescript
    const SERVER_NAME = "cookbook-register-server";
    
    interface Settings {
      baseUrl: string;
      username: string;
      password: string;
      connectionId: string;
      serverPassword: string;
    }
    
    // Read the settings from the environment. The || operator, unlike ??, also
    // treats an empty variable as unset.
    function settings(): Settings {
      const username = process.env.WORKBENCH_USERNAME || "";
      const password = process.env.WORKBENCH_PASSWORD || "";
      const connectionId = process.env.WORKBENCH_CONNECTION_ID || "";
      if (!username || !password || !connectionId) {
        throw new Error(
          "WORKBENCH_USERNAME, WORKBENCH_PASSWORD, and WORKBENCH_CONNECTION_ID " +
            "must be set",
        );
      }
      const baseUrl = process.env.WORKBENCH_URL || "http://localhost:8080";
      return {
        baseUrl: baseUrl.replace(/\/+$/, ""),
        username,
        password,
        connectionId,
        // The Workbench refuses to register a server without a password, even
        // one that uses trust authentication, so fall back to a placeholder.
        serverPassword:
          process.env.PGPASSWORD || "unused-with-trust-authentication",
      };
    }
    ```

=== "Java"

    ```java
    static final String SERVER_NAME = "cookbook-register-server";
    
    /** The settings that the program reads from the environment. */
    record Settings(String baseUrl, String username, String password,
            String connectionId, String serverPassword) {}
    
    /**
     * Returns the value of an environment variable, or the fallback if the
     * variable is unset or empty, as an unset variable would be.
     */
    static String envOr(String name, String fallback) {
        String value = System.getenv(name);
        return (value != null && !value.isEmpty()) ? value : fallback;
    }
    
    /** Reads the settings from the environment. */
    static Settings settings() throws IOException {
        String username = envOr("WORKBENCH_USERNAME", "");
        String password = envOr("WORKBENCH_PASSWORD", "");
        String connectionId = envOr("WORKBENCH_CONNECTION_ID", "");
        if (username.isEmpty() || password.isEmpty()
                || connectionId.isEmpty()) {
            throw new IOException("WORKBENCH_USERNAME, WORKBENCH_PASSWORD, "
                    + "and WORKBENCH_CONNECTION_ID must be set");
        }
        String baseUrl = envOr("WORKBENCH_URL", "http://localhost:8080")
                .replaceAll("/+$", "");
        // The Workbench refuses to register a server without a password,
        // even one that uses trust authentication, so fall back to a
        // placeholder.
        String serverPassword =
                envOr("PGPASSWORD", "unused-with-trust-authentication");
        return new Settings(baseUrl, username, password, connectionId,
                serverPassword);
    }
    ```

=== "C#"

    ```csharp
    const string ServerName = "cookbook-register-server";
    
    // Returns the value of an environment variable, or null if the variable
    // is unset or empty, as an unset variable would be.
    static string? EnvValue(string name) =>
        Environment.GetEnvironmentVariable(name) is { Length: > 0 } value
            ? value
            : null;
    
    // Reads the settings from the environment.
    static (string BaseUrl, string Username, string Password,
        string ConnectionId, string ServerPassword) Settings()
    {
        var username = EnvValue("WORKBENCH_USERNAME");
        var password = EnvValue("WORKBENCH_PASSWORD");
        var connectionId = EnvValue("WORKBENCH_CONNECTION_ID");
        if (username is null || password is null || connectionId is null)
        {
            throw new InvalidOperationException(
                "WORKBENCH_USERNAME, WORKBENCH_PASSWORD, and "
                + "WORKBENCH_CONNECTION_ID must be set");
        }
        var baseUrl = EnvValue("WORKBENCH_URL") ?? "http://localhost:8080";
        // The Workbench refuses to register a server without a password, even
        // one that uses trust authentication, so fall back to a placeholder.
        var serverPassword =
            EnvValue("PGPASSWORD") ?? "unused-with-trust-authentication";
        return (baseUrl.TrimEnd('/'), username, password, connectionId,
            serverPassword);
    }
    ```

=== "Go"

    ```go
    const serverName = "cookbook-register-server"
    
    // settings holds the values that the program reads from the environment.
    type settings struct {
    	baseURL        string
    	username       string
    	password       string
    	connectionID   string
    	serverPassword string
    }
    
    // envOr returns the value of an environment variable, or the fallback if
    // the variable is unset or empty, as an unset variable would be.
    func envOr(name, fallback string) string {
    	if value := os.Getenv(name); value != "" {
    		return value
    	}
    	return fallback
    }
    
    // loadSettings reads the settings from the environment.
    func loadSettings() (settings, error) {
    	s := settings{
    		baseURL:      strings.TrimRight(envOr("WORKBENCH_URL", "http://localhost:8080"), "/"),
    		username:     os.Getenv("WORKBENCH_USERNAME"),
    		password:     os.Getenv("WORKBENCH_PASSWORD"),
    		connectionID: os.Getenv("WORKBENCH_CONNECTION_ID"),
    		// The Workbench refuses to register a server without a password,
    		// even one that uses trust authentication, so fall back to a
    		// placeholder.
    		serverPassword: envOr("PGPASSWORD", "unused-with-trust-authentication"),
    	}
    	if s.username == "" || s.password == "" || s.connectionID == "" {
    		return s, errors.New("WORKBENCH_USERNAME, WORKBENCH_PASSWORD, and WORKBENCH_CONNECTION_ID must be set")
    	}
    	return s, nil
    }
    
    ```

=== "Rust"

    ```rust
    const SERVER_NAME: &str = "cookbook-register-server";
    
    /// Any error, boxed, so that a function can return errors of several types
    /// with the ? operator.
    type Result<T> = std::result::Result<T, Box<dyn Error>>;
    
    /// The settings that the program reads from the environment.
    struct Settings {
        base_url: String,
        username: String,
        password: String,
        connection_id: String,
        server_password: String,
    }
    
    /// Returns the value of an environment variable, if it is set and not
    /// empty; an empty variable counts as unset.
    fn env_value(name: &str) -> Option<String> {
        env::var(name).ok().filter(|value| !value.is_empty())
    }
    
    /// Reads the settings from the environment.
    fn settings() -> Result<Settings> {
        let (Some(username), Some(password), Some(connection_id)) = (
            env_value("WORKBENCH_USERNAME"),
            env_value("WORKBENCH_PASSWORD"),
            env_value("WORKBENCH_CONNECTION_ID"),
        ) else {
            return Err("WORKBENCH_USERNAME, WORKBENCH_PASSWORD, and \
                        WORKBENCH_CONNECTION_ID must be set"
                .into());
        };
        let base_url = env_value("WORKBENCH_URL")
            .unwrap_or_else(|| "http://localhost:8080".to_string())
            .trim_end_matches('/')
            .to_string();
        // The Workbench refuses to register a server without a password, even
        // one that uses trust authentication, so fall back to a placeholder.
        let server_password =
            env_value("PGPASSWORD").unwrap_or_else(|| "unused-with-trust-authentication".to_string());
        Ok(Settings {
            base_url,
            username,
            password,
            connection_id,
            server_password,
        })
    }
    ```

=== "Ruby"

    ```ruby
    SERVER_NAME = "cookbook-register-server"
    
    # Returns the value of an environment variable, or a fallback if the
    # variable is unset or empty, as an unset variable would be.
    def env_or(name, fallback)
      value = ENV[name]
      value.nil? || value.empty? ? fallback : value
    end
    
    # Reads the settings from the environment.
    def settings
      username = env_or("WORKBENCH_USERNAME", nil)
      password = env_or("WORKBENCH_PASSWORD", nil)
      connection_id = env_or("WORKBENCH_CONNECTION_ID", nil)
      unless username && password && connection_id
        raise "WORKBENCH_USERNAME, WORKBENCH_PASSWORD, and " \
              "WORKBENCH_CONNECTION_ID must be set"
      end
    
      {
        base_url: env_or("WORKBENCH_URL", "http://localhost:8080").sub(%r{/+\z}, ""),
        username: username,
        password: password,
        connection_id: connection_id,
        # The Workbench refuses to register a server without a password, even
        # one that uses trust authentication, so fall back to a placeholder.
        server_password: env_or("PGPASSWORD", "unused-with-trust-authentication")
      }
    end
    ```

=== "curl"

    ```bash
    # Read the settings from the environment. The :- and :? forms, unlike - and
    # ?, treat an empty variable as unset.
    WORKBENCH_URL="${WORKBENCH_URL:-http://localhost:8080}"
    WORKBENCH_URL="${WORKBENCH_URL%/}"
    : "${WORKBENCH_USERNAME:?WORKBENCH_USERNAME must be set}"
    : "${WORKBENCH_PASSWORD:?WORKBENCH_PASSWORD must be set}"
    : "${WORKBENCH_CONNECTION_ID:?WORKBENCH_CONNECTION_ID must be set}"
    
    # The Workbench refuses to register a server without a password, even one
    # that uses trust authentication, so the script falls back to a placeholder.
    SERVER_PASSWORD="${PGPASSWORD:-unused-with-trust-authentication}"
    SERVER_NAME="cookbook-register-server"
    ```

## Sending Requests

Every call to the API goes through one helper function. The function adds the
`/api/v1` prefix to the path, sends the token as a `Bearer` credential in the
`Authorization` header, and sets a timeout so that a stalled server cannot hang
the program. When the server rejects a request, the function raises an error
that includes the status code and the message from the server. The following
tabs show the helper function from each program:

=== "Python"

    ```python
    def api(method: str, base_url: str, path: str, token: str | None = None,
            **kwargs) -> httpx.Response:
        """Sends a request to the API and returns the response.
    
        A request that the server rejects raises an error that includes the
        message from the server, which raise_for_status alone would leave out.
        """
        headers = {"Authorization": f"Bearer {token}"} if token else {}
        response = httpx.request(
            method, f"{base_url}/api/v1{path}", headers=headers, timeout=30,
            **kwargs,
        )
        if response.is_error:
            raise RuntimeError(
                f"{method} {path} failed with status {response.status_code}: "
                f"{response.text.strip()}"
            )
        return response
    ```

=== "TypeScript"

    ```typescript
    // Sends a request to the API and returns the response. A request that the
    // server rejects throws an error that includes the message from the server.
    async function api(
      method: string,
      baseUrl: string,
      path: string,
      token?: string,
      body?: unknown,
    ): Promise<Response> {
      const headers: Record<string, string> = {};
      if (token) headers["Authorization"] = `Bearer ${token}`;
      if (body !== undefined) headers["Content-Type"] = "application/json";
    
      const response = await fetch(`${baseUrl}/api/v1${path}`, {
        method,
        headers,
        body: body === undefined ? undefined : JSON.stringify(body),
        signal: AbortSignal.timeout(30_000),
      });
      if (!response.ok) {
        const text = (await response.text()).trim();
        throw new Error(
          `${method} ${path} failed with status ${response.status}: ${text}`,
        );
      }
      return response;
    }
    ```

=== "Java"

    ```java
    /** One client serves every request; it is safe to share. */
    static final HttpClient CLIENT = HttpClient.newBuilder()
            .connectTimeout(Duration.ofSeconds(30))
            .build();
    
    /**
     * Sends a request and returns the response with its whole body. The
     * request timeout stops applying once the headers arrive, so a server
     * that stalls part of the way through the body would hang send(); this
     * applies the same timeout to the whole exchange instead.
     */
    static HttpResponse<String> send(HttpRequest request)
            throws IOException, InterruptedException {
        Duration timeout = request.timeout().orElseThrow();
        CompletableFuture<HttpResponse<String>> pending =
                CLIENT.sendAsync(request, HttpResponse.BodyHandlers.ofString());
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
    
    /** Converts between JSON text and Java objects. */
    static final ObjectMapper JSON = new ObjectMapper();
    
    /**
     * Sends a request to the API and returns the response. The token and
     * the body may be null. A request that the server rejects throws an
     * error that includes the message from the server.
     */
    static HttpResponse<String> api(String method, String baseUrl,
            String path, String token, Object body)
            throws IOException, InterruptedException {
        HttpRequest.Builder request = HttpRequest
                .newBuilder(URI.create(baseUrl + "/api/v1" + path))
                .timeout(Duration.ofSeconds(30));
        if (token != null) {
            request.header("Authorization", "Bearer " + token);
        }
        HttpRequest.BodyPublisher content = HttpRequest.BodyPublishers.noBody();
        if (body != null) {
            request.header("Content-Type", "application/json");
            content = HttpRequest.BodyPublishers.ofString(
                    JSON.writeValueAsString(body));
        }
    
        HttpResponse<String> response = send(request.method(method, content).build());
        if (response.statusCode() >= 400) {
            throw new IOException(method + " " + path
                    + " failed with status " + response.statusCode() + ": "
                    + response.body().strip());
        }
        return response;
    }
    
    /** Sends a request to the API and returns the JSON reply. */
    static JsonNode apiJson(String method, String baseUrl, String path,
            String token, Object body)
            throws IOException, InterruptedException {
        return JSON.readTree(api(method, baseUrl, path, token, body).body());
    }
    ```

=== "C#"

    ```csharp
    // One client serves every request, with a timeout for each. The handler
    // keeps no cookies, so the session token goes only where the program
    // sends it.
    var http = new HttpClient(new SocketsHttpHandler { UseCookies = false })
    {
        Timeout = TimeSpan.FromSeconds(30),
    };
    
    // Sends a request to the API and returns the response, which the caller
    // must dispose of. A request that the server rejects throws an error that
    // includes the message from the server.
    async Task<HttpResponseMessage> Api(string method, string baseUrl,
        string path, string? token = null, object? body = null)
    {
        using var request = new HttpRequestMessage(
            new HttpMethod(method), $"{baseUrl}/api/v1{path}");
        if (token is not null)
        {
            request.Headers.Authorization =
                new AuthenticationHeaderValue("Bearer", token);
        }
        if (body is not null)
        {
            request.Content = JsonContent.Create(body);
        }
    
        var response = await http.SendAsync(request);
        var code = (int)response.StatusCode;
        if (code >= 400)
        {
            var text = (await response.Content.ReadAsStringAsync()).Trim();
            response.Dispose();
            throw new HttpRequestException(
                $"{method} {path} failed with status {code}: {text}");
        }
        return response;
    }
    
    // Sends a request to the API and returns the JSON reply.
    async Task<JsonNode> ApiJson(string method, string baseUrl, string path,
        string? token = null, object? body = null)
    {
        using var response = await Api(method, baseUrl, path, token, body);
        return JsonNode.Parse(await response.Content.ReadAsStringAsync())
            ?? throw new InvalidOperationException(
                $"{method} {path} returned no JSON");
    }
    ```

=== "Go"

    ```go
    // client gives every request a timeout; the default client has none.
    var client = &http.Client{Timeout: 30 * time.Second}
    
    // api sends a request to the API and returns the response, which the caller
    // must close. A request that the server rejects returns an error that
    // includes the message from the server.
    func api(method, baseURL, path, token string, body any) (*http.Response, error) {
    	var reader io.Reader
    	if body != nil {
    		encoded, err := json.Marshal(body)
    		if err != nil {
    			return nil, err
    		}
    		reader = bytes.NewReader(encoded)
    	}
    
    	req, err := http.NewRequest(method, baseURL+"/api/v1"+path, reader)
    	if err != nil {
    		return nil, err
    	}
    	if body != nil {
    		req.Header.Set("Content-Type", "application/json")
    	}
    	if token != "" {
    		req.Header.Set("Authorization", "Bearer "+token)
    	}
    
    	resp, err := client.Do(req)
    	if err != nil {
    		return nil, err
    	}
    	if resp.StatusCode >= 400 {
    		defer resp.Body.Close()
    		text, _ := io.ReadAll(resp.Body)
    		return nil, fmt.Errorf("%s %s failed with status %d: %s",
    			method, path, resp.StatusCode, strings.TrimSpace(string(text)))
    	}
    	return resp, nil
    }
    
    // apiJSON sends a request and decodes the JSON reply into out, if given.
    func apiJSON(method, baseURL, path, token string, body, out any) error {
    	resp, err := api(method, baseURL, path, token, body)
    	if err != nil {
    		return err
    	}
    	defer resp.Body.Close()
    	if out == nil {
    		return nil
    	}
    	return json.NewDecoder(resp.Body).Decode(out)
    }
    
    ```

=== "Rust"

    ```rust
    /// One client serves every request, with a timeout for each; the client
    /// has none by default.
    static CLIENT: LazyLock<Client> = LazyLock::new(|| {
        Client::builder()
            .timeout(Duration::from_secs(30))
            .build()
            .expect("could not create the HTTP client")
    });
    
    /// Sends a request to the API and returns the response. A request that the
    /// server rejects returns an error that includes the message from the
    /// server.
    fn api(
        method: Method,
        base_url: &str,
        path: &str,
        token: Option<&str>,
        body: Option<&Value>,
    ) -> Result<Response> {
        let mut request = CLIENT.request(method.clone(), format!("{base_url}/api/v1{path}"));
        if let Some(token) = token {
            request = request.bearer_auth(token);
        }
        if let Some(body) = body {
            request = request.json(body);
        }
    
        let response = request.send()?;
        let status = response.status().as_u16();
        if status >= 400 {
            let text = response.text()?;
            return Err(format!(
                "{method} {path} failed with status {status}: {}",
                text.trim()
            )
            .into());
        }
        Ok(response)
    }
    ```

=== "Ruby"

    ```ruby
    # Sends a request to the API and returns the response. The body, if given,
    # is sent as JSON. A request that the server rejects raises an error that
    # includes the message from the server.
    def api(method, base_url, path, token = nil, body = nil)
      uri = URI("#{base_url}/api/v1#{path}")
      headers = {}
      headers["Authorization"] = "Bearer #{token}" if token
      headers["Content-Type"] = "application/json" if body
    
      # Net::HTTP has no overall timeout, so limit both the connection and
      # each read.
      response = Net::HTTP.start(uri.host, uri.port,
                                 use_ssl: uri.scheme == "https",
                                 open_timeout: 30, read_timeout: 30) do |http|
        http.send_request(method, uri.request_uri, body&.to_json, headers)
      end
      if response.code.to_i >= 400
        raise "#{method} #{path} failed with status #{response.code}: " \
              "#{response.body.to_s.strip}"
      end
      response
    end
    ```

=== "curl"

    ```bash
    # Sends an authenticated request and prints the JSON reply:
    # api METHOD PATH TOKEN [curl options]. With --fail-with-body, a request
    # that the server rejects leaves the server's error message in the reply,
    # and the function prints it to standard error.
    # The token goes to curl in a header file that bash supplies through a pipe,
    # so that it never appears in the arguments of the curl process, which other
    # users can read in the process list.
    api() {
        local method="$1" path="$2" token="$3"
        shift 3
        local response
        response=$(curl --silent --show-error --fail-with-body \
            --connect-timeout 10 --max-time 30 \
            --request "$method" \
            --header @<(printf 'Authorization: Bearer %s\n' "$token") \
            "$@" "$WORKBENCH_URL/api/v1$path") || {
            echo "$method $path failed: $response" >&2
            return 1
        }
        printf '%s' "$response"
    }
    ```

## Logging In

The Workbench accepts only a session token, not an API token, for requests that
create, change, or delete a connection. The program sends the user name and the
password to `POST /api/v1/auth/login`, and reads the session token from the
`session_token` cookie in the reply. The following tabs show how each program
logs in:

=== "Python"

    ```python
    def login(base_url: str, username: str, password: str) -> str:
        """Logs in and returns the session token.
    
        The server returns the token in a session_token cookie, not in the
        body of the reply.
        """
        response = api("POST", base_url, "/auth/login",
                       json={"username": username, "password": password})
        token = response.cookies.get("session_token")
        if not token:
            raise RuntimeError("The login reply had no session_token cookie")
        return token
    ```

=== "TypeScript"

    ```typescript
    // Logs in and returns the session token. The server returns the token in a
    // session_token cookie, not in the body of the reply.
    async function login(
      baseUrl: string,
      username: string,
      password: string,
    ): Promise<string> {
      const response = await api("POST", baseUrl, "/auth/login", undefined, {
        username,
        password,
      });
      for (const cookie of response.headers.getSetCookie()) {
        const match = /^session_token=([^;]*)/.exec(cookie);
        if (match) return match[1];
      }
      throw new Error("The login reply had no session_token cookie");
    }
    ```

=== "Java"

    ```java
    /** Matches the session_token cookie in a Set-Cookie header. */
    static final Pattern SESSION_COOKIE =
            Pattern.compile("^session_token=([^;]*)");
    
    /**
     * Logs in and returns the session token. The server returns the token
     * in a session_token cookie, not in the body of the reply.
     */
    static String login(String baseUrl, String username, String password)
            throws IOException, InterruptedException {
        HttpResponse<String> response = api("POST", baseUrl, "/auth/login",
                null, Map.of("username", username, "password", password));
        for (String cookie : response.headers().allValues("Set-Cookie")) {
            Matcher match = SESSION_COOKIE.matcher(cookie);
            if (match.find()) {
                return match.group(1);
            }
        }
        throw new IOException("The login reply had no session_token cookie");
    }
    ```

=== "C#"

    ```csharp
    // Logs in and returns the session token. The server returns the token in a
    // session_token cookie, not in the body of the reply.
    async Task<string> Login(string baseUrl, string username, string password)
    {
        using var response = await Api("POST", baseUrl, "/auth/login",
            body: new { username, password });
        if (response.Headers.TryGetValues("Set-Cookie", out var cookies))
        {
            foreach (var cookie in cookies)
            {
                var match = Regex.Match(cookie, "^session_token=([^;]*)");
                if (match.Success)
                {
                    return match.Groups[1].Value;
                }
            }
        }
        throw new InvalidOperationException(
            "The login reply had no session_token cookie");
    }
    ```

=== "Go"

    ```go
    // login logs in and returns the session token. The server returns the token
    // in a session_token cookie, not in the body of the reply.
    func login(baseURL, username, password string) (string, error) {
    	resp, err := api("POST", baseURL, "/auth/login", "", map[string]string{
    		"username": username,
    		"password": password,
    	})
    	if err != nil {
    		return "", err
    	}
    	defer resp.Body.Close()
    
    	for _, cookie := range resp.Cookies() {
    		if cookie.Name == "session_token" {
    			return cookie.Value, nil
    		}
    	}
    	return "", errors.New("the login reply had no session_token cookie")
    }
    
    ```

=== "Rust"

    ```rust
    /// Logs in and returns the session token. The server returns the token in
    /// a session_token cookie, not in the body of the reply.
    fn login(base_url: &str, username: &str, password: &str) -> Result<String> {
        let body = json!({ "username": username, "password": password });
        let response = api(Method::POST, base_url, "/auth/login", None, Some(&body))?;
        for cookie in response.headers().get_all("set-cookie") {
            if let Some(rest) = cookie.to_str()?.strip_prefix("session_token=") {
                // The value runs up to the first attribute, if there is one.
                let value = rest.split(';').next().unwrap_or_default();
                return Ok(value.to_string());
            }
        }
        Err("the login reply had no session_token cookie".into())
    }
    ```

=== "Ruby"

    ```ruby
    # Logs in and returns the session token. The server returns the token in a
    # session_token cookie, not in the body of the reply.
    def login(base_url, username, password)
      response = api("POST", base_url, "/auth/login", nil,
                     { username: username, password: password })
      (response.get_fields("set-cookie") || []).each do |cookie|
        match = /\Asession_token=([^;]*)/.match(cookie)
        return match[1] if match
      end
      raise "The login reply had no session_token cookie"
    end
    ```

=== "curl"

    ```bash
    # Logs in and prints the session token. The server returns the token in a
    # session_token cookie, so the request includes the response headers.
    login() {
        local response
        # jq reads the credentials from its environment, and curl reads the
        # request from standard input, so that neither the password nor the
        # request body appears in a process list.
        response=$(jq -n '{username: env.WORKBENCH_USERNAME,
                           password: env.WORKBENCH_PASSWORD}' |
            curl --silent --show-error --fail-with-body --include \
                 --connect-timeout 10 --max-time 30 \
                 --request POST \
                 --header 'Content-Type: application/json' \
                 --data @- \
                 "$WORKBENCH_URL/api/v1/auth/login") || {
            echo "Login failed: $response" >&2
            return 1
        }
    
        # Header lines end in a carriage return, which tr removes.
        local token
        token=$(printf '%s' "$response" | tr -d '\r' |
            sed -n 's/^[Ss]et-[Cc]ookie: session_token=\([^;]*\).*/\1/p')
        if [[ -z "$token" ]]; then
            echo "The login reply had no session_token cookie" >&2
            return 1
        fi
        printf '%s' "$token"
    }
    ```

## Reading the Existing Connection

The new connection needs the host, the port, the database, and the user of the
server to monitor. The program reads them from the existing connection with
`GET /api/v1/connections/{id}`, so the example works against any server that
the Workbench already monitors. The following tabs show how each program reads
the connection:

=== "Python"

    ```python
    def get_connection(base_url: str, session: str, connection_id: str) -> dict:
        """Returns the details of an existing connection, which the program
        uses as the address of the server to register."""
        return api("GET", base_url, f"/connections/{connection_id}",
                   session).json()
    ```

=== "TypeScript"

    ```typescript
    interface Connection {
      id: number;
      name: string;
      host: string;
      port: number;
      database_name: string;
      username: string;
      ssl_mode?: string;
      is_monitored: boolean;
    }
    
    // Returns the details of an existing connection, which the program uses as
    // the address of the server to register.
    async function getConnection(
      baseUrl: string,
      session: string,
      connectionId: string,
    ): Promise<Connection> {
      const response = await api(
        "GET",
        baseUrl,
        `/connections/${connectionId}`,
        session,
      );
      return (await response.json()) as Connection;
    }
    ```

=== "Java"

    ```java
    /**
     * Returns the details of an existing connection, which the program
     * uses as the address of the server to register.
     */
    static JsonNode getConnection(String baseUrl, String session,
            String connectionId) throws IOException, InterruptedException {
        return apiJson("GET", baseUrl, "/connections/" + connectionId,
                session, null);
    }
    ```

=== "C#"

    ```csharp
    // Returns the details of an existing connection, which the program uses
    // as the address of the server to register.
    async Task<JsonNode> GetConnection(string baseUrl, string session,
        string connectionId) =>
        await ApiJson("GET", baseUrl, $"/connections/{connectionId}", session);
    ```

=== "Go"

    ```go
    // connection is the part of a connection that the program needs.
    type connection struct {
    	ID           int64  `json:"id"`
    	Name         string `json:"name"`
    	Host         string `json:"host"`
    	Port         int    `json:"port"`
    	DatabaseName string `json:"database_name"`
    	Username     string `json:"username"`
    	SSLMode      string `json:"ssl_mode"`
    	IsMonitored  bool   `json:"is_monitored"`
    }
    
    // getConnection returns the details of an existing connection, which the
    // program uses as the address of the server to register.
    func getConnection(baseURL, session, id string) (connection, error) {
    	var c connection
    	err := apiJSON("GET", baseURL, "/connections/"+id, session, nil, &c)
    	return c, err
    }
    
    ```

=== "Rust"

    ```rust
    /// Returns the details of an existing connection, which the program uses
    /// as the address of the server to register.
    fn get_connection(base_url: &str, session: &str, connection_id: &str) -> Result<Value> {
        let path = format!("/connections/{connection_id}");
        Ok(api(Method::GET, base_url, &path, Some(session), None)?.json()?)
    }
    ```

=== "Ruby"

    ```ruby
    # Returns the details of an existing connection, which the program uses as
    # the address of the server to register.
    def get_connection(base_url, session, connection_id)
      JSON.parse(api("GET", base_url, "/connections/#{connection_id}",
                     session).body)
    end
    ```

=== "curl"

    ```bash
    # Prints the details of an existing connection, which the script uses as
    # the address of the server to register.
    get_connection() {
        local session="$1" connection_id="$2"
        api GET "/connections/$connection_id" "$session"
    }
    ```

## Registering the Server

The program registers the server with `POST /api/v1/connections`. The request
copies the address from the existing connection, and adds a name, a
description, the password, and two flags: `is_monitored` makes the collector
monitor the server, and `is_shared` set to `false` does not share the
connection with other users. The Workbench 1.0.0 server rejects a request
without a description. The reply contains the ID of the new connection. The
following tabs show how each program registers the server:

=== "Python"

    ```python
    def register_server(base_url: str, session: str, name: str, template: dict,
                        password: str) -> int:
        """Registers a server and returns the ID of the new connection.
    
        The address comes from an existing connection. The request must
        include a password, and a description, which the server needs in
        version 1.0.0.
        """
        created = api("POST", base_url, "/connections", session, json={
            "name": name,
            "description": "Registered by the cookbook",
            "host": template["host"],
            "port": template["port"],
            "database_name": template["database_name"],
            "username": template["username"],
            "ssl_mode": template.get("ssl_mode"),
            "password": password,
            "is_monitored": True,
            "is_shared": False,
        }).json()
        return created["id"]
    ```

=== "TypeScript"

    ```typescript
    // Registers a server and returns the ID of the new connection. The address
    // comes from an existing connection. The request must include a password,
    // and a description, which the server needs in version 1.0.0.
    async function registerServer(
      baseUrl: string,
      session: string,
      name: string,
      template: Connection,
      password: string,
    ): Promise<number> {
      const response = await api("POST", baseUrl, "/connections", session, {
        name,
        description: "Registered by the cookbook",
        host: template.host,
        port: template.port,
        database_name: template.database_name,
        username: template.username,
        ssl_mode: template.ssl_mode,
        password,
        is_monitored: true,
        is_shared: false,
      });
      return ((await response.json()) as Connection).id;
    }
    ```

=== "Java"

    ```java
    /**
     * Registers a server and returns the ID of the new connection. The
     * address comes from an existing connection. The request must include
     * a password, and a description, which the server needs in version
     * 1.0.0.
     */
    static long registerServer(String baseUrl, String session, String name,
            JsonNode template, String password)
            throws IOException, InterruptedException {
        ObjectNode body = JSON.createObjectNode()
                .put("name", name)
                .put("description", "Registered by the cookbook");
        // Copy the address from the existing connection; set() writes a
        // JSON null for a field that the connection lacks.
        for (String field : new String[] {
                "host", "port", "database_name", "username", "ssl_mode"}) {
            body.set(field, template.get(field));
        }
        body.put("password", password)
                .put("is_monitored", true)
                .put("is_shared", false);
    
        JsonNode created = apiJson("POST", baseUrl, "/connections", session,
                body);
        return created.get("id").asLong();
    }
    ```

=== "C#"

    ```csharp
    // Registers a server and returns the ID of the new connection. The address
    // comes from an existing connection. The request must include a password,
    // and a description, which the server needs in version 1.0.0.
    async Task<long> RegisterServer(string baseUrl, string session,
        string name, JsonNode template, string password)
    {
        // A JSON node belongs to one parent at a time, so the program copies
        // each field that it takes from the existing connection.
        var body = new JsonObject
        {
            ["name"] = name,
            ["description"] = "Registered by the cookbook",
            ["host"] = template["host"]?.DeepClone(),
            ["port"] = template["port"]?.DeepClone(),
            ["database_name"] = template["database_name"]?.DeepClone(),
            ["username"] = template["username"]?.DeepClone(),
            ["ssl_mode"] = template["ssl_mode"]?.DeepClone(),
            ["password"] = password,
            ["is_monitored"] = true,
            ["is_shared"] = false,
        };
        var created = await ApiJson("POST", baseUrl, "/connections", session,
            body);
        return created["id"]!.GetValue<long>();
    }
    ```

=== "Go"

    ```go
    // registerServer registers a server and returns the ID of the new
    // connection. The address comes from an existing connection. The request
    // must include a password, and a description, which the server needs in
    // version 1.0.0.
    func registerServer(baseURL, session, name string, template connection, password string) (int64, error) {
    	var created connection
    	err := apiJSON("POST", baseURL, "/connections", session, map[string]any{
    		"name":          name,
    		"description":   "Registered by the cookbook",
    		"host":          template.Host,
    		"port":          template.Port,
    		"database_name": template.DatabaseName,
    		"username":      template.Username,
    		"ssl_mode":      template.SSLMode,
    		"password":      password,
    		"is_monitored":  true,
    		"is_shared":     false,
    	}, &created)
    	return created.ID, err
    }
    
    ```

=== "Rust"

    ```rust
    /// Registers a server and returns the ID of the new connection. The
    /// address comes from an existing connection. The request must include a
    /// password, and a description, which the server needs in version 1.0.0.
    fn register_server(
        base_url: &str,
        session: &str,
        name: &str,
        template: &Value,
        password: &str,
    ) -> Result<i64> {
        // Indexing a missing field gives null rather than a panic.
        let body = json!({
            "name": name,
            "description": "Registered by the cookbook",
            "host": template["host"],
            "port": template["port"],
            "database_name": template["database_name"],
            "username": template["username"],
            "ssl_mode": template["ssl_mode"],
            "password": password,
            "is_monitored": true,
            "is_shared": false,
        });
        let created: Value = api(
            Method::POST,
            base_url,
            "/connections",
            Some(session),
            Some(&body),
        )?
        .json()?;
        Ok(created["id"]
            .as_i64()
            .ok_or("the reply had no connection ID")?)
    }
    ```

=== "Ruby"

    ```ruby
    # Registers a server and returns the ID of the new connection. The address
    # comes from an existing connection. The request must include a password,
    # and a description, which the server needs in version 1.0.0.
    def register_server(base_url, session, name, template, password)
      response = api("POST", base_url, "/connections", session, {
                       name: name,
                       description: "Registered by the cookbook",
                       host: template.fetch("host"),
                       port: template.fetch("port"),
                       database_name: template.fetch("database_name"),
                       username: template.fetch("username"),
                       ssl_mode: template["ssl_mode"],
                       password: password,
                       is_monitored: true,
                       is_shared: false
                     })
      JSON.parse(response.body).fetch("id")
    end
    ```

=== "curl"

    ```bash
    # Registers a server and prints the ID of the new connection. The address
    # comes from an existing connection, given as JSON in the third argument.
    register_server() {
        local session="$1" name="$2" template="$3"
        # The template's host, port, database, and user become the new
        # connection's. jq reads the password from its environment, which keeps
        # it off the command line, and the request sends a description, which
        # the server needs in version 1.0.0.
        SERVER_PASSWORD="$SERVER_PASSWORD" \
        jq --arg name "$name" \
           '{name: $name, description: "Registered by the cookbook",
             host, port, database_name, username, ssl_mode,
             password: env.SERVER_PASSWORD, is_monitored: true,
             is_shared: false}' \
           <<<"$template" |
            api POST /connections "$session" \
                --header 'Content-Type: application/json' --data @- |
            jq -r '.id'
    }
    ```

## Listing the Connections

The program lists the connections with `GET /api/v1/connections`, and looks for
the new connection by its name. The program runs this step twice: once to
confirm that the registration worked, and once after the delete to confirm that
the connection has gone. The following tabs show how each program finds a
connection in the list:

=== "Python"

    ```python
    def find_connection(base_url: str, session: str, name: str) -> dict | None:
        """Returns the named connection from the list, or None if the list has
        no such connection."""
        connections = api("GET", base_url, "/connections", session).json()
        return next((c for c in connections if c["name"] == name), None)
    ```

=== "TypeScript"

    ```typescript
    // Returns the named connection from the list, or undefined if the list has
    // no such connection.
    async function findConnection(
      baseUrl: string,
      session: string,
      name: string,
    ): Promise<Connection | undefined> {
      const response = await api("GET", baseUrl, "/connections", session);
      const connections = (await response.json()) as Connection[];
      return connections.find((c) => c.name === name);
    }
    ```

=== "Java"

    ```java
    /**
     * Returns the named connection from the list, or null if the list has
     * no such connection.
     */
    static JsonNode findConnection(String baseUrl, String session,
            String name) throws IOException, InterruptedException {
        for (JsonNode connection
                : apiJson("GET", baseUrl, "/connections", session, null)) {
            if (name.equals(connection.get("name").asString())) {
                return connection;
            }
        }
        return null;
    }
    ```

=== "C#"

    ```csharp
    // Returns the named connection from the list, or null if the list has no
    // such connection.
    async Task<JsonNode?> FindConnection(string baseUrl, string session,
        string name)
    {
        var connections = await ApiJson("GET", baseUrl, "/connections", session);
        return connections.AsArray().FirstOrDefault(
            c => c?["name"]?.GetValue<string>() == name);
    }
    ```

=== "Go"

    ```go
    // findConnection returns the named connection from the list, or nil if the
    // list has no such connection.
    func findConnection(baseURL, session, name string) (*connection, error) {
    	var connections []connection
    	if err := apiJSON("GET", baseURL, "/connections", session, nil, &connections); err != nil {
    		return nil, err
    	}
    	for i := range connections {
    		if connections[i].Name == name {
    			return &connections[i], nil
    		}
    	}
    	return nil, nil
    }
    
    ```

=== "Rust"

    ```rust
    /// Returns the named connection from the list, or None if the list has no
    /// such connection.
    fn find_connection(base_url: &str, session: &str, name: &str) -> Result<Option<Value>> {
        let connections: Vec<Value> =
            api(Method::GET, base_url, "/connections", Some(session), None)?.json()?;
        Ok(connections.into_iter().find(|c| c["name"] == name))
    }
    ```

=== "Ruby"

    ```ruby
    # Returns the named connection from the list, or nil if the list has no
    # such connection.
    def find_connection(base_url, session, name)
      connections = JSON.parse(api("GET", base_url, "/connections", session).body)
      connections.find { |c| c["name"] == name }
    end
    ```

=== "curl"

    ```bash
    # Prints the monitoring state of the named connection, or nothing if the
    # list has no such connection.
    find_connection() {
        local session="$1" name="$2"
        api GET /connections "$session" |
            jq -r --arg name "$name" \
               '.[] | select(.name == $name) | "monitored: \(.is_monitored)"'
    }
    ```

## Deleting the Connection

The program deletes the connection with `DELETE /api/v1/connections/{id}`,
using the ID from the reply to the create call. The following tabs show how
each program deletes the connection:

=== "Python"

    ```python
    def delete_connection(base_url: str, session: str,
                          connection_id: int) -> None:
        """Deletes a connection by its ID."""
        api("DELETE", base_url, f"/connections/{connection_id}", session)
    ```

=== "TypeScript"

    ```typescript
    // Deletes a connection by its ID.
    async function deleteConnection(
      baseUrl: string,
      session: string,
      connectionId: number,
    ): Promise<void> {
      await api("DELETE", baseUrl, `/connections/${connectionId}`, session);
    }
    ```

=== "Java"

    ```java
    /** Deletes a connection by its ID. */
    static void deleteConnection(String baseUrl, String session,
            long connectionId) throws IOException, InterruptedException {
        api("DELETE", baseUrl, "/connections/" + connectionId, session,
                null);
    }
    ```

=== "C#"

    ```csharp
    // Deletes a connection by its ID.
    async Task DeleteConnection(string baseUrl, string session,
        long connectionId)
    {
        using var response = await Api("DELETE", baseUrl,
            $"/connections/{connectionId}", session);
    }
    ```

=== "Go"

    ```go
    // deleteConnection deletes a connection by its ID.
    func deleteConnection(baseURL, session string, id int64) error {
    	return apiJSON("DELETE", baseURL, fmt.Sprintf("/connections/%d", id),
    		session, nil, nil)
    }
    
    ```

=== "Rust"

    ```rust
    /// Deletes a connection by its ID.
    fn delete_connection(base_url: &str, session: &str, connection_id: i64) -> Result<()> {
        let path = format!("/connections/{connection_id}");
        api(Method::DELETE, base_url, &path, Some(session), None)?;
        Ok(())
    }
    ```

=== "Ruby"

    ```ruby
    # Deletes a connection by its ID.
    def delete_connection(base_url, session, connection_id)
      api("DELETE", base_url, "/connections/#{connection_id}", session)
    end
    ```

=== "curl"

    ```bash
    # Deletes a connection by its ID.
    delete_connection() {
        local session="$1" connection_id="$2"
        api DELETE "/connections/$connection_id" "$session" >/dev/null
    }
    ```

## Cleaning Up After a Failure

The main part of each program deletes the connection on every path, so that a
failure after the registration does not leave a monitored server behind. The
Python program uses a `finally` block and the Ruby program an `ensure` block,
and the TypeScript program keeps the delete step in a variable that runs after
the `try` block. The Java and C# programs keep the connection's ID in a
variable that a `finally` block checks. The Go program returns
the delete step from its `run()` function to `main()`, the Rust program's
`run()` function records what to delete in a value that `main()` owns, and
the curl script uses an `EXIT` trap. Each program reports a failure on
`stderr` and exits with a non-zero status. The following tabs show the main
part of each program:

=== "Python"

    ```python
    def main() -> int:
        new_id = None
        status = 0
        try:
            config = settings()
            base_url = config["base_url"]
    
            session = login(base_url, config["username"], config["password"])
            template = get_connection(base_url, session, config["connection_id"])
    
            new_id = register_server(base_url, session, SERVER_NAME, template,
                                     config["server_password"])
            print(f"Registered the server '{SERVER_NAME}'")
    
            found = find_connection(base_url, session, SERVER_NAME)
            if found is None:
                raise RuntimeError("The new connection is missing from the list")
            monitored = str(found["is_monitored"]).lower()
            print(f"Found '{SERVER_NAME}' in the list (monitored: {monitored})")
    
            delete_connection(base_url, session, new_id)
            new_id = None
            print("Deleted the connection")
    
            if find_connection(base_url, session, SERVER_NAME) is not None:
                raise RuntimeError("The connection is still in the list")
            print("The connection is no longer in the list")
        # httpx.HTTPError covers failures to connect, and RuntimeError covers
        # replies that the server rejected or that lacked what we need.
        except (httpx.HTTPError, RuntimeError) as e:
            print(f"Error: {e}", file=sys.stderr)
            status = 1
        finally:
            # Delete the connection whether or not a later step failed, so
            # that a failed run does not leave a server registered. A return
            # statement in a finally block would hide an exception that is
            # still in flight, so this block sets the exit status instead.
            if new_id is not None:
                try:
                    delete_connection(base_url, session, new_id)
                except (httpx.HTTPError, RuntimeError) as e:
                    print(f"Error: could not delete the connection: {e}",
                          file=sys.stderr)
                    status = 1
    
        return status
    
    
    if __name__ == "__main__":
        sys.exit(main())
    ```

=== "TypeScript"

    ```typescript
    async function main(): Promise<number> {
      let exitCode = 0;
      let cleanup: (() => Promise<void>) | undefined;
      try {
        const s = settings();
    
        const session = await login(s.baseUrl, s.username, s.password);
        const template = await getConnection(s.baseUrl, session, s.connectionId);
    
        const newId = await registerServer(
          s.baseUrl,
          session,
          SERVER_NAME,
          template,
          s.serverPassword,
        );
        // Delete the connection whether or not a later step fails, so that a
        // failed run does not leave a server registered.
        cleanup = () => deleteConnection(s.baseUrl, session, newId);
        console.log(`Registered the server '${SERVER_NAME}'`);
    
        const found = await findConnection(s.baseUrl, session, SERVER_NAME);
        if (!found) throw new Error("The new connection is missing from the list");
        console.log(
          `Found '${SERVER_NAME}' in the list (monitored: ${found.is_monitored})`,
        );
    
        await cleanup();
        cleanup = undefined;
        console.log("Deleted the connection");
    
        if (await findConnection(s.baseUrl, session, SERVER_NAME)) {
          throw new Error("The connection is still in the list");
        }
        console.log("The connection is no longer in the list");
      } catch (err) {
        console.error(`Error: ${err instanceof Error ? err.message : err}`);
        exitCode = 1;
      }
    
      if (cleanup) {
        try {
          await cleanup();
        } catch (err) {
          console.error(
            `Error: could not delete the connection: ${
              err instanceof Error ? err.message : err
            }`,
          );
          exitCode = 1;
        }
      }
      return exitCode;
    }
    
    process.exitCode = await main();
    ```

=== "Java"

    ```java
    /**
     * Returns the message of an error. Some errors, such as a refused
     * connection, have no message, so their type stands in for one.
     */
    static String describe(Exception e) {
        return Objects.requireNonNullElse(e.getMessage(), e.toString());
    }
    
    public static void main(String[] args) {
        int status = 0;
        String baseUrl = null;
        String session = null;
        Long newId = null;
        try {
            Settings settings = settings();
            baseUrl = settings.baseUrl();
    
            session = login(baseUrl, settings.username(),
                    settings.password());
            JsonNode template = getConnection(baseUrl, session,
                    settings.connectionId());
    
            newId = registerServer(baseUrl, session, SERVER_NAME, template,
                    settings.serverPassword());
            System.out.println("Registered the server '" + SERVER_NAME + "'");
    
            JsonNode found = findConnection(baseUrl, session, SERVER_NAME);
            if (found == null) {
                throw new IOException(
                        "The new connection is missing from the list");
            }
            System.out.println("Found '" + SERVER_NAME
                    + "' in the list (monitored: "
                    + found.get("is_monitored").asBoolean() + ")");
    
            deleteConnection(baseUrl, session, newId);
            newId = null;
            System.out.println("Deleted the connection");
    
            if (findConnection(baseUrl, session, SERVER_NAME) != null) {
                throw new IOException("The connection is still in the list");
            }
            System.out.println("The connection is no longer in the list");
        // IOException covers failures to connect, replies that the server
        // rejected, and replies that lacked what we need; the client
        // throws InterruptedException if the thread is interrupted, and
        // Jackson throws JacksonException for a reply that is not JSON.
        } catch (IOException | InterruptedException | JacksonException e) {
            System.err.println("Error: " + describe(e));
            status = 1;
        } finally {
            // Delete the connection whether or not a later step failed, so
            // that a failed run does not leave a server registered. The
            // finally block also runs for an error that the catch does not
            // handle.
            if (newId != null) {
                try {
                    deleteConnection(baseUrl, session, newId);
                } catch (IOException | InterruptedException
                        | JacksonException e) {
                    System.err.println(
                            "Error: could not delete the connection: "
                            + describe(e));
                    status = 1;
                }
            }
        }
        System.exit(status);
    }
    ```

=== "C#"

    ```csharp
    var status = 0;
    var baseUrl = "";
    var session = "";
    long? newId = null;
    try
    {
        var settings = Settings();
        baseUrl = settings.BaseUrl;
    
        session = await Login(baseUrl, settings.Username, settings.Password);
        var template = await GetConnection(baseUrl, session,
            settings.ConnectionId);
    
        newId = await RegisterServer(baseUrl, session, ServerName, template,
            settings.ServerPassword);
        Console.WriteLine($"Registered the server '{ServerName}'");
    
        var found = await FindConnection(baseUrl, session, ServerName)
            ?? throw new InvalidOperationException(
                "The new connection is missing from the list");
        // A bool would print as True or False, so spell the flag out.
        var monitored = found["is_monitored"]!.GetValue<bool>() ? "true" : "false";
        Console.WriteLine(
            $"Found '{ServerName}' in the list (monitored: {monitored})");
    
        await DeleteConnection(baseUrl, session, newId.Value);
        newId = null;
        Console.WriteLine("Deleted the connection");
    
        if (await FindConnection(baseUrl, session, ServerName) is not null)
        {
            throw new InvalidOperationException(
                "The connection is still in the list");
        }
        Console.WriteLine("The connection is no longer in the list");
    }
    // HttpRequestException covers failures to connect and replies that the
    // server rejected, TaskCanceledException covers a request that timed out,
    // and the others cover replies that lacked what we need.
    catch (Exception e) when (e is HttpRequestException
        or TaskCanceledException or InvalidOperationException or JsonException)
    {
        Console.Error.WriteLine($"Error: {e.Message}");
        status = 1;
    }
    finally
    {
        // Delete the connection whether or not a later step failed, so that a
        // failed run does not leave a server registered. The finally block also
        // runs for an error that the catch does not handle.
        if (newId is not null)
        {
            try
            {
                await DeleteConnection(baseUrl, session, newId.Value);
            }
            catch (Exception e) when (e is HttpRequestException
                or TaskCanceledException)
            {
                Console.Error.WriteLine(
                    $"Error: could not delete the connection: {e.Message}");
                status = 1;
            }
        }
    }
    
    return status;
    ```

=== "Go"

    ```go
    // run does the work. It returns the cleanup that the caller must run if the
    // program has registered a server and not yet deleted it.
    func run(s settings) (cleanup func() error, err error) {
    	session, err := login(s.baseURL, s.username, s.password)
    	if err != nil {
    		return nil, err
    	}
    	template, err := getConnection(s.baseURL, session, s.connectionID)
    	if err != nil {
    		return nil, err
    	}
    
    	newID, err := registerServer(s.baseURL, session, serverName, template, s.serverPassword)
    	if err != nil {
    		return nil, err
    	}
    	// Return the cleanup before any later step can fail, so that a failed
    	// run does not leave a server registered.
    	cleanup = func() error { return deleteConnection(s.baseURL, session, newID) }
    	fmt.Printf("Registered the server '%s'\n", serverName)
    
    	found, err := findConnection(s.baseURL, session, serverName)
    	if err != nil {
    		return cleanup, err
    	}
    	if found == nil {
    		return cleanup, errors.New("the new connection is missing from the list")
    	}
    	fmt.Printf("Found '%s' in the list (monitored: %t)\n", serverName, found.IsMonitored)
    
    	if err := cleanup(); err != nil {
    		return cleanup, err
    	}
    	cleanup = nil
    	fmt.Println("Deleted the connection")
    
    	found, err = findConnection(s.baseURL, session, serverName)
    	if err != nil {
    		return nil, err
    	}
    	if found != nil {
    		return nil, errors.New("the connection is still in the list")
    	}
    	fmt.Println("The connection is no longer in the list")
    	return nil, nil
    }
    
    func main() {
    	s, err := loadSettings()
    	if err != nil {
    		fmt.Fprintln(os.Stderr, "Error:", err)
    		os.Exit(1)
    	}
    
    	failed := false
    	cleanup, err := run(s)
    	if err != nil {
    		fmt.Fprintln(os.Stderr, "Error:", err)
    		failed = true
    	}
    	if cleanup != nil {
    		if err := cleanup(); err != nil {
    			fmt.Fprintln(os.Stderr, "Error: could not delete the connection:", err)
    			failed = true
    		}
    	}
    	if failed {
    		os.Exit(1)
    	}
    }
    
    ```

=== "Rust"

    ```rust
    /// What the program must delete when it finishes: the new connection's
    /// ID, and the session token that has the right to delete it.
    struct Cleanup {
        session: String,
        connection_id: i64,
    }
    
    /// Does the work. Once it has registered the server, it records the new
    /// connection in cleanup, so that main deletes it even if a later step
    /// fails.
    fn run(s: &Settings, cleanup: &mut Option<Cleanup>) -> Result<()> {
        let session = login(&s.base_url, &s.username, &s.password)?;
        let template = get_connection(&s.base_url, &session, &s.connection_id)?;
    
        let new_id = register_server(
            &s.base_url,
            &session,
            SERVER_NAME,
            &template,
            &s.server_password,
        )?;
        *cleanup = Some(Cleanup {
            session: session.clone(),
            connection_id: new_id,
        });
        println!("Registered the server '{SERVER_NAME}'");
    
        let found = find_connection(&s.base_url, &session, SERVER_NAME)?
            .ok_or("the new connection is missing from the list")?;
        let monitored = found["is_monitored"]
            .as_bool()
            .ok_or("the connection had no monitored flag")?;
        println!("Found '{SERVER_NAME}' in the list (monitored: {monitored})");
    
        delete_connection(&s.base_url, &session, new_id)?;
        *cleanup = None;
        println!("Deleted the connection");
    
        if find_connection(&s.base_url, &session, SERVER_NAME)?.is_some() {
            return Err("the connection is still in the list".into());
        }
        println!("The connection is no longer in the list");
        Ok(())
    }
    
    /// Prints an error with the chain of underlying causes, because the
    /// top-level error is often generic ("error sending request").
    fn report(prefix: &str, e: &dyn Error) {
        eprintln!("{prefix}{e}");
        let mut cause = e.source();
        while let Some(c) = cause {
            eprintln!("  caused by: {c}");
            cause = c.source();
        }
    }
    
    fn main() -> ExitCode {
        let s = match settings() {
            Ok(s) => s,
            Err(e) => {
                report("Error: ", e.as_ref());
                return ExitCode::FAILURE;
            }
        };
    
        let mut status = ExitCode::SUCCESS;
        let mut cleanup = None;
        if let Err(e) = run(&s, &mut cleanup) {
            report("Error: ", e.as_ref());
            status = ExitCode::FAILURE;
        }
    
        // Delete the connection whether or not a later step failed, so that a
        // failed run does not leave a server registered.
        if let Some(c) = cleanup {
            if let Err(e) = delete_connection(&s.base_url, &c.session, c.connection_id) {
                report("Error: could not delete the connection: ", e.as_ref());
                status = ExitCode::FAILURE;
            }
        }
        status
    }
    ```

=== "Ruby"

    ```ruby
    def main
      new_id = nil
      status = 0
      begin
        config = settings
        base_url = config[:base_url]
    
        session = login(base_url, config[:username], config[:password])
        template = get_connection(base_url, session, config[:connection_id])
    
        new_id = register_server(base_url, session, SERVER_NAME, template,
                                 config[:server_password])
        puts "Registered the server '#{SERVER_NAME}'"
    
        found = find_connection(base_url, session, SERVER_NAME)
        raise "The new connection is missing from the list" if found.nil?
    
        puts "Found '#{SERVER_NAME}' in the list " \
             "(monitored: #{found.fetch('is_monitored')})"
    
        delete_connection(base_url, session, new_id)
        new_id = nil
        puts "Deleted the connection"
    
        unless find_connection(base_url, session, SERVER_NAME).nil?
          raise "The connection is still in the list"
        end
    
        puts "The connection is no longer in the list"
      # Net::HTTP raises errors of many classes, such as SystemCallError for a
      # refused connection and Net::OpenTimeout for a timeout, and the program
      # raises RuntimeError for replies that the server rejected or that lacked
      # what we need, so this catches StandardError, their common ancestor.
      rescue StandardError => e
        warn "Error: #{e.message}"
        status = 1
      ensure
        # Delete the connection whether or not a later step failed, so that a
        # failed run does not leave a server registered.
        if new_id
          begin
            delete_connection(base_url, session, new_id)
          rescue StandardError => e
            warn "Error: could not delete the connection: #{e.message}"
            status = 1
          end
        end
      end
      status
    end
    
    exit main
    ```

=== "curl"

    ```bash
    # These variables are global, because the EXIT trap runs after main returns.
    session=""
    new_id=""
    
    cleanup() {
        local status=$?
        # Delete the connection when the script ends, even if a later step
        # failed, so that a failed run does not leave a server registered.
        # Report a delete that fails, and make the exit status non-zero.
        if [[ -n "$new_id" ]]; then
            delete_connection "$session" "$new_id" || {
                echo "Error: could not delete the connection $new_id" >&2
                status=1
            }
        fi
        exit "$status"
    }
    
    main() {
        session=$(login)
        local template found
        template=$(get_connection "$session" "$WORKBENCH_CONNECTION_ID")
    
        new_id=$(register_server "$session" "$SERVER_NAME" "$template")
        echo "Registered the server '$SERVER_NAME'"
    
        found=$(find_connection "$session" "$SERVER_NAME")
        if [[ -z "$found" ]]; then
            echo "The new connection is missing from the list" >&2
            return 1
        fi
        echo "Found '$SERVER_NAME' in the list ($found)"
    
        delete_connection "$session" "$new_id"
        new_id=""
        echo "Deleted the connection"
    
        if [[ -n "$(find_connection "$session" "$SERVER_NAME")" ]]; then
            echo "The connection is still in the list" >&2
            return 1
        fi
        echo "The connection is no longer in the list"
    }
    
    trap cleanup EXIT
    main
    ```

## Running the Example

The complete project for each language is available in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/ai_dba_workbench/register_server).
Set `WORKBENCH_URL`, `WORKBENCH_USERNAME`, `WORKBENCH_PASSWORD`, and
`WORKBENCH_CONNECTION_ID` for your server, and then run the command for your
language from the corresponding project directory. The following tabs show the
commands that build and run each example:

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
    Registering a server to monitor with the AI DBA Workbench API, using httpx.
    
    Copyright (c) 2026, pgEdge, Inc.
    This code is released under the PostgreSQL License.
    """
    
    import os
    import sys
    
    import httpx
    
    
    SERVER_NAME = "cookbook-register-server"
    
    
    def settings() -> dict:
        """Reads the settings from the environment.
    
        The or operator treats an empty variable as unset.
        """
        username = os.environ.get("WORKBENCH_USERNAME") or ""
        password = os.environ.get("WORKBENCH_PASSWORD") or ""
        connection_id = os.environ.get("WORKBENCH_CONNECTION_ID") or ""
        if not (username and password and connection_id):
            raise RuntimeError(
                "WORKBENCH_USERNAME, WORKBENCH_PASSWORD, and "
                "WORKBENCH_CONNECTION_ID must be set"
            )
        return {
            "base_url": (
                os.environ.get("WORKBENCH_URL") or "http://localhost:8080"
            ).rstrip("/"),
            "username": username,
            "password": password,
            "connection_id": connection_id,
            # The Workbench refuses to register a server without a password,
            # even one that uses trust authentication, so fall back to a
            # placeholder.
            "server_password": (
                os.environ.get("PGPASSWORD") or "unused-with-trust-authentication"
            ),
        }
    
    
    def api(method: str, base_url: str, path: str, token: str | None = None,
            **kwargs) -> httpx.Response:
        """Sends a request to the API and returns the response.
    
        A request that the server rejects raises an error that includes the
        message from the server, which raise_for_status alone would leave out.
        """
        headers = {"Authorization": f"Bearer {token}"} if token else {}
        response = httpx.request(
            method, f"{base_url}/api/v1{path}", headers=headers, timeout=30,
            **kwargs,
        )
        if response.is_error:
            raise RuntimeError(
                f"{method} {path} failed with status {response.status_code}: "
                f"{response.text.strip()}"
            )
        return response
    
    
    def login(base_url: str, username: str, password: str) -> str:
        """Logs in and returns the session token.
    
        The server returns the token in a session_token cookie, not in the
        body of the reply.
        """
        response = api("POST", base_url, "/auth/login",
                       json={"username": username, "password": password})
        token = response.cookies.get("session_token")
        if not token:
            raise RuntimeError("The login reply had no session_token cookie")
        return token
    
    
    def get_connection(base_url: str, session: str, connection_id: str) -> dict:
        """Returns the details of an existing connection, which the program
        uses as the address of the server to register."""
        return api("GET", base_url, f"/connections/{connection_id}",
                   session).json()
    
    
    def register_server(base_url: str, session: str, name: str, template: dict,
                        password: str) -> int:
        """Registers a server and returns the ID of the new connection.
    
        The address comes from an existing connection. The request must
        include a password, and a description, which the server needs in
        version 1.0.0.
        """
        created = api("POST", base_url, "/connections", session, json={
            "name": name,
            "description": "Registered by the cookbook",
            "host": template["host"],
            "port": template["port"],
            "database_name": template["database_name"],
            "username": template["username"],
            "ssl_mode": template.get("ssl_mode"),
            "password": password,
            "is_monitored": True,
            "is_shared": False,
        }).json()
        return created["id"]
    
    
    def find_connection(base_url: str, session: str, name: str) -> dict | None:
        """Returns the named connection from the list, or None if the list has
        no such connection."""
        connections = api("GET", base_url, "/connections", session).json()
        return next((c for c in connections if c["name"] == name), None)
    
    
    def delete_connection(base_url: str, session: str,
                          connection_id: int) -> None:
        """Deletes a connection by its ID."""
        api("DELETE", base_url, f"/connections/{connection_id}", session)
    
    
    def main() -> int:
        new_id = None
        status = 0
        try:
            config = settings()
            base_url = config["base_url"]
    
            session = login(base_url, config["username"], config["password"])
            template = get_connection(base_url, session, config["connection_id"])
    
            new_id = register_server(base_url, session, SERVER_NAME, template,
                                     config["server_password"])
            print(f"Registered the server '{SERVER_NAME}'")
    
            found = find_connection(base_url, session, SERVER_NAME)
            if found is None:
                raise RuntimeError("The new connection is missing from the list")
            monitored = str(found["is_monitored"]).lower()
            print(f"Found '{SERVER_NAME}' in the list (monitored: {monitored})")
    
            delete_connection(base_url, session, new_id)
            new_id = None
            print("Deleted the connection")
    
            if find_connection(base_url, session, SERVER_NAME) is not None:
                raise RuntimeError("The connection is still in the list")
            print("The connection is no longer in the list")
        # httpx.HTTPError covers failures to connect, and RuntimeError covers
        # replies that the server rejected or that lacked what we need.
        except (httpx.HTTPError, RuntimeError) as e:
            print(f"Error: {e}", file=sys.stderr)
            status = 1
        finally:
            # Delete the connection whether or not a later step failed, so
            # that a failed run does not leave a server registered. A return
            # statement in a finally block would hide an exception that is
            # still in flight, so this block sets the exit status instead.
            if new_id is not None:
                try:
                    delete_connection(base_url, session, new_id)
                except (httpx.HTTPError, RuntimeError) as e:
                    print(f"Error: could not delete the connection: {e}",
                          file=sys.stderr)
                    status = 1
    
        return status
    
    
    if __name__ == "__main__":
        sys.exit(main())
    
    ```

=== "TypeScript"

    ```typescript
    /*
     * Ellie's Postgres Cookbook
     * Registering a server to monitor with the AI DBA Workbench API, using the
     * built-in fetch.
     *
     * Copyright (c) 2026, pgEdge, Inc.
     * This code is released under the PostgreSQL License.
     */
    
    // The program needs no imports: fetch and process are built in to Node.js.
    
    const SERVER_NAME = "cookbook-register-server";
    
    interface Settings {
      baseUrl: string;
      username: string;
      password: string;
      connectionId: string;
      serverPassword: string;
    }
    
    // Read the settings from the environment. The || operator, unlike ??, also
    // treats an empty variable as unset.
    function settings(): Settings {
      const username = process.env.WORKBENCH_USERNAME || "";
      const password = process.env.WORKBENCH_PASSWORD || "";
      const connectionId = process.env.WORKBENCH_CONNECTION_ID || "";
      if (!username || !password || !connectionId) {
        throw new Error(
          "WORKBENCH_USERNAME, WORKBENCH_PASSWORD, and WORKBENCH_CONNECTION_ID " +
            "must be set",
        );
      }
      const baseUrl = process.env.WORKBENCH_URL || "http://localhost:8080";
      return {
        baseUrl: baseUrl.replace(/\/+$/, ""),
        username,
        password,
        connectionId,
        // The Workbench refuses to register a server without a password, even
        // one that uses trust authentication, so fall back to a placeholder.
        serverPassword:
          process.env.PGPASSWORD || "unused-with-trust-authentication",
      };
    }
    
    // Sends a request to the API and returns the response. A request that the
    // server rejects throws an error that includes the message from the server.
    async function api(
      method: string,
      baseUrl: string,
      path: string,
      token?: string,
      body?: unknown,
    ): Promise<Response> {
      const headers: Record<string, string> = {};
      if (token) headers["Authorization"] = `Bearer ${token}`;
      if (body !== undefined) headers["Content-Type"] = "application/json";
    
      const response = await fetch(`${baseUrl}/api/v1${path}`, {
        method,
        headers,
        body: body === undefined ? undefined : JSON.stringify(body),
        signal: AbortSignal.timeout(30_000),
      });
      if (!response.ok) {
        const text = (await response.text()).trim();
        throw new Error(
          `${method} ${path} failed with status ${response.status}: ${text}`,
        );
      }
      return response;
    }
    
    // Logs in and returns the session token. The server returns the token in a
    // session_token cookie, not in the body of the reply.
    async function login(
      baseUrl: string,
      username: string,
      password: string,
    ): Promise<string> {
      const response = await api("POST", baseUrl, "/auth/login", undefined, {
        username,
        password,
      });
      for (const cookie of response.headers.getSetCookie()) {
        const match = /^session_token=([^;]*)/.exec(cookie);
        if (match) return match[1];
      }
      throw new Error("The login reply had no session_token cookie");
    }
    
    interface Connection {
      id: number;
      name: string;
      host: string;
      port: number;
      database_name: string;
      username: string;
      ssl_mode?: string;
      is_monitored: boolean;
    }
    
    // Returns the details of an existing connection, which the program uses as
    // the address of the server to register.
    async function getConnection(
      baseUrl: string,
      session: string,
      connectionId: string,
    ): Promise<Connection> {
      const response = await api(
        "GET",
        baseUrl,
        `/connections/${connectionId}`,
        session,
      );
      return (await response.json()) as Connection;
    }
    
    // Registers a server and returns the ID of the new connection. The address
    // comes from an existing connection. The request must include a password,
    // and a description, which the server needs in version 1.0.0.
    async function registerServer(
      baseUrl: string,
      session: string,
      name: string,
      template: Connection,
      password: string,
    ): Promise<number> {
      const response = await api("POST", baseUrl, "/connections", session, {
        name,
        description: "Registered by the cookbook",
        host: template.host,
        port: template.port,
        database_name: template.database_name,
        username: template.username,
        ssl_mode: template.ssl_mode,
        password,
        is_monitored: true,
        is_shared: false,
      });
      return ((await response.json()) as Connection).id;
    }
    
    // Returns the named connection from the list, or undefined if the list has
    // no such connection.
    async function findConnection(
      baseUrl: string,
      session: string,
      name: string,
    ): Promise<Connection | undefined> {
      const response = await api("GET", baseUrl, "/connections", session);
      const connections = (await response.json()) as Connection[];
      return connections.find((c) => c.name === name);
    }
    
    // Deletes a connection by its ID.
    async function deleteConnection(
      baseUrl: string,
      session: string,
      connectionId: number,
    ): Promise<void> {
      await api("DELETE", baseUrl, `/connections/${connectionId}`, session);
    }
    
    async function main(): Promise<number> {
      let exitCode = 0;
      let cleanup: (() => Promise<void>) | undefined;
      try {
        const s = settings();
    
        const session = await login(s.baseUrl, s.username, s.password);
        const template = await getConnection(s.baseUrl, session, s.connectionId);
    
        const newId = await registerServer(
          s.baseUrl,
          session,
          SERVER_NAME,
          template,
          s.serverPassword,
        );
        // Delete the connection whether or not a later step fails, so that a
        // failed run does not leave a server registered.
        cleanup = () => deleteConnection(s.baseUrl, session, newId);
        console.log(`Registered the server '${SERVER_NAME}'`);
    
        const found = await findConnection(s.baseUrl, session, SERVER_NAME);
        if (!found) throw new Error("The new connection is missing from the list");
        console.log(
          `Found '${SERVER_NAME}' in the list (monitored: ${found.is_monitored})`,
        );
    
        await cleanup();
        cleanup = undefined;
        console.log("Deleted the connection");
    
        if (await findConnection(s.baseUrl, session, SERVER_NAME)) {
          throw new Error("The connection is still in the list");
        }
        console.log("The connection is no longer in the list");
      } catch (err) {
        console.error(`Error: ${err instanceof Error ? err.message : err}`);
        exitCode = 1;
      }
    
      if (cleanup) {
        try {
          await cleanup();
        } catch (err) {
          console.error(
            `Error: could not delete the connection: ${
              err instanceof Error ? err.message : err
            }`,
          );
          exitCode = 1;
        }
      }
      return exitCode;
    }
    
    process.exitCode = await main();
    
    ```

=== "Java"

    ```java
    /*
     * Ellie's Postgres Cookbook
     * Registering a server to monitor with the AI DBA Workbench API, using
     * java.net.http and Jackson.
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
    import java.time.Duration;
    import java.util.Map;
    import java.util.Objects;
    import java.util.concurrent.CompletableFuture;
    import java.util.concurrent.ExecutionException;
    import java.util.concurrent.TimeUnit;
    import java.util.concurrent.TimeoutException;
    import java.util.regex.Matcher;
    import java.util.regex.Pattern;
    import tools.jackson.core.JacksonException;
    import tools.jackson.databind.JsonNode;
    import tools.jackson.databind.ObjectMapper;
    import tools.jackson.databind.node.ObjectNode;
    
    public class Main {
    
        static final String SERVER_NAME = "cookbook-register-server";
    
        /** The settings that the program reads from the environment. */
        record Settings(String baseUrl, String username, String password,
                String connectionId, String serverPassword) {}
    
        /**
         * Returns the value of an environment variable, or the fallback if the
         * variable is unset or empty, as an unset variable would be.
         */
        static String envOr(String name, String fallback) {
            String value = System.getenv(name);
            return (value != null && !value.isEmpty()) ? value : fallback;
        }
    
        /** Reads the settings from the environment. */
        static Settings settings() throws IOException {
            String username = envOr("WORKBENCH_USERNAME", "");
            String password = envOr("WORKBENCH_PASSWORD", "");
            String connectionId = envOr("WORKBENCH_CONNECTION_ID", "");
            if (username.isEmpty() || password.isEmpty()
                    || connectionId.isEmpty()) {
                throw new IOException("WORKBENCH_USERNAME, WORKBENCH_PASSWORD, "
                        + "and WORKBENCH_CONNECTION_ID must be set");
            }
            String baseUrl = envOr("WORKBENCH_URL", "http://localhost:8080")
                    .replaceAll("/+$", "");
            // The Workbench refuses to register a server without a password,
            // even one that uses trust authentication, so fall back to a
            // placeholder.
            String serverPassword =
                    envOr("PGPASSWORD", "unused-with-trust-authentication");
            return new Settings(baseUrl, username, password, connectionId,
                    serverPassword);
        }
    
        /** One client serves every request; it is safe to share. */
        static final HttpClient CLIENT = HttpClient.newBuilder()
                .connectTimeout(Duration.ofSeconds(30))
                .build();
    
        /**
         * Sends a request and returns the response with its whole body. The
         * request timeout stops applying once the headers arrive, so a server
         * that stalls part of the way through the body would hang send(); this
         * applies the same timeout to the whole exchange instead.
         */
        static HttpResponse<String> send(HttpRequest request)
                throws IOException, InterruptedException {
            Duration timeout = request.timeout().orElseThrow();
            CompletableFuture<HttpResponse<String>> pending =
                    CLIENT.sendAsync(request, HttpResponse.BodyHandlers.ofString());
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
    
        /** Converts between JSON text and Java objects. */
        static final ObjectMapper JSON = new ObjectMapper();
    
        /**
         * Sends a request to the API and returns the response. The token and
         * the body may be null. A request that the server rejects throws an
         * error that includes the message from the server.
         */
        static HttpResponse<String> api(String method, String baseUrl,
                String path, String token, Object body)
                throws IOException, InterruptedException {
            HttpRequest.Builder request = HttpRequest
                    .newBuilder(URI.create(baseUrl + "/api/v1" + path))
                    .timeout(Duration.ofSeconds(30));
            if (token != null) {
                request.header("Authorization", "Bearer " + token);
            }
            HttpRequest.BodyPublisher content = HttpRequest.BodyPublishers.noBody();
            if (body != null) {
                request.header("Content-Type", "application/json");
                content = HttpRequest.BodyPublishers.ofString(
                        JSON.writeValueAsString(body));
            }
    
            HttpResponse<String> response = send(request.method(method, content).build());
            if (response.statusCode() >= 400) {
                throw new IOException(method + " " + path
                        + " failed with status " + response.statusCode() + ": "
                        + response.body().strip());
            }
            return response;
        }
    
        /** Sends a request to the API and returns the JSON reply. */
        static JsonNode apiJson(String method, String baseUrl, String path,
                String token, Object body)
                throws IOException, InterruptedException {
            return JSON.readTree(api(method, baseUrl, path, token, body).body());
        }
    
        /** Matches the session_token cookie in a Set-Cookie header. */
        static final Pattern SESSION_COOKIE =
                Pattern.compile("^session_token=([^;]*)");
    
        /**
         * Logs in and returns the session token. The server returns the token
         * in a session_token cookie, not in the body of the reply.
         */
        static String login(String baseUrl, String username, String password)
                throws IOException, InterruptedException {
            HttpResponse<String> response = api("POST", baseUrl, "/auth/login",
                    null, Map.of("username", username, "password", password));
            for (String cookie : response.headers().allValues("Set-Cookie")) {
                Matcher match = SESSION_COOKIE.matcher(cookie);
                if (match.find()) {
                    return match.group(1);
                }
            }
            throw new IOException("The login reply had no session_token cookie");
        }
    
        /**
         * Returns the details of an existing connection, which the program
         * uses as the address of the server to register.
         */
        static JsonNode getConnection(String baseUrl, String session,
                String connectionId) throws IOException, InterruptedException {
            return apiJson("GET", baseUrl, "/connections/" + connectionId,
                    session, null);
        }
    
        /**
         * Registers a server and returns the ID of the new connection. The
         * address comes from an existing connection. The request must include
         * a password, and a description, which the server needs in version
         * 1.0.0.
         */
        static long registerServer(String baseUrl, String session, String name,
                JsonNode template, String password)
                throws IOException, InterruptedException {
            ObjectNode body = JSON.createObjectNode()
                    .put("name", name)
                    .put("description", "Registered by the cookbook");
            // Copy the address from the existing connection; set() writes a
            // JSON null for a field that the connection lacks.
            for (String field : new String[] {
                    "host", "port", "database_name", "username", "ssl_mode"}) {
                body.set(field, template.get(field));
            }
            body.put("password", password)
                    .put("is_monitored", true)
                    .put("is_shared", false);
    
            JsonNode created = apiJson("POST", baseUrl, "/connections", session,
                    body);
            return created.get("id").asLong();
        }
    
        /**
         * Returns the named connection from the list, or null if the list has
         * no such connection.
         */
        static JsonNode findConnection(String baseUrl, String session,
                String name) throws IOException, InterruptedException {
            for (JsonNode connection
                    : apiJson("GET", baseUrl, "/connections", session, null)) {
                if (name.equals(connection.get("name").asString())) {
                    return connection;
                }
            }
            return null;
        }
    
        /** Deletes a connection by its ID. */
        static void deleteConnection(String baseUrl, String session,
                long connectionId) throws IOException, InterruptedException {
            api("DELETE", baseUrl, "/connections/" + connectionId, session,
                    null);
        }
    
        /**
         * Returns the message of an error. Some errors, such as a refused
         * connection, have no message, so their type stands in for one.
         */
        static String describe(Exception e) {
            return Objects.requireNonNullElse(e.getMessage(), e.toString());
        }
    
        public static void main(String[] args) {
            int status = 0;
            String baseUrl = null;
            String session = null;
            Long newId = null;
            try {
                Settings settings = settings();
                baseUrl = settings.baseUrl();
    
                session = login(baseUrl, settings.username(),
                        settings.password());
                JsonNode template = getConnection(baseUrl, session,
                        settings.connectionId());
    
                newId = registerServer(baseUrl, session, SERVER_NAME, template,
                        settings.serverPassword());
                System.out.println("Registered the server '" + SERVER_NAME + "'");
    
                JsonNode found = findConnection(baseUrl, session, SERVER_NAME);
                if (found == null) {
                    throw new IOException(
                            "The new connection is missing from the list");
                }
                System.out.println("Found '" + SERVER_NAME
                        + "' in the list (monitored: "
                        + found.get("is_monitored").asBoolean() + ")");
    
                deleteConnection(baseUrl, session, newId);
                newId = null;
                System.out.println("Deleted the connection");
    
                if (findConnection(baseUrl, session, SERVER_NAME) != null) {
                    throw new IOException("The connection is still in the list");
                }
                System.out.println("The connection is no longer in the list");
            // IOException covers failures to connect, replies that the server
            // rejected, and replies that lacked what we need; the client
            // throws InterruptedException if the thread is interrupted, and
            // Jackson throws JacksonException for a reply that is not JSON.
            } catch (IOException | InterruptedException | JacksonException e) {
                System.err.println("Error: " + describe(e));
                status = 1;
            } finally {
                // Delete the connection whether or not a later step failed, so
                // that a failed run does not leave a server registered. The
                // finally block also runs for an error that the catch does not
                // handle.
                if (newId != null) {
                    try {
                        deleteConnection(baseUrl, session, newId);
                    } catch (IOException | InterruptedException
                            | JacksonException e) {
                        System.err.println(
                                "Error: could not delete the connection: "
                                + describe(e));
                        status = 1;
                    }
                }
            }
            System.exit(status);
        }
    }
    
    ```

=== "C#"

    ```csharp
    /*
     * Ellie's Postgres Cookbook
     * Registering a server to monitor with the AI DBA Workbench API, using
     * HttpClient and System.Text.Json.
     *
     * Copyright (c) 2026, pgEdge, Inc.
     * This code is released under the PostgreSQL License.
     */
    
    using System.Net.Http.Headers;
    using System.Net.Http.Json;
    using System.Text.Json;
    using System.Text.Json.Nodes;
    using System.Text.RegularExpressions;
    
    const string ServerName = "cookbook-register-server";
    
    // Returns the value of an environment variable, or null if the variable
    // is unset or empty, as an unset variable would be.
    static string? EnvValue(string name) =>
        Environment.GetEnvironmentVariable(name) is { Length: > 0 } value
            ? value
            : null;
    
    // Reads the settings from the environment.
    static (string BaseUrl, string Username, string Password,
        string ConnectionId, string ServerPassword) Settings()
    {
        var username = EnvValue("WORKBENCH_USERNAME");
        var password = EnvValue("WORKBENCH_PASSWORD");
        var connectionId = EnvValue("WORKBENCH_CONNECTION_ID");
        if (username is null || password is null || connectionId is null)
        {
            throw new InvalidOperationException(
                "WORKBENCH_USERNAME, WORKBENCH_PASSWORD, and "
                + "WORKBENCH_CONNECTION_ID must be set");
        }
        var baseUrl = EnvValue("WORKBENCH_URL") ?? "http://localhost:8080";
        // The Workbench refuses to register a server without a password, even
        // one that uses trust authentication, so fall back to a placeholder.
        var serverPassword =
            EnvValue("PGPASSWORD") ?? "unused-with-trust-authentication";
        return (baseUrl.TrimEnd('/'), username, password, connectionId,
            serverPassword);
    }
    
    // One client serves every request, with a timeout for each. The handler
    // keeps no cookies, so the session token goes only where the program
    // sends it.
    var http = new HttpClient(new SocketsHttpHandler { UseCookies = false })
    {
        Timeout = TimeSpan.FromSeconds(30),
    };
    
    // Sends a request to the API and returns the response, which the caller
    // must dispose of. A request that the server rejects throws an error that
    // includes the message from the server.
    async Task<HttpResponseMessage> Api(string method, string baseUrl,
        string path, string? token = null, object? body = null)
    {
        using var request = new HttpRequestMessage(
            new HttpMethod(method), $"{baseUrl}/api/v1{path}");
        if (token is not null)
        {
            request.Headers.Authorization =
                new AuthenticationHeaderValue("Bearer", token);
        }
        if (body is not null)
        {
            request.Content = JsonContent.Create(body);
        }
    
        var response = await http.SendAsync(request);
        var code = (int)response.StatusCode;
        if (code >= 400)
        {
            var text = (await response.Content.ReadAsStringAsync()).Trim();
            response.Dispose();
            throw new HttpRequestException(
                $"{method} {path} failed with status {code}: {text}");
        }
        return response;
    }
    
    // Sends a request to the API and returns the JSON reply.
    async Task<JsonNode> ApiJson(string method, string baseUrl, string path,
        string? token = null, object? body = null)
    {
        using var response = await Api(method, baseUrl, path, token, body);
        return JsonNode.Parse(await response.Content.ReadAsStringAsync())
            ?? throw new InvalidOperationException(
                $"{method} {path} returned no JSON");
    }
    
    // Logs in and returns the session token. The server returns the token in a
    // session_token cookie, not in the body of the reply.
    async Task<string> Login(string baseUrl, string username, string password)
    {
        using var response = await Api("POST", baseUrl, "/auth/login",
            body: new { username, password });
        if (response.Headers.TryGetValues("Set-Cookie", out var cookies))
        {
            foreach (var cookie in cookies)
            {
                var match = Regex.Match(cookie, "^session_token=([^;]*)");
                if (match.Success)
                {
                    return match.Groups[1].Value;
                }
            }
        }
        throw new InvalidOperationException(
            "The login reply had no session_token cookie");
    }
    
    // Returns the details of an existing connection, which the program uses
    // as the address of the server to register.
    async Task<JsonNode> GetConnection(string baseUrl, string session,
        string connectionId) =>
        await ApiJson("GET", baseUrl, $"/connections/{connectionId}", session);
    
    // Registers a server and returns the ID of the new connection. The address
    // comes from an existing connection. The request must include a password,
    // and a description, which the server needs in version 1.0.0.
    async Task<long> RegisterServer(string baseUrl, string session,
        string name, JsonNode template, string password)
    {
        // A JSON node belongs to one parent at a time, so the program copies
        // each field that it takes from the existing connection.
        var body = new JsonObject
        {
            ["name"] = name,
            ["description"] = "Registered by the cookbook",
            ["host"] = template["host"]?.DeepClone(),
            ["port"] = template["port"]?.DeepClone(),
            ["database_name"] = template["database_name"]?.DeepClone(),
            ["username"] = template["username"]?.DeepClone(),
            ["ssl_mode"] = template["ssl_mode"]?.DeepClone(),
            ["password"] = password,
            ["is_monitored"] = true,
            ["is_shared"] = false,
        };
        var created = await ApiJson("POST", baseUrl, "/connections", session,
            body);
        return created["id"]!.GetValue<long>();
    }
    
    // Returns the named connection from the list, or null if the list has no
    // such connection.
    async Task<JsonNode?> FindConnection(string baseUrl, string session,
        string name)
    {
        var connections = await ApiJson("GET", baseUrl, "/connections", session);
        return connections.AsArray().FirstOrDefault(
            c => c?["name"]?.GetValue<string>() == name);
    }
    
    // Deletes a connection by its ID.
    async Task DeleteConnection(string baseUrl, string session,
        long connectionId)
    {
        using var response = await Api("DELETE", baseUrl,
            $"/connections/{connectionId}", session);
    }
    
    var status = 0;
    var baseUrl = "";
    var session = "";
    long? newId = null;
    try
    {
        var settings = Settings();
        baseUrl = settings.BaseUrl;
    
        session = await Login(baseUrl, settings.Username, settings.Password);
        var template = await GetConnection(baseUrl, session,
            settings.ConnectionId);
    
        newId = await RegisterServer(baseUrl, session, ServerName, template,
            settings.ServerPassword);
        Console.WriteLine($"Registered the server '{ServerName}'");
    
        var found = await FindConnection(baseUrl, session, ServerName)
            ?? throw new InvalidOperationException(
                "The new connection is missing from the list");
        // A bool would print as True or False, so spell the flag out.
        var monitored = found["is_monitored"]!.GetValue<bool>() ? "true" : "false";
        Console.WriteLine(
            $"Found '{ServerName}' in the list (monitored: {monitored})");
    
        await DeleteConnection(baseUrl, session, newId.Value);
        newId = null;
        Console.WriteLine("Deleted the connection");
    
        if (await FindConnection(baseUrl, session, ServerName) is not null)
        {
            throw new InvalidOperationException(
                "The connection is still in the list");
        }
        Console.WriteLine("The connection is no longer in the list");
    }
    // HttpRequestException covers failures to connect and replies that the
    // server rejected, TaskCanceledException covers a request that timed out,
    // and the others cover replies that lacked what we need.
    catch (Exception e) when (e is HttpRequestException
        or TaskCanceledException or InvalidOperationException or JsonException)
    {
        Console.Error.WriteLine($"Error: {e.Message}");
        status = 1;
    }
    finally
    {
        // Delete the connection whether or not a later step failed, so that a
        // failed run does not leave a server registered. The finally block also
        // runs for an error that the catch does not handle.
        if (newId is not null)
        {
            try
            {
                await DeleteConnection(baseUrl, session, newId.Value);
            }
            catch (Exception e) when (e is HttpRequestException
                or TaskCanceledException)
            {
                Console.Error.WriteLine(
                    $"Error: could not delete the connection: {e.Message}");
                status = 1;
            }
        }
    }
    
    return status;
    
    ```

=== "Go"

    ```go
    /*
     * Ellie's Postgres Cookbook
     * Registering a server to monitor with the AI DBA Workbench API, using
     * net/http.
     *
     * Copyright (c) 2026, pgEdge, Inc.
     * This code is released under the PostgreSQL License.
     */
    
    package main
    
    import (
    	"bytes"
    	"encoding/json"
    	"errors"
    	"fmt"
    	"io"
    	"net/http"
    	"os"
    	"strings"
    	"time"
    )
    
    
    const serverName = "cookbook-register-server"
    
    // settings holds the values that the program reads from the environment.
    type settings struct {
    	baseURL        string
    	username       string
    	password       string
    	connectionID   string
    	serverPassword string
    }
    
    // envOr returns the value of an environment variable, or the fallback if
    // the variable is unset or empty, as an unset variable would be.
    func envOr(name, fallback string) string {
    	if value := os.Getenv(name); value != "" {
    		return value
    	}
    	return fallback
    }
    
    // loadSettings reads the settings from the environment.
    func loadSettings() (settings, error) {
    	s := settings{
    		baseURL:      strings.TrimRight(envOr("WORKBENCH_URL", "http://localhost:8080"), "/"),
    		username:     os.Getenv("WORKBENCH_USERNAME"),
    		password:     os.Getenv("WORKBENCH_PASSWORD"),
    		connectionID: os.Getenv("WORKBENCH_CONNECTION_ID"),
    		// The Workbench refuses to register a server without a password,
    		// even one that uses trust authentication, so fall back to a
    		// placeholder.
    		serverPassword: envOr("PGPASSWORD", "unused-with-trust-authentication"),
    	}
    	if s.username == "" || s.password == "" || s.connectionID == "" {
    		return s, errors.New("WORKBENCH_USERNAME, WORKBENCH_PASSWORD, and WORKBENCH_CONNECTION_ID must be set")
    	}
    	return s, nil
    }
    
    
    // client gives every request a timeout; the default client has none.
    var client = &http.Client{Timeout: 30 * time.Second}
    
    // api sends a request to the API and returns the response, which the caller
    // must close. A request that the server rejects returns an error that
    // includes the message from the server.
    func api(method, baseURL, path, token string, body any) (*http.Response, error) {
    	var reader io.Reader
    	if body != nil {
    		encoded, err := json.Marshal(body)
    		if err != nil {
    			return nil, err
    		}
    		reader = bytes.NewReader(encoded)
    	}
    
    	req, err := http.NewRequest(method, baseURL+"/api/v1"+path, reader)
    	if err != nil {
    		return nil, err
    	}
    	if body != nil {
    		req.Header.Set("Content-Type", "application/json")
    	}
    	if token != "" {
    		req.Header.Set("Authorization", "Bearer "+token)
    	}
    
    	resp, err := client.Do(req)
    	if err != nil {
    		return nil, err
    	}
    	if resp.StatusCode >= 400 {
    		defer resp.Body.Close()
    		text, _ := io.ReadAll(resp.Body)
    		return nil, fmt.Errorf("%s %s failed with status %d: %s",
    			method, path, resp.StatusCode, strings.TrimSpace(string(text)))
    	}
    	return resp, nil
    }
    
    // apiJSON sends a request and decodes the JSON reply into out, if given.
    func apiJSON(method, baseURL, path, token string, body, out any) error {
    	resp, err := api(method, baseURL, path, token, body)
    	if err != nil {
    		return err
    	}
    	defer resp.Body.Close()
    	if out == nil {
    		return nil
    	}
    	return json.NewDecoder(resp.Body).Decode(out)
    }
    
    
    // login logs in and returns the session token. The server returns the token
    // in a session_token cookie, not in the body of the reply.
    func login(baseURL, username, password string) (string, error) {
    	resp, err := api("POST", baseURL, "/auth/login", "", map[string]string{
    		"username": username,
    		"password": password,
    	})
    	if err != nil {
    		return "", err
    	}
    	defer resp.Body.Close()
    
    	for _, cookie := range resp.Cookies() {
    		if cookie.Name == "session_token" {
    			return cookie.Value, nil
    		}
    	}
    	return "", errors.New("the login reply had no session_token cookie")
    }
    
    
    // connection is the part of a connection that the program needs.
    type connection struct {
    	ID           int64  `json:"id"`
    	Name         string `json:"name"`
    	Host         string `json:"host"`
    	Port         int    `json:"port"`
    	DatabaseName string `json:"database_name"`
    	Username     string `json:"username"`
    	SSLMode      string `json:"ssl_mode"`
    	IsMonitored  bool   `json:"is_monitored"`
    }
    
    // getConnection returns the details of an existing connection, which the
    // program uses as the address of the server to register.
    func getConnection(baseURL, session, id string) (connection, error) {
    	var c connection
    	err := apiJSON("GET", baseURL, "/connections/"+id, session, nil, &c)
    	return c, err
    }
    
    
    // registerServer registers a server and returns the ID of the new
    // connection. The address comes from an existing connection. The request
    // must include a password, and a description, which the server needs in
    // version 1.0.0.
    func registerServer(baseURL, session, name string, template connection, password string) (int64, error) {
    	var created connection
    	err := apiJSON("POST", baseURL, "/connections", session, map[string]any{
    		"name":          name,
    		"description":   "Registered by the cookbook",
    		"host":          template.Host,
    		"port":          template.Port,
    		"database_name": template.DatabaseName,
    		"username":      template.Username,
    		"ssl_mode":      template.SSLMode,
    		"password":      password,
    		"is_monitored":  true,
    		"is_shared":     false,
    	}, &created)
    	return created.ID, err
    }
    
    
    // findConnection returns the named connection from the list, or nil if the
    // list has no such connection.
    func findConnection(baseURL, session, name string) (*connection, error) {
    	var connections []connection
    	if err := apiJSON("GET", baseURL, "/connections", session, nil, &connections); err != nil {
    		return nil, err
    	}
    	for i := range connections {
    		if connections[i].Name == name {
    			return &connections[i], nil
    		}
    	}
    	return nil, nil
    }
    
    
    // deleteConnection deletes a connection by its ID.
    func deleteConnection(baseURL, session string, id int64) error {
    	return apiJSON("DELETE", baseURL, fmt.Sprintf("/connections/%d", id),
    		session, nil, nil)
    }
    
    
    // run does the work. It returns the cleanup that the caller must run if the
    // program has registered a server and not yet deleted it.
    func run(s settings) (cleanup func() error, err error) {
    	session, err := login(s.baseURL, s.username, s.password)
    	if err != nil {
    		return nil, err
    	}
    	template, err := getConnection(s.baseURL, session, s.connectionID)
    	if err != nil {
    		return nil, err
    	}
    
    	newID, err := registerServer(s.baseURL, session, serverName, template, s.serverPassword)
    	if err != nil {
    		return nil, err
    	}
    	// Return the cleanup before any later step can fail, so that a failed
    	// run does not leave a server registered.
    	cleanup = func() error { return deleteConnection(s.baseURL, session, newID) }
    	fmt.Printf("Registered the server '%s'\n", serverName)
    
    	found, err := findConnection(s.baseURL, session, serverName)
    	if err != nil {
    		return cleanup, err
    	}
    	if found == nil {
    		return cleanup, errors.New("the new connection is missing from the list")
    	}
    	fmt.Printf("Found '%s' in the list (monitored: %t)\n", serverName, found.IsMonitored)
    
    	if err := cleanup(); err != nil {
    		return cleanup, err
    	}
    	cleanup = nil
    	fmt.Println("Deleted the connection")
    
    	found, err = findConnection(s.baseURL, session, serverName)
    	if err != nil {
    		return nil, err
    	}
    	if found != nil {
    		return nil, errors.New("the connection is still in the list")
    	}
    	fmt.Println("The connection is no longer in the list")
    	return nil, nil
    }
    
    func main() {
    	s, err := loadSettings()
    	if err != nil {
    		fmt.Fprintln(os.Stderr, "Error:", err)
    		os.Exit(1)
    	}
    
    	failed := false
    	cleanup, err := run(s)
    	if err != nil {
    		fmt.Fprintln(os.Stderr, "Error:", err)
    		failed = true
    	}
    	if cleanup != nil {
    		if err := cleanup(); err != nil {
    			fmt.Fprintln(os.Stderr, "Error: could not delete the connection:", err)
    			failed = true
    		}
    	}
    	if failed {
    		os.Exit(1)
    	}
    }
    
    
    ```

=== "Rust"

    ```rust
    // Ellie's Postgres Cookbook
    // Registering a server to monitor with the AI DBA Workbench API, using
    // reqwest and serde_json.
    //
    // Copyright (c) 2026, pgEdge, Inc.
    // This code is released under the PostgreSQL License.
    
    use std::env;
    use std::error::Error;
    use std::process::ExitCode;
    use std::sync::LazyLock;
    use std::time::Duration;
    
    use reqwest::blocking::{Client, Response};
    use reqwest::Method;
    use serde_json::{json, Value};
    
    const SERVER_NAME: &str = "cookbook-register-server";
    
    /// Any error, boxed, so that a function can return errors of several types
    /// with the ? operator.
    type Result<T> = std::result::Result<T, Box<dyn Error>>;
    
    /// The settings that the program reads from the environment.
    struct Settings {
        base_url: String,
        username: String,
        password: String,
        connection_id: String,
        server_password: String,
    }
    
    /// Returns the value of an environment variable, if it is set and not
    /// empty; an empty variable counts as unset.
    fn env_value(name: &str) -> Option<String> {
        env::var(name).ok().filter(|value| !value.is_empty())
    }
    
    /// Reads the settings from the environment.
    fn settings() -> Result<Settings> {
        let (Some(username), Some(password), Some(connection_id)) = (
            env_value("WORKBENCH_USERNAME"),
            env_value("WORKBENCH_PASSWORD"),
            env_value("WORKBENCH_CONNECTION_ID"),
        ) else {
            return Err("WORKBENCH_USERNAME, WORKBENCH_PASSWORD, and \
                        WORKBENCH_CONNECTION_ID must be set"
                .into());
        };
        let base_url = env_value("WORKBENCH_URL")
            .unwrap_or_else(|| "http://localhost:8080".to_string())
            .trim_end_matches('/')
            .to_string();
        // The Workbench refuses to register a server without a password, even
        // one that uses trust authentication, so fall back to a placeholder.
        let server_password =
            env_value("PGPASSWORD").unwrap_or_else(|| "unused-with-trust-authentication".to_string());
        Ok(Settings {
            base_url,
            username,
            password,
            connection_id,
            server_password,
        })
    }
    
    /// One client serves every request, with a timeout for each; the client
    /// has none by default.
    static CLIENT: LazyLock<Client> = LazyLock::new(|| {
        Client::builder()
            .timeout(Duration::from_secs(30))
            .build()
            .expect("could not create the HTTP client")
    });
    
    /// Sends a request to the API and returns the response. A request that the
    /// server rejects returns an error that includes the message from the
    /// server.
    fn api(
        method: Method,
        base_url: &str,
        path: &str,
        token: Option<&str>,
        body: Option<&Value>,
    ) -> Result<Response> {
        let mut request = CLIENT.request(method.clone(), format!("{base_url}/api/v1{path}"));
        if let Some(token) = token {
            request = request.bearer_auth(token);
        }
        if let Some(body) = body {
            request = request.json(body);
        }
    
        let response = request.send()?;
        let status = response.status().as_u16();
        if status >= 400 {
            let text = response.text()?;
            return Err(format!(
                "{method} {path} failed with status {status}: {}",
                text.trim()
            )
            .into());
        }
        Ok(response)
    }
    
    /// Logs in and returns the session token. The server returns the token in
    /// a session_token cookie, not in the body of the reply.
    fn login(base_url: &str, username: &str, password: &str) -> Result<String> {
        let body = json!({ "username": username, "password": password });
        let response = api(Method::POST, base_url, "/auth/login", None, Some(&body))?;
        for cookie in response.headers().get_all("set-cookie") {
            if let Some(rest) = cookie.to_str()?.strip_prefix("session_token=") {
                // The value runs up to the first attribute, if there is one.
                let value = rest.split(';').next().unwrap_or_default();
                return Ok(value.to_string());
            }
        }
        Err("the login reply had no session_token cookie".into())
    }
    
    /// Returns the details of an existing connection, which the program uses
    /// as the address of the server to register.
    fn get_connection(base_url: &str, session: &str, connection_id: &str) -> Result<Value> {
        let path = format!("/connections/{connection_id}");
        Ok(api(Method::GET, base_url, &path, Some(session), None)?.json()?)
    }
    
    /// Registers a server and returns the ID of the new connection. The
    /// address comes from an existing connection. The request must include a
    /// password, and a description, which the server needs in version 1.0.0.
    fn register_server(
        base_url: &str,
        session: &str,
        name: &str,
        template: &Value,
        password: &str,
    ) -> Result<i64> {
        // Indexing a missing field gives null rather than a panic.
        let body = json!({
            "name": name,
            "description": "Registered by the cookbook",
            "host": template["host"],
            "port": template["port"],
            "database_name": template["database_name"],
            "username": template["username"],
            "ssl_mode": template["ssl_mode"],
            "password": password,
            "is_monitored": true,
            "is_shared": false,
        });
        let created: Value = api(
            Method::POST,
            base_url,
            "/connections",
            Some(session),
            Some(&body),
        )?
        .json()?;
        Ok(created["id"]
            .as_i64()
            .ok_or("the reply had no connection ID")?)
    }
    
    /// Returns the named connection from the list, or None if the list has no
    /// such connection.
    fn find_connection(base_url: &str, session: &str, name: &str) -> Result<Option<Value>> {
        let connections: Vec<Value> =
            api(Method::GET, base_url, "/connections", Some(session), None)?.json()?;
        Ok(connections.into_iter().find(|c| c["name"] == name))
    }
    
    /// Deletes a connection by its ID.
    fn delete_connection(base_url: &str, session: &str, connection_id: i64) -> Result<()> {
        let path = format!("/connections/{connection_id}");
        api(Method::DELETE, base_url, &path, Some(session), None)?;
        Ok(())
    }
    
    /// What the program must delete when it finishes: the new connection's
    /// ID, and the session token that has the right to delete it.
    struct Cleanup {
        session: String,
        connection_id: i64,
    }
    
    /// Does the work. Once it has registered the server, it records the new
    /// connection in cleanup, so that main deletes it even if a later step
    /// fails.
    fn run(s: &Settings, cleanup: &mut Option<Cleanup>) -> Result<()> {
        let session = login(&s.base_url, &s.username, &s.password)?;
        let template = get_connection(&s.base_url, &session, &s.connection_id)?;
    
        let new_id = register_server(
            &s.base_url,
            &session,
            SERVER_NAME,
            &template,
            &s.server_password,
        )?;
        *cleanup = Some(Cleanup {
            session: session.clone(),
            connection_id: new_id,
        });
        println!("Registered the server '{SERVER_NAME}'");
    
        let found = find_connection(&s.base_url, &session, SERVER_NAME)?
            .ok_or("the new connection is missing from the list")?;
        let monitored = found["is_monitored"]
            .as_bool()
            .ok_or("the connection had no monitored flag")?;
        println!("Found '{SERVER_NAME}' in the list (monitored: {monitored})");
    
        delete_connection(&s.base_url, &session, new_id)?;
        *cleanup = None;
        println!("Deleted the connection");
    
        if find_connection(&s.base_url, &session, SERVER_NAME)?.is_some() {
            return Err("the connection is still in the list".into());
        }
        println!("The connection is no longer in the list");
        Ok(())
    }
    
    /// Prints an error with the chain of underlying causes, because the
    /// top-level error is often generic ("error sending request").
    fn report(prefix: &str, e: &dyn Error) {
        eprintln!("{prefix}{e}");
        let mut cause = e.source();
        while let Some(c) = cause {
            eprintln!("  caused by: {c}");
            cause = c.source();
        }
    }
    
    fn main() -> ExitCode {
        let s = match settings() {
            Ok(s) => s,
            Err(e) => {
                report("Error: ", e.as_ref());
                return ExitCode::FAILURE;
            }
        };
    
        let mut status = ExitCode::SUCCESS;
        let mut cleanup = None;
        if let Err(e) = run(&s, &mut cleanup) {
            report("Error: ", e.as_ref());
            status = ExitCode::FAILURE;
        }
    
        // Delete the connection whether or not a later step failed, so that a
        // failed run does not leave a server registered.
        if let Some(c) = cleanup {
            if let Err(e) = delete_connection(&s.base_url, &c.session, c.connection_id) {
                report("Error: could not delete the connection: ", e.as_ref());
                status = ExitCode::FAILURE;
            }
        }
        status
    }
    
    ```

=== "Ruby"

    ```ruby
    # Ellie's Postgres Cookbook
    # Registering a server to monitor with the AI DBA Workbench API, using
    # Net::HTTP.
    #
    # Copyright (c) 2026, pgEdge, Inc.
    # This code is released under the PostgreSQL License.
    
    require "json"
    require "net/http"
    
    SERVER_NAME = "cookbook-register-server"
    
    # Returns the value of an environment variable, or a fallback if the
    # variable is unset or empty, as an unset variable would be.
    def env_or(name, fallback)
      value = ENV[name]
      value.nil? || value.empty? ? fallback : value
    end
    
    # Reads the settings from the environment.
    def settings
      username = env_or("WORKBENCH_USERNAME", nil)
      password = env_or("WORKBENCH_PASSWORD", nil)
      connection_id = env_or("WORKBENCH_CONNECTION_ID", nil)
      unless username && password && connection_id
        raise "WORKBENCH_USERNAME, WORKBENCH_PASSWORD, and " \
              "WORKBENCH_CONNECTION_ID must be set"
      end
    
      {
        base_url: env_or("WORKBENCH_URL", "http://localhost:8080").sub(%r{/+\z}, ""),
        username: username,
        password: password,
        connection_id: connection_id,
        # The Workbench refuses to register a server without a password, even
        # one that uses trust authentication, so fall back to a placeholder.
        server_password: env_or("PGPASSWORD", "unused-with-trust-authentication")
      }
    end
    
    # Sends a request to the API and returns the response. The body, if given,
    # is sent as JSON. A request that the server rejects raises an error that
    # includes the message from the server.
    def api(method, base_url, path, token = nil, body = nil)
      uri = URI("#{base_url}/api/v1#{path}")
      headers = {}
      headers["Authorization"] = "Bearer #{token}" if token
      headers["Content-Type"] = "application/json" if body
    
      # Net::HTTP has no overall timeout, so limit both the connection and
      # each read.
      response = Net::HTTP.start(uri.host, uri.port,
                                 use_ssl: uri.scheme == "https",
                                 open_timeout: 30, read_timeout: 30) do |http|
        http.send_request(method, uri.request_uri, body&.to_json, headers)
      end
      if response.code.to_i >= 400
        raise "#{method} #{path} failed with status #{response.code}: " \
              "#{response.body.to_s.strip}"
      end
      response
    end
    
    # Logs in and returns the session token. The server returns the token in a
    # session_token cookie, not in the body of the reply.
    def login(base_url, username, password)
      response = api("POST", base_url, "/auth/login", nil,
                     { username: username, password: password })
      (response.get_fields("set-cookie") || []).each do |cookie|
        match = /\Asession_token=([^;]*)/.match(cookie)
        return match[1] if match
      end
      raise "The login reply had no session_token cookie"
    end
    
    # Returns the details of an existing connection, which the program uses as
    # the address of the server to register.
    def get_connection(base_url, session, connection_id)
      JSON.parse(api("GET", base_url, "/connections/#{connection_id}",
                     session).body)
    end
    
    # Registers a server and returns the ID of the new connection. The address
    # comes from an existing connection. The request must include a password,
    # and a description, which the server needs in version 1.0.0.
    def register_server(base_url, session, name, template, password)
      response = api("POST", base_url, "/connections", session, {
                       name: name,
                       description: "Registered by the cookbook",
                       host: template.fetch("host"),
                       port: template.fetch("port"),
                       database_name: template.fetch("database_name"),
                       username: template.fetch("username"),
                       ssl_mode: template["ssl_mode"],
                       password: password,
                       is_monitored: true,
                       is_shared: false
                     })
      JSON.parse(response.body).fetch("id")
    end
    
    # Returns the named connection from the list, or nil if the list has no
    # such connection.
    def find_connection(base_url, session, name)
      connections = JSON.parse(api("GET", base_url, "/connections", session).body)
      connections.find { |c| c["name"] == name }
    end
    
    # Deletes a connection by its ID.
    def delete_connection(base_url, session, connection_id)
      api("DELETE", base_url, "/connections/#{connection_id}", session)
    end
    
    def main
      new_id = nil
      status = 0
      begin
        config = settings
        base_url = config[:base_url]
    
        session = login(base_url, config[:username], config[:password])
        template = get_connection(base_url, session, config[:connection_id])
    
        new_id = register_server(base_url, session, SERVER_NAME, template,
                                 config[:server_password])
        puts "Registered the server '#{SERVER_NAME}'"
    
        found = find_connection(base_url, session, SERVER_NAME)
        raise "The new connection is missing from the list" if found.nil?
    
        puts "Found '#{SERVER_NAME}' in the list " \
             "(monitored: #{found.fetch('is_monitored')})"
    
        delete_connection(base_url, session, new_id)
        new_id = nil
        puts "Deleted the connection"
    
        unless find_connection(base_url, session, SERVER_NAME).nil?
          raise "The connection is still in the list"
        end
    
        puts "The connection is no longer in the list"
      # Net::HTTP raises errors of many classes, such as SystemCallError for a
      # refused connection and Net::OpenTimeout for a timeout, and the program
      # raises RuntimeError for replies that the server rejected or that lacked
      # what we need, so this catches StandardError, their common ancestor.
      rescue StandardError => e
        warn "Error: #{e.message}"
        status = 1
      ensure
        # Delete the connection whether or not a later step failed, so that a
        # failed run does not leave a server registered.
        if new_id
          begin
            delete_connection(base_url, session, new_id)
          rescue StandardError => e
            warn "Error: could not delete the connection: #{e.message}"
            status = 1
          end
        end
      end
      status
    end
    
    exit main
    
    ```

=== "curl"

    ```bash
    #!/usr/bin/env bash
    #
    # Ellie's Postgres Cookbook
    # Registering a server to monitor with the AI DBA Workbench API, using curl
    # and jq.
    #
    # Copyright (c) 2026, pgEdge, Inc.
    # This code is released under the PostgreSQL License.
    
    # Stop at the first failing command, treat an unset variable as an error,
    # and fail a pipeline when any command in it fails.
    set -euo pipefail
    
    # The script needs curl to make the requests and jq to read the replies.
    for tool in curl jq; do
        command -v "$tool" >/dev/null || { echo "$tool is required" >&2; exit 1; }
    done
    
    # Read the settings from the environment. The :- and :? forms, unlike - and
    # ?, treat an empty variable as unset.
    WORKBENCH_URL="${WORKBENCH_URL:-http://localhost:8080}"
    WORKBENCH_URL="${WORKBENCH_URL%/}"
    : "${WORKBENCH_USERNAME:?WORKBENCH_USERNAME must be set}"
    : "${WORKBENCH_PASSWORD:?WORKBENCH_PASSWORD must be set}"
    : "${WORKBENCH_CONNECTION_ID:?WORKBENCH_CONNECTION_ID must be set}"
    
    # The Workbench refuses to register a server without a password, even one
    # that uses trust authentication, so the script falls back to a placeholder.
    SERVER_PASSWORD="${PGPASSWORD:-unused-with-trust-authentication}"
    SERVER_NAME="cookbook-register-server"
    
    # Sends an authenticated request and prints the JSON reply:
    # api METHOD PATH TOKEN [curl options]. With --fail-with-body, a request
    # that the server rejects leaves the server's error message in the reply,
    # and the function prints it to standard error.
    # The token goes to curl in a header file that bash supplies through a pipe,
    # so that it never appears in the arguments of the curl process, which other
    # users can read in the process list.
    api() {
        local method="$1" path="$2" token="$3"
        shift 3
        local response
        response=$(curl --silent --show-error --fail-with-body \
            --connect-timeout 10 --max-time 30 \
            --request "$method" \
            --header @<(printf 'Authorization: Bearer %s\n' "$token") \
            "$@" "$WORKBENCH_URL/api/v1$path") || {
            echo "$method $path failed: $response" >&2
            return 1
        }
        printf '%s' "$response"
    }
    
    # Logs in and prints the session token. The server returns the token in a
    # session_token cookie, so the request includes the response headers.
    login() {
        local response
        # jq reads the credentials from its environment, and curl reads the
        # request from standard input, so that neither the password nor the
        # request body appears in a process list.
        response=$(jq -n '{username: env.WORKBENCH_USERNAME,
                           password: env.WORKBENCH_PASSWORD}' |
            curl --silent --show-error --fail-with-body --include \
                 --connect-timeout 10 --max-time 30 \
                 --request POST \
                 --header 'Content-Type: application/json' \
                 --data @- \
                 "$WORKBENCH_URL/api/v1/auth/login") || {
            echo "Login failed: $response" >&2
            return 1
        }
    
        # Header lines end in a carriage return, which tr removes.
        local token
        token=$(printf '%s' "$response" | tr -d '\r' |
            sed -n 's/^[Ss]et-[Cc]ookie: session_token=\([^;]*\).*/\1/p')
        if [[ -z "$token" ]]; then
            echo "The login reply had no session_token cookie" >&2
            return 1
        fi
        printf '%s' "$token"
    }
    
    # Prints the details of an existing connection, which the script uses as
    # the address of the server to register.
    get_connection() {
        local session="$1" connection_id="$2"
        api GET "/connections/$connection_id" "$session"
    }
    
    # Registers a server and prints the ID of the new connection. The address
    # comes from an existing connection, given as JSON in the third argument.
    register_server() {
        local session="$1" name="$2" template="$3"
        # The template's host, port, database, and user become the new
        # connection's. jq reads the password from its environment, which keeps
        # it off the command line, and the request sends a description, which
        # the server needs in version 1.0.0.
        SERVER_PASSWORD="$SERVER_PASSWORD" \
        jq --arg name "$name" \
           '{name: $name, description: "Registered by the cookbook",
             host, port, database_name, username, ssl_mode,
             password: env.SERVER_PASSWORD, is_monitored: true,
             is_shared: false}' \
           <<<"$template" |
            api POST /connections "$session" \
                --header 'Content-Type: application/json' --data @- |
            jq -r '.id'
    }
    
    # Prints the monitoring state of the named connection, or nothing if the
    # list has no such connection.
    find_connection() {
        local session="$1" name="$2"
        api GET /connections "$session" |
            jq -r --arg name "$name" \
               '.[] | select(.name == $name) | "monitored: \(.is_monitored)"'
    }
    
    # Deletes a connection by its ID.
    delete_connection() {
        local session="$1" connection_id="$2"
        api DELETE "/connections/$connection_id" "$session" >/dev/null
    }
    
    # These variables are global, because the EXIT trap runs after main returns.
    session=""
    new_id=""
    
    cleanup() {
        local status=$?
        # Delete the connection when the script ends, even if a later step
        # failed, so that a failed run does not leave a server registered.
        # Report a delete that fails, and make the exit status non-zero.
        if [[ -n "$new_id" ]]; then
            delete_connection "$session" "$new_id" || {
                echo "Error: could not delete the connection $new_id" >&2
                status=1
            }
        fi
        exit "$status"
    }
    
    main() {
        session=$(login)
        local template found
        template=$(get_connection "$session" "$WORKBENCH_CONNECTION_ID")
    
        new_id=$(register_server "$session" "$SERVER_NAME" "$template")
        echo "Registered the server '$SERVER_NAME'"
    
        found=$(find_connection "$session" "$SERVER_NAME")
        if [[ -z "$found" ]]; then
            echo "The new connection is missing from the list" >&2
            return 1
        fi
        echo "Found '$SERVER_NAME' in the list ($found)"
    
        delete_connection "$session" "$new_id"
        new_id=""
        echo "Deleted the connection"
    
        if [[ -n "$(find_connection "$session" "$SERVER_NAME")" ]]; then
            echo "The connection is still in the list" >&2
            return 1
        fi
        echo "The connection is no longer in the list"
    }
    
    trap cleanup EXIT
    main
    
    ```

## Next Steps

The following resources provide more information about the topics in this
recipe:

- The [Authenticating](authenticate.md) recipe explains the two kinds of token
  that the Workbench issues.
- The [Listing and Acknowledging Alerts](alerts.md) recipe shows how to work
  with the alerts that a monitored server raises.
- The AI DBA Workbench
  [API reference](https://github.com/pgEdge/ai-dba-workbench/blob/v1.0.0/docs/admin-guide/api/reference.md)
  describes every endpoint.
