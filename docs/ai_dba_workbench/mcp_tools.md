# Calling AI DBA Workbench MCP Tools

This recipe shows how a program calls the tools that the pgEdge AI DBA
Workbench offers through its Model Context Protocol (MCP) endpoint. These
examples are for AI DBA Workbench 1.0.0. Each step shows the code in every
supported language; selecting a language tab switches every tab on the site to
that language.

MCP is a protocol in which a client lists the tools that a server offers and
then calls them, and it is built on JSON-RPC 2.0 over HTTP. The Workbench
serves it at `/mcp/v1`, and the same tools are available to any MCP client,
such as an AI assistant. The example program introduces itself to the server,
lists the tools, runs a read-only query with the `query_database` tool, and
plans another query with the `execute_explain` tool. The output has the
following form:

```text
Server: pgedge-postgres-mcp 1.0.0
query_database requires: query
execute_explain requires: query
Columns: greeting, answer
Row: Hello from the Workbench, 42
Plan starts with: Result
```

## Preparing the Ingredients

The `scripts/start_workbench.sh` script in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook)
starts a test Workbench in Docker. The script creates a `cookbook` user and an
API token, registers a test PostgreSQL server as a monitored connection, and
prints the `WORKBENCH_URL`, `WORKBENCH_TOKEN`, `WORKBENCH_USERNAME`,
`WORKBENCH_PASSWORD`, and `WORKBENCH_CONNECTION_ID` values that the examples
read from the environment.

