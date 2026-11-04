# Connecting to a Starfleet Database

This recipe shows how to connect to a pgEdge Starfleet database and run a
query. Because the recipe needs a database, the program creates one with
the code from the "Creating a Database and Waiting for It" recipe, reads
its connection details from the API, connects with a PostgreSQL driver,
prints the server version, and deletes the database again. Starfleet bills
for the database whilst it exists, so the program removes it on every
path out.

These examples are for the pgEdge Starfleet Managed API v1.

The name of the database, the number of status lines, and the version
string vary, so the output looks similar to the following:

```text
Region: us-east-2
Size: small
Created database cookbook-3f9a1c
Database status: creating
Database status: available
Database is available
Server version: PostgreSQL 18.1 on x86_64-pc-linux-gnu, compiled by gcc, 64-bit
Deleted database
```

## Preparing the Ingredients

You need a pgEdge Starfleet account and an API client with its client ID
and secret. Never put the client secret in
a file that you commit to version control, and never paste it into a
command line, because other users of the machine can read the command
lines of running processes. The programs in this recipe read the secret
from the environment and, for the curl script, pass it to curl on standard
input.

The programs use [psycopg](https://www.psycopg.org/psycopg3/) for Python, [node-postgres](https://node-postgres.com/) for TypeScript, and [pgx](https://github.com/jackc/pgx) for Go. The curl script needs `psql`, the PostgreSQL command line client, in addition to `curl` and `jq`. The following excerpts show the dependencies:

!!! warning "These examples create billable resources"

    Starfleet bills for a database from the moment that it becomes
    connectable until you request its deletion. The program deletes the
    database that it creates whether the example succeeds, fails, or is
    interrupted with Ctrl-C, and waits until the API no longer lists it.
    A program that is killed outright, with `kill -9` for instance, cannot
    clean up, so check your account for databases whose names start with
    `cookbook-` if you stop a run that way.

=== "Python"

    ```text
    --8<-- "recipes/starfleet/connect_database/python/requirements.txt:deps"
    ```

=== "TypeScript"

    ```json
    --8<-- "recipes/starfleet/connect_database/typescript/package.json"
    ```

=== "Go"

    ```text
    --8<-- "recipes/starfleet/connect_database/go/go.mod:deps"
    ```


## Importing the Libraries

The following code shows the imports and, for the curl script, the check for the tools that it needs:

=== "Python"

    ```python
    --8<-- "recipes/starfleet/connect_database/python/main.py:imports"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/starfleet/connect_database/typescript/main.ts:imports"
    ```

=== "Go"

    ```go
    --8<-- "recipes/starfleet/connect_database/go/main.go:imports"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/starfleet/connect_database/curl/main.sh:imports"
    ```


## Configuring the Program

The program reads the same environment variables as the other Starfleet recipes, and treats an empty variable as unset:

| Variable                  | Default                  | Description                          |
|---------------------------|--------------------------|--------------------------------------|
| `STARFLEET_CLIENT_ID`     | None                     | The client ID of your API client.    |
| `STARFLEET_CLIENT_SECRET` | None                     | The client secret of the client.     |
| `STARFLEET_API_URL`       | `https://api.pgedge.com` | The base URL of the Starfleet API.   |

The constants set how long to wait for the database, which can take several minutes to provision, and how often to check. The following code reads the settings:

=== "Python"

    ```python
    --8<-- "recipes/starfleet/connect_database/python/main.py:config"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/starfleet/connect_database/typescript/main.ts:config"
    ```

=== "Go"

    ```go
    --8<-- "recipes/starfleet/connect_database/go/main.go:config"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/starfleet/connect_database/curl/main.sh:config"
    ```


## Getting a Token

The program gets a token in the same way as the "Getting an Access Token" recipe:

=== "Python"

    ```python
    --8<-- "recipes/starfleet/connect_database/python/main.py:token"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/starfleet/connect_database/typescript/main.ts:token"
    ```

=== "Go"

    ```go
    --8<-- "recipes/starfleet/connect_database/go/main.go:token"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/starfleet/connect_database/curl/main.sh:token"
    ```


## Calling the Managed API

The `api` function sends an authenticated request and returns the decoded reply. The program also reacts to particular error statuses, so the error that the function raises carries the HTTP status:

=== "Python"

    ```python
    --8<-- "recipes/starfleet/connect_database/python/main.py:api"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/starfleet/connect_database/typescript/main.ts:api"
    ```

=== "Go"

    ```go
    --8<-- "recipes/starfleet/connect_database/go/main.go:api"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/starfleet/connect_database/curl/main.sh:api"
    ```


## Creating the Database and Waiting for It

The program creates its own database to connect to, with the code from the "Creating a Database and Waiting for It" recipe. It chooses the first region and the smallest size, and the following code makes the choice:

=== "Python"

    ```python
    --8<-- "recipes/starfleet/connect_database/python/main.py:placement"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/starfleet/connect_database/typescript/main.ts:placement"
    ```

=== "Go"

    ```go
    --8<-- "recipes/starfleet/connect_database/go/main.go:placement"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/starfleet/connect_database/curl/main.sh:placement"
    ```


## Creating the Database

The following code creates the database, which only your machine can reach, and names it with the `cookbook-` prefix:

=== "Python"

    ```python
    --8<-- "recipes/starfleet/connect_database/python/main.py:create"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/starfleet/connect_database/typescript/main.ts:create"
    ```

=== "Go"

    ```go
    --8<-- "recipes/starfleet/connect_database/go/main.go:create"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/starfleet/connect_database/curl/main.sh:create"
    ```


## Waiting for the Database

The following code polls the database until its status is `available`:

=== "Python"

    ```python
    --8<-- "recipes/starfleet/connect_database/python/main.py:wait"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/starfleet/connect_database/typescript/main.ts:wait"
    ```

=== "Go"

    ```go
    --8<-- "recipes/starfleet/connect_database/go/main.go:wait"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/starfleet/connect_database/curl/main.sh:wait"
    ```


## Reading the Connection Details

The description of an available database includes a `connection` object with the host name, the port, the database name, the user name, and the password of the `app` user. The details appear only once the database is available. The following code turns them into the settings that the driver needs. The password goes to the driver as a separate setting and not in a connection string, so that it never lands in a log line or in the process list:

=== "Python"

    ```python
    --8<-- "recipes/starfleet/connect_database/python/main.py:connection"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/starfleet/connect_database/typescript/main.ts:connection"
    ```

=== "Go"

    ```go
    --8<-- "recipes/starfleet/connect_database/go/main.go:connection"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/starfleet/connect_database/curl/main.sh:connection"
    ```


## Running the Query

The program connects with the driver for the language (psycopg for Python, node-postgres for TypeScript, pgx for Go, and `psql` for the curl script) and runs `SELECT version()`. The connection is encrypted. The certificate of a Starfleet database is not signed by a public authority, so the example does not verify it, so do not rely on the example for data that matters. A database can refuse connections for a short while after the API reports it as available, so the code makes up to six attempts, ten seconds apart. The following code runs the query:

=== "Python"

    ```python
    --8<-- "recipes/starfleet/connect_database/python/main.py:query"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/starfleet/connect_database/typescript/main.ts:query"
    ```

=== "Go"

    ```go
    --8<-- "recipes/starfleet/connect_database/go/main.go:query"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/starfleet/connect_database/curl/main.sh:query"
    ```


## Deleting the Database

The API refuses a delete with the status 409 whilst the database is still busy with another operation, such as being created, so the program retries until the API accepts the request. A delete only starts the teardown, so the program then polls until the API answers 404, which shows that the database has gone and that the billing has stopped. The following code deletes the database:

=== "Python"

    ```python
    --8<-- "recipes/starfleet/connect_database/python/main.py:delete"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/starfleet/connect_database/typescript/main.ts:delete"
    ```

=== "Go"

    ```go
    --8<-- "recipes/starfleet/connect_database/go/main.go:delete"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/starfleet/connect_database/curl/main.sh:delete"
    ```


## Running the Program

The `main` function runs the steps in order, and deletes the database in a `finally` block (a `defer` in Go, and a trap on `EXIT` in the curl script), so that the deletion happens when a step fails or when you press Ctrl-C. The program also turns the SIGTERM signal into a normal exit, so that `kill` cleans up as well. The cleanup ignores further interrupts, because a second Ctrl-C must not leave a billable database behind. The following code shows the function:

=== "Python"

    ```python
    --8<-- "recipes/starfleet/connect_database/python/main.py:main"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/starfleet/connect_database/typescript/main.ts:main"
    ```

=== "Go"

    ```go
    --8<-- "recipes/starfleet/connect_database/go/main.go:main"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/starfleet/connect_database/curl/main.sh:main"
    ```


## Running the Example

The complete project for each language is available in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/starfleet/connect_database).
Set the environment variables for your account, and then run the command
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
    ./main.sh
    ```

The run takes several minutes, almost all of it spent waiting for the
database to become available.

## Viewing the Complete Program

The following tabs show the complete program for each language:

=== "Python"

    ```python
    --8<-- "recipes/starfleet/connect_database/python/main.py"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/starfleet/connect_database/typescript/main.ts"
    ```

=== "Go"

    ```go
    --8<-- "recipes/starfleet/connect_database/go/main.go"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/starfleet/connect_database/curl/main.sh"
    ```

## Next Steps

The following resources provide more information about the topics in this
recipe:

- The "Creating a Database and Waiting for It" recipe explains the
  creation and deletion steps in more detail.
- The PostgreSQL documentation for
  [SSL support](https://www.postgresql.org/docs/current/libpq-ssl.html)
  explains the `sslmode` setting.
- The Starfleet documentation describes the IP allowlist, which controls
  who can reach a database.
