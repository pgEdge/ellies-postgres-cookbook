# Registering a Server with the AI DBA Workbench API

This recipe shows how a program registers a PostgreSQL server for monitoring
with the pgEdge AI DBA Workbench API, finds it in the list of connections, and
deletes it again. These examples are for AI DBA Workbench 1.0.0. Each step
shows the code in every supported language; selecting a language tab switches
every tab on the site to that language.

The example program registers a second connection to the same PostgreSQL server
that an existing connection monitors, so that it needs no other server. It logs
in, reads the address of the existing connection, registers a new connection
called `cookbook-register-server`, checks that the new connection appears in
the list, and then deletes it. The program deletes the connection even when a
step in the middle fails, so a failed run does not leave a monitored server
behind. The output has the following form:

```text
Registered the server 'cookbook-register-server'
Found 'cookbook-register-server' in the list (monitored: true)
Deleted the connection
The connection is no longer in the list
```

## Preparing the Ingredients

The examples need a running Workbench server, a user that can log in, and the
ID of an existing connection. The Python example uses
[httpx](https://www.python-httpx.org/), the TypeScript example uses the `fetch`
function that Node.js provides, and the Go example uses the `net/http` package
from the standard library. The curl example is a bash script that uses
[jq](https://jqlang.org/) to read the JSON replies. The following tabs show the
dependency declaration from each example project:

=== "Python"

    ```text
    --8<-- "recipes/ai_dba_workbench/register_server/python/requirements.txt:deps"
    ```

=== "TypeScript"

    ```json
    --8<-- "recipes/ai_dba_workbench/register_server/typescript/package.json"
    ```

=== "Go"

    ```text
    --8<-- "recipes/ai_dba_workbench/register_server/go/go.mod:deps"
    ```

## Importing the Libraries

Each program begins by importing the modules that it uses. The following tabs
show the imports for each language:

=== "Python"

    ```python
    --8<-- "recipes/ai_dba_workbench/register_server/python/main.py:imports"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/ai_dba_workbench/register_server/typescript/main.ts:imports"
    ```

=== "Go"

    ```go
    --8<-- "recipes/ai_dba_workbench/register_server/go/main.go:imports"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/ai_dba_workbench/register_server/curl/main.sh:imports"
    ```

## Configuring the Connection

The examples read their settings from environment variables, and treat an empty
variable as unset. The following table describes the variables that the
examples read:

| Variable                  | Description                                   |
|---------------------------|-----------------------------------------------|
| `WORKBENCH_URL`           | The base URL; default `http://localhost:8080` |
| `WORKBENCH_USERNAME`      | The user to log in as.                        |
| `WORKBENCH_PASSWORD`      | The password of that user.                    |
| `WORKBENCH_CONNECTION_ID` | An existing connection to copy.               |
| `PGPASSWORD`              | The new connection password (optional).       |

The new connection uses the password in `PGPASSWORD`, which is the variable
that `psql` reads, so the example works against the same server as the other
recipes. The Workbench 1.0.0 server rejects a connection with an empty
password, even when the monitored server uses trust authentication and ignores
the password. When `PGPASSWORD` is not set, the examples send a placeholder
password instead.

!!! note

    Production applications should not store passwords in environment
    variables or source code. A secrets manager provides a safer
    alternative.

The following tabs show how each program reads the settings and stops with an
error when a required variable is missing:

=== "Python"

    ```python
    --8<-- "recipes/ai_dba_workbench/register_server/python/main.py:config"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/ai_dba_workbench/register_server/typescript/main.ts:config"
    ```

=== "Go"

    ```go
    --8<-- "recipes/ai_dba_workbench/register_server/go/main.go:config"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/ai_dba_workbench/register_server/curl/main.sh:config"
    ```

## Sending Requests

Every call to the API goes through one helper function. The function adds the
`/api/v1` prefix to the path, sends the token as a `Bearer` credential in the
`Authorization` header, and sets a timeout so that a stalled server cannot hang
the program. When the server rejects a request, the function raises an error
that includes the status code and the message from the server. The following
tabs show the helper function from each program:

=== "Python"

    ```python
    --8<-- "recipes/ai_dba_workbench/register_server/python/main.py:request"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/ai_dba_workbench/register_server/typescript/main.ts:request"
    ```

=== "Go"

    ```go
    --8<-- "recipes/ai_dba_workbench/register_server/go/main.go:request"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/ai_dba_workbench/register_server/curl/main.sh:request"
    ```

## Logging In

The Workbench accepts only a session token, not an API token, for requests that
create, change, or delete a connection. The program sends the user name and the
password to `POST /api/v1/auth/login`, and reads the session token from the
`session_token` cookie in the reply. The following tabs show how each program
logs in:

=== "Python"

    ```python
    --8<-- "recipes/ai_dba_workbench/register_server/python/main.py:login"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/ai_dba_workbench/register_server/typescript/main.ts:login"
    ```

=== "Go"

    ```go
    --8<-- "recipes/ai_dba_workbench/register_server/go/main.go:login"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/ai_dba_workbench/register_server/curl/main.sh:login"
    ```

## Reading the Existing Connection

The new connection needs the host, the port, the database, and the user of the
server to monitor. The program reads them from the existing connection with
`GET /api/v1/connections/{id}`, so the example works against any server that
the Workbench already monitors. The following tabs show how each program reads
the connection:

=== "Python"

    ```python
    --8<-- "recipes/ai_dba_workbench/register_server/python/main.py:lookup"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/ai_dba_workbench/register_server/typescript/main.ts:lookup"
    ```

=== "Go"

    ```go
    --8<-- "recipes/ai_dba_workbench/register_server/go/main.go:lookup"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/ai_dba_workbench/register_server/curl/main.sh:lookup"
    ```

## Registering the Server

The program registers the server with `POST /api/v1/connections`. The request
copies the address from the existing connection, and adds a name, a
description, the password, and two flags: `is_monitored` makes the collector
monitor the server, and `is_shared` set to `false` does not share the
connection with other users. The Workbench 1.0.0 server rejects a request
without a description. The reply contains the ID of the new connection. The
following tabs show how each program registers the server:

=== "Python"

    ```python
    --8<-- "recipes/ai_dba_workbench/register_server/python/main.py:register"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/ai_dba_workbench/register_server/typescript/main.ts:register"
    ```

=== "Go"

    ```go
    --8<-- "recipes/ai_dba_workbench/register_server/go/main.go:register"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/ai_dba_workbench/register_server/curl/main.sh:register"
    ```

## Listing the Connections

The program lists the connections with `GET /api/v1/connections`, and looks for
the new connection by its name. The program runs this step twice: once to
confirm that the registration worked, and once after the delete to confirm that
the connection has gone. The following tabs show how each program finds a
connection in the list:

=== "Python"

    ```python
    --8<-- "recipes/ai_dba_workbench/register_server/python/main.py:list"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/ai_dba_workbench/register_server/typescript/main.ts:list"
    ```

=== "Go"

    ```go
    --8<-- "recipes/ai_dba_workbench/register_server/go/main.go:list"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/ai_dba_workbench/register_server/curl/main.sh:list"
    ```

## Deleting the Connection

The program deletes the connection with `DELETE /api/v1/connections/{id}`,
using the ID from the reply to the create call. The following tabs show how
each program deletes the connection:

=== "Python"

    ```python
    --8<-- "recipes/ai_dba_workbench/register_server/python/main.py:delete"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/ai_dba_workbench/register_server/typescript/main.ts:delete"
    ```

=== "Go"

    ```go
    --8<-- "recipes/ai_dba_workbench/register_server/go/main.go:delete"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/ai_dba_workbench/register_server/curl/main.sh:delete"
    ```

## Cleaning Up After a Failure

The main part of each program deletes the connection on every path, so that a
failure after the registration does not leave a monitored server behind. The
Python program uses a `finally` block, and the TypeScript program keeps the
delete step in a variable that runs after the `try` block. The Go program
returns the delete step from its `run()` function to `main()`, and the curl
script uses an `EXIT` trap. Each program reports a failure on `stderr` and
exits with a non-zero status. The following tabs show the main part of each
program:

=== "Python"

    ```python
    --8<-- "recipes/ai_dba_workbench/register_server/python/main.py:main"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/ai_dba_workbench/register_server/typescript/main.ts:main"
    ```

=== "Go"

    ```go
    --8<-- "recipes/ai_dba_workbench/register_server/go/main.go:main"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/ai_dba_workbench/register_server/curl/main.sh:main"
    ```

## Running the Example

The complete project for each language is available in the [cookbook
repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/ai_dba_workbench/register_server).
Set `WORKBENCH_URL`, `WORKBENCH_USERNAME`, `WORKBENCH_PASSWORD`, and
`WORKBENCH_CONNECTION_ID` for your server, and then run the command for your
language from the corresponding project directory. The following tabs show the
commands that build and run each example:

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
    --8<-- "recipes/ai_dba_workbench/register_server/python/main.py"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/ai_dba_workbench/register_server/typescript/main.ts"
    ```

=== "Go"

    ```go
    --8<-- "recipes/ai_dba_workbench/register_server/go/main.go"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/ai_dba_workbench/register_server/curl/main.sh"
    ```

## Next Steps

The following resources provide more information about the topics in this
recipe:

- The [Authenticating](authenticate.md) recipe explains the two kinds of token
  that the Workbench issues.
- The [Listing and Acknowledging Alerts](alerts.md) recipe shows how to work
  with the alerts that a monitored server raises.
- The AI DBA Workbench [API
  reference](https://github.com/pgEdge/ai-dba-workbench/blob/v1.0.0/docs/admin-guide/api/reference.md)
  describes every endpoint.