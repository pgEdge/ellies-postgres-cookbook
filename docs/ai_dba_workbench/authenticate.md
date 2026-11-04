# Authenticating with the AI DBA Workbench API

This recipe shows how a program logs in to the pgEdge AI DBA Workbench API,
checks who it is logged in as, and creates an API token for later use. These
examples are for AI DBA Workbench 1.0.0. Each step shows the code in every
supported language; selecting a language tab switches every tab on the site to
that language.

The example program logs in with a user name and a password, which gives it a
session token. It asks the server which user the session token belongs to, and
then creates an API token that expires after an hour. It uses the new API token
to ask the same question, and finally deletes the token so that the example
leaves nothing behind. The program never prints either token; the output has
the following form:

```text
Logged in with a session token
Session token belongs to cookbook (superuser: true)
Created the API token 'cookbook-authenticate'
API token belongs to cookbook (superuser: true)
Deleted the API token
```

## Preparing the Ingredients

The `scripts/start_workbench.sh` script in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook)
starts a test Workbench in Docker. The script creates a `cookbook` user and an
API token, registers a test PostgreSQL server as a monitored connection, and
prints the `WORKBENCH_URL`, `WORKBENCH_TOKEN`, `WORKBENCH_USERNAME`,
`WORKBENCH_PASSWORD`, and `WORKBENCH_CONNECTION_ID` values that the examples
read from the environment.

