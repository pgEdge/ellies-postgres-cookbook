# Scheduling a Maintenance Blackout with the AI DBA Workbench API

This recipe shows how a program schedules a maintenance blackout for a
monitored server with the pgEdge AI DBA Workbench API, reads it back, stops it,
and deletes it. These examples are for AI DBA Workbench 1.0.0. Each step shows
the code in every supported language; selecting a language tab switches every
tab on the site to that language.

A blackout suppresses alert notifications for a server, a cluster, a group of
servers, or the whole estate while planned maintenance takes place. The example
program creates a blackout for one server that started a minute ago and ends in
an hour, reads it back, stops it early, and then deletes it. The program
deletes the blackout even when a step in the middle fails, so a failed run does
not leave alerts suppressed. The output has the following form:

```text
Created a blackout for the server (active: true)
Read the blackout back (active: true)
Stopped the blackout (active: false)
Deleted the blackout
```

## Preparing the Ingredients

The examples need a running Workbench server that monitors at least one
PostgreSQL server, and an API token for a user that may manage blackouts. The
Python example uses [httpx](https://www.python-httpx.org/), the TypeScript
example uses the `fetch` function that Node.js provides, and the Go example
uses the `net/http` package from the standard library. The curl example is a
bash script that uses [jq](https://jqlang.org/) to build the requests and read
the JSON replies. The following tabs show the dependency declaration from each
example project:

=== "Python"

    ```text
    --8<-- "recipes/ai_dba_workbench/blackouts/python/requirements.txt:deps"
    ```

=== "TypeScript"

    ```json
    --8<-- "recipes/ai_dba_workbench/blackouts/typescript/package.json"
    ```

=== "Go"

    ```text
    --8<-- "recipes/ai_dba_workbench/blackouts/go/go.mod:deps"
    ```

## Importing the Libraries

Each program begins by importing the modules that it uses. The following tabs
show the imports for each language:

=== "Python"

    ```python
    --8<-- "recipes/ai_dba_workbench/blackouts/python/main.py:imports"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/ai_dba_workbench/blackouts/typescript/main.ts:imports"
    ```

=== "Go"

    ```go
    --8<-- "recipes/ai_dba_workbench/blackouts/go/main.go:imports"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/ai_dba_workbench/blackouts/curl/main.sh:imports"
    ```

## Configuring the Connection

The examples read their settings from environment variables, and treat an empty
variable as unset. The following table describes the variables that the
examples read:

| Variable                  | Description                                   |
|---------------------------|-----------------------------------------------|
| `WORKBENCH_URL`           | The base URL; default `http://localhost:8080` |
| `WORKBENCH_TOKEN`         | An API token for the Workbench.               |
| `WORKBENCH_CONNECTION_ID` | The ID of the server to put in a blackout.    |

The [Authenticating](authenticate.md) recipe shows how to create an API token. The user that owns
the token needs the `manage_blackouts` administrative permission, which a
superuser has. The Workbench accepts an API token for the blackout endpoints,
so unlike the connection endpoints, they need no login. The following tabs show
how each program reads the settings and stops with an error when the token or
the connection ID is missing:

=== "Python"

    ```python
    --8<-- "recipes/ai_dba_workbench/blackouts/python/main.py:config"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/ai_dba_workbench/blackouts/typescript/main.ts:config"
    ```

=== "Go"

    ```go
    --8<-- "recipes/ai_dba_workbench/blackouts/go/main.go:config"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/ai_dba_workbench/blackouts/curl/main.sh:config"
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
    --8<-- "recipes/ai_dba_workbench/blackouts/python/main.py:request"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/ai_dba_workbench/blackouts/typescript/main.ts:request"
    ```

=== "Go"

    ```go
    --8<-- "recipes/ai_dba_workbench/blackouts/go/main.go:request"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/ai_dba_workbench/blackouts/curl/main.sh:request"
    ```

## Creating the Blackout

The program creates the blackout with `POST /api/v1/blackouts`. The `scope`
field is `estate`, `group`, `cluster`, or `server`, and a `server` blackout
also needs the `connection_id` of the server. The `start_time` and
`end_time` fields are timestamps in RFC 3339 format, and the end must come after
the start. The program starts the blackout a minute in the past, so that a small
difference between the clocks of the two machines cannot leave it inactive. The
reply is the new blackout, including its `id` and an `is_active` flag. The
following tabs show how each program creates the blackout:

=== "Python"

    ```python
    --8<-- "recipes/ai_dba_workbench/blackouts/python/main.py:create"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/ai_dba_workbench/blackouts/typescript/main.ts:create"
    ```

=== "Go"

    ```go
    --8<-- "recipes/ai_dba_workbench/blackouts/go/main.go:create"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/ai_dba_workbench/blackouts/curl/main.sh:create"
    ```

## Reading the Blackout

The program reads the blackout back with `GET /api/v1/blackouts/{id}`. The reply
has the same fields as the reply to the create call, and `is_active` is `true`
while the current time lies between the start and the end. The following tabs
show how each program reads the blackout:

=== "Python"

    ```python
    --8<-- "recipes/ai_dba_workbench/blackouts/python/main.py:read"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/ai_dba_workbench/blackouts/typescript/main.ts:read"
    ```

=== "Go"

    ```go
    --8<-- "recipes/ai_dba_workbench/blackouts/go/main.go:read"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/ai_dba_workbench/blackouts/curl/main.sh:read"
    ```

## Stopping the Blackout

The program ends the blackout early with `POST /api/v1/blackouts/{id}/stop`,
which sets the end time to the current time. The reply is the stopped blackout,
and `is_active` is now `false`. The Workbench keeps a stopped blackout as a
record, and a second stop request fails with a 404 status because the blackout
is no longer in progress. The following tabs show how each program stops the
blackout:

=== "Python"

    ```python
    --8<-- "recipes/ai_dba_workbench/blackouts/python/main.py:stop"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/ai_dba_workbench/blackouts/typescript/main.ts:stop"
    ```

=== "Go"

    ```go
    --8<-- "recipes/ai_dba_workbench/blackouts/go/main.go:stop"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/ai_dba_workbench/blackouts/curl/main.sh:stop"
    ```

## Deleting the Blackout

The program removes the record with `DELETE /api/v1/blackouts/{id}`. The reply is
a short status message. The following tabs show how each program deletes the
blackout:

=== "Python"

    ```python
    --8<-- "recipes/ai_dba_workbench/blackouts/python/main.py:delete"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/ai_dba_workbench/blackouts/typescript/main.ts:delete"
    ```

=== "Go"

    ```go
    --8<-- "recipes/ai_dba_workbench/blackouts/go/main.go:delete"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/ai_dba_workbench/blackouts/curl/main.sh:delete"
    ```

## Cleaning Up After a Failure

The main part of each program deletes the blackout on every path, so that a
failure after the create call does not leave alerts suppressed for the next
hour. The Python program uses a `finally` block, and the TypeScript program
keeps the delete step in a variable that runs after the `try` block. The Go
program returns the delete step from its `run()` function to `main()`, and the
curl script uses an `EXIT` trap. Each program reports a failure on `stderr` and
exits with a non-zero status. The following tabs show the main part of each
program:

=== "Python"

    ```python
    --8<-- "recipes/ai_dba_workbench/blackouts/python/main.py:main"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/ai_dba_workbench/blackouts/typescript/main.ts:main"
    ```

=== "Go"

    ```go
    --8<-- "recipes/ai_dba_workbench/blackouts/go/main.go:main"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/ai_dba_workbench/blackouts/curl/main.sh:main"
    ```

If a run is killed without a chance to clean up (with `kill -9`, for example),
the blackout stays in place until its end time. To end it sooner, send a `POST`
request to its `stop` path, using the ID that the create call printed or the
Workbench web interface shows.

## Running the Example

The complete project for each language is available in the [cookbook
repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/ai_dba_workbench/blackouts).
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
    --8<-- "recipes/ai_dba_workbench/blackouts/python/main.py"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/ai_dba_workbench/blackouts/typescript/main.ts"
    ```

=== "Go"

    ```go
    --8<-- "recipes/ai_dba_workbench/blackouts/go/main.go"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/ai_dba_workbench/blackouts/curl/main.sh"
    ```

## Next Steps

The following resources provide more information about the topics in this
recipe:

- The [Authenticating](authenticate.md) recipe explains how to create the API
  token that these examples use.
- The [Listing and Acknowledging Alerts](alerts.md) recipe shows the alerts
  that a blackout suppresses.
- The AI DBA Workbench [blackouts
  guide](https://github.com/pgEdge/ai-dba-workbench/blob/v1.0.0/docs/user-guide/blackouts.md)
  describes how blackouts affect alerting.
- The AI DBA Workbench [API
  reference](https://github.com/pgEdge/ai-dba-workbench/blob/v1.0.0/docs/admin-guide/api/reference.md)
  describes every endpoint.
