# Authenticating with the AI DBA Workbench API

This recipe shows how a program logs in to the pgEdge AI DBA Workbench API,
checks who it is logged in as, and creates an API token for later use. These
examples are for AI DBA Workbench 1.0.0. Each step shows the code in every
supported language; selecting a language tab switches every tab on the site to
that language.

The example program logs in with a user name and a password, which gives it a
session token. It asks the server which user the session token belongs to, and
then creates an API token that expires after an hour. It uses the new API token
to ask the same question, and finally deletes the token so that the example
leaves nothing behind. The program never prints either token; the output has
the following form:

```text
Logged in with a session token
Session token belongs to cookbook (superuser: true)
Created the API token 'cookbook-authenticate'
API token belongs to cookbook (superuser: true)
Deleted the API token
```

## Preparing the Ingredients

The `scripts/start_workbench.sh` script in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook)
starts a test Workbench in Docker. The script creates a `cookbook` user and an
API token, registers a test PostgreSQL server as a monitored connection, and
prints the `WORKBENCH_URL`, `WORKBENCH_TOKEN`, `WORKBENCH_USERNAME`,
`WORKBENCH_PASSWORD`, and `WORKBENCH_CONNECTION_ID` values that the examples
read from the environment.

The examples need a running Workbench server and a user that can log in. The
following table lists the HTTP client and the JSON library that each example
uses:

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
      "name": "authenticate",
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

The Go project has no dependencies, so its `go.mod` file names only the version
of Go, the Ruby project's `Gemfile` names no gems, and the C# project
references no packages. The TypeScript project depends on the compiler and the
Node.js type definitions only.

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

| Variable             | Default                 | Description          |
|----------------------|-------------------------|----------------------|
| `WORKBENCH_URL`      | `http://localhost:8080` | The server base URL. |
| `WORKBENCH_USERNAME` | None                    | The user name.       |
| `WORKBENCH_PASSWORD` | None                    | The password.        |

!!! note

    Production applications should not store passwords in environment
    variables or source code. A secrets manager provides a safer
    alternative.

The following tabs show how each program reads the settings and stops with an
error when the user name or the password is missing:

=== "Python"

    ```python
    def settings() -> dict:
        """Reads the settings from the environment.
    
        The or operator treats an empty variable as unset.
        """
        username = os.environ.get("WORKBENCH_USERNAME") or ""
        password = os.environ.get("WORKBENCH_PASSWORD") or ""
        if not username or not password:
            raise RuntimeError(
                "WORKBENCH_USERNAME and WORKBENCH_PASSWORD must be set"
            )
        return {
            "base_url": (
                os.environ.get("WORKBENCH_URL") or "http://localhost:8080"
            ).rstrip("/"),
            "username": username,
            "password": password,
        }
    ```

=== "TypeScript"

    ```typescript
    interface Settings {
      baseUrl: string;
      username: string;
      password: string;
    }
    
    // Read the settings from the environment. The || operator, unlike ??, also
    // treats an empty variable as unset.
    function settings(): Settings {
      const username = process.env.WORKBENCH_USERNAME || "";
      const password = process.env.WORKBENCH_PASSWORD || "";
      if (!username || !password) {
        throw new Error("WORKBENCH_USERNAME and WORKBENCH_PASSWORD must be set");
      }
      const baseUrl = process.env.WORKBENCH_URL || "http://localhost:8080";
      return { baseUrl: baseUrl.replace(/\/+$/, ""), username, password };
    }
    ```

=== "Java"

    ```java
    /** The settings that the program reads from the environment. */
    record Settings(String baseUrl, String username, String password) {}
    
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
        if (username.isEmpty() || password.isEmpty()) {
            throw new IOException(
                    "WORKBENCH_USERNAME and WORKBENCH_PASSWORD must be set");
        }
        String baseUrl = envOr("WORKBENCH_URL", "http://localhost:8080")
                .replaceAll("/+$", "");
        return new Settings(baseUrl, username, password);
    }
    ```

=== "C#"

    ```csharp
    // Returns the value of an environment variable, or null if the variable
    // is unset or empty, as an unset variable would be.
    static string? EnvValue(string name) =>
        Environment.GetEnvironmentVariable(name) is { Length: > 0 } value
            ? value
            : null;
    
    // Reads the settings from the environment.
    static (string BaseUrl, string Username, string Password) Settings()
    {
        var username = EnvValue("WORKBENCH_USERNAME");
        var password = EnvValue("WORKBENCH_PASSWORD");
        if (username is null || password is null)
        {
            throw new InvalidOperationException(
                "WORKBENCH_USERNAME and WORKBENCH_PASSWORD must be set");
        }
        var baseUrl = EnvValue("WORKBENCH_URL") ?? "http://localhost:8080";
        return (baseUrl.TrimEnd('/'), username, password);
    }
    ```

=== "Go"

    ```go
    // settings holds the values that the program reads from the environment.
    type settings struct {
    	baseURL  string
    	username string
    	password string
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
    		baseURL:  strings.TrimRight(envOr("WORKBENCH_URL", "http://localhost:8080"), "/"),
    		username: os.Getenv("WORKBENCH_USERNAME"),
    		password: os.Getenv("WORKBENCH_PASSWORD"),
    	}
    	if s.username == "" || s.password == "" {
    		return s, errors.New("WORKBENCH_USERNAME and WORKBENCH_PASSWORD must be set")
    	}
    	return s, nil
    }
    
    ```

=== "Rust"

    ```rust
    /// Any error, boxed, so that a function can return errors of several types
    /// with the ? operator.
    type Result<T> = std::result::Result<T, Box<dyn Error>>;
    
    /// The settings that the program reads from the environment.
    struct Settings {
        base_url: String,
        username: String,
        password: String,
    }
    
    /// Returns the value of an environment variable, if it is set and not
    /// empty; an empty variable counts as unset.
    fn env_value(name: &str) -> Option<String> {
        env::var(name).ok().filter(|value| !value.is_empty())
    }
    
    /// Reads the settings from the environment.
    fn settings() -> Result<Settings> {
        let (Some(username), Some(password)) = (
            env_value("WORKBENCH_USERNAME"),
            env_value("WORKBENCH_PASSWORD"),
        ) else {
            return Err("WORKBENCH_USERNAME and WORKBENCH_PASSWORD must be set".into());
        };
        let base_url = env_value("WORKBENCH_URL")
            .unwrap_or_else(|| "http://localhost:8080".to_string())
            .trim_end_matches('/')
            .to_string();
        Ok(Settings {
            base_url,
            username,
            password,
        })
    }
    ```

=== "Ruby"

    ```ruby
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
      unless username && password
        raise "WORKBENCH_USERNAME and WORKBENCH_PASSWORD must be set"
      end
    
      {
        base_url: env_or("WORKBENCH_URL", "http://localhost:8080").sub(%r{/+\z}, ""),
        username: username,
        password: password
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
    ```

