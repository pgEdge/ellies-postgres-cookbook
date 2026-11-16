# Getting an Access Token

This recipe shows how to authenticate to the pgEdge Starfleet API. The program
exchanges an API client ID and secret for an access token, and then prints the
type of the token, its length, and its lifetime. The program never prints the
token itself, because anyone who holds a token can use your account until it
expires.

These examples are for the pgEdge Starfleet Managed API v1.

The programs print three lines. The token length and lifetime vary, so the
output looks similar to the following:

```text
Token type: Bearer
Token length: 1032 characters
Expires in: 86400 seconds
```

## Preparing the Ingredients

You need a pgEdge Starfleet account and an API client with its client ID and
secret. Never put the client secret in a file that you commit to version
control, and never paste it into a command line, because other users of the
machine can read the command lines of running processes. The programs in this
recipe read the secret from the environment and, for the curl script, pass it
to curl on standard input.

The following table lists the HTTP client and the JSON library that each
example uses:

| Language   | HTTP client and JSON library                                   |
|------------|----------------------------------------------------------------|
| Python     | [httpx](https://www.python-httpx.org/) and the `json` module   |
| TypeScript | The `fetch` function that Node.js provides                     |
| Java       | The `java.net.http` client and [Jackson](https://github.com/FasterXML/jackson) |
| C#         | `HttpClient` and `System.Text.Json`, which are part of .NET    |
| Go         | The `net/http` and `encoding/json` standard library packages   |
| Rust       | [reqwest](https://docs.rs/reqwest) and [serde_json](https://docs.rs/serde_json) |
| Ruby       | `Net::HTTP` and `json`, which come with Ruby                   |

The curl script needs `curl` and `jq`. The following excerpts show the
dependencies of each example project:

=== "Python"

    ```text
    # httpx is an HTTP client with a clean, requests-like interface.
    httpx>=0.28,<1
    ```

=== "TypeScript"

    ```json
    {
      "name": "starfleet-access-token",
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
    // The program uses only the Go standard library, so it has no
    // dependencies to declare.
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

The following code shows the imports and, for the curl script, the check for
the tools that it needs:

=== "Python"

    ```python
    import os
    import sys
    
    import httpx
    ```

=== "TypeScript"

    ```typescript
    // Node.js provides fetch as a global function, so the only import is the
    // process object, which holds the environment and the exit status.
    import process from "node:process";
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
    import tools.jackson.core.JacksonException;
    import tools.jackson.databind.JsonNode;
    import tools.jackson.databind.ObjectMapper;
    ```

=== "C#"

    ```csharp
    using System.Text;
    using System.Text.Json;
    using System.Text.Json.Nodes;
    ```

=== "Go"

    ```go
    import (
    	"bytes"
    	"context"
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
    use std::time::Duration;
    
    use reqwest::blocking::Client;
    use serde_json::{json, Value};
    ```

=== "Ruby"

    ```ruby
    require "json"
    require "net/http"
    ```

=== "curl"

    ```bash
    # Stop at the first failed command or unset variable, and make a failure
    # anywhere in a pipeline fail the whole pipeline.
    set -euo pipefail
    
    # The script needs curl to call the API and jq to read the JSON replies.
    for tool in curl jq; do
        command -v "$tool" >/dev/null || { echo "Error: $tool is required" >&2; exit 1; }
    done
    ```

## Configuring the Program

The program reads its settings from the following environment variables, and
treats an empty variable as unset:

| Variable                  | Default                  | Description         |
|---------------------------|--------------------------|---------------------|
| `STARFLEET_CLIENT_ID`     | None                     | Your client ID.     |
| `STARFLEET_CLIENT_SECRET` | None                     | Your client secret. |
| `STARFLEET_API_URL`       | `https://api.pgedge.com` | The API base URL.   |

The following code reads the settings:

=== "Python"

    ```python
    def settings() -> dict:
        """Reads the API settings from the environment.
    
        The or operator treats an empty variable as unset. The client ID and
        secret have no defaults, so a missing value becomes None, and the
        token request reports it.
        """
        return {
            "base_url": (
                os.environ.get("STARFLEET_API_URL") or "https://api.pgedge.com"
            ).rstrip("/"),
            "client_id": os.environ.get("STARFLEET_CLIENT_ID") or None,
            "client_secret": os.environ.get("STARFLEET_CLIENT_SECRET") or None,
        }
    ```

=== "TypeScript"

    ```typescript
    // Read the API settings from the environment. The || operator, unlike ??,
    // also treats an empty variable as unset.
    const baseUrl = (
      process.env.STARFLEET_API_URL || "https://api.pgedge.com"
    ).replace(/\/+$/, "");
    const clientId = process.env.STARFLEET_CLIENT_ID || "";
    const clientSecret = process.env.STARFLEET_CLIENT_SECRET || "";
    ```

=== "Java"

    ```java
    /** The settings that the program reads from the environment. */
    record Settings(String baseUrl, String clientId, String clientSecret) {}
    
    /**
     * Returns the value of an environment variable, or the fallback if the
     * variable is unset or empty, as an unset variable would be.
     */
    static String envOr(String name, String fallback) {
        String value = System.getenv(name);
        return (value != null && !value.isEmpty()) ? value : fallback;
    }
    
    /**
     * Reads the API settings from the environment. The client ID and secret
     * have no defaults, so a missing value becomes null, and the token
     * request reports it.
     */
    static Settings settings() {
        return new Settings(
                envOr("STARFLEET_API_URL", "https://api.pgedge.com")
                        .replaceAll("/+$", ""),
                envOr("STARFLEET_CLIENT_ID", null),
                envOr("STARFLEET_CLIENT_SECRET", null));
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
    
    // Reads the API settings from the environment. The client ID and secret
    // have no defaults, so a missing value becomes null, and the token request
    // reports it.
    static (string BaseUrl, string? ClientId, string? ClientSecret) Settings() =>
        ((EnvValue("STARFLEET_API_URL") ?? "https://api.pgedge.com").TrimEnd('/'),
            EnvValue("STARFLEET_CLIENT_ID"),
            EnvValue("STARFLEET_CLIENT_SECRET"));
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
    
    // baseURL is the root of the Starfleet API, without a trailing slash.
    func baseURL() string {
    	return strings.TrimRight(envOr("STARFLEET_API_URL", "https://api.pgedge.com"), "/")
    }
    
    // httpClient gives every request a timeout; the default client has none.
    var httpClient = &http.Client{Timeout: 30 * time.Second}
    
    ```

=== "Rust"

    ```rust
    /// The settings that the program reads from the environment.
    struct Settings {
        base_url: String,
        client_id: Option<String>,
        client_secret: Option<String>,
    }
    
    /// Returns the value of an environment variable, if it is set and not
    /// empty; an empty variable counts as unset.
    fn env_value(name: &str) -> Option<String> {
        env::var(name).ok().filter(|value| !value.is_empty())
    }
    
    /// Reads the API settings from the environment. The client ID and secret
    /// have no defaults, so a missing value becomes None, and the token
    /// request reports it.
    fn settings() -> Settings {
        Settings {
            base_url: env_value("STARFLEET_API_URL")
                .unwrap_or_else(|| "https://api.pgedge.com".to_string())
                .trim_end_matches('/')
                .to_string(),
            client_id: env_value("STARFLEET_CLIENT_ID"),
            client_secret: env_value("STARFLEET_CLIENT_SECRET"),
        }
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
    
    # Reads the API settings from the environment. The client ID and secret
    # have no defaults, so a missing value becomes nil, and the token request
    # reports it.
    def settings
      {
        base_url: env_or("STARFLEET_API_URL", "https://api.pgedge.com").sub(%r{/+\z}, ""),
        client_id: env_or("STARFLEET_CLIENT_ID", nil),
        client_secret: env_or("STARFLEET_CLIENT_SECRET", nil)
      }
    end
    ```

=== "curl"

    ```bash
    # The :- expansion treats an empty variable as unset.
    base_url="${STARFLEET_API_URL:-https://api.pgedge.com}"
    base_url="${base_url%/}"
    client_id="${STARFLEET_CLIENT_ID:-}"
    client_secret="${STARFLEET_CLIENT_SECRET:-}"
    ```

## Requesting the Token

The Starfleet account API issues tokens at `/account/v1/oauth/token`, and the
Managed API accepts them as bearer tokens until they expire. The request body
holds the grant type, the client ID, and the client secret. The following code
requests a token and returns it; the curl script builds the body with `jq` from
the environment, and passes it to curl on standard input, so that the secret
never appears in the process list:

=== "Python"

    ```python
    def get_token(config: dict) -> dict:
        """Exchanges the client ID and secret for an access token.
    
        The token endpoint belongs to the account API, and accepts the OAuth
        2.0 client credentials grant as a JSON body.
        """
        if not config["client_id"] or not config["client_secret"]:
            raise RuntimeError(
                "STARFLEET_CLIENT_ID and STARFLEET_CLIENT_SECRET must be set"
            )
    
        response = httpx.post(
            f"{config['base_url']}/account/v1/oauth/token",
            json={
                "grant_type": "client_credentials",
                "client_id": config["client_id"],
                "client_secret": config["client_secret"],
            },
            timeout=30,
        )
        # Turn any 4xx or 5xx status into an httpx.HTTPStatusError.
        response.raise_for_status()
        token = response.json()
        if not token.get("access_token"):
            raise RuntimeError("the token response has no access token")
        return token
    ```

=== "TypeScript"

    ```typescript
    interface AccessToken {
      access_token: string;
      token_type: string;
      expires_in: number;
    }
    
    // Exchanges the client ID and secret for an access token. The token
    // endpoint belongs to the account API, and accepts the OAuth 2.0 client
    // credentials grant as a JSON body.
    async function getToken(): Promise<AccessToken> {
      if (!clientId || !clientSecret) {
        throw new Error(
          "STARFLEET_CLIENT_ID and STARFLEET_CLIENT_SECRET must be set",
        );
      }
    
      const response = await fetch(`${baseUrl}/account/v1/oauth/token`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          grant_type: "client_credentials",
          client_id: clientId,
          client_secret: clientSecret,
        }),
        signal: AbortSignal.timeout(30_000),
      });
    
      // fetch only rejects on network failures, so check the status here.
      if (!response.ok) {
        throw new Error(
          `token request failed: ${response.status} ${await response.text()}`,
        );
      }
      const token = (await response.json()) as AccessToken;
      if (!token.access_token) {
        throw new Error("the token response has no access token");
      }
      return token;
    }
    ```

=== "Java"

    ```java
    /** One client serves every request; it is safe to share. */
    static final HttpClient CLIENT = HttpClient.newBuilder()
            .connectTimeout(Duration.ofSeconds(30))
            .build();
    
    /** Converts between JSON text and Java objects. */
    static final ObjectMapper JSON = new ObjectMapper();
    
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
    
    /**
     * Exchanges the client ID and secret for an access token. The token
     * endpoint belongs to the account API, and accepts the OAuth 2.0 client
     * credentials grant as a JSON body.
     */
    static JsonNode getToken(Settings cfg) throws IOException, InterruptedException {
        if (cfg.clientId() == null || cfg.clientSecret() == null) {
            throw new IllegalStateException(
                    "STARFLEET_CLIENT_ID and STARFLEET_CLIENT_SECRET must be set");
        }
    
        String path = "/account/v1/oauth/token";
        HttpRequest request = HttpRequest.newBuilder(URI.create(cfg.baseUrl() + path))
                .timeout(Duration.ofSeconds(30))
                .header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString(JSON.writeValueAsString(Map.of(
                        "grant_type", "client_credentials",
                        "client_id", cfg.clientId(),
                        "client_secret", cfg.clientSecret()))))
                .build();
        HttpResponse<String> response = send(request);
        if (response.statusCode() >= 400) {
            throw new IOException("POST " + path + " failed with status "
                    + response.statusCode() + ": " + response.body().strip());
        }
        JsonNode token = JSON.readTree(response.body());
        if (token.path("access_token").asString().isEmpty()) {
            throw new IllegalStateException("the token response has no access token");
        }
        return token;
    }
    ```

=== "C#"

    ```csharp
    // One client serves every request. Its timeout covers the whole exchange,
    // the body of the reply included.
    var http = new HttpClient { Timeout = TimeSpan.FromSeconds(30) };
    
    // Exchanges the client ID and secret for an access token. The token
    // endpoint belongs to the account API, and accepts the OAuth 2.0 client
    // credentials grant as a JSON body.
    async Task<JsonNode> GetToken((string BaseUrl, string? ClientId,
        string? ClientSecret) cfg)
    {
        if (cfg.ClientId is null || cfg.ClientSecret is null)
        {
            throw new InvalidOperationException(
                "STARFLEET_CLIENT_ID and STARFLEET_CLIENT_SECRET must be set");
        }
    
        const string path = "/account/v1/oauth/token";
        var body = JsonSerializer.Serialize(new
        {
            grant_type = "client_credentials",
            client_id = cfg.ClientId,
            client_secret = cfg.ClientSecret,
        });
        using var response = await http.PostAsync(cfg.BaseUrl + path,
            new StringContent(body, Encoding.UTF8, "application/json"));
        var text = await response.Content.ReadAsStringAsync();
        if ((int)response.StatusCode >= 400)
        {
            throw new HttpRequestException(
                $"POST {path} failed with status {(int)response.StatusCode}: "
                + text.Trim(), null, response.StatusCode);
        }
        var token = JsonNode.Parse(text);
        if (token?["access_token"]?.ToString() is not { Length: > 0 })
        {
            throw new InvalidOperationException(
                "the token response has no access token");
        }
        return token;
    }
    ```

=== "Go"

    ```go
    // AccessToken is the response from the token endpoint.
    type AccessToken struct {
    	AccessToken string `json:"access_token"`
    	TokenType   string `json:"token_type"`
    	ExpiresIn   int    `json:"expires_in"`
    }
    
    // getToken exchanges the client ID and secret for an access token. The
    // token endpoint belongs to the account API, and accepts the OAuth 2.0
    // client credentials grant as a JSON body.
    func getToken(ctx context.Context) (*AccessToken, error) {
    	clientID := os.Getenv("STARFLEET_CLIENT_ID")
    	clientSecret := os.Getenv("STARFLEET_CLIENT_SECRET")
    	if clientID == "" || clientSecret == "" {
    		return nil, errors.New("STARFLEET_CLIENT_ID and STARFLEET_CLIENT_SECRET must be set")
    	}
    
    	body, err := json.Marshal(map[string]string{
    		"grant_type":    "client_credentials",
    		"client_id":     clientID,
    		"client_secret": clientSecret,
    	})
    	if err != nil {
    		return nil, err
    	}
    
    	req, err := http.NewRequestWithContext(ctx, http.MethodPost,
    		baseURL()+"/account/v1/oauth/token", bytes.NewReader(body))
    	if err != nil {
    		return nil, err
    	}
    	req.Header.Set("Content-Type", "application/json")
    
    	resp, err := httpClient.Do(req)
    	if err != nil {
    		return nil, fmt.Errorf("token request failed: %w", err)
    	}
    	defer resp.Body.Close()
    
    	// A non-2xx status is not a Go error, so check it explicitly.
    	if resp.StatusCode != http.StatusOK {
    		detail, _ := io.ReadAll(io.LimitReader(resp.Body, 1024))
    		return nil, fmt.Errorf("token request failed: %s %s", resp.Status, detail)
    	}
    
    	var token AccessToken
    	if err := json.NewDecoder(resp.Body).Decode(&token); err != nil {
    		return nil, fmt.Errorf("decoding the token response: %w", err)
    	}
    	if token.AccessToken == "" {
    		return nil, errors.New("the token response has no access token")
    	}
    	return &token, nil
    }
    
    ```

=== "Rust"

    ```rust
    /// The ways in which getting a token can fail: the request itself, or
    /// what the program needs from the settings and the reply.
    enum TokenError {
        Api(String),
        Other(String),
    }
    
    /// Exchanges the client ID and secret for an access token. The token
    /// endpoint belongs to the account API, and accepts the OAuth 2.0 client
    /// credentials grant as a JSON body.
    fn get_token(cfg: &Settings) -> Result<Value, TokenError> {
        let (Some(client_id), Some(client_secret)) = (&cfg.client_id, &cfg.client_secret) else {
            return Err(TokenError::Other(
                "STARFLEET_CLIENT_ID and STARFLEET_CLIENT_SECRET must be set".into(),
            ));
        };
    
        // The client's timeout covers the whole exchange, the body of the
        // reply included.
        let client = Client::builder()
            .timeout(Duration::from_secs(30))
            .build()
            .map_err(|e| TokenError::Other(e.to_string()))?;
        let path = "/account/v1/oauth/token";
        let response = client
            .post(format!("{}{path}", cfg.base_url))
            .json(&json!({
                "grant_type": "client_credentials",
                "client_id": client_id,
                "client_secret": client_secret,
            }))
            .send()
            .map_err(|e| TokenError::Api(describe(&e)))?;
        let status = response.status().as_u16();
        let text = response.text().map_err(|e| TokenError::Api(describe(&e)))?;
        if status >= 400 {
            return Err(TokenError::Api(format!(
                "POST {path} failed with status {status}: {}",
                text.trim()
            )));
        }
    
        let token: Value = serde_json::from_str(&text).map_err(|e| TokenError::Other(e.to_string()))?;
        if token["access_token"].as_str().is_none_or(str::is_empty) {
            return Err(TokenError::Other("the token response has no access token".into()));
        }
        Ok(token)
    }
    ```

=== "Ruby"

    ```ruby
    # An error reply from the API.
    class ApiError < StandardError; end
    
    # Exchanges the client ID and secret for an access token. The token
    # endpoint belongs to the account API, and accepts the OAuth 2.0 client
    # credentials grant as a JSON body.
    def get_token(config)
      unless config[:client_id] && config[:client_secret]
        raise "STARFLEET_CLIENT_ID and STARFLEET_CLIENT_SECRET must be set"
      end
    
      uri = URI("#{config[:base_url]}/account/v1/oauth/token")
      body = {
        grant_type: "client_credentials",
        client_id: config[:client_id],
        client_secret: config[:client_secret]
      }.to_json
      # Net::HTTP has no overall timeout, so limit both the connection and
      # each read.
      response = Net::HTTP.start(uri.host, uri.port,
                                 use_ssl: uri.scheme == "https",
                                 open_timeout: 30, read_timeout: 30) do |http|
        http.post(uri.request_uri, body, "Content-Type" => "application/json")
      end
      if response.code.to_i >= 400
        raise ApiError, "POST #{uri.path} failed with status #{response.code}: " \
                        "#{response.body.to_s.strip}"
      end
    
      token = JSON.parse(response.body)
      raise "the token response has no access token" if token["access_token"].to_s.empty?
    
      token
    end
    ```

=== "curl"

    ```bash
    # Exchanges the client ID and secret for an access token, and prints the
    # JSON reply. The token endpoint belongs to the account API, and accepts
    # the OAuth 2.0 client credentials grant as a JSON body.
    get_token() {
        if [[ -z "$client_id" || -z "$client_secret" ]]; then
            echo "Error: STARFLEET_CLIENT_ID and STARFLEET_CLIENT_SECRET must be set" >&2
            return 1
        fi
    
        # jq builds the body from the environment, and curl reads it from
        # standard input with --data @-, so the secret never appears in the
        # process list. --fail-with-body makes curl exit non-zero on an HTTP
        # error status whilst still printing the API's error message.
        jq -n '{grant_type: "client_credentials",
                client_id: env.STARFLEET_CLIENT_ID,
                client_secret: env.STARFLEET_CLIENT_SECRET}' |
            curl --silent --show-error --fail-with-body --max-time 30 \
                --header "Content-Type: application/json" \
                --data @- \
                "$base_url/account/v1/oauth/token"
    }
    ```

## Running the Program

The `main` function gets a token and prints its details. The following code
shows the function, and the error handling that turns a failed request into a
message and a non-zero exit status:

=== "Python"

    ```python
    def main() -> int:
        try:
            token = get_token(settings())
            # Never print the token itself; it grants access to the account.
            print(f"Token type: {token['token_type']}")
            print(f"Token length: {len(token['access_token'])} characters")
            print(f"Expires in: {token['expires_in']} seconds")
        # httpx.HTTPError covers connection failures and, through
        # raise_for_status(), error responses from the API.
        except httpx.HTTPError as e:
            print(f"API error: {e}", file=sys.stderr)
            return 1
        except RuntimeError as e:
            print(f"Error: {e}", file=sys.stderr)
            return 1
    
        return 0
    
    
    if __name__ == "__main__":
        sys.exit(main())
    ```

=== "TypeScript"

    ```typescript
    // Returns a readable description of an error. A failure to connect
    // arrives as a TypeError whose cause holds the details, and Node reports
    // a failure to reach several addresses as an AggregateError.
    function describe(err: unknown): string {
      if (err instanceof AggregateError) {
        return err.errors.map(describe).join("; ");
      }
      if (err instanceof Error && err.cause) {
        return `${err.message}: ${describe(err.cause)}`;
      }
      return err instanceof Error ? err.message : String(err);
    }
    
    async function main(): Promise<number> {
      try {
        const token = await getToken();
        // Never print the token itself; it grants access to the account.
        console.log(`Token type: ${token.token_type}`);
        console.log(`Token length: ${token.access_token.length} characters`);
        console.log(`Expires in: ${token.expires_in} seconds`);
        return 0;
      } catch (err) {
        console.error(`Error: ${describe(err)}`);
        return 1;
      }
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
        try {
            JsonNode token = getToken(settings());
            // Never print the token itself; it grants access to the account.
            System.out.println("Token type: " + token.path("token_type").asString());
            System.out.println("Token length: "
                    + token.get("access_token").asString().length() + " characters");
            System.out.println("Expires in: " + token.path("expires_in").asString()
                    + " seconds");
        // IOException covers failures to connect and error replies from the
        // API, and the client throws InterruptedException if the thread is
        // interrupted.
        } catch (IOException | InterruptedException e) {
            System.err.println("API error: " + describe(e));
            System.exit(1);
        // Jackson throws JacksonException for a reply that is not JSON, and
        // IllegalStateException covers settings and replies that the
        // program cannot use.
        } catch (JacksonException | IllegalStateException e) {
            System.err.println("Error: " + describe(e));
            System.exit(1);
        }
    }
    ```

=== "C#"

    ```csharp
    try
    {
        var token = await GetToken(Settings());
        // Never print the token itself; it grants access to the account.
        Console.WriteLine($"Token type: {token["token_type"]}");
        Console.WriteLine(
            $"Token length: {token["access_token"]!.ToString().Length} characters");
        Console.WriteLine($"Expires in: {token["expires_in"]} seconds");
    }
    // HttpRequestException covers failures to connect and error replies from
    // the API, and HttpClient throws TaskCanceledException when a request
    // times out.
    catch (Exception e) when (e is HttpRequestException or TaskCanceledException)
    {
        Console.Error.WriteLine($"API error: {e.Message}");
        return 1;
    }
    // JsonException covers a reply that is not JSON, and
    // InvalidOperationException covers settings and replies that the program
    // cannot use.
    catch (Exception e) when (e is JsonException or InvalidOperationException)
    {
        Console.Error.WriteLine($"Error: {e.Message}");
        return 1;
    }
    
    return 0;
    ```

=== "Go"

    ```go
    // run requests a token and prints its details, returning any error to the
    // caller.
    func run(ctx context.Context) error {
    	token, err := getToken(ctx)
    	if err != nil {
    		return err
    	}
    
    	// Never print the token itself; it grants access to the account.
    	fmt.Printf("Token type: %s\n", token.TokenType)
    	fmt.Printf("Token length: %d characters\n", len(token.AccessToken))
    	fmt.Printf("Expires in: %d seconds\n", token.ExpiresIn)
    	return nil
    }
    
    // main reports any error returned by run() and exits with a non-zero
    // status.
    func main() {
    	if err := run(context.Background()); err != nil {
    		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
    		os.Exit(1)
    	}
    }
    
    ```

=== "Rust"

    ```rust
    /// Returns an error with the chain of underlying causes, because the
    /// top-level error is often generic ("error sending request").
    fn describe(e: &dyn Error) -> String {
        let mut text = e.to_string();
        let mut cause = e.source();
        while let Some(c) = cause {
            text.push_str(&format!(": {c}"));
            cause = c.source();
        }
        text
    }
    
    fn main() -> ExitCode {
        match get_token(&settings()) {
            Ok(token) => {
                // Never print the token itself; it grants access to the account.
                // The length counts characters, as the other languages do.
                let length = token["access_token"].as_str().unwrap_or("").chars().count();
                println!("Token type: {}", token["token_type"].as_str().unwrap_or(""));
                println!("Token length: {length} characters");
                println!("Expires in: {} seconds", token["expires_in"]);
                ExitCode::SUCCESS
            }
            Err(TokenError::Api(message)) => {
                eprintln!("API error: {message}");
                ExitCode::FAILURE
            }
            Err(TokenError::Other(message)) => {
                eprintln!("Error: {message}");
                ExitCode::FAILURE
            }
        }
    }
    ```

=== "Ruby"

    ```ruby
    def main
      token = get_token(settings)
      # Never print the token itself; it grants access to the account.
      puts "Token type: #{token.fetch('token_type')}"
      puts "Token length: #{token['access_token'].length} characters"
      puts "Expires in: #{token.fetch('expires_in')} seconds"
      0
    # Net::HTTP raises errors of several classes for a failed request: for
    # example SystemCallError for a refused connection and Net::OpenTimeout,
    # a Timeout::Error, for a timeout.
    rescue ApiError, SystemCallError, IOError, SocketError, Timeout::Error => e
      warn "API error: #{e.message}"
      1
    rescue StandardError => e
      warn "Error: #{e.message}"
      1
    end
    
    exit main
    ```

=== "curl"

    ```bash
    main() {
        local reply token_type token_length expires_in
        reply="$(get_token)" || return 1
    
        # Read each field on its own, because jq -e takes its exit status from
        # the last value that it prints, and so would not notice a missing
        # field earlier in a list. The strings and numbers filters produce
        # nothing for a missing or null field, and -e then makes jq exit
        # non-zero. Never print the token itself; it grants access to the
        # account.
        token_type="$(jq -er '.token_type | strings' <<<"$reply")" || {
            echo "Error: the token response has no token type" >&2; return 1; }
        token_length="$(jq -er '.access_token | strings | length' <<<"$reply")" || {
            echo "Error: the token response has no access token" >&2; return 1; }
        expires_in="$(jq -er '.expires_in | numbers' <<<"$reply")" || {
            echo "Error: the token response has no lifetime" >&2; return 1; }
    
        echo "Token type: $token_type"
        echo "Token length: $token_length characters"
        echo "Expires in: $expires_in seconds"
    }
    
    main
    ```

## Running the Example

The complete project for each language is available in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/starfleet/access_token).
Set the environment variables for your account, and then run the command for
your language from the corresponding project directory. The following tabs show
the commands that build and run each example:

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
    ./main.sh
    ```

## Viewing the Complete Program

The following tabs show the complete program for each language:

=== "Python"

    ```python
    """
    Ellie's Postgres Cookbook
    Exchanging a client ID and secret for a pgEdge Starfleet access token,
    using httpx.
    
    Copyright (c) 2026, pgEdge, Inc.
    This code is released under the PostgreSQL License.
    """
    
    import os
    import sys
    
    import httpx
    
    
    def settings() -> dict:
        """Reads the API settings from the environment.
    
        The or operator treats an empty variable as unset. The client ID and
        secret have no defaults, so a missing value becomes None, and the
        token request reports it.
        """
        return {
            "base_url": (
                os.environ.get("STARFLEET_API_URL") or "https://api.pgedge.com"
            ).rstrip("/"),
            "client_id": os.environ.get("STARFLEET_CLIENT_ID") or None,
            "client_secret": os.environ.get("STARFLEET_CLIENT_SECRET") or None,
        }
    
    
    def get_token(config: dict) -> dict:
        """Exchanges the client ID and secret for an access token.
    
        The token endpoint belongs to the account API, and accepts the OAuth
        2.0 client credentials grant as a JSON body.
        """
        if not config["client_id"] or not config["client_secret"]:
            raise RuntimeError(
                "STARFLEET_CLIENT_ID and STARFLEET_CLIENT_SECRET must be set"
            )
    
        response = httpx.post(
            f"{config['base_url']}/account/v1/oauth/token",
            json={
                "grant_type": "client_credentials",
                "client_id": config["client_id"],
                "client_secret": config["client_secret"],
            },
            timeout=30,
        )
        # Turn any 4xx or 5xx status into an httpx.HTTPStatusError.
        response.raise_for_status()
        token = response.json()
        if not token.get("access_token"):
            raise RuntimeError("the token response has no access token")
        return token
    
    
    def main() -> int:
        try:
            token = get_token(settings())
            # Never print the token itself; it grants access to the account.
            print(f"Token type: {token['token_type']}")
            print(f"Token length: {len(token['access_token'])} characters")
            print(f"Expires in: {token['expires_in']} seconds")
        # httpx.HTTPError covers connection failures and, through
        # raise_for_status(), error responses from the API.
        except httpx.HTTPError as e:
            print(f"API error: {e}", file=sys.stderr)
            return 1
        except RuntimeError as e:
            print(f"Error: {e}", file=sys.stderr)
            return 1
    
        return 0
    
    
    if __name__ == "__main__":
        sys.exit(main())
    
    ```

=== "TypeScript"

    ```typescript
    /*
     * Ellie's Postgres Cookbook
     * Exchanging a client ID and secret for a pgEdge Starfleet access token,
     * using the built-in fetch function.
     *
     * Copyright (c) 2026, pgEdge, Inc.
     * This code is released under the PostgreSQL License.
     */
    
    // Node.js provides fetch as a global function, so the only import is the
    // process object, which holds the environment and the exit status.
    import process from "node:process";
    
    // Read the API settings from the environment. The || operator, unlike ??,
    // also treats an empty variable as unset.
    const baseUrl = (
      process.env.STARFLEET_API_URL || "https://api.pgedge.com"
    ).replace(/\/+$/, "");
    const clientId = process.env.STARFLEET_CLIENT_ID || "";
    const clientSecret = process.env.STARFLEET_CLIENT_SECRET || "";
    
    interface AccessToken {
      access_token: string;
      token_type: string;
      expires_in: number;
    }
    
    // Exchanges the client ID and secret for an access token. The token
    // endpoint belongs to the account API, and accepts the OAuth 2.0 client
    // credentials grant as a JSON body.
    async function getToken(): Promise<AccessToken> {
      if (!clientId || !clientSecret) {
        throw new Error(
          "STARFLEET_CLIENT_ID and STARFLEET_CLIENT_SECRET must be set",
        );
      }
    
      const response = await fetch(`${baseUrl}/account/v1/oauth/token`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          grant_type: "client_credentials",
          client_id: clientId,
          client_secret: clientSecret,
        }),
        signal: AbortSignal.timeout(30_000),
      });
    
      // fetch only rejects on network failures, so check the status here.
      if (!response.ok) {
        throw new Error(
          `token request failed: ${response.status} ${await response.text()}`,
        );
      }
      const token = (await response.json()) as AccessToken;
      if (!token.access_token) {
        throw new Error("the token response has no access token");
      }
      return token;
    }
    
    // Returns a readable description of an error. A failure to connect
    // arrives as a TypeError whose cause holds the details, and Node reports
    // a failure to reach several addresses as an AggregateError.
    function describe(err: unknown): string {
      if (err instanceof AggregateError) {
        return err.errors.map(describe).join("; ");
      }
      if (err instanceof Error && err.cause) {
        return `${err.message}: ${describe(err.cause)}`;
      }
      return err instanceof Error ? err.message : String(err);
    }
    
    async function main(): Promise<number> {
      try {
        const token = await getToken();
        // Never print the token itself; it grants access to the account.
        console.log(`Token type: ${token.token_type}`);
        console.log(`Token length: ${token.access_token.length} characters`);
        console.log(`Expires in: ${token.expires_in} seconds`);
        return 0;
      } catch (err) {
        console.error(`Error: ${describe(err)}`);
        return 1;
      }
    }
    
    process.exitCode = await main();
    
    ```

=== "Java"

    ```java
    /*
     * Ellie's Postgres Cookbook
     * Exchanging a client ID and secret for a pgEdge Starfleet access token,
     * using java.net.http and Jackson.
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
    import tools.jackson.core.JacksonException;
    import tools.jackson.databind.JsonNode;
    import tools.jackson.databind.ObjectMapper;
    
    public class Main {
    
        /** The settings that the program reads from the environment. */
        record Settings(String baseUrl, String clientId, String clientSecret) {}
    
        /**
         * Returns the value of an environment variable, or the fallback if the
         * variable is unset or empty, as an unset variable would be.
         */
        static String envOr(String name, String fallback) {
            String value = System.getenv(name);
            return (value != null && !value.isEmpty()) ? value : fallback;
        }
    
        /**
         * Reads the API settings from the environment. The client ID and secret
         * have no defaults, so a missing value becomes null, and the token
         * request reports it.
         */
        static Settings settings() {
            return new Settings(
                    envOr("STARFLEET_API_URL", "https://api.pgedge.com")
                            .replaceAll("/+$", ""),
                    envOr("STARFLEET_CLIENT_ID", null),
                    envOr("STARFLEET_CLIENT_SECRET", null));
        }
    
        /** One client serves every request; it is safe to share. */
        static final HttpClient CLIENT = HttpClient.newBuilder()
                .connectTimeout(Duration.ofSeconds(30))
                .build();
    
        /** Converts between JSON text and Java objects. */
        static final ObjectMapper JSON = new ObjectMapper();
    
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
    
        /**
         * Exchanges the client ID and secret for an access token. The token
         * endpoint belongs to the account API, and accepts the OAuth 2.0 client
         * credentials grant as a JSON body.
         */
        static JsonNode getToken(Settings cfg) throws IOException, InterruptedException {
            if (cfg.clientId() == null || cfg.clientSecret() == null) {
                throw new IllegalStateException(
                        "STARFLEET_CLIENT_ID and STARFLEET_CLIENT_SECRET must be set");
            }
    
            String path = "/account/v1/oauth/token";
            HttpRequest request = HttpRequest.newBuilder(URI.create(cfg.baseUrl() + path))
                    .timeout(Duration.ofSeconds(30))
                    .header("Content-Type", "application/json")
                    .POST(HttpRequest.BodyPublishers.ofString(JSON.writeValueAsString(Map.of(
                            "grant_type", "client_credentials",
                            "client_id", cfg.clientId(),
                            "client_secret", cfg.clientSecret()))))
                    .build();
            HttpResponse<String> response = send(request);
            if (response.statusCode() >= 400) {
                throw new IOException("POST " + path + " failed with status "
                        + response.statusCode() + ": " + response.body().strip());
            }
            JsonNode token = JSON.readTree(response.body());
            if (token.path("access_token").asString().isEmpty()) {
                throw new IllegalStateException("the token response has no access token");
            }
            return token;
        }
    
        /**
         * Returns the message of an error. Some errors, such as a refused
         * connection, have no message, so their type stands in for one.
         */
        static String describe(Exception e) {
            return Objects.requireNonNullElse(e.getMessage(), e.toString());
        }
    
        public static void main(String[] args) {
            try {
                JsonNode token = getToken(settings());
                // Never print the token itself; it grants access to the account.
                System.out.println("Token type: " + token.path("token_type").asString());
                System.out.println("Token length: "
                        + token.get("access_token").asString().length() + " characters");
                System.out.println("Expires in: " + token.path("expires_in").asString()
                        + " seconds");
            // IOException covers failures to connect and error replies from the
            // API, and the client throws InterruptedException if the thread is
            // interrupted.
            } catch (IOException | InterruptedException e) {
                System.err.println("API error: " + describe(e));
                System.exit(1);
            // Jackson throws JacksonException for a reply that is not JSON, and
            // IllegalStateException covers settings and replies that the
            // program cannot use.
            } catch (JacksonException | IllegalStateException e) {
                System.err.println("Error: " + describe(e));
                System.exit(1);
            }
        }
    }
    
    ```

=== "C#"

    ```csharp
    /*
     * Ellie's Postgres Cookbook
     * Getting an access token for the pgEdge Starfleet Managed API, using
     * HttpClient and System.Text.Json.
     *
     * Copyright (c) 2026, pgEdge, Inc.
     * This code is released under the PostgreSQL License.
     */
    
    using System.Text;
    using System.Text.Json;
    using System.Text.Json.Nodes;
    
    // Returns the value of an environment variable, or null if the variable
    // is unset or empty, as an unset variable would be.
    static string? EnvValue(string name) =>
        Environment.GetEnvironmentVariable(name) is { Length: > 0 } value
            ? value
            : null;
    
    // Reads the API settings from the environment. The client ID and secret
    // have no defaults, so a missing value becomes null, and the token request
    // reports it.
    static (string BaseUrl, string? ClientId, string? ClientSecret) Settings() =>
        ((EnvValue("STARFLEET_API_URL") ?? "https://api.pgedge.com").TrimEnd('/'),
            EnvValue("STARFLEET_CLIENT_ID"),
            EnvValue("STARFLEET_CLIENT_SECRET"));
    
    // One client serves every request. Its timeout covers the whole exchange,
    // the body of the reply included.
    var http = new HttpClient { Timeout = TimeSpan.FromSeconds(30) };
    
    // Exchanges the client ID and secret for an access token. The token
    // endpoint belongs to the account API, and accepts the OAuth 2.0 client
    // credentials grant as a JSON body.
    async Task<JsonNode> GetToken((string BaseUrl, string? ClientId,
        string? ClientSecret) cfg)
    {
        if (cfg.ClientId is null || cfg.ClientSecret is null)
        {
            throw new InvalidOperationException(
                "STARFLEET_CLIENT_ID and STARFLEET_CLIENT_SECRET must be set");
        }
    
        const string path = "/account/v1/oauth/token";
        var body = JsonSerializer.Serialize(new
        {
            grant_type = "client_credentials",
            client_id = cfg.ClientId,
            client_secret = cfg.ClientSecret,
        });
        using var response = await http.PostAsync(cfg.BaseUrl + path,
            new StringContent(body, Encoding.UTF8, "application/json"));
        var text = await response.Content.ReadAsStringAsync();
        if ((int)response.StatusCode >= 400)
        {
            throw new HttpRequestException(
                $"POST {path} failed with status {(int)response.StatusCode}: "
                + text.Trim(), null, response.StatusCode);
        }
        var token = JsonNode.Parse(text);
        if (token?["access_token"]?.ToString() is not { Length: > 0 })
        {
            throw new InvalidOperationException(
                "the token response has no access token");
        }
        return token;
    }
    
    try
    {
        var token = await GetToken(Settings());
        // Never print the token itself; it grants access to the account.
        Console.WriteLine($"Token type: {token["token_type"]}");
        Console.WriteLine(
            $"Token length: {token["access_token"]!.ToString().Length} characters");
        Console.WriteLine($"Expires in: {token["expires_in"]} seconds");
    }
    // HttpRequestException covers failures to connect and error replies from
    // the API, and HttpClient throws TaskCanceledException when a request
    // times out.
    catch (Exception e) when (e is HttpRequestException or TaskCanceledException)
    {
        Console.Error.WriteLine($"API error: {e.Message}");
        return 1;
    }
    // JsonException covers a reply that is not JSON, and
    // InvalidOperationException covers settings and replies that the program
    // cannot use.
    catch (Exception e) when (e is JsonException or InvalidOperationException)
    {
        Console.Error.WriteLine($"Error: {e.Message}");
        return 1;
    }
    
    return 0;
    
    ```

=== "Go"

    ```go
    // Ellie's Postgres Cookbook
    // Exchanging a client ID and secret for a pgEdge Starfleet access token,
    // using the net/http package.
    //
    // Copyright (c) 2026, pgEdge, Inc.
    // This code is released under the PostgreSQL License.
    
    package main
    
    import (
    	"bytes"
    	"context"
    	"encoding/json"
    	"errors"
    	"fmt"
    	"io"
    	"net/http"
    	"os"
    	"strings"
    	"time"
    )
    
    
    // envOr returns the value of an environment variable, or a fallback if
    // the variable is unset or empty.
    func envOr(name, fallback string) string {
    	if value := os.Getenv(name); value != "" {
    		return value
    	}
    	return fallback
    }
    
    // baseURL is the root of the Starfleet API, without a trailing slash.
    func baseURL() string {
    	return strings.TrimRight(envOr("STARFLEET_API_URL", "https://api.pgedge.com"), "/")
    }
    
    // httpClient gives every request a timeout; the default client has none.
    var httpClient = &http.Client{Timeout: 30 * time.Second}
    
    
    // AccessToken is the response from the token endpoint.
    type AccessToken struct {
    	AccessToken string `json:"access_token"`
    	TokenType   string `json:"token_type"`
    	ExpiresIn   int    `json:"expires_in"`
    }
    
    // getToken exchanges the client ID and secret for an access token. The
    // token endpoint belongs to the account API, and accepts the OAuth 2.0
    // client credentials grant as a JSON body.
    func getToken(ctx context.Context) (*AccessToken, error) {
    	clientID := os.Getenv("STARFLEET_CLIENT_ID")
    	clientSecret := os.Getenv("STARFLEET_CLIENT_SECRET")
    	if clientID == "" || clientSecret == "" {
    		return nil, errors.New("STARFLEET_CLIENT_ID and STARFLEET_CLIENT_SECRET must be set")
    	}
    
    	body, err := json.Marshal(map[string]string{
    		"grant_type":    "client_credentials",
    		"client_id":     clientID,
    		"client_secret": clientSecret,
    	})
    	if err != nil {
    		return nil, err
    	}
    
    	req, err := http.NewRequestWithContext(ctx, http.MethodPost,
    		baseURL()+"/account/v1/oauth/token", bytes.NewReader(body))
    	if err != nil {
    		return nil, err
    	}
    	req.Header.Set("Content-Type", "application/json")
    
    	resp, err := httpClient.Do(req)
    	if err != nil {
    		return nil, fmt.Errorf("token request failed: %w", err)
    	}
    	defer resp.Body.Close()
    
    	// A non-2xx status is not a Go error, so check it explicitly.
    	if resp.StatusCode != http.StatusOK {
    		detail, _ := io.ReadAll(io.LimitReader(resp.Body, 1024))
    		return nil, fmt.Errorf("token request failed: %s %s", resp.Status, detail)
    	}
    
    	var token AccessToken
    	if err := json.NewDecoder(resp.Body).Decode(&token); err != nil {
    		return nil, fmt.Errorf("decoding the token response: %w", err)
    	}
    	if token.AccessToken == "" {
    		return nil, errors.New("the token response has no access token")
    	}
    	return &token, nil
    }
    
    
    // run requests a token and prints its details, returning any error to the
    // caller.
    func run(ctx context.Context) error {
    	token, err := getToken(ctx)
    	if err != nil {
    		return err
    	}
    
    	// Never print the token itself; it grants access to the account.
    	fmt.Printf("Token type: %s\n", token.TokenType)
    	fmt.Printf("Token length: %d characters\n", len(token.AccessToken))
    	fmt.Printf("Expires in: %d seconds\n", token.ExpiresIn)
    	return nil
    }
    
    // main reports any error returned by run() and exits with a non-zero
    // status.
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
    // Getting an access token for the pgEdge Starfleet Managed API, using
    // reqwest and serde_json.
    //
    // Copyright (c) 2026, pgEdge, Inc.
    // This code is released under the PostgreSQL License.
    
    use std::env;
    use std::error::Error;
    use std::process::ExitCode;
    use std::time::Duration;
    
    use reqwest::blocking::Client;
    use serde_json::{json, Value};
    
    /// The settings that the program reads from the environment.
    struct Settings {
        base_url: String,
        client_id: Option<String>,
        client_secret: Option<String>,
    }
    
    /// Returns the value of an environment variable, if it is set and not
    /// empty; an empty variable counts as unset.
    fn env_value(name: &str) -> Option<String> {
        env::var(name).ok().filter(|value| !value.is_empty())
    }
    
    /// Reads the API settings from the environment. The client ID and secret
    /// have no defaults, so a missing value becomes None, and the token
    /// request reports it.
    fn settings() -> Settings {
        Settings {
            base_url: env_value("STARFLEET_API_URL")
                .unwrap_or_else(|| "https://api.pgedge.com".to_string())
                .trim_end_matches('/')
                .to_string(),
            client_id: env_value("STARFLEET_CLIENT_ID"),
            client_secret: env_value("STARFLEET_CLIENT_SECRET"),
        }
    }
    
    /// The ways in which getting a token can fail: the request itself, or
    /// what the program needs from the settings and the reply.
    enum TokenError {
        Api(String),
        Other(String),
    }
    
    /// Exchanges the client ID and secret for an access token. The token
    /// endpoint belongs to the account API, and accepts the OAuth 2.0 client
    /// credentials grant as a JSON body.
    fn get_token(cfg: &Settings) -> Result<Value, TokenError> {
        let (Some(client_id), Some(client_secret)) = (&cfg.client_id, &cfg.client_secret) else {
            return Err(TokenError::Other(
                "STARFLEET_CLIENT_ID and STARFLEET_CLIENT_SECRET must be set".into(),
            ));
        };
    
        // The client's timeout covers the whole exchange, the body of the
        // reply included.
        let client = Client::builder()
            .timeout(Duration::from_secs(30))
            .build()
            .map_err(|e| TokenError::Other(e.to_string()))?;
        let path = "/account/v1/oauth/token";
        let response = client
            .post(format!("{}{path}", cfg.base_url))
            .json(&json!({
                "grant_type": "client_credentials",
                "client_id": client_id,
                "client_secret": client_secret,
            }))
            .send()
            .map_err(|e| TokenError::Api(describe(&e)))?;
        let status = response.status().as_u16();
        let text = response.text().map_err(|e| TokenError::Api(describe(&e)))?;
        if status >= 400 {
            return Err(TokenError::Api(format!(
                "POST {path} failed with status {status}: {}",
                text.trim()
            )));
        }
    
        let token: Value = serde_json::from_str(&text).map_err(|e| TokenError::Other(e.to_string()))?;
        if token["access_token"].as_str().is_none_or(str::is_empty) {
            return Err(TokenError::Other("the token response has no access token".into()));
        }
        Ok(token)
    }
    
    /// Returns an error with the chain of underlying causes, because the
    /// top-level error is often generic ("error sending request").
    fn describe(e: &dyn Error) -> String {
        let mut text = e.to_string();
        let mut cause = e.source();
        while let Some(c) = cause {
            text.push_str(&format!(": {c}"));
            cause = c.source();
        }
        text
    }
    
    fn main() -> ExitCode {
        match get_token(&settings()) {
            Ok(token) => {
                // Never print the token itself; it grants access to the account.
                // The length counts characters, as the other languages do.
                let length = token["access_token"].as_str().unwrap_or("").chars().count();
                println!("Token type: {}", token["token_type"].as_str().unwrap_or(""));
                println!("Token length: {length} characters");
                println!("Expires in: {} seconds", token["expires_in"]);
                ExitCode::SUCCESS
            }
            Err(TokenError::Api(message)) => {
                eprintln!("API error: {message}");
                ExitCode::FAILURE
            }
            Err(TokenError::Other(message)) => {
                eprintln!("Error: {message}");
                ExitCode::FAILURE
            }
        }
    }
    
    ```

=== "Ruby"

    ```ruby
    # Ellie's Postgres Cookbook
    # Exchanging a client ID and secret for a pgEdge Starfleet access token,
    # using Net::HTTP.
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
    
    # Reads the API settings from the environment. The client ID and secret
    # have no defaults, so a missing value becomes nil, and the token request
    # reports it.
    def settings
      {
        base_url: env_or("STARFLEET_API_URL", "https://api.pgedge.com").sub(%r{/+\z}, ""),
        client_id: env_or("STARFLEET_CLIENT_ID", nil),
        client_secret: env_or("STARFLEET_CLIENT_SECRET", nil)
      }
    end
    
    # An error reply from the API.
    class ApiError < StandardError; end
    
    # Exchanges the client ID and secret for an access token. The token
    # endpoint belongs to the account API, and accepts the OAuth 2.0 client
    # credentials grant as a JSON body.
    def get_token(config)
      unless config[:client_id] && config[:client_secret]
        raise "STARFLEET_CLIENT_ID and STARFLEET_CLIENT_SECRET must be set"
      end
    
      uri = URI("#{config[:base_url]}/account/v1/oauth/token")
      body = {
        grant_type: "client_credentials",
        client_id: config[:client_id],
        client_secret: config[:client_secret]
      }.to_json
      # Net::HTTP has no overall timeout, so limit both the connection and
      # each read.
      response = Net::HTTP.start(uri.host, uri.port,
                                 use_ssl: uri.scheme == "https",
                                 open_timeout: 30, read_timeout: 30) do |http|
        http.post(uri.request_uri, body, "Content-Type" => "application/json")
      end
      if response.code.to_i >= 400
        raise ApiError, "POST #{uri.path} failed with status #{response.code}: " \
                        "#{response.body.to_s.strip}"
      end
    
      token = JSON.parse(response.body)
      raise "the token response has no access token" if token["access_token"].to_s.empty?
    
      token
    end
    
    def main
      token = get_token(settings)
      # Never print the token itself; it grants access to the account.
      puts "Token type: #{token.fetch('token_type')}"
      puts "Token length: #{token['access_token'].length} characters"
      puts "Expires in: #{token.fetch('expires_in')} seconds"
      0
    # Net::HTTP raises errors of several classes for a failed request: for
    # example SystemCallError for a refused connection and Net::OpenTimeout,
    # a Timeout::Error, for a timeout.
    rescue ApiError, SystemCallError, IOError, SocketError, Timeout::Error => e
      warn "API error: #{e.message}"
      1
    rescue StandardError => e
      warn "Error: #{e.message}"
      1
    end
    
    exit main
    
    ```

=== "curl"

    ```bash
    #!/usr/bin/env bash
    #
    # Ellie's Postgres Cookbook
    # Exchanging a client ID and secret for a pgEdge Starfleet access token,
    # using curl and jq.
    #
    # Copyright (c) 2026, pgEdge, Inc.
    # This code is released under the PostgreSQL License.
    
    # Stop at the first failed command or unset variable, and make a failure
    # anywhere in a pipeline fail the whole pipeline.
    set -euo pipefail
    
    # The script needs curl to call the API and jq to read the JSON replies.
    for tool in curl jq; do
        command -v "$tool" >/dev/null || { echo "Error: $tool is required" >&2; exit 1; }
    done
    
    # The :- expansion treats an empty variable as unset.
    base_url="${STARFLEET_API_URL:-https://api.pgedge.com}"
    base_url="${base_url%/}"
    client_id="${STARFLEET_CLIENT_ID:-}"
    client_secret="${STARFLEET_CLIENT_SECRET:-}"
    
    # Exchanges the client ID and secret for an access token, and prints the
    # JSON reply. The token endpoint belongs to the account API, and accepts
    # the OAuth 2.0 client credentials grant as a JSON body.
    get_token() {
        if [[ -z "$client_id" || -z "$client_secret" ]]; then
            echo "Error: STARFLEET_CLIENT_ID and STARFLEET_CLIENT_SECRET must be set" >&2
            return 1
        fi
    
        # jq builds the body from the environment, and curl reads it from
        # standard input with --data @-, so the secret never appears in the
        # process list. --fail-with-body makes curl exit non-zero on an HTTP
        # error status whilst still printing the API's error message.
        jq -n '{grant_type: "client_credentials",
                client_id: env.STARFLEET_CLIENT_ID,
                client_secret: env.STARFLEET_CLIENT_SECRET}' |
            curl --silent --show-error --fail-with-body --max-time 30 \
                --header "Content-Type: application/json" \
                --data @- \
                "$base_url/account/v1/oauth/token"
    }
    
    main() {
        local reply token_type token_length expires_in
        reply="$(get_token)" || return 1
    
        # Read each field on its own, because jq -e takes its exit status from
        # the last value that it prints, and so would not notice a missing
        # field earlier in a list. The strings and numbers filters produce
        # nothing for a missing or null field, and -e then makes jq exit
        # non-zero. Never print the token itself; it grants access to the
        # account.
        token_type="$(jq -er '.token_type | strings' <<<"$reply")" || {
            echo "Error: the token response has no token type" >&2; return 1; }
        token_length="$(jq -er '.access_token | strings | length' <<<"$reply")" || {
            echo "Error: the token response has no access token" >&2; return 1; }
        expires_in="$(jq -er '.expires_in | numbers' <<<"$reply")" || {
            echo "Error: the token response has no lifetime" >&2; return 1; }
    
        echo "Token type: $token_type"
        echo "Token length: $token_length characters"
        echo "Expires in: $expires_in seconds"
    }
    
    main
    
    ```

## Next Steps

The following resources provide more information about the topics in this
recipe:

- The "Listing Regions, Sizes, and Versions" recipe uses the token to call
  the Managed API.
- The [Contributing a Recipe](../contributing.md) page explains how to add
  a recipe or a language to the cookbook.
