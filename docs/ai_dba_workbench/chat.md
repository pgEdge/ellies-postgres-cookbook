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

The examples need a running Workbench server that has an LLM provider
configured, and an API token for a user that may use the chat feature. The
Python example uses [httpx](https://www.python-httpx.org/), the TypeScript
example uses the `fetch` function that Node.js provides, and the Go example
uses the `net/http` package from the standard library. The curl example is a
bash script that uses [jq](https://jqlang.org/) to build the requests and read
the JSON replies. The following tabs show the dependency declaration from each
example project:

=== "Python"

    ```text
    --8<-- "recipes/ai_dba_workbench/chat/python/requirements.txt:deps"
    ```

=== "TypeScript"

    ```json
    --8<-- "recipes/ai_dba_workbench/chat/typescript/package.json"
    ```

=== "Go"

    ```text
    --8<-- "recipes/ai_dba_workbench/chat/go/go.mod:deps"
    ```

## Importing the Libraries

Each program begins by importing the modules that it uses. The following tabs
show the imports for each language:

=== "Python"

    ```python
    --8<-- "recipes/ai_dba_workbench/chat/python/main.py:imports"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/ai_dba_workbench/chat/typescript/main.ts:imports"
    ```

=== "Go"

    ```go
    --8<-- "recipes/ai_dba_workbench/chat/go/main.go:imports"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/ai_dba_workbench/chat/curl/main.sh:imports"
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
    --8<-- "recipes/ai_dba_workbench/chat/python/main.py:config"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/ai_dba_workbench/chat/typescript/main.ts:config"
    ```

=== "Go"

    ```go
    --8<-- "recipes/ai_dba_workbench/chat/go/main.go:config"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/ai_dba_workbench/chat/curl/main.sh:config"
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
    --8<-- "recipes/ai_dba_workbench/chat/python/main.py:request"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/ai_dba_workbench/chat/typescript/main.ts:request"
    ```

=== "Go"

    ```go
    --8<-- "recipes/ai_dba_workbench/chat/go/main.go:request"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/ai_dba_workbench/chat/curl/main.sh:request"
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
    --8<-- "recipes/ai_dba_workbench/chat/python/main.py:providers"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/ai_dba_workbench/chat/typescript/main.ts:providers"
    ```

=== "Go"

    ```go
    --8<-- "recipes/ai_dba_workbench/chat/go/main.go:providers"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/ai_dba_workbench/chat/curl/main.sh:providers"
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
    --8<-- "recipes/ai_dba_workbench/chat/python/main.py:chat"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/ai_dba_workbench/chat/typescript/main.ts:chat"
    ```

=== "Go"

    ```go
    --8<-- "recipes/ai_dba_workbench/chat/go/main.go:chat"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/ai_dba_workbench/chat/curl/main.sh:chat"
    ```

## Holding a Conversation

The main part of each program prints the default provider, sends the first
question, and then sends a follow-up question together with the first question
and the model's answer. It reports a failure on `stderr` and exits with a
non-zero status. The following tabs show the main part of each program:

=== "Python"

    ```python
    --8<-- "recipes/ai_dba_workbench/chat/python/main.py:main"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/ai_dba_workbench/chat/typescript/main.ts:main"
    ```

=== "Go"

    ```go
    --8<-- "recipes/ai_dba_workbench/chat/go/main.go:main"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/ai_dba_workbench/chat/curl/main.sh:main"
    ```

## Running the Example

The complete project for each language is available in the [cookbook
repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/ai_dba_workbench/chat).
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
    --8<-- "recipes/ai_dba_workbench/chat/python/main.py"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/ai_dba_workbench/chat/typescript/main.ts"
    ```

=== "Go"

    ```go
    --8<-- "recipes/ai_dba_workbench/chat/go/main.go"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/ai_dba_workbench/chat/curl/main.sh"
    ```

## Next Steps

The following resources provide more information about the topics in this
recipe:

- The [Authenticating with the AI DBA Workbench API](authenticate.md) recipe
  explains how to create the API token that these examples use.
- The [Calling AI DBA Workbench MCP Tools](mcp_tools.md) recipe shows how to
  run queries against a monitored server from a program.
- The AI DBA Workbench [API
  reference](https://github.com/pgEdge/ai-dba-workbench/blob/v1.0.0/docs/admin-guide/api/reference.md)
  describes every endpoint.
