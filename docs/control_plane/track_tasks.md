# Following a Task

This recipe finds the task that a pgEdge Control Plane server ran to create a
database, prints the entries of its log as they appear, and then reports how
the task finished. The Control Plane runs every create, update and delete of a
database as a task in the background, so following the task is how a program
learns what the server is doing, and why a change failed. Each step shows the
code in every supported language; selecting a language tab switches every tab
on the site to that language.

These examples are for the Control Plane v0.11.0.

The program prints output like the following; the log has more entries than
are shown here, and the names and timings in them vary from run to run:

```text
Task: create
Log: refreshing current state
Log: finished refreshing current state (took 205.344792ms)
Log: creating resource common.patroni_cluster::n1
Log: finished creating resource common.patroni_cluster::n1 (took 16.625µs)
Log: creating resource database.postgres_database::n1:cookbook
Log: finished creating resource database.postgres_database::n1:cookbook (took 283.094583ms)
Status: completed
```

## Preparing the Ingredients

The examples assume a running Control Plane server with a database. The
`scripts/start_control_plane.sh` script in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook)
starts a server in Docker and creates a database with the ID `cookbook`, whose
creation task the program follows.

The program calls three endpoints, and each takes a `GET` request. The
following table describes them:

| Endpoint                                 | Description                            |
|------------------------------------------|----------------------------------------|
| `/v1/databases/{id}/tasks`               | Lists the tasks of a database.         |
| `/v1/databases/{id}/tasks/{task_id}`     | Returns a task, with its status.       |
| `/v1/databases/{id}/tasks/{task_id}/log` | Returns the entries of the task's log. |

A task has a `type`, such as `create`, and a `status`, which is `pending`,
`running`, `completed`, `failed`, `canceling`, `canceled` or `unknown`. The
reply from the log endpoint holds the `entries`, each with a `timestamp` and a
`message`, and the `last_entry_id`; passing that ID back in the
`after_entry_id` query parameter returns only the entries that came after it.

The following tabs show the dependency declaration from each example project:

=== "Python"

    ```text
    # httpx, an HTTP client with a requests-like API.
    httpx>=0.28,<1
    ```

=== "TypeScript"

    ```json
    {
      "name": "track-tasks",
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
    import time
    
    import httpx
    ```

=== "TypeScript"

    ```typescript
    // Node.js provides fetch and AbortSignal as globals; setTimeout from
    // timers/promises returns a promise, which suits a polling loop.
    import { setTimeout as sleep } from "node:timers/promises";
    ```

=== "Java"

    ```java
    import java.io.IOException;
    import java.net.URI;
    import java.net.URLEncoder;
    import java.net.http.HttpClient;
    import java.net.http.HttpRequest;
    import java.net.http.HttpResponse;
    import java.net.http.HttpTimeoutException;
    import java.nio.charset.StandardCharsets;
    import java.time.Duration;
    import java.util.Set;
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
    using System.Diagnostics;
    using System.Text.Json;
    using System.Text.Json.Nodes;
    ```

=== "Go"

    ```go
    import (
    	"encoding/json"
    	"fmt"
    	"io"
    	"net/http"
    	"net/url"
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
    use std::thread;
    use std::time::{Duration, Instant};
    
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

The examples read their settings from environment variables, and treat an
empty value as unset. Each request may take up to 30 seconds, and the program
follows a running task for up to 600 seconds, checking every five seconds. The
following table describes the environment variables:

| Variable                    | Default                 | Description                        |
|-----------------------------|-------------------------|------------------------------------|
| `CONTROL_PLANE_URL`         | `http://localhost:3000` | The base URL of the Control Plane. |
| `CONTROL_PLANE_DATABASE_ID` | `cookbook`              | The ID of the database.            |

The following tabs show how each program reads its settings, and how it fetches
a path from the server:

=== "Python"

    ```python
    # The or operator treats an empty variable as unset.
    BASE_URL = (os.environ.get("CONTROL_PLANE_URL") or "http://localhost:3000").rstrip("/")
    DATABASE_ID = os.environ.get("CONTROL_PLANE_DATABASE_ID") or "cookbook"
    
    TIMEOUT_SECONDS = 30.0
    
    # How long to follow a task that is still running, and how often to check.
    FOLLOW_SECONDS = 600
    POLL_SECONDS = 5
    
    # The statuses after which a task does not change again.
    FINAL_STATUSES = {"completed", "failed", "canceled"}
    
    
    class ControlPlaneError(Exception):
        """Raised when the Control Plane rejects a request or replies oddly."""
    
    
    def get(client: httpx.Client, path: str, params: dict | None = None) -> dict:
        """Fetches a path from the server, and returns the decoded reply."""
        response = client.get(path, params=params)
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
    const databaseId = process.env.CONTROL_PLANE_DATABASE_ID || "cookbook";
    
    const timeoutMs = 30_000;
    
    // How long to follow a task that is still running, and how often to check.
    const followMs = 600_000;
    const pollMs = 5_000;
    
    // The statuses after which a task does not change again.
    const finalStatuses = new Set(["completed", "failed", "canceled"]);
    
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
    static final String DATABASE_ID = envOr("CONTROL_PLANE_DATABASE_ID", "cookbook");
    
    static final Duration TIMEOUT = Duration.ofSeconds(30);
    
    // How long to follow a task that is still running, and how often to
    // check.
    static final Duration FOLLOW_FOR = Duration.ofSeconds(600);
    static final Duration POLL_INTERVAL = Duration.ofSeconds(5);
    
    // The statuses after which a task does not change again.
    static final Set<String> FINAL_STATUSES = Set.of("completed", "failed", "canceled");
    
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
    
    static string DatabaseId() => EnvOr("CONTROL_PLANE_DATABASE_ID", "cookbook");
    
    const int TimeoutSeconds = 30;
    
    // How long to follow a task that is still running, and how often to check.
    const int FollowSeconds = 600;
    const int PollSeconds = 5;
    
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
    
    var (
    	baseURL    = strings.TrimRight(envOr("CONTROL_PLANE_URL", "http://localhost:3000"), "/")
    	databaseID = envOr("CONTROL_PLANE_DATABASE_ID", "cookbook")
    )
    
    const timeout = 30 * time.Second
    
    // How long to follow a task that is still running, and how often to check.
    const (
    	followFor    = 600 * time.Second
    	pollInterval = 5 * time.Second
    )
    
    // finalStatuses holds the statuses after which a task does not change
    // again.
    var finalStatuses = map[string]bool{"completed": true, "failed": true, "canceled": true}
    
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
    
    fn database_id() -> String {
        env_or("CONTROL_PLANE_DATABASE_ID", "cookbook")
    }
    
    const TIMEOUT: Duration = Duration::from_secs(30);
    
    // How long to follow a task that is still running, and how often to check.
    const FOLLOW_FOR: Duration = Duration::from_secs(600);
    const POLL_INTERVAL: Duration = Duration::from_secs(5);
    
    /// The statuses after which a task does not change again.
    const FINAL_STATUSES: [&str; 3] = ["completed", "failed", "canceled"];
    
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
    DATABASE_ID = env_or("CONTROL_PLANE_DATABASE_ID", "cookbook")
    
    TIMEOUT_SECONDS = 30
    
    # How long to follow a task that is still running, and how often to check.
    FOLLOW_SECONDS = 600
    POLL_SECONDS = 5
    
    # The statuses after which a task does not change again.
    FINAL_STATUSES = %w[completed failed canceled].freeze
    
    # Raised when the Control Plane rejects a request or replies oddly.
    class ControlPlaneError < StandardError; end
    
    # Fetches a path from the server, and returns the decoded reply. The query
    # hash is encoded and added to the URL.
    def get(http, path, query = {})
      uri = URI("#{BASE_URL}#{path}")
      uri.query = URI.encode_www_form(query) unless query.empty?
      response = http.request(Net::HTTP::Get.new(uri))
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
    DATABASE_ID="${CONTROL_PLANE_DATABASE_ID:-cookbook}"
    
    TIMEOUT_SECONDS=30
    
    # How long to follow a task that is still running, and how often to check.
    FOLLOW_SECONDS=600
    POLL_SECONDS=5
    
    # Fetches a path from the server and prints the JSON reply. With
    # --fail-with-body, curl exits non-zero on an HTTP error status but still
    # prints the body, which carries the server's explanation.
    get() {
        curl --silent --show-error --fail-with-body \
            --max-time "$TIMEOUT_SECONDS" "$CONTROL_PLANE_URL$1"
    }
    ```