The examples need a running Workbench server and a user that can log in. The
Python example uses [httpx](https://www.python-httpx.org/), the TypeScript
example uses the `fetch` function that Node.js provides, and the Go example
uses the `net/http` package from the standard library. The curl example is a
bash script that uses [jq](https://jqlang.org/) to read the JSON replies. The
following tabs show the dependency declaration from each example project:

=== "Python"

    ```text
    --8<-- "recipes/ai_dba_workbench/authenticate/python/requirements.txt:deps"
    ```

=== "TypeScript"

    ```json
    --8<-- "recipes/ai_dba_workbench/authenticate/typescript/package.json"
    ```

=== "Go"

    ```text
    --8<-- "recipes/ai_dba_workbench/authenticate/go/go.mod:deps"
    ```

The Go project has no dependencies, so its `go.mod` file names only the version
of Go, and the TypeScript project depends on the compiler and the Node.js type
definitions only.

## Importing the Libraries

Each program begins by importing the modules that it uses. The following tabs
show the imports for each language:

=== "Python"

    ```python
    --8<-- "recipes/ai_dba_workbench/authenticate/python/main.py:imports"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/ai_dba_workbench/authenticate/typescript/main.ts:imports"
    ```

=== "Go"

    ```go
    --8<-- "recipes/ai_dba_workbench/authenticate/go/main.go:imports"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/ai_dba_workbench/authenticate/curl/main.sh:imports"
    ```

## Configuring the Connection

The examples read their settings from environment variables, and treat an empty
variable as unset. The following table describes the variables that the
examples read:

| Variable             | Default                 | Description          |
|----------------------|-------------------------|----------------------|
| `WORKBENCH_URL`      | `http://localhost:8080` | The server base URL. |
| `WORKBENCH_USERNAME` | None                    | The user name.       |
| `WORKBENCH_PASSWORD` | None                    | The password.        |

!!! note

    Production applications should not store passwords in environment
    variables or source code. A secrets manager provides a safer
    alternative.

The following tabs show how each program reads the settings and stops with an
error when the user name or the password is missing:

=== "Python"

    ```python
    --8<-- "recipes/ai_dba_workbench/authenticate/python/main.py:config"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/ai_dba_workbench/authenticate/typescript/main.ts:config"
    ```

=== "Go"

    ```go
    --8<-- "recipes/ai_dba_workbench/authenticate/go/main.go:config"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/ai_dba_workbench/authenticate/curl/main.sh:config"
    ```

## Sending Requests

Every call to the API goes through one helper function. The function adds the
`/api/v1` prefix to the path, sends the token as a `Bearer` credential in the
`Authorization` header when it has one, and sets a timeout so that a stalled
server cannot hang the program. When the server rejects a request, the function
raises an error that includes the status code and the message from the server,
which is more useful than the status code alone. The following tabs show the
helper function from each program:

=== "Python"

    ```python
    --8<-- "recipes/ai_dba_workbench/authenticate/python/main.py:request"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/ai_dba_workbench/authenticate/typescript/main.ts:request"
    ```

=== "Go"

    ```go
    --8<-- "recipes/ai_dba_workbench/authenticate/go/main.go:request"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/ai_dba_workbench/authenticate/curl/main.sh:request"
    ```

## Logging In

The program sends the user name and the password to `POST /api/v1/auth/login`
as a JSON object. The server sets the session token in a cookie named
`session_token` instead of returning it in the body of the reply, so each
program reads the token from the cookie. The program sends the session token in
the `Authorization` header, as it would an API token, which keeps the rest of
the program the same for both. The following tabs show how each program logs
in:

=== "Python"

    ```python
    --8<-- "recipes/ai_dba_workbench/authenticate/python/main.py:login"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/ai_dba_workbench/authenticate/typescript/main.ts:login"
    ```

=== "Go"

    ```go
    --8<-- "recipes/ai_dba_workbench/authenticate/go/main.go:login"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/ai_dba_workbench/authenticate/curl/main.sh:login"
    ```

## Checking the User

The `GET /api/v1/user/info` call returns the user that a token belongs to, and
whether that user is a superuser. The same call works with a session token and
with an API token, so the program uses it to check each of them. The following
tabs show how each program reads the reply:

=== "Python"

    ```python
    --8<-- "recipes/ai_dba_workbench/authenticate/python/main.py:user_info"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/ai_dba_workbench/authenticate/typescript/main.ts:user_info"
    ```

=== "Go"

    ```go
    --8<-- "recipes/ai_dba_workbench/authenticate/go/main.go:user_info"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/ai_dba_workbench/authenticate/curl/main.sh:user_info"
    ```

## Creating an API Token

An API token suits a program that runs without a person present. The program
sends `POST /api/v1/rbac/tokens` with the owner, a note that says what the
token is for, and a lifetime of one hour. The server returns the value of the
token only once, in the reply to this call, so a program that needs the token
later must store it safely at this point. The following tabs show how each
program creates the token:

=== "Python"

    ```python
    --8<-- "recipes/ai_dba_workbench/authenticate/python/main.py:create_token"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/ai_dba_workbench/authenticate/typescript/main.ts:create_token"
    ```

=== "Go"

    ```go
    --8<-- "recipes/ai_dba_workbench/authenticate/go/main.go:create_token"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/ai_dba_workbench/authenticate/curl/main.sh:create_token"
    ```

## Deleting the Token

The program deletes the token with `DELETE /api/v1/rbac/tokens/{id}`, using the
ID from the reply to the create call. Each program runs the delete step even
when an earlier step fails. The Python program uses a `finally` block, the
TypeScript program keeps the step in a variable that runs after the `try`
block, the Go program returns the step from its `run()` function to `main()`,
and the curl script uses an `EXIT` trap. The following tabs show how each
program deletes the token:

=== "Python"

    ```python
    --8<-- "recipes/ai_dba_workbench/authenticate/python/main.py:delete_token"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/ai_dba_workbench/authenticate/typescript/main.ts:delete_token"
    ```

=== "Go"

    ```go
    --8<-- "recipes/ai_dba_workbench/authenticate/go/main.go:delete_token"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/ai_dba_workbench/authenticate/curl/main.sh:delete_token"
    ```

## Putting It Together

The main part of each program logs in, checks the session token, creates the
API token, checks the API token, and then deletes it. The program reports any
failure on `stderr` and exits with a non-zero status. The following tabs show
the main part of each program:

=== "Python"

    ```python
    --8<-- "recipes/ai_dba_workbench/authenticate/python/main.py:main"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/ai_dba_workbench/authenticate/typescript/main.ts:main"
    ```

=== "Go"

    ```go
    --8<-- "recipes/ai_dba_workbench/authenticate/go/main.go:main"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/ai_dba_workbench/authenticate/curl/main.sh:main"
    ```

## Running the Example

The complete project for each language is available in the [cookbook
repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/ai_dba_workbench/authenticate).
Set `WORKBENCH_URL`, `WORKBENCH_USERNAME`, and `WORKBENCH_PASSWORD` for your
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
    --8<-- "recipes/ai_dba_workbench/authenticate/python/main.py"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/ai_dba_workbench/authenticate/typescript/main.ts"
    ```

=== "Go"

    ```go
    --8<-- "recipes/ai_dba_workbench/authenticate/go/main.go"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/ai_dba_workbench/authenticate/curl/main.sh"
    ```

## Next Steps

The following resources provide more information about the topics in this
recipe:

- The [Registering a Server](register_server.md) recipe uses the session token
  from this recipe to register a server for monitoring.
- The [Listing and Acknowledging Alerts](alerts.md) recipe uses an API token to
  manage alerts.
- The AI DBA Workbench [API
  reference](https://github.com/pgEdge/ai-dba-workbench/blob/v1.0.0/docs/admin-guide/api/reference.md)
  describes every endpoint.