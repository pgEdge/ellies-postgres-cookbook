# Listing Regions, Sizes, and Versions

This recipe shows how to find out what the pgEdge Starfleet Managed API offers
before you create a database. The program lists the regions in which a database
can run, the sizes with their limits and prices, and the versions of PostgreSQL
that are available. The lists change as pgEdge adds regions, sizes, and
versions, so the output varies.

These examples are for the pgEdge Starfleet Managed API v1.

The lists depend on the current offering, so the output looks similar to the
following:

```text
Regions:
  us-east-2
Sizes (smallest first):
  small: 20 connections, 25Gi storage, 25.00 usd per month
  medium: 35 connections, 50Gi storage, 69.00 usd per month
PostgreSQL versions:
  18 (default)
  17
```

## Preparing the Ingredients

You need a pgEdge Starfleet account and an API client with its client ID and
secret. Never put the client secret in a file that you commit to version
control, and never paste it into a command line, because other users of the
machine can read the command lines of running processes. The programs in this
recipe read the secret from the environment and, for the curl script, pass it
to curl on standard input.

The dependencies are the same as for the "Getting an Access Token" recipe. The
following excerpts show them:

=== "Python"

    ```text
    # httpx is an HTTP client with a clean, requests-like interface.
    httpx>=0.28,<1
    ```