## Finding the Task

Each program lists the tasks of the database, oldest first, by passing
`sort_order=asc`, and picks the first task whose type is `create`. The
following tabs show how each program finds the task:

=== "Python"

    ```python
    def find_create_task(client: httpx.Client) -> str:
        """Returns the ID of the task that created the database. Every create,
        update and delete runs as a task. The IDs sort by creation time, and
        sort_order=asc lists the oldest task first."""
        reply = get(client, f"/v1/databases/{DATABASE_ID}/tasks",
                    {"sort_order": "asc"})
        for task in reply.get("tasks") or []:
            if task.get("type") == "create":
                return task["task_id"]
        raise ControlPlaneError(f"no create task for {DATABASE_ID}")
    ```

=== "TypeScript"

    ```typescript
    interface Task {
      task_id?: string;
      type?: string;
      status?: string;
    }
    
    // Returns the ID of the task that created the database. Every create,
    // update and delete runs as a task. The IDs sort by creation time, and
    // sort_order=asc lists the oldest task first.
    async function findCreateTask(): Promise<string> {
      const reply = await get<{ tasks?: Task[] }>(
        `/v1/databases/${databaseId}/tasks?sort_order=asc`,
      );
      const task = (reply.tasks ?? []).find((t) => t.type === "create");
      if (!task?.task_id) {
        throw new Error(`no create task for ${databaseId}`);
      }
      return task.task_id;
    }
    ```

=== "Java"

    ```java
    /**
     * Returns the ID of the task that created the database. Every create,
     * update and delete runs as a task. The IDs sort by creation time, and
     * sort_order=asc lists the oldest task first.
     */
    static String findCreateTask(HttpClient client)
            throws IOException, InterruptedException, ControlPlaneException {
        JsonNode reply = get(client,
                "/v1/databases/" + DATABASE_ID + "/tasks?sort_order=asc");
        for (JsonNode task : reply.path("tasks")) {
            if (task.path("type").asString("").equals("create")) {
                return task.path("task_id").asString();
            }
        }
        throw new ControlPlaneException("no create task for " + DATABASE_ID);
    }
    ```

=== "C#"

    ```csharp
    // Returns the ID of the task that created the database. Every create,
    // update and delete runs as a task. The IDs sort by creation time, and
    // sort_order=asc lists the oldest task first.
    static async Task<string> FindCreateTaskAsync(HttpClient client)
    {
        var reply = await GetAsync(
            client, $"/v1/databases/{DatabaseId()}/tasks?sort_order=asc");
        foreach (var task in reply["tasks"] as JsonArray ?? [])
        {
            if (task?["type"]?.ToString() == "create" &&
                task["task_id"]?.ToString() is { } taskId)
            {
                return taskId;
            }
        }
        throw new ControlPlaneException($"no create task for {DatabaseId()}");
    }
    ```

=== "Go"

    ```go
    // task holds the fields of a task that this program uses.
    type task struct {
    	TaskID string `json:"task_id"`
    	Type   string `json:"type"`
    	Status string `json:"status"`
    }
    
    // findCreateTask returns the ID of the task that created the database.
    // Every create, update and delete runs as a task. The IDs sort by
    // creation time, and sort_order=asc lists the oldest task first.
    func findCreateTask(client *http.Client) (string, error) {
    	var reply struct {
    		Tasks []task `json:"tasks"`
    	}
    	err := get(client, "/v1/databases/"+databaseID+"/tasks?sort_order=asc", &reply)
    	if err != nil {
    		return "", err
    	}
    	for _, t := range reply.Tasks {
    		if t.Type == "create" {
    			return t.TaskID, nil
    		}
    	}
    	return "", fmt.Errorf("no create task for %s", databaseID)
    }
    
    ```

=== "Rust"

    ```rust
    /// Returns the ID of the task that created the database. Every create,
    /// update and delete runs as a task. The IDs sort by creation time, and
    /// sort_order=asc lists the oldest task first.
    fn find_create_task(client: &Client) -> Result<String, BoxError> {
        let path = format!("/v1/databases/{}/tasks?sort_order=asc", database_id());
        let reply = get(client, &path)?;
        let tasks = reply["tasks"].as_array().cloned().unwrap_or_default();
        tasks
            .iter()
            .find(|task| task["type"] == "create")
            .and_then(|task| task["task_id"].as_str())
            .map(str::to_string)
            .ok_or_else(|| format!("no create task for {}", database_id()).into())
    }
    ```

=== "Ruby"

    ```ruby
    # Returns the ID of the task that created the database. Every create,
    # update and delete runs as a task. The IDs sort by creation time, and
    # sort_order=asc lists the oldest task first.
    def find_create_task(http)
      reply = get(http, "/v1/databases/#{DATABASE_ID}/tasks", { "sort_order" => "asc" })
      task = (reply["tasks"] || []).find { |t| t["type"] == "create" }
      raise ControlPlaneError, "no create task for #{DATABASE_ID}" unless task
    
      task["task_id"]
    end
    ```

=== "curl"

    ```bash
    # Prints the ID of the task that created the database. Every create,
    # update and delete runs as a task. The IDs sort by creation time, and
    # sort_order=asc lists the oldest task first.
    find_create_task() {
        local response
        response="$(get "/v1/databases/$DATABASE_ID/tasks?sort_order=asc")" || {
            echo "Control Plane error: $response" >&2
            return 1
        }
        jq -er 'first(.tasks[] | select(.type == "create")) | .task_id' \
            <<<"$response" || {
            echo "Control Plane error: no create task for $DATABASE_ID" >&2
            return 1
        }
    }
    ```

## Following the Log

Each program reads the status of the task and then the log entries that it
has not yet printed, and repeats both every five seconds until the status is
`completed`, `failed` or `canceled`. Reading the status before the log means
that, once the status is final, the log read after it is complete. The
following tabs show how each program follows the task:

