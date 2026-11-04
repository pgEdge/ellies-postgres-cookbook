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

| Language   | HTTP client                                                  |
|------------|--------------------------------------------------------------|
| Python     | [httpx](https://www.python-httpx.org/)                       |
| TypeScript | The `fetch` function that Node.js provides                   |
| Go         | The `net/http` package                                       |
| curl       | [curl](https://curl.se/) and [jq](https://jqlang.org/)       |

The following tabs show the dependency declaration from each example
project; the TypeScript project needs only the compiler and the Node.js
type definitions, and the Go program needs nothing beyond the standard
library:

=== "Python"

    ```text
    --8<-- "recipes/rag_server/stream_answer/python/requirements.txt:deps"
    ```

=== "TypeScript"

    ```json
    --8<-- "recipes/rag_server/stream_answer/typescript/package.json"
    ```

=== "Go"

    ```text
    --8<-- "recipes/rag_server/stream_answer/go/go.mod:deps"
    ```

## Importing the Libraries

Each program begins by importing the HTTP client, along with any standard
library modules that it uses. The TypeScript program imports nothing, and
the curl script stops at the first failed command and checks that `curl`
and `jq` are installed. The following tabs show the imports for each
language:

=== "Python"

    ```python
    --8<-- "recipes/rag_server/stream_answer/python/main.py:imports"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/rag_server/stream_answer/typescript/main.ts:imports"
    ```

=== "Go"

    ```go
    --8<-- "recipes/rag_server/stream_answer/go/main.go:imports"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/rag_server/stream_answer/curl/main.sh:imports"
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
    --8<-- "recipes/rag_server/stream_answer/python/main.py:config"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/rag_server/stream_answer/typescript/main.ts:config"
    ```

=== "Go"

    ```go
    --8<-- "recipes/rag_server/stream_answer/go/main.go:config"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/rag_server/stream_answer/curl/main.sh:config"
    ```

## Parsing the Events

An event can arrive in pieces, and a single network read can hold several
events or half of one, so the programs read the response line by line rather
than read by read. A parser collects the `data:` lines of an event, decodes
them as JSON when it reaches the blank line that ends the event, and ignores
comment lines and any other field. The parser also sends the last event when
the stream ends without a final blank line, so that a stream cut short in
that way does not lose its `done` event. The following tabs show the parser
for each language:

=== "Python"

    ```python
    --8<-- "recipes/rag_server/stream_answer/python/main.py:events"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/rag_server/stream_answer/typescript/main.ts:events"
    ```

=== "Go"

    ```go
    --8<-- "recipes/rag_server/stream_answer/go/main.go:events"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/rag_server/stream_answer/curl/main.sh:events"
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
    --8<-- "recipes/rag_server/stream_answer/python/main.py:stream"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/rag_server/stream_answer/typescript/main.ts:stream"
    ```

=== "Go"

    ```go
    --8<-- "recipes/rag_server/stream_answer/go/main.go:stream"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/rag_server/stream_answer/curl/main.sh:request"
    ```

## Handling Errors

The main part of each program prints the question, calls the function from
the previous step, and prints the number of chunks. The program reports any
failure on `stderr`, whether the server was unreachable, replied with an
error status, or sent an `error` event, and then exits with a non-zero
status. The Python program catches `httpx.HTTPError`, the base class for
connection failures and timeouts, as well as its own error class; the
TypeScript program catches any rejected promise; the Go program returns each
error from a `run()` function to `main()`; and the curl script relies on
`set -o pipefail`, so a failure of `curl` or of the event reader fails the
whole pipeline. The following tabs show the main part of each program:

=== "Python"

    ```python
    --8<-- "recipes/rag_server/stream_answer/python/main.py:main"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/rag_server/stream_answer/typescript/main.ts:main"
    ```

=== "Go"

    ```go
    --8<-- "recipes/rag_server/stream_answer/go/main.go:main"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/rag_server/stream_answer/curl/main.sh:main"
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

=== "Go"

    ```bash
    go run .
    ```

=== "curl"

    ```bash
    bash main.sh
    ```

## Viewing the Complete Program

The following tabs show the complete program for each language:

=== "Python"

    ```python
    --8<-- "recipes/rag_server/stream_answer/python/main.py"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/rag_server/stream_answer/typescript/main.ts"
    ```

=== "Go"

    ```go
    --8<-- "recipes/rag_server/stream_answer/go/main.go"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/rag_server/stream_answer/curl/main.sh"
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
