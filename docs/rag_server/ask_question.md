# Asking a Question

This recipe sends a question to a pgEdge RAG Server pipeline and prints the
answer, together with the number of tokens that the request used. The RAG
Server finds the stored documents that best match the question, gives them
to a language model as context, and returns the model's answer. Each step
shows the code in every supported language; selecting a language tab
switches every tab on the site to that language.

These examples are for pgEdge RAG Server 2.0.0.

The example programs ask how long the fictional Acme Widget 2.0 takes to
charge. The wording of the answer varies from run to run, because a language
model writes it, but the output has the following shape:

```text
Question: How long does the Acme Widget 2.0 take to charge?
Answer:
The Acme Widget 2.0 takes ninety minutes to fully charge.
Tokens used: 812
```

## Preparing the Ingredients

The examples need a running RAG Server with a pipeline that reads a table of
embedded documents; the
[Preparing Data for the RAG Server](prepare_data.md) recipe shows how to
build such a table and its pipeline. The examples assume a pipeline named
`cookbook` that holds the fictional Acme Widget support documents, which the
`scripts/start_rag_server.sh` script in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook)
loads and starts in Docker. Any pipeline works if you change the question.

The RAG Server answers a question with a `POST` request to
`/v1/pipelines/{name}`, where `{name}` is the name of the pipeline. The body
is a JSON object, and only the `query` field is required:

```json
{"query": "How long does the Acme Widget 2.0 take to charge?"}
```

The reply is a JSON object with the answer and the total number of tokens
that the request consumed:

```json
{"answer": "...", "tokens_used": 812}
```

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
    --8<-- "recipes/rag_server/ask_question/python/requirements.txt:deps"
    ```

=== "TypeScript"

    ```json
    --8<-- "recipes/rag_server/ask_question/typescript/package.json"
    ```

=== "Go"

    ```text
    --8<-- "recipes/rag_server/ask_question/go/go.mod:deps"
    ```

## Importing the Libraries

Each program begins by importing the HTTP client, along with any standard
library modules that it uses. The TypeScript program imports nothing, and
the curl script stops at the first failed command and checks that `curl`
and `jq` are installed. The following tabs show the imports for each
language:

=== "Python"

    ```python
    --8<-- "recipes/rag_server/ask_question/python/main.py:imports"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/rag_server/ask_question/typescript/main.ts:imports"
    ```

=== "Go"

    ```go
    --8<-- "recipes/rag_server/ask_question/go/main.go:imports"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/rag_server/ask_question/curl/main.sh:imports"
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
    --8<-- "recipes/rag_server/ask_question/python/main.py:config"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/rag_server/ask_question/typescript/main.ts:config"
    ```

=== "Go"

    ```go
    --8<-- "recipes/rag_server/ask_question/go/main.go:config"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/rag_server/ask_question/curl/main.sh:config"
    ```

## Sending the Question

Each program sends the question in a `POST` request with a JSON body, and
reads the `answer` and `tokens_used` fields of the reply. The Python,
TypeScript, and Go programs build the URL from the pipeline name, and escape
any character in the name that is not safe in a URL path. Each program
builds the JSON body with a JSON encoder (`jq` in the curl script) rather
than by joining strings, so a question that contains quotation marks cannot
break the request.

The RAG Server reports a failure with an HTTP error status and a JSON body
that holds an error code and a message, such as `PIPELINE_NOT_FOUND` for a
pipeline that does not exist, or `REQUEST_TIMEOUT` when the request takes too
long. The programs print the code and the message. Some HTTP clients treat
an error status as a normal response, so the Python program checks
`is_error`, the TypeScript program checks `response.ok`, the Go program
compares the status code, and curl uses `--fail-with-body`, which makes
`curl` exit with an error and still print the body. The following tabs show
how each program sends the question and reads the reply:

=== "Python"

    ```python
    --8<-- "recipes/rag_server/ask_question/python/main.py:ask"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/rag_server/ask_question/typescript/main.ts:ask"
    ```

=== "Go"

    ```go
    --8<-- "recipes/rag_server/ask_question/go/main.go:ask"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/rag_server/ask_question/curl/main.sh:ask"
    ```

## Handling Errors and Printing the Answer

The main part of each program calls the function from the previous step and
prints the question, the answer, and the token count. The program reports
any failure on `stderr`, whether the server was unreachable or replied with
an error, and then exits with a non-zero status. The Python program catches
`httpx.HTTPError`, the base class for connection failures and timeouts, as
well as its own error class for error replies; the TypeScript program
catches any rejected promise; the Go program returns each error from a
`run()` function to `main()`; and the curl script checks the exit status of
`curl` explicitly. The following tabs show the main part of each program:

=== "Python"

    ```python
    --8<-- "recipes/rag_server/ask_question/python/main.py:main"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/rag_server/ask_question/typescript/main.ts:main"
    ```

=== "Go"

    ```go
    --8<-- "recipes/rag_server/ask_question/go/main.go:main"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/rag_server/ask_question/curl/main.sh:main"
    ```

## Running the Example

The complete project for each language is available in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/rag_server/ask_question).
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
    --8<-- "recipes/rag_server/ask_question/python/main.py"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/rag_server/ask_question/typescript/main.ts"
    ```

=== "Go"

    ```go
    --8<-- "recipes/rag_server/ask_question/go/main.go"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/rag_server/ask_question/curl/main.sh"
    ```

## Next Steps

The following resources provide more information about the topics in this
recipe:

- The [Streaming an Answer](stream_answer.md) recipe shows how to display
  the answer as the model writes it.
- The [Showing the Sources of an Answer](include_sources.md) recipe shows how
  to list the documents that an answer came from.
- The
  [pgEdge RAG Server documentation](https://docs.pgedge.com/pgedge-rag-server/)
  describes the API and the pipeline configuration.
- The [Contributing a Recipe](../contributing.md) page explains how to add
  a recipe or a language to the cookbook.
