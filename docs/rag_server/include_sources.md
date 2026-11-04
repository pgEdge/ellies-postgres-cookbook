# Showing the Sources of an Answer

This recipe asks a pgEdge RAG Server pipeline a question and prints the
answer together with the stored documents that the answer came from. Showing
sources lets a reader check an answer against the original text. Each step
shows the code in every supported language; selecting a language tab
switches every tab on the site to that language.

These examples are for pgEdge RAG Server 2.0.0.

The wording of the answer varies from run to run, because a language model
writes it, but the output has the following shape:

```text
Question: How long does the Acme Widget 2.0 take to charge?
Answer:
The Acme Widget 2.0 takes ninety minutes to fully charge.
Sources (3):
- 3: The Acme Widget 2.0 charges through its USB-C port. A full c...
- 1: The Acme Widget 2.0 is a fictional gadget used in the cookbo...
- 2: To reset the Acme Widget 2.0, hold the power button for eigh...
```

## Preparing the Ingredients

The examples need a running RAG Server with a pipeline that reads a table of
embedded documents; the
[Preparing Data for the RAG Server](prepare_data.md) recipe shows how to
build such a table and its pipeline. The examples assume a pipeline named
`cookbook` that holds the fictional Acme Widget support documents, which the
`scripts/start_rag_server.sh` script in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook)
loads and starts in Docker. The [Asking a Question](ask_question.md) recipe
describes the request that this recipe extends.

Two settings must both allow sources before a reply includes them. The
request must set `"include_sources": true` in its JSON body, and the
pipeline must set `allow_include_sources: true` in the RAG Server
configuration file:

```yaml
pipelines:
  - name: "cookbook"
    allow_include_sources: true
```

When the pipeline does not allow sources, the server still answers the
question and returns no error; it simply leaves the `sources` array out of
the reply. The programs therefore print a hint when the array is missing.

!!! warning

    A pipeline that sets `allow_include_sources: true` returns the text of
    the matching rows to anyone who can call it, so treat every row in the
    table as public. Leave the setting off for a table that holds anything
    that callers should not see.

The reply is a JSON object whose `sources` array holds one object for each
document that the server gave to the language model:

```json
{
  "answer": "...",
  "sources": [{"id": "3", "content": "...", "score": 0.83}],
  "tokens_used": 812
}
```

The `id` is the value of the table's ID column, as a string, the `content`
is the document text, and the `score` says how closely the document matched
the question.

The programs use only an HTTP client and a JSON encoder. The following table
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
    --8<-- "recipes/rag_server/include_sources/python/requirements.txt:deps"
    ```

=== "TypeScript"

    ```json
    --8<-- "recipes/rag_server/include_sources/typescript/package.json"
    ```

=== "Go"

    ```text
    --8<-- "recipes/rag_server/include_sources/go/go.mod:deps"
    ```

## Importing the Libraries

Each program begins by importing the HTTP client, along with any standard
library modules that it uses. The TypeScript program imports nothing, and
the curl script stops at the first failed command and checks that `curl`
and `jq` are installed. The following tabs show the imports for each
language:

=== "Python"

    ```python
    --8<-- "recipes/rag_server/include_sources/python/main.py:imports"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/rag_server/include_sources/typescript/main.ts:imports"
    ```

=== "Go"

    ```go
    --8<-- "recipes/rag_server/include_sources/go/main.go:imports"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/rag_server/include_sources/curl/main.sh:imports"
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

A language model can take a while to write an answer, particularly a small
model on a modest machine, so each program allows 300 seconds for the
reply. The following tabs show how each program reads its settings:

=== "Python"

    ```python
    --8<-- "recipes/rag_server/include_sources/python/main.py:config"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/rag_server/include_sources/typescript/main.ts:config"
    ```

=== "Go"

    ```go
    --8<-- "recipes/rag_server/include_sources/go/main.go:config"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/rag_server/include_sources/curl/main.sh:config"
    ```

## Asking for the Sources

Each program sends the question in a `POST` request whose JSON body sets
`include_sources` to true, and returns the decoded reply. The RAG Server
reports a failure with an HTTP error status and a JSON body that holds an
error code and a message, and the programs print both. The following tabs
show how each program sends the question:

=== "Python"

    ```python
    --8<-- "recipes/rag_server/include_sources/python/main.py:ask"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/rag_server/include_sources/typescript/main.ts:ask"
    ```

=== "Go"

    ```go
    --8<-- "recipes/rag_server/include_sources/go/main.go:ask"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/rag_server/include_sources/curl/main.sh:ask"
    ```

## Printing the Sources

Each program prints one line for each source, with the ID and the start of
the document text. The programs join line breaks in the text into spaces and
shorten the text to 60 characters, so that each source fits on one line, and
they print the sources in the order that the server returns them. The
following tabs show how each program prints the sources:

=== "Python"

    ```python
    --8<-- "recipes/rag_server/include_sources/python/main.py:sources"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/rag_server/include_sources/typescript/main.ts:sources"
    ```

=== "Go"

    ```go
    --8<-- "recipes/rag_server/include_sources/go/main.go:sources"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/rag_server/include_sources/curl/main.sh:sources"
    ```

## Handling Errors

The main part of each program prints the question, the answer, and the
sources. The program reports any failure on `stderr`, whether the server was
unreachable or replied with an error, and then exits with a non-zero
status. The following tabs show the main part of each program:

=== "Python"

    ```python
    --8<-- "recipes/rag_server/include_sources/python/main.py:main"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/rag_server/include_sources/typescript/main.ts:main"
    ```

=== "Go"

    ```go
    --8<-- "recipes/rag_server/include_sources/go/main.go:main"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/rag_server/include_sources/curl/main.sh:main"
    ```

## Running the Example

The complete project for each language is available in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/rag_server/include_sources).
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
    --8<-- "recipes/rag_server/include_sources/python/main.py"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/rag_server/include_sources/typescript/main.ts"
    ```

=== "Go"

    ```go
    --8<-- "recipes/rag_server/include_sources/go/main.go"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/rag_server/include_sources/curl/main.sh"
    ```

## Next Steps

The following resources provide more information about the topics in this
recipe:

- The [Asking a Question](ask_question.md) recipe shows the same request
  without the sources.
- The [Streaming an Answer](stream_answer.md) recipe shows how to display
  the answer as the model writes it. A streaming reply carries no sources in
  RAG Server 2.0.0.
- The
  [pgEdge RAG Server documentation](https://docs.pgedge.com/pgedge-rag-server/)
  describes the API and the pipeline configuration.
- The [Contributing a Recipe](../contributing.md) page explains how to add
  a recipe or a language to the cookbook.
