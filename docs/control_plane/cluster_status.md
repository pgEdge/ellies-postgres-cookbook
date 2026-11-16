# Checking the Cluster

This recipe asks a pgEdge Control Plane server for its version, the state of
its cluster, and the state of each host in the cluster. The checks suit a
deployment script that must wait for the Control Plane before it creates a
database, or a monitoring probe that watches the hosts. Each step shows the
code in every supported language; selecting a language tab switches every tab
on the site to that language.

These examples are for the Control Plane v0.11.0.

The program prints the following output when the cluster has one healthy host:

```text
Version: v0.11.0
Cluster: available
Hosts (1):
- cookbook-host-1: healthy
```

## Preparing the Ingredients

The examples assume a running Control Plane server whose cluster has been
initialised. The `scripts/start_control_plane.sh` script in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook)
starts one in Docker, as host `cookbook-host-1`, initialises its cluster, and
prints the environment variables that the Control Plane recipes use.

The program calls three endpoints, and each takes a `GET` request. The
following table describes them:

| Endpoint      | Description                                        |
|---------------|----------------------------------------------------|
| `/v1/version` | Returns the version of the Control Plane server.   |
| `/v1/cluster` | Returns the ID and state of the cluster.           |
| `/v1/hosts`   | Lists the hosts in the cluster, with their states. |

The server answers `/v1/cluster` only once the cluster has been initialised,
and then reports the state `available`, so the health of the cluster shows in
the state of each host instead. A host is `healthy`, `degraded`,
`unreachable` or `unknown`. An error reply carries a JSON body with a `name`
and a `message` that explain the problem.

The following tabs show the dependency declaration from each example project:

=== "Python"

    ```text
    # httpx, an HTTP client with a requests-like API.
    httpx>=0.28,<1
    ```

=== "TypeScript"

    ```json
    {
      "name": "cluster-status",
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
      <!-- Jackson, for reading and writing JSON; the HTTP client is part of
           the JDK. -->
      <dependency>
        <groupId>tools.jackson.core</groupId>
        <artifactId>jackson-databind</artifactId>
        <version>3.2.4</version>
      </dependency>
    </dependencies>
    ```

=== "C#"

    ```xml
    <!-- HttpClient and System.Text.Json are part of .NET, so the project
         needs no packages. -->
    ```

=== "Go"

    ```text
    // The program uses only the standard library, so there is nothing to add.
    ```

=== "Rust"

    ```toml
    [dependencies]
    # The blocking client, with TLS from rustls and request and response bodies
    # as JSON; the default features add HTTP/2 and other things this example
    # does not use.
    reqwest = { version = "0.13", default-features = false, features = ["blocking", "json", "rustls"] }
    serde_json = "1"
    ```

=== "Ruby"

    ```ruby
    source "https://rubygems.org"
    
    # The program uses only Net::HTTP and json from the standard library, so
    # there is no gem to add.
    ```

## Importing the Libraries

Each program begins by importing its HTTP client and JSON library, along with
any standard library modules that it uses, and the curl script checks that
`curl` and `jq` are installed. The following tabs show the imports for each
language:

=== "Python"

    ```python
    import os
    import sys
    
    import httpx
    ```

=== "TypeScript"

    ```typescript
    // Node.js provides fetch and AbortSignal as globals, so this program
    // imports nothing.
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
    ```

=== "Go"

    ```go
    import (
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
    use serde_json::Value;
    ```

=== "Ruby"

    ```ruby
    require "json"
    require "net/http"
    require "uri"
    ```

=== "curl"

    ```bash
    # Stop at the first failed command or unset variable, and treat a failure
    # anywhere in a pipeline as a failure of the whole pipeline.
    set -euo pipefail
    
    for tool in curl jq; do
        command -v "$tool" >/dev/null || { echo "Control Plane error: $tool is required" >&2; exit 1; }
    done
    ```

## Configuring the Program

The examples read the address of the Control Plane from the
`CONTROL_PLANE_URL` environment variable, and treat an empty value as unset.
Each request may take up to 30 seconds. The following table describes the
environment variable:

| Variable            | Default                 | Description                        |
|---------------------|-------------------------|------------------------------------|
| `CONTROL_PLANE_URL` | `http://localhost:3000` | The base URL of the Control Plane. |

The following tabs show how each program reads its settings, and how it fetches
a path from the server:

=== "Python"

    ```python
    # The or operator treats an empty variable as unset.
    BASE_URL = (os.environ.get("CONTROL_PLANE_URL") or "http://localhost:3000").rstrip("/")
    
    TIMEOUT_SECONDS = 30.0
    
    
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
    // The || operator, unlike ??, also treats an empty variable as unset.
    const baseUrl = (process.env.CONTROL_PLANE_URL || "http://localhost:3000").replace(/\/+$/, "");
    
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
    
    static final String BASE_URL =
            envOr("CONTROL_PLANE_URL", "http://localhost:3000")
                    .replaceAll("/+$", "");
    
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
    static string EnvOr(string name, string fallback) =>
        Environment.GetEnvironmentVariable(name) is { Length: > 0 } value
            ? value
            : fallback;
    
    static string BaseUrl() =>
        EnvOr("CONTROL_PLANE_URL", "http://localhost:3000").TrimEnd('/');
    
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
    
    var baseURL = strings.TrimRight(envOr("CONTROL_PLANE_URL", "http://localhost:3000"), "/")
    
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
    /// Returns the value of an environment variable, or a fallback if the
    /// variable is unset or empty.
    fn env_or(name: &str, fallback: &str) -> String {
        env::var(name)
            .ok()
            .filter(|value| !value.is_empty())
            .unwrap_or_else(|| fallback.to_string())
    }
    
    fn base_url() -> String {
        env_or("CONTROL_PLANE_URL", "http://localhost:3000")
            .trim_end_matches('/')
            .to_string()
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
    
    BASE_URL = env_or("CONTROL_PLANE_URL", "http://localhost:3000").sub(%r{/+\z}, "")
    
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
    # The :- operator treats an empty variable as unset.
    CONTROL_PLANE_URL="${CONTROL_PLANE_URL:-http://localhost:3000}"
    CONTROL_PLANE_URL="${CONTROL_PLANE_URL%/}"
    
    TIMEOUT_SECONDS=30
    
    # Fetches a path from the server and prints the JSON reply. With
    # --fail-with-body, curl exits non-zero on an HTTP error status but still
    # prints the body, which carries the server's explanation.
    get() {
        curl --silent --show-error --fail-with-body \
            --max-time "$TIMEOUT_SECONDS" "$CONTROL_PLANE_URL$1"
    }
    ```