=== "TypeScript"

    ```json
    {
      "name": "starfleet-reference-data",
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
    import java.util.ArrayList;
    import java.util.List;
    import java.util.Locale;
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
    using System.Globalization;
    using System.Net.Http.Headers;
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
    use std::fmt;
    use std::process::ExitCode;
    use std::sync::LazyLock;
    use std::time::Duration;
    
    use reqwest::blocking::{Client, RequestBuilder};
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
    
    var cfg = Settings();
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
    /// Any error, boxed, so that a function can return errors of several types
    /// with the ? operator.
    type Result<T> = std::result::Result<T, Box<dyn Error>>;
    
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

## Getting a Token

The program gets a token in the same way as the "Getting an Access Token"
recipe. The following code requests the token:

=== "Python"

    ```python
    def get_token(config: dict) -> str:
        """Exchanges the client ID and secret for an access token, which the
        Managed API accepts as a bearer token until it expires."""
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
        return response.json()["access_token"]
    ```

=== "TypeScript"

    ```typescript
    // Exchanges the client ID and secret for an access token, which the
    // Managed API accepts as a bearer token until it expires.
    async function getToken(): Promise<string> {
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
      const body = (await response.json()) as { access_token: string };
      return body.access_token;
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
     * Sends a request and returns the decoded JSON reply. A 4xx or 5xx reply
     * throws an IOException that includes the message from the API.
     */
    static JsonNode request(HttpRequest request, String path)
            throws IOException, InterruptedException {
        HttpResponse<String> response = send(request);
        if (response.statusCode() >= 400) {
            throw new IOException(request.method() + " " + path
                    + " failed with status " + response.statusCode() + ": "
                    + response.body().strip());
        }
        return JSON.readTree(response.body());
    }
    
    /**
     * Exchanges the client ID and secret for an access token, which the
     * Managed API accepts as a bearer token until it expires.
     */
    static String getToken(Settings cfg) throws IOException, InterruptedException {
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
        return request(request, path).get("access_token").asString();
    }
    ```

=== "C#"

    ```csharp
    // One client serves every request. Its timeout covers the whole exchange,
    // the body of the reply included.
    var http = new HttpClient { Timeout = TimeSpan.FromSeconds(30) };
    
    // Sends a request and returns the decoded JSON reply. A 4xx or 5xx reply
    // throws an HttpRequestException that includes the message from the API.
    async Task<JsonNode> Send(HttpRequestMessage request, string path)
    {
        using var response = await http.SendAsync(request);
        var text = await response.Content.ReadAsStringAsync();
        if ((int)response.StatusCode >= 400)
        {
            throw new HttpRequestException(
                $"{request.Method} {path} failed with status "
                + $"{(int)response.StatusCode}: {text.Trim()}",
                null, response.StatusCode);
        }
        return JsonNode.Parse(text)
            ?? throw new InvalidOperationException($"the reply to {path} is empty");
    }
    
    // Exchanges the client ID and secret for an access token, which the
    // Managed API accepts as a bearer token until it expires.
    async Task<string> GetToken()
    {
        if (cfg.ClientId is null || cfg.ClientSecret is null)
        {
            throw new InvalidOperationException(
                "STARFLEET_CLIENT_ID and STARFLEET_CLIENT_SECRET must be set");
        }
    
        const string path = "/account/v1/oauth/token";
        using var request = new HttpRequestMessage(HttpMethod.Post, cfg.BaseUrl + path)
        {
            Content = new StringContent(JsonSerializer.Serialize(new
            {
                grant_type = "client_credentials",
                client_id = cfg.ClientId,
                client_secret = cfg.ClientSecret,
            }), Encoding.UTF8, "application/json"),
        };
        return (await Send(request, path))["access_token"]!.ToString();
    }
    ```

=== "Go"

    ```go
    // getToken exchanges the client ID and secret for an access token, which
    // the Managed API accepts as a bearer token until it expires.
    func getToken(ctx context.Context) (string, error) {
    	clientID := os.Getenv("STARFLEET_CLIENT_ID")
    	clientSecret := os.Getenv("STARFLEET_CLIENT_SECRET")
    	if clientID == "" || clientSecret == "" {
    		return "", errors.New("STARFLEET_CLIENT_ID and STARFLEET_CLIENT_SECRET must be set")
    	}
    
    	body, err := json.Marshal(map[string]string{
    		"grant_type":    "client_credentials",
    		"client_id":     clientID,
    		"client_secret": clientSecret,
    	})
    	if err != nil {
    		return "", err
    	}
    
    	req, err := http.NewRequestWithContext(ctx, http.MethodPost,
    		baseURL()+"/account/v1/oauth/token", bytes.NewReader(body))
    	if err != nil {
    		return "", err
    	}
    	req.Header.Set("Content-Type", "application/json")
    
    	resp, err := httpClient.Do(req)
    	if err != nil {
    		return "", fmt.Errorf("token request failed: %w", err)
    	}
    	defer resp.Body.Close()
    
    	// A non-2xx status is not a Go error, so check it explicitly.
    	if resp.StatusCode != http.StatusOK {
    		detail, _ := io.ReadAll(io.LimitReader(resp.Body, 1024))
    		return "", fmt.Errorf("token request failed: %s %s", resp.Status, detail)
    	}
    
    	var token struct {
    		AccessToken string `json:"access_token"`
    	}
    	if err := json.NewDecoder(resp.Body).Decode(&token); err != nil {
    		return "", fmt.Errorf("decoding the token response: %w", err)
    	}
    	return token.AccessToken, nil
    }
    
    ```

=== "Rust"

    ```rust
    /// One client serves every request. Its timeout covers the whole exchange,
    /// the body of the reply included.
    static CLIENT: LazyLock<Client> = LazyLock::new(|| {
        Client::builder()
            .timeout(Duration::from_secs(30))
            .build()
            .expect("could not create the HTTP client")
    });
    
    /// A failed request or an error reply from the API, which the program
    /// reports differently from other errors.
    #[derive(Debug)]
    struct ApiError(String);
    
    impl fmt::Display for ApiError {
        fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
            f.write_str(&self.0)
        }
    }
    
    impl Error for ApiError {}
    
    /// Sends a request and returns the decoded JSON reply. A failed request,
    /// or a 4xx or 5xx reply, returns an ApiError that includes the message
    /// from the API, and the chain of causes for a failed request, whose
    /// top-level error is often generic ("error sending request").
    fn send(request: RequestBuilder, description: &str) -> Result<Value> {
        let chain = |e: reqwest::Error| {
            let mut text = e.to_string();
            let mut cause = e.source();
            while let Some(c) = cause {
                text.push_str(&format!(": {c}"));
                cause = c.source();
            }
            ApiError(text)
        };
        let response = request.send().map_err(chain)?;
        let status = response.status().as_u16();
        let text = response.text().map_err(chain)?;
        if status >= 400 {
            return Err(ApiError(format!(
                "{description} failed with status {status}: {}",
                text.trim()
            ))
            .into());
        }
        Ok(serde_json::from_str(&text)?)
    }
    
    /// Exchanges the client ID and secret for an access token, which the
    /// Managed API accepts as a bearer token until it expires.
    fn get_token(cfg: &Settings) -> Result<String> {
        let (Some(client_id), Some(client_secret)) = (&cfg.client_id, &cfg.client_secret) else {
            return Err("STARFLEET_CLIENT_ID and STARFLEET_CLIENT_SECRET must be set".into());
        };
        let path = "/account/v1/oauth/token";
        let request = CLIENT.post(format!("{}{path}", cfg.base_url)).json(&json!({
            "grant_type": "client_credentials",
            "client_id": client_id,
            "client_secret": client_secret,
        }));
        let token = send(request, &format!("POST {path}"))?;
        Ok(token["access_token"]
            .as_str()
            .ok_or("the token response has no access token")?
            .to_string())
    }
    ```

=== "Ruby"

    ```ruby
    # An error reply from the API.
    class ApiError < StandardError; end
    
    # Sends a request with a JSON body, if there is one, and returns the
    # decoded JSON reply. Net::HTTP has no overall timeout, so this limits
    # both the connection and each read.
    def request_json(method, url, headers, body = nil)
      uri = URI(url)
      headers = headers.merge("Content-Type" => "application/json") if body
      response = Net::HTTP.start(uri.host, uri.port,
                                 use_ssl: uri.scheme == "https",
                                 open_timeout: 30, read_timeout: 30) do |http|
        http.send_request(method, uri.request_uri, body&.to_json, headers)
      end
      if response.code.to_i >= 400
        raise ApiError, "#{method} #{uri.path} failed with status #{response.code}: " \
                        "#{response.body.to_s.strip}"
      end
      JSON.parse(response.body)
    end
    
    # Exchanges the client ID and secret for an access token, which the
    # Managed API accepts as a bearer token until it expires.
    def get_token(config)
      unless config[:client_id] && config[:client_secret]
        raise "STARFLEET_CLIENT_ID and STARFLEET_CLIENT_SECRET must be set"
      end
    
      request_json("POST", "#{config[:base_url]}/account/v1/oauth/token", {}, {
                     grant_type: "client_credentials",
                     client_id: config[:client_id],
                     client_secret: config[:client_secret]
                   }).fetch("access_token")
    end
    ```

=== "curl"

    ```bash
    # Exchanges the client ID and secret for an access token, which the
    # Managed API accepts as a bearer token until it expires, and prints
    # the token.
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
                "$base_url/account/v1/oauth/token" |
            jq -er '.access_token'
    }
    ```

## Calling the Managed API

Every call to the Managed API carries the token in an `Authorization` header.
The following code wraps that in one function, which reports the API's own
message when a call fails:

=== "Python"

    ```python
    def api_get(config: dict, token: str, path: str, **params):
        """Sends an authenticated GET request to the Managed API and returns
        the decoded JSON reply."""
        response = httpx.get(
            f"{config['base_url']}/managed/v1{path}",
            headers={"Authorization": f"Bearer {token}"},
            params=params,
            timeout=30,
        )
        response.raise_for_status()
        return response.json()
    ```

=== "TypeScript"

    ```typescript
    // Sends an authenticated GET request to the Managed API and returns the
    // decoded JSON reply.
    async function apiGet<T>(
      token: string,
      path: string,
      query = "",
    ): Promise<T> {
      const response = await fetch(`${baseUrl}/managed/v1${path}${query}`, {
        headers: { Authorization: `Bearer ${token}` },
        signal: AbortSignal.timeout(30_000),
      });
      if (!response.ok) {
        throw new Error(
          `GET ${path} failed: ${response.status} ${await response.text()}`,
        );
      }
      return (await response.json()) as T;
    }
    ```

=== "Java"

    ```java
    /**
     * Sends an authenticated GET request to the Managed API and returns the
     * decoded JSON reply. The query, if there is one, follows the path.
     */
    static JsonNode apiGet(Settings cfg, String token, String path, String query)
            throws IOException, InterruptedException {
        String url = cfg.baseUrl() + "/managed/v1" + path
                + (query.isEmpty() ? "" : "?" + query);
        HttpRequest request = HttpRequest.newBuilder(URI.create(url))
                .timeout(Duration.ofSeconds(30))
                .header("Authorization", "Bearer " + token)
                .GET()
                .build();
        return request(request, path);
    }
    ```

=== "C#"

    ```csharp
    // Sends an authenticated GET request to the Managed API and returns the
    // decoded JSON reply. The query, if there is one, follows the path.
    async Task<JsonNode> ApiGet(string token, string path, string query = "")
    {
        var url = $"{cfg.BaseUrl}/managed/v1{path}"
            + (query.Length == 0 ? "" : $"?{query}");
        using var request = new HttpRequestMessage(HttpMethod.Get, url);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        return await Send(request, path);
    }
    ```

=== "Go"

    ```go
    // apiGet sends an authenticated GET request to the Managed API and
    // decodes the JSON reply into result.
    func apiGet(ctx context.Context, token, path string, result any) error {
    	req, err := http.NewRequestWithContext(ctx, http.MethodGet,
    		baseURL()+"/managed/v1"+path, nil)
    	if err != nil {
    		return err
    	}
    	req.Header.Set("Authorization", "Bearer "+token)
    
    	resp, err := httpClient.Do(req)
    	if err != nil {
    		return fmt.Errorf("GET %s failed: %w", path, err)
    	}
    	defer resp.Body.Close()
    
    	if resp.StatusCode != http.StatusOK {
    		detail, _ := io.ReadAll(io.LimitReader(resp.Body, 1024))
    		return fmt.Errorf("GET %s failed: %s %s", path, resp.Status, detail)
    	}
    	return json.NewDecoder(resp.Body).Decode(result)
    }
    
    ```

=== "Rust"

    ```rust
    /// Sends an authenticated GET request to the Managed API and returns the
    /// decoded JSON reply. The query, if there is one, follows the path.
    fn api_get(cfg: &Settings, token: &str, path: &str, query: &str) -> Result<Vec<Value>> {
        let mut url = format!("{}/managed/v1{path}", cfg.base_url);
        if !query.is_empty() {
            url = format!("{url}?{query}");
        }
        let reply = send(CLIENT.get(url).bearer_auth(token), &format!("GET {path}"))?;
        match reply {
            Value::Array(items) => Ok(items),
            _ => Err(format!("the reply to {path} is not a list").into()),
        }
    }
    
    /// Returns a field of a JSON object as text, and an error if the field is
    /// missing.
    fn field(value: &Value, name: &str) -> Result<String> {
        match value.get(name) {
            Some(Value::String(text)) => Ok(text.clone()),
            Some(Value::Null) | None => Err(format!("the reply has no {name}").into()),
            Some(other) => Ok(other.to_string()),
        }
    }
    ```

=== "Ruby"

    ```ruby
    # Sends an authenticated GET request to the Managed API and returns the
    # decoded JSON reply.
    def api_get(config, token, path, params = {})
      url = "#{config[:base_url]}/managed/v1#{path}"
      url += "?#{URI.encode_www_form(params)}" unless params.empty?
      request_json("GET", url, { "Authorization" => "Bearer #{token}" })
    end
    ```

=== "curl"

    ```bash
    # Sends an authenticated GET request to the Managed API and prints the
    # JSON reply. The --config option reads the Authorization header from a
    # file that bash creates from the printf command, so the token never
    # appears in the process list.
    api_get() {
        curl --silent --show-error --fail-with-body --max-time 30 \
            --config <(printf 'header = "Authorization: Bearer %s"\n' "$token") \
            "$base_url/managed/v1$1"
    }
    ```

## Listing the Regions

The `/regions` endpoint lists the regions in which Starfleet can run a
database. The following code prints them:

=== "Python"

    ```python
    def list_regions(config: dict, token: str) -> list[str]:
        """Returns the identifiers of the regions that can host a database."""
        return [r["region"] for r in api_get(config, token, "/regions")]
    ```

=== "TypeScript"

    ```typescript
    // Returns the identifiers of the regions that can host a database.
    async function listRegions(token: string): Promise<string[]> {
      const regions = await apiGet<{ region: string }[]>(token, "/regions");
      return regions.map((r) => r.region);
    }
    ```

=== "Java"

    ```java
    /** Returns the identifiers of the regions that can host a database. */
    static List<String> listRegions(Settings cfg, String token)
            throws IOException, InterruptedException {
        List<String> regions = new ArrayList<>();
        for (JsonNode region : apiGet(cfg, token, "/regions", "")) {
            regions.add(region.get("region").asString());
        }
        return regions;
    }
    ```

=== "C#"

    ```csharp
    // Returns the identifiers of the regions that can host a database.
    async Task<List<string>> ListRegions(string token) =>
        (await ApiGet(token, "/regions")).AsArray()
            .Select(region => region!["region"]!.ToString())
            .ToList();
    ```

=== "Go"

    ```go
    // listRegions returns the identifiers of the regions that can host a
    // database.
    func listRegions(ctx context.Context, token string) ([]string, error) {
    	var regions []struct {
    		Region string `json:"region"`
    	}
    	if err := apiGet(ctx, token, "/regions", &regions); err != nil {
    		return nil, err
    	}
    
    	names := make([]string, 0, len(regions))
    	for _, r := range regions {
    		names = append(names, r.Region)
    	}
    	return names, nil
    }
    
    ```

=== "Rust"

    ```rust
    /// Returns the identifiers of the regions that can host a database.
    fn list_regions(cfg: &Settings, token: &str) -> Result<Vec<String>> {
        api_get(cfg, token, "/regions", "")?
            .iter()
            .map(|region| field(region, "region"))
            .collect()
    }
    ```

=== "Ruby"

    ```ruby
    # Returns the identifiers of the regions that can host a database.
    def list_regions(config, token)
      api_get(config, token, "/regions").map { |r| r.fetch("region") }
    end
    ```

=== "curl"

    ```bash
    # Prints the identifiers of the regions that can host a database.
    list_regions() {
        api_get /regions | jq -r '.[] | "  \(.region)"'
    }
    ```

## Listing the Sizes

The `/sizes` endpoint lists the sizes, smallest first, with the number of
connections, the storage, and the monthly price of each. The program prints the
list in the order that the API returns it. The following code prints the sizes:

=== "Python"

    ```python
    def list_sizes(config: dict, token: str) -> list[str]:
        """Returns a description of each size, smallest first."""
        # The pricing option asks the API to include each size's price, which
        # takes a little longer because the API looks it up from billing.
        sizes = api_get(config, token, "/sizes", include="pricing")
    
        lines = []
        for size in sizes:
            line = (
                f"{size['name']}: {size['connections']} connections, "
                f"{size['storage_size']} storage"
            )
            # A size with no configured price omits the pricing field. The
            # amount is in the smallest unit of the currency, such as cents.
            price = size.get("pricing")
            if price:
                line += (
                    f", {price['price_amount'] / 100:.2f} "
                    f"{price['currency']} per {price['billing_interval']}"
                )
            lines.append(line)
        return lines
    ```

=== "TypeScript"

    ```typescript
    interface Size {
      name: string;
      connections: number;
      storage_size: string;
      pricing?: {
        price_amount: number;
        currency: string;
        billing_interval: string;
      };
    }
    
    // Returns a description of each size, smallest first.
    async function listSizes(token: string): Promise<string[]> {
      // The pricing option asks the API to include each size's price, which
      // takes a little longer because the API looks it up from billing.
      const sizes = await apiGet<Size[]>(token, "/sizes", "?include=pricing");
    
      return sizes.map((size) => {
        let line = `${size.name}: ${size.connections} connections, ${size.storage_size} storage`;
        // A size with no configured price omits the pricing field. The
        // amount is in the smallest unit of the currency, such as cents.
        if (size.pricing) {
          const amount = (size.pricing.price_amount / 100).toFixed(2);
          line += `, ${amount} ${size.pricing.currency} per ${size.pricing.billing_interval}`;
        }
        return line;
      });
    }
    ```

=== "Java"

    ```java
    /** Returns a description of each size, smallest first. */
    static List<String> listSizes(Settings cfg, String token)
            throws IOException, InterruptedException {
        // The pricing option asks the API to include each size's price,
        // which takes a little longer because the API looks it up from
        // billing.
        List<String> sizes = new ArrayList<>();
        for (JsonNode size : apiGet(cfg, token, "/sizes", "include=pricing")) {
            String line = size.get("name").asString() + ": "
                    + size.get("connections").asLong() + " connections, "
                    + size.get("storage_size").asString() + " storage";
            // A size with no configured price omits the pricing field. The
            // amount is in the smallest unit of the currency, such as
            // cents. Locale.ROOT keeps the decimal point a full stop.
            JsonNode price = size.get("pricing");
            if (price != null && !price.isNull()) {
                line += String.format(Locale.ROOT, ", %.2f %s per %s",
                        price.get("price_amount").asLong() / 100.0,
                        price.get("currency").asString(),
                        price.get("billing_interval").asString());
            }
            sizes.add(line);
        }
        return sizes;
    }
    ```

=== "C#"

    ```csharp
    // Returns a description of each size, smallest first.
    async Task<List<string>> ListSizes(string token)
    {
        // The pricing option asks the API to include each size's price, which
        // takes a little longer because the API looks it up from billing.
        var sizes = new List<string>();
        foreach (var size in (await ApiGet(token, "/sizes", "include=pricing")).AsArray())
        {
            var line = $"{size!["name"]}: {size["connections"]} connections, "
                + $"{size["storage_size"]} storage";
            // A size with no configured price omits the pricing field. The
            // amount is in the smallest unit of the currency, such as cents.
            // The invariant culture keeps the decimal point a full stop.
            if (size["pricing"] is JsonObject price)
            {
                var amount = price["price_amount"]!.GetValue<long>() / 100.0;
                line += $", {amount.ToString("F2", CultureInfo.InvariantCulture)} "
                    + $"{price["currency"]} per {price["billing_interval"]}";
            }
            sizes.Add(line);
        }
        return sizes;
    }
    ```

=== "Go"

    ```go
    // listSizes returns a description of each size, smallest first.
    func listSizes(ctx context.Context, token string) ([]string, error) {
    	// A pointer field is nil when the API omits it, which is how a size
    	// with no configured price appears.
    	var sizes []struct {
    		Name        string `json:"name"`
    		Connections int    `json:"connections"`
    		StorageSize string `json:"storage_size"`
    		Pricing     *struct {
    			PriceAmount     int64  `json:"price_amount"`
    			Currency        string `json:"currency"`
    			BillingInterval string `json:"billing_interval"`
    		} `json:"pricing"`
    	}
    	// The pricing option asks the API to include each size's price, which
    	// takes a little longer because the API looks it up from billing.
    	if err := apiGet(ctx, token, "/sizes?include=pricing", &sizes); err != nil {
    		return nil, err
    	}
    
    	lines := make([]string, 0, len(sizes))
    	for _, s := range sizes {
    		line := fmt.Sprintf("%s: %d connections, %s storage", s.Name, s.Connections, s.StorageSize)
    		// The amount is in the smallest unit of the currency, such as cents.
    		if s.Pricing != nil {
    			line += fmt.Sprintf(", %.2f %s per %s",
    				float64(s.Pricing.PriceAmount)/100, s.Pricing.Currency, s.Pricing.BillingInterval)
    		}
    		lines = append(lines, line)
    	}
    	return lines, nil
    }
    
    ```

=== "Rust"

    ```rust
    /// Returns a description of each size, smallest first.
    fn list_sizes(cfg: &Settings, token: &str) -> Result<Vec<String>> {
        // The pricing option asks the API to include each size's price, which
        // takes a little longer because the API looks it up from billing.
        let mut sizes = Vec::new();
        for size in api_get(cfg, token, "/sizes", "include=pricing")? {
            let mut line = format!(
                "{}: {} connections, {} storage",
                field(&size, "name")?,
                field(&size, "connections")?,
                field(&size, "storage_size")?
            );
            // A size with no configured price omits the pricing field. The
            // amount is in the smallest unit of the currency, such as cents;
            // Rust always formats a decimal point as a full stop.
            if let Some(price) = size.get("pricing").filter(|price| !price.is_null()) {
                let amount = price["price_amount"]
                    .as_i64()
                    .ok_or("the price has no amount")?;
                line.push_str(&format!(
                    ", {:.2} {} per {}",
                    amount as f64 / 100.0,
                    field(price, "currency")?,
                    field(price, "billing_interval")?
                ));
            }
            sizes.push(line);
        }
        Ok(sizes)
    }
    ```

=== "Ruby"

    ```ruby
    # Returns a description of each size, smallest first.
    def list_sizes(config, token)
      # The pricing option asks the API to include each size's price, which
      # takes a little longer because the API looks it up from billing.
      api_get(config, token, "/sizes", include: "pricing").map do |size|
        line = "#{size.fetch('name')}: #{size.fetch('connections')} connections, " \
               "#{size.fetch('storage_size')} storage"
        # A size with no configured price omits the pricing field. The amount
        # is in the smallest unit of the currency, such as cents.
        price = size["pricing"]
        if price
          line += format(", %.2f %s per %s", price.fetch("price_amount") / 100.0,
                         price.fetch("currency"), price.fetch("billing_interval"))
        end
        line
      end
    end
    ```

=== "curl"

    ```bash
    # Prints a description of each size, smallest first. The pricing option
    # asks the API to include each size's price. A size with no configured
    # price omits the field, and the amount is in the smallest unit of the
    # currency, such as cents.
    list_sizes() {
        api_get "/sizes?include=pricing" | jq -r '.[] |
            "  \(.name): \(.connections) connections, \(.storage_size) storage" +
            (if .pricing then
                ", \(.pricing.price_amount / 100 | floor).\("0\(.pricing.price_amount % 100)"[-2:]) \(.pricing.currency) per \(.pricing.billing_interval)"
             else "" end)'
    }
    ```

## Listing the PostgreSQL Versions

The `/pg-versions` endpoint lists the versions of PostgreSQL that a new
database can use, and marks the default. The following code prints the
versions:

=== "Python"

    ```python
    def list_versions(config: dict, token: str) -> list[str]:
        """Returns the PostgreSQL major versions, newest first, marking the
        one that a new database gets by default."""
        return [
            v["version"] + (" (default)" if v["default"] else "")
            for v in api_get(config, token, "/pg-versions")
        ]
    ```

=== "TypeScript"

    ```typescript
    // Returns the PostgreSQL major versions, newest first, marking the one
    // that a new database gets by default.
    async function listVersions(token: string): Promise<string[]> {
      const versions = await apiGet<{ version: string; default: boolean }[]>(
        token,
        "/pg-versions",
      );
      return versions.map((v) => v.version + (v.default ? " (default)" : ""));
    }
    ```

=== "Java"

    ```java
    /**
     * Returns the PostgreSQL major versions, newest first, marking the one
     * that a new database gets by default.
     */
    static List<String> listVersions(Settings cfg, String token)
            throws IOException, InterruptedException {
        List<String> versions = new ArrayList<>();
        for (JsonNode version : apiGet(cfg, token, "/pg-versions", "")) {
            versions.add(version.get("version").asString()
                    + (version.path("default").asBoolean() ? " (default)" : ""));
        }
        return versions;
    }
    ```

=== "C#"

    ```csharp
    // Returns the PostgreSQL major versions, newest first, marking the one that
    // a new database gets by default.
    async Task<List<string>> ListVersions(string token) =>
        (await ApiGet(token, "/pg-versions")).AsArray()
            .Select(version => version!["version"]!.ToString()
                + (version["default"]?.GetValue<bool>() == true ? " (default)" : ""))
            .ToList();
    ```

=== "Go"

    ```go
    // listVersions returns the PostgreSQL major versions, newest first,
    // marking the one that a new database gets by default.
    func listVersions(ctx context.Context, token string) ([]string, error) {
    	var versions []struct {
    		Version string `json:"version"`
    		Default bool   `json:"default"`
    	}
    	if err := apiGet(ctx, token, "/pg-versions", &versions); err != nil {
    		return nil, err
    	}
    
    	lines := make([]string, 0, len(versions))
    	for _, v := range versions {
    		if v.Default {
    			lines = append(lines, v.Version+" (default)")
    		} else {
    			lines = append(lines, v.Version)
    		}
    	}
    	return lines, nil
    }
    
    ```

=== "Rust"

    ```rust
    /// Returns the PostgreSQL major versions, newest first, marking the one
    /// that a new database gets by default.
    fn list_versions(cfg: &Settings, token: &str) -> Result<Vec<String>> {
        api_get(cfg, token, "/pg-versions", "")?
            .iter()
            .map(|version| {
                let default = version["default"].as_bool() == Some(true);
                Ok(field(version, "version")? + if default { " (default)" } else { "" })
            })
            .collect()
    }
    ```

=== "Ruby"

    ```ruby
    # Returns the PostgreSQL major versions, newest first, marking the one
    # that a new database gets by default.
    def list_versions(config, token)
      api_get(config, token, "/pg-versions").map do |v|
        v.fetch("version") + (v["default"] ? " (default)" : "")
      end
    end
    ```

=== "curl"

    ```bash
    # Prints the PostgreSQL major versions, newest first, marking the one
    # that a new database gets by default.
    list_versions() {
        api_get /pg-versions |
            jq -r '.[] | "  \(.version)\(if .default then " (default)" else "" end)"'
    }
    ```

## Running the Program

The `main` function gets a token and prints the three lists:

=== "Python"

    ```python
    def main() -> int:
        try:
            config = settings()
            token = get_token(config)
    
            print("Regions:")
            for region in list_regions(config, token):
                print(f"  {region}")
    
            print("Sizes (smallest first):")
            for size in list_sizes(config, token):
                print(f"  {size}")
    
            print("PostgreSQL versions:")
            for version in list_versions(config, token):
                print(f"  {version}")
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
    
        console.log("Regions:");
        for (const region of await listRegions(token)) {
          console.log(`  ${region}`);
        }
    
        console.log("Sizes (smallest first):");
        for (const size of await listSizes(token)) {
          console.log(`  ${size}`);
        }
    
        console.log("PostgreSQL versions:");
        for (const version of await listVersions(token)) {
          console.log(`  ${version}`);
        }
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
            Settings cfg = settings();
            String token = getToken(cfg);
    
            System.out.println("Regions:");
            for (String region : listRegions(cfg, token)) {
                System.out.println("  " + region);
            }
    
            System.out.println("Sizes (smallest first):");
            for (String size : listSizes(cfg, token)) {
                System.out.println("  " + size);
            }
    
            System.out.println("PostgreSQL versions:");
            for (String version : listVersions(cfg, token)) {
                System.out.println("  " + version);
            }
        // IOException covers failures to connect and error replies from the
        // API, and the client throws InterruptedException if the thread is
        // interrupted.
        } catch (IOException | InterruptedException e) {
            System.err.println("API error: " + describe(e));
            System.exit(1);
        // Jackson throws JacksonException for a reply that is not JSON, and
        // IllegalStateException covers settings that are missing.
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
        var token = await GetToken();
    
        Console.WriteLine("Regions:");
        foreach (var region in await ListRegions(token))
        {
            Console.WriteLine($"  {region}");
        }
    
        Console.WriteLine("Sizes (smallest first):");
        foreach (var size in await ListSizes(token))
        {
            Console.WriteLine($"  {size}");
        }
    
        Console.WriteLine("PostgreSQL versions:");
        foreach (var version in await ListVersions(token))
        {
            Console.WriteLine($"  {version}");
        }
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
    // printList prints a heading followed by an indented line per item.
    func printList(heading string, items []string) {
    	fmt.Println(heading)
    	for _, item := range items {
    		fmt.Printf("  %s\n", item)
    	}
    }
    
    // run fetches and prints each list, returning any error to the caller.
    func run(ctx context.Context) error {
    	token, err := getToken(ctx)
    	if err != nil {
    		return err
    	}
    
    	regions, err := listRegions(ctx, token)
    	if err != nil {
    		return err
    	}
    	printList("Regions:", regions)
    
    	sizes, err := listSizes(ctx, token)
    	if err != nil {
    		return err
    	}
    	printList("Sizes (smallest first):", sizes)
    
    	versions, err := listVersions(ctx, token)
    	if err != nil {
    		return err
    	}
    	printList("PostgreSQL versions:", versions)
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
    /// Prints the reference data, returning any error to the caller.
    fn run() -> Result<()> {
        let cfg = settings();
        let token = get_token(&cfg)?;
    
        println!("Regions:");
        for region in list_regions(&cfg, &token)? {
            println!("  {region}");
        }
    
        println!("Sizes (smallest first):");
        for size in list_sizes(&cfg, &token)? {
            println!("  {size}");
        }
    
        println!("PostgreSQL versions:");
        for version in list_versions(&cfg, &token)? {
            println!("  {version}");
        }
        Ok(())
    }
    
    fn main() -> ExitCode {
        match run() {
            Ok(()) => ExitCode::SUCCESS,
            // An ApiError covers failures to connect and error replies from
            // the API; anything else is a setting or a reply that the program
            // cannot use.
            Err(e) if e.is::<ApiError>() => {
                eprintln!("API error: {e}");
                ExitCode::FAILURE
            }
            Err(e) => {
                eprintln!("Error: {e}");
                ExitCode::FAILURE
            }
        }
    }
    ```

=== "Ruby"

    ```ruby
    def main
      config = settings
      token = get_token(config)
    
      puts "Regions:"
      list_regions(config, token).each { |region| puts "  #{region}" }
    
      puts "Sizes (smallest first):"
      list_sizes(config, token).each { |size| puts "  #{size}" }
    
      puts "PostgreSQL versions:"
      list_versions(config, token).each { |version| puts "  #{version}" }
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
        token="$(get_token)" || return 1
    
        echo "Regions:"
        list_regions
        echo "Sizes (smallest first):"
        list_sizes
        echo "PostgreSQL versions:"
        list_versions
    }
    
    main
    ```

## Running the Example

The complete project for each language is available in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/starfleet/reference_data).
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
    Listing the regions, sizes, and PostgreSQL versions that the pgEdge
    Starfleet Managed API offers, using httpx.
    
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
    
    
    def get_token(config: dict) -> str:
        """Exchanges the client ID and secret for an access token, which the
        Managed API accepts as a bearer token until it expires."""
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
        return response.json()["access_token"]
    
    
    def api_get(config: dict, token: str, path: str, **params):
        """Sends an authenticated GET request to the Managed API and returns
        the decoded JSON reply."""
        response = httpx.get(
            f"{config['base_url']}/managed/v1{path}",
            headers={"Authorization": f"Bearer {token}"},
            params=params,
            timeout=30,
        )
        response.raise_for_status()
        return response.json()
    
    
    def list_regions(config: dict, token: str) -> list[str]:
        """Returns the identifiers of the regions that can host a database."""
        return [r["region"] for r in api_get(config, token, "/regions")]
    
    
    def list_sizes(config: dict, token: str) -> list[str]:
        """Returns a description of each size, smallest first."""
        # The pricing option asks the API to include each size's price, which
        # takes a little longer because the API looks it up from billing.
        sizes = api_get(config, token, "/sizes", include="pricing")
    
        lines = []
        for size in sizes:
            line = (
                f"{size['name']}: {size['connections']} connections, "
                f"{size['storage_size']} storage"
            )
            # A size with no configured price omits the pricing field. The
            # amount is in the smallest unit of the currency, such as cents.
            price = size.get("pricing")
            if price:
                line += (
                    f", {price['price_amount'] / 100:.2f} "
                    f"{price['currency']} per {price['billing_interval']}"
                )
            lines.append(line)
        return lines
    
    
    def list_versions(config: dict, token: str) -> list[str]:
        """Returns the PostgreSQL major versions, newest first, marking the
        one that a new database gets by default."""
        return [
            v["version"] + (" (default)" if v["default"] else "")
            for v in api_get(config, token, "/pg-versions")
        ]
    
    
    def main() -> int:
        try:
            config = settings()
            token = get_token(config)
    
            print("Regions:")
            for region in list_regions(config, token):
                print(f"  {region}")
    
            print("Sizes (smallest first):")
            for size in list_sizes(config, token):
                print(f"  {size}")
    
            print("PostgreSQL versions:")
            for version in list_versions(config, token):
                print(f"  {version}")
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
     * Listing the regions, sizes, and PostgreSQL versions that the pgEdge
     * Starfleet Managed API offers, using the built-in fetch function.
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
    
    // Exchanges the client ID and secret for an access token, which the
    // Managed API accepts as a bearer token until it expires.
    async function getToken(): Promise<string> {
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
      const body = (await response.json()) as { access_token: string };
      return body.access_token;
    }
    
    // Sends an authenticated GET request to the Managed API and returns the
    // decoded JSON reply.
    async function apiGet<T>(
      token: string,
      path: string,
      query = "",
    ): Promise<T> {
      const response = await fetch(`${baseUrl}/managed/v1${path}${query}`, {
        headers: { Authorization: `Bearer ${token}` },
        signal: AbortSignal.timeout(30_000),
      });
      if (!response.ok) {
        throw new Error(
          `GET ${path} failed: ${response.status} ${await response.text()}`,
        );
      }
      return (await response.json()) as T;
    }
    
    // Returns the identifiers of the regions that can host a database.
    async function listRegions(token: string): Promise<string[]> {
      const regions = await apiGet<{ region: string }[]>(token, "/regions");
      return regions.map((r) => r.region);
    }
    
    interface Size {
      name: string;
      connections: number;
      storage_size: string;
      pricing?: {
        price_amount: number;
        currency: string;
        billing_interval: string;
      };
    }
    
    // Returns a description of each size, smallest first.
    async function listSizes(token: string): Promise<string[]> {
      // The pricing option asks the API to include each size's price, which
      // takes a little longer because the API looks it up from billing.
      const sizes = await apiGet<Size[]>(token, "/sizes", "?include=pricing");
    
      return sizes.map((size) => {
        let line = `${size.name}: ${size.connections} connections, ${size.storage_size} storage`;
        // A size with no configured price omits the pricing field. The
        // amount is in the smallest unit of the currency, such as cents.
        if (size.pricing) {
          const amount = (size.pricing.price_amount / 100).toFixed(2);
          line += `, ${amount} ${size.pricing.currency} per ${size.pricing.billing_interval}`;
        }
        return line;
      });
    }
    
    // Returns the PostgreSQL major versions, newest first, marking the one
    // that a new database gets by default.
    async function listVersions(token: string): Promise<string[]> {
      const versions = await apiGet<{ version: string; default: boolean }[]>(
        token,
        "/pg-versions",
      );
      return versions.map((v) => v.version + (v.default ? " (default)" : ""));
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
    
        console.log("Regions:");
        for (const region of await listRegions(token)) {
          console.log(`  ${region}`);
        }
    
        console.log("Sizes (smallest first):");
        for (const size of await listSizes(token)) {
          console.log(`  ${size}`);
        }
    
        console.log("PostgreSQL versions:");
        for (const version of await listVersions(token)) {
          console.log(`  ${version}`);
        }
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
     * Listing the regions, sizes, and PostgreSQL versions that the pgEdge
     * Starfleet Managed API offers, using java.net.http and Jackson.
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
    import java.util.ArrayList;
    import java.util.List;
    import java.util.Locale;
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
         * Sends a request and returns the decoded JSON reply. A 4xx or 5xx reply
         * throws an IOException that includes the message from the API.
         */
        static JsonNode request(HttpRequest request, String path)
                throws IOException, InterruptedException {
            HttpResponse<String> response = send(request);
            if (response.statusCode() >= 400) {
                throw new IOException(request.method() + " " + path
                        + " failed with status " + response.statusCode() + ": "
                        + response.body().strip());
            }
            return JSON.readTree(response.body());
        }
    
        /**
         * Exchanges the client ID and secret for an access token, which the
         * Managed API accepts as a bearer token until it expires.
         */
        static String getToken(Settings cfg) throws IOException, InterruptedException {
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
            return request(request, path).get("access_token").asString();
        }
    
        /**
         * Sends an authenticated GET request to the Managed API and returns the
         * decoded JSON reply. The query, if there is one, follows the path.
         */
        static JsonNode apiGet(Settings cfg, String token, String path, String query)
                throws IOException, InterruptedException {
            String url = cfg.baseUrl() + "/managed/v1" + path
                    + (query.isEmpty() ? "" : "?" + query);
            HttpRequest request = HttpRequest.newBuilder(URI.create(url))
                    .timeout(Duration.ofSeconds(30))
                    .header("Authorization", "Bearer " + token)
                    .GET()
                    .build();
            return request(request, path);
        }
    
        /** Returns the identifiers of the regions that can host a database. */
        static List<String> listRegions(Settings cfg, String token)
                throws IOException, InterruptedException {
            List<String> regions = new ArrayList<>();
            for (JsonNode region : apiGet(cfg, token, "/regions", "")) {
                regions.add(region.get("region").asString());
            }
            return regions;
        }
    
        /** Returns a description of each size, smallest first. */
        static List<String> listSizes(Settings cfg, String token)
                throws IOException, InterruptedException {
            // The pricing option asks the API to include each size's price,
            // which takes a little longer because the API looks it up from
            // billing.
            List<String> sizes = new ArrayList<>();
            for (JsonNode size : apiGet(cfg, token, "/sizes", "include=pricing")) {
                String line = size.get("name").asString() + ": "
                        + size.get("connections").asLong() + " connections, "
                        + size.get("storage_size").asString() + " storage";
                // A size with no configured price omits the pricing field. The
                // amount is in the smallest unit of the currency, such as
                // cents. Locale.ROOT keeps the decimal point a full stop.
                JsonNode price = size.get("pricing");
                if (price != null && !price.isNull()) {
                    line += String.format(Locale.ROOT, ", %.2f %s per %s",
                            price.get("price_amount").asLong() / 100.0,
                            price.get("currency").asString(),
                            price.get("billing_interval").asString());
                }
                sizes.add(line);
            }
            return sizes;
        }
    
        /**
         * Returns the PostgreSQL major versions, newest first, marking the one
         * that a new database gets by default.
         */
        static List<String> listVersions(Settings cfg, String token)
                throws IOException, InterruptedException {
            List<String> versions = new ArrayList<>();
            for (JsonNode version : apiGet(cfg, token, "/pg-versions", "")) {
                versions.add(version.get("version").asString()
                        + (version.path("default").asBoolean() ? " (default)" : ""));
            }
            return versions;
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
                Settings cfg = settings();
                String token = getToken(cfg);
    
                System.out.println("Regions:");
                for (String region : listRegions(cfg, token)) {
                    System.out.println("  " + region);
                }
    
                System.out.println("Sizes (smallest first):");
                for (String size : listSizes(cfg, token)) {
                    System.out.println("  " + size);
                }
    
                System.out.println("PostgreSQL versions:");
                for (String version : listVersions(cfg, token)) {
                    System.out.println("  " + version);
                }
            // IOException covers failures to connect and error replies from the
            // API, and the client throws InterruptedException if the thread is
            // interrupted.
            } catch (IOException | InterruptedException e) {
                System.err.println("API error: " + describe(e));
                System.exit(1);
            // Jackson throws JacksonException for a reply that is not JSON, and
            // IllegalStateException covers settings that are missing.
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
     * Listing the regions, sizes, and PostgreSQL versions that the pgEdge
     * Starfleet Managed API offers, using HttpClient and System.Text.Json.
     *
     * Copyright (c) 2026, pgEdge, Inc.
     * This code is released under the PostgreSQL License.
     */
    
    using System.Globalization;
    using System.Net.Http.Headers;
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
    
    var cfg = Settings();
    
    // One client serves every request. Its timeout covers the whole exchange,
    // the body of the reply included.
    var http = new HttpClient { Timeout = TimeSpan.FromSeconds(30) };
    
    // Sends a request and returns the decoded JSON reply. A 4xx or 5xx reply
    // throws an HttpRequestException that includes the message from the API.
    async Task<JsonNode> Send(HttpRequestMessage request, string path)
    {
        using var response = await http.SendAsync(request);
        var text = await response.Content.ReadAsStringAsync();
        if ((int)response.StatusCode >= 400)
        {
            throw new HttpRequestException(
                $"{request.Method} {path} failed with status "
                + $"{(int)response.StatusCode}: {text.Trim()}",
                null, response.StatusCode);
        }
        return JsonNode.Parse(text)
            ?? throw new InvalidOperationException($"the reply to {path} is empty");
    }
    
    // Exchanges the client ID and secret for an access token, which the
    // Managed API accepts as a bearer token until it expires.
    async Task<string> GetToken()
    {
        if (cfg.ClientId is null || cfg.ClientSecret is null)
        {
            throw new InvalidOperationException(
                "STARFLEET_CLIENT_ID and STARFLEET_CLIENT_SECRET must be set");
        }
    
        const string path = "/account/v1/oauth/token";
        using var request = new HttpRequestMessage(HttpMethod.Post, cfg.BaseUrl + path)
        {
            Content = new StringContent(JsonSerializer.Serialize(new
            {
                grant_type = "client_credentials",
                client_id = cfg.ClientId,
                client_secret = cfg.ClientSecret,
            }), Encoding.UTF8, "application/json"),
        };
        return (await Send(request, path))["access_token"]!.ToString();
    }
    
    // Sends an authenticated GET request to the Managed API and returns the
    // decoded JSON reply. The query, if there is one, follows the path.
    async Task<JsonNode> ApiGet(string token, string path, string query = "")
    {
        var url = $"{cfg.BaseUrl}/managed/v1{path}"
            + (query.Length == 0 ? "" : $"?{query}");
        using var request = new HttpRequestMessage(HttpMethod.Get, url);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        return await Send(request, path);
    }
    
    // Returns the identifiers of the regions that can host a database.
    async Task<List<string>> ListRegions(string token) =>
        (await ApiGet(token, "/regions")).AsArray()
            .Select(region => region!["region"]!.ToString())
            .ToList();
    
    // Returns a description of each size, smallest first.
    async Task<List<string>> ListSizes(string token)
    {
        // The pricing option asks the API to include each size's price, which
        // takes a little longer because the API looks it up from billing.
        var sizes = new List<string>();
        foreach (var size in (await ApiGet(token, "/sizes", "include=pricing")).AsArray())
        {
            var line = $"{size!["name"]}: {size["connections"]} connections, "
                + $"{size["storage_size"]} storage";
            // A size with no configured price omits the pricing field. The
            // amount is in the smallest unit of the currency, such as cents.
            // The invariant culture keeps the decimal point a full stop.
            if (size["pricing"] is JsonObject price)
            {
                var amount = price["price_amount"]!.GetValue<long>() / 100.0;
                line += $", {amount.ToString("F2", CultureInfo.InvariantCulture)} "
                    + $"{price["currency"]} per {price["billing_interval"]}";
            }
            sizes.Add(line);
        }
        return sizes;
    }
    
    // Returns the PostgreSQL major versions, newest first, marking the one that
    // a new database gets by default.
    async Task<List<string>> ListVersions(string token) =>
        (await ApiGet(token, "/pg-versions")).AsArray()
            .Select(version => version!["version"]!.ToString()
                + (version["default"]?.GetValue<bool>() == true ? " (default)" : ""))
            .ToList();
    
    try
    {
        var token = await GetToken();
    
        Console.WriteLine("Regions:");
        foreach (var region in await ListRegions(token))
        {
            Console.WriteLine($"  {region}");
        }
    
        Console.WriteLine("Sizes (smallest first):");
        foreach (var size in await ListSizes(token))
        {
            Console.WriteLine($"  {size}");
        }
    
        Console.WriteLine("PostgreSQL versions:");
        foreach (var version in await ListVersions(token))
        {
            Console.WriteLine($"  {version}");
        }
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
    // Listing the regions, sizes, and PostgreSQL versions that the pgEdge
    // Starfleet Managed API offers, using the net/http package.
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
    
    
    // getToken exchanges the client ID and secret for an access token, which
    // the Managed API accepts as a bearer token until it expires.
    func getToken(ctx context.Context) (string, error) {
    	clientID := os.Getenv("STARFLEET_CLIENT_ID")
    	clientSecret := os.Getenv("STARFLEET_CLIENT_SECRET")
    	if clientID == "" || clientSecret == "" {
    		return "", errors.New("STARFLEET_CLIENT_ID and STARFLEET_CLIENT_SECRET must be set")
    	}
    
    	body, err := json.Marshal(map[string]string{
    		"grant_type":    "client_credentials",
    		"client_id":     clientID,
    		"client_secret": clientSecret,
    	})
    	if err != nil {
    		return "", err
    	}
    
    	req, err := http.NewRequestWithContext(ctx, http.MethodPost,
    		baseURL()+"/account/v1/oauth/token", bytes.NewReader(body))
    	if err != nil {
    		return "", err
    	}
    	req.Header.Set("Content-Type", "application/json")
    
    	resp, err := httpClient.Do(req)
    	if err != nil {
    		return "", fmt.Errorf("token request failed: %w", err)
    	}
    	defer resp.Body.Close()
    
    	// A non-2xx status is not a Go error, so check it explicitly.
    	if resp.StatusCode != http.StatusOK {
    		detail, _ := io.ReadAll(io.LimitReader(resp.Body, 1024))
    		return "", fmt.Errorf("token request failed: %s %s", resp.Status, detail)
    	}
    
    	var token struct {
    		AccessToken string `json:"access_token"`
    	}
    	if err := json.NewDecoder(resp.Body).Decode(&token); err != nil {
    		return "", fmt.Errorf("decoding the token response: %w", err)
    	}
    	return token.AccessToken, nil
    }
    
    
    // apiGet sends an authenticated GET request to the Managed API and
    // decodes the JSON reply into result.
    func apiGet(ctx context.Context, token, path string, result any) error {
    	req, err := http.NewRequestWithContext(ctx, http.MethodGet,
    		baseURL()+"/managed/v1"+path, nil)
    	if err != nil {
    		return err
    	}
    	req.Header.Set("Authorization", "Bearer "+token)
    
    	resp, err := httpClient.Do(req)
    	if err != nil {
    		return fmt.Errorf("GET %s failed: %w", path, err)
    	}
    	defer resp.Body.Close()
    
    	if resp.StatusCode != http.StatusOK {
    		detail, _ := io.ReadAll(io.LimitReader(resp.Body, 1024))
    		return fmt.Errorf("GET %s failed: %s %s", path, resp.Status, detail)
    	}
    	return json.NewDecoder(resp.Body).Decode(result)
    }
    
    
    // listRegions returns the identifiers of the regions that can host a
    // database.
    func listRegions(ctx context.Context, token string) ([]string, error) {
    	var regions []struct {
    		Region string `json:"region"`
    	}
    	if err := apiGet(ctx, token, "/regions", &regions); err != nil {
    		return nil, err
    	}
    
    	names := make([]string, 0, len(regions))
    	for _, r := range regions {
    		names = append(names, r.Region)
    	}
    	return names, nil
    }
    
    
    // listSizes returns a description of each size, smallest first.
    func listSizes(ctx context.Context, token string) ([]string, error) {
    	// A pointer field is nil when the API omits it, which is how a size
    	// with no configured price appears.
    	var sizes []struct {
    		Name        string `json:"name"`
    		Connections int    `json:"connections"`
    		StorageSize string `json:"storage_size"`
    		Pricing     *struct {
    			PriceAmount     int64  `json:"price_amount"`
    			Currency        string `json:"currency"`
    			BillingInterval string `json:"billing_interval"`
    		} `json:"pricing"`
    	}
    	// The pricing option asks the API to include each size's price, which
    	// takes a little longer because the API looks it up from billing.
    	if err := apiGet(ctx, token, "/sizes?include=pricing", &sizes); err != nil {
    		return nil, err
    	}
    
    	lines := make([]string, 0, len(sizes))
    	for _, s := range sizes {
    		line := fmt.Sprintf("%s: %d connections, %s storage", s.Name, s.Connections, s.StorageSize)
    		// The amount is in the smallest unit of the currency, such as cents.
    		if s.Pricing != nil {
    			line += fmt.Sprintf(", %.2f %s per %s",
    				float64(s.Pricing.PriceAmount)/100, s.Pricing.Currency, s.Pricing.BillingInterval)
    		}
    		lines = append(lines, line)
    	}
    	return lines, nil
    }
    
    
    // listVersions returns the PostgreSQL major versions, newest first,
    // marking the one that a new database gets by default.
    func listVersions(ctx context.Context, token string) ([]string, error) {
    	var versions []struct {
    		Version string `json:"version"`
    		Default bool   `json:"default"`
    	}
    	if err := apiGet(ctx, token, "/pg-versions", &versions); err != nil {
    		return nil, err
    	}
    
    	lines := make([]string, 0, len(versions))
    	for _, v := range versions {
    		if v.Default {
    			lines = append(lines, v.Version+" (default)")
    		} else {
    			lines = append(lines, v.Version)
    		}
    	}
    	return lines, nil
    }
    
    
    // printList prints a heading followed by an indented line per item.
    func printList(heading string, items []string) {
    	fmt.Println(heading)
    	for _, item := range items {
    		fmt.Printf("  %s\n", item)
    	}
    }
    
    // run fetches and prints each list, returning any error to the caller.
    func run(ctx context.Context) error {
    	token, err := getToken(ctx)
    	if err != nil {
    		return err
    	}
    
    	regions, err := listRegions(ctx, token)
    	if err != nil {
    		return err
    	}
    	printList("Regions:", regions)
    
    	sizes, err := listSizes(ctx, token)
    	if err != nil {
    		return err
    	}
    	printList("Sizes (smallest first):", sizes)
    
    	versions, err := listVersions(ctx, token)
    	if err != nil {
    		return err
    	}
    	printList("PostgreSQL versions:", versions)
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
    // Listing the regions, sizes, and PostgreSQL versions that the pgEdge
    // Starfleet Managed API offers, using reqwest and serde_json.
    //
    // Copyright (c) 2026, pgEdge, Inc.
    // This code is released under the PostgreSQL License.
    
    use std::env;
    use std::error::Error;
    use std::fmt;
    use std::process::ExitCode;
    use std::sync::LazyLock;
    use std::time::Duration;
    
    use reqwest::blocking::{Client, RequestBuilder};
    use serde_json::{json, Value};
    
    /// Any error, boxed, so that a function can return errors of several types
    /// with the ? operator.
    type Result<T> = std::result::Result<T, Box<dyn Error>>;
    
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
    
    /// One client serves every request. Its timeout covers the whole exchange,
    /// the body of the reply included.
    static CLIENT: LazyLock<Client> = LazyLock::new(|| {
        Client::builder()
            .timeout(Duration::from_secs(30))
            .build()
            .expect("could not create the HTTP client")
    });
    
    /// A failed request or an error reply from the API, which the program
    /// reports differently from other errors.
    #[derive(Debug)]
    struct ApiError(String);
    
    impl fmt::Display for ApiError {
        fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
            f.write_str(&self.0)
        }
    }
    
    impl Error for ApiError {}
    
    /// Sends a request and returns the decoded JSON reply. A failed request,
    /// or a 4xx or 5xx reply, returns an ApiError that includes the message
    /// from the API, and the chain of causes for a failed request, whose
    /// top-level error is often generic ("error sending request").
    fn send(request: RequestBuilder, description: &str) -> Result<Value> {
        let chain = |e: reqwest::Error| {
            let mut text = e.to_string();
            let mut cause = e.source();
            while let Some(c) = cause {
                text.push_str(&format!(": {c}"));
                cause = c.source();
            }
            ApiError(text)
        };
        let response = request.send().map_err(chain)?;
        let status = response.status().as_u16();
        let text = response.text().map_err(chain)?;
        if status >= 400 {
            return Err(ApiError(format!(
                "{description} failed with status {status}: {}",
                text.trim()
            ))
            .into());
        }
        Ok(serde_json::from_str(&text)?)
    }
    
    /// Exchanges the client ID and secret for an access token, which the
    /// Managed API accepts as a bearer token until it expires.
    fn get_token(cfg: &Settings) -> Result<String> {
        let (Some(client_id), Some(client_secret)) = (&cfg.client_id, &cfg.client_secret) else {
            return Err("STARFLEET_CLIENT_ID and STARFLEET_CLIENT_SECRET must be set".into());
        };
        let path = "/account/v1/oauth/token";
        let request = CLIENT.post(format!("{}{path}", cfg.base_url)).json(&json!({
            "grant_type": "client_credentials",
            "client_id": client_id,
            "client_secret": client_secret,
        }));
        let token = send(request, &format!("POST {path}"))?;
        Ok(token["access_token"]
            .as_str()
            .ok_or("the token response has no access token")?
            .to_string())
    }
    
    /// Sends an authenticated GET request to the Managed API and returns the
    /// decoded JSON reply. The query, if there is one, follows the path.
    fn api_get(cfg: &Settings, token: &str, path: &str, query: &str) -> Result<Vec<Value>> {
        let mut url = format!("{}/managed/v1{path}", cfg.base_url);
        if !query.is_empty() {
            url = format!("{url}?{query}");
        }
        let reply = send(CLIENT.get(url).bearer_auth(token), &format!("GET {path}"))?;
        match reply {
            Value::Array(items) => Ok(items),
            _ => Err(format!("the reply to {path} is not a list").into()),
        }
    }
    
    /// Returns a field of a JSON object as text, and an error if the field is
    /// missing.
    fn field(value: &Value, name: &str) -> Result<String> {
        match value.get(name) {
            Some(Value::String(text)) => Ok(text.clone()),
            Some(Value::Null) | None => Err(format!("the reply has no {name}").into()),
            Some(other) => Ok(other.to_string()),
        }
    }
    
    /// Returns the identifiers of the regions that can host a database.
    fn list_regions(cfg: &Settings, token: &str) -> Result<Vec<String>> {
        api_get(cfg, token, "/regions", "")?
            .iter()
            .map(|region| field(region, "region"))
            .collect()
    }
    
    /// Returns a description of each size, smallest first.
    fn list_sizes(cfg: &Settings, token: &str) -> Result<Vec<String>> {
        // The pricing option asks the API to include each size's price, which
        // takes a little longer because the API looks it up from billing.
        let mut sizes = Vec::new();
        for size in api_get(cfg, token, "/sizes", "include=pricing")? {
            let mut line = format!(
                "{}: {} connections, {} storage",
                field(&size, "name")?,
                field(&size, "connections")?,
                field(&size, "storage_size")?
            );
            // A size with no configured price omits the pricing field. The
            // amount is in the smallest unit of the currency, such as cents;
            // Rust always formats a decimal point as a full stop.
            if let Some(price) = size.get("pricing").filter(|price| !price.is_null()) {
                let amount = price["price_amount"]
                    .as_i64()
                    .ok_or("the price has no amount")?;
                line.push_str(&format!(
                    ", {:.2} {} per {}",
                    amount as f64 / 100.0,
                    field(price, "currency")?,
                    field(price, "billing_interval")?
                ));
            }
            sizes.push(line);
        }
        Ok(sizes)
    }
    
    /// Returns the PostgreSQL major versions, newest first, marking the one
    /// that a new database gets by default.
    fn list_versions(cfg: &Settings, token: &str) -> Result<Vec<String>> {
        api_get(cfg, token, "/pg-versions", "")?
            .iter()
            .map(|version| {
                let default = version["default"].as_bool() == Some(true);
                Ok(field(version, "version")? + if default { " (default)" } else { "" })
            })
            .collect()
    }
    
    /// Prints the reference data, returning any error to the caller.
    fn run() -> Result<()> {
        let cfg = settings();
        let token = get_token(&cfg)?;
    
        println!("Regions:");
        for region in list_regions(&cfg, &token)? {
            println!("  {region}");
        }
    
        println!("Sizes (smallest first):");
        for size in list_sizes(&cfg, &token)? {
            println!("  {size}");
        }
    
        println!("PostgreSQL versions:");
        for version in list_versions(&cfg, &token)? {
            println!("  {version}");
        }
        Ok(())
    }
    
    fn main() -> ExitCode {
        match run() {
            Ok(()) => ExitCode::SUCCESS,
            // An ApiError covers failures to connect and error replies from
            // the API; anything else is a setting or a reply that the program
            // cannot use.
            Err(e) if e.is::<ApiError>() => {
                eprintln!("API error: {e}");
                ExitCode::FAILURE
            }
            Err(e) => {
                eprintln!("Error: {e}");
                ExitCode::FAILURE
            }
        }
    }
    
    ```

=== "Ruby"

    ```ruby
    # Ellie's Postgres Cookbook
    # Listing the regions, sizes, and PostgreSQL versions that the pgEdge
    # Starfleet Managed API offers, using Net::HTTP.
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
    
    # Sends a request with a JSON body, if there is one, and returns the
    # decoded JSON reply. Net::HTTP has no overall timeout, so this limits
    # both the connection and each read.
    def request_json(method, url, headers, body = nil)
      uri = URI(url)
      headers = headers.merge("Content-Type" => "application/json") if body
      response = Net::HTTP.start(uri.host, uri.port,
                                 use_ssl: uri.scheme == "https",
                                 open_timeout: 30, read_timeout: 30) do |http|
        http.send_request(method, uri.request_uri, body&.to_json, headers)
      end
      if response.code.to_i >= 400
        raise ApiError, "#{method} #{uri.path} failed with status #{response.code}: " \
                        "#{response.body.to_s.strip}"
      end
      JSON.parse(response.body)
    end
    
    # Exchanges the client ID and secret for an access token, which the
    # Managed API accepts as a bearer token until it expires.
    def get_token(config)
      unless config[:client_id] && config[:client_secret]
        raise "STARFLEET_CLIENT_ID and STARFLEET_CLIENT_SECRET must be set"
      end
    
      request_json("POST", "#{config[:base_url]}/account/v1/oauth/token", {}, {
                     grant_type: "client_credentials",
                     client_id: config[:client_id],
                     client_secret: config[:client_secret]
                   }).fetch("access_token")
    end
    
    # Sends an authenticated GET request to the Managed API and returns the
    # decoded JSON reply.
    def api_get(config, token, path, params = {})
      url = "#{config[:base_url]}/managed/v1#{path}"
      url += "?#{URI.encode_www_form(params)}" unless params.empty?
      request_json("GET", url, { "Authorization" => "Bearer #{token}" })
    end
    
    # Returns the identifiers of the regions that can host a database.
    def list_regions(config, token)
      api_get(config, token, "/regions").map { |r| r.fetch("region") }
    end
    
    # Returns a description of each size, smallest first.
    def list_sizes(config, token)
      # The pricing option asks the API to include each size's price, which
      # takes a little longer because the API looks it up from billing.
      api_get(config, token, "/sizes", include: "pricing").map do |size|
        line = "#{size.fetch('name')}: #{size.fetch('connections')} connections, " \
               "#{size.fetch('storage_size')} storage"
        # A size with no configured price omits the pricing field. The amount
        # is in the smallest unit of the currency, such as cents.
        price = size["pricing"]
        if price
          line += format(", %.2f %s per %s", price.fetch("price_amount") / 100.0,
                         price.fetch("currency"), price.fetch("billing_interval"))
        end
        line
      end
    end
    
    # Returns the PostgreSQL major versions, newest first, marking the one
    # that a new database gets by default.
    def list_versions(config, token)
      api_get(config, token, "/pg-versions").map do |v|
        v.fetch("version") + (v["default"] ? " (default)" : "")
      end
    end
    
    def main
      config = settings
      token = get_token(config)
    
      puts "Regions:"
      list_regions(config, token).each { |region| puts "  #{region}" }
    
      puts "Sizes (smallest first):"
      list_sizes(config, token).each { |size| puts "  #{size}" }
    
      puts "PostgreSQL versions:"
      list_versions(config, token).each { |version| puts "  #{version}" }
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
    # Listing the regions, sizes, and PostgreSQL versions that the pgEdge
    # Starfleet Managed API offers, using curl and jq.
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
    
    # Exchanges the client ID and secret for an access token, which the
    # Managed API accepts as a bearer token until it expires, and prints
    # the token.
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
                "$base_url/account/v1/oauth/token" |
            jq -er '.access_token'
    }
    
    # Sends an authenticated GET request to the Managed API and prints the
    # JSON reply. The --config option reads the Authorization header from a
    # file that bash creates from the printf command, so the token never
    # appears in the process list.
    api_get() {
        curl --silent --show-error --fail-with-body --max-time 30 \
            --config <(printf 'header = "Authorization: Bearer %s"\n' "$token") \
            "$base_url/managed/v1$1"
    }
    
    # Prints the identifiers of the regions that can host a database.
    list_regions() {
        api_get /regions | jq -r '.[] | "  \(.region)"'
    }
    
    # Prints a description of each size, smallest first. The pricing option
    # asks the API to include each size's price. A size with no configured
    # price omits the field, and the amount is in the smallest unit of the
    # currency, such as cents.
    list_sizes() {
        api_get "/sizes?include=pricing" | jq -r '.[] |
            "  \(.name): \(.connections) connections, \(.storage_size) storage" +
            (if .pricing then
                ", \(.pricing.price_amount / 100 | floor).\("0\(.pricing.price_amount % 100)"[-2:]) \(.pricing.currency) per \(.pricing.billing_interval)"
             else "" end)'
    }
    
    # Prints the PostgreSQL major versions, newest first, marking the one
    # that a new database gets by default.
    list_versions() {
        api_get /pg-versions |
            jq -r '.[] | "  \(.version)\(if .default then " (default)" else "" end)"'
    }
    
    main() {
        token="$(get_token)" || return 1
    
        echo "Regions:"
        list_regions
        echo "Sizes (smallest first):"
        list_sizes
        echo "PostgreSQL versions:"
        list_versions
    }
    
    main
    
    ```

## Next Steps

The following resources provide more information about the topics in this
recipe:

- The "Creating a Database and Waiting for It" recipe uses the first
  region and the smallest size from these lists.