## Sending Requests

Every call to the API goes through one helper function. The function adds the
`/api/v1` prefix to the path, sends the token as a `Bearer` credential in the
`Authorization` header when it has one, and sets a timeout so that a stalled
server cannot hang the program. When the server rejects a request, the function
raises an error that includes the status code and the message from the server,
which is more useful than the status code alone. The following tabs show the
helper function from each program:

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

The program sends the user name and the password to `POST /api/v1/auth/login`
as a JSON object. The server sets the session token in a cookie named
`session_token` instead of returning it in the body of the reply, so each
program reads the token from the cookie. The program sends the session token in
the `Authorization` header, as it would an API token, which keeps the rest of
the program the same for both. The following tabs show how each program logs
in:

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

## Checking the User

The `GET /api/v1/user/info` call returns the user that a token belongs to, and
whether that user is a superuser. The same call works with a session token and
with an API token, so the program uses it to check each of them. The following
tabs show how each program reads the reply:

=== "Python"

    ```python
    def user_info(base_url: str, token: str) -> str:
        """Returns the user that a token belongs to, with its superuser flag."""
        info = api("GET", base_url, "/user/info", token).json()
        superuser = str(info["is_superuser"]).lower()
        return f"{info['username']} (superuser: {superuser})"
    ```

=== "TypeScript"

    ```typescript
    interface UserInfo {
      username: string;
      is_superuser: boolean;
    }
    
    // Returns the user that a token belongs to, with its superuser flag.
    async function userInfo(baseUrl: string, token: string): Promise<string> {
      const response = await api("GET", baseUrl, "/user/info", token);
      const info = (await response.json()) as UserInfo;
      return `${info.username} (superuser: ${info.is_superuser})`;
    }
    ```

=== "Java"

    ```java
    /** Returns the user that a token belongs to, with its superuser flag. */
    static String userInfo(String baseUrl, String token)
            throws IOException, InterruptedException {
        JsonNode info = JSON.readTree(
                api("GET", baseUrl, "/user/info", token, null).body());
        return info.get("username").asString() + " (superuser: "
                + info.get("is_superuser").asBoolean() + ")";
    }
    ```

=== "C#"

    ```csharp
    // Returns the user that a token belongs to, with its superuser flag.
    async Task<string> UserInfo(string baseUrl, string token)
    {
        var info = await ApiJson("GET", baseUrl, "/user/info", token);
        // A bool would print as True or False, so spell the flag out.
        var superuser = info["is_superuser"]!.GetValue<bool>() ? "true" : "false";
        return $"{info["username"]!.GetValue<string>()} (superuser: {superuser})";
    }
    ```

=== "Go"

    ```go
    // userInfo returns the user that a token belongs to, with its superuser flag.
    func userInfo(baseURL, token string) (string, error) {
    	var info struct {
    		Username    string `json:"username"`
    		IsSuperuser bool   `json:"is_superuser"`
    	}
    	if err := apiJSON("GET", baseURL, "/user/info", token, nil, &info); err != nil {
    		return "", err
    	}
    	return fmt.Sprintf("%s (superuser: %t)", info.Username, info.IsSuperuser), nil
    }
    
    ```

=== "Rust"

    ```rust
    /// Returns the user that a token belongs to, with its superuser flag.
    fn user_info(base_url: &str, token: &str) -> Result<String> {
        let info: Value = api(Method::GET, base_url, "/user/info", Some(token), None)?.json()?;
        let username = info["username"]
            .as_str()
            .ok_or("the reply had no username")?;
        let superuser = info["is_superuser"]
            .as_bool()
            .ok_or("the reply had no superuser flag")?;
        Ok(format!("{username} (superuser: {superuser})"))
    }
    ```

=== "Ruby"

    ```ruby
    # Returns the user that a token belongs to, with its superuser flag.
    def user_info(base_url, token)
      info = JSON.parse(api("GET", base_url, "/user/info", token).body)
      "#{info.fetch('username')} (superuser: #{info.fetch('is_superuser')})"
    end
    ```

=== "curl"

    ```bash
    # Prints the user that a token belongs to, as "name (superuser: flag)".
    user_info() {
        local token="$1"
        api GET /user/info "$token" |
            jq -r '"\(.username) (superuser: \(.is_superuser))"'
    }
    ```

## Creating an API Token

An API token suits a program that runs without a person present. The program
sends `POST /api/v1/rbac/tokens` with the owner, a note that says what the
token is for, and a lifetime of one hour. The server returns the value of the
token only once, in the reply to this call, so a program that needs the token
later must store it safely at this point. The following tabs show how each
program creates the token:

=== "Python"

    ```python
    def create_token(base_url: str, session: str, owner: str,
                     annotation: str) -> tuple[int, str]:
        """Creates an API token for a user and returns its ID and its value.
    
        The server shows the value only once. The token expires after an hour.
        """
        created = api("POST", base_url, "/rbac/tokens", session, json={
            "owner_username": owner,
            "annotation": annotation,
            "expires_in": "1h",
        }).json()
        return created["id"], created["token"]
    ```

=== "TypeScript"

    ```typescript
    interface CreatedToken {
      id: number;
      token: string;
    }
    
    // Creates an API token for a user and returns its ID and its value. The
    // server shows the value only once. The token expires after an hour.
    async function createToken(
      baseUrl: string,
      session: string,
      owner: string,
      annotation: string,
    ): Promise<CreatedToken> {
      const response = await api("POST", baseUrl, "/rbac/tokens", session, {
        owner_username: owner,
        annotation,
        expires_in: "1h",
      });
      return (await response.json()) as CreatedToken;
    }
    ```

=== "Java"

    ```java
    /** The ID and the value of a new API token. */
    record CreatedToken(long id, String token) {}
    
    /**
     * Creates an API token for a user and returns its ID and its value.
     * The server shows the value only once. The token expires after an
     * hour.
     */
    static CreatedToken createToken(String baseUrl, String session,
            String owner, String annotation)
            throws IOException, InterruptedException {
        JsonNode created = JSON.readTree(api("POST", baseUrl, "/rbac/tokens",
                session, Map.of(
                        "owner_username", owner,
                        "annotation", annotation,
                        "expires_in", "1h")).body());
        return new CreatedToken(created.get("id").asLong(),
                created.get("token").asString());
    }
    ```

=== "C#"

    ```csharp
    // Creates an API token for a user and returns its ID and its value. The
    // server shows the value only once. The token expires after an hour.
    async Task<(long Id, string Token)> CreateToken(string baseUrl,
        string session, string owner, string annotation)
    {
        var created = await ApiJson("POST", baseUrl, "/rbac/tokens", session,
            new { owner_username = owner, annotation, expires_in = "1h" });
        return (created["id"]!.GetValue<long>(),
            created["token"]!.GetValue<string>());
    }
    ```

