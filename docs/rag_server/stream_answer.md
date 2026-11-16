# Streaming an Answer

This recipe asks a pgEdge RAG Server pipeline a question and prints the
answer as the language model writes it, instead of waiting for the complete
reply. Streaming makes an application feel responsive, because the first
words appear in a moment rather than after the whole answer is ready. Each
step shows the code in every supported language; selecting a language tab
switches every tab on the site to that language.

These examples are for pgEdge RAG Server 2.0.0.

The wording of the answer varies from run to run, because a language model
writes it, but the output has the following shape:

```text
Question: How long does the Acme Widget 2.0 take to charge?
Answer:
The Acme Widget 2.0 takes ninety minutes to fully charge.
Chunks received: 15
```

## Preparing the Ingredients

The examples need a running RAG Server with a pipeline that holds documents;
the examples assume a pipeline named `cookbook` that holds the fictional Acme
Widget support documents, which the `scripts/start_rag_server.sh` script in
the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook)
loads and starts in Docker. The [Asking a Question](ask_question.md) recipe
describes the request that this recipe extends.

A request with `"stream": true` in its JSON body makes the server reply with
[Server-Sent Events](https://html.spec.whatwg.org/multipage/server-sent-events.html),
a stream of events that stays open until the answer is complete. Each event
is a line that starts with `data:` and holds a JSON object, followed by a
blank line:

```text
data: {"type":"chunk","content":"The"}

data: {"type":"chunk","content":" Acme"}

data: {"type":"done"}
```

The `type` field says what kind of event it is. The following table lists
the three types:

| Type    | Fields    | Meaning                                              |
|---------|-----------|------------------------------------------------------|
| `chunk` | `content` | The next piece of the answer.                        |
| `error` | `error`   | The request failed after the stream had started.     |
| `done`  | none      | The server has finished sending events.              |

The programs use only an HTTP client and a JSON decoder. The following table
lists the client that each example uses:

| Language   | HTTP client                                                                                  |
|------------|----------------------------------------------------------------------------------------------|
| Python     | [httpx](https://www.python-httpx.org/)                                                       |
| TypeScript | The `fetch` function that Node.js provides                                                   |
| Java       | The `java.net.http` package, with [Jackson](https://github.com/FasterXML/jackson) for JSON   |
| C#         | The `HttpClient` class and `System.Text.Json`, which .NET provides                           |
| Go         | The `net/http` package                                                                       |
| Rust       | [reqwest](https://docs.rs/reqwest/), with [serde_json](https://docs.rs/serde_json/) for JSON |
| Ruby       | `Net::HTTP` and `json` from the standard library                                             |
| curl       | [curl](https://curl.se/) and [jq](https://jqlang.org/)                                       |

The following tabs show the dependency declaration from each example project;
the TypeScript project needs only the compiler and the Node.js type
definitions, the Java project adds Jackson, the Rust project adds reqwest and
serde_json, and the C#, Go and Ruby projects need nothing beyond their standard
libraries:

=== "Python"

    ```text
    # httpx, an HTTP client with a requests-like API.
    httpx>=0.28,<1
    ```

=== "TypeScript"

    ```json
    {
      "name": "stream-answer",
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

Each program begins by importing the HTTP client, along with any standard
library modules that it uses. The TypeScript program imports nothing, and
the curl script stops at the first failed command and checks that `curl`
and `jq` are installed. The following tabs show the imports for each
language:

=== "Python"

    ```python
    import json
    import os
    import sys
    from collections.abc import Iterable, Iterator
    from urllib.parse import quote
    
    import httpx
    ```

=== "TypeScript"

    ```typescript
    // Node.js provides fetch, AbortSignal, and TextDecoder as globals, so this
    // program imports nothing.
    ```

=== "Java"

    ```java
    import java.io.BufferedReader;
    import java.io.IOException;
    import java.io.InputStream;
    import java.io.InputStreamReader;
    import java.net.URI;
    import java.net.URLEncoder;
    import java.net.http.HttpClient;
    import java.net.http.HttpRequest;
    import java.net.http.HttpResponse;
    import java.net.http.HttpTimeoutException;
    import java.nio.charset.StandardCharsets;
    import java.time.Duration;
    import java.util.ArrayList;
    import java.util.List;
    import java.util.concurrent.Executors;
    import java.util.concurrent.ScheduledExecutorService;
    import java.util.concurrent.ScheduledFuture;
    import java.util.concurrent.TimeUnit;
    import java.util.concurrent.atomic.AtomicBoolean;
    import java.util.function.Consumer;
    
    import tools.jackson.core.JacksonException;
    import tools.jackson.databind.JsonNode;
    import tools.jackson.databind.ObjectMapper;
    import tools.jackson.databind.json.JsonMapper;
    ```

=== "C#"

    ```csharp
    using System.Net.Http.Json;
    using System.Text.Json;
    using System.Text.Json.Nodes;
    ```

=== "Go"

    ```go
    import (
    	"bufio"
    	"bytes"
    	"encoding/json"
    	"errors"
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
    use std::io::{self, BufRead, BufReader, Read, Write};
    use std::process::ExitCode;
    use std::time::Duration;
    
    use reqwest::blocking::Client;
    use reqwest::Url;
    use serde_json::{json, Value};
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
        command -v "$tool" >/dev/null || { echo "$tool is required" >&2; exit 1; }
    done
    ```

## Configuring the Program

The examples read the address of the RAG Server and the name of the pipeline
from environment variables. Each example treats an empty variable as unset,
and uses the default instead. The following table describes the environment
variables that the examples read:

| Variable         | Default                 | Description                      |
|------------------|-------------------------|----------------------------------|
| `RAG_SERVER_URL` | `http://localhost:8080` | The base URL of the RAG Server.  |
| `RAG_PIPELINE`   | `cookbook`              | The name of the pipeline to ask. |

The server may wait a while for the language model to begin, particularly a
small model on a modest machine, so each program allows 300 seconds for the
request. The following tabs show how each program reads its settings:

=== "Python"

    ```python
    # The or operator treats an empty variable as unset.
    BASE_URL = (os.environ.get("RAG_SERVER_URL") or "http://localhost:8080").rstrip("/")
    PIPELINE = os.environ.get("RAG_PIPELINE") or "cookbook"
    
    QUESTION = "How long does the Acme Widget 2.0 take to charge?"
    
    # The timeout applies to each wait for data rather than to the whole
    # stream, but the server may wait for the language model to begin, and a
    # small model on a modest machine can take a while, so allow plenty of
    # time.
    TIMEOUT_SECONDS = 300.0
    ```

=== "TypeScript"

    ```typescript
    // The || operator, unlike ??, also treats an empty variable as unset.
    const baseUrl = (process.env.RAG_SERVER_URL || "http://localhost:8080").replace(/\/+$/, "");
    const pipeline = process.env.RAG_PIPELINE || "cookbook";
    
    const question = "How long does the Acme Widget 2.0 take to charge?";
    
    // The server may wait for the language model before the first chunk
    // arrives, and a small model on a modest machine can take a while, so
    // allow plenty of time for the whole stream.
    const timeoutMs = 300_000;
    ```

=== "Java"

    ```java
    /** Returns the value of an environment variable, or a fallback. */
    static String envOr(String name, String fallback) {
        String value = System.getenv(name);
        return (value != null && !value.isEmpty()) ? value : fallback;
    }
    
    static final String BASE_URL =
            envOr("RAG_SERVER_URL", "http://localhost:8080")
                    .replaceAll("/+$", "");
    static final String PIPELINE = envOr("RAG_PIPELINE", "cookbook");
    
    static final String QUESTION =
            "How long does the Acme Widget 2.0 take to charge?";
    
    // The program applies the timeout to the wait for the response and to
    // each wait for a line of the stream, rather than to the whole stream,
    // but the server may wait for the language model to begin, and a small
    // model on a modest machine can take a while, so allow plenty of time.
    static final Duration TIMEOUT = Duration.ofSeconds(300);
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
        EnvOr("RAG_SERVER_URL", "http://localhost:8080").TrimEnd('/');
    static string Pipeline() => EnvOr("RAG_PIPELINE", "cookbook");
    
    const string Question = "How long does the Acme Widget 2.0 take to charge?";
    
    // The program applies the timeout to the wait for the response and to each
    // wait for a line of the stream, rather than to the whole stream, but the
    // server may wait for the language model to begin, and a small model on a
    // modest machine can take a while, so allow plenty of time.
    const int TimeoutSeconds = 300;
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
    	baseURL  = strings.TrimRight(envOr("RAG_SERVER_URL", "http://localhost:8080"), "/")
    	pipeline = envOr("RAG_PIPELINE", "cookbook")
    )
    
    const question = "How long does the Acme Widget 2.0 take to charge?"
    
    // The client's timeout covers the whole exchange, including the time it
    // takes to read the stream. The server may wait for the language model
    // before the first chunk arrives, and a small model on a modest machine
    // can take a while, so allow plenty of time.
    const timeout = 300 * time.Second
    
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
        env_or("RAG_SERVER_URL", "http://localhost:8080")
            .trim_end_matches('/')
            .to_string()
    }
    
    fn pipeline() -> String {
        env_or("RAG_PIPELINE", "cookbook")
    }
    
    const QUESTION: &str = "How long does the Acme Widget 2.0 take to charge?";
    
    /// The blocking client applies the timeout to the wait for the response
    /// and to each wait for data, rather than to the whole stream, but the
    /// server may wait for the language model to begin, and a small model on a
    /// modest machine can take a while, so allow plenty of time.
    const TIMEOUT: Duration = Duration::from_secs(300);
    ```

=== "Ruby"

    ```ruby
    # Returns the value of an environment variable, or a fallback if the
    # variable is unset or empty.
    def env_or(name, fallback)
      value = ENV[name]
      value.nil? || value.empty? ? fallback : value
    end
    
    BASE_URL = env_or("RAG_SERVER_URL", "http://localhost:8080").sub(%r{/+\z}, "")
    PIPELINE = env_or("RAG_PIPELINE", "cookbook")
    
    QUESTION = "How long does the Acme Widget 2.0 take to charge?"
    
    # The timeout applies to each wait for data rather than to the whole
    # stream, but the server may wait for the language model to begin, and a
    # small model on a modest machine can take a while, so allow plenty of
    # time.
    TIMEOUT_SECONDS = 300
    ```

=== "curl"

    ```bash
    # The :- operator treats an empty variable as unset.
    RAG_SERVER_URL="${RAG_SERVER_URL:-http://localhost:8080}"
    RAG_SERVER_URL="${RAG_SERVER_URL%/}"
    RAG_PIPELINE="${RAG_PIPELINE:-cookbook}"
    
    QUESTION="How long does the Acme Widget 2.0 take to charge?"
    
    # The server may wait for the language model before the first chunk
    # arrives, and a small model on a modest machine can take a while, so
    # allow plenty of time for the whole stream.
    TIMEOUT_SECONDS=300
    
    # Escapes a value for use in a URL path, as the other languages do.
    escape() { jq -rn --arg value "$1" '$value | @uri'; }
    ```

## Parsing the Events

An event can arrive in pieces, and a single network read can hold several
events or half of one, so the programs read the response line by line rather
than read by read. A parser collects the `data:` lines of an event, decodes
them as JSON when it reaches the blank line that ends the event, and ignores
comment lines and any other field. The parser also sends the last event when
the stream ends without a final blank line, so that a stream cut short in
that way does not lose its `done` event. The Java and C# HTTP clients stop
applying their timeout once the headers arrive, so those two programs give each
line of the stream its own 300-second limit, which the C# parser applies here
and the Java program applies in the next step; without it, a server that stops
sending part of the way through would leave the program waiting for ever. The
following tabs show the parser for each language:

=== "Python"

    ```python
    def read_events(lines: Iterable[str]) -> Iterator[dict]:
        """Parses Server-Sent Events, and yields the JSON object that the data
        of each event holds.
    
        An event is one or more "data:" lines followed by a blank line. The
        stream may end without the final blank line, so the last event is sent
        when the lines run out as well.
        """
        data: list[str] = []
        for line in lines:
            if line == "":
                if data:
                    yield json.loads("\n".join(data))
                    data = []
            elif line.startswith("data:"):
                # A single space after the colon is not part of the data.
                data.append(line[len("data:"):].removeprefix(" "))
            # Comment lines (which start with a colon) and other fields are
            # ignored.
        if data:
            yield json.loads("\n".join(data))
    ```

=== "TypeScript"

    ```typescript
    interface StreamEvent {
      type: string;
      content?: string;
      error?: string;
    }
    
    // Yields the lines of a streamed response body. A line can be split
    // across two reads, so keep the unfinished part until the next read.
    async function* readLines(body: ReadableStream<Uint8Array>): AsyncGenerator<string> {
      const reader = body.getReader();
      const decoder = new TextDecoder();
      let buffer = "";
      for (;;) {
        const { done, value } = await reader.read();
        // The stream option keeps a multi-byte character that is split across
        // two reads intact.
        buffer += decoder.decode(value, { stream: !done });
        let newline: number;
        while ((newline = buffer.indexOf("\n")) >= 0) {
          yield buffer.slice(0, newline).replace(/\r$/, "");
          buffer = buffer.slice(newline + 1);
        }
        if (done) break;
      }
      if (buffer) yield buffer;
    }
    
    // Parses Server-Sent Events, and yields the JSON object that the data of
    // each event holds. An event is one or more "data:" lines followed by a
    // blank line. The stream may end without the final blank line, so the last
    // event is sent when the lines run out as well.
    async function* readEvents(body: ReadableStream<Uint8Array>): AsyncGenerator<StreamEvent> {
      let data: string[] = [];
      for await (const line of readLines(body)) {
        if (line === "") {
          if (data.length > 0) {
            yield JSON.parse(data.join("\n")) as StreamEvent;
            data = [];
          }
        } else if (line.startsWith("data:")) {
          // A single space after the colon is not part of the data.
          data.push(line.slice("data:".length).replace(/^ /, ""));
        }
        // Comment lines (which start with a colon) and other fields are
        // ignored.
      }
      if (data.length > 0) {
        yield JSON.parse(data.join("\n")) as StreamEvent;
      }
    }
    ```

=== "Java"

    ```java
    // A mapper is safe to share, so the program creates only one.
    static final ObjectMapper MAPPER = JsonMapper.builder().build();
    
    /** Supplies the lines of a stream, returning null at the end. */
    interface LineSource {
        String readLine() throws IOException;
    }
    
    /**
     * Parses Server-Sent Events from a source of lines, and passes the JSON
     * object that the data of each event holds to handle, as each event
     * arrives.
     *
     * An event is one or more "data:" lines followed by a blank line. The
     * stream may end without the final blank line, so the last event is
     * sent when the lines run out as well. readTree() throws a
     * JacksonException for data that is not valid JSON.
     */
    static void readEvents(LineSource lines, Consumer<JsonNode> handle)
            throws IOException {
        List<String> data = new ArrayList<>();
        String line;
        while ((line = lines.readLine()) != null) {
            if (line.isEmpty()) {
                if (!data.isEmpty()) {
                    handle.accept(MAPPER.readTree(String.join("\n", data)));
                    data.clear();
                }
            } else if (line.startsWith("data:")) {
                // A single space after the colon is not part of the data.
                String value = line.substring("data:".length());
                data.add(value.startsWith(" ") ? value.substring(1) : value);
            }
            // Comment lines (which start with a colon) and other fields are
            // ignored.
        }
        if (!data.isEmpty()) {
            handle.accept(MAPPER.readTree(String.join("\n", data)));
        }
    }
    ```

=== "C#"

    ```csharp
    // Parses Server-Sent Events from a reader, and yields the JSON that the
    // data of each event holds, as each event arrives.
    //
    // An event is one or more "data:" lines followed by a blank line. The
    // stream may end without the final blank line, so the last event is sent
    // when the lines run out as well. JsonNode.Parse throws a JsonException
    // for data that is not valid JSON.
    static async IAsyncEnumerable<JsonNode?> ReadEventsAsync(StreamReader reader)
    {
        var data = new List<string>();
        while (true)
        {
            // The client's timeout stops applying once the headers arrive, so a
            // server that stops sending part of the way through would otherwise
            // leave the read waiting for ever. The token cancels a read for
            // which no line arrives in time.
            using var timeout = new CancellationTokenSource(
                TimeSpan.FromSeconds(TimeoutSeconds));
            string? line;
            try
            {
                line = await reader.ReadLineAsync(timeout.Token);
            }
            catch (OperationCanceledException) when (timeout.IsCancellationRequested)
            {
                throw new TimeoutException(
                    $"No data from the server for {TimeoutSeconds} seconds");
            }
            if (line is null)
            {
                break;
            }
    
            if (line.Length == 0)
            {
                if (data.Count > 0)
                {
                    yield return JsonNode.Parse(string.Join("\n", data));
                    data.Clear();
                }
            }
            else if (line.StartsWith("data:", StringComparison.Ordinal))
            {
                // A single space after the colon is not part of the data.
                var value = line["data:".Length..];
                data.Add(value.StartsWith(' ') ? value[1..] : value);
            }
            // Comment lines (which start with a colon) and other fields are
            // ignored.
        }
        if (data.Count > 0)
        {
            yield return JsonNode.Parse(string.Join("\n", data));
        }
    }
    ```

=== "Go"

    ```go
    // streamEvent is one event of the stream: a "chunk" with content, an
    // "error" with a message, or "done".
    type streamEvent struct {
    	Type    string `json:"type"`
    	Content string `json:"content"`
    	Error   string `json:"error"`
    }
    
    // readEvents parses Server-Sent Events from r, and calls handle with the
    // JSON object that the data of each event holds. An event is one or more
    // "data:" lines followed by a blank line. The stream may end without the
    // final blank line, so the last event is sent when the lines run out as
    // well.
    func readEvents(r io.Reader, handle func(streamEvent)) error {
    	var data []string
    
    	flush := func() error {
    		if len(data) == 0 {
    			return nil
    		}
    		var event streamEvent
    		err := json.Unmarshal([]byte(strings.Join(data, "\n")), &event)
    		data = nil
    		if err != nil {
    			return fmt.Errorf("invalid event: %w", err)
    		}
    		handle(event)
    		return nil
    	}
    
    	scanner := bufio.NewScanner(r)
    	// Allow lines of up to 1 MiB; the default limit is 64 KiB.
    	scanner.Buffer(make([]byte, 0, 64*1024), 1024*1024)
    	for scanner.Scan() {
    		line := scanner.Text()
    		if line == "" {
    			if err := flush(); err != nil {
    				return err
    			}
    		} else if after, found := strings.CutPrefix(line, "data:"); found {
    			// A single space after the colon is not part of the data.
    			data = append(data, strings.TrimPrefix(after, " "))
    		}
    		// Comment lines (which start with a colon) and other fields are
    		// ignored.
    	}
    	if err := scanner.Err(); err != nil {
    		return err
    	}
    	return flush()
    }
    
    ```

=== "Rust"

    ```rust
    /// The errors that the functions below return; a string converts into one
    /// with the ? operator or into().
    type BoxError = Box<dyn Error>;
    
    /// Parses Server-Sent Events from a reader, and passes the JSON that the
    /// data of each event holds to handle, as each event arrives.
    ///
    /// An event is one or more "data:" lines followed by a blank line. The
    /// stream may end without the final blank line, so the last event is sent
    /// when the lines run out as well.
    fn read_events(reader: impl BufRead, mut handle: impl FnMut(Value)) -> Result<(), BoxError> {
        let mut data: Vec<String> = Vec::new();
        for line in reader.lines() {
            let line = line?;
            if line.is_empty() {
                if !data.is_empty() {
                    handle(serde_json::from_str(&data.join("\n"))?);
                    data.clear();
                }
            } else if let Some(value) = line.strip_prefix("data:") {
                // A single space after the colon is not part of the data.
                data.push(value.strip_prefix(' ').unwrap_or(value).to_string());
            }
            // Comment lines (which start with a colon) and other fields are
            // ignored.
        }
        if !data.is_empty() {
            handle(serde_json::from_str(&data.join("\n"))?);
        }
        Ok(())
    }
    ```

=== "Ruby"

    ```ruby
    # Yields each line of a response body, without its line ending, as soon as
    # the whole line has arrived. read_body hands over the body in pieces that
    # need not end at a line break, so the start of a line waits in a buffer
    # for the rest.
    def each_line(response)
      buffer = String.new
      response.read_body do |piece|
        buffer << piece
        while (index = buffer.index("\n"))
          yield buffer.slice!(0..index).chomp.force_encoding(Encoding::UTF_8)
        end
      end
      yield buffer.chomp.force_encoding(Encoding::UTF_8) unless buffer.empty?
    end
    
    # Parses Server-Sent Events from a response, and yields the JSON that the
    # data of each event holds, as each event arrives.
    #
    # An event is one or more "data:" lines followed by a blank line. The
    # stream may end without the final blank line, so the last event is sent
    # when the lines run out as well. JSON.parse raises JSON::ParserError for
    # data that is not valid JSON.
    def read_events(response)
      data = []
      each_line(response) do |line|
        if line.empty?
          yield JSON.parse(data.join("\n")) unless data.empty?
          data = []
        elsif line.start_with?("data:")
          # A single space after the colon is not part of the data.
          data << line.delete_prefix("data:").delete_prefix(" ")
        end
        # Comment lines (which start with a colon) and other fields are
        # ignored.
      end
      yield JSON.parse(data.join("\n")) unless data.empty?
    end
    ```

=== "curl"

    ```bash
    # Reads Server-Sent Events from standard input, prints the content of each
    # chunk event as it arrives, and returns non-zero if the stream reports an
    # error, holds an event that is not valid JSON, or ends without a done
    # event. An event is one or more "data:" lines, which are joined with
    # newlines, followed by a blank line. The loop also handles a final line
    # that has no newline.
    read_events() {
        local line data="" have_data=false kind chunks=0 error="" other=""
        local done=false
    
        # Handles the event that has been collected. It sets the variables of
        # read_events, because a bash function can change its caller's locals.
        # The explicit checks matter, because set -e does not apply inside a
        # function that runs on the left of ||.
        handle_event() {
            local content
            $have_data || return 0
            kind="$(jq -r '.type' <<<"$data")" || {
                echo "The stream sent an event that is not valid JSON: $data" >&2
                return 1
            }
            case "$kind" in
                chunk)
                    # The last chunk has no content. A command substitution
                    # strips trailing newlines, which would run paragraphs
                    # together, so jq -j appends an x after the content and
                    # the next line removes it again.
                    content="$(jq -j '(.content // "") + "x"' <<<"$data")" ||
                        return 1
                    content="${content%x}"
                    if [[ -n "$content" ]]; then
                        printf '%s' "$content"
                        chunks=$((chunks + 1))
                    fi
                    ;;
                error)
                    error="$(jq -r '.error // "unknown error"' <<<"$data")" ||
                        return 1
                    ;;
                done) done=true ;;
            esac
            data=""
            have_data=false
        }
    
        while IFS= read -r line || [[ -n "$line" ]]; do
            line="${line%$'\r'}"
            if [[ -z "$line" ]]; then
                # A blank line ends the event.
                handle_event || return 1
            elif [[ "$line" == data:* ]]; then
                line="${line#data:}"
                if $have_data; then data+=$'\n'; fi
                data+="${line# }"
                have_data=true
            elif [[ "$line" != :* ]]; then
                # Comment lines start with a colon. Anything else is not an
                # event, such as the JSON body of an HTTP error, so keep it for
                # the error message.
                other+="$line"
            fi
        done
        # The stream may end without a blank line after the last event.
        handle_event || return 1
        echo
    
        # The server sends a done event after an error event, so keep reading
        # until the stream ends before reporting the error.
        if [[ -n "$error" ]]; then
            echo "The stream reported an error: $error" >&2
            return 1
        fi
        if [[ "$done" != true ]]; then
            echo "The stream ended before the done event${other:+: $other}" >&2
            return 1
        fi
        echo "Chunks received: $chunks"
    }
    ```

## Handling the Events

The HTTP status of a streaming reply is always 200, because the server
commits to it before it starts to look for documents or to call the language
model. A request that the server rejects outright, such as one for a
pipeline that does not exist, still gets an error status and an ordinary JSON
body, so each program checks the status first. After the stream starts, a
failure arrives as an `error` event followed by a `done` event.

Each program therefore prints the content of every `chunk` event as it
arrives, remembers the message from an `error` event, and keeps reading until
the stream ends. The last `chunk` event may carry no content, so the programs
skip empty chunks. After the stream ends, a program reports the error from an
`error` event, or the absence of a `done` event, and exits with a non-zero
status. The following tabs show how each program sends the request and handles
the events; the curl tab shows only the request, because the script reads the
events with the parser in the previous step and the main part in the next:

=== "Python"

    ```python
    class RagError(Exception):
        """Raised when the RAG Server rejects a request or the stream fails."""
    
    
    def error_text(response: httpx.Response) -> str:
        """Describes an error response, which carries a JSON body of the form
        {"error": {"code": "...", "message": "..."}}."""
        try:
            error = response.json()["error"]
            return f"{error['code']}: {error['message']}"
        except (ValueError, KeyError, TypeError):
            return response.text[:200] or response.reason_phrase
    
    
    def stream_answer(client: httpx.Client, question: str) -> int:
        """Prints the answer as it arrives, and returns the number of chunks."""
        chunks = 0
        error = None
        done = False
    
        with client.stream(
            "POST",
            f"/v1/pipelines/{quote(PIPELINE, safe='')}",
            json={"query": question, "stream": True},
        ) as response:
            # A request the server rejects gets an ordinary error status. Once
            # streaming starts the status is always 200, so later failures
            # arrive as events instead.
            if response.is_error:
                response.read()
                raise RagError(f"HTTP {response.status_code}, {error_text(response)}")
    
            for event in read_events(response.iter_lines()):
                kind = event.get("type")
                if kind == "chunk":
                    # The last chunk has no content, so use get().
                    content = event.get("content", "")
                    if content:
                        print(content, end="", flush=True)
                        chunks += 1
                elif kind == "error":
                    error = event.get("error") or "unknown error"
                elif kind == "done":
                    done = True
    
        print()
        # The server sends a done event after an error event, so keep reading
        # until the stream ends before reporting the error.
        if error:
            raise RagError(f"The stream reported an error: {error}")
        if not done:
            raise RagError("The stream ended before the done event")
        return chunks
    ```

=== "TypeScript"

    ```typescript
    // Describes an error response, which carries a JSON body of the form
    // {"error": {"code": "...", "message": "..."}}.
    async function errorText(response: Response): Promise<string> {
      const text = await response.text();
      try {
        const { error } = JSON.parse(text);
        return `${error.code}: ${error.message}`;
      } catch {
        return text.slice(0, 200) || response.statusText;
      }
    }
    
    // Prints the answer as it arrives, and returns the number of chunks.
    async function streamAnswer(question: string): Promise<number> {
      const response = await fetch(
        `${baseUrl}/v1/pipelines/${encodeURIComponent(pipeline)}`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ query: question, stream: true }),
          signal: AbortSignal.timeout(timeoutMs),
        },
      );
    
      // A request the server rejects gets an ordinary error status. Once
      // streaming starts the status is always 200, so later failures arrive
      // as events instead.
      if (!response.ok) {
        throw new Error(`HTTP ${response.status}, ${await errorText(response)}`);
      }
      if (!response.body) {
        throw new Error("The response has no body");
      }
    
      let chunks = 0;
      let error: string | undefined;
      let done = false;
    
      for await (const event of readEvents(response.body)) {
        if (event.type === "chunk") {
          // The last chunk has no content.
          if (event.content) {
            process.stdout.write(event.content);
            chunks++;
          }
        } else if (event.type === "error") {
          error = event.error || "unknown error";
        } else if (event.type === "done") {
          done = true;
        }
      }
    
      console.log();
      // The server sends a done event after an error event, so keep reading
      // until the stream ends before reporting the error.
      if (error) {
        throw new Error(`The stream reported an error: ${error}`);
      }
      if (!done) {
        throw new Error("The stream ended before the done event");
      }
      return chunks;
    }
    ```

=== "Java"

    ```java
    /** Thrown when the RAG Server rejects a request or the stream fails. */
    static class RagException extends Exception {
        RagException(String message) {
            super(message);
        }
    }
    
    /** What the stream has reported so far. */
    static class StreamState {
        int chunks = 0;
        String error = null;
        boolean done = false;
    }
    
    /**
     * Describes an error response, which carries a JSON body of the form
     * {"error": {"code": "...", "message": "..."}}.
     */
    static String errorText(String body) {
        try {
            JsonNode error = MAPPER.readTree(body).path("error");
            if (error.path("code").isString()) {
                return error.path("code").stringValue() + ": "
                        + error.path("message").asString();
            }
        } catch (JacksonException e) {
            // The body is not JSON, so show it as it is.
        }
        String text = body.strip();
        return text.length() > 200 ? text.substring(0, 200) : text;
    }
    
    /**
     * Returns the URL of a pipeline. URLEncoder escapes any character that
     * is not safe in a URL, but it writes a space as + for an HTML form,
     * so the + becomes %20 for use in a URL path.
     */
    static URI pipelineUri(String pipeline) {
        String name = URLEncoder.encode(pipeline, StandardCharsets.UTF_8)
                .replace("+", "%20");
        return URI.create(BASE_URL + "/v1/pipelines/" + name);
    }
    
    // A daemon thread does not keep the program running after main()
    // returns.
    static final ScheduledExecutorService WATCHDOG =
            Executors.newSingleThreadScheduledExecutor(task -> {
                Thread thread = new Thread(task);
                thread.setDaemon(true);
                return thread;
            });
    
    /** A read from the response body, such as of a line or of some bytes. */
    interface BodyRead<T> {
        T read() throws IOException;
    }
    
    /** Reads a line, giving up if none arrives within TIMEOUT. */
    static String readLineWithin(BufferedReader reader, InputStream body)
            throws IOException {
        return readWithin(reader::readLine, body);
    }
    
    /**
     * Runs a read of the body, giving up if it does not finish within
     * TIMEOUT. The request's timeout stops applying once the headers
     * arrive, so a server that stops sending part of the way through would
     * otherwise leave the read waiting for ever. Closing the stream from
     * another thread ends a read that is waiting for data.
     */
    static <T> T readWithin(BodyRead<T> read, InputStream body)
            throws IOException {
        // The flag is set before the stream is closed, so the read that
        // fails as a result can tell that it timed out.
        AtomicBoolean timedOut = new AtomicBoolean(false);
        ScheduledFuture<?> timer = WATCHDOG.schedule(() -> {
            timedOut.set(true);
            try {
                body.close();
            } catch (IOException e) {
                // The stream is being abandoned, so there is nothing to do.
            }
        }, TIMEOUT.toMillis(), TimeUnit.MILLISECONDS);
        T result;
        try {
            result = read.read();
        } catch (IOException e) {
            if (!timedOut.get()) {
                throw e;
            }
            result = null;
        } finally {
            timer.cancel(false);
        }
        if (timedOut.get()) {
            throw new HttpTimeoutException("No data from the server for "
                    + TIMEOUT.toSeconds() + " seconds");
        }
        return result;
    }
    
    /** Prints the answer as it arrives, and returns the number of chunks. */
    static int streamAnswer(HttpClient client, String question)
            throws IOException, InterruptedException, RagException {
        String payload = MAPPER.writeValueAsString(MAPPER.createObjectNode()
                .put("query", question)
                .put("stream", true));
        HttpRequest request = HttpRequest.newBuilder(pipelineUri(PIPELINE))
                .timeout(TIMEOUT)
                .header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString(payload))
                .build();
        // ofInputStream() returns as soon as the headers arrive, and the
        // body is read from the stream as the server sends it. The
        // request's timeout covers only the wait for the headers.
        HttpResponse<InputStream> response =
                client.send(request, HttpResponse.BodyHandlers.ofInputStream());
    
        StreamState state = new StreamState();
        // try-with-resources closes the stream, and with it the connection,
        // whether or not an error occurred.
        try (BufferedReader reader = new BufferedReader(
                new InputStreamReader(response.body(), StandardCharsets.UTF_8))) {
            // A request the server rejects gets an ordinary error status.
            // Once streaming starts the status is always 200, so later
            // failures arrive as events instead.
            if (response.statusCode() != 200) {
                // Bound this read as well, in case the server stalls.
                byte[] bytes = readWithin(
                        () -> response.body().readNBytes(4096), response.body());
                String body = new String(bytes, StandardCharsets.UTF_8);
                throw new RagException("HTTP " + response.statusCode() + ", "
                        + errorText(body));
            }
    
            readEvents(() -> readLineWithin(reader, response.body()), event -> {
                switch (event.path("type").asString()) {
                    case "chunk" -> {
                        // The last chunk has no content.
                        String content = event.path("content").asString("");
                        if (!content.isEmpty()) {
                            System.out.print(content);
                            System.out.flush();
                            state.chunks++;
                        }
                    }
                    case "error" -> {
                        String error = event.path("error").asString("");
                        state.error = error.isEmpty() ? "unknown error" : error;
                    }
                    case "done" -> state.done = true;
                    default -> {
                        // Other event types are ignored.
                    }
                }
            });
        }
    
        System.out.println();
        // The server sends a done event after an error event, so keep
        // reading until the stream ends before reporting the error.
        if (state.error != null) {
            throw new RagException("The stream reported an error: " + state.error);
        }
        if (!state.done) {
            throw new RagException("The stream ended before the done event");
        }
        return state.chunks;
    }
    ```

=== "C#"

    ```csharp
    // Describes an error response, which carries a JSON body of the form
    // {"error": {"code": "...", "message": "..."}}.
    static string ErrorText(string body)
    {
        try
        {
            if (JsonNode.Parse(body)?["error"] is JsonObject error &&
                error["code"] is JsonValue codeNode &&
                codeNode.TryGetValue(out string? code))
            {
                return $"{code}: {error["message"]}";
            }
        }
        catch (JsonException)
        {
            // The body is not JSON, so show it as it is.
        }
        var text = body.Trim();
        return text.Length > 200 ? text[..200] : text;
    }
    
    // Prints the answer as it arrives, and returns the number of chunks.
    static async Task<int> StreamAnswerAsync(HttpClient client, string question)
    {
        var url = $"{BaseUrl()}/v1/pipelines/{Uri.EscapeDataString(Pipeline())}";
        using var request = new HttpRequestMessage(HttpMethod.Post, url)
        {
            Content = JsonContent.Create(new { query = question, stream = true }),
        };
        // ResponseHeadersRead returns as soon as the headers arrive, rather
        // than after the whole body, so the body can be read as the server
        // sends it.
        using var response = await client.SendAsync(
            request, HttpCompletionOption.ResponseHeadersRead);
    
        // A request the server rejects gets an ordinary error status. Once
        // streaming starts the status is always 200, so later failures arrive
        // as events instead.
        if (!response.IsSuccessStatusCode)
        {
            // Bound this read as well, in case the server stalls.
            using var timeout = new CancellationTokenSource(
                TimeSpan.FromSeconds(TimeoutSeconds));
            string body;
            try
            {
                body = await response.Content.ReadAsStringAsync(timeout.Token);
            }
            catch (OperationCanceledException) when (timeout.IsCancellationRequested)
            {
                throw new TimeoutException(
                    $"No data from the server for {TimeoutSeconds} seconds");
            }
            throw new RagException(
                $"HTTP {(int)response.StatusCode}, {ErrorText(body)}");
        }
    
        var chunks = 0;
        string? error = null;
        var done = false;
    
        using var reader = new StreamReader(await response.Content.ReadAsStreamAsync());
        await foreach (var ev in ReadEventsAsync(reader))
        {
            // Anything other than a JSON object is not an event this program
            // knows, so skip it.
            if (ev is not JsonObject obj)
            {
                continue;
            }
            switch (obj["type"]?.ToString())
            {
                case "chunk":
                    // The last chunk has no content.
                    var content = obj["content"]?.ToString();
                    if (!string.IsNullOrEmpty(content))
                    {
                        Console.Write(content);
                        chunks++;
                    }
                    break;
                case "error":
                    var message = obj["error"]?.ToString();
                    error = string.IsNullOrEmpty(message) ? "unknown error" : message;
                    break;
                case "done":
                    done = true;
                    break;
            }
        }
    
        Console.WriteLine();
        // The server sends a done event after an error event, so keep reading
        // until the stream ends before reporting the error.
        if (error is not null)
        {
            throw new RagException($"The stream reported an error: {error}");
        }
        if (!done)
        {
            throw new RagException("The stream ended before the done event");
        }
        return chunks;
    }
    ```

=== "Go"

    ```go
    // errorText describes an error response, which carries a JSON body of the
    // form {"error": {"code": "...", "message": "..."}}.
    func errorText(body []byte) string {
    	var e struct {
    		Error struct {
    			Code    string `json:"code"`
    			Message string `json:"message"`
    		} `json:"error"`
    	}
    	if json.Unmarshal(body, &e) == nil && e.Error.Code != "" {
    		return e.Error.Code + ": " + e.Error.Message
    	}
    	return strings.TrimSpace(string(body))
    }
    
    // streamAnswer prints the answer as it arrives, and returns the number of
    // chunks.
    func streamAnswer(client *http.Client, question string) (int, error) {
    	payload, err := json.Marshal(map[string]any{"query": question, "stream": true})
    	if err != nil {
    		return 0, err
    	}
    
    	endpoint := baseURL + "/v1/pipelines/" + url.PathEscape(pipeline)
    	response, err := client.Post(endpoint, "application/json", bytes.NewReader(payload))
    	if err != nil {
    		return 0, err
    	}
    	defer response.Body.Close()
    
    	// A request the server rejects gets an ordinary error status. Once
    	// streaming starts the status is always 200, so later failures arrive
    	// as events instead.
    	if response.StatusCode != http.StatusOK {
    		body, _ := io.ReadAll(io.LimitReader(response.Body, 4096))
    		return 0, fmt.Errorf("HTTP %d, %s", response.StatusCode, errorText(body))
    	}
    
    	chunks := 0
    	streamError := ""
    	done := false
    
    	err = readEvents(response.Body, func(event streamEvent) {
    		switch event.Type {
    		case "chunk":
    			// The last chunk has no content.
    			if event.Content != "" {
    				fmt.Print(event.Content)
    				chunks++
    			}
    		case "error":
    			streamError = event.Error
    			if streamError == "" {
    				streamError = "unknown error"
    			}
    		case "done":
    			done = true
    		}
    	})
    	fmt.Println()
    	if err != nil {
    		return chunks, err
    	}
    
    	// The server sends a done event after an error event, so keep reading
    	// until the stream ends before reporting the error.
    	if streamError != "" {
    		return chunks, fmt.Errorf("the stream reported an error: %s", streamError)
    	}
    	if !done {
    		return chunks, errors.New("the stream ended before the done event")
    	}
    	return chunks, nil
    }
    
    ```

=== "Rust"

    ```rust
    /// Describes an error response, which carries a JSON body of the form
    /// {"error": {"code": "...", "message": "..."}}.
    fn error_text(body: &str) -> String {
        // A body that is not JSON becomes Null, and indexing Null (or any
        // missing field) gives Null again, which as_str() turns into None.
        let reply: Value = serde_json::from_str(body).unwrap_or(Value::Null);
        let error = &reply["error"];
        match (error["code"].as_str(), error["message"].as_str()) {
            (Some(code), message) => format!("{code}: {}", message.unwrap_or("")),
            _ => body.trim().chars().take(200).collect(),
        }
    }
    
    /// Returns the URL of a pipeline. push() escapes any character in the
    /// pipeline name that is not safe in a URL path.
    fn pipeline_url(name: &str) -> Result<Url, BoxError> {
        let mut url = Url::parse(&format!("{}/v1/pipelines/", base_url()))?;
        url.path_segments_mut()
            .map_err(|()| "RAG_SERVER_URL cannot be a base URL")?
            .pop_if_empty()
            .push(name);
        Ok(url)
    }
    
    /// Prints the answer as it arrives, and returns the number of chunks.
    fn stream_answer(client: &Client, question: &str) -> Result<u32, BoxError> {
        // send() returns as soon as the headers arrive, and the response can
        // then be read as the server sends the body.
        let response = client
            .post(pipeline_url(&pipeline())?)
            .json(&json!({ "query": question, "stream": true }))
            .send()?;
    
        // A request the server rejects gets an ordinary error status. Once
        // streaming starts the status is always 200, so later failures arrive
        // as events instead.
        let status = response.status();
        if !status.is_success() {
            let mut body = String::new();
            response.take(4096).read_to_string(&mut body)?;
            return Err(format!("HTTP {}, {}", status.as_u16(), error_text(&body)).into());
        }
    
        let mut chunks = 0;
        let mut error: Option<String> = None;
        let mut done = false;
        let mut stdout = io::stdout();
    
        read_events(BufReader::new(response), |event| {
            match event["type"].as_str() {
                Some("chunk") => {
                    // The last chunk has no content.
                    let content = event["content"].as_str().unwrap_or("");
                    if !content.is_empty() {
                        // Rust buffers standard output by line, so flush it to
                        // show each chunk at once.
                        print!("{content}");
                        let _ = stdout.flush();
                        chunks += 1;
                    }
                }
                Some("error") => {
                    let message = event["error"].as_str().unwrap_or("");
                    error = Some(if message.is_empty() { "unknown error" } else { message }.to_string());
                }
                Some("done") => done = true,
                _ => {}
            }
        })?;
    
        println!();
        // The server sends a done event after an error event, so keep reading
        // until the stream ends before reporting the error.
        if let Some(error) = error {
            return Err(format!("The stream reported an error: {error}").into());
        }
        if !done {
            return Err("The stream ended before the done event".into());
        }
        Ok(chunks)
    }
    ```

=== "Ruby"

    ```ruby
    # Raised when the RAG Server rejects a request or the stream fails.
    class RagError < StandardError; end
    
    # Describes an error response, which carries a JSON body of the form
    # {"error": {"code": "...", "message": "..."}}.
    def error_text(body)
      error = JSON.parse(body.to_s)["error"]
      return "#{error["code"]}: #{error["message"]}" if error.is_a?(Hash) && error["code"].is_a?(String)
    
      body.to_s.strip[0, 200]
    rescue JSON::ParserError, NoMethodError, TypeError
      body.to_s.strip[0, 200]
    end
    
    # Prints the answer as it arrives, and returns the number of chunks.
    def stream_answer(http, question)
      uri = URI("#{BASE_URL}/v1/pipelines/#{URI.encode_uri_component(PIPELINE)}")
      request = Net::HTTP::Post.new(uri, "Content-Type" => "application/json")
      request.body = JSON.generate({ query: question, stream: true })
    
      chunks = 0
      error = nil
      done = false
    
      # Given a block, request hands over the response before reading its
      # body, which the block then reads as the server sends it.
      http.request(request) do |response|
        # A request the server rejects gets an ordinary error status. Once
        # streaming starts the status is always 200, so later failures arrive
        # as events instead.
        unless response.is_a?(Net::HTTPSuccess)
          raise RagError, "HTTP #{response.code}, #{error_text(response.read_body)}"
        end
    
        read_events(response) do |event|
          # Anything other than a JSON object is not an event this program
          # knows, so skip it.
          next unless event.is_a?(Hash)
    
          case event["type"]
          when "chunk"
            # The last chunk has no content.
            content = event["content"].to_s
            unless content.empty?
              # Ruby buffers standard output when it is not a terminal, so
              # flush it to show each chunk at once.
              print content
              $stdout.flush
              chunks += 1
            end
          when "error"
            message = event["error"].to_s
            error = message.empty? ? "unknown error" : message
          when "done"
            done = true
          end
        end
      end
    
      puts
      # The server sends a done event after an error event, so keep reading
      # until the stream ends before reporting the error.
      raise RagError, "The stream reported an error: #{error}" if error
      raise RagError, "The stream ended before the done event" unless done
    
      chunks
    end
    ```

=== "curl"

    ```bash
    # Sends the question with streaming switched on, and prints the Server-Sent
    # Events as they arrive. --no-buffer stops curl from holding the output
    # back, and --fail-with-body makes curl exit non-zero on an HTTP error
    # status while still printing the body, which carries the explanation.
    request_stream() {
        jq -n --arg query "$1" '{query: $query, stream: true}' |
            curl --silent --show-error --fail-with-body --no-buffer \
                --max-time "$TIMEOUT_SECONDS" \
                --header 'Content-Type: application/json' \
                --data-binary @- \
                "$RAG_SERVER_URL/v1/pipelines/$(escape "$RAG_PIPELINE")"
    }
    ```

## Handling Errors

The main part of each program prints the question, calls the function from the
previous step, and prints the number of chunks. The program reports any failure
on `stderr`, whether the server was unreachable, replied with an error status,
or sent an `error` event, and then exits with a non-zero status. The Python
program catches `httpx.HTTPError`, the base class for connection failures and
timeouts, as well as its own error class; the TypeScript program catches any
rejected promise; the Java program catches `IOException`, which covers
connection failures and timeouts, including the `HttpTimeoutException` it
throws when the stream stops part of the way through, along with its own
exception class and Jackson's `JacksonException` for an event that is not valid
JSON; the C# program uses an exception filter that accepts
`HttpRequestException`, `TaskCanceledException` (for a timeout while waiting
for the response), `TimeoutException` (which it throws when the stream stops
part of the way through), `IOException`, `JsonException` and its own exception
class; the Go and Rust programs return each error from a `run()`
function to `main()`, and the Rust program also prints the chain of underlying
causes; the Ruby program rescues the standard library's network errors,
`JSON::ParserError` and its own error class; and the curl script relies on `set
-o pipefail`, so a failure of `curl` or of the event reader fails the whole
pipeline. The following tabs show the main part of each program:

=== "Python"

    ```python
    def main() -> int:
        print(f"Question: {QUESTION}")
        print("Answer:")
        try:
            with httpx.Client(base_url=BASE_URL, timeout=TIMEOUT_SECONDS) as client:
                chunks = stream_answer(client, QUESTION)
        # json.JSONDecodeError is a ValueError, raised for an event whose data
        # is not valid JSON.
        except (httpx.HTTPError, RagError, ValueError) as e:
            print(f"RAG Server error: {e}", file=sys.stderr)
            return 1
    
        print(f"Chunks received: {chunks}")
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
      console.log(`Question: ${question}`);
      console.log("Answer:");
      try {
        const chunks = await streamAnswer(question);
        console.log(`Chunks received: ${chunks}`);
        return 0;
      } catch (err) {
        console.error(`RAG Server error: ${describe(err)}`);
        return 1;
      }
    }
    
    process.exitCode = await main();
    ```

=== "Java"

    ```java
    public static void main(String[] args) {
        System.out.println("Question: " + QUESTION);
        System.out.println("Answer:");
        HttpClient client = HttpClient.newHttpClient();
        try {
            int chunks = streamAnswer(client, QUESTION);
            System.out.println("Chunks received: " + chunks);
        // IOException covers failures to reach the server, such as a
        // refused connection, and timeouts, including a stream that stops
        // part of the way through. The message of a refused
        // connection can be empty, so print the exception itself, which
        // includes its type.
        } catch (IOException | InterruptedException e) {
            System.err.println("RAG Server error: " + e);
            System.exit(1);
        // JacksonException is thrown for an event whose data is not valid
        // JSON.
        } catch (RagException | JacksonException e) {
            System.err.println("RAG Server error: " + e.getMessage());
            System.exit(1);
        }
    }
    ```

=== "C#"

    ```csharp
    Console.WriteLine($"Question: {Question}");
    Console.WriteLine("Answer:");
    try
    {
        // using disposes of the client, and closes its connections, when the
        // block exits, whether or not an error occurred.
        using var client = new HttpClient
        {
            Timeout = TimeSpan.FromSeconds(TimeoutSeconds),
        };
        var chunks = await StreamAnswerAsync(client, Question);
        Console.WriteLine($"Chunks received: {chunks}");
    }
    // HttpRequestException covers failures to reach the server, such as a
    // refused connection, TaskCanceledException covers a timeout while waiting
    // for the response, TimeoutException covers a stream that stops part of
    // the way through, IOException covers a stream that fails part of the way
    // through, and JsonException covers an event whose data is not valid JSON.
    catch (Exception e) when (e is HttpRequestException or TaskCanceledException
        or TimeoutException or IOException or JsonException or RagException)
    {
        Console.Error.WriteLine($"RAG Server error: {e.Message}");
        return 1;
    }
    
    return 0;
    
    // C# requires type declarations to follow the top-level statements, so
    // the exception that the program throws for an error reply is declared
    // here, at the end.
    class RagException(string message) : Exception(message);
    ```

=== "Go"

    ```go
    // run asks the question and prints the answer as it streams in, returning
    // any error to the caller.
    func run() error {
    	client := &http.Client{Timeout: timeout}
    
    	fmt.Printf("Question: %s\n", question)
    	fmt.Println("Answer:")
    	chunks, err := streamAnswer(client, question)
    	if err != nil {
    		return err
    	}
    
    	fmt.Printf("Chunks received: %d\n", chunks)
    	return nil
    }
    
    // main reports any error returned by run() and exits with a non-zero
    // status.
    func main() {
    	if err := run(); err != nil {
    		fmt.Fprintf(os.Stderr, "RAG Server error: %v\n", err)
    		os.Exit(1)
    	}
    }
    
    ```

=== "Rust"

    ```rust
    /// Asks the question and prints the answer as it streams in. The ?
    /// operator returns any error to the caller.
    fn run() -> Result<(), BoxError> {
        let client = Client::builder().timeout(TIMEOUT).build()?;
    
        println!("Question: {QUESTION}");
        println!("Answer:");
        let chunks = stream_answer(&client, QUESTION)?;
        println!("Chunks received: {chunks}");
        Ok(())
    }
    
    /// Reports any error returned by run() and exits with a failure status.
    /// The top-level error is often generic ("error sending request"), so the
    /// chain of underlying causes is printed too.
    fn main() -> ExitCode {
        match run() {
            Ok(()) => ExitCode::SUCCESS,
            Err(e) => {
                eprintln!("RAG Server error: {e}");
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
    puts "Question: #{QUESTION}"
    puts "Answer:"
    begin
      uri = URI(BASE_URL)
      # start opens a connection, and closes it when the block exits, whether
      # or not an error occurred.
      chunks = Net::HTTP.start(
        uri.host, uri.port,
        use_ssl: uri.scheme == "https",
        open_timeout: TIMEOUT_SECONDS, read_timeout: TIMEOUT_SECONDS
      ) { |http| stream_answer(http, QUESTION) }
      puts "Chunks received: #{chunks}"
    # SystemCallError covers a refused connection, Timeout::Error covers the
    # connection and read timeouts, SocketError covers an unknown host, and
    # JSON::ParserError covers an event whose data is not valid JSON.
    rescue RagError, SystemCallError, Timeout::Error, SocketError, IOError,
           JSON::ParserError => e
      warn "RAG Server error: #{e.message}"
      exit 1
    end
    ```

=== "curl"

    ```bash
    main() {
        echo "Question: $QUESTION"
        echo "Answer:"
        # With pipefail, the pipeline fails if curl fails or the stream
        # reports an error.
        request_stream "$QUESTION" | read_events || {
            echo "RAG Server error: the request failed" >&2
            exit 1
        }
    }
    
    main
    ```

## Running the Example

The complete project for each language is available in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/rag_server/stream_answer).
Set the environment variables for your RAG Server, and then run the command
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
    Streaming an answer from the pgEdge RAG Server, using httpx.
    
    These examples are for pgEdge RAG Server 2.0.0.
    
    Copyright (c) 2026, pgEdge, Inc.
    This code is released under the PostgreSQL License.
    """
    
    import json
    import os
    import sys
    from collections.abc import Iterable, Iterator
    from urllib.parse import quote
    
    import httpx
    
    
    # The or operator treats an empty variable as unset.
    BASE_URL = (os.environ.get("RAG_SERVER_URL") or "http://localhost:8080").rstrip("/")
    PIPELINE = os.environ.get("RAG_PIPELINE") or "cookbook"
    
    QUESTION = "How long does the Acme Widget 2.0 take to charge?"
    
    # The timeout applies to each wait for data rather than to the whole
    # stream, but the server may wait for the language model to begin, and a
    # small model on a modest machine can take a while, so allow plenty of
    # time.
    TIMEOUT_SECONDS = 300.0
    
    
    def read_events(lines: Iterable[str]) -> Iterator[dict]:
        """Parses Server-Sent Events, and yields the JSON object that the data
        of each event holds.
    
        An event is one or more "data:" lines followed by a blank line. The
        stream may end without the final blank line, so the last event is sent
        when the lines run out as well.
        """
        data: list[str] = []
        for line in lines:
            if line == "":
                if data:
                    yield json.loads("\n".join(data))
                    data = []
            elif line.startswith("data:"):
                # A single space after the colon is not part of the data.
                data.append(line[len("data:"):].removeprefix(" "))
            # Comment lines (which start with a colon) and other fields are
            # ignored.
        if data:
            yield json.loads("\n".join(data))
    
    
    class RagError(Exception):
        """Raised when the RAG Server rejects a request or the stream fails."""
    
    
    def error_text(response: httpx.Response) -> str:
        """Describes an error response, which carries a JSON body of the form
        {"error": {"code": "...", "message": "..."}}."""
        try:
            error = response.json()["error"]
            return f"{error['code']}: {error['message']}"
        except (ValueError, KeyError, TypeError):
            return response.text[:200] or response.reason_phrase
    
    
    def stream_answer(client: httpx.Client, question: str) -> int:
        """Prints the answer as it arrives, and returns the number of chunks."""
        chunks = 0
        error = None
        done = False
    
        with client.stream(
            "POST",
            f"/v1/pipelines/{quote(PIPELINE, safe='')}",
            json={"query": question, "stream": True},
        ) as response:
            # A request the server rejects gets an ordinary error status. Once
            # streaming starts the status is always 200, so later failures
            # arrive as events instead.
            if response.is_error:
                response.read()
                raise RagError(f"HTTP {response.status_code}, {error_text(response)}")
    
            for event in read_events(response.iter_lines()):
                kind = event.get("type")
                if kind == "chunk":
                    # The last chunk has no content, so use get().
                    content = event.get("content", "")
                    if content:
                        print(content, end="", flush=True)
                        chunks += 1
                elif kind == "error":
                    error = event.get("error") or "unknown error"
                elif kind == "done":
                    done = True
    
        print()
        # The server sends a done event after an error event, so keep reading
        # until the stream ends before reporting the error.
        if error:
            raise RagError(f"The stream reported an error: {error}")
        if not done:
            raise RagError("The stream ended before the done event")
        return chunks
    
    
    def main() -> int:
        print(f"Question: {QUESTION}")
        print("Answer:")
        try:
            with httpx.Client(base_url=BASE_URL, timeout=TIMEOUT_SECONDS) as client:
                chunks = stream_answer(client, QUESTION)
        # json.JSONDecodeError is a ValueError, raised for an event whose data
        # is not valid JSON.
        except (httpx.HTTPError, RagError, ValueError) as e:
            print(f"RAG Server error: {e}", file=sys.stderr)
            return 1
    
        print(f"Chunks received: {chunks}")
        return 0
    
    
    if __name__ == "__main__":
        sys.exit(main())
    
    ```

=== "TypeScript"

    ```typescript
    /*
     * Ellie's Postgres Cookbook
     * Streaming an answer from the pgEdge RAG Server, using the built-in fetch.
     *
     * These examples are for pgEdge RAG Server 2.0.0.
     *
     * Copyright (c) 2026, pgEdge, Inc.
     * This code is released under the PostgreSQL License.
     */
    
    // Node.js provides fetch, AbortSignal, and TextDecoder as globals, so this
    // program imports nothing.
    
    // The || operator, unlike ??, also treats an empty variable as unset.
    const baseUrl = (process.env.RAG_SERVER_URL || "http://localhost:8080").replace(/\/+$/, "");
    const pipeline = process.env.RAG_PIPELINE || "cookbook";
    
    const question = "How long does the Acme Widget 2.0 take to charge?";
    
    // The server may wait for the language model before the first chunk
    // arrives, and a small model on a modest machine can take a while, so
    // allow plenty of time for the whole stream.
    const timeoutMs = 300_000;
    
    interface StreamEvent {
      type: string;
      content?: string;
      error?: string;
    }
    
    // Yields the lines of a streamed response body. A line can be split
    // across two reads, so keep the unfinished part until the next read.
    async function* readLines(body: ReadableStream<Uint8Array>): AsyncGenerator<string> {
      const reader = body.getReader();
      const decoder = new TextDecoder();
      let buffer = "";
      for (;;) {
        const { done, value } = await reader.read();
        // The stream option keeps a multi-byte character that is split across
        // two reads intact.
        buffer += decoder.decode(value, { stream: !done });
        let newline: number;
        while ((newline = buffer.indexOf("\n")) >= 0) {
          yield buffer.slice(0, newline).replace(/\r$/, "");
          buffer = buffer.slice(newline + 1);
        }
        if (done) break;
      }
      if (buffer) yield buffer;
    }
    
    // Parses Server-Sent Events, and yields the JSON object that the data of
    // each event holds. An event is one or more "data:" lines followed by a
    // blank line. The stream may end without the final blank line, so the last
    // event is sent when the lines run out as well.
    async function* readEvents(body: ReadableStream<Uint8Array>): AsyncGenerator<StreamEvent> {
      let data: string[] = [];
      for await (const line of readLines(body)) {
        if (line === "") {
          if (data.length > 0) {
            yield JSON.parse(data.join("\n")) as StreamEvent;
            data = [];
          }
        } else if (line.startsWith("data:")) {
          // A single space after the colon is not part of the data.
          data.push(line.slice("data:".length).replace(/^ /, ""));
        }
        // Comment lines (which start with a colon) and other fields are
        // ignored.
      }
      if (data.length > 0) {
        yield JSON.parse(data.join("\n")) as StreamEvent;
      }
    }
    
    // Describes an error response, which carries a JSON body of the form
    // {"error": {"code": "...", "message": "..."}}.
    async function errorText(response: Response): Promise<string> {
      const text = await response.text();
      try {
        const { error } = JSON.parse(text);
        return `${error.code}: ${error.message}`;
      } catch {
        return text.slice(0, 200) || response.statusText;
      }
    }
    
    // Prints the answer as it arrives, and returns the number of chunks.
    async function streamAnswer(question: string): Promise<number> {
      const response = await fetch(
        `${baseUrl}/v1/pipelines/${encodeURIComponent(pipeline)}`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ query: question, stream: true }),
          signal: AbortSignal.timeout(timeoutMs),
        },
      );
    
      // A request the server rejects gets an ordinary error status. Once
      // streaming starts the status is always 200, so later failures arrive
      // as events instead.
      if (!response.ok) {
        throw new Error(`HTTP ${response.status}, ${await errorText(response)}`);
      }
      if (!response.body) {
        throw new Error("The response has no body");
      }
    
      let chunks = 0;
      let error: string | undefined;
      let done = false;
    
      for await (const event of readEvents(response.body)) {
        if (event.type === "chunk") {
          // The last chunk has no content.
          if (event.content) {
            process.stdout.write(event.content);
            chunks++;
          }
        } else if (event.type === "error") {
          error = event.error || "unknown error";
        } else if (event.type === "done") {
          done = true;
        }
      }
    
      console.log();
      // The server sends a done event after an error event, so keep reading
      // until the stream ends before reporting the error.
      if (error) {
        throw new Error(`The stream reported an error: ${error}`);
      }
      if (!done) {
        throw new Error("The stream ended before the done event");
      }
      return chunks;
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
      console.log(`Question: ${question}`);
      console.log("Answer:");
      try {
        const chunks = await streamAnswer(question);
        console.log(`Chunks received: ${chunks}`);
        return 0;
      } catch (err) {
        console.error(`RAG Server error: ${describe(err)}`);
        return 1;
      }
    }
    
    process.exitCode = await main();
    
    ```

=== "Java"

    ```java
    /*
     * Ellie's Postgres Cookbook
     * Streaming an answer from the pgEdge RAG Server, using java.net.http and
     * Jackson.
     *
     * These examples are for pgEdge RAG Server 2.0.0.
     *
     * Copyright (c) 2026, pgEdge, Inc.
     * This code is released under the PostgreSQL License.
     */
    
    import java.io.BufferedReader;
    import java.io.IOException;
    import java.io.InputStream;
    import java.io.InputStreamReader;
    import java.net.URI;
    import java.net.URLEncoder;
    import java.net.http.HttpClient;
    import java.net.http.HttpRequest;
    import java.net.http.HttpResponse;
    import java.net.http.HttpTimeoutException;
    import java.nio.charset.StandardCharsets;
    import java.time.Duration;
    import java.util.ArrayList;
    import java.util.List;
    import java.util.concurrent.Executors;
    import java.util.concurrent.ScheduledExecutorService;
    import java.util.concurrent.ScheduledFuture;
    import java.util.concurrent.TimeUnit;
    import java.util.concurrent.atomic.AtomicBoolean;
    import java.util.function.Consumer;
    
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
                envOr("RAG_SERVER_URL", "http://localhost:8080")
                        .replaceAll("/+$", "");
        static final String PIPELINE = envOr("RAG_PIPELINE", "cookbook");
    
        static final String QUESTION =
                "How long does the Acme Widget 2.0 take to charge?";
    
        // The program applies the timeout to the wait for the response and to
        // each wait for a line of the stream, rather than to the whole stream,
        // but the server may wait for the language model to begin, and a small
        // model on a modest machine can take a while, so allow plenty of time.
        static final Duration TIMEOUT = Duration.ofSeconds(300);
    
        // A mapper is safe to share, so the program creates only one.
        static final ObjectMapper MAPPER = JsonMapper.builder().build();
    
        /** Supplies the lines of a stream, returning null at the end. */
        interface LineSource {
            String readLine() throws IOException;
        }
    
        /**
         * Parses Server-Sent Events from a source of lines, and passes the JSON
         * object that the data of each event holds to handle, as each event
         * arrives.
         *
         * An event is one or more "data:" lines followed by a blank line. The
         * stream may end without the final blank line, so the last event is
         * sent when the lines run out as well. readTree() throws a
         * JacksonException for data that is not valid JSON.
         */
        static void readEvents(LineSource lines, Consumer<JsonNode> handle)
                throws IOException {
            List<String> data = new ArrayList<>();
            String line;
            while ((line = lines.readLine()) != null) {
                if (line.isEmpty()) {
                    if (!data.isEmpty()) {
                        handle.accept(MAPPER.readTree(String.join("\n", data)));
                        data.clear();
                    }
                } else if (line.startsWith("data:")) {
                    // A single space after the colon is not part of the data.
                    String value = line.substring("data:".length());
                    data.add(value.startsWith(" ") ? value.substring(1) : value);
                }
                // Comment lines (which start with a colon) and other fields are
                // ignored.
            }
            if (!data.isEmpty()) {
                handle.accept(MAPPER.readTree(String.join("\n", data)));
            }
        }
    
        /** Thrown when the RAG Server rejects a request or the stream fails. */
        static class RagException extends Exception {
            RagException(String message) {
                super(message);
            }
        }
    
        /** What the stream has reported so far. */
        static class StreamState {
            int chunks = 0;
            String error = null;
            boolean done = false;
        }
    
        /**
         * Describes an error response, which carries a JSON body of the form
         * {"error": {"code": "...", "message": "..."}}.
         */
        static String errorText(String body) {
            try {
                JsonNode error = MAPPER.readTree(body).path("error");
                if (error.path("code").isString()) {
                    return error.path("code").stringValue() + ": "
                            + error.path("message").asString();
                }
            } catch (JacksonException e) {
                // The body is not JSON, so show it as it is.
            }
            String text = body.strip();
            return text.length() > 200 ? text.substring(0, 200) : text;
        }
    
        /**
         * Returns the URL of a pipeline. URLEncoder escapes any character that
         * is not safe in a URL, but it writes a space as + for an HTML form,
         * so the + becomes %20 for use in a URL path.
         */
        static URI pipelineUri(String pipeline) {
            String name = URLEncoder.encode(pipeline, StandardCharsets.UTF_8)
                    .replace("+", "%20");
            return URI.create(BASE_URL + "/v1/pipelines/" + name);
        }
    
        // A daemon thread does not keep the program running after main()
        // returns.
        static final ScheduledExecutorService WATCHDOG =
                Executors.newSingleThreadScheduledExecutor(task -> {
                    Thread thread = new Thread(task);
                    thread.setDaemon(true);
                    return thread;
                });
    
        /** A read from the response body, such as of a line or of some bytes. */
        interface BodyRead<T> {
            T read() throws IOException;
        }
    
        /** Reads a line, giving up if none arrives within TIMEOUT. */
        static String readLineWithin(BufferedReader reader, InputStream body)
                throws IOException {
            return readWithin(reader::readLine, body);
        }
    
        /**
         * Runs a read of the body, giving up if it does not finish within
         * TIMEOUT. The request's timeout stops applying once the headers
         * arrive, so a server that stops sending part of the way through would
         * otherwise leave the read waiting for ever. Closing the stream from
         * another thread ends a read that is waiting for data.
         */
        static <T> T readWithin(BodyRead<T> read, InputStream body)
                throws IOException {
            // The flag is set before the stream is closed, so the read that
            // fails as a result can tell that it timed out.
            AtomicBoolean timedOut = new AtomicBoolean(false);
            ScheduledFuture<?> timer = WATCHDOG.schedule(() -> {
                timedOut.set(true);
                try {
                    body.close();
                } catch (IOException e) {
                    // The stream is being abandoned, so there is nothing to do.
                }
            }, TIMEOUT.toMillis(), TimeUnit.MILLISECONDS);
            T result;
            try {
                result = read.read();
            } catch (IOException e) {
                if (!timedOut.get()) {
                    throw e;
                }
                result = null;
            } finally {
                timer.cancel(false);
            }
            if (timedOut.get()) {
                throw new HttpTimeoutException("No data from the server for "
                        + TIMEOUT.toSeconds() + " seconds");
            }
            return result;
        }
    
        /** Prints the answer as it arrives, and returns the number of chunks. */
        static int streamAnswer(HttpClient client, String question)
                throws IOException, InterruptedException, RagException {
            String payload = MAPPER.writeValueAsString(MAPPER.createObjectNode()
                    .put("query", question)
                    .put("stream", true));
            HttpRequest request = HttpRequest.newBuilder(pipelineUri(PIPELINE))
                    .timeout(TIMEOUT)
                    .header("Content-Type", "application/json")
                    .POST(HttpRequest.BodyPublishers.ofString(payload))
                    .build();
            // ofInputStream() returns as soon as the headers arrive, and the
            // body is read from the stream as the server sends it. The
            // request's timeout covers only the wait for the headers.
            HttpResponse<InputStream> response =
                    client.send(request, HttpResponse.BodyHandlers.ofInputStream());
    
            StreamState state = new StreamState();
            // try-with-resources closes the stream, and with it the connection,
            // whether or not an error occurred.
            try (BufferedReader reader = new BufferedReader(
                    new InputStreamReader(response.body(), StandardCharsets.UTF_8))) {
                // A request the server rejects gets an ordinary error status.
                // Once streaming starts the status is always 200, so later
                // failures arrive as events instead.
                if (response.statusCode() != 200) {
                    // Bound this read as well, in case the server stalls.
                    byte[] bytes = readWithin(
                            () -> response.body().readNBytes(4096), response.body());
                    String body = new String(bytes, StandardCharsets.UTF_8);
                    throw new RagException("HTTP " + response.statusCode() + ", "
                            + errorText(body));
                }
    
                readEvents(() -> readLineWithin(reader, response.body()), event -> {
                    switch (event.path("type").asString()) {
                        case "chunk" -> {
                            // The last chunk has no content.
                            String content = event.path("content").asString("");
                            if (!content.isEmpty()) {
                                System.out.print(content);
                                System.out.flush();
                                state.chunks++;
                            }
                        }
                        case "error" -> {
                            String error = event.path("error").asString("");
                            state.error = error.isEmpty() ? "unknown error" : error;
                        }
                        case "done" -> state.done = true;
                        default -> {
                            // Other event types are ignored.
                        }
                    }
                });
            }
    
            System.out.println();
            // The server sends a done event after an error event, so keep
            // reading until the stream ends before reporting the error.
            if (state.error != null) {
                throw new RagException("The stream reported an error: " + state.error);
            }
            if (!state.done) {
                throw new RagException("The stream ended before the done event");
            }
            return state.chunks;
        }
    
        public static void main(String[] args) {
            System.out.println("Question: " + QUESTION);
            System.out.println("Answer:");
            HttpClient client = HttpClient.newHttpClient();
            try {
                int chunks = streamAnswer(client, QUESTION);
                System.out.println("Chunks received: " + chunks);
            // IOException covers failures to reach the server, such as a
            // refused connection, and timeouts, including a stream that stops
            // part of the way through. The message of a refused
            // connection can be empty, so print the exception itself, which
            // includes its type.
            } catch (IOException | InterruptedException e) {
                System.err.println("RAG Server error: " + e);
                System.exit(1);
            // JacksonException is thrown for an event whose data is not valid
            // JSON.
            } catch (RagException | JacksonException e) {
                System.err.println("RAG Server error: " + e.getMessage());
                System.exit(1);
            }
        }
    }
    
    ```

=== "C#"

    ```csharp
    /*
     * Ellie's Postgres Cookbook
     * Streaming an answer from the pgEdge RAG Server, using HttpClient and
     * System.Text.Json.
     *
     * These examples are for pgEdge RAG Server 2.0.0.
     *
     * Copyright (c) 2026, pgEdge, Inc.
     * This code is released under the PostgreSQL License.
     */
    
    using System.Net.Http.Json;
    using System.Text.Json;
    using System.Text.Json.Nodes;
    
    // Returns the value of an environment variable, or a fallback if the
    // variable is unset or empty.
    static string EnvOr(string name, string fallback) =>
        Environment.GetEnvironmentVariable(name) is { Length: > 0 } value
            ? value
            : fallback;
    
    static string BaseUrl() =>
        EnvOr("RAG_SERVER_URL", "http://localhost:8080").TrimEnd('/');
    static string Pipeline() => EnvOr("RAG_PIPELINE", "cookbook");
    
    const string Question = "How long does the Acme Widget 2.0 take to charge?";
    
    // The program applies the timeout to the wait for the response and to each
    // wait for a line of the stream, rather than to the whole stream, but the
    // server may wait for the language model to begin, and a small model on a
    // modest machine can take a while, so allow plenty of time.
    const int TimeoutSeconds = 300;
    
    // Parses Server-Sent Events from a reader, and yields the JSON that the
    // data of each event holds, as each event arrives.
    //
    // An event is one or more "data:" lines followed by a blank line. The
    // stream may end without the final blank line, so the last event is sent
    // when the lines run out as well. JsonNode.Parse throws a JsonException
    // for data that is not valid JSON.
    static async IAsyncEnumerable<JsonNode?> ReadEventsAsync(StreamReader reader)
    {
        var data = new List<string>();
        while (true)
        {
            // The client's timeout stops applying once the headers arrive, so a
            // server that stops sending part of the way through would otherwise
            // leave the read waiting for ever. The token cancels a read for
            // which no line arrives in time.
            using var timeout = new CancellationTokenSource(
                TimeSpan.FromSeconds(TimeoutSeconds));
            string? line;
            try
            {
                line = await reader.ReadLineAsync(timeout.Token);
            }
            catch (OperationCanceledException) when (timeout.IsCancellationRequested)
            {
                throw new TimeoutException(
                    $"No data from the server for {TimeoutSeconds} seconds");
            }
            if (line is null)
            {
                break;
            }
    
            if (line.Length == 0)
            {
                if (data.Count > 0)
                {
                    yield return JsonNode.Parse(string.Join("\n", data));
                    data.Clear();
                }
            }
            else if (line.StartsWith("data:", StringComparison.Ordinal))
            {
                // A single space after the colon is not part of the data.
                var value = line["data:".Length..];
                data.Add(value.StartsWith(' ') ? value[1..] : value);
            }
            // Comment lines (which start with a colon) and other fields are
            // ignored.
        }
        if (data.Count > 0)
        {
            yield return JsonNode.Parse(string.Join("\n", data));
        }
    }
    
    // Describes an error response, which carries a JSON body of the form
    // {"error": {"code": "...", "message": "..."}}.
    static string ErrorText(string body)
    {
        try
        {
            if (JsonNode.Parse(body)?["error"] is JsonObject error &&
                error["code"] is JsonValue codeNode &&
                codeNode.TryGetValue(out string? code))
            {
                return $"{code}: {error["message"]}";
            }
        }
        catch (JsonException)
        {
            // The body is not JSON, so show it as it is.
        }
        var text = body.Trim();
        return text.Length > 200 ? text[..200] : text;
    }
    
    // Prints the answer as it arrives, and returns the number of chunks.
    static async Task<int> StreamAnswerAsync(HttpClient client, string question)
    {
        var url = $"{BaseUrl()}/v1/pipelines/{Uri.EscapeDataString(Pipeline())}";
        using var request = new HttpRequestMessage(HttpMethod.Post, url)
        {
            Content = JsonContent.Create(new { query = question, stream = true }),
        };
        // ResponseHeadersRead returns as soon as the headers arrive, rather
        // than after the whole body, so the body can be read as the server
        // sends it.
        using var response = await client.SendAsync(
            request, HttpCompletionOption.ResponseHeadersRead);
    
        // A request the server rejects gets an ordinary error status. Once
        // streaming starts the status is always 200, so later failures arrive
        // as events instead.
        if (!response.IsSuccessStatusCode)
        {
            // Bound this read as well, in case the server stalls.
            using var timeout = new CancellationTokenSource(
                TimeSpan.FromSeconds(TimeoutSeconds));
            string body;
            try
            {
                body = await response.Content.ReadAsStringAsync(timeout.Token);
            }
            catch (OperationCanceledException) when (timeout.IsCancellationRequested)
            {
                throw new TimeoutException(
                    $"No data from the server for {TimeoutSeconds} seconds");
            }
            throw new RagException(
                $"HTTP {(int)response.StatusCode}, {ErrorText(body)}");
        }
    
        var chunks = 0;
        string? error = null;
        var done = false;
    
        using var reader = new StreamReader(await response.Content.ReadAsStreamAsync());
        await foreach (var ev in ReadEventsAsync(reader))
        {
            // Anything other than a JSON object is not an event this program
            // knows, so skip it.
            if (ev is not JsonObject obj)
            {
                continue;
            }
            switch (obj["type"]?.ToString())
            {
                case "chunk":
                    // The last chunk has no content.
                    var content = obj["content"]?.ToString();
                    if (!string.IsNullOrEmpty(content))
                    {
                        Console.Write(content);
                        chunks++;
                    }
                    break;
                case "error":
                    var message = obj["error"]?.ToString();
                    error = string.IsNullOrEmpty(message) ? "unknown error" : message;
                    break;
                case "done":
                    done = true;
                    break;
            }
        }
    
        Console.WriteLine();
        // The server sends a done event after an error event, so keep reading
        // until the stream ends before reporting the error.
        if (error is not null)
        {
            throw new RagException($"The stream reported an error: {error}");
        }
        if (!done)
        {
            throw new RagException("The stream ended before the done event");
        }
        return chunks;
    }
    
    Console.WriteLine($"Question: {Question}");
    Console.WriteLine("Answer:");
    try
    {
        // using disposes of the client, and closes its connections, when the
        // block exits, whether or not an error occurred.
        using var client = new HttpClient
        {
            Timeout = TimeSpan.FromSeconds(TimeoutSeconds),
        };
        var chunks = await StreamAnswerAsync(client, Question);
        Console.WriteLine($"Chunks received: {chunks}");
    }
    // HttpRequestException covers failures to reach the server, such as a
    // refused connection, TaskCanceledException covers a timeout while waiting
    // for the response, TimeoutException covers a stream that stops part of
    // the way through, IOException covers a stream that fails part of the way
    // through, and JsonException covers an event whose data is not valid JSON.
    catch (Exception e) when (e is HttpRequestException or TaskCanceledException
        or TimeoutException or IOException or JsonException or RagException)
    {
        Console.Error.WriteLine($"RAG Server error: {e.Message}");
        return 1;
    }
    
    return 0;
    
    // C# requires type declarations to follow the top-level statements, so
    // the exception that the program throws for an error reply is declared
    // here, at the end.
    class RagException(string message) : Exception(message);
    
    ```

=== "Go"

    ```go
    // Ellie's Postgres Cookbook
    // Streaming an answer from the pgEdge RAG Server, using net/http.
    //
    // These examples are for pgEdge RAG Server 2.0.0.
    //
    // Copyright (c) 2026, pgEdge, Inc.
    // This code is released under the PostgreSQL License.
    
    package main
    
    import (
    	"bufio"
    	"bytes"
    	"encoding/json"
    	"errors"
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
    	baseURL  = strings.TrimRight(envOr("RAG_SERVER_URL", "http://localhost:8080"), "/")
    	pipeline = envOr("RAG_PIPELINE", "cookbook")
    )
    
    const question = "How long does the Acme Widget 2.0 take to charge?"
    
    // The client's timeout covers the whole exchange, including the time it
    // takes to read the stream. The server may wait for the language model
    // before the first chunk arrives, and a small model on a modest machine
    // can take a while, so allow plenty of time.
    const timeout = 300 * time.Second
    
    
    // streamEvent is one event of the stream: a "chunk" with content, an
    // "error" with a message, or "done".
    type streamEvent struct {
    	Type    string `json:"type"`
    	Content string `json:"content"`
    	Error   string `json:"error"`
    }
    
    // readEvents parses Server-Sent Events from r, and calls handle with the
    // JSON object that the data of each event holds. An event is one or more
    // "data:" lines followed by a blank line. The stream may end without the
    // final blank line, so the last event is sent when the lines run out as
    // well.
    func readEvents(r io.Reader, handle func(streamEvent)) error {
    	var data []string
    
    	flush := func() error {
    		if len(data) == 0 {
    			return nil
    		}
    		var event streamEvent
    		err := json.Unmarshal([]byte(strings.Join(data, "\n")), &event)
    		data = nil
    		if err != nil {
    			return fmt.Errorf("invalid event: %w", err)
    		}
    		handle(event)
    		return nil
    	}
    
    	scanner := bufio.NewScanner(r)
    	// Allow lines of up to 1 MiB; the default limit is 64 KiB.
    	scanner.Buffer(make([]byte, 0, 64*1024), 1024*1024)
    	for scanner.Scan() {
    		line := scanner.Text()
    		if line == "" {
    			if err := flush(); err != nil {
    				return err
    			}
    		} else if after, found := strings.CutPrefix(line, "data:"); found {
    			// A single space after the colon is not part of the data.
    			data = append(data, strings.TrimPrefix(after, " "))
    		}
    		// Comment lines (which start with a colon) and other fields are
    		// ignored.
    	}
    	if err := scanner.Err(); err != nil {
    		return err
    	}
    	return flush()
    }
    
    
    // errorText describes an error response, which carries a JSON body of the
    // form {"error": {"code": "...", "message": "..."}}.
    func errorText(body []byte) string {
    	var e struct {
    		Error struct {
    			Code    string `json:"code"`
    			Message string `json:"message"`
    		} `json:"error"`
    	}
    	if json.Unmarshal(body, &e) == nil && e.Error.Code != "" {
    		return e.Error.Code + ": " + e.Error.Message
    	}
    	return strings.TrimSpace(string(body))
    }
    
    // streamAnswer prints the answer as it arrives, and returns the number of
    // chunks.
    func streamAnswer(client *http.Client, question string) (int, error) {
    	payload, err := json.Marshal(map[string]any{"query": question, "stream": true})
    	if err != nil {
    		return 0, err
    	}
    
    	endpoint := baseURL + "/v1/pipelines/" + url.PathEscape(pipeline)
    	response, err := client.Post(endpoint, "application/json", bytes.NewReader(payload))
    	if err != nil {
    		return 0, err
    	}
    	defer response.Body.Close()
    
    	// A request the server rejects gets an ordinary error status. Once
    	// streaming starts the status is always 200, so later failures arrive
    	// as events instead.
    	if response.StatusCode != http.StatusOK {
    		body, _ := io.ReadAll(io.LimitReader(response.Body, 4096))
    		return 0, fmt.Errorf("HTTP %d, %s", response.StatusCode, errorText(body))
    	}
    
    	chunks := 0
    	streamError := ""
    	done := false
    
    	err = readEvents(response.Body, func(event streamEvent) {
    		switch event.Type {
    		case "chunk":
    			// The last chunk has no content.
    			if event.Content != "" {
    				fmt.Print(event.Content)
    				chunks++
    			}
    		case "error":
    			streamError = event.Error
    			if streamError == "" {
    				streamError = "unknown error"
    			}
    		case "done":
    			done = true
    		}
    	})
    	fmt.Println()
    	if err != nil {
    		return chunks, err
    	}
    
    	// The server sends a done event after an error event, so keep reading
    	// until the stream ends before reporting the error.
    	if streamError != "" {
    		return chunks, fmt.Errorf("the stream reported an error: %s", streamError)
    	}
    	if !done {
    		return chunks, errors.New("the stream ended before the done event")
    	}
    	return chunks, nil
    }
    
    
    // run asks the question and prints the answer as it streams in, returning
    // any error to the caller.
    func run() error {
    	client := &http.Client{Timeout: timeout}
    
    	fmt.Printf("Question: %s\n", question)
    	fmt.Println("Answer:")
    	chunks, err := streamAnswer(client, question)
    	if err != nil {
    		return err
    	}
    
    	fmt.Printf("Chunks received: %d\n", chunks)
    	return nil
    }
    
    // main reports any error returned by run() and exits with a non-zero
    // status.
    func main() {
    	if err := run(); err != nil {
    		fmt.Fprintf(os.Stderr, "RAG Server error: %v\n", err)
    		os.Exit(1)
    	}
    }
    
    
    ```

=== "Rust"

    ```rust
    // Ellie's Postgres Cookbook
    // Streaming an answer from the pgEdge RAG Server, using reqwest and
    // serde_json.
    //
    // These examples are for pgEdge RAG Server 2.0.0.
    //
    // Copyright (c) 2026, pgEdge, Inc.
    // This code is released under the PostgreSQL License.
    
    use std::env;
    use std::error::Error;
    use std::io::{self, BufRead, BufReader, Read, Write};
    use std::process::ExitCode;
    use std::time::Duration;
    
    use reqwest::blocking::Client;
    use reqwest::Url;
    use serde_json::{json, Value};
    
    /// Returns the value of an environment variable, or a fallback if the
    /// variable is unset or empty.
    fn env_or(name: &str, fallback: &str) -> String {
        env::var(name)
            .ok()
            .filter(|value| !value.is_empty())
            .unwrap_or_else(|| fallback.to_string())
    }
    
    fn base_url() -> String {
        env_or("RAG_SERVER_URL", "http://localhost:8080")
            .trim_end_matches('/')
            .to_string()
    }
    
    fn pipeline() -> String {
        env_or("RAG_PIPELINE", "cookbook")
    }
    
    const QUESTION: &str = "How long does the Acme Widget 2.0 take to charge?";
    
    /// The blocking client applies the timeout to the wait for the response
    /// and to each wait for data, rather than to the whole stream, but the
    /// server may wait for the language model to begin, and a small model on a
    /// modest machine can take a while, so allow plenty of time.
    const TIMEOUT: Duration = Duration::from_secs(300);
    
    /// The errors that the functions below return; a string converts into one
    /// with the ? operator or into().
    type BoxError = Box<dyn Error>;
    
    /// Parses Server-Sent Events from a reader, and passes the JSON that the
    /// data of each event holds to handle, as each event arrives.
    ///
    /// An event is one or more "data:" lines followed by a blank line. The
    /// stream may end without the final blank line, so the last event is sent
    /// when the lines run out as well.
    fn read_events(reader: impl BufRead, mut handle: impl FnMut(Value)) -> Result<(), BoxError> {
        let mut data: Vec<String> = Vec::new();
        for line in reader.lines() {
            let line = line?;
            if line.is_empty() {
                if !data.is_empty() {
                    handle(serde_json::from_str(&data.join("\n"))?);
                    data.clear();
                }
            } else if let Some(value) = line.strip_prefix("data:") {
                // A single space after the colon is not part of the data.
                data.push(value.strip_prefix(' ').unwrap_or(value).to_string());
            }
            // Comment lines (which start with a colon) and other fields are
            // ignored.
        }
        if !data.is_empty() {
            handle(serde_json::from_str(&data.join("\n"))?);
        }
        Ok(())
    }
    
    /// Describes an error response, which carries a JSON body of the form
    /// {"error": {"code": "...", "message": "..."}}.
    fn error_text(body: &str) -> String {
        // A body that is not JSON becomes Null, and indexing Null (or any
        // missing field) gives Null again, which as_str() turns into None.
        let reply: Value = serde_json::from_str(body).unwrap_or(Value::Null);
        let error = &reply["error"];
        match (error["code"].as_str(), error["message"].as_str()) {
            (Some(code), message) => format!("{code}: {}", message.unwrap_or("")),
            _ => body.trim().chars().take(200).collect(),
        }
    }
    
    /// Returns the URL of a pipeline. push() escapes any character in the
    /// pipeline name that is not safe in a URL path.
    fn pipeline_url(name: &str) -> Result<Url, BoxError> {
        let mut url = Url::parse(&format!("{}/v1/pipelines/", base_url()))?;
        url.path_segments_mut()
            .map_err(|()| "RAG_SERVER_URL cannot be a base URL")?
            .pop_if_empty()
            .push(name);
        Ok(url)
    }
    
    /// Prints the answer as it arrives, and returns the number of chunks.
    fn stream_answer(client: &Client, question: &str) -> Result<u32, BoxError> {
        // send() returns as soon as the headers arrive, and the response can
        // then be read as the server sends the body.
        let response = client
            .post(pipeline_url(&pipeline())?)
            .json(&json!({ "query": question, "stream": true }))
            .send()?;
    
        // A request the server rejects gets an ordinary error status. Once
        // streaming starts the status is always 200, so later failures arrive
        // as events instead.
        let status = response.status();
        if !status.is_success() {
            let mut body = String::new();
            response.take(4096).read_to_string(&mut body)?;
            return Err(format!("HTTP {}, {}", status.as_u16(), error_text(&body)).into());
        }
    
        let mut chunks = 0;
        let mut error: Option<String> = None;
        let mut done = false;
        let mut stdout = io::stdout();
    
        read_events(BufReader::new(response), |event| {
            match event["type"].as_str() {
                Some("chunk") => {
                    // The last chunk has no content.
                    let content = event["content"].as_str().unwrap_or("");
                    if !content.is_empty() {
                        // Rust buffers standard output by line, so flush it to
                        // show each chunk at once.
                        print!("{content}");
                        let _ = stdout.flush();
                        chunks += 1;
                    }
                }
                Some("error") => {
                    let message = event["error"].as_str().unwrap_or("");
                    error = Some(if message.is_empty() { "unknown error" } else { message }.to_string());
                }
                Some("done") => done = true,
                _ => {}
            }
        })?;
    
        println!();
        // The server sends a done event after an error event, so keep reading
        // until the stream ends before reporting the error.
        if let Some(error) = error {
            return Err(format!("The stream reported an error: {error}").into());
        }
        if !done {
            return Err("The stream ended before the done event".into());
        }
        Ok(chunks)
    }
    
    /// Asks the question and prints the answer as it streams in. The ?
    /// operator returns any error to the caller.
    fn run() -> Result<(), BoxError> {
        let client = Client::builder().timeout(TIMEOUT).build()?;
    
        println!("Question: {QUESTION}");
        println!("Answer:");
        let chunks = stream_answer(&client, QUESTION)?;
        println!("Chunks received: {chunks}");
        Ok(())
    }
    
    /// Reports any error returned by run() and exits with a failure status.
    /// The top-level error is often generic ("error sending request"), so the
    /// chain of underlying causes is printed too.
    fn main() -> ExitCode {
        match run() {
            Ok(()) => ExitCode::SUCCESS,
            Err(e) => {
                eprintln!("RAG Server error: {e}");
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
    # Streaming an answer from the pgEdge RAG Server, using Net::HTTP.
    #
    # These examples are for pgEdge RAG Server 2.0.0.
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
    
    BASE_URL = env_or("RAG_SERVER_URL", "http://localhost:8080").sub(%r{/+\z}, "")
    PIPELINE = env_or("RAG_PIPELINE", "cookbook")
    
    QUESTION = "How long does the Acme Widget 2.0 take to charge?"
    
    # The timeout applies to each wait for data rather than to the whole
    # stream, but the server may wait for the language model to begin, and a
    # small model on a modest machine can take a while, so allow plenty of
    # time.
    TIMEOUT_SECONDS = 300
    
    # Yields each line of a response body, without its line ending, as soon as
    # the whole line has arrived. read_body hands over the body in pieces that
    # need not end at a line break, so the start of a line waits in a buffer
    # for the rest.
    def each_line(response)
      buffer = String.new
      response.read_body do |piece|
        buffer << piece
        while (index = buffer.index("\n"))
          yield buffer.slice!(0..index).chomp.force_encoding(Encoding::UTF_8)
        end
      end
      yield buffer.chomp.force_encoding(Encoding::UTF_8) unless buffer.empty?
    end
    
    # Parses Server-Sent Events from a response, and yields the JSON that the
    # data of each event holds, as each event arrives.
    #
    # An event is one or more "data:" lines followed by a blank line. The
    # stream may end without the final blank line, so the last event is sent
    # when the lines run out as well. JSON.parse raises JSON::ParserError for
    # data that is not valid JSON.
    def read_events(response)
      data = []
      each_line(response) do |line|
        if line.empty?
          yield JSON.parse(data.join("\n")) unless data.empty?
          data = []
        elsif line.start_with?("data:")
          # A single space after the colon is not part of the data.
          data << line.delete_prefix("data:").delete_prefix(" ")
        end
        # Comment lines (which start with a colon) and other fields are
        # ignored.
      end
      yield JSON.parse(data.join("\n")) unless data.empty?
    end
    
    # Raised when the RAG Server rejects a request or the stream fails.
    class RagError < StandardError; end
    
    # Describes an error response, which carries a JSON body of the form
    # {"error": {"code": "...", "message": "..."}}.
    def error_text(body)
      error = JSON.parse(body.to_s)["error"]
      return "#{error["code"]}: #{error["message"]}" if error.is_a?(Hash) && error["code"].is_a?(String)
    
      body.to_s.strip[0, 200]
    rescue JSON::ParserError, NoMethodError, TypeError
      body.to_s.strip[0, 200]
    end
    
    # Prints the answer as it arrives, and returns the number of chunks.
    def stream_answer(http, question)
      uri = URI("#{BASE_URL}/v1/pipelines/#{URI.encode_uri_component(PIPELINE)}")
      request = Net::HTTP::Post.new(uri, "Content-Type" => "application/json")
      request.body = JSON.generate({ query: question, stream: true })
    
      chunks = 0
      error = nil
      done = false
    
      # Given a block, request hands over the response before reading its
      # body, which the block then reads as the server sends it.
      http.request(request) do |response|
        # A request the server rejects gets an ordinary error status. Once
        # streaming starts the status is always 200, so later failures arrive
        # as events instead.
        unless response.is_a?(Net::HTTPSuccess)
          raise RagError, "HTTP #{response.code}, #{error_text(response.read_body)}"
        end
    
        read_events(response) do |event|
          # Anything other than a JSON object is not an event this program
          # knows, so skip it.
          next unless event.is_a?(Hash)
    
          case event["type"]
          when "chunk"
            # The last chunk has no content.
            content = event["content"].to_s
            unless content.empty?
              # Ruby buffers standard output when it is not a terminal, so
              # flush it to show each chunk at once.
              print content
              $stdout.flush
              chunks += 1
            end
          when "error"
            message = event["error"].to_s
            error = message.empty? ? "unknown error" : message
          when "done"
            done = true
          end
        end
      end
    
      puts
      # The server sends a done event after an error event, so keep reading
      # until the stream ends before reporting the error.
      raise RagError, "The stream reported an error: #{error}" if error
      raise RagError, "The stream ended before the done event" unless done
    
      chunks
    end
    
    puts "Question: #{QUESTION}"
    puts "Answer:"
    begin
      uri = URI(BASE_URL)
      # start opens a connection, and closes it when the block exits, whether
      # or not an error occurred.
      chunks = Net::HTTP.start(
        uri.host, uri.port,
        use_ssl: uri.scheme == "https",
        open_timeout: TIMEOUT_SECONDS, read_timeout: TIMEOUT_SECONDS
      ) { |http| stream_answer(http, QUESTION) }
      puts "Chunks received: #{chunks}"
    # SystemCallError covers a refused connection, Timeout::Error covers the
    # connection and read timeouts, SocketError covers an unknown host, and
    # JSON::ParserError covers an event whose data is not valid JSON.
    rescue RagError, SystemCallError, Timeout::Error, SocketError, IOError,
           JSON::ParserError => e
      warn "RAG Server error: #{e.message}"
      exit 1
    end
    
    ```

=== "curl"

    ```bash
    #!/usr/bin/env bash
    #
    # Ellie's Postgres Cookbook
    # Streaming an answer from the pgEdge RAG Server, using curl and jq.
    #
    # These examples are for pgEdge RAG Server 2.0.0.
    #
    # Copyright (c) 2026, pgEdge, Inc.
    # This code is released under the PostgreSQL License.
    
    # Stop at the first failed command or unset variable, and treat a failure
    # anywhere in a pipeline as a failure of the whole pipeline.
    set -euo pipefail
    
    for tool in curl jq; do
        command -v "$tool" >/dev/null || { echo "$tool is required" >&2; exit 1; }
    done
    
    # The :- operator treats an empty variable as unset.
    RAG_SERVER_URL="${RAG_SERVER_URL:-http://localhost:8080}"
    RAG_SERVER_URL="${RAG_SERVER_URL%/}"
    RAG_PIPELINE="${RAG_PIPELINE:-cookbook}"
    
    QUESTION="How long does the Acme Widget 2.0 take to charge?"
    
    # The server may wait for the language model before the first chunk
    # arrives, and a small model on a modest machine can take a while, so
    # allow plenty of time for the whole stream.
    TIMEOUT_SECONDS=300
    
    # Escapes a value for use in a URL path, as the other languages do.
    escape() { jq -rn --arg value "$1" '$value | @uri'; }
    
    # Sends the question with streaming switched on, and prints the Server-Sent
    # Events as they arrive. --no-buffer stops curl from holding the output
    # back, and --fail-with-body makes curl exit non-zero on an HTTP error
    # status while still printing the body, which carries the explanation.
    request_stream() {
        jq -n --arg query "$1" '{query: $query, stream: true}' |
            curl --silent --show-error --fail-with-body --no-buffer \
                --max-time "$TIMEOUT_SECONDS" \
                --header 'Content-Type: application/json' \
                --data-binary @- \
                "$RAG_SERVER_URL/v1/pipelines/$(escape "$RAG_PIPELINE")"
    }
    
    # Reads Server-Sent Events from standard input, prints the content of each
    # chunk event as it arrives, and returns non-zero if the stream reports an
    # error, holds an event that is not valid JSON, or ends without a done
    # event. An event is one or more "data:" lines, which are joined with
    # newlines, followed by a blank line. The loop also handles a final line
    # that has no newline.
    read_events() {
        local line data="" have_data=false kind chunks=0 error="" other=""
        local done=false
    
        # Handles the event that has been collected. It sets the variables of
        # read_events, because a bash function can change its caller's locals.
        # The explicit checks matter, because set -e does not apply inside a
        # function that runs on the left of ||.
        handle_event() {
            local content
            $have_data || return 0
            kind="$(jq -r '.type' <<<"$data")" || {
                echo "The stream sent an event that is not valid JSON: $data" >&2
                return 1
            }
            case "$kind" in
                chunk)
                    # The last chunk has no content. A command substitution
                    # strips trailing newlines, which would run paragraphs
                    # together, so jq -j appends an x after the content and
                    # the next line removes it again.
                    content="$(jq -j '(.content // "") + "x"' <<<"$data")" ||
                        return 1
                    content="${content%x}"
                    if [[ -n "$content" ]]; then
                        printf '%s' "$content"
                        chunks=$((chunks + 1))
                    fi
                    ;;
                error)
                    error="$(jq -r '.error // "unknown error"' <<<"$data")" ||
                        return 1
                    ;;
                done) done=true ;;
            esac
            data=""
            have_data=false
        }
    
        while IFS= read -r line || [[ -n "$line" ]]; do
            line="${line%$'\r'}"
            if [[ -z "$line" ]]; then
                # A blank line ends the event.
                handle_event || return 1
            elif [[ "$line" == data:* ]]; then
                line="${line#data:}"
                if $have_data; then data+=$'\n'; fi
                data+="${line# }"
                have_data=true
            elif [[ "$line" != :* ]]; then
                # Comment lines start with a colon. Anything else is not an
                # event, such as the JSON body of an HTTP error, so keep it for
                # the error message.
                other+="$line"
            fi
        done
        # The stream may end without a blank line after the last event.
        handle_event || return 1
        echo
    
        # The server sends a done event after an error event, so keep reading
        # until the stream ends before reporting the error.
        if [[ -n "$error" ]]; then
            echo "The stream reported an error: $error" >&2
            return 1
        fi
        if [[ "$done" != true ]]; then
            echo "The stream ended before the done event${other:+: $other}" >&2
            return 1
        fi
        echo "Chunks received: $chunks"
    }
    
    main() {
        echo "Question: $QUESTION"
        echo "Answer:"
        # With pipefail, the pipeline fails if curl fails or the stream
        # reports an error.
        request_stream "$QUESTION" | read_events || {
            echo "RAG Server error: the request failed" >&2
            exit 1
        }
    }
    
    main
    
    ```

## Next Steps

The following resources provide more information about the topics in this
recipe:

- The [Asking a Question](ask_question.md) recipe shows the same request
  without streaming.
- The [Showing the Sources of an Answer](include_sources.md) recipe shows how
  to list the documents that an answer came from. A streaming reply carries no
  sources in RAG Server 2.0.0, so request them without streaming.
- The
  [pgEdge RAG Server documentation](https://docs.pgedge.com/pgedge-rag-server/)
  describes the API and the pipeline configuration.
- The [Contributing a Recipe](../contributing.md) page explains how to add
  a recipe or a language to the cookbook.