=== "Python"

    ```python
    def follow_task(client: httpx.Client, task_id: str) -> str:
        """Prints the log of a task as it grows, until the task finishes, and
        returns its final status. Each log reply carries last_entry_id, and
        passing that back as after_entry_id fetches only the newer entries.
        The status is read before the log, so that once it is final, the log
        that follows it is complete."""
        path = f"/v1/databases/{DATABASE_ID}/tasks/{task_id}"
        deadline = time.monotonic() + FOLLOW_SECONDS
        after = None
        while True:
            status = get(client, path).get("status")
    
            log = get(client, f"{path}/log",
                      {"after_entry_id": after} if after else None)
            for entry in log.get("entries") or []:
                print(f"Log: {entry.get('message')}")
            after = log.get("last_entry_id") or after
    
            if status in FINAL_STATUSES:
                return status
            if time.monotonic() >= deadline:
                raise ControlPlaneError(
                    f"task {task_id} was still {status} after {FOLLOW_SECONDS} seconds")
            time.sleep(POLL_SECONDS)
    ```

=== "TypeScript"

    ```typescript
    interface TaskLog {
      last_entry_id?: string;
      entries?: { message?: string }[];
    }
    
    // Prints the log of a task as it grows, until the task finishes, and
    // returns its final status. Each log reply carries last_entry_id, and
    // passing that back as after_entry_id fetches only the newer entries. The
    // status is read before the log, so that once it is final, the log that
    // follows it is complete.
    async function followTask(taskId: string): Promise<string> {
      const path = `/v1/databases/${databaseId}/tasks/${taskId}`;
      const deadline = Date.now() + followMs;
      let after: string | undefined;
      for (;;) {
        const { status = "unknown" } = await get<Task>(path);
    
        const query = after ? `?after_entry_id=${encodeURIComponent(after)}` : "";
        const log = await get<TaskLog>(`${path}/log${query}`);
        for (const entry of log.entries ?? []) {
          console.log(`Log: ${entry.message}`);
        }
        after = log.last_entry_id || after;
    
        if (finalStatuses.has(status)) {
          return status;
        }
        if (Date.now() >= deadline) {
          throw new Error(`task ${taskId} was still ${status} after ${followMs / 1000} seconds`);
        }
        await sleep(pollMs);
      }
    }
    ```

=== "Java"

    ```java
    /**
     * Prints the log of a task as it grows, until the task finishes, and
     * returns its final status. Each log reply carries last_entry_id, and
     * passing that back as after_entry_id fetches only the newer entries.
     * The status is read before the log, so that once it is final, the log
     * that follows it is complete.
     */
    static String followTask(HttpClient client, String taskId)
            throws IOException, InterruptedException, ControlPlaneException {
        String path = "/v1/databases/" + DATABASE_ID + "/tasks/" + taskId;
        long deadline = System.nanoTime() + FOLLOW_FOR.toNanos();
        String after = "";
        while (true) {
            String status = get(client, path).path("status").asString("unknown");
    
            String query = after.isEmpty() ? ""
                    : "?after_entry_id=" + URLEncoder.encode(after, StandardCharsets.UTF_8);
            JsonNode log = get(client, path + "/log" + query);
            for (JsonNode entry : log.path("entries")) {
                System.out.println("Log: " + entry.path("message").asString(""));
            }
            String last = log.path("last_entry_id").asString("");
            if (!last.isEmpty()) {
                after = last;
            }
    
            if (FINAL_STATUSES.contains(status)) {
                return status;
            }
            if (System.nanoTime() >= deadline) {
                throw new ControlPlaneException("task " + taskId + " was still "
                        + status + " after " + FOLLOW_FOR.toSeconds() + " seconds");
            }
            Thread.sleep(POLL_INTERVAL.toMillis());
        }
    }
    ```

=== "C#"

    ```csharp
    // Prints the log of a task as it grows, until the task finishes, and
    // returns its final status. Each log reply carries last_entry_id, and
    // passing that back as after_entry_id fetches only the newer entries. The
    // status is read before the log, so that once it is final, the log that
    // follows it is complete.
    static async Task<string> FollowTaskAsync(HttpClient client, string taskId)
    {
        string[] finalStatuses = ["completed", "failed", "canceled"];
        var path = $"/v1/databases/{DatabaseId()}/tasks/{taskId}";
        var clock = Stopwatch.StartNew();
        var after = "";
        while (true)
        {
            var task = await GetAsync(client, path);
            var status = task["status"]?.ToString() ?? "unknown";
    
            var query = after == "" ? "" : $"?after_entry_id={Uri.EscapeDataString(after)}";
            var log = await GetAsync(client, $"{path}/log{query}");
            foreach (var entry in log["entries"] as JsonArray ?? [])
            {
                Console.WriteLine($"Log: {entry?["message"]}");
            }
            if (log["last_entry_id"]?.ToString() is { Length: > 0 } last)
            {
                after = last;
            }
    
            if (finalStatuses.Contains(status))
            {
                return status;
            }
            if (clock.Elapsed.TotalSeconds >= FollowSeconds)
            {
                throw new ControlPlaneException(
                    $"task {taskId} was still {status} after {FollowSeconds} seconds");
            }
            await Task.Delay(TimeSpan.FromSeconds(PollSeconds));
        }
    }
    ```

=== "Go"

    ```go
    // followTask prints the log of a task as it grows, until the task
    // finishes, and returns its final status. Each log reply carries
    // last_entry_id, and passing that back as after_entry_id fetches only the
    // newer entries. The status is read before the log, so that once it is
    // final, the log that follows it is complete.
    func followTask(client *http.Client, taskID string) (string, error) {
    	path := "/v1/databases/" + databaseID + "/tasks/" + taskID
    	deadline := time.Now().Add(followFor)
    	after := ""
    	for {
    		var t task
    		if err := get(client, path, &t); err != nil {
    			return "", err
    		}
    
    		var log struct {
    			LastEntryID string `json:"last_entry_id"`
    			Entries     []struct {
    				Message string `json:"message"`
    			} `json:"entries"`
    		}
    		query := ""
    		if after != "" {
    			query = "?after_entry_id=" + url.QueryEscape(after)
    		}
    		if err := get(client, path+"/log"+query, &log); err != nil {
    			return "", err
    		}
    		for _, entry := range log.Entries {
    			fmt.Printf("Log: %s\n", entry.Message)
    		}
    		if log.LastEntryID != "" {
    			after = log.LastEntryID
    		}
    
    		if finalStatuses[t.Status] {
    			return t.Status, nil
    		}
    		if time.Now().After(deadline) {
    			return "", fmt.Errorf("task %s was still %s after %v", taskID, t.Status, followFor)
    		}
    		time.Sleep(pollInterval)
    	}
    }
    
    ```

=== "Rust"

    ```rust
    /// Prints the log of a task as it grows, until the task finishes, and
    /// returns its final status. Each log reply carries last_entry_id, and
    /// passing that back as after_entry_id fetches only the newer entries.
    /// The status is read before the log, so that once it is final, the log
    /// that follows it is complete.
    fn follow_task(client: &Client, task_id: &str) -> Result<String, BoxError> {
        let path = format!("/v1/databases/{}/tasks/{task_id}", database_id());
        let deadline = Instant::now() + FOLLOW_FOR;
        let mut after = String::new();
        loop {
            let task = get(client, &path)?;
            let status = task["status"].as_str().unwrap_or("unknown").to_string();
    
            // Entry IDs are UUIDs, so they need no escaping in a URL.
            let query = if after.is_empty() {
                String::new()
            } else {
                format!("?after_entry_id={after}")
            };
            let log = get(client, &format!("{path}/log{query}"))?;
            for entry in log["entries"].as_array().into_iter().flatten() {
                println!("Log: {}", entry["message"].as_str().unwrap_or(""));
            }
            if let Some(last) = log["last_entry_id"].as_str().filter(|s| !s.is_empty()) {
                after = last.to_string();
            }
    
            if FINAL_STATUSES.contains(&status.as_str()) {
                return Ok(status);
            }
            if Instant::now() >= deadline {
                return Err(format!(
                    "task {task_id} was still {status} after {} seconds",
                    FOLLOW_FOR.as_secs()
                )
                .into());
            }
            thread::sleep(POLL_INTERVAL);
        }
    }
    ```