=== "Go"

    ```go
    // createdToken is the part of the reply that the program needs.
    type createdToken struct {
    	ID    int64  `json:"id"`
    	Token string `json:"token"`
    }
    
    // createToken creates an API token for a user and returns its ID and its
    // value. The server shows the value only once. The token expires after an
    // hour.
    func createToken(baseURL, session, owner, annotation string) (createdToken, error) {
    	var created createdToken
    	err := apiJSON("POST", baseURL, "/rbac/tokens", session, map[string]string{
    		"owner_username": owner,
    		"annotation":     annotation,
    		"expires_in":     "1h",
    	}, &created)
    	return created, err
    }
    
    ```

=== "Rust"

    ```rust
    /// Creates an API token for a user and returns its ID and its value. The
    /// server shows the value only once. The token expires after an hour.
    fn create_token(
        base_url: &str,
        session: &str,
        owner: &str,
        annotation: &str,
    ) -> Result<(i64, String)> {
        let body = json!({
            "owner_username": owner,
            "annotation": annotation,
            "expires_in": "1h",
        });
        let created: Value = api(
            Method::POST,
            base_url,
            "/rbac/tokens",
            Some(session),
            Some(&body),
        )?
        .json()?;
        let id = created["id"].as_i64().ok_or("the reply had no token ID")?;
        let token = created["token"].as_str().ok_or("the reply had no token")?;
        Ok((id, token.to_string()))
    }
    ```

=== "Ruby"

    ```ruby
    # Creates an API token for a user and returns its ID and its value. The
    # server shows the value only once. The token expires after an hour.
    def create_token(base_url, session, owner, annotation)
      response = api("POST", base_url, "/rbac/tokens", session, {
                       owner_username: owner,
                       annotation: annotation,
                       expires_in: "1h"
                     })
      created = JSON.parse(response.body)
      [created.fetch("id"), created.fetch("token")]
    end
    ```

=== "curl"

    ```bash
    # Creates an API token for a user and prints its ID and its value, which
    # the server shows only once. The token expires after an hour.
    create_token() {
        local session="$1" owner="$2" annotation="$3"
        jq -n --arg owner "$owner" --arg annotation "$annotation" \
              '{owner_username: $owner, annotation: $annotation,
                expires_in: "1h"}' |
            api POST /rbac/tokens "$session" \
                --header 'Content-Type: application/json' --data @- |
            jq -r '"\(.id) \(.token)"'
    }
    ```

## Deleting the Token

The program deletes the token with `DELETE /api/v1/rbac/tokens/{id}`, using the
ID from the reply to the create call. Each program runs the delete step even
when an earlier step fails. The Python program uses a `finally` block and the
Ruby program an `ensure` block, the TypeScript program keeps the step in a
variable that runs after the `try` block, and the Java and C# programs keep the
token's ID in a variable that a `finally` block checks. The Go
program returns the step from its `run()` function to `main()`, the Rust
program's `run()` function records what to delete in a value that `main()`
owns, and the curl script uses an `EXIT` trap. The following tabs show how
each program deletes the token:

=== "Python"

    ```python
    def delete_token(base_url: str, session: str, token_id: int) -> None:
        """Deletes an API token by its ID."""
        api("DELETE", base_url, f"/rbac/tokens/{token_id}", session)
    ```

=== "TypeScript"

    ```typescript
    // Deletes an API token by its ID.
    async function deleteToken(
      baseUrl: string,
      session: string,
      tokenId: number,
    ): Promise<void> {
      await api("DELETE", baseUrl, `/rbac/tokens/${tokenId}`, session);
    }
    ```

=== "Java"

    ```java
    /** Deletes an API token by its ID. */
    static void deleteToken(String baseUrl, String session, long tokenId)
            throws IOException, InterruptedException {
        api("DELETE", baseUrl, "/rbac/tokens/" + tokenId, session, null);
    }
    ```

=== "C#"

    ```csharp
    // Deletes an API token by its ID.
    async Task DeleteToken(string baseUrl, string session, long tokenId)
    {
        using var response =
            await Api("DELETE", baseUrl, $"/rbac/tokens/{tokenId}", session);
    }
    ```

=== "Go"

    ```go
    // deleteToken deletes an API token by its ID.
    func deleteToken(baseURL, session string, tokenID int64) error {
    	return apiJSON("DELETE", baseURL, fmt.Sprintf("/rbac/tokens/%d", tokenID),
    		session, nil, nil)
    }
    
    ```

=== "Rust"

    ```rust
    /// Deletes an API token by its ID.
    fn delete_token(base_url: &str, session: &str, token_id: i64) -> Result<()> {
        let path = format!("/rbac/tokens/{token_id}");
        api(Method::DELETE, base_url, &path, Some(session), None)?;
        Ok(())
    }
    ```

=== "Ruby"

    ```ruby
    # Deletes an API token by its ID.
    def delete_token(base_url, session, token_id)
      api("DELETE", base_url, "/rbac/tokens/#{token_id}", session)
    end
    ```

=== "curl"

    ```bash
    # Deletes an API token by its ID.
    delete_token() {
        local session="$1" token_id="$2"
        api DELETE "/rbac/tokens/$token_id" "$session" >/dev/null
    }
    ```

## Putting It Together

The main part of each program logs in, checks the session token, creates the
API token, checks the API token, and then deletes it. The program reports any
failure on `stderr` and exits with a non-zero status. The following tabs show
the main part of each program:

=== "Python"

    ```python
    def main() -> int:
        token_id = None
        status = 0
        try:
            config = settings()
            base_url = config["base_url"]
    
            session = login(base_url, config["username"], config["password"])
            print("Logged in with a session token")
            print(f"Session token belongs to {user_info(base_url, session)}")
    
            token_id, api_token = create_token(
                base_url, session, config["username"], "cookbook-authenticate"
            )
            print("Created the API token 'cookbook-authenticate'")
            print(f"API token belongs to {user_info(base_url, api_token)}")
        # httpx.HTTPError covers failures to connect, and RuntimeError covers
        # replies that the server rejected or that lacked what we need.
        except (httpx.HTTPError, RuntimeError) as e:
            print(f"Error: {e}", file=sys.stderr)
            status = 1
        finally:
            # Delete the token whether or not a later step failed, so that a
            # failed run does not leave a token behind. A return statement in a
            # finally block would hide an exception that is still in flight, so
            # this block sets the exit status instead.
            if token_id is not None:
                try:
                    delete_token(base_url, session, token_id)
                    print("Deleted the API token")
                except (httpx.HTTPError, RuntimeError) as e:
                    print(f"Error: could not delete the token: {e}",
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
        const { baseUrl, username, password } = settings();
    
        const session = await login(baseUrl, username, password);
        console.log("Logged in with a session token");
        console.log(`Session token belongs to ${await userInfo(baseUrl, session)}`);
    
        const created = await createToken(
          baseUrl,
          session,
          username,
          "cookbook-authenticate",
        );
        // Delete the token whether or not a later step fails, so that a failed
        // run does not leave a token behind.
        cleanup = () => deleteToken(baseUrl, session, created.id);
        console.log("Created the API token 'cookbook-authenticate'");
        console.log(
          `API token belongs to ${await userInfo(baseUrl, created.token)}`,
        );
      } catch (err) {
        console.error(`Error: ${err instanceof Error ? err.message : err}`);
        exitCode = 1;
      }
    
      if (cleanup) {
        try {
          await cleanup();
          console.log("Deleted the API token");
        } catch (err) {
          console.error(
            `Error: could not delete the token: ${
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
        CreatedToken created = null;
        try {
            Settings settings = settings();
            baseUrl = settings.baseUrl();
    
            session = login(baseUrl, settings.username(),
                    settings.password());
            System.out.println("Logged in with a session token");
            System.out.println("Session token belongs to "
                    + userInfo(baseUrl, session));
    
            created = createToken(baseUrl, session, settings.username(),
                    "cookbook-authenticate");
            System.out.println(
                    "Created the API token 'cookbook-authenticate'");
            System.out.println("API token belongs to "
                    + userInfo(baseUrl, created.token()));
        // IOException covers failures to connect, replies that the server
        // rejected, and replies that lacked what we need; the client
        // throws InterruptedException if the thread is interrupted, and
        // Jackson throws JacksonException for a reply that is not JSON.
        } catch (IOException | InterruptedException | JacksonException e) {
            System.err.println("Error: " + describe(e));
            status = 1;
        } finally {
            // Delete the token whether or not a later step failed, so that a
            // failed run does not leave a token behind. The finally block also
            // runs for an error that the catch does not handle.
            if (created != null) {
                try {
                    deleteToken(baseUrl, session, created.id());
                    System.out.println("Deleted the API token");
                } catch (IOException | InterruptedException
                        | JacksonException e) {
                    System.err.println("Error: could not delete the token: "
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
    long? tokenId = null;
    try
    {
        var (url, username, password) = Settings();
        baseUrl = url;
    
        session = await Login(baseUrl, username, password);
        Console.WriteLine("Logged in with a session token");
        Console.WriteLine(
            $"Session token belongs to {await UserInfo(baseUrl, session)}");
    
        var created = await CreateToken(baseUrl, session, username,
            "cookbook-authenticate");
        tokenId = created.Id;
        Console.WriteLine("Created the API token 'cookbook-authenticate'");
        Console.WriteLine(
            $"API token belongs to {await UserInfo(baseUrl, created.Token)}");
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
        // Delete the token whether or not a later step failed, so that a failed
        // run does not leave a token behind. The finally block also runs for an
        // error that the catch does not handle.
        if (tokenId is not null)
        {
            try
            {
                await DeleteToken(baseUrl, session, tokenId.Value);
                Console.WriteLine("Deleted the API token");
            }
            catch (Exception e) when (e is HttpRequestException
                or TaskCanceledException)
            {
                Console.Error.WriteLine(
                    $"Error: could not delete the token: {e.Message}");
                status = 1;
            }
        }
    }
    
    return status;
    ```

=== "Go"

    ```go
    // run does the work and returns the cleanup that the caller must run, if a
    // token was created.
    func run(s settings) (cleanup func() error, err error) {
    	session, err := login(s.baseURL, s.username, s.password)
    	if err != nil {
    		return nil, err
    	}
    	fmt.Println("Logged in with a session token")
    	who, err := userInfo(s.baseURL, session)
    	if err != nil {
    		return nil, err
    	}
    	fmt.Println("Session token belongs to", who)
    
    	created, err := createToken(s.baseURL, session, s.username, "cookbook-authenticate")
    	if err != nil {
    		return nil, err
    	}
    	// Return the cleanup before any later step can fail, so that a failed
    	// run does not leave a token behind.
    	cleanup = func() error { return deleteToken(s.baseURL, session, created.ID) }
    	fmt.Println("Created the API token 'cookbook-authenticate'")
    	who, err = userInfo(s.baseURL, created.Token)
    	if err != nil {
    		return cleanup, err
    	}
    	fmt.Println("API token belongs to", who)
    	return cleanup, nil
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
    			fmt.Fprintln(os.Stderr, "Error: could not delete the token:", err)
    			failed = true
    		} else {
    			fmt.Println("Deleted the API token")
    		}
    	}
    	if failed {
    		os.Exit(1)
    	}
    }
    
    ```

=== "Rust"

    ```rust
    /// What the program must delete when it finishes: the token's ID, and the
    /// session token that has the right to delete it.
    struct Cleanup {
        session: String,
        token_id: i64,
    }
    
    /// Does the work. Once it has created a token, it records the token in
    /// cleanup, so that main deletes the token even if a later step fails.
    fn run(s: &Settings, cleanup: &mut Option<Cleanup>) -> Result<()> {
        let session = login(&s.base_url, &s.username, &s.password)?;
        println!("Logged in with a session token");
        println!(
            "Session token belongs to {}",
            user_info(&s.base_url, &session)?
        );
    
        let (token_id, api_token) =
            create_token(&s.base_url, &session, &s.username, "cookbook-authenticate")?;
        *cleanup = Some(Cleanup { session, token_id });
        println!("Created the API token 'cookbook-authenticate'");
        println!(
            "API token belongs to {}",
            user_info(&s.base_url, &api_token)?
        );
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
    
        // Delete the token whether or not a later step failed, so that a
        // failed run does not leave a token behind.
        if let Some(c) = cleanup {
            match delete_token(&s.base_url, &c.session, c.token_id) {
                Ok(()) => println!("Deleted the API token"),
                Err(e) => {
                    report("Error: could not delete the token: ", e.as_ref());
                    status = ExitCode::FAILURE;
                }
            }
        }
        status
    }
    ```

=== "Ruby"

    ```ruby
    def main
      token_id = nil
      status = 0
      begin
        config = settings
        base_url = config[:base_url]
    
        session = login(base_url, config[:username], config[:password])
        puts "Logged in with a session token"
        puts "Session token belongs to #{user_info(base_url, session)}"
    
        token_id, api_token = create_token(base_url, session, config[:username],
                                           "cookbook-authenticate")
        puts "Created the API token 'cookbook-authenticate'"
        puts "API token belongs to #{user_info(base_url, api_token)}"
      # Net::HTTP raises errors of many classes, such as SystemCallError for a
      # refused connection and Net::OpenTimeout for a timeout, and the program
      # raises RuntimeError for replies that the server rejected or that lacked
      # what we need, so this catches StandardError, their common ancestor.
      rescue StandardError => e
        warn "Error: #{e.message}"
        status = 1
      ensure
        # Delete the token whether or not a later step failed, so that a
        # failed run does not leave a token behind.
        if token_id
          begin
            delete_token(base_url, session, token_id)
            puts "Deleted the API token"
          rescue StandardError => e
            warn "Error: could not delete the token: #{e.message}"
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
    token_id=""
    
    cleanup() {
        local status=$?
        # Delete the token when the script ends, even if a later step failed,
        # so that a failed run does not leave a token behind. Report a delete
        # that fails, and make the exit status non-zero.
        if [[ -n "$token_id" ]]; then
            delete_token "$session" "$token_id" || {
                echo "Error: could not delete the API token" >&2
                status=1
            }
        fi
        exit "$status"
    }
    
    main() {
        local who created api_token
        session=$(login)
        echo "Logged in with a session token"
        # Assign the result first: a failure inside a command substitution that
        # is an argument of echo would not stop the script.
        who=$(user_info "$session")
        echo "Session token belongs to $who"
    
        created=$(create_token "$session" "$WORKBENCH_USERNAME" \
                               "cookbook-authenticate")
        token_id="${created%% *}"
        api_token="${created#* }"
        echo "Created the API token 'cookbook-authenticate'"
        who=$(user_info "$api_token")
        echo "API token belongs to $who"
    
        delete_token "$session" "$token_id"
        token_id=""
        echo "Deleted the API token"
    }
    
    trap cleanup EXIT
    main
    ```

## Running the Example

The complete project for each language is available in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/ai_dba_workbench/authenticate).
Set `WORKBENCH_URL`, `WORKBENCH_USERNAME`, and `WORKBENCH_PASSWORD` for your
server, and then run the command for your language from the corresponding
project directory. The following tabs show the commands that build and run each
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
    Authenticating with the AI DBA Workbench API, using httpx.
    
    Copyright (c) 2026, pgEdge, Inc.
    This code is released under the PostgreSQL License.
    """
    
    import os
    import sys
    
    import httpx
    
    
    def settings() -> dict:
        """Reads the settings from the environment.
    
        The or operator treats an empty variable as unset.
        """
        username = os.environ.get("WORKBENCH_USERNAME") or ""
        password = os.environ.get("WORKBENCH_PASSWORD") or ""
        if not username or not password:
            raise RuntimeError(
                "WORKBENCH_USERNAME and WORKBENCH_PASSWORD must be set"
            )
        return {
            "base_url": (
                os.environ.get("WORKBENCH_URL") or "http://localhost:8080"
            ).rstrip("/"),
            "username": username,
            "password": password,
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
    
    
    def user_info(base_url: str, token: str) -> str:
        """Returns the user that a token belongs to, with its superuser flag."""
        info = api("GET", base_url, "/user/info", token).json()
        superuser = str(info["is_superuser"]).lower()
        return f"{info['username']} (superuser: {superuser})"
    
    
    def create_token(base_url: str, session: str, owner: str,
                     annotation: str) -> tuple[int, str]:
        """Creates an API token for a user and returns its ID and its value.
    
        The server shows the value only once. The token expires after an hour.
        """
        created = api("POST", base_url, "/rbac/tokens", session, json={
            "owner_username": owner,
            "annotation": annotation,
            "expires_in": "1h",
        }).json()
        return created["id"], created["token"]
    
    
    def delete_token(base_url: str, session: str, token_id: int) -> None:
        """Deletes an API token by its ID."""
        api("DELETE", base_url, f"/rbac/tokens/{token_id}", session)
    
    
    def main() -> int:
        token_id = None
        status = 0
        try:
            config = settings()
            base_url = config["base_url"]
    
            session = login(base_url, config["username"], config["password"])
            print("Logged in with a session token")
            print(f"Session token belongs to {user_info(base_url, session)}")
    
            token_id, api_token = create_token(
                base_url, session, config["username"], "cookbook-authenticate"
            )
            print("Created the API token 'cookbook-authenticate'")
            print(f"API token belongs to {user_info(base_url, api_token)}")
        # httpx.HTTPError covers failures to connect, and RuntimeError covers
        # replies that the server rejected or that lacked what we need.
        except (httpx.HTTPError, RuntimeError) as e:
            print(f"Error: {e}", file=sys.stderr)
            status = 1
        finally:
            # Delete the token whether or not a later step failed, so that a
            # failed run does not leave a token behind. A return statement in a
            # finally block would hide an exception that is still in flight, so
            # this block sets the exit status instead.
            if token_id is not None:
                try:
                    delete_token(base_url, session, token_id)
                    print("Deleted the API token")
                except (httpx.HTTPError, RuntimeError) as e:
                    print(f"Error: could not delete the token: {e}",
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
     * Authenticating with the AI DBA Workbench API, using the built-in fetch.
     *
     * Copyright (c) 2026, pgEdge, Inc.
     * This code is released under the PostgreSQL License.
     */
    
    // The program needs no imports: fetch and process are built in to Node.js.
    
    interface Settings {
      baseUrl: string;
      username: string;
      password: string;
    }
    
    // Read the settings from the environment. The || operator, unlike ??, also
    // treats an empty variable as unset.
    function settings(): Settings {
      const username = process.env.WORKBENCH_USERNAME || "";
      const password = process.env.WORKBENCH_PASSWORD || "";
      if (!username || !password) {
        throw new Error("WORKBENCH_USERNAME and WORKBENCH_PASSWORD must be set");
      }
      const baseUrl = process.env.WORKBENCH_URL || "http://localhost:8080";
      return { baseUrl: baseUrl.replace(/\/+$/, ""), username, password };
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
    
    interface UserInfo {
      username: string;
      is_superuser: boolean;
    }
    
    // Returns the user that a token belongs to, with its superuser flag.
    async function userInfo(baseUrl: string, token: string): Promise<string> {
      const response = await api("GET", baseUrl, "/user/info", token);
      const info = (await response.json()) as UserInfo;
      return `${info.username} (superuser: ${info.is_superuser})`;
    }
    
    interface CreatedToken {
      id: number;
      token: string;
    }
    
    // Creates an API token for a user and returns its ID and its value. The
    // server shows the value only once. The token expires after an hour.
    async function createToken(
      baseUrl: string,
      session: string,
      owner: string,
      annotation: string,
    ): Promise<CreatedToken> {
      const response = await api("POST", baseUrl, "/rbac/tokens", session, {
        owner_username: owner,
        annotation,
        expires_in: "1h",
      });
      return (await response.json()) as CreatedToken;
    }
    
    // Deletes an API token by its ID.
    async function deleteToken(
      baseUrl: string,
      session: string,
      tokenId: number,
    ): Promise<void> {
      await api("DELETE", baseUrl, `/rbac/tokens/${tokenId}`, session);
    }
    
    async function main(): Promise<number> {
      let exitCode = 0;
      let cleanup: (() => Promise<void>) | undefined;
      try {
        const { baseUrl, username, password } = settings();
    
        const session = await login(baseUrl, username, password);
        console.log("Logged in with a session token");
        console.log(`Session token belongs to ${await userInfo(baseUrl, session)}`);
    
        const created = await createToken(
          baseUrl,
          session,
          username,
          "cookbook-authenticate",
        );
        // Delete the token whether or not a later step fails, so that a failed
        // run does not leave a token behind.
        cleanup = () => deleteToken(baseUrl, session, created.id);
        console.log("Created the API token 'cookbook-authenticate'");
        console.log(
          `API token belongs to ${await userInfo(baseUrl, created.token)}`,
        );
      } catch (err) {
        console.error(`Error: ${err instanceof Error ? err.message : err}`);
        exitCode = 1;
      }
    
      if (cleanup) {
        try {
          await cleanup();
          console.log("Deleted the API token");
        } catch (err) {
          console.error(
            `Error: could not delete the token: ${
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
     * Authenticating with the AI DBA Workbench API, using java.net.http and
     * Jackson.
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
    
    public class Main {
    
        /** The settings that the program reads from the environment. */
        record Settings(String baseUrl, String username, String password) {}
    
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
            if (username.isEmpty() || password.isEmpty()) {
                throw new IOException(
                        "WORKBENCH_USERNAME and WORKBENCH_PASSWORD must be set");
            }
            String baseUrl = envOr("WORKBENCH_URL", "http://localhost:8080")
                    .replaceAll("/+$", "");
            return new Settings(baseUrl, username, password);
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
    
        /** Returns the user that a token belongs to, with its superuser flag. */
        static String userInfo(String baseUrl, String token)
                throws IOException, InterruptedException {
            JsonNode info = JSON.readTree(
                    api("GET", baseUrl, "/user/info", token, null).body());
            return info.get("username").asString() + " (superuser: "
                    + info.get("is_superuser").asBoolean() + ")";
        }
    
        /** The ID and the value of a new API token. */
        record CreatedToken(long id, String token) {}
    
        /**
         * Creates an API token for a user and returns its ID and its value.
         * The server shows the value only once. The token expires after an
         * hour.
         */
        static CreatedToken createToken(String baseUrl, String session,
                String owner, String annotation)
                throws IOException, InterruptedException {
            JsonNode created = JSON.readTree(api("POST", baseUrl, "/rbac/tokens",
                    session, Map.of(
                            "owner_username", owner,
                            "annotation", annotation,
                            "expires_in", "1h")).body());
            return new CreatedToken(created.get("id").asLong(),
                    created.get("token").asString());
        }
    
        /** Deletes an API token by its ID. */
        static void deleteToken(String baseUrl, String session, long tokenId)
                throws IOException, InterruptedException {
            api("DELETE", baseUrl, "/rbac/tokens/" + tokenId, session, null);
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
            CreatedToken created = null;
            try {
                Settings settings = settings();
                baseUrl = settings.baseUrl();
    
                session = login(baseUrl, settings.username(),
                        settings.password());
                System.out.println("Logged in with a session token");
                System.out.println("Session token belongs to "
                        + userInfo(baseUrl, session));
    
                created = createToken(baseUrl, session, settings.username(),
                        "cookbook-authenticate");
                System.out.println(
                        "Created the API token 'cookbook-authenticate'");
                System.out.println("API token belongs to "
                        + userInfo(baseUrl, created.token()));
            // IOException covers failures to connect, replies that the server
            // rejected, and replies that lacked what we need; the client
            // throws InterruptedException if the thread is interrupted, and
            // Jackson throws JacksonException for a reply that is not JSON.
            } catch (IOException | InterruptedException | JacksonException e) {
                System.err.println("Error: " + describe(e));
                status = 1;
            } finally {
                // Delete the token whether or not a later step failed, so that a
                // failed run does not leave a token behind. The finally block also
                // runs for an error that the catch does not handle.
                if (created != null) {
                    try {
                        deleteToken(baseUrl, session, created.id());
                        System.out.println("Deleted the API token");
                    } catch (IOException | InterruptedException
                            | JacksonException e) {
                        System.err.println("Error: could not delete the token: "
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
     * Authenticating with the AI DBA Workbench API, using HttpClient and
     * System.Text.Json.
     *
     * Copyright (c) 2026, pgEdge, Inc.
     * This code is released under the PostgreSQL License.
     */
    
    using System.Net.Http.Headers;
    using System.Net.Http.Json;
    using System.Text.Json;
    using System.Text.Json.Nodes;
    using System.Text.RegularExpressions;
    
    // Returns the value of an environment variable, or null if the variable
    // is unset or empty, as an unset variable would be.
    static string? EnvValue(string name) =>
        Environment.GetEnvironmentVariable(name) is { Length: > 0 } value
            ? value
            : null;
    
    // Reads the settings from the environment.
    static (string BaseUrl, string Username, string Password) Settings()
    {
        var username = EnvValue("WORKBENCH_USERNAME");
        var password = EnvValue("WORKBENCH_PASSWORD");
        if (username is null || password is null)
        {
            throw new InvalidOperationException(
                "WORKBENCH_USERNAME and WORKBENCH_PASSWORD must be set");
        }
        var baseUrl = EnvValue("WORKBENCH_URL") ?? "http://localhost:8080";
        return (baseUrl.TrimEnd('/'), username, password);
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
    
    // Returns the user that a token belongs to, with its superuser flag.
    async Task<string> UserInfo(string baseUrl, string token)
    {
        var info = await ApiJson("GET", baseUrl, "/user/info", token);
        // A bool would print as True or False, so spell the flag out.
        var superuser = info["is_superuser"]!.GetValue<bool>() ? "true" : "false";
        return $"{info["username"]!.GetValue<string>()} (superuser: {superuser})";
    }
    
    // Creates an API token for a user and returns its ID and its value. The
    // server shows the value only once. The token expires after an hour.
    async Task<(long Id, string Token)> CreateToken(string baseUrl,
        string session, string owner, string annotation)
    {
        var created = await ApiJson("POST", baseUrl, "/rbac/tokens", session,
            new { owner_username = owner, annotation, expires_in = "1h" });
        return (created["id"]!.GetValue<long>(),
            created["token"]!.GetValue<string>());
    }
    
    // Deletes an API token by its ID.
    async Task DeleteToken(string baseUrl, string session, long tokenId)
    {
        using var response =
            await Api("DELETE", baseUrl, $"/rbac/tokens/{tokenId}", session);
    }
    
    var status = 0;
    var baseUrl = "";
    var session = "";
    long? tokenId = null;
    try
    {
        var (url, username, password) = Settings();
        baseUrl = url;
    
        session = await Login(baseUrl, username, password);
        Console.WriteLine("Logged in with a session token");
        Console.WriteLine(
            $"Session token belongs to {await UserInfo(baseUrl, session)}");
    
        var created = await CreateToken(baseUrl, session, username,
            "cookbook-authenticate");
        tokenId = created.Id;
        Console.WriteLine("Created the API token 'cookbook-authenticate'");
        Console.WriteLine(
            $"API token belongs to {await UserInfo(baseUrl, created.Token)}");
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
        // Delete the token whether or not a later step failed, so that a failed
        // run does not leave a token behind. The finally block also runs for an
        // error that the catch does not handle.
        if (tokenId is not null)
        {
            try
            {
                await DeleteToken(baseUrl, session, tokenId.Value);
                Console.WriteLine("Deleted the API token");
            }
            catch (Exception e) when (e is HttpRequestException
                or TaskCanceledException)
            {
                Console.Error.WriteLine(
                    $"Error: could not delete the token: {e.Message}");
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
     * Authenticating with the AI DBA Workbench API, using net/http.
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
    
    
    // settings holds the values that the program reads from the environment.
    type settings struct {
    	baseURL  string
    	username string
    	password string
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
    		baseURL:  strings.TrimRight(envOr("WORKBENCH_URL", "http://localhost:8080"), "/"),
    		username: os.Getenv("WORKBENCH_USERNAME"),
    		password: os.Getenv("WORKBENCH_PASSWORD"),
    	}
    	if s.username == "" || s.password == "" {
    		return s, errors.New("WORKBENCH_USERNAME and WORKBENCH_PASSWORD must be set")
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
    
    
    // userInfo returns the user that a token belongs to, with its superuser flag.
    func userInfo(baseURL, token string) (string, error) {
    	var info struct {
    		Username    string `json:"username"`
    		IsSuperuser bool   `json:"is_superuser"`
    	}
    	if err := apiJSON("GET", baseURL, "/user/info", token, nil, &info); err != nil {
    		return "", err
    	}
    	return fmt.Sprintf("%s (superuser: %t)", info.Username, info.IsSuperuser), nil
    }
    
    
    // createdToken is the part of the reply that the program needs.
    type createdToken struct {
    	ID    int64  `json:"id"`
    	Token string `json:"token"`
    }
    
    // createToken creates an API token for a user and returns its ID and its
    // value. The server shows the value only once. The token expires after an
    // hour.
    func createToken(baseURL, session, owner, annotation string) (createdToken, error) {
    	var created createdToken
    	err := apiJSON("POST", baseURL, "/rbac/tokens", session, map[string]string{
    		"owner_username": owner,
    		"annotation":     annotation,
    		"expires_in":     "1h",
    	}, &created)
    	return created, err
    }
    
    
    // deleteToken deletes an API token by its ID.
    func deleteToken(baseURL, session string, tokenID int64) error {
    	return apiJSON("DELETE", baseURL, fmt.Sprintf("/rbac/tokens/%d", tokenID),
    		session, nil, nil)
    }
    
    
    // run does the work and returns the cleanup that the caller must run, if a
    // token was created.
    func run(s settings) (cleanup func() error, err error) {
    	session, err := login(s.baseURL, s.username, s.password)
    	if err != nil {
    		return nil, err
    	}
    	fmt.Println("Logged in with a session token")
    	who, err := userInfo(s.baseURL, session)
    	if err != nil {
    		return nil, err
    	}
    	fmt.Println("Session token belongs to", who)
    
    	created, err := createToken(s.baseURL, session, s.username, "cookbook-authenticate")
    	if err != nil {
    		return nil, err
    	}
    	// Return the cleanup before any later step can fail, so that a failed
    	// run does not leave a token behind.
    	cleanup = func() error { return deleteToken(s.baseURL, session, created.ID) }
    	fmt.Println("Created the API token 'cookbook-authenticate'")
    	who, err = userInfo(s.baseURL, created.Token)
    	if err != nil {
    		return cleanup, err
    	}
    	fmt.Println("API token belongs to", who)
    	return cleanup, nil
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
    			fmt.Fprintln(os.Stderr, "Error: could not delete the token:", err)
    			failed = true
    		} else {
    			fmt.Println("Deleted the API token")
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
    // Authenticating with the AI DBA Workbench API, using reqwest and
    // serde_json.
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
    
    /// Any error, boxed, so that a function can return errors of several types
    /// with the ? operator.
    type Result<T> = std::result::Result<T, Box<dyn Error>>;
    
    /// The settings that the program reads from the environment.
    struct Settings {
        base_url: String,
        username: String,
        password: String,
    }
    
    /// Returns the value of an environment variable, if it is set and not
    /// empty; an empty variable counts as unset.
    fn env_value(name: &str) -> Option<String> {
        env::var(name).ok().filter(|value| !value.is_empty())
    }
    
    /// Reads the settings from the environment.
    fn settings() -> Result<Settings> {
        let (Some(username), Some(password)) = (
            env_value("WORKBENCH_USERNAME"),
            env_value("WORKBENCH_PASSWORD"),
        ) else {
            return Err("WORKBENCH_USERNAME and WORKBENCH_PASSWORD must be set".into());
        };
        let base_url = env_value("WORKBENCH_URL")
            .unwrap_or_else(|| "http://localhost:8080".to_string())
            .trim_end_matches('/')
            .to_string();
        Ok(Settings {
            base_url,
            username,
            password,
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
    
    /// Returns the user that a token belongs to, with its superuser flag.
    fn user_info(base_url: &str, token: &str) -> Result<String> {
        let info: Value = api(Method::GET, base_url, "/user/info", Some(token), None)?.json()?;
        let username = info["username"]
            .as_str()
            .ok_or("the reply had no username")?;
        let superuser = info["is_superuser"]
            .as_bool()
            .ok_or("the reply had no superuser flag")?;
        Ok(format!("{username} (superuser: {superuser})"))
    }
    
    /// Creates an API token for a user and returns its ID and its value. The
    /// server shows the value only once. The token expires after an hour.
    fn create_token(
        base_url: &str,
        session: &str,
        owner: &str,
        annotation: &str,
    ) -> Result<(i64, String)> {
        let body = json!({
            "owner_username": owner,
            "annotation": annotation,
            "expires_in": "1h",
        });
        let created: Value = api(
            Method::POST,
            base_url,
            "/rbac/tokens",
            Some(session),
            Some(&body),
        )?
        .json()?;
        let id = created["id"].as_i64().ok_or("the reply had no token ID")?;
        let token = created["token"].as_str().ok_or("the reply had no token")?;
        Ok((id, token.to_string()))
    }
    
    /// Deletes an API token by its ID.
    fn delete_token(base_url: &str, session: &str, token_id: i64) -> Result<()> {
        let path = format!("/rbac/tokens/{token_id}");
        api(Method::DELETE, base_url, &path, Some(session), None)?;
        Ok(())
    }
    
    /// What the program must delete when it finishes: the token's ID, and the
    /// session token that has the right to delete it.
    struct Cleanup {
        session: String,
        token_id: i64,
    }
    
    /// Does the work. Once it has created a token, it records the token in
    /// cleanup, so that main deletes the token even if a later step fails.
    fn run(s: &Settings, cleanup: &mut Option<Cleanup>) -> Result<()> {
        let session = login(&s.base_url, &s.username, &s.password)?;
        println!("Logged in with a session token");
        println!(
            "Session token belongs to {}",
            user_info(&s.base_url, &session)?
        );
    
        let (token_id, api_token) =
            create_token(&s.base_url, &session, &s.username, "cookbook-authenticate")?;
        *cleanup = Some(Cleanup { session, token_id });
        println!("Created the API token 'cookbook-authenticate'");
        println!(
            "API token belongs to {}",
            user_info(&s.base_url, &api_token)?
        );
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
    
        // Delete the token whether or not a later step failed, so that a
        // failed run does not leave a token behind.
        if let Some(c) = cleanup {
            match delete_token(&s.base_url, &c.session, c.token_id) {
                Ok(()) => println!("Deleted the API token"),
                Err(e) => {
                    report("Error: could not delete the token: ", e.as_ref());
                    status = ExitCode::FAILURE;
                }
            }
        }
        status
    }
    
    ```

=== "Ruby"

    ```ruby
    # Ellie's Postgres Cookbook
    # Authenticating with the AI DBA Workbench API, using Net::HTTP.
    #
    # Copyright (c) 2026, pgEdge, Inc.
    # This code is released under the PostgreSQL License.
    
    require "json"
    require "net/http"
    
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
      unless username && password
        raise "WORKBENCH_USERNAME and WORKBENCH_PASSWORD must be set"
      end
    
      {
        base_url: env_or("WORKBENCH_URL", "http://localhost:8080").sub(%r{/+\z}, ""),
        username: username,
        password: password
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
    
    # Returns the user that a token belongs to, with its superuser flag.
    def user_info(base_url, token)
      info = JSON.parse(api("GET", base_url, "/user/info", token).body)
      "#{info.fetch('username')} (superuser: #{info.fetch('is_superuser')})"
    end
    
    # Creates an API token for a user and returns its ID and its value. The
    # server shows the value only once. The token expires after an hour.
    def create_token(base_url, session, owner, annotation)
      response = api("POST", base_url, "/rbac/tokens", session, {
                       owner_username: owner,
                       annotation: annotation,
                       expires_in: "1h"
                     })
      created = JSON.parse(response.body)
      [created.fetch("id"), created.fetch("token")]
    end
    
    # Deletes an API token by its ID.
    def delete_token(base_url, session, token_id)
      api("DELETE", base_url, "/rbac/tokens/#{token_id}", session)
    end
    
    def main
      token_id = nil
      status = 0
      begin
        config = settings
        base_url = config[:base_url]
    
        session = login(base_url, config[:username], config[:password])
        puts "Logged in with a session token"
        puts "Session token belongs to #{user_info(base_url, session)}"
    
        token_id, api_token = create_token(base_url, session, config[:username],
                                           "cookbook-authenticate")
        puts "Created the API token 'cookbook-authenticate'"
        puts "API token belongs to #{user_info(base_url, api_token)}"
      # Net::HTTP raises errors of many classes, such as SystemCallError for a
      # refused connection and Net::OpenTimeout for a timeout, and the program
      # raises RuntimeError for replies that the server rejected or that lacked
      # what we need, so this catches StandardError, their common ancestor.
      rescue StandardError => e
        warn "Error: #{e.message}"
        status = 1
      ensure
        # Delete the token whether or not a later step failed, so that a
        # failed run does not leave a token behind.
        if token_id
          begin
            delete_token(base_url, session, token_id)
            puts "Deleted the API token"
          rescue StandardError => e
            warn "Error: could not delete the token: #{e.message}"
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
    # Authenticating with the AI DBA Workbench API, using curl and jq.
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
    
    # Prints the user that a token belongs to, as "name (superuser: flag)".
    user_info() {
        local token="$1"
        api GET /user/info "$token" |
            jq -r '"\(.username) (superuser: \(.is_superuser))"'
    }
    
    # Creates an API token for a user and prints its ID and its value, which
    # the server shows only once. The token expires after an hour.
    create_token() {
        local session="$1" owner="$2" annotation="$3"
        jq -n --arg owner "$owner" --arg annotation "$annotation" \
              '{owner_username: $owner, annotation: $annotation,
                expires_in: "1h"}' |
            api POST /rbac/tokens "$session" \
                --header 'Content-Type: application/json' --data @- |
            jq -r '"\(.id) \(.token)"'
    }
    
    # Deletes an API token by its ID.
    delete_token() {
        local session="$1" token_id="$2"
        api DELETE "/rbac/tokens/$token_id" "$session" >/dev/null
    }
    
    # These variables are global, because the EXIT trap runs after main returns.
    session=""
    token_id=""
    
    cleanup() {
        local status=$?
        # Delete the token when the script ends, even if a later step failed,
        # so that a failed run does not leave a token behind. Report a delete
        # that fails, and make the exit status non-zero.
        if [[ -n "$token_id" ]]; then
            delete_token "$session" "$token_id" || {
                echo "Error: could not delete the API token" >&2
                status=1
            }
        fi
        exit "$status"
    }
    
    main() {
        local who created api_token
        session=$(login)
        echo "Logged in with a session token"
        # Assign the result first: a failure inside a command substitution that
        # is an argument of echo would not stop the script.
        who=$(user_info "$session")
        echo "Session token belongs to $who"
    
        created=$(create_token "$session" "$WORKBENCH_USERNAME" \
                               "cookbook-authenticate")
        token_id="${created%% *}"
        api_token="${created#* }"
        echo "Created the API token 'cookbook-authenticate'"
        who=$(user_info "$api_token")
        echo "API token belongs to $who"
    
        delete_token "$session" "$token_id"
        token_id=""
        echo "Deleted the API token"
    }
    
    trap cleanup EXIT
    main
    
    ```

## Next Steps

The following resources provide more information about the topics in this
recipe:

- The [Registering a Server](register_server.md) recipe uses the session token
  from this recipe to register a server for monitoring.
- The [Listing and Acknowledging Alerts](alerts.md) recipe uses an API token to
  manage alerts.
- The AI DBA Workbench
  [API reference](https://github.com/pgEdge/ai-dba-workbench/blob/v1.0.0/docs/admin-guide/api/reference.md)
  describes every endpoint.