The examples need a running Workbench server that monitors at least one
PostgreSQL server, and an API token for a user that may use the tools. The
Python example uses [httpx](https://www.python-httpx.org/), the TypeScript
example uses the `fetch` function that Node.js provides, and the Go example
uses the `net/http` package from the standard library. The curl example is a
bash script that uses [jq](https://jqlang.org/) to build the requests and read
the JSON replies. The following tabs show the dependency declaration from each
example project:

=== "Python"

    ```text
    --8<-- "recipes/ai_dba_workbench/mcp_tools/python/requirements.txt:deps"
    ```

=== "TypeScript"

    ```json
    --8<-- "recipes/ai_dba_workbench/mcp_tools/typescript/package.json"
    ```

=== "Go"

    ```text
    --8<-- "recipes/ai_dba_workbench/mcp_tools/go/go.mod:deps"
    ```

## Importing the Libraries

Each program begins by importing the modules that it uses. The following tabs
show the imports for each language:

=== "Python"

    ```python
    --8<-- "recipes/ai_dba_workbench/mcp_tools/python/main.py:imports"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/ai_dba_workbench/mcp_tools/typescript/main.ts:imports"
    ```

=== "Go"

    ```go
    --8<-- "recipes/ai_dba_workbench/mcp_tools/go/main.go:imports"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/ai_dba_workbench/mcp_tools/curl/main.sh:imports"
    ```

## Configuring the Connection

The examples read their settings from environment variables, and treat an empty
variable as unset. The following table describes the variables that the
examples read:

| Variable                  | Description                                   |
|---------------------------|-----------------------------------------------|
| `WORKBENCH_URL`           | The base URL; default `http://localhost:8080` |
| `WORKBENCH_TOKEN`         | An API token for the Workbench.               |
| `WORKBENCH_CONNECTION_ID` | The ID of the server to query.                |

The [Authenticating with the AI DBA Workbench API](authenticate.md) recipe
shows how to create an API token. The MCP endpoint accepts the token as a
`Bearer` credential and answers a request without one with a 401 status. The
following tabs show how each program reads the settings and stops with an error
when the token or the connection ID is missing:

=== "Python"

    ```python
    --8<-- "recipes/ai_dba_workbench/mcp_tools/python/main.py:config"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/ai_dba_workbench/mcp_tools/typescript/main.ts:config"
    ```

=== "Go"

    ```go
    --8<-- "recipes/ai_dba_workbench/mcp_tools/go/main.go:config"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/ai_dba_workbench/mcp_tools/curl/main.sh:config"
    ```

## Sending JSON-RPC Requests

Every MCP call is a `POST` request to `/mcp/v1` with a JSON-RPC body that holds
the `jsonrpc` version, an `id`, a `method`, and its `params`. The Workbench
keeps no session between requests, so the requests carry nothing but the token.
The server answers a JSON-RPC error with a 200 HTTP status and an `error`
member in the body, so the helper function checks for both kinds of failure
before it returns the `result` member. The following tabs show the helper
function from each program:

=== "Python"

    ```python
    --8<-- "recipes/ai_dba_workbench/mcp_tools/python/main.py:rpc"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/ai_dba_workbench/mcp_tools/typescript/main.ts:rpc"
    ```

=== "Go"

    ```go
    --8<-- "recipes/ai_dba_workbench/mcp_tools/go/main.go:rpc"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/ai_dba_workbench/mcp_tools/curl/main.sh:rpc"
    ```

## Introducing the Client

The `initialize` method tells the server which protocol version the client
speaks, and the reply names the server and its version. The Workbench does not
require this step, because it keeps no session, but a well-behaved MCP client
sends it first. The following tabs show how each program calls the method and
prints the name and version of the server:

=== "Python"

    ```python
    --8<-- "recipes/ai_dba_workbench/mcp_tools/python/main.py:initialize"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/ai_dba_workbench/mcp_tools/typescript/main.ts:initialize"
    ```

=== "Go"

    ```go
    --8<-- "recipes/ai_dba_workbench/mcp_tools/go/main.go:initialize"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/ai_dba_workbench/mcp_tools/curl/main.sh:initialize"
    ```

## Listing the Tools

The `tools/list` method returns every tool that the server offers, and each
tool has a `name`, a `description`, and an `inputSchema` in JSON Schema form.
The Workbench lists its tools in no fixed order, so the program looks the two
tools that it needs up by name, stops with an error if either is missing, and
prints the arguments that each one requires from the `required` member of its
schema. The following tabs show how each program lists the tools:

=== "Python"

    ```python
    --8<-- "recipes/ai_dba_workbench/mcp_tools/python/main.py:list_tools"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/ai_dba_workbench/mcp_tools/typescript/main.ts:list_tools"
    ```

=== "Go"

    ```go
    --8<-- "recipes/ai_dba_workbench/mcp_tools/go/main.go:list_tools"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/ai_dba_workbench/mcp_tools/curl/main.sh:list_tools"
    ```

## Calling a Tool

The `tools/call` method runs a tool, and its `params` hold the `name` of the
tool and its `arguments`. The reply holds a `content` list, and the text of the
tool's output is in the first item. A tool that fails returns an ordinary
result with `isError` set to `true`, so the helper function checks that flag
and raises an error with the text of the reply. The following tabs show the
helper function from each program:

=== "Python"

    ```python
    --8<-- "recipes/ai_dba_workbench/mcp_tools/python/main.py:call_tool"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/ai_dba_workbench/mcp_tools/typescript/main.ts:call_tool"
    ```

=== "Go"

    ```go
    --8<-- "recipes/ai_dba_workbench/mcp_tools/go/main.go:call_tool"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/ai_dba_workbench/mcp_tools/curl/main.sh:call_tool"
    ```

## Running a Query

The `query_database` tool runs a read-only query against a monitored server,
and it takes the `connection_id` of the server and the `query` to run. The
reply is text rather than JSON: it names the database, repeats the query, and
then has a line that starts with `Results` followed by a row of tab-separated
column names and the rows of data. The program prints only the part after the
`Results` line, with the tabs replaced by commas. The parsing of the text
depends on the layout of the output in Workbench 1.0.0, so check it again after
an upgrade. The following tabs show how each program runs the query:

=== "Python"

    ```python
    --8<-- "recipes/ai_dba_workbench/mcp_tools/python/main.py:query_database"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/ai_dba_workbench/mcp_tools/typescript/main.ts:query_database"
    ```

=== "Go"

    ```go
    --8<-- "recipes/ai_dba_workbench/mcp_tools/go/main.go:query_database"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/ai_dba_workbench/mcp_tools/curl/main.sh:query_database"
    ```

## Planning a Query

The `execute_explain` tool returns the execution plan for a query. Setting
`analyze` to `false` plans the query without running it, whereas `true` runs
the query to measure it. Do not also set `buffers` to `false`, because the
Workbench 1.0.0 then sends `EXPLAIN ()` to PostgreSQL, which is a syntax error;
the example leaves `buffers` at its default. The plan follows a line of equals
signs in the reply, and the program prints the type of the first plan node. The
following tabs show how each program plans the query:

=== "Python"

    ```python
    --8<-- "recipes/ai_dba_workbench/mcp_tools/python/main.py:execute_explain"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/ai_dba_workbench/mcp_tools/typescript/main.ts:execute_explain"
    ```

=== "Go"

    ```go
    --8<-- "recipes/ai_dba_workbench/mcp_tools/go/main.go:execute_explain"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/ai_dba_workbench/mcp_tools/curl/main.sh:execute_explain"
    ```

## Putting It Together

The main part of each program reads the settings and calls the four steps in
order. It reports a failure on `stderr` and exits with a non-zero status. The
following tabs show the main part of each program:

=== "Python"

    ```python
    --8<-- "recipes/ai_dba_workbench/mcp_tools/python/main.py:main"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/ai_dba_workbench/mcp_tools/typescript/main.ts:main"
    ```

=== "Go"

    ```go
    --8<-- "recipes/ai_dba_workbench/mcp_tools/go/main.go:main"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/ai_dba_workbench/mcp_tools/curl/main.sh:main"
    ```

## Running the Example

The complete project for each language is available in the [cookbook
repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/ai_dba_workbench/mcp_tools).
Set `WORKBENCH_URL`, `WORKBENCH_TOKEN`, and `WORKBENCH_CONNECTION_ID` for your
server, and then run the command for your language from the corresponding
project directory. The following tabs show the commands that build and run each
example:

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
    --8<-- "recipes/ai_dba_workbench/mcp_tools/python/main.py"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/ai_dba_workbench/mcp_tools/typescript/main.ts"
    ```

=== "Go"

    ```go
    --8<-- "recipes/ai_dba_workbench/mcp_tools/go/main.go"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/ai_dba_workbench/mcp_tools/curl/main.sh"
    ```

## Next Steps

The following resources provide more information about the topics in this
recipe:

- The [Authenticating with the AI DBA Workbench API](authenticate.md) recipe
  explains how to create the API token that these examples use.
- The [Registering a Server with the AI DBA Workbench API](register_server.md)
  recipe shows how to add the server that the tools query.
- The AI DBA Workbench
  [documentation](https://github.com/pgEdge/ai-dba-workbench/tree/v1.0.0/docs)
  describes the full set of tools.