## Reading the Version

Each program asks for the version first, because the reply shows that the
server is running and which release of the API it offers. The following tabs
show the version request:

=== "Python"

    ```python
    def show_version(client: httpx.Client) -> None:
        """Prints the version of the Control Plane server."""
        version = get(client, "/v1/version").get("version")
        if not isinstance(version, str):
            raise ControlPlaneError("Unexpected response: missing version")
        print(f"Version: {version}")
    ```

=== "TypeScript"

    ```typescript
    // Prints the version of the Control Plane server.
    async function showVersion(): Promise<void> {
      const body = await get<{ version?: unknown }>("/v1/version");
      if (typeof body.version !== "string") {
        throw new Error("Unexpected response: missing version");
      }
      console.log(`Version: ${body.version}`);
    }
    ```

=== "Java"

    ```java
    /** Prints the version of the Control Plane server. */
    static void showVersion(HttpClient client)
            throws IOException, InterruptedException, ControlPlaneException {
        JsonNode version = get(client, "/v1/version").path("version");
        if (!version.isString()) {
            throw new ControlPlaneException("Unexpected response: missing version");
        }
        System.out.println("Version: " + version.stringValue());
    }
    ```

=== "C#"

    ```csharp
    // Prints the version of the Control Plane server.
    static async Task ShowVersionAsync(HttpClient client)
    {
        var reply = await GetAsync(client, "/v1/version");
        if (reply["version"] is not JsonValue node ||
            !node.TryGetValue(out string? version))
        {
            throw new ControlPlaneException("Unexpected response: missing version");
        }
        Console.WriteLine($"Version: {version}");
    }
    ```

=== "Go"

    ```go
    // showVersion prints the version of the Control Plane server.
    func showVersion(client *http.Client) error {
    	var body struct {
    		Version *string `json:"version"`
    	}
    	if err := get(client, "/v1/version", &body); err != nil {
    		return err
    	}
    	if body.Version == nil {
    		return errors.New("unexpected response: missing version")
    	}
    	fmt.Printf("Version: %s\n", *body.Version)
    	return nil
    }
    
    ```

=== "Rust"

    ```rust
    /// Prints the version of the Control Plane server.
    fn show_version(client: &Client) -> Result<(), BoxError> {
        let reply = get(client, "/v1/version")?;
        let Some(version) = reply["version"].as_str() else {
            return Err("Unexpected response: missing version".into());
        };
        println!("Version: {version}");
        Ok(())
    }
    ```

=== "Ruby"

    ```ruby
    # Prints the version of the Control Plane server.
    def show_version(http)
      version = get(http, "/v1/version")["version"]
      raise ControlPlaneError, "Unexpected response: missing version" unless version.is_a?(String)
    
      puts "Version: #{version}"
    end
    ```

=== "curl"

    ```bash
    # Prints the version of the Control Plane server.
    show_version() {
        local response
        response="$(get /v1/version)" || {
            echo "Control Plane error: $response" >&2
            return 1
        }
        jq -er '"Version: \(.version | strings)"' <<<"$response" || {
            echo "Unexpected response: $response" >&2
            return 1
        }
    }
    ```

## Reading the Cluster State

Each program then reads the state of the cluster from the `status` object of
the reply. The following tabs show the cluster request:

=== "Python"

    ```python
    def show_cluster(client: httpx.Client) -> None:
        """Prints the state of the cluster. A server answers this request only
        once its cluster has been initialised, and it then reports
        "available"; the health of the cluster shows in the state of each
        host."""
        state = (get(client, "/v1/cluster").get("status") or {}).get("state")
        if not isinstance(state, str):
            raise ControlPlaneError("Unexpected response: missing state")
        print(f"Cluster: {state}")
    ```

=== "TypeScript"

    ```typescript
    // Prints the state of the cluster. A server answers this request only
    // once its cluster has been initialised, and it then reports "available";
    // the health of the cluster shows in the state of each host.
    async function showCluster(): Promise<void> {
      const body = await get<{ status?: { state?: unknown } }>("/v1/cluster");
      if (typeof body.status?.state !== "string") {
        throw new Error("Unexpected response: missing state");
      }
      console.log(`Cluster: ${body.status.state}`);
    }
    ```

=== "Java"

    ```java
    /**
     * Prints the state of the cluster. A server answers this request only
     * once its cluster has been initialised, and it then reports
     * "available"; the health of the cluster shows in the state of each
     * host.
     */
    static void showCluster(HttpClient client)
            throws IOException, InterruptedException, ControlPlaneException {
        JsonNode state = get(client, "/v1/cluster").path("status").path("state");
        if (!state.isString()) {
            throw new ControlPlaneException("Unexpected response: missing state");
        }
        System.out.println("Cluster: " + state.stringValue());
    }
    ```

=== "C#"

    ```csharp
    // Prints the state of the cluster. A server answers this request only once
    // its cluster has been initialised, and it then reports "available"; the
    // health of the cluster shows in the state of each host.
    static async Task ShowClusterAsync(HttpClient client)
    {
        var reply = await GetAsync(client, "/v1/cluster");
        if (reply["status"]?["state"] is not JsonValue node ||
            !node.TryGetValue(out string? state))
        {
            throw new ControlPlaneException("Unexpected response: missing state");
        }
        Console.WriteLine($"Cluster: {state}");
    }
    ```

=== "Go"

    ```go
    // showCluster prints the state of the cluster. A server answers this
    // request only once its cluster has been initialised, and it then reports
    // "available"; the health of the cluster shows in the state of each host.
    func showCluster(client *http.Client) error {
    	var body struct {
    		Status struct {
    			State *string `json:"state"`
    		} `json:"status"`
    	}
    	if err := get(client, "/v1/cluster", &body); err != nil {
    		return err
    	}
    	if body.Status.State == nil {
    		return errors.New("unexpected response: missing state")
    	}
    	fmt.Printf("Cluster: %s\n", *body.Status.State)
    	return nil
    }
    
    ```