=== "Ruby"

    ```ruby
    # Prints the log of a task as it grows, until the task finishes, and
    # returns its final status. Each log reply carries last_entry_id, and
    # passing that back as after_entry_id fetches only the newer entries. The
    # status is read before the log, so that once it is final, the log that
    # follows it is complete.
    def follow_task(http, task_id)
      path = "/v1/databases/#{DATABASE_ID}/tasks/#{task_id}"
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + FOLLOW_SECONDS
      after = nil
      loop do
        status = get(http, path)["status"] || "unknown"
    
        log = get(http, "#{path}/log", after ? { "after_entry_id" => after } : {})
        (log["entries"] || []).each { |entry| puts "Log: #{entry["message"]}" }
        after = log["last_entry_id"] unless log["last_entry_id"].to_s.empty?
    
        return status if FINAL_STATUSES.include?(status)
        if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
          raise ControlPlaneError, "task #{task_id} was still #{status} after #{FOLLOW_SECONDS} seconds"
        end
    
        sleep POLL_SECONDS
      end
    end
    ```

=== "curl"

    ```bash
    # Prints the log of a task as it grows, until the task finishes, and then
    # prints its final status. Each log reply carries last_entry_id, and
    # passing that back as after_entry_id fetches only the newer entries. The
    # status is read before the log, so that once it is final, the log that
    # follows it is complete.
    follow_task() {
        local task_id="$1" path="/v1/databases/$DATABASE_ID/tasks/$1"
        local deadline=$((SECONDS + FOLLOW_SECONDS)) after="" task status log
    
        while true; do
            task="$(get "$path")" || {
                echo "Control Plane error: $task" >&2
                return 1
            }
            status="$(jq -er '.status' <<<"$task")"
    
            log="$(get "$path/log${after:+?after_entry_id=$after}")" || {
                echo "Control Plane error: $log" >&2
                return 1
            }
            jq -r '.entries[] | "Log: \(.message)"' <<<"$log"
            after="$(jq -r '.last_entry_id // empty' <<<"$log")"
    
            case "$status" in
                completed|failed|canceled) break ;;
            esac
            if ((SECONDS >= deadline)); then
                echo "Control Plane error: task $task_id was still $status after $FOLLOW_SECONDS seconds" >&2
                return 1
            fi
            sleep "$POLL_SECONDS"
        done
    
        echo "Status: $status"
        [[ "$status" == "completed" ]]
    }
    ```

## Handling Errors

The main part of each program finds the task and follows it, reports any
failure on `stderr`, and exits with a non-zero status when the server is
unreachable or the task did not complete. The following tabs show the main part
of each program:

=== "Python"

    ```python
    def main() -> int:
        try:
            with httpx.Client(base_url=BASE_URL, timeout=TIMEOUT_SECONDS) as client:
                task_id = find_create_task(client)
                print("Task: create")
                status = follow_task(client, task_id)
        # httpx.HTTPError is the base class for failures to reach the server,
        # such as a refused connection or a timeout.
        except (httpx.HTTPError, ControlPlaneError) as e:
            print(f"Control Plane error: {e}", file=sys.stderr)
            return 1
    
        print(f"Status: {status}")
        return 0 if status == "completed" else 1
    
    
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
        const taskId = await findCreateTask();
        console.log("Task: create");
        const status = await followTask(taskId);
        console.log(`Status: ${status}`);
        return status === "completed" ? 0 : 1;
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
        String status;
        try {
            HttpClient client = HttpClient.newHttpClient();
            String taskId = findCreateTask(client);
            System.out.println("Task: create");
            status = followTask(client, taskId);
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
    
        System.out.println("Status: " + status);
        if (!status.equals("completed")) {
            System.exit(1);
        }
    }
    ```

=== "C#"

    ```csharp
    string status;
    try
    {
        // using disposes of the client, and closes its connections, when the
        // block exits, whether or not an error occurred.
        using var client = new HttpClient
        {
            Timeout = TimeSpan.FromSeconds(TimeoutSeconds),
        };
        var taskId = await FindCreateTaskAsync(client);
        Console.WriteLine("Task: create");
        status = await FollowTaskAsync(client, taskId);
    }
    // HttpRequestException covers failures to reach the server, such as a
    // refused connection, and TaskCanceledException covers a timeout.
    catch (Exception e) when (
        e is HttpRequestException or TaskCanceledException or ControlPlaneException)
    {
        Console.Error.WriteLine($"Control Plane error: {e.Message}");
        return 1;
    }
    
    Console.WriteLine($"Status: {status}");
    return status == "completed" ? 0 : 1;
    
    // C# requires type declarations to follow the top-level statements, so
    // the exception that the program throws for an error reply is declared
    // here, at the end.
    class ControlPlaneException(string message) : Exception(message);
    ```

=== "Go"

    ```go
    // run finds the task and follows it, and returns any error to the
    // caller.
    func run() error {
    	client := &http.Client{Timeout: timeout}
    
    	taskID, err := findCreateTask(client)
    	if err != nil {
    		return err
    	}
    	fmt.Println("Task: create")
    	status, err := followTask(client, taskID)
    	if err != nil {
    		return err
    	}
    	fmt.Printf("Status: %s\n", status)
    	if status != "completed" {
    		return fmt.Errorf("the task finished with the status %s", status)
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
    /// Finds the task and follows it, and returns its final status. The ?
    /// operator returns any error to the caller.
    fn run() -> Result<String, BoxError> {
        let client = Client::builder().timeout(TIMEOUT).build()?;
        let task_id = find_create_task(&client)?;
        println!("Task: create");
        follow_task(&client, &task_id)
    }
    
    /// Reports any error returned by run() and exits with a failure status.
    /// The top-level error is often generic ("error sending request"), so the
    /// chain of underlying causes is printed too.
    fn main() -> ExitCode {
        match run() {
            Ok(status) => {
                println!("Status: {status}");
                if status == "completed" {
                    ExitCode::SUCCESS
                } else {
                    ExitCode::FAILURE
                }
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
      status = Net::HTTP.start(
        uri.host, uri.port,
        use_ssl: uri.scheme == "https",
        open_timeout: TIMEOUT_SECONDS, read_timeout: TIMEOUT_SECONDS
      ) do |http|
        task_id = find_create_task(http)
        puts "Task: create"
        follow_task(http, task_id)
      end
    # SystemCallError covers a refused connection, Timeout::Error covers the
    # connection and read timeouts, and SocketError covers an unknown host.
    rescue ControlPlaneError, SystemCallError, Timeout::Error, SocketError, IOError => e
      warn "Control Plane error: #{e.message}"
      exit 1
    end
    
    puts "Status: #{status}"
    exit 1 unless status == "completed"
    ```

