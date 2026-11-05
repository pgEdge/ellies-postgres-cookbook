# Chatting with the LLM through the AI DBA Workbench API

This recipe shows how a program holds a short conversation with the large
language model (LLM) that the pgEdge AI DBA Workbench is configured to use.
These examples are for AI DBA Workbench 1.0.0. Each step shows the code in
every supported language; selecting a language tab switches every tab on the
site to that language.

The Workbench 1.0.0 API has no streaming chat endpoint: `POST /api/v1/llm/chat`
returns the whole reply in one response, and the only endpoint that streams is
`GET /api/v1/overview/stream`, which sends server-sent events that report the
progress of generating the estate overview. This recipe therefore uses the chat
endpoint without streaming. The example program reads the default provider and
model, asks a question, and then asks a follow-up question that relies on the
first answer. The reply text depends on the model, so the output has the
following form:

```text
Provider: ollama (model qwen2.5:1.5b)
Reply: A B-tree index is the default index type in PostgreSQL.
Follow-up reply: B-tree is the default index.
Stop reason: end_turn
```

## Preparing the Ingredients

The `scripts/start_workbench.sh` script in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook)
starts a test Workbench in Docker. The script creates a `cookbook` user and an
API token, registers a test PostgreSQL server as a monitored connection, and
prints the `WORKBENCH_URL`, `WORKBENCH_TOKEN`, `WORKBENCH_USERNAME`,
`WORKBENCH_PASSWORD`, and `WORKBENCH_CONNECTION_ID` values that the examples
read from the environment.

The examples need a running Workbench server that has an LLM provider
configured, and an API token for a user that may use the chat feature. The
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