=== "Rust"

    ```rust
    /// Prints the state of the cluster. A server answers this request only
    /// once its cluster has been initialised, and it then reports
    /// "available"; the health of the cluster shows in the state of each host.
    fn show_cluster(client: &Client) -> Result<(), BoxError> {
        let reply = get(client, "/v1/cluster")?;
        let Some(state) = reply["status"]["state"].as_str() else {
            return Err("Unexpected response: missing state".into());
        };
        println!("Cluster: {state}");
        Ok(())
    }
    ```

=== "Ruby"

    ```ruby
    # Prints the state of the cluster. A server answers this request only once
    # its cluster has been initialised, and it then reports "available"; the
    # health of the cluster shows in the state of each host.
    def show_cluster(http)
      state = (get(http, "/v1/cluster")["status"] || {})["state"]
      raise ControlPlaneError, "Unexpected response: missing state" unless state.is_a?(String)
    
      puts "Cluster: #{state}"
    end
    ```

=== "curl"

    ```bash
    # Prints the state of the cluster. A server answers this request only once
    # its cluster has been initialised, and it then reports "available"; the
    # health of the cluster shows in the state of each host.
    show_cluster() {
        local response
        response="$(get /v1/cluster)" || {
            echo "Control Plane error: $response" >&2
            return 1
        }
        jq -er '"Cluster: \(.status.state | strings)"' <<<"$response" || {
            echo "Unexpected response: $response" >&2
            return 1
        }
    }
    ```

## Listing the Hosts

Each program lists every host with its state, and notes whether any host is
not `healthy`. The following tabs show how each program lists the hosts:

=== "Python"

    ```python
    def show_hosts(client: httpx.Client) -> bool:
        """Lists the hosts in the cluster with their states, and returns
        whether every host is "healthy". The other states are "degraded",
        "unreachable" and "unknown"."""
        hosts = get(client, "/v1/hosts").get("hosts")
        if not isinstance(hosts, list):
            raise ControlPlaneError("Unexpected response: missing hosts")
    
        print(f"Hosts ({len(hosts)}):")
        healthy = True
        for host in hosts:
            state = (host.get("status") or {}).get("state", "unknown")
            print(f"- {host.get('id')}: {state}")
            healthy = healthy and state == "healthy"
        return healthy
    ```

=== "TypeScript"

    ```typescript
    interface Host {
      id?: string;
      status?: { state?: string };
    }
    
    // Lists the hosts in the cluster with their states, and returns whether
    // every host is "healthy". The other states are "degraded", "unreachable"
    // and "unknown".
    async function showHosts(): Promise<boolean> {
      const body = await get<{ hosts?: Host[] }>("/v1/hosts");
      if (!Array.isArray(body.hosts)) {
        throw new Error("Unexpected response: missing hosts");
      }
    
      console.log(`Hosts (${body.hosts.length}):`);
      let healthy = true;
      for (const host of body.hosts) {
        const state = host.status?.state ?? "unknown";
        console.log(`- ${host.id}: ${state}`);
        healthy &&= state === "healthy";
      }
      return healthy;
    }
    ```

=== "Java"

    ```java
    /**
     * Lists the hosts in the cluster with their states, and returns whether
     * every host is "healthy". The other states are "degraded",
     * "unreachable" and "unknown".
     */
    static boolean showHosts(HttpClient client)
            throws IOException, InterruptedException, ControlPlaneException {
        JsonNode hosts = get(client, "/v1/hosts").path("hosts");
        if (!hosts.isArray()) {
            throw new ControlPlaneException("Unexpected response: missing hosts");
        }
    
        System.out.println("Hosts (" + hosts.size() + "):");
        boolean healthy = true;
        for (JsonNode host : hosts) {
            String state = host.path("status").path("state").asString("unknown");
            System.out.println("- " + host.path("id").asString() + ": " + state);
            healthy = healthy && state.equals("healthy");
        }
        return healthy;
    }
    ```

=== "C#"

    ```csharp
    // Lists the hosts in the cluster with their states, and returns whether
    // every host is "healthy". The other states are "degraded", "unreachable"
    // and "unknown".
    static async Task<bool> ShowHostsAsync(HttpClient client)
    {
        var reply = await GetAsync(client, "/v1/hosts");
        if (reply["hosts"] is not JsonArray hosts)
        {
            throw new ControlPlaneException("Unexpected response: missing hosts");
        }
    
        Console.WriteLine($"Hosts ({hosts.Count}):");
        var healthy = true;
        foreach (var host in hosts)
        {
            var state = host?["status"]?["state"]?.ToString() ?? "unknown";
            Console.WriteLine($"- {host?["id"]}: {state}");
            healthy = healthy && state == "healthy";
        }
        return healthy;
    }
    ```

=== "Go"

    ```go
    // showHosts lists the hosts in the cluster with their states, and returns
    // whether every host is "healthy". The other states are "degraded",
    // "unreachable" and "unknown".
    func showHosts(client *http.Client) (bool, error) {
    	var body struct {
    		Hosts *[]struct {
    			ID     string `json:"id"`
    			Status struct {
    				State string `json:"state"`
    			} `json:"status"`
    		} `json:"hosts"`
    	}
    	if err := get(client, "/v1/hosts", &body); err != nil {
    		return false, err
    	}
    	if body.Hosts == nil {
    		return false, errors.New("unexpected response: missing hosts")
    	}
    
    	fmt.Printf("Hosts (%d):\n", len(*body.Hosts))
    	healthy := true
    	for _, host := range *body.Hosts {
    		state := host.Status.State
    		if state == "" {
    			state = "unknown"
    		}
    		fmt.Printf("- %s: %s\n", host.ID, state)
    		healthy = healthy && state == "healthy"
    	}
    	return healthy, nil
    }
    
    ```

=== "Rust"

    ```rust
    /// Lists the hosts in the cluster with their states, and returns whether
    /// every host is "healthy". The other states are "degraded",
    /// "unreachable" and "unknown".
    fn show_hosts(client: &Client) -> Result<bool, BoxError> {
        let reply = get(client, "/v1/hosts")?;
        let Some(hosts) = reply["hosts"].as_array() else {
            return Err("Unexpected response: missing hosts".into());
        };
    
        println!("Hosts ({}):", hosts.len());
        let mut healthy = true;
        for host in hosts {
            let state = host["status"]["state"].as_str().unwrap_or("unknown");
            println!("- {}: {state}", host["id"].as_str().unwrap_or(""));
            healthy = healthy && state == "healthy";
        }
        Ok(healthy)
    }
    ```