=== "curl"

    ```bash
    main() {
        local task_id
        task_id="$(find_create_task)" || exit 1
        echo "Task: create"
        follow_task "$task_id" || exit 1
    }
    
    main
    ```

## Running the Example

The complete project for each language is available in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/control_plane/track_tasks).
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
    Finding the task that created a pgEdge Control Plane database, and
    following its log until the task finishes, using httpx.
    
    These examples are for the Control Plane v0.11.0.
    
    Copyright (c) 2026, pgEdge, Inc.
    This code is released under the PostgreSQL License.
    """
    
    import os
    import sys
    import time
    
    import httpx
    
    
    # The or operator treats an empty variable as unset.
    BASE_URL = (os.environ.get("CONTROL_PLANE_URL") or "http://localhost:3000").rstrip("/")
    DATABASE_ID = os.environ.get("CONTROL_PLANE_DATABASE_ID") or "cookbook"
    
    TIMEOUT_SECONDS = 30.0
    
    # How long to follow a task that is still running, and how often to check.
    FOLLOW_SECONDS = 600
    POLL_SECONDS = 5
    
    # The statuses after which a task does not change again.
    FINAL_STATUSES = {"completed", "failed", "canceled"}
    
    
    class ControlPlaneError(Exception):
        """Raised when the Control Plane rejects a request or replies oddly."""
    
    
    def get(client: httpx.Client, path: str, params: dict | None = None) -> dict:
        """Fetches a path from the server, and returns the decoded reply."""
        response = client.get(path, params=params)
        if response.is_error:
            raise ControlPlaneError(f"HTTP {response.status_code}, {response.text[:200]}")
        try:
            body = response.json()
            if isinstance(body, dict):
                return body
        except ValueError:
            pass
        raise ControlPlaneError(f"Unexpected response: {response.text[:200]}")
    
    
    def find_create_task(client: httpx.Client) -> str:
        """Returns the ID of the task that created the database. Every create,
        update and delete runs as a task. The IDs sort by creation time, and
        sort_order=asc lists the oldest task first."""
        reply = get(client, f"/v1/databases/{DATABASE_ID}/tasks",
                    {"sort_order": "asc"})
        for task in reply.get("tasks") or []:
            if task.get("type") == "create":
                return task["task_id"]
        raise ControlPlaneError(f"no create task for {DATABASE_ID}")
    
    
    def follow_task(client: httpx.Client, task_id: str) -> str:
        """Prints the log of a task as it grows, until the task finishes, and
        returns its final status. Each log reply carries last_entry_id, and
        passing that back as after_entry_id fetches only the newer entries.
        The status is read before the log, so that once it is final, the log
        that follows it is complete."""
        path = f"/v1/databases/{DATABASE_ID}/tasks/{task_id}"
        deadline = time.monotonic() + FOLLOW_SECONDS
        after = None
        while True:
            status = get(client, path).get("status")
    
            log = get(client, f"{path}/log",
                      {"after_entry_id": after} if after else None)
            for entry in log.get("entries") or []:
                print(f"Log: {entry.get('message')}")
            after = log.get("last_entry_id") or after
    
            if status in FINAL_STATUSES:
                return status
            if time.monotonic() >= deadline:
                raise ControlPlaneError(
                    f"task {task_id} was still {status} after {FOLLOW_SECONDS} seconds")
            time.sleep(POLL_SECONDS)
    
    
    def main() -> int:
        try:
            with httpx.Client(base_url=BASE_URL, timeout=TIMEOUT_SECONDS) as client:
                task_id = find_create_task(client)
                print("Task: create")
                status = follow_task(client, task_id)
        # httpx.HTTPError is the base class for failures to reach the server,
        # such as a refused connection or a timeout.
        except (httpx.HTTPError, ControlPlaneError) as e:
            print(f"Control Plane error: {e}", file=sys.stderr)
            return 1
    
        print(f"Status: {status}")
        return 0 if status == "completed" else 1
    
    
    if __name__ == "__main__":
        sys.exit(main())
    
    ```

=== "TypeScript"

    ```typescript
    /*
     * Ellie's Postgres Cookbook
     * Finding the task that created a pgEdge Control Plane database, and
     * following its log until the task finishes, using the built-in fetch.
     *
     * These examples are for the Control Plane v0.11.0.
     *
     * Copyright (c) 2026, pgEdge, Inc.
     * This code is released under the PostgreSQL License.
     */
    
    // Node.js provides fetch and AbortSignal as globals; setTimeout from
    // timers/promises returns a promise, which suits a polling loop.
    import { setTimeout as sleep } from "node:timers/promises";
    
    // The || operator, unlike ??, also treats an empty variable as unset.
    const baseUrl = (process.env.CONTROL_PLANE_URL || "http://localhost:3000").replace(/\/+$/, "");
    const databaseId = process.env.CONTROL_PLANE_DATABASE_ID || "cookbook";
    
    const timeoutMs = 30_000;
    
    // How long to follow a task that is still running, and how often to check.
    const followMs = 600_000;
    const pollMs = 5_000;
    
    // The statuses after which a task does not change again.
    const finalStatuses = new Set(["completed", "failed", "canceled"]);
    
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
    
    interface Task {
      task_id?: string;
      type?: string;
      status?: string;
    }
    
    // Returns the ID of the task that created the database. Every create,
    // update and delete runs as a task. The IDs sort by creation time, and
    // sort_order=asc lists the oldest task first.
    async function findCreateTask(): Promise<string> {
      const reply = await get<{ tasks?: Task[] }>(
        `/v1/databases/${databaseId}/tasks?sort_order=asc`,
      );
      const task = (reply.tasks ?? []).find((t) => t.type === "create");
      if (!task?.task_id) {
        throw new Error(`no create task for ${databaseId}`);
      }
      return task.task_id;
    }
    
    interface TaskLog {
      last_entry_id?: string;
      entries?: { message?: string }[];
    }
    
    // Prints the log of a task as it grows, until the task finishes, and
    // returns its final status. Each log reply carries last_entry_id, and
    // passing that back as after_entry_id fetches only the newer entries. The
    // status is read before the log, so that once it is final, the log that
    // follows it is complete.
    async function followTask(taskId: string): Promise<string> {
      const path = `/v1/databases/${databaseId}/tasks/${taskId}`;
      const deadline = Date.now() + followMs;
      let after: string | undefined;
      for (;;) {
        const { status = "unknown" } = await get<Task>(path);
    
        const query = after ? `?after_entry_id=${encodeURIComponent(after)}` : "";
        const log = await get<TaskLog>(`${path}/log${query}`);
        for (const entry of log.entries ?? []) {
          console.log(`Log: ${entry.message}`);
        }
        after = log.last_entry_id || after;
    
        if (finalStatuses.has(status)) {
          return status;
        }
        if (Date.now() >= deadline) {
          throw new Error(`task ${taskId} was still ${status} after ${followMs / 1000} seconds`);
        }
        await sleep(pollMs);
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
      try {
        const taskId = await findCreateTask();
        console.log("Task: create");
        const status = await followTask(taskId);
        console.log(`Status: ${status}`);
        return status === "completed" ? 0 : 1;
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
     * Finding the task that created a pgEdge Control Plane database, and
     * following its log until the task finishes, using java.net.http and
     * Jackson.
     *
     * These examples are for the Control Plane v0.11.0.
     *
     * Copyright (c) 2026, pgEdge, Inc.
     * This code is released under the PostgreSQL License.
     */
    
    import java.io.IOException;
    import java.net.URI;
    import java.net.URLEncoder;
    import java.net.http.HttpClient;
    import java.net.http.HttpRequest;
    import java.net.http.HttpResponse;
    import java.net.http.HttpTimeoutException;
    import java.nio.charset.StandardCharsets;
    import java.time.Duration;
    import java.util.Set;
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
        static final String DATABASE_ID = envOr("CONTROL_PLANE_DATABASE_ID", "cookbook");
    
        static final Duration TIMEOUT = Duration.ofSeconds(30);
    
        // How long to follow a task that is still running, and how often to
        // check.
        static final Duration FOLLOW_FOR = Duration.ofSeconds(600);
        static final Duration POLL_INTERVAL = Duration.ofSeconds(5);
    
        // The statuses after which a task does not change again.
        static final Set<String> FINAL_STATUSES = Set.of("completed", "failed", "canceled");
    
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
    
        /**
         * Returns the ID of the task that created the database. Every create,
         * update and delete runs as a task. The IDs sort by creation time, and
         * sort_order=asc lists the oldest task first.
         */
        static String findCreateTask(HttpClient client)
                throws IOException, InterruptedException, ControlPlaneException {
            JsonNode reply = get(client,
                    "/v1/databases/" + DATABASE_ID + "/tasks?sort_order=asc");
            for (JsonNode task : reply.path("tasks")) {
                if (task.path("type").asString("").equals("create")) {
                    return task.path("task_id").asString();
                }
            }
            throw new ControlPlaneException("no create task for " + DATABASE_ID);
        }
    
        /**
         * Prints the log of a task as it grows, until the task finishes, and
         * returns its final status. Each log reply carries last_entry_id, and
         * passing that back as after_entry_id fetches only the newer entries.
         * The status is read before the log, so that once it is final, the log
         * that follows it is complete.
         */
        static String followTask(HttpClient client, String taskId)
                throws IOException, InterruptedException, ControlPlaneException {
            String path = "/v1/databases/" + DATABASE_ID + "/tasks/" + taskId;
            long deadline = System.nanoTime() + FOLLOW_FOR.toNanos();
            String after = "";
            while (true) {
                String status = get(client, path).path("status").asString("unknown");
    
                String query = after.isEmpty() ? ""
                        : "?after_entry_id=" + URLEncoder.encode(after, StandardCharsets.UTF_8);
                JsonNode log = get(client, path + "/log" + query);
                for (JsonNode entry : log.path("entries")) {
                    System.out.println("Log: " + entry.path("message").asString(""));
                }
                String last = log.path("last_entry_id").asString("");
                if (!last.isEmpty()) {
                    after = last;
                }
    
                if (FINAL_STATUSES.contains(status)) {
                    return status;
                }
                if (System.nanoTime() >= deadline) {
                    throw new ControlPlaneException("task " + taskId + " was still "
                            + status + " after " + FOLLOW_FOR.toSeconds() + " seconds");
                }
                Thread.sleep(POLL_INTERVAL.toMillis());
            }
        }
    
        public static void main(String[] args) {
            String status;
            try {
                HttpClient client = HttpClient.newHttpClient();
                String taskId = findCreateTask(client);
                System.out.println("Task: create");
                status = followTask(client, taskId);
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
    
            System.out.println("Status: " + status);
            if (!status.equals("completed")) {
                System.exit(1);
            }
        }
    }
    
    ```

=== "C#"

    ```csharp
    /*
     * Ellie's Postgres Cookbook
     * Finding the task that created a pgEdge Control Plane database, and
     * following its log until the task finishes, using HttpClient and
     * System.Text.Json.
     *
     * These examples are for the Control Plane v0.11.0.
     *
     * Copyright (c) 2026, pgEdge, Inc.
     * This code is released under the PostgreSQL License.
     */
    
    using System.Diagnostics;
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
    
    static string DatabaseId() => EnvOr("CONTROL_PLANE_DATABASE_ID", "cookbook");
    
    const int TimeoutSeconds = 30;
    
    // How long to follow a task that is still running, and how often to check.
    const int FollowSeconds = 600;
    const int PollSeconds = 5;
    
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
    
    // Returns the ID of the task that created the database. Every create,
    // update and delete runs as a task. The IDs sort by creation time, and
    // sort_order=asc lists the oldest task first.
    static async Task<string> FindCreateTaskAsync(HttpClient client)
    {
        var reply = await GetAsync(
            client, $"/v1/databases/{DatabaseId()}/tasks?sort_order=asc");
        foreach (var task in reply["tasks"] as JsonArray ?? [])
        {
            if (task?["type"]?.ToString() == "create" &&
                task["task_id"]?.ToString() is { } taskId)
            {
                return taskId;
            }
        }
        throw new ControlPlaneException($"no create task for {DatabaseId()}");
    }
    
    // Prints the log of a task as it grows, until the task finishes, and
    // returns its final status. Each log reply carries last_entry_id, and
    // passing that back as after_entry_id fetches only the newer entries. The
    // status is read before the log, so that once it is final, the log that
    // follows it is complete.
    static async Task<string> FollowTaskAsync(HttpClient client, string taskId)
    {
        string[] finalStatuses = ["completed", "failed", "canceled"];
        var path = $"/v1/databases/{DatabaseId()}/tasks/{taskId}";
        var clock = Stopwatch.StartNew();
        var after = "";
        while (true)
        {
            var task = await GetAsync(client, path);
            var status = task["status"]?.ToString() ?? "unknown";
    
            var query = after == "" ? "" : $"?after_entry_id={Uri.EscapeDataString(after)}";
            var log = await GetAsync(client, $"{path}/log{query}");
            foreach (var entry in log["entries"] as JsonArray ?? [])
            {
                Console.WriteLine($"Log: {entry?["message"]}");
            }
            if (log["last_entry_id"]?.ToString() is { Length: > 0 } last)
            {
                after = last;
            }
    
            if (finalStatuses.Contains(status))
            {
                return status;
            }
            if (clock.Elapsed.TotalSeconds >= FollowSeconds)
            {
                throw new ControlPlaneException(
                    $"task {taskId} was still {status} after {FollowSeconds} seconds");
            }
            await Task.Delay(TimeSpan.FromSeconds(PollSeconds));
        }
    }
    
    string status;
    try
    {
        // using disposes of the client, and closes its connections, when the
        // block exits, whether or not an error occurred.
        using var client = new HttpClient
        {
            Timeout = TimeSpan.FromSeconds(TimeoutSeconds),
        };
        var taskId = await FindCreateTaskAsync(client);
        Console.WriteLine("Task: create");
        status = await FollowTaskAsync(client, taskId);
    }
    // HttpRequestException covers failures to reach the server, such as a
    // refused connection, and TaskCanceledException covers a timeout.
    catch (Exception e) when (
        e is HttpRequestException or TaskCanceledException or ControlPlaneException)
    {
        Console.Error.WriteLine($"Control Plane error: {e.Message}");
        return 1;
    }
    
    Console.WriteLine($"Status: {status}");
    return status == "completed" ? 0 : 1;
    
    // C# requires type declarations to follow the top-level statements, so
    // the exception that the program throws for an error reply is declared
    // here, at the end.
    class ControlPlaneException(string message) : Exception(message);
    
    ```

=== "Go"

    ```go
    // Ellie's Postgres Cookbook
    // Finding the task that created a pgEdge Control Plane database, and
    // following its log until the task finishes, using net/http.
    //
    // These examples are for the Control Plane v0.11.0.
    //
    // Copyright (c) 2026, pgEdge, Inc.
    // This code is released under the PostgreSQL License.
    
    package main
    
    import (
    	"encoding/json"
    	"fmt"
    	"io"
    	"net/http"
    	"net/url"
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
    
    var (
    	baseURL    = strings.TrimRight(envOr("CONTROL_PLANE_URL", "http://localhost:3000"), "/")
    	databaseID = envOr("CONTROL_PLANE_DATABASE_ID", "cookbook")
    )
    
    const timeout = 30 * time.Second
    
    // How long to follow a task that is still running, and how often to check.
    const (
    	followFor    = 600 * time.Second
    	pollInterval = 5 * time.Second
    )
    
    // finalStatuses holds the statuses after which a task does not change
    // again.
    var finalStatuses = map[string]bool{"completed": true, "failed": true, "canceled": true}
    
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
    
    
    // task holds the fields of a task that this program uses.
    type task struct {
    	TaskID string `json:"task_id"`
    	Type   string `json:"type"`
    	Status string `json:"status"`
    }
    
    // findCreateTask returns the ID of the task that created the database.
    // Every create, update and delete runs as a task. The IDs sort by
    // creation time, and sort_order=asc lists the oldest task first.
    func findCreateTask(client *http.Client) (string, error) {
    	var reply struct {
    		Tasks []task `json:"tasks"`
    	}
    	err := get(client, "/v1/databases/"+databaseID+"/tasks?sort_order=asc", &reply)
    	if err != nil {
    		return "", err
    	}
    	for _, t := range reply.Tasks {
    		if t.Type == "create" {
    			return t.TaskID, nil
    		}
    	}
    	return "", fmt.Errorf("no create task for %s", databaseID)
    }
    
    
    // followTask prints the log of a task as it grows, until the task
    // finishes, and returns its final status. Each log reply carries
    // last_entry_id, and passing that back as after_entry_id fetches only the
    // newer entries. The status is read before the log, so that once it is
    // final, the log that follows it is complete.
    func followTask(client *http.Client, taskID string) (string, error) {
    	path := "/v1/databases/" + databaseID + "/tasks/" + taskID
    	deadline := time.Now().Add(followFor)
    	after := ""
    	for {
    		var t task
    		if err := get(client, path, &t); err != nil {
    			return "", err
    		}
    
    		var log struct {
    			LastEntryID string `json:"last_entry_id"`
    			Entries     []struct {
    				Message string `json:"message"`
    			} `json:"entries"`
    		}
    		query := ""
    		if after != "" {
    			query = "?after_entry_id=" + url.QueryEscape(after)
    		}
    		if err := get(client, path+"/log"+query, &log); err != nil {
    			return "", err
    		}
    		for _, entry := range log.Entries {
    			fmt.Printf("Log: %s\n", entry.Message)
    		}
    		if log.LastEntryID != "" {
    			after = log.LastEntryID
    		}
    
    		if finalStatuses[t.Status] {
    			return t.Status, nil
    		}
    		if time.Now().After(deadline) {
    			return "", fmt.Errorf("task %s was still %s after %v", taskID, t.Status, followFor)
    		}
    		time.Sleep(pollInterval)
    	}
    }
    
    
    // run finds the task and follows it, and returns any error to the
    // caller.
    func run() error {
    	client := &http.Client{Timeout: timeout}
    
    	taskID, err := findCreateTask(client)
    	if err != nil {
    		return err
    	}
    	fmt.Println("Task: create")
    	status, err := followTask(client, taskID)
    	if err != nil {
    		return err
    	}
    	fmt.Printf("Status: %s\n", status)
    	if status != "completed" {
    		return fmt.Errorf("the task finished with the status %s", status)
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
    // Finding the task that created a pgEdge Control Plane database, and
    // following its log until the task finishes, using reqwest and serde_json.
    //
    // These examples are for the Control Plane v0.11.0.
    //
    // Copyright (c) 2026, pgEdge, Inc.
    // This code is released under the PostgreSQL License.
    
    use std::env;
    use std::error::Error;
    use std::process::ExitCode;
    use std::thread;
    use std::time::{Duration, Instant};
    
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
    
    fn database_id() -> String {
        env_or("CONTROL_PLANE_DATABASE_ID", "cookbook")
    }
    
    const TIMEOUT: Duration = Duration::from_secs(30);
    
    // How long to follow a task that is still running, and how often to check.
    const FOLLOW_FOR: Duration = Duration::from_secs(600);
    const POLL_INTERVAL: Duration = Duration::from_secs(5);
    
    /// The statuses after which a task does not change again.
    const FINAL_STATUSES: [&str; 3] = ["completed", "failed", "canceled"];
    
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
    
    /// Returns the ID of the task that created the database. Every create,
    /// update and delete runs as a task. The IDs sort by creation time, and
    /// sort_order=asc lists the oldest task first.
    fn find_create_task(client: &Client) -> Result<String, BoxError> {
        let path = format!("/v1/databases/{}/tasks?sort_order=asc", database_id());
        let reply = get(client, &path)?;
        let tasks = reply["tasks"].as_array().cloned().unwrap_or_default();
        tasks
            .iter()
            .find(|task| task["type"] == "create")
            .and_then(|task| task["task_id"].as_str())
            .map(str::to_string)
            .ok_or_else(|| format!("no create task for {}", database_id()).into())
    }
    
    /// Prints the log of a task as it grows, until the task finishes, and
    /// returns its final status. Each log reply carries last_entry_id, and
    /// passing that back as after_entry_id fetches only the newer entries.
    /// The status is read before the log, so that once it is final, the log
    /// that follows it is complete.
    fn follow_task(client: &Client, task_id: &str) -> Result<String, BoxError> {
        let path = format!("/v1/databases/{}/tasks/{task_id}", database_id());
        let deadline = Instant::now() + FOLLOW_FOR;
        let mut after = String::new();
        loop {
            let task = get(client, &path)?;
            let status = task["status"].as_str().unwrap_or("unknown").to_string();
    
            // Entry IDs are UUIDs, so they need no escaping in a URL.
            let query = if after.is_empty() {
                String::new()
            } else {
                format!("?after_entry_id={after}")
            };
            let log = get(client, &format!("{path}/log{query}"))?;
            for entry in log["entries"].as_array().into_iter().flatten() {
                println!("Log: {}", entry["message"].as_str().unwrap_or(""));
            }
            if let Some(last) = log["last_entry_id"].as_str().filter(|s| !s.is_empty()) {
                after = last.to_string();
            }
    
            if FINAL_STATUSES.contains(&status.as_str()) {
                return Ok(status);
            }
            if Instant::now() >= deadline {
                return Err(format!(
                    "task {task_id} was still {status} after {} seconds",
                    FOLLOW_FOR.as_secs()
                )
                .into());
            }
            thread::sleep(POLL_INTERVAL);
        }
    }
    
    /// Finds the task and follows it, and returns its final status. The ?
    /// operator returns any error to the caller.
    fn run() -> Result<String, BoxError> {
        let client = Client::builder().timeout(TIMEOUT).build()?;
        let task_id = find_create_task(&client)?;
        println!("Task: create");
        follow_task(&client, &task_id)
    }
    
    /// Reports any error returned by run() and exits with a failure status.
    /// The top-level error is often generic ("error sending request"), so the
    /// chain of underlying causes is printed too.
    fn main() -> ExitCode {
        match run() {
            Ok(status) => {
                println!("Status: {status}");
                if status == "completed" {
                    ExitCode::SUCCESS
                } else {
                    ExitCode::FAILURE
                }
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
    # Finding the task that created a pgEdge Control Plane database, and
    # following its log until the task finishes, using Net::HTTP.
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
    DATABASE_ID = env_or("CONTROL_PLANE_DATABASE_ID", "cookbook")
    
    TIMEOUT_SECONDS = 30
    
    # How long to follow a task that is still running, and how often to check.
    FOLLOW_SECONDS = 600
    POLL_SECONDS = 5
    
    # The statuses after which a task does not change again.
    FINAL_STATUSES = %w[completed failed canceled].freeze
    
    # Raised when the Control Plane rejects a request or replies oddly.
    class ControlPlaneError < StandardError; end
    
    # Fetches a path from the server, and returns the decoded reply. The query
    # hash is encoded and added to the URL.
    def get(http, path, query = {})
      uri = URI("#{BASE_URL}#{path}")
      uri.query = URI.encode_www_form(query) unless query.empty?
      response = http.request(Net::HTTP::Get.new(uri))
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
    
    # Returns the ID of the task that created the database. Every create,
    # update and delete runs as a task. The IDs sort by creation time, and
    # sort_order=asc lists the oldest task first.
    def find_create_task(http)
      reply = get(http, "/v1/databases/#{DATABASE_ID}/tasks", { "sort_order" => "asc" })
      task = (reply["tasks"] || []).find { |t| t["type"] == "create" }
      raise ControlPlaneError, "no create task for #{DATABASE_ID}" unless task
    
      task["task_id"]
    end
    
    # Prints the log of a task as it grows, until the task finishes, and
    # returns its final status. Each log reply carries last_entry_id, and
    # passing that back as after_entry_id fetches only the newer entries. The
    # status is read before the log, so that once it is final, the log that
    # follows it is complete.
    def follow_task(http, task_id)
      path = "/v1/databases/#{DATABASE_ID}/tasks/#{task_id}"
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + FOLLOW_SECONDS
      after = nil
      loop do
        status = get(http, path)["status"] || "unknown"
    
        log = get(http, "#{path}/log", after ? { "after_entry_id" => after } : {})
        (log["entries"] || []).each { |entry| puts "Log: #{entry["message"]}" }
        after = log["last_entry_id"] unless log["last_entry_id"].to_s.empty?
    
        return status if FINAL_STATUSES.include?(status)
        if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
          raise ControlPlaneError, "task #{task_id} was still #{status} after #{FOLLOW_SECONDS} seconds"
        end
    
        sleep POLL_SECONDS
      end
    end
    
    begin
      uri = URI(BASE_URL)
      # start opens a connection, and closes it when the block exits, whether
      # or not an error occurred.
      status = Net::HTTP.start(
        uri.host, uri.port,
        use_ssl: uri.scheme == "https",
        open_timeout: TIMEOUT_SECONDS, read_timeout: TIMEOUT_SECONDS
      ) do |http|
        task_id = find_create_task(http)
        puts "Task: create"
        follow_task(http, task_id)
      end
    # SystemCallError covers a refused connection, Timeout::Error covers the
    # connection and read timeouts, and SocketError covers an unknown host.
    rescue ControlPlaneError, SystemCallError, Timeout::Error, SocketError, IOError => e
      warn "Control Plane error: #{e.message}"
      exit 1
    end
    
    puts "Status: #{status}"
    exit 1 unless status == "completed"
    
    ```

=== "curl"

    ```bash
    #!/usr/bin/env bash
    #
    # Ellie's Postgres Cookbook
    # Finding the task that created a pgEdge Control Plane database, and
    # following its log until the task finishes, using curl and jq.
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
    DATABASE_ID="${CONTROL_PLANE_DATABASE_ID:-cookbook}"
    
    TIMEOUT_SECONDS=30
    
    # How long to follow a task that is still running, and how often to check.
    FOLLOW_SECONDS=600
    POLL_SECONDS=5
    
    # Fetches a path from the server and prints the JSON reply. With
    # --fail-with-body, curl exits non-zero on an HTTP error status but still
    # prints the body, which carries the server's explanation.
    get() {
        curl --silent --show-error --fail-with-body \
            --max-time "$TIMEOUT_SECONDS" "$CONTROL_PLANE_URL$1"
    }
    
    # Prints the ID of the task that created the database. Every create,
    # update and delete runs as a task. The IDs sort by creation time, and
    # sort_order=asc lists the oldest task first.
    find_create_task() {
        local response
        response="$(get "/v1/databases/$DATABASE_ID/tasks?sort_order=asc")" || {
            echo "Control Plane error: $response" >&2
            return 1
        }
        jq -er 'first(.tasks[] | select(.type == "create")) | .task_id' \
            <<<"$response" || {
            echo "Control Plane error: no create task for $DATABASE_ID" >&2
            return 1
        }
    }
    
    # Prints the log of a task as it grows, until the task finishes, and then
    # prints its final status. Each log reply carries last_entry_id, and
    # passing that back as after_entry_id fetches only the newer entries. The
    # status is read before the log, so that once it is final, the log that
    # follows it is complete.
    follow_task() {
        local task_id="$1" path="/v1/databases/$DATABASE_ID/tasks/$1"
        local deadline=$((SECONDS + FOLLOW_SECONDS)) after="" task status log
    
        while true; do
            task="$(get "$path")" || {
                echo "Control Plane error: $task" >&2
                return 1
            }
            status="$(jq -er '.status' <<<"$task")"
    
            log="$(get "$path/log${after:+?after_entry_id=$after}")" || {
                echo "Control Plane error: $log" >&2
                return 1
            }
            jq -r '.entries[] | "Log: \(.message)"' <<<"$log"
            after="$(jq -r '.last_entry_id // empty' <<<"$log")"
    
            case "$status" in
                completed|failed|canceled) break ;;
            esac
            if ((SECONDS >= deadline)); then
                echo "Control Plane error: task $task_id was still $status after $FOLLOW_SECONDS seconds" >&2
                return 1
            fi
            sleep "$POLL_SECONDS"
        done
    
        echo "Status: $status"
        [[ "$status" == "completed" ]]
    }
    
    main() {
        local task_id
        task_id="$(find_create_task)" || exit 1
        echo "Task: create"
        follow_task "$task_id" || exit 1
    }
    
    main
    
    ```

## Next Steps

The following resources provide more information about the topics in this
recipe:

- The [Changing a Database's Settings](update_database.md) recipe shows how to
  start an update task and wait for it to finish.
- The [Creating a Database](create_database.md) recipe shows how to create a
  database, which starts a task like the one that this recipe follows.
- The
  [pgEdge Control Plane documentation](https://docs.pgedge.com/control-plane/v0-11/)
  describes every endpoint and setting.
- The [Contributing a Recipe](../contributing.md) page explains how to add a
  recipe or a language to the cookbook.