The curl example is a bash script that uses [jq](https://jqlang.org/) to build
the requests and read the JSON replies. The following tabs show the dependency
declaration from each example project:

=== "Python"

    ```text
    # httpx, an HTTP client with a requests-like interface.
    httpx>=0.28,<1
    ```

=== "TypeScript"

    ```json
    {
      "name": "chat",
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
    import java.util.ArrayList;
    import java.util.List;
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
    
    use reqwest::blocking::Client;
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
    
    # The script needs curl to make the requests and jq to build the requests
    # and read the replies.
    for tool in curl jq; do
        command -v "$tool" >/dev/null || { echo "$tool is required" >&2; exit 1; }
    done
    ```

## Configuring the Connection

The examples read their settings from environment variables, and treat an empty
variable as unset. The following table describes the variables that the
examples read:

| Variable          | Description                                   |
|-------------------|-----------------------------------------------|
| `WORKBENCH_URL`   | The base URL; default `http://localhost:8080` |
| `WORKBENCH_TOKEN` | An API token for the Workbench.               |

The [Authenticating with the AI DBA Workbench API](authenticate.md) recipe
shows how to create an API token. The following tabs show how each program
reads the settings and stops with an error when the token is missing:

=== "Python"

    ```python
    def settings() -> dict:
        """Reads the settings from the environment.
    
        The or operator treats an empty variable as unset.
        """
        token = os.environ.get("WORKBENCH_TOKEN") or ""
        if not token:
            raise RuntimeError("WORKBENCH_TOKEN must be set")
        return {
            "base_url": (
                os.environ.get("WORKBENCH_URL") or "http://localhost:8080"
            ).rstrip("/"),
            "token": token,
        }
    ```

=== "TypeScript"

    ```typescript
    interface Settings {
      baseUrl: string;
      token: string;
    }
    
    // Read the settings from the environment. The || operator, unlike ??, also
    // treats an empty variable as unset.
    function settings(): Settings {
      const token = process.env.WORKBENCH_TOKEN || "";
      if (!token) throw new Error("WORKBENCH_TOKEN must be set");
      const baseUrl = process.env.WORKBENCH_URL || "http://localhost:8080";
      return { baseUrl: baseUrl.replace(/\/+$/, ""), token };
    }
    ```

=== "Java"

    ```java
    /** The settings that the program reads from the environment. */
    record Settings(String baseUrl, String token) {}
    
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
        String token = envOr("WORKBENCH_TOKEN", "");
        if (token.isEmpty()) {
            throw new IOException("WORKBENCH_TOKEN must be set");
        }
        String baseUrl = envOr("WORKBENCH_URL", "http://localhost:8080")
                .replaceAll("/+$", "");
        return new Settings(baseUrl, token);
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
    static (string BaseUrl, string Token) Settings()
    {
        var token = EnvValue("WORKBENCH_TOKEN")
            ?? throw new InvalidOperationException("WORKBENCH_TOKEN must be set");
        var baseUrl = EnvValue("WORKBENCH_URL") ?? "http://localhost:8080";
        return (baseUrl.TrimEnd('/'), token);
    }
    ```

=== "Go"

    ```go
    // settings holds the values that the program reads from the environment.
    type settings struct {
    	baseURL string
    	token   string
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
    		baseURL: strings.TrimRight(envOr("WORKBENCH_URL", "http://localhost:8080"), "/"),
    		token:   os.Getenv("WORKBENCH_TOKEN"),
    	}
    	if s.token == "" {
    		return s, errors.New("WORKBENCH_TOKEN must be set")
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
        token: String,
    }
    
    /// Returns the value of an environment variable, if it is set and not
    /// empty; an empty variable counts as unset.
    fn env_value(name: &str) -> Option<String> {
        env::var(name).ok().filter(|value| !value.is_empty())
    }
    
    /// Reads the settings from the environment.
    fn settings() -> Result<Settings> {
        let token = env_value("WORKBENCH_TOKEN").ok_or("WORKBENCH_TOKEN must be set")?;
        let base_url = env_value("WORKBENCH_URL")
            .unwrap_or_else(|| "http://localhost:8080".to_string())
            .trim_end_matches('/')
            .to_string();
        Ok(Settings { base_url, token })
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
      token = env_or("WORKBENCH_TOKEN", nil)
      raise "WORKBENCH_TOKEN must be set" unless token
    
      {
        base_url: env_or("WORKBENCH_URL", "http://localhost:8080").sub(%r{/+\z}, ""),
        token: token
      }
    end
    ```

=== "curl"

    ```bash
    # Read the settings from the environment. The :- and :? forms, unlike - and
    # ?, treat an empty variable as unset.
    WORKBENCH_URL="${WORKBENCH_URL:-http://localhost:8080}"
    WORKBENCH_URL="${WORKBENCH_URL%/}"
    : "${WORKBENCH_TOKEN:?WORKBENCH_TOKEN must be set}"
    ```

## Sending Requests

Every call to the API goes through one helper function. The function adds the
`/api/v1` prefix to the path, sends the token as a `Bearer` credential, and
sets a timeout of five minutes, because a small model running on a CPU can take
a while to answer. When the server rejects a request, the function raises an
error that includes the status code and the message from the server. The
following tabs show the helper function from each program:

=== "Python"

    ```python
    def api(cfg: dict, method: str, path: str, **kwargs) -> httpx.Response:
        """Sends a request to the API and returns the response.
    
        A request that the server rejects raises an error that includes the
        message from the server, which raise_for_status alone would leave out.
        """
        # A small model on a CPU can take a while to answer, so the timeout is
        # generous.
        response = httpx.request(
            method, f"{cfg['base_url']}/api/v1{path}", timeout=300,
            headers={"Authorization": f"Bearer {cfg['token']}"}, **kwargs,
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
      s: Settings,
      method: string,
      path: string,
      body?: unknown,
    ): Promise<Response> {
      const headers: Record<string, string> = {
        Authorization: `Bearer ${s.token}`,
      };
      if (body !== undefined) headers["Content-Type"] = "application/json";
    
      const response = await fetch(`${s.baseUrl}/api/v1${path}`, {
        method,
        headers,
        body: body === undefined ? undefined : JSON.stringify(body),
        // A small model on a CPU can take a while to answer, so the timeout is
        // generous.
        signal: AbortSignal.timeout(300_000),
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
     * Sends a request to the API and returns the JSON reply. The body may
     * be null. A request that the server rejects throws an error that
     * includes the message from the server.
     */
    static JsonNode api(Settings cfg, String method, String path,
            Object body) throws IOException, InterruptedException {
        // A small model on a CPU can take a while to answer, so the
        // timeout is generous.
        HttpRequest.Builder request = HttpRequest
                .newBuilder(URI.create(cfg.baseUrl() + "/api/v1" + path))
                .timeout(Duration.ofSeconds(300))
                .header("Authorization", "Bearer " + cfg.token());
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
        return JSON.readTree(response.body());
    }
    ```

=== "C#"

    ```csharp
    // One client serves every request. A small model on a CPU can take a while
    // to answer, so the timeout is generous.
    var http = new HttpClient { Timeout = TimeSpan.FromSeconds(300) };
    
    // Sends a request to the API and returns the JSON reply. A request that the
    // server rejects throws an error that includes the message from the server.
    async Task<JsonNode> Api(string baseUrl, string token, string method,
        string path, object? body = null)
    {
        using var request = new HttpRequestMessage(
            new HttpMethod(method), $"{baseUrl}/api/v1{path}");
        request.Headers.Authorization =
            new AuthenticationHeaderValue("Bearer", token);
        if (body is not null)
        {
            request.Content = JsonContent.Create(body);
        }
    
        using var response = await http.SendAsync(request);
        var text = await response.Content.ReadAsStringAsync();
        if ((int)response.StatusCode >= 400)
        {
            throw new HttpRequestException(
                $"{method} {path} failed with status {(int)response.StatusCode}: "
                + text.Trim());
        }
        return JsonNode.Parse(text)
            ?? throw new InvalidOperationException(
                $"{method} {path} returned no JSON");
    }
    ```

=== "Go"

    ```go
    // client gives every request a timeout; the default client has none. A small
    // model on a CPU can take a while to answer, so the timeout is generous.
    var client = &http.Client{Timeout: 300 * time.Second}
    
    // api sends a request to the API and decodes the JSON reply into out. A
    // request that the server rejects returns an error that includes the message
    // from the server.
    func api(s settings, method, path string, body, out any) error {
    	var reader io.Reader
    	if body != nil {
    		encoded, err := json.Marshal(body)
    		if err != nil {
    			return err
    		}
    		reader = bytes.NewReader(encoded)
    	}
    
    	req, err := http.NewRequest(method, s.baseURL+"/api/v1"+path, reader)
    	if err != nil {
    		return err
    	}
    	req.Header.Set("Authorization", "Bearer "+s.token)
    	if body != nil {
    		req.Header.Set("Content-Type", "application/json")
    	}
    
    	resp, err := client.Do(req)
    	if err != nil {
    		return err
    	}
    	defer resp.Body.Close()
    	if resp.StatusCode >= 400 {
    		text, _ := io.ReadAll(resp.Body)
    		return fmt.Errorf("%s %s failed with status %d: %s",
    			method, path, resp.StatusCode, strings.TrimSpace(string(text)))
    	}
    	return json.NewDecoder(resp.Body).Decode(out)
    }
    
    ```

=== "Rust"

    ```rust
    /// One client serves every request. A small model on a CPU can take a
    /// while to answer, so the timeout is generous.
    static CLIENT: LazyLock<Client> = LazyLock::new(|| {
        Client::builder()
            .timeout(Duration::from_secs(300))
            .build()
            .expect("could not create the HTTP client")
    });
    
    /// Sends a request to the API and returns the JSON reply. A request that
    /// the server rejects returns an error that includes the message from the
    /// server.
    fn api(cfg: &Settings, method: Method, path: &str, body: Option<&Value>) -> Result<Value> {
        let mut request = CLIENT
            .request(method.clone(), format!("{}/api/v1{path}", cfg.base_url))
            .bearer_auth(&cfg.token);
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
        Ok(response.json()?)
    }
    ```

=== "Ruby"

    ```ruby
    # Sends a request to the API and returns the decoded reply. The body, if
    # given, is sent as JSON. A request that the server rejects raises an error
    # that includes the message from the server.
    def api(cfg, method, path, body = nil)
      uri = URI("#{cfg[:base_url]}/api/v1#{path}")
      headers = { "Authorization" => "Bearer #{cfg[:token]}" }
      headers["Content-Type"] = "application/json" if body
    
      # A small model on a CPU can take a while to answer, so the read timeout
      # is generous.
      response = Net::HTTP.start(uri.host, uri.port,
                                 use_ssl: uri.scheme == "https",
                                 open_timeout: 30, read_timeout: 300) do |http|
        http.send_request(method, uri.request_uri, body&.to_json, headers)
      end
      if response.code.to_i >= 400
        raise "#{method} #{path} failed with status #{response.code}: " \
              "#{response.body.to_s.strip}"
      end
      JSON.parse(response.body)
    end
    ```

=== "curl"

    ```bash
    # Sends an authenticated request and prints the JSON reply:
    # api METHOD PATH [curl options]. With --fail-with-body, a request that the
    # server rejects leaves the server's error message in the reply, and the
    # function prints it to standard error.
    # The token goes to curl in a header file that bash supplies through a pipe,
    # so that it never appears in the arguments of the curl process, which other
    # users can read in the process list.
    api() {
        local method="$1" path="$2"
        shift 2
        local response
        response=$(curl --silent --show-error --fail-with-body \
            --connect-timeout 10 --max-time 300 \
            --request "$method" \
            --header @<(printf 'Authorization: Bearer %s\n' "$WORKBENCH_TOKEN") \
            "$@" "$WORKBENCH_URL/api/v1$path") || {
            echo "$method $path failed: $response" >&2
            return 1
        }
        printf '%s' "$response"
    }
    ```

## Finding the Default Provider

The `GET /api/v1/llm/providers` call lists the LLM providers that the Workbench
has configured. Each provider has a `name`, a `display` name, and an
`isDefault` flag, and the reply also has the `defaultModel`. A chat request
that names neither a provider nor a model uses these defaults. The program
prints the default provider and model, and stops with an error if the Workbench
has no default. The following tabs show how each program finds the default
provider:

=== "Python"

    ```python
    def show_provider(cfg: dict) -> None:
        """Prints the default provider and model, which the chat endpoint uses
        when a request names neither."""
        reply = api(cfg, "GET", "/llm/providers").json()
        default = next((p for p in reply["providers"] if p["isDefault"]), None)
        if default is None:
            raise RuntimeError("The Workbench has no default LLM provider")
        print(f"Provider: {default['name']} (model {reply['defaultModel']})")
    ```

=== "TypeScript"

    ```typescript
    interface Providers {
      providers: { name: string; isDefault: boolean }[];
      defaultModel: string;
    }
    
    // Prints the default provider and model, which the chat endpoint uses when a
    // request names neither.
    async function showProvider(s: Settings): Promise<void> {
      const reply = (await (
        await api(s, "GET", "/llm/providers")
      ).json()) as Providers;
      const provider = reply.providers.find((p) => p.isDefault);
      if (!provider) throw new Error("The Workbench has no default LLM provider");
      console.log(`Provider: ${provider.name} (model ${reply.defaultModel})`);
    }
    ```

=== "Java"

    ```java
    /**
     * Prints the default provider and model, which the chat endpoint uses
     * when a request names neither.
     */
    static void showProvider(Settings cfg)
            throws IOException, InterruptedException {
        JsonNode reply = api(cfg, "GET", "/llm/providers", null);
        for (JsonNode provider : reply.path("providers")) {
            if (provider.path("isDefault").asBoolean(false)) {
                System.out.println("Provider: "
                        + provider.get("name").asString() + " (model " + reply.get("defaultModel").asString()
                        + ")");
                return;
            }
        }
        throw new IOException("The Workbench has no default LLM provider");
    }
    ```

=== "C#"

    ```csharp
    // Prints the default provider and model, which the chat endpoint uses when
    // a request names neither.
    async Task ShowProvider(string baseUrl, string token)
    {
        var reply = await Api(baseUrl, token, "GET", "/llm/providers");
        var provider = reply["providers"]?.AsArray()
            .FirstOrDefault(p => p?["isDefault"]?.GetValue<bool>() == true)
            ?? throw new InvalidOperationException(
                "The Workbench has no default LLM provider");
        Console.WriteLine(
            $"Provider: {provider["name"]} (model {reply["defaultModel"]})");
    }
    ```

=== "Go"

    ```go
    // showProvider prints the default provider and model, which the chat
    // endpoint uses when a request names neither.
    func showProvider(s settings) error {
    	var reply struct {
    		Providers []struct {
    			Name      string `json:"name"`
    			IsDefault bool   `json:"isDefault"`
    		} `json:"providers"`
    		DefaultModel string `json:"defaultModel"`
    	}
    	if err := api(s, "GET", "/llm/providers", nil, &reply); err != nil {
    		return err
    	}
    	for _, p := range reply.Providers {
    		if p.IsDefault {
    			fmt.Printf("Provider: %s (model %s)\n", p.Name, reply.DefaultModel)
    			return nil
    		}
    	}
    	return errors.New("the Workbench has no default LLM provider")
    }
    
    ```

=== "Rust"

    ```rust
    /// Prints the default provider and model, which the chat endpoint uses
    /// when a request names neither.
    fn show_provider(cfg: &Settings) -> Result<()> {
        let reply = api(cfg, Method::GET, "/llm/providers", None)?;
        let default = reply["providers"]
            .as_array()
            .and_then(|providers| providers.iter().find(|p| p["isDefault"] == true))
            .ok_or("the Workbench has no default LLM provider")?;
        let name = default["name"].as_str().ok_or("the provider had no name")?;
        let model = reply["defaultModel"]
            .as_str()
            .ok_or("the reply had no default model")?;
        println!("Provider: {name} (model {model})");
        Ok(())
    }
    ```

=== "Ruby"

    ```ruby
    # Prints the default provider and model, which the chat endpoint uses when
    # a request names neither.
    def show_provider(cfg)
      reply = api(cfg, "GET", "/llm/providers")
      default = reply.fetch("providers").find { |p| p["isDefault"] }
      raise "The Workbench has no default LLM provider" if default.nil?
    
      puts "Provider: #{default.fetch('name')} (model #{reply.fetch('defaultModel')})"
    end
    ```

=== "curl"

    ```bash
    # Prints the default provider and model, which the chat endpoint uses when a
    # request names neither.
    show_provider() {
        local providers
        providers=$(api GET /llm/providers)
        jq -r '"Provider: \(.providers[] | select(.isDefault) | .name) " +
               "(model \(.defaultModel))"' <<<"$providers"
    }
    ```

## Chatting

The `POST /api/v1/llm/chat` call takes a `messages` list, where each message
has a `role` of `user` or `assistant` and some `content`. The reply has a
`content` list of blocks, where the blocks of type `text` hold the answer, and
a `stop_reason`. The server keeps no conversation, so a client that wants a
follow-up must send the earlier messages again, including the replies of the
model. Because a small model may spread its answer over several lines, the
helper function joins the text blocks and collapses the white space, and it
raises an error if the reply holds no text. A request for a provider that the
Workbench does not know about fails with a 400 status and a plain-text message.
The following tabs show the two helper functions from each program:

=== "Python"

    ```python
    def chat(cfg: dict, messages: list) -> dict:
        """Sends a conversation to the model and returns the reply.
    
        The messages are the conversation so far, each with a role of user or
        assistant and some content.
        """
        return api(cfg, "POST", "/llm/chat", json={"messages": messages}).json()
    
    
    def reply_text(reply: dict) -> str:
        """Returns the text of a reply on a single line.
    
        A small model may spread its answer over several lines, so the function
        joins the text blocks and collapses the white space. It fails when the
        reply holds no text.
        """
        blocks = [b["text"] for b in reply["content"] if b["type"] == "text"]
        text = " ".join(" ".join(blocks).split())
        if not text:
            raise RuntimeError("The model returned no text")
        return text
    ```

=== "TypeScript"

    ```typescript
    interface Message {
      role: "user" | "assistant";
      content: string;
    }
    
    interface ChatReply {
      content: { type: string; text?: string }[];
      stop_reason: string;
    }
    
    // Sends a conversation to the model and returns the reply. The messages are
    // the conversation so far, each with a role of user or assistant and some
    // content.
    async function chat(s: Settings, messages: Message[]): Promise<ChatReply> {
      const response = await api(s, "POST", "/llm/chat", { messages });
      return (await response.json()) as ChatReply;
    }
    
    // Returns the text of a reply on a single line. A small model may spread its
    // answer over several lines, so the function joins the text blocks and
    // collapses the white space. It throws when the reply holds no text.
    function replyText(reply: ChatReply): string {
      const text = reply.content
        .filter((block) => block.type === "text")
        .map((block) => block.text ?? "")
        .join(" ")
        .split(/\s+/)
        .filter((word) => word !== "")
        .join(" ");
      if (!text) throw new Error("The model returned no text");
      return text;
    }
    ```

=== "Java"

    ```java
    /**
     * Sends a conversation to the model and returns the reply. The messages
     * are the conversation so far, each with a role of user or assistant
     * and some content.
     */
    static JsonNode chat(Settings cfg, List<Map<String, String>> messages)
            throws IOException, InterruptedException {
        return api(cfg, "POST", "/llm/chat", Map.of("messages", messages));
    }
    
    /**
     * Returns the text of a reply on a single line. A small model may
     * spread its answer over several lines, so the method joins the text
     * blocks and collapses the white space. It fails when the reply holds
     * no text.
     */
    static String replyText(JsonNode reply) throws IOException {
        List<String> blocks = new ArrayList<>();
        for (JsonNode block : reply.path("content")) {
            if ("text".equals(block.path("type").asString())) {
                blocks.add(block.path("text").asString());
            }
        }
        String text = String.join(" ", blocks).strip().replaceAll("\\s+", " ");
        if (text.isEmpty()) {
            throw new IOException("The model returned no text");
        }
        return text;
    }
    ```

=== "C#"

    ```csharp
    // Sends a conversation to the model and returns the reply. The messages are
    // the conversation so far, each with a role of user or assistant and some
    // content.
    async Task<JsonNode> Chat(string baseUrl, string token,
        List<object> messages) =>
        await Api(baseUrl, token, "POST", "/llm/chat", new { messages });
    
    // Returns the text of a reply on a single line. A small model may spread
    // its answer over several lines, so the function joins the text blocks and
    // collapses the white space. It fails when the reply holds no text.
    static string ReplyText(JsonNode reply)
    {
        var blocks = (reply["content"]?.AsArray() ?? new JsonArray())
            .Where(b => b?["type"]?.GetValue<string>() == "text")
            .Select(b => b!["text"]?.GetValue<string>() ?? "");
        var text = Regex.Replace(string.Join(" ", blocks).Trim(), @"\s+", " ");
        if (text.Length == 0)
        {
            throw new InvalidOperationException("The model returned no text");
        }
        return text;
    }
    ```

=== "Go"

    ```go
    // message is one turn of a conversation, with a role of user or assistant.
    type message struct {
    	Role    string `json:"role"`
    	Content string `json:"content"`
    }
    
    // chatReply is the part of the server's reply that the program needs.
    type chatReply struct {
    	Content []struct {
    		Type string `json:"type"`
    		Text string `json:"text"`
    	} `json:"content"`
    	StopReason string `json:"stop_reason"`
    }
    
    // chat sends a conversation to the model and returns the reply. The messages
    // are the conversation so far.
    func chat(s settings, messages []message) (chatReply, error) {
    	var reply chatReply
    	err := api(s, "POST", "/llm/chat", map[string]any{"messages": messages}, &reply)
    	return reply, err
    }
    
    // text returns the text of a reply on a single line. A small model may
    // spread its answer over several lines, so the function joins the text
    // blocks and collapses the white space. It fails when the reply holds no
    // text.
    func (r chatReply) text() (string, error) {
    	var blocks []string
    	for _, block := range r.Content {
    		if block.Type == "text" {
    			blocks = append(blocks, block.Text)
    		}
    	}
    	text := strings.Join(strings.Fields(strings.Join(blocks, " ")), " ")
    	if text == "" {
    		return "", errors.New("the model returned no text")
    	}
    	return text, nil
    }
    
    ```

=== "Rust"

    ```rust
    /// Sends a conversation to the model and returns the reply. The messages
    /// are the conversation so far, each with a role of user or assistant and
    /// some content.
    fn chat(cfg: &Settings, messages: &[Value]) -> Result<Value> {
        api(
            cfg,
            Method::POST,
            "/llm/chat",
            Some(&json!({ "messages": messages })),
        )
    }
    
    /// Returns the text of a reply on a single line. A small model may spread
    /// its answer over several lines, so the function joins the text blocks
    /// and collapses the white space. It fails when the reply holds no text.
    fn reply_text(reply: &Value) -> Result<String> {
        let blocks: Vec<&str> = reply["content"]
            .as_array()
            .map(Vec::as_slice)
            .unwrap_or_default()
            .iter()
            .filter(|b| b["type"] == "text")
            .filter_map(|b| b["text"].as_str())
            .collect();
        let joined = blocks.join(" ");
        let text = joined.split_whitespace().collect::<Vec<_>>().join(" ");
        if text.is_empty() {
            return Err("the model returned no text".into());
        }
        Ok(text)
    }
    ```

=== "Ruby"

    ```ruby
    # Sends a conversation to the model and returns the reply. The messages are
    # the conversation so far, each with a role of user or assistant and some
    # content.
    def chat(cfg, messages)
      api(cfg, "POST", "/llm/chat", { messages: messages })
    end
    
    # Returns the text of a reply on a single line. A small model may spread
    # its answer over several lines, so the method joins the text blocks and
    # collapses the white space. It fails when the reply holds no text.
    def reply_text(reply)
      blocks = reply.fetch("content").select { |b| b["type"] == "text" }
      text = blocks.map { |b| b["text"] }.join(" ").split.join(" ")
      raise "The model returned no text" if text.empty?
    
      text
    end
    ```

=== "curl"

    ```bash
    # Sends a conversation to the model and prints the reply as JSON. The
    # argument is the conversation so far, as a JSON array of messages.
    chat() {
        local messages="$1"
        jq -n --argjson messages "$messages" '{messages: $messages}' |
            api POST /llm/chat \
                --header 'Content-Type: application/json' --data @-
    }
    
    # Prints the text of a reply on a single line. A small model may spread its
    # answer over several lines, so the function joins the text blocks and
    # collapses the white space, and it fails when the reply holds no text.
    reply_text() {
        local text
        text=$(jq -r '[.content[] | select(.type == "text") | .text] | join(" ")' \
            <<<"$1" | tr -s '[:space:]' ' ' | sed 's/^ //; s/ $//')
        if [[ -z "$text" ]]; then
            echo "The model returned no text" >&2
            return 1
        fi
        printf '%s\n' "$text"
    }
    ```

## Holding a Conversation

The main part of each program prints the default provider, sends the first
question, and then sends a follow-up question together with the first question
and the model's answer. It reports a failure on `stderr` and exits with a
non-zero status. The following tabs show the main part of each program:

=== "Python"

    ```python
    def main() -> int:
        try:
            cfg = settings()
            show_provider(cfg)
    
            # The first message starts the conversation.
            question = "Name one type of PostgreSQL index, in one sentence."
            messages = [{"role": "user", "content": question}]
            text = reply_text(chat(cfg, messages))
            print(f"Reply: {text}")
    
            # The server keeps no conversation, so the follow-up repeats the
            # earlier messages, including the model's reply, and adds the new
            # question.
            messages += [
                {"role": "assistant", "content": text},
                {"role": "user",
                 "content": "Summarise your answer in five words."},
            ]
            follow_up = chat(cfg, messages)
            print(f"Follow-up reply: {reply_text(follow_up)}")
            print(f"Stop reason: {follow_up['stop_reason']}")
        # httpx.HTTPError covers failures to connect, and RuntimeError covers
        # replies that the server rejected or that lacked what we need.
        except (httpx.HTTPError, RuntimeError) as e:
            print(f"Error: {e}", file=sys.stderr)
            return 1
        return 0
    
    
    if __name__ == "__main__":
        sys.exit(main())
    ```

=== "TypeScript"

    ```typescript
    async function main(): Promise<number> {
      try {
        const s = settings();
        await showProvider(s);
    
        // The first message starts the conversation.
        const question = "Name one type of PostgreSQL index, in one sentence.";
        const messages: Message[] = [{ role: "user", content: question }];
        const text = replyText(await chat(s, messages));
        console.log(`Reply: ${text}`);
    
        // The server keeps no conversation, so the follow-up repeats the earlier
        // messages, including the model's reply, and adds the new question.
        messages.push(
          { role: "assistant", content: text },
          { role: "user", content: "Summarise your answer in five words." },
        );
        const followUp = await chat(s, messages);
        console.log(`Follow-up reply: ${replyText(followUp)}`);
        console.log(`Stop reason: ${followUp.stop_reason}`);
      } catch (err) {
        console.error(`Error: ${err instanceof Error ? err.message : err}`);
        return 1;
      }
      return 0;
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
        try {
            Settings cfg = settings();
            showProvider(cfg);
    
            // The first message starts the conversation.
            String question =
                    "Name one type of PostgreSQL index, in one sentence.";
            List<Map<String, String>> messages = new ArrayList<>();
            messages.add(Map.of("role", "user", "content", question));
            String text = replyText(chat(cfg, messages));
            System.out.println("Reply: " + text);
    
            // The server keeps no conversation, so the follow-up repeats
            // the earlier messages, including the model's reply, and adds
            // the new question.
            messages.add(Map.of("role", "assistant", "content", text));
            messages.add(Map.of("role", "user",
                    "content", "Summarise your answer in five words."));
            JsonNode followUp = chat(cfg, messages);
            System.out.println("Follow-up reply: " + replyText(followUp));
            System.out.println("Stop reason: "
                    + followUp.path("stop_reason").asString());
        // IOException covers failures to connect, replies that the server
        // rejected, and replies that lacked what we need; the client
        // throws InterruptedException if the thread is interrupted, and
        // Jackson throws JacksonException for a reply that is not JSON.
        } catch (IOException | InterruptedException | JacksonException e) {
            System.err.println("Error: " + describe(e));
            status = 1;
        }
        System.exit(status);
    }
    ```

=== "C#"

    ```csharp
    try
    {
        var (baseUrl, token) = Settings();
        await ShowProvider(baseUrl, token);
    
        // The first message starts the conversation.
        var question = "Name one type of PostgreSQL index, in one sentence.";
        var messages = new List<object>
        {
            new { role = "user", content = question },
        };
        var text = ReplyText(await Chat(baseUrl, token, messages));
        Console.WriteLine($"Reply: {text}");
    
        // The server keeps no conversation, so the follow-up repeats the
        // earlier messages, including the model's reply, and adds the new
        // question.
        messages.Add(new { role = "assistant", content = text });
        messages.Add(new
        {
            role = "user",
            content = "Summarise your answer in five words.",
        });
        var followUp = await Chat(baseUrl, token, messages);
        Console.WriteLine($"Follow-up reply: {ReplyText(followUp)}");
        Console.WriteLine($"Stop reason: {followUp["stop_reason"]}");
    }
    // HttpRequestException covers failures to connect and replies that the
    // server rejected, TaskCanceledException covers a request that timed out,
    // and the others cover replies that lacked what we need.
    catch (Exception e) when (e is HttpRequestException
        or TaskCanceledException or InvalidOperationException or JsonException)
    {
        Console.Error.WriteLine($"Error: {e.Message}");
        return 1;
    }
    return 0;
    ```

=== "Go"

    ```go
    func run() error {
    	s, err := loadSettings()
    	if err != nil {
    		return err
    	}
    	if err := showProvider(s); err != nil {
    		return err
    	}
    
    	// The first message starts the conversation.
    	question := "Name one type of PostgreSQL index, in one sentence."
    	messages := []message{{Role: "user", Content: question}}
    	reply, err := chat(s, messages)
    	if err != nil {
    		return err
    	}
    	text, err := reply.text()
    	if err != nil {
    		return err
    	}
    	fmt.Printf("Reply: %s\n", text)
    
    	// The server keeps no conversation, so the follow-up repeats the earlier
    	// messages, including the model's reply, and adds the new question.
    	messages = append(messages,
    		message{Role: "assistant", Content: text},
    		message{Role: "user", Content: "Summarise your answer in five words."})
    	followUp, err := chat(s, messages)
    	if err != nil {
    		return err
    	}
    	text, err = followUp.text()
    	if err != nil {
    		return err
    	}
    	fmt.Printf("Follow-up reply: %s\n", text)
    	fmt.Printf("Stop reason: %s\n", followUp.StopReason)
    	return nil
    }
    
    func main() {
    	if err := run(); err != nil {
    		fmt.Fprintln(os.Stderr, "Error:", err)
    		os.Exit(1)
    	}
    }
    
    ```

=== "Rust"

    ```rust
    /// Prints an error with the chain of underlying causes, because the
    /// top-level error is often generic ("error sending request").
    fn report(e: &dyn Error) {
        eprintln!("Error: {e}");
        let mut cause = e.source();
        while let Some(c) = cause {
            eprintln!("  caused by: {c}");
            cause = c.source();
        }
    }
    
    fn run() -> Result<()> {
        let cfg = settings()?;
        show_provider(&cfg)?;
    
        // The first message starts the conversation.
        let question = "Name one type of PostgreSQL index, in one sentence.";
        let mut messages = vec![json!({ "role": "user", "content": question })];
        let text = reply_text(&chat(&cfg, &messages)?)?;
        println!("Reply: {text}");
    
        // The server keeps no conversation, so the follow-up repeats the
        // earlier messages, including the model's reply, and adds the new
        // question.
        messages.push(json!({ "role": "assistant", "content": text }));
        messages.push(json!({ "role": "user", "content": "Summarise your answer in five words." }));
        let follow_up = chat(&cfg, &messages)?;
        println!("Follow-up reply: {}", reply_text(&follow_up)?);
        let stop_reason = follow_up["stop_reason"].as_str().unwrap_or_default();
        println!("Stop reason: {stop_reason}");
        Ok(())
    }
    
    fn main() -> ExitCode {
        match run() {
            Ok(()) => ExitCode::SUCCESS,
            Err(e) => {
                report(e.as_ref());
                ExitCode::FAILURE
            }
        }
    }
    ```

=== "Ruby"

    ```ruby
    def main
      cfg = settings
      show_provider(cfg)
    
      # The first message starts the conversation.
      question = "Name one type of PostgreSQL index, in one sentence."
      messages = [{ role: "user", content: question }]
      text = reply_text(chat(cfg, messages))
      puts "Reply: #{text}"
    
      # The server keeps no conversation, so the follow-up repeats the earlier
      # messages, including the model's reply, and adds the new question.
      messages += [
        { role: "assistant", content: text },
        { role: "user", content: "Summarise your answer in five words." }
      ]
      follow_up = chat(cfg, messages)
      puts "Follow-up reply: #{reply_text(follow_up)}"
      puts "Stop reason: #{follow_up['stop_reason']}"
      0
    # Net::HTTP raises errors of many classes, such as SystemCallError for a
    # refused connection and Net::ReadTimeout for a timeout, and the program
    # raises RuntimeError for replies that the server rejected or that lacked
    # what we need, so this catches StandardError, their common ancestor.
    rescue StandardError => e
      warn "Error: #{e.message}"
      1
    end
    
    exit main
    ```

=== "curl"

    ```bash
    main() {
        local first second question text
    
        show_provider
    
        # The first message starts the conversation.
        question="Name one type of PostgreSQL index, in one sentence."
        first=$(chat "$(jq -nc --arg q "$question" \
            '[{role: "user", content: $q}]')")
        text=$(reply_text "$first")
        echo "Reply: $text"
    
        # The server keeps no conversation, so the follow-up repeats the earlier
        # messages, including the model's reply, and adds the new question.
        second=$(chat "$(jq -nc --arg q "$question" --arg a "$text" \
            '[{role: "user", content: $q},
              {role: "assistant", content: $a},
              {role: "user", content: "Summarise your answer in five words."}]')")
        text=$(reply_text "$second")
        echo "Follow-up reply: $text"
        echo "Stop reason: $(jq -r '.stop_reason' <<<"$second")"
    }
    
    main
    ```

## Running the Example

The complete project for each language is available in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/ai_dba_workbench/chat).
Set `WORKBENCH_URL` and `WORKBENCH_TOKEN` for your server, and then run the
command for your language from the corresponding project directory. The
following tabs show the commands that build and run each example:

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
    Chatting with the LLM through the AI DBA Workbench API, using httpx.
    
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
        token = os.environ.get("WORKBENCH_TOKEN") or ""
        if not token:
            raise RuntimeError("WORKBENCH_TOKEN must be set")
        return {
            "base_url": (
                os.environ.get("WORKBENCH_URL") or "http://localhost:8080"
            ).rstrip("/"),
            "token": token,
        }
    
    
    def api(cfg: dict, method: str, path: str, **kwargs) -> httpx.Response:
        """Sends a request to the API and returns the response.
    
        A request that the server rejects raises an error that includes the
        message from the server, which raise_for_status alone would leave out.
        """
        # A small model on a CPU can take a while to answer, so the timeout is
        # generous.
        response = httpx.request(
            method, f"{cfg['base_url']}/api/v1{path}", timeout=300,
            headers={"Authorization": f"Bearer {cfg['token']}"}, **kwargs,
        )
        if response.is_error:
            raise RuntimeError(
                f"{method} {path} failed with status {response.status_code}: "
                f"{response.text.strip()}"
            )
        return response
    
    
    def show_provider(cfg: dict) -> None:
        """Prints the default provider and model, which the chat endpoint uses
        when a request names neither."""
        reply = api(cfg, "GET", "/llm/providers").json()
        default = next((p for p in reply["providers"] if p["isDefault"]), None)
        if default is None:
            raise RuntimeError("The Workbench has no default LLM provider")
        print(f"Provider: {default['name']} (model {reply['defaultModel']})")
    
    
    def chat(cfg: dict, messages: list) -> dict:
        """Sends a conversation to the model and returns the reply.
    
        The messages are the conversation so far, each with a role of user or
        assistant and some content.
        """
        return api(cfg, "POST", "/llm/chat", json={"messages": messages}).json()
    
    
    def reply_text(reply: dict) -> str:
        """Returns the text of a reply on a single line.
    
        A small model may spread its answer over several lines, so the function
        joins the text blocks and collapses the white space. It fails when the
        reply holds no text.
        """
        blocks = [b["text"] for b in reply["content"] if b["type"] == "text"]
        text = " ".join(" ".join(blocks).split())
        if not text:
            raise RuntimeError("The model returned no text")
        return text
    
    
    def main() -> int:
        try:
            cfg = settings()
            show_provider(cfg)
    
            # The first message starts the conversation.
            question = "Name one type of PostgreSQL index, in one sentence."
            messages = [{"role": "user", "content": question}]
            text = reply_text(chat(cfg, messages))
            print(f"Reply: {text}")
    
            # The server keeps no conversation, so the follow-up repeats the
            # earlier messages, including the model's reply, and adds the new
            # question.
            messages += [
                {"role": "assistant", "content": text},
                {"role": "user",
                 "content": "Summarise your answer in five words."},
            ]
            follow_up = chat(cfg, messages)
            print(f"Follow-up reply: {reply_text(follow_up)}")
            print(f"Stop reason: {follow_up['stop_reason']}")
        # httpx.HTTPError covers failures to connect, and RuntimeError covers
        # replies that the server rejected or that lacked what we need.
        except (httpx.HTTPError, RuntimeError) as e:
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
     * Chatting with the LLM through the AI DBA Workbench API, using the built-in
     * fetch.
     *
     * Copyright (c) 2026, pgEdge, Inc.
     * This code is released under the PostgreSQL License.
     */
    
    // The program needs no imports: fetch and process are built in to Node.js.
    
    interface Settings {
      baseUrl: string;
      token: string;
    }
    
    // Read the settings from the environment. The || operator, unlike ??, also
    // treats an empty variable as unset.
    function settings(): Settings {
      const token = process.env.WORKBENCH_TOKEN || "";
      if (!token) throw new Error("WORKBENCH_TOKEN must be set");
      const baseUrl = process.env.WORKBENCH_URL || "http://localhost:8080";
      return { baseUrl: baseUrl.replace(/\/+$/, ""), token };
    }
    
    // Sends a request to the API and returns the response. A request that the
    // server rejects throws an error that includes the message from the server.
    async function api(
      s: Settings,
      method: string,
      path: string,
      body?: unknown,
    ): Promise<Response> {
      const headers: Record<string, string> = {
        Authorization: `Bearer ${s.token}`,
      };
      if (body !== undefined) headers["Content-Type"] = "application/json";
    
      const response = await fetch(`${s.baseUrl}/api/v1${path}`, {
        method,
        headers,
        body: body === undefined ? undefined : JSON.stringify(body),
        // A small model on a CPU can take a while to answer, so the timeout is
        // generous.
        signal: AbortSignal.timeout(300_000),
      });
      if (!response.ok) {
        const text = (await response.text()).trim();
        throw new Error(
          `${method} ${path} failed with status ${response.status}: ${text}`,
        );
      }
      return response;
    }
    
    interface Providers {
      providers: { name: string; isDefault: boolean }[];
      defaultModel: string;
    }
    
    // Prints the default provider and model, which the chat endpoint uses when a
    // request names neither.
    async function showProvider(s: Settings): Promise<void> {
      const reply = (await (
        await api(s, "GET", "/llm/providers")
      ).json()) as Providers;
      const provider = reply.providers.find((p) => p.isDefault);
      if (!provider) throw new Error("The Workbench has no default LLM provider");
      console.log(`Provider: ${provider.name} (model ${reply.defaultModel})`);
    }
    
    interface Message {
      role: "user" | "assistant";
      content: string;
    }
    
    interface ChatReply {
      content: { type: string; text?: string }[];
      stop_reason: string;
    }
    
    // Sends a conversation to the model and returns the reply. The messages are
    // the conversation so far, each with a role of user or assistant and some
    // content.
    async function chat(s: Settings, messages: Message[]): Promise<ChatReply> {
      const response = await api(s, "POST", "/llm/chat", { messages });
      return (await response.json()) as ChatReply;
    }
    
    // Returns the text of a reply on a single line. A small model may spread its
    // answer over several lines, so the function joins the text blocks and
    // collapses the white space. It throws when the reply holds no text.
    function replyText(reply: ChatReply): string {
      const text = reply.content
        .filter((block) => block.type === "text")
        .map((block) => block.text ?? "")
        .join(" ")
        .split(/\s+/)
        .filter((word) => word !== "")
        .join(" ");
      if (!text) throw new Error("The model returned no text");
      return text;
    }
    
    async function main(): Promise<number> {
      try {
        const s = settings();
        await showProvider(s);
    
        // The first message starts the conversation.
        const question = "Name one type of PostgreSQL index, in one sentence.";
        const messages: Message[] = [{ role: "user", content: question }];
        const text = replyText(await chat(s, messages));
        console.log(`Reply: ${text}`);
    
        // The server keeps no conversation, so the follow-up repeats the earlier
        // messages, including the model's reply, and adds the new question.
        messages.push(
          { role: "assistant", content: text },
          { role: "user", content: "Summarise your answer in five words." },
        );
        const followUp = await chat(s, messages);
        console.log(`Follow-up reply: ${replyText(followUp)}`);
        console.log(`Stop reason: ${followUp.stop_reason}`);
      } catch (err) {
        console.error(`Error: ${err instanceof Error ? err.message : err}`);
        return 1;
      }
      return 0;
    }
    
    process.exitCode = await main();
    
    ```

=== "Java"

    ```java
    /*
     * Ellie's Postgres Cookbook
     * Chatting with the LLM through the AI DBA Workbench API, using
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
    import java.util.ArrayList;
    import java.util.List;
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
        record Settings(String baseUrl, String token) {}
    
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
            String token = envOr("WORKBENCH_TOKEN", "");
            if (token.isEmpty()) {
                throw new IOException("WORKBENCH_TOKEN must be set");
            }
            String baseUrl = envOr("WORKBENCH_URL", "http://localhost:8080")
                    .replaceAll("/+$", "");
            return new Settings(baseUrl, token);
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
         * Sends a request to the API and returns the JSON reply. The body may
         * be null. A request that the server rejects throws an error that
         * includes the message from the server.
         */
        static JsonNode api(Settings cfg, String method, String path,
                Object body) throws IOException, InterruptedException {
            // A small model on a CPU can take a while to answer, so the
            // timeout is generous.
            HttpRequest.Builder request = HttpRequest
                    .newBuilder(URI.create(cfg.baseUrl() + "/api/v1" + path))
                    .timeout(Duration.ofSeconds(300))
                    .header("Authorization", "Bearer " + cfg.token());
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
            return JSON.readTree(response.body());
        }
    
        /**
         * Prints the default provider and model, which the chat endpoint uses
         * when a request names neither.
         */
        static void showProvider(Settings cfg)
                throws IOException, InterruptedException {
            JsonNode reply = api(cfg, "GET", "/llm/providers", null);
            for (JsonNode provider : reply.path("providers")) {
                if (provider.path("isDefault").asBoolean(false)) {
                    System.out.println("Provider: "
                            + provider.get("name").asString() + " (model " + reply.get("defaultModel").asString()
                            + ")");
                    return;
                }
            }
            throw new IOException("The Workbench has no default LLM provider");
        }
    
        /**
         * Sends a conversation to the model and returns the reply. The messages
         * are the conversation so far, each with a role of user or assistant
         * and some content.
         */
        static JsonNode chat(Settings cfg, List<Map<String, String>> messages)
                throws IOException, InterruptedException {
            return api(cfg, "POST", "/llm/chat", Map.of("messages", messages));
        }
    
        /**
         * Returns the text of a reply on a single line. A small model may
         * spread its answer over several lines, so the method joins the text
         * blocks and collapses the white space. It fails when the reply holds
         * no text.
         */
        static String replyText(JsonNode reply) throws IOException {
            List<String> blocks = new ArrayList<>();
            for (JsonNode block : reply.path("content")) {
                if ("text".equals(block.path("type").asString())) {
                    blocks.add(block.path("text").asString());
                }
            }
            String text = String.join(" ", blocks).strip().replaceAll("\\s+", " ");
            if (text.isEmpty()) {
                throw new IOException("The model returned no text");
            }
            return text;
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
            try {
                Settings cfg = settings();
                showProvider(cfg);
    
                // The first message starts the conversation.
                String question =
                        "Name one type of PostgreSQL index, in one sentence.";
                List<Map<String, String>> messages = new ArrayList<>();
                messages.add(Map.of("role", "user", "content", question));
                String text = replyText(chat(cfg, messages));
                System.out.println("Reply: " + text);
    
                // The server keeps no conversation, so the follow-up repeats
                // the earlier messages, including the model's reply, and adds
                // the new question.
                messages.add(Map.of("role", "assistant", "content", text));
                messages.add(Map.of("role", "user",
                        "content", "Summarise your answer in five words."));
                JsonNode followUp = chat(cfg, messages);
                System.out.println("Follow-up reply: " + replyText(followUp));
                System.out.println("Stop reason: "
                        + followUp.path("stop_reason").asString());
            // IOException covers failures to connect, replies that the server
            // rejected, and replies that lacked what we need; the client
            // throws InterruptedException if the thread is interrupted, and
            // Jackson throws JacksonException for a reply that is not JSON.
            } catch (IOException | InterruptedException | JacksonException e) {
                System.err.println("Error: " + describe(e));
                status = 1;
            }
            System.exit(status);
        }
    }
    
    ```

=== "C#"

    ```csharp
    /*
     * Ellie's Postgres Cookbook
     * Chatting with the LLM through the AI DBA Workbench API, using
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
    
    // Returns the value of an environment variable, or null if the variable
    // is unset or empty, as an unset variable would be.
    static string? EnvValue(string name) =>
        Environment.GetEnvironmentVariable(name) is { Length: > 0 } value
            ? value
            : null;
    
    // Reads the settings from the environment.
    static (string BaseUrl, string Token) Settings()
    {
        var token = EnvValue("WORKBENCH_TOKEN")
            ?? throw new InvalidOperationException("WORKBENCH_TOKEN must be set");
        var baseUrl = EnvValue("WORKBENCH_URL") ?? "http://localhost:8080";
        return (baseUrl.TrimEnd('/'), token);
    }
    
    // One client serves every request. A small model on a CPU can take a while
    // to answer, so the timeout is generous.
    var http = new HttpClient { Timeout = TimeSpan.FromSeconds(300) };
    
    // Sends a request to the API and returns the JSON reply. A request that the
    // server rejects throws an error that includes the message from the server.
    async Task<JsonNode> Api(string baseUrl, string token, string method,
        string path, object? body = null)
    {
        using var request = new HttpRequestMessage(
            new HttpMethod(method), $"{baseUrl}/api/v1{path}");
        request.Headers.Authorization =
            new AuthenticationHeaderValue("Bearer", token);
        if (body is not null)
        {
            request.Content = JsonContent.Create(body);
        }
    
        using var response = await http.SendAsync(request);
        var text = await response.Content.ReadAsStringAsync();
        if ((int)response.StatusCode >= 400)
        {
            throw new HttpRequestException(
                $"{method} {path} failed with status {(int)response.StatusCode}: "
                + text.Trim());
        }
        return JsonNode.Parse(text)
            ?? throw new InvalidOperationException(
                $"{method} {path} returned no JSON");
    }
    
    // Prints the default provider and model, which the chat endpoint uses when
    // a request names neither.
    async Task ShowProvider(string baseUrl, string token)
    {
        var reply = await Api(baseUrl, token, "GET", "/llm/providers");
        var provider = reply["providers"]?.AsArray()
            .FirstOrDefault(p => p?["isDefault"]?.GetValue<bool>() == true)
            ?? throw new InvalidOperationException(
                "The Workbench has no default LLM provider");
        Console.WriteLine(
            $"Provider: {provider["name"]} (model {reply["defaultModel"]})");
    }
    
    // Sends a conversation to the model and returns the reply. The messages are
    // the conversation so far, each with a role of user or assistant and some
    // content.
    async Task<JsonNode> Chat(string baseUrl, string token,
        List<object> messages) =>
        await Api(baseUrl, token, "POST", "/llm/chat", new { messages });
    
    // Returns the text of a reply on a single line. A small model may spread
    // its answer over several lines, so the function joins the text blocks and
    // collapses the white space. It fails when the reply holds no text.
    static string ReplyText(JsonNode reply)
    {
        var blocks = (reply["content"]?.AsArray() ?? new JsonArray())
            .Where(b => b?["type"]?.GetValue<string>() == "text")
            .Select(b => b!["text"]?.GetValue<string>() ?? "");
        var text = Regex.Replace(string.Join(" ", blocks).Trim(), @"\s+", " ");
        if (text.Length == 0)
        {
            throw new InvalidOperationException("The model returned no text");
        }
        return text;
    }
    
    try
    {
        var (baseUrl, token) = Settings();
        await ShowProvider(baseUrl, token);
    
        // The first message starts the conversation.
        var question = "Name one type of PostgreSQL index, in one sentence.";
        var messages = new List<object>
        {
            new { role = "user", content = question },
        };
        var text = ReplyText(await Chat(baseUrl, token, messages));
        Console.WriteLine($"Reply: {text}");
    
        // The server keeps no conversation, so the follow-up repeats the
        // earlier messages, including the model's reply, and adds the new
        // question.
        messages.Add(new { role = "assistant", content = text });
        messages.Add(new
        {
            role = "user",
            content = "Summarise your answer in five words.",
        });
        var followUp = await Chat(baseUrl, token, messages);
        Console.WriteLine($"Follow-up reply: {ReplyText(followUp)}");
        Console.WriteLine($"Stop reason: {followUp["stop_reason"]}");
    }
    // HttpRequestException covers failures to connect and replies that the
    // server rejected, TaskCanceledException covers a request that timed out,
    // and the others cover replies that lacked what we need.
    catch (Exception e) when (e is HttpRequestException
        or TaskCanceledException or InvalidOperationException or JsonException)
    {
        Console.Error.WriteLine($"Error: {e.Message}");
        return 1;
    }
    return 0;
    
    ```

=== "Go"

    ```go
    /*
     * Ellie's Postgres Cookbook
     * Chatting with the LLM through the AI DBA Workbench API, using net/http.
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
    	baseURL string
    	token   string
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
    		baseURL: strings.TrimRight(envOr("WORKBENCH_URL", "http://localhost:8080"), "/"),
    		token:   os.Getenv("WORKBENCH_TOKEN"),
    	}
    	if s.token == "" {
    		return s, errors.New("WORKBENCH_TOKEN must be set")
    	}
    	return s, nil
    }
    
    
    // client gives every request a timeout; the default client has none. A small
    // model on a CPU can take a while to answer, so the timeout is generous.
    var client = &http.Client{Timeout: 300 * time.Second}
    
    // api sends a request to the API and decodes the JSON reply into out. A
    // request that the server rejects returns an error that includes the message
    // from the server.
    func api(s settings, method, path string, body, out any) error {
    	var reader io.Reader
    	if body != nil {
    		encoded, err := json.Marshal(body)
    		if err != nil {
    			return err
    		}
    		reader = bytes.NewReader(encoded)
    	}
    
    	req, err := http.NewRequest(method, s.baseURL+"/api/v1"+path, reader)
    	if err != nil {
    		return err
    	}
    	req.Header.Set("Authorization", "Bearer "+s.token)
    	if body != nil {
    		req.Header.Set("Content-Type", "application/json")
    	}
    
    	resp, err := client.Do(req)
    	if err != nil {
    		return err
    	}
    	defer resp.Body.Close()
    	if resp.StatusCode >= 400 {
    		text, _ := io.ReadAll(resp.Body)
    		return fmt.Errorf("%s %s failed with status %d: %s",
    			method, path, resp.StatusCode, strings.TrimSpace(string(text)))
    	}
    	return json.NewDecoder(resp.Body).Decode(out)
    }
    
    
    // showProvider prints the default provider and model, which the chat
    // endpoint uses when a request names neither.
    func showProvider(s settings) error {
    	var reply struct {
    		Providers []struct {
    			Name      string `json:"name"`
    			IsDefault bool   `json:"isDefault"`
    		} `json:"providers"`
    		DefaultModel string `json:"defaultModel"`
    	}
    	if err := api(s, "GET", "/llm/providers", nil, &reply); err != nil {
    		return err
    	}
    	for _, p := range reply.Providers {
    		if p.IsDefault {
    			fmt.Printf("Provider: %s (model %s)\n", p.Name, reply.DefaultModel)
    			return nil
    		}
    	}
    	return errors.New("the Workbench has no default LLM provider")
    }
    
    
    // message is one turn of a conversation, with a role of user or assistant.
    type message struct {
    	Role    string `json:"role"`
    	Content string `json:"content"`
    }
    
    // chatReply is the part of the server's reply that the program needs.
    type chatReply struct {
    	Content []struct {
    		Type string `json:"type"`
    		Text string `json:"text"`
    	} `json:"content"`
    	StopReason string `json:"stop_reason"`
    }
    
    // chat sends a conversation to the model and returns the reply. The messages
    // are the conversation so far.
    func chat(s settings, messages []message) (chatReply, error) {
    	var reply chatReply
    	err := api(s, "POST", "/llm/chat", map[string]any{"messages": messages}, &reply)
    	return reply, err
    }
    
    // text returns the text of a reply on a single line. A small model may
    // spread its answer over several lines, so the function joins the text
    // blocks and collapses the white space. It fails when the reply holds no
    // text.
    func (r chatReply) text() (string, error) {
    	var blocks []string
    	for _, block := range r.Content {
    		if block.Type == "text" {
    			blocks = append(blocks, block.Text)
    		}
    	}
    	text := strings.Join(strings.Fields(strings.Join(blocks, " ")), " ")
    	if text == "" {
    		return "", errors.New("the model returned no text")
    	}
    	return text, nil
    }
    
    
    func run() error {
    	s, err := loadSettings()
    	if err != nil {
    		return err
    	}
    	if err := showProvider(s); err != nil {
    		return err
    	}
    
    	// The first message starts the conversation.
    	question := "Name one type of PostgreSQL index, in one sentence."
    	messages := []message{{Role: "user", Content: question}}
    	reply, err := chat(s, messages)
    	if err != nil {
    		return err
    	}
    	text, err := reply.text()
    	if err != nil {
    		return err
    	}
    	fmt.Printf("Reply: %s\n", text)
    
    	// The server keeps no conversation, so the follow-up repeats the earlier
    	// messages, including the model's reply, and adds the new question.
    	messages = append(messages,
    		message{Role: "assistant", Content: text},
    		message{Role: "user", Content: "Summarise your answer in five words."})
    	followUp, err := chat(s, messages)
    	if err != nil {
    		return err
    	}
    	text, err = followUp.text()
    	if err != nil {
    		return err
    	}
    	fmt.Printf("Follow-up reply: %s\n", text)
    	fmt.Printf("Stop reason: %s\n", followUp.StopReason)
    	return nil
    }
    
    func main() {
    	if err := run(); err != nil {
    		fmt.Fprintln(os.Stderr, "Error:", err)
    		os.Exit(1)
    	}
    }
    
    
    ```

=== "Rust"

    ```rust
    // Ellie's Postgres Cookbook
    // Chatting with the LLM through the AI DBA Workbench API, using reqwest
    // and serde_json.
    //
    // Copyright (c) 2026, pgEdge, Inc.
    // This code is released under the PostgreSQL License.
    
    use std::env;
    use std::error::Error;
    use std::process::ExitCode;
    use std::sync::LazyLock;
    use std::time::Duration;
    
    use reqwest::blocking::Client;
    use reqwest::Method;
    use serde_json::{json, Value};
    
    /// Any error, boxed, so that a function can return errors of several types
    /// with the ? operator.
    type Result<T> = std::result::Result<T, Box<dyn Error>>;
    
    /// The settings that the program reads from the environment.
    struct Settings {
        base_url: String,
        token: String,
    }
    
    /// Returns the value of an environment variable, if it is set and not
    /// empty; an empty variable counts as unset.
    fn env_value(name: &str) -> Option<String> {
        env::var(name).ok().filter(|value| !value.is_empty())
    }
    
    /// Reads the settings from the environment.
    fn settings() -> Result<Settings> {
        let token = env_value("WORKBENCH_TOKEN").ok_or("WORKBENCH_TOKEN must be set")?;
        let base_url = env_value("WORKBENCH_URL")
            .unwrap_or_else(|| "http://localhost:8080".to_string())
            .trim_end_matches('/')
            .to_string();
        Ok(Settings { base_url, token })
    }
    
    /// One client serves every request. A small model on a CPU can take a
    /// while to answer, so the timeout is generous.
    static CLIENT: LazyLock<Client> = LazyLock::new(|| {
        Client::builder()
            .timeout(Duration::from_secs(300))
            .build()
            .expect("could not create the HTTP client")
    });
    
    /// Sends a request to the API and returns the JSON reply. A request that
    /// the server rejects returns an error that includes the message from the
    /// server.
    fn api(cfg: &Settings, method: Method, path: &str, body: Option<&Value>) -> Result<Value> {
        let mut request = CLIENT
            .request(method.clone(), format!("{}/api/v1{path}", cfg.base_url))
            .bearer_auth(&cfg.token);
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
        Ok(response.json()?)
    }
    
    /// Prints the default provider and model, which the chat endpoint uses
    /// when a request names neither.
    fn show_provider(cfg: &Settings) -> Result<()> {
        let reply = api(cfg, Method::GET, "/llm/providers", None)?;
        let default = reply["providers"]
            .as_array()
            .and_then(|providers| providers.iter().find(|p| p["isDefault"] == true))
            .ok_or("the Workbench has no default LLM provider")?;
        let name = default["name"].as_str().ok_or("the provider had no name")?;
        let model = reply["defaultModel"]
            .as_str()
            .ok_or("the reply had no default model")?;
        println!("Provider: {name} (model {model})");
        Ok(())
    }
    
    /// Sends a conversation to the model and returns the reply. The messages
    /// are the conversation so far, each with a role of user or assistant and
    /// some content.
    fn chat(cfg: &Settings, messages: &[Value]) -> Result<Value> {
        api(
            cfg,
            Method::POST,
            "/llm/chat",
            Some(&json!({ "messages": messages })),
        )
    }
    
    /// Returns the text of a reply on a single line. A small model may spread
    /// its answer over several lines, so the function joins the text blocks
    /// and collapses the white space. It fails when the reply holds no text.
    fn reply_text(reply: &Value) -> Result<String> {
        let blocks: Vec<&str> = reply["content"]
            .as_array()
            .map(Vec::as_slice)
            .unwrap_or_default()
            .iter()
            .filter(|b| b["type"] == "text")
            .filter_map(|b| b["text"].as_str())
            .collect();
        let joined = blocks.join(" ");
        let text = joined.split_whitespace().collect::<Vec<_>>().join(" ");
        if text.is_empty() {
            return Err("the model returned no text".into());
        }
        Ok(text)
    }
    
    /// Prints an error with the chain of underlying causes, because the
    /// top-level error is often generic ("error sending request").
    fn report(e: &dyn Error) {
        eprintln!("Error: {e}");
        let mut cause = e.source();
        while let Some(c) = cause {
            eprintln!("  caused by: {c}");
            cause = c.source();
        }
    }
    
    fn run() -> Result<()> {
        let cfg = settings()?;
        show_provider(&cfg)?;
    
        // The first message starts the conversation.
        let question = "Name one type of PostgreSQL index, in one sentence.";
        let mut messages = vec![json!({ "role": "user", "content": question })];
        let text = reply_text(&chat(&cfg, &messages)?)?;
        println!("Reply: {text}");
    
        // The server keeps no conversation, so the follow-up repeats the
        // earlier messages, including the model's reply, and adds the new
        // question.
        messages.push(json!({ "role": "assistant", "content": text }));
        messages.push(json!({ "role": "user", "content": "Summarise your answer in five words." }));
        let follow_up = chat(&cfg, &messages)?;
        println!("Follow-up reply: {}", reply_text(&follow_up)?);
        let stop_reason = follow_up["stop_reason"].as_str().unwrap_or_default();
        println!("Stop reason: {stop_reason}");
        Ok(())
    }
    
    fn main() -> ExitCode {
        match run() {
            Ok(()) => ExitCode::SUCCESS,
            Err(e) => {
                report(e.as_ref());
                ExitCode::FAILURE
            }
        }
    }
    
    ```

=== "Ruby"

    ```ruby
    # Ellie's Postgres Cookbook
    # Chatting with the LLM through the AI DBA Workbench API, using Net::HTTP.
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
      token = env_or("WORKBENCH_TOKEN", nil)
      raise "WORKBENCH_TOKEN must be set" unless token
    
      {
        base_url: env_or("WORKBENCH_URL", "http://localhost:8080").sub(%r{/+\z}, ""),
        token: token
      }
    end
    
    # Sends a request to the API and returns the decoded reply. The body, if
    # given, is sent as JSON. A request that the server rejects raises an error
    # that includes the message from the server.
    def api(cfg, method, path, body = nil)
      uri = URI("#{cfg[:base_url]}/api/v1#{path}")
      headers = { "Authorization" => "Bearer #{cfg[:token]}" }
      headers["Content-Type"] = "application/json" if body
    
      # A small model on a CPU can take a while to answer, so the read timeout
      # is generous.
      response = Net::HTTP.start(uri.host, uri.port,
                                 use_ssl: uri.scheme == "https",
                                 open_timeout: 30, read_timeout: 300) do |http|
        http.send_request(method, uri.request_uri, body&.to_json, headers)
      end
      if response.code.to_i >= 400
        raise "#{method} #{path} failed with status #{response.code}: " \
              "#{response.body.to_s.strip}"
      end
      JSON.parse(response.body)
    end
    
    # Prints the default provider and model, which the chat endpoint uses when
    # a request names neither.
    def show_provider(cfg)
      reply = api(cfg, "GET", "/llm/providers")
      default = reply.fetch("providers").find { |p| p["isDefault"] }
      raise "The Workbench has no default LLM provider" if default.nil?
    
      puts "Provider: #{default.fetch('name')} (model #{reply.fetch('defaultModel')})"
    end
    
    # Sends a conversation to the model and returns the reply. The messages are
    # the conversation so far, each with a role of user or assistant and some
    # content.
    def chat(cfg, messages)
      api(cfg, "POST", "/llm/chat", { messages: messages })
    end
    
    # Returns the text of a reply on a single line. A small model may spread
    # its answer over several lines, so the method joins the text blocks and
    # collapses the white space. It fails when the reply holds no text.
    def reply_text(reply)
      blocks = reply.fetch("content").select { |b| b["type"] == "text" }
      text = blocks.map { |b| b["text"] }.join(" ").split.join(" ")
      raise "The model returned no text" if text.empty?
    
      text
    end
    
    def main
      cfg = settings
      show_provider(cfg)
    
      # The first message starts the conversation.
      question = "Name one type of PostgreSQL index, in one sentence."
      messages = [{ role: "user", content: question }]
      text = reply_text(chat(cfg, messages))
      puts "Reply: #{text}"
    
      # The server keeps no conversation, so the follow-up repeats the earlier
      # messages, including the model's reply, and adds the new question.
      messages += [
        { role: "assistant", content: text },
        { role: "user", content: "Summarise your answer in five words." }
      ]
      follow_up = chat(cfg, messages)
      puts "Follow-up reply: #{reply_text(follow_up)}"
      puts "Stop reason: #{follow_up['stop_reason']}"
      0
    # Net::HTTP raises errors of many classes, such as SystemCallError for a
    # refused connection and Net::ReadTimeout for a timeout, and the program
    # raises RuntimeError for replies that the server rejected or that lacked
    # what we need, so this catches StandardError, their common ancestor.
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
    # Chatting with the LLM through the AI DBA Workbench API, using curl and jq.
    #
    # Copyright (c) 2026, pgEdge, Inc.
    # This code is released under the PostgreSQL License.
    
    # Stop at the first failing command, treat an unset variable as an error,
    # and fail a pipeline when any command in it fails.
    set -euo pipefail
    
    # The script needs curl to make the requests and jq to build the requests
    # and read the replies.
    for tool in curl jq; do
        command -v "$tool" >/dev/null || { echo "$tool is required" >&2; exit 1; }
    done
    
    # Read the settings from the environment. The :- and :? forms, unlike - and
    # ?, treat an empty variable as unset.
    WORKBENCH_URL="${WORKBENCH_URL:-http://localhost:8080}"
    WORKBENCH_URL="${WORKBENCH_URL%/}"
    : "${WORKBENCH_TOKEN:?WORKBENCH_TOKEN must be set}"
    
    # Sends an authenticated request and prints the JSON reply:
    # api METHOD PATH [curl options]. With --fail-with-body, a request that the
    # server rejects leaves the server's error message in the reply, and the
    # function prints it to standard error.
    # The token goes to curl in a header file that bash supplies through a pipe,
    # so that it never appears in the arguments of the curl process, which other
    # users can read in the process list.
    api() {
        local method="$1" path="$2"
        shift 2
        local response
        response=$(curl --silent --show-error --fail-with-body \
            --connect-timeout 10 --max-time 300 \
            --request "$method" \
            --header @<(printf 'Authorization: Bearer %s\n' "$WORKBENCH_TOKEN") \
            "$@" "$WORKBENCH_URL/api/v1$path") || {
            echo "$method $path failed: $response" >&2
            return 1
        }
        printf '%s' "$response"
    }
    
    # Prints the default provider and model, which the chat endpoint uses when a
    # request names neither.
    show_provider() {
        local providers
        providers=$(api GET /llm/providers)
        jq -r '"Provider: \(.providers[] | select(.isDefault) | .name) " +
               "(model \(.defaultModel))"' <<<"$providers"
    }
    
    # Sends a conversation to the model and prints the reply as JSON. The
    # argument is the conversation so far, as a JSON array of messages.
    chat() {
        local messages="$1"
        jq -n --argjson messages "$messages" '{messages: $messages}' |
            api POST /llm/chat \
                --header 'Content-Type: application/json' --data @-
    }
    
    # Prints the text of a reply on a single line. A small model may spread its
    # answer over several lines, so the function joins the text blocks and
    # collapses the white space, and it fails when the reply holds no text.
    reply_text() {
        local text
        text=$(jq -r '[.content[] | select(.type == "text") | .text] | join(" ")' \
            <<<"$1" | tr -s '[:space:]' ' ' | sed 's/^ //; s/ $//')
        if [[ -z "$text" ]]; then
            echo "The model returned no text" >&2
            return 1
        fi
        printf '%s\n' "$text"
    }
    
    main() {
        local first second question text
    
        show_provider
    
        # The first message starts the conversation.
        question="Name one type of PostgreSQL index, in one sentence."
        first=$(chat "$(jq -nc --arg q "$question" \
            '[{role: "user", content: $q}]')")
        text=$(reply_text "$first")
        echo "Reply: $text"
    
        # The server keeps no conversation, so the follow-up repeats the earlier
        # messages, including the model's reply, and adds the new question.
        second=$(chat "$(jq -nc --arg q "$question" --arg a "$text" \
            '[{role: "user", content: $q},
              {role: "assistant", content: $a},
              {role: "user", content: "Summarise your answer in five words."}]')")
        text=$(reply_text "$second")
        echo "Follow-up reply: $text"
        echo "Stop reason: $(jq -r '.stop_reason' <<<"$second")"
    }
    
    main
    
    ```

## Next Steps

The following resources provide more information about the topics in this
recipe:

- The [Authenticating with the AI DBA Workbench API](authenticate.md) recipe
  explains how to create the API token that these examples use.
- The [Calling AI DBA Workbench MCP Tools](mcp_tools.md) recipe shows how to
  run queries against a monitored server from a program.
- The AI DBA Workbench
  [API reference](https://github.com/pgEdge/ai-dba-workbench/blob/v1.0.0/docs/admin-guide/api/reference.md)
  describes every endpoint.