=== "Ruby"

    ```ruby
    # Lists the hosts in the cluster with their states, and returns whether
    # every host is "healthy". The other states are "degraded", "unreachable"
    # and "unknown".
    def show_hosts(http)
      hosts = get(http, "/v1/hosts")["hosts"]
      raise ControlPlaneError, "Unexpected response: missing hosts" unless hosts.is_a?(Array)
    
      puts "Hosts (#{hosts.length}):"
      hosts.map do |host|
        state = (host["status"] || {}).fetch("state", "unknown")
        puts "- #{host["id"]}: #{state}"
        state == "healthy"
      end.all?
    end
    ```

=== "curl"

    ```bash
    # Lists the hosts in the cluster with their states, and fails when a
    # request or reply fails or when a host is anything but "healthy". The
    # other states are "degraded", "unreachable" and "unknown".
    show_hosts() {
        local response
        response="$(get /v1/hosts)" || {
            echo "Control Plane error: $response" >&2
            return 1
        }
        jq -er '
            if (.hosts | type) != "array" then error("missing hosts") else
                "Hosts (\(.hosts | length)):",
                (.hosts[] | "- \(.id): \(.status.state // "unknown")")
            end' <<<"$response" || {
            echo "Unexpected response: $response" >&2
            return 1
        }
        jq -e 'all(.hosts[]; .status.state == "healthy")' <<<"$response" >/dev/null || {
            echo "A host is not healthy" >&2
            return 1
        }
    }
    ```

## Handling Errors

The main part of each program runs the three checks, reports any failure on
`stderr`, and exits with a non-zero status when the server is unreachable or a
host is not healthy, so that a script can act on the result. The following tabs
show the main part of each program:

=== "Python"

    ```python
    def main() -> int:
        try:
            with httpx.Client(base_url=BASE_URL, timeout=TIMEOUT_SECONDS) as client:
                show_version(client)
                show_cluster(client)
                healthy = show_hosts(client)
        # httpx.HTTPError is the base class for failures to reach the server,
        # such as a refused connection or a timeout.
        except (httpx.HTTPError, ControlPlaneError) as e:
            print(f"Control Plane error: {e}", file=sys.stderr)
            return 1
    
        # Report an unhealthy host with the exit status.
        if not healthy:
            print("A host is not healthy", file=sys.stderr)
            return 1
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
      try {
        await showVersion();
        await showCluster();
        const healthy = await showHosts();
    
        // Report an unhealthy host with the exit status.
        if (!healthy) {
          console.error("A host is not healthy");
          return 1;
        }
        return 0;
      } catch (err) {
        console.error(`Control Plane error: ${describe(err)}`);
        return 1;
      }
    }
    
    process.exitCode = await main();
    ```

=== "Java"

    ```java
    public static void main(String[] args) {
        HttpClient client = HttpClient.newHttpClient();
        boolean healthy;
        try {
            showVersion(client);
            showCluster(client);
            healthy = showHosts(client);
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
    
        // Report an unhealthy host with the exit status.
        if (!healthy) {
            System.err.println("A host is not healthy");
            System.exit(1);
        }
    }
    ```

=== "C#"

    ```csharp
    bool healthy;
    try
    {
        // using disposes of the client, and closes its connections, when the
        // block exits, whether or not an error occurred.
        using var client = new HttpClient
        {
            Timeout = TimeSpan.FromSeconds(TimeoutSeconds),
        };
        await ShowVersionAsync(client);
        await ShowClusterAsync(client);
        healthy = await ShowHostsAsync(client);
    }
    // HttpRequestException covers failures to reach the server, such as a
    // refused connection, and TaskCanceledException covers a timeout.
    catch (Exception e) when (
        e is HttpRequestException or TaskCanceledException or ControlPlaneException)
    {
        Console.Error.WriteLine($"Control Plane error: {e.Message}");
        return 1;
    }
    
    // Report an unhealthy host with the exit status.
    if (!healthy)
    {
        Console.Error.WriteLine("A host is not healthy");
        return 1;
    }
    return 0;
    
    // C# requires type declarations to follow the top-level statements, so
    // the exception that the program throws for an error reply is declared
    // here, at the end.
    class ControlPlaneException(string message) : Exception(message);
    ```

=== "Go"

    ```go
    // run performs the checks and returns any error to the caller.
    func run() error {
    	client := &http.Client{Timeout: timeout}
    
    	if err := showVersion(client); err != nil {
    		return err
    	}
    	if err := showCluster(client); err != nil {
    		return err
    	}
    	healthy, err := showHosts(client)
    	if err != nil {
    		return err
    	}
    
    	// Report an unhealthy host with the exit status.
    	if !healthy {
    		return errors.New("a host is not healthy")
    	}
    	return nil
    }
    
    // main reports any error returned by run() and exits with a non-zero
    // status.
    func main() {
    	if err := run(); err != nil {
    		fmt.Fprintf(os.Stderr, "Control Plane error: %v\n", err)
    		os.Exit(1)
    	}
    }
    
    ```

=== "Rust"

    ```rust
    /// Runs the three checks, and returns whether every host is healthy. The
    /// ? operator returns any error to the caller.
    fn run() -> Result<bool, BoxError> {
        let client = Client::builder().timeout(TIMEOUT).build()?;
        show_version(&client)?;
        show_cluster(&client)?;
        show_hosts(&client)
    }
    
    /// Reports any error returned by run() and exits with a failure status.
    /// The top-level error is often generic ("error sending request"), so the
    /// chain of underlying causes is printed too.
    fn main() -> ExitCode {
        match run() {
            Ok(true) => ExitCode::SUCCESS,
            // Report an unhealthy host with the exit status.
            Ok(false) => {
                eprintln!("A host is not healthy");
                ExitCode::FAILURE
            }
            Err(e) => {
                eprintln!("Control Plane error: {e}");
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
      uri = URI(BASE_URL)
      # start opens a connection, and closes it when the block exits, whether
      # or not an error occurred.
      healthy = Net::HTTP.start(
        uri.host, uri.port,
        use_ssl: uri.scheme == "https",
        open_timeout: TIMEOUT_SECONDS, read_timeout: TIMEOUT_SECONDS
      ) do |http|
        show_version(http)
        show_cluster(http)
        show_hosts(http)
      end
    # SystemCallError covers a refused connection, Timeout::Error covers the
    # connection and read timeouts, and SocketError covers an unknown host.
    rescue ControlPlaneError, SystemCallError, Timeout::Error, SocketError, IOError => e
      warn "Control Plane error: #{e.message}"
      exit 1
    end
    
    # Report an unhealthy host with the exit status.
    unless healthy
      warn "A host is not healthy"
      exit 1
    end
    ```

=== "curl"

    ```bash
    main() {
        # Any failure, including an unhealthy host, gives a non-zero exit
        # status.
        show_version || exit 1
        show_cluster || exit 1
        show_hosts || exit 1
    }
    
    main
    ```

## Running the Example

The complete project for each language is available in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/control_plane/cluster_status).
Set the environment variables for your Control Plane, and then run the command
for your language from the corresponding project directory. The following tabs
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
    Checking the version of the pgEdge Control Plane, its cluster, and the
    state of each host, using httpx.
    
    These examples are for the Control Plane v0.11.0.
    
    Copyright (c) 2026, pgEdge, Inc.
    This code is released under the PostgreSQL License.
    """
    
    import os
    import sys
    
    import httpx
    
    
    # The or operator treats an empty variable as unset.
    BASE_URL = (os.environ.get("CONTROL_PLANE_URL") or "http://localhost:3000").rstrip("/")
    
    TIMEOUT_SECONDS = 30.0
    
    
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
    
    
    def show_version(client: httpx.Client) -> None:
        """Prints the version of the Control Plane server."""
        version = get(client, "/v1/version").get("version")
        if not isinstance(version, str):
            raise ControlPlaneError("Unexpected response: missing version")
        print(f"Version: {version}")
    
    
    def show_cluster(client: httpx.Client) -> None:
        """Prints the state of the cluster. A server answers this request only
        once its cluster has been initialised, and it then reports
        "available"; the health of the cluster shows in the state of each
        host."""
        state = (get(client, "/v1/cluster").get("status") or {}).get("state")
        if not isinstance(state, str):
            raise ControlPlaneError("Unexpected response: missing state")
        print(f"Cluster: {state}")
    
    
    def show_hosts(client: httpx.Client) -> bool:
        """Lists the hosts in the cluster with their states, and returns
        whether every host is "healthy". The other states are "degraded",
        "unreachable" and "unknown"."""
        hosts = get(client, "/v1/hosts").get("hosts")
        if not isinstance(hosts, list):
            raise ControlPlaneError("Unexpected response: missing hosts")
    
        print(f"Hosts ({len(hosts)}):")
        healthy = True
        for host in hosts:
            state = (host.get("status") or {}).get("state", "unknown")
            print(f"- {host.get('id')}: {state}")
            healthy = healthy and state == "healthy"
        return healthy
    
    
    def main() -> int:
        try:
            with httpx.Client(base_url=BASE_URL, timeout=TIMEOUT_SECONDS) as client:
                show_version(client)
                show_cluster(client)
                healthy = show_hosts(client)
        # httpx.HTTPError is the base class for failures to reach the server,
        # such as a refused connection or a timeout.
        except (httpx.HTTPError, ControlPlaneError) as e:
            print(f"Control Plane error: {e}", file=sys.stderr)
            return 1
    
        # Report an unhealthy host with the exit status.
        if not healthy:
            print("A host is not healthy", file=sys.stderr)
            return 1
        return 0
    
    
    if __name__ == "__main__":
        sys.exit(main())
    
    ```

=== "TypeScript"

    ```typescript
    /*
     * Ellie's Postgres Cookbook
     * Checking the version of the pgEdge Control Plane, its cluster, and the
     * state of each host, using the built-in fetch.
     *
     * These examples are for the Control Plane v0.11.0.
     *
     * Copyright (c) 2026, pgEdge, Inc.
     * This code is released under the PostgreSQL License.
     */
    
    // Node.js provides fetch and AbortSignal as globals, so this program
    // imports nothing.
    
    // The || operator, unlike ??, also treats an empty variable as unset.
    const baseUrl = (process.env.CONTROL_PLANE_URL || "http://localhost:3000").replace(/\/+$/, "");
    
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
    
    // Prints the version of the Control Plane server.
    async function showVersion(): Promise<void> {
      const body = await get<{ version?: unknown }>("/v1/version");
      if (typeof body.version !== "string") {
        throw new Error("Unexpected response: missing version");
      }
      console.log(`Version: ${body.version}`);
    }
    
    // Prints the state of the cluster. A server answers this request only
    // once its cluster has been initialised, and it then reports "available";
    // the health of the cluster shows in the state of each host.
    async function showCluster(): Promise<void> {
      const body = await get<{ status?: { state?: unknown } }>("/v1/cluster");
      if (typeof body.status?.state !== "string") {
        throw new Error("Unexpected response: missing state");
      }
      console.log(`Cluster: ${body.status.state}`);
    }
    
    interface Host {
      id?: string;
      status?: { state?: string };
    }
    
    // Lists the hosts in the cluster with their states, and returns whether
    // every host is "healthy". The other states are "degraded", "unreachable"
    // and "unknown".
    async function showHosts(): Promise<boolean> {
      const body = await get<{ hosts?: Host[] }>("/v1/hosts");
      if (!Array.isArray(body.hosts)) {
        throw new Error("Unexpected response: missing hosts");
      }
    
      console.log(`Hosts (${body.hosts.length}):`);
      let healthy = true;
      for (const host of body.hosts) {
        const state = host.status?.state ?? "unknown";
        console.log(`- ${host.id}: ${state}`);
        healthy &&= state === "healthy";
      }
      return healthy;
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
      try {
        await showVersion();
        await showCluster();
        const healthy = await showHosts();
    
        // Report an unhealthy host with the exit status.
        if (!healthy) {
          console.error("A host is not healthy");
          return 1;
        }
        return 0;
      } catch (err) {
        console.error(`Control Plane error: ${describe(err)}`);
        return 1;
      }
    }
    
    process.exitCode = await main();
    
    ```

=== "Java"

    ```java
    /*
     * Ellie's Postgres Cookbook
     * Checking the version of the pgEdge Control Plane, its cluster, and the
     * state of each host, using java.net.http and Jackson.
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
    import java.time.Duration;
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
    
        static final String BASE_URL =
                envOr("CONTROL_PLANE_URL", "http://localhost:3000")
                        .replaceAll("/+$", "");
    
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
    
        /** Prints the version of the Control Plane server. */
        static void showVersion(HttpClient client)
                throws IOException, InterruptedException, ControlPlaneException {
            JsonNode version = get(client, "/v1/version").path("version");
            if (!version.isString()) {
                throw new ControlPlaneException("Unexpected response: missing version");
            }
            System.out.println("Version: " + version.stringValue());
        }
    
        /**
         * Prints the state of the cluster. A server answers this request only
         * once its cluster has been initialised, and it then reports
         * "available"; the health of the cluster shows in the state of each
         * host.
         */
        static void showCluster(HttpClient client)
                throws IOException, InterruptedException, ControlPlaneException {
            JsonNode state = get(client, "/v1/cluster").path("status").path("state");
            if (!state.isString()) {
                throw new ControlPlaneException("Unexpected response: missing state");
            }
            System.out.println("Cluster: " + state.stringValue());
        }
    
        /**
         * Lists the hosts in the cluster with their states, and returns whether
         * every host is "healthy". The other states are "degraded",
         * "unreachable" and "unknown".
         */
        static boolean showHosts(HttpClient client)
                throws IOException, InterruptedException, ControlPlaneException {
            JsonNode hosts = get(client, "/v1/hosts").path("hosts");
            if (!hosts.isArray()) {
                throw new ControlPlaneException("Unexpected response: missing hosts");
            }
    
            System.out.println("Hosts (" + hosts.size() + "):");
            boolean healthy = true;
            for (JsonNode host : hosts) {
                String state = host.path("status").path("state").asString("unknown");
                System.out.println("- " + host.path("id").asString() + ": " + state);
                healthy = healthy && state.equals("healthy");
            }
            return healthy;
        }
    
        public static void main(String[] args) {
            HttpClient client = HttpClient.newHttpClient();
            boolean healthy;
            try {
                showVersion(client);
                showCluster(client);
                healthy = showHosts(client);
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
    
            // Report an unhealthy host with the exit status.
            if (!healthy) {
                System.err.println("A host is not healthy");
                System.exit(1);
            }
        }
    }
    
    ```

=== "C#"

    ```csharp
    /*
     * Ellie's Postgres Cookbook
     * Checking the version of the pgEdge Control Plane, its cluster, and the
     * state of each host, using HttpClient and System.Text.Json.
     *
     * These examples are for the Control Plane v0.11.0.
     *
     * Copyright (c) 2026, pgEdge, Inc.
     * This code is released under the PostgreSQL License.
     */
    
    using System.Text.Json;
    using System.Text.Json.Nodes;
    
    // Returns the value of an environment variable, or a fallback if the
    // variable is unset or empty.
    static string EnvOr(string name, string fallback) =>
        Environment.GetEnvironmentVariable(name) is { Length: > 0 } value
            ? value
            : fallback;
    
    static string BaseUrl() =>
        EnvOr("CONTROL_PLANE_URL", "http://localhost:3000").TrimEnd('/');
    
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
    
    // Prints the version of the Control Plane server.
    static async Task ShowVersionAsync(HttpClient client)
    {
        var reply = await GetAsync(client, "/v1/version");
        if (reply["version"] is not JsonValue node ||
            !node.TryGetValue(out string? version))
        {
            throw new ControlPlaneException("Unexpected response: missing version");
        }
        Console.WriteLine($"Version: {version}");
    }
    
    // Prints the state of the cluster. A server answers this request only once
    // its cluster has been initialised, and it then reports "available"; the
    // health of the cluster shows in the state of each host.
    static async Task ShowClusterAsync(HttpClient client)
    {
        var reply = await GetAsync(client, "/v1/cluster");
        if (reply["status"]?["state"] is not JsonValue node ||
            !node.TryGetValue(out string? state))
        {
            throw new ControlPlaneException("Unexpected response: missing state");
        }
        Console.WriteLine($"Cluster: {state}");
    }
    
    // Lists the hosts in the cluster with their states, and returns whether
    // every host is "healthy". The other states are "degraded", "unreachable"
    // and "unknown".
    static async Task<bool> ShowHostsAsync(HttpClient client)
    {
        var reply = await GetAsync(client, "/v1/hosts");
        if (reply["hosts"] is not JsonArray hosts)
        {
            throw new ControlPlaneException("Unexpected response: missing hosts");
        }
    
        Console.WriteLine($"Hosts ({hosts.Count}):");
        var healthy = true;
        foreach (var host in hosts)
        {
            var state = host?["status"]?["state"]?.ToString() ?? "unknown";
            Console.WriteLine($"- {host?["id"]}: {state}");
            healthy = healthy && state == "healthy";
        }
        return healthy;
    }
    
    bool healthy;
    try
    {
        // using disposes of the client, and closes its connections, when the
        // block exits, whether or not an error occurred.
        using var client = new HttpClient
        {
            Timeout = TimeSpan.FromSeconds(TimeoutSeconds),
        };
        await ShowVersionAsync(client);
        await ShowClusterAsync(client);
        healthy = await ShowHostsAsync(client);
    }
    // HttpRequestException covers failures to reach the server, such as a
    // refused connection, and TaskCanceledException covers a timeout.
    catch (Exception e) when (
        e is HttpRequestException or TaskCanceledException or ControlPlaneException)
    {
        Console.Error.WriteLine($"Control Plane error: {e.Message}");
        return 1;
    }
    
    // Report an unhealthy host with the exit status.
    if (!healthy)
    {
        Console.Error.WriteLine("A host is not healthy");
        return 1;
    }
    return 0;
    
    // C# requires type declarations to follow the top-level statements, so
    // the exception that the program throws for an error reply is declared
    // here, at the end.
    class ControlPlaneException(string message) : Exception(message);
    
    ```

=== "Go"

    ```go
    // Ellie's Postgres Cookbook
    // Checking the version of the pgEdge Control Plane, its cluster, and the
    // state of each host, using net/http.
    //
    // These examples are for the Control Plane v0.11.0.
    //
    // Copyright (c) 2026, pgEdge, Inc.
    // This code is released under the PostgreSQL License.
    
    package main
    
    import (
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
    
    var baseURL = strings.TrimRight(envOr("CONTROL_PLANE_URL", "http://localhost:3000"), "/")
    
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
    
    
    // showVersion prints the version of the Control Plane server.
    func showVersion(client *http.Client) error {
    	var body struct {
    		Version *string `json:"version"`
    	}
    	if err := get(client, "/v1/version", &body); err != nil {
    		return err
    	}
    	if body.Version == nil {
    		return errors.New("unexpected response: missing version")
    	}
    	fmt.Printf("Version: %s\n", *body.Version)
    	return nil
    }
    
    
    // showCluster prints the state of the cluster. A server answers this
    // request only once its cluster has been initialised, and it then reports
    // "available"; the health of the cluster shows in the state of each host.
    func showCluster(client *http.Client) error {
    	var body struct {
    		Status struct {
    			State *string `json:"state"`
    		} `json:"status"`
    	}
    	if err := get(client, "/v1/cluster", &body); err != nil {
    		return err
    	}
    	if body.Status.State == nil {
    		return errors.New("unexpected response: missing state")
    	}
    	fmt.Printf("Cluster: %s\n", *body.Status.State)
    	return nil
    }
    
    
    // showHosts lists the hosts in the cluster with their states, and returns
    // whether every host is "healthy". The other states are "degraded",
    // "unreachable" and "unknown".
    func showHosts(client *http.Client) (bool, error) {
    	var body struct {
    		Hosts *[]struct {
    			ID     string `json:"id"`
    			Status struct {
    				State string `json:"state"`
    			} `json:"status"`
    		} `json:"hosts"`
    	}
    	if err := get(client, "/v1/hosts", &body); err != nil {
    		return false, err
    	}
    	if body.Hosts == nil {
    		return false, errors.New("unexpected response: missing hosts")
    	}
    
    	fmt.Printf("Hosts (%d):\n", len(*body.Hosts))
    	healthy := true
    	for _, host := range *body.Hosts {
    		state := host.Status.State
    		if state == "" {
    			state = "unknown"
    		}
    		fmt.Printf("- %s: %s\n", host.ID, state)
    		healthy = healthy && state == "healthy"
    	}
    	return healthy, nil
    }
    
    
    // run performs the checks and returns any error to the caller.
    func run() error {
    	client := &http.Client{Timeout: timeout}
    
    	if err := showVersion(client); err != nil {
    		return err
    	}
    	if err := showCluster(client); err != nil {
    		return err
    	}
    	healthy, err := showHosts(client)
    	if err != nil {
    		return err
    	}
    
    	// Report an unhealthy host with the exit status.
    	if !healthy {
    		return errors.New("a host is not healthy")
    	}
    	return nil
    }
    
    // main reports any error returned by run() and exits with a non-zero
    // status.
    func main() {
    	if err := run(); err != nil {
    		fmt.Fprintf(os.Stderr, "Control Plane error: %v\n", err)
    		os.Exit(1)
    	}
    }
    
    
    ```

=== "Rust"

    ```rust
    // Ellie's Postgres Cookbook
    // Checking the version of the pgEdge Control Plane, its cluster, and the
    // state of each host, using reqwest and serde_json.
    //
    // These examples are for the Control Plane v0.11.0.
    //
    // Copyright (c) 2026, pgEdge, Inc.
    // This code is released under the PostgreSQL License.
    
    use std::env;
    use std::error::Error;
    use std::process::ExitCode;
    use std::time::Duration;
    
    use reqwest::blocking::Client;
    use serde_json::Value;
    
    /// Returns the value of an environment variable, or a fallback if the
    /// variable is unset or empty.
    fn env_or(name: &str, fallback: &str) -> String {
        env::var(name)
            .ok()
            .filter(|value| !value.is_empty())
            .unwrap_or_else(|| fallback.to_string())
    }
    
    fn base_url() -> String {
        env_or("CONTROL_PLANE_URL", "http://localhost:3000")
            .trim_end_matches('/')
            .to_string()
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
    
    /// Prints the version of the Control Plane server.
    fn show_version(client: &Client) -> Result<(), BoxError> {
        let reply = get(client, "/v1/version")?;
        let Some(version) = reply["version"].as_str() else {
            return Err("Unexpected response: missing version".into());
        };
        println!("Version: {version}");
        Ok(())
    }
    
    /// Prints the state of the cluster. A server answers this request only
    /// once its cluster has been initialised, and it then reports
    /// "available"; the health of the cluster shows in the state of each host.
    fn show_cluster(client: &Client) -> Result<(), BoxError> {
        let reply = get(client, "/v1/cluster")?;
        let Some(state) = reply["status"]["state"].as_str() else {
            return Err("Unexpected response: missing state".into());
        };
        println!("Cluster: {state}");
        Ok(())
    }
    
    /// Lists the hosts in the cluster with their states, and returns whether
    /// every host is "healthy". The other states are "degraded",
    /// "unreachable" and "unknown".
    fn show_hosts(client: &Client) -> Result<bool, BoxError> {
        let reply = get(client, "/v1/hosts")?;
        let Some(hosts) = reply["hosts"].as_array() else {
            return Err("Unexpected response: missing hosts".into());
        };
    
        println!("Hosts ({}):", hosts.len());
        let mut healthy = true;
        for host in hosts {
            let state = host["status"]["state"].as_str().unwrap_or("unknown");
            println!("- {}: {state}", host["id"].as_str().unwrap_or(""));
            healthy = healthy && state == "healthy";
        }
        Ok(healthy)
    }
    
    /// Runs the three checks, and returns whether every host is healthy. The
    /// ? operator returns any error to the caller.
    fn run() -> Result<bool, BoxError> {
        let client = Client::builder().timeout(TIMEOUT).build()?;
        show_version(&client)?;
        show_cluster(&client)?;
        show_hosts(&client)
    }
    
    /// Reports any error returned by run() and exits with a failure status.
    /// The top-level error is often generic ("error sending request"), so the
    /// chain of underlying causes is printed too.
    fn main() -> ExitCode {
        match run() {
            Ok(true) => ExitCode::SUCCESS,
            // Report an unhealthy host with the exit status.
            Ok(false) => {
                eprintln!("A host is not healthy");
                ExitCode::FAILURE
            }
            Err(e) => {
                eprintln!("Control Plane error: {e}");
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
    # Checking the version of the pgEdge Control Plane, its cluster, and the
    # state of each host, using Net::HTTP.
    #
    # These examples are for the Control Plane v0.11.0.
    #
    # Copyright (c) 2026, pgEdge, Inc.
    # This code is released under the PostgreSQL License.
    
    require "json"
    require "net/http"
    require "uri"
    
    # Returns the value of an environment variable, or a fallback if the
    # variable is unset or empty.
    def env_or(name, fallback)
      value = ENV[name]
      value.nil? || value.empty? ? fallback : value
    end
    
    BASE_URL = env_or("CONTROL_PLANE_URL", "http://localhost:3000").sub(%r{/+\z}, "")
    
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
    
    # Prints the version of the Control Plane server.
    def show_version(http)
      version = get(http, "/v1/version")["version"]
      raise ControlPlaneError, "Unexpected response: missing version" unless version.is_a?(String)
    
      puts "Version: #{version}"
    end
    
    # Prints the state of the cluster. A server answers this request only once
    # its cluster has been initialised, and it then reports "available"; the
    # health of the cluster shows in the state of each host.
    def show_cluster(http)
      state = (get(http, "/v1/cluster")["status"] || {})["state"]
      raise ControlPlaneError, "Unexpected response: missing state" unless state.is_a?(String)
    
      puts "Cluster: #{state}"
    end
    
    # Lists the hosts in the cluster with their states, and returns whether
    # every host is "healthy". The other states are "degraded", "unreachable"
    # and "unknown".
    def show_hosts(http)
      hosts = get(http, "/v1/hosts")["hosts"]
      raise ControlPlaneError, "Unexpected response: missing hosts" unless hosts.is_a?(Array)
    
      puts "Hosts (#{hosts.length}):"
      hosts.map do |host|
        state = (host["status"] || {}).fetch("state", "unknown")
        puts "- #{host["id"]}: #{state}"
        state == "healthy"
      end.all?
    end
    
    begin
      uri = URI(BASE_URL)
      # start opens a connection, and closes it when the block exits, whether
      # or not an error occurred.
      healthy = Net::HTTP.start(
        uri.host, uri.port,
        use_ssl: uri.scheme == "https",
        open_timeout: TIMEOUT_SECONDS, read_timeout: TIMEOUT_SECONDS
      ) do |http|
        show_version(http)
        show_cluster(http)
        show_hosts(http)
      end
    # SystemCallError covers a refused connection, Timeout::Error covers the
    # connection and read timeouts, and SocketError covers an unknown host.
    rescue ControlPlaneError, SystemCallError, Timeout::Error, SocketError, IOError => e
      warn "Control Plane error: #{e.message}"
      exit 1
    end
    
    # Report an unhealthy host with the exit status.
    unless healthy
      warn "A host is not healthy"
      exit 1
    end
    
    ```

=== "curl"

    ```bash
    #!/usr/bin/env bash
    #
    # Ellie's Postgres Cookbook
    # Checking the version of the pgEdge Control Plane, its cluster, and the
    # state of each host, using curl and jq.
    #
    # These examples are for the Control Plane v0.11.0.
    #
    # Copyright (c) 2026, pgEdge, Inc.
    # This code is released under the PostgreSQL License.
    
    # Stop at the first failed command or unset variable, and treat a failure
    # anywhere in a pipeline as a failure of the whole pipeline.
    set -euo pipefail
    
    for tool in curl jq; do
        command -v "$tool" >/dev/null || { echo "Control Plane error: $tool is required" >&2; exit 1; }
    done
    
    # The :- operator treats an empty variable as unset.
    CONTROL_PLANE_URL="${CONTROL_PLANE_URL:-http://localhost:3000}"
    CONTROL_PLANE_URL="${CONTROL_PLANE_URL%/}"
    
    TIMEOUT_SECONDS=30
    
    # Fetches a path from the server and prints the JSON reply. With
    # --fail-with-body, curl exits non-zero on an HTTP error status but still
    # prints the body, which carries the server's explanation.
    get() {
        curl --silent --show-error --fail-with-body \
            --max-time "$TIMEOUT_SECONDS" "$CONTROL_PLANE_URL$1"
    }
    
    # Prints the version of the Control Plane server.
    show_version() {
        local response
        response="$(get /v1/version)" || {
            echo "Control Plane error: $response" >&2
            return 1
        }
        jq -er '"Version: \(.version | strings)"' <<<"$response" || {
            echo "Unexpected response: $response" >&2
            return 1
        }
    }
    
    # Prints the state of the cluster. A server answers this request only once
    # its cluster has been initialised, and it then reports "available"; the
    # health of the cluster shows in the state of each host.
    show_cluster() {
        local response
        response="$(get /v1/cluster)" || {
            echo "Control Plane error: $response" >&2
            return 1
        }
        jq -er '"Cluster: \(.status.state | strings)"' <<<"$response" || {
            echo "Unexpected response: $response" >&2
            return 1
        }
    }
    
    # Lists the hosts in the cluster with their states, and fails when a
    # request or reply fails or when a host is anything but "healthy". The
    # other states are "degraded", "unreachable" and "unknown".
    show_hosts() {
        local response
        response="$(get /v1/hosts)" || {
            echo "Control Plane error: $response" >&2
            return 1
        }
        jq -er '
            if (.hosts | type) != "array" then error("missing hosts") else
                "Hosts (\(.hosts | length)):",
                (.hosts[] | "- \(.id): \(.status.state // "unknown")")
            end' <<<"$response" || {
            echo "Unexpected response: $response" >&2
            return 1
        }
        jq -e 'all(.hosts[]; .status.state == "healthy")' <<<"$response" >/dev/null || {
            echo "A host is not healthy" >&2
            return 1
        }
    }
    
    main() {
        # Any failure, including an unhealthy host, gives a non-zero exit
        # status.
        show_version || exit 1
        show_cluster || exit 1
        show_hosts || exit 1
    }
    
    main
    
    ```

## Next Steps

The following resources provide more information about the topics in this
recipe:

- The [Creating a Database](create_database.md) recipe shows how to create a
  database on one of the hosts that this recipe lists.
- The [Connecting to a Database](connect_database.md) recipe shows how to find
  the address of a database and connect to it.
- The
  [pgEdge Control Plane documentation](https://docs.pgedge.com/control-plane/v0-11/)
  describes every endpoint and setting.
- The [Contributing a Recipe](../contributing.md) page explains how to add a
  recipe or a language to the cookbook.
