# Creating a Branch for a Test Run

This recipe shows how to create a copy-on-write branch of a pgEdge Starfleet
database for a test run, wait for it, connect to the branch and run a query,
and delete it. Because the recipe needs a database to branch, the program
creates one with the code from the "Creating a Database and Waiting for It"
recipe, and deletes the branch and then the database at the end. Starfleet
bills for each of them whilst it exists, so the program removes both on every
path out.

These examples are for the pgEdge Starfleet Managed API v1.

The names of the resources, the number of status lines, and the version strings
vary, so the output looks similar to the following:

```text
Region: us-east-2
Size: small
Created database cookbook-3f9a1c
Database status: creating
Database status: available
Database is available
Created branch cookbook-3f9a1c-branch
Branch status: creating
Branch status: available
Branch is available
Branch server version: PostgreSQL 18.1 on x86_64-pc-linux-gnu, 64-bit
Deleted branch
Deleted database
```

## Preparing the Ingredients

You need a pgEdge Starfleet account and an API client with its client ID and
secret. Never put the client secret in a file that you commit to version
control, and never paste it into a command line, because other users of the
machine can read the command lines of running processes. The programs in this
recipe read the secret from the environment and, for the curl script, pass it
to curl on standard input.

The following warning describes what the example creates and what it does to
clean up:

!!! warning "These examples create billable resources"

    Starfleet bills for a database, and for each of its branches, until
    deletion is requested. The program deletes the branch and then the database
    that it creates whether the example succeeds, fails, or is interrupted with
    Ctrl-C, and waits until the API no longer lists them. If the reply to a
    create request is lost, the program looks the resource up by its name
    before it deletes it, and if that fails it tells you the name so that you
    can delete it by hand. A program that is killed outright, with `kill -9`
    for instance, cannot clean up, so check your account for databases whose
    display names start with `cookbook-` if you stop a run that way.

The programs use [psycopg](https://www.psycopg.org/psycopg3/) for Python,
[node-postgres](https://node-postgres.com/) for TypeScript, and
[pgx](https://github.com/jackc/pgx) for Go. The curl script needs `psql`, the
PostgreSQL command line client, in addition to `curl` and `jq`. The following
excerpts show the dependencies:

=== "Python"

    ```text
    --8<-- "recipes/starfleet/branches/python/requirements.txt:deps"
    ```

=== "TypeScript"

    ```json
    --8<-- "recipes/starfleet/branches/typescript/package.json"
    ```

=== "Go"

    ```text
    --8<-- "recipes/starfleet/branches/go/go.mod:deps"
    ```

## Importing the Libraries

The following code shows the imports and, for the curl script, the check for
the tools that it needs:

=== "Python"

    ```python
    --8<-- "recipes/starfleet/branches/python/main.py:imports"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/starfleet/branches/typescript/main.ts:imports"
    ```

=== "Go"

    ```go
    --8<-- "recipes/starfleet/branches/go/main.go:imports"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/starfleet/branches/curl/main.sh:imports"
    ```

## Configuring the Program

The program reads the same environment variables as the other Starfleet
recipes, and treats an empty variable as unset:

| Variable                  | Default                  | Description         |
|---------------------------|--------------------------|---------------------|
| `STARFLEET_CLIENT_ID`     | None                     | Your client ID.     |
| `STARFLEET_CLIENT_SECRET` | None                     | Your client secret. |
| `STARFLEET_API_URL`       | `https://api.pgedge.com` | The API base URL.   |

The constants set how long to wait for each resource, which can take several
minutes to provision, and how often to check. The following code reads the
settings:

=== "Python"

    ```python
    --8<-- "recipes/starfleet/branches/python/main.py:config"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/starfleet/branches/typescript/main.ts:config"
    ```

=== "Go"

    ```go
    --8<-- "recipes/starfleet/branches/go/main.go:config"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/starfleet/branches/curl/main.sh:config"
    ```

## Getting a Token

The program gets a token in the same way as the "Getting an Access Token"
recipe:

=== "Python"

    ```python
    --8<-- "recipes/starfleet/branches/python/main.py:token"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/starfleet/branches/typescript/main.ts:token"
    ```

=== "Go"

    ```go
    --8<-- "recipes/starfleet/branches/go/main.go:token"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/starfleet/branches/curl/main.sh:token"
    ```

## Calling the Managed API

The `api` function sends an authenticated request and returns the decoded
reply. The program also reacts to particular error statuses, so the error that
the function raises carries the HTTP status:

=== "Python"

    ```python
    --8<-- "recipes/starfleet/branches/python/main.py:api"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/starfleet/branches/typescript/main.ts:api"
    ```

=== "Go"

    ```go
    --8<-- "recipes/starfleet/branches/go/main.go:api"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/starfleet/branches/curl/main.sh:api"
    ```

## Choosing a Region and Size

The program creates its own database, with the code from the "Creating a
Database and Waiting for It" recipe. It chooses the first region and the
smallest size, and the following code makes the choice:

=== "Python"

    ```python
    --8<-- "recipes/starfleet/branches/python/main.py:placement"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/starfleet/branches/typescript/main.ts:placement"
    ```

=== "Go"

    ```go
    --8<-- "recipes/starfleet/branches/go/main.go:placement"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/starfleet/branches/curl/main.sh:placement"
    ```

## Creating the Database

The following code creates the database, which only your machine can reach, and
names it with the `cookbook-` prefix:

=== "Python"

    ```python
    --8<-- "recipes/starfleet/branches/python/main.py:create"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/starfleet/branches/typescript/main.ts:create"
    ```

=== "Go"

    ```go
    --8<-- "recipes/starfleet/branches/go/main.go:create"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/starfleet/branches/curl/main.sh:create"
    ```

## Waiting for the Database

The following code polls the database until its status is `available`, and
stops at once if the status is `degraded` or `failed`:

=== "Python"

    ```python
    --8<-- "recipes/starfleet/branches/python/main.py:wait"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/starfleet/branches/typescript/main.ts:wait"
    ```

=== "Go"

    ```go
    --8<-- "recipes/starfleet/branches/go/main.go:wait"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/starfleet/branches/curl/main.sh:wait"
    ```

## Creating the Branch

The API creates a branch from the `POST` request to the branches of a database,
and documents that the new branch copies the source's size, Postgres version,
options, and service configuration at creation, with its own name, host name,
and credentials. The request here sets only a display name, which the program
chooses before the request so that it can find the branch again if the reply is
lost. It sends no IP allowlist, so the branch copies the rules of the database,
which admit your machine. The API documents that the request is refused while
the source is not available, when the database is at its branch limit, and
while the subscription has a failed payment. The following code creates the
branch and polls it until its status is `available`, and stops at once if the
status is `degraded` or `failed`:

=== "Python"

    ```python
    --8<-- "recipes/starfleet/branches/python/main.py:branch"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/starfleet/branches/typescript/main.ts:branch"
    ```

=== "Go"

    ```go
    --8<-- "recipes/starfleet/branches/go/main.go:branch"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/starfleet/branches/curl/main.sh:branch"
    ```

## Reading the Connection Details

The description of an available branch includes a `connection` object with the
host name, the port, the database name, the user name, and the password. The
API documents that the database name is the source's Postgres database name and
that the credentials are the branch's own, and that the connection is present
only while the branch is available. The API does not require any of the fields,
so the code checks that they are all present, and falls back to the external IP
address if the host is missing. The password never goes in a connection string
or on a command line: Python and TypeScript pass it to the driver as a separate
setting, Go sets it on the parsed configuration, and the curl script writes it
to a temporary password file that only its owner can read, and removes the file
at the end:

=== "Python"

    ```python
    --8<-- "recipes/starfleet/branches/python/main.py:connection"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/starfleet/branches/typescript/main.ts:connection"
    ```

=== "Go"

    ```go
    --8<-- "recipes/starfleet/branches/go/main.go:connection"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/starfleet/branches/curl/main.sh:connection"
    ```

## Running the Query

The program connects to the branch with the driver for the language (psycopg
for Python, node-postgres for TypeScript, pgx for Go, and `psql` for the curl
script) and runs `SELECT version()`. The connection is encrypted. The
certificate of a Starfleet database is not signed by a public authority, so the
example does not verify it. That leaves the connection open to a
man-in-the-middle attack, because anyone who can intercept the traffic could
pose as the server, so do not use this approach for data that matters. A server
can refuse connections for a short while after the API reports it as available,
so the code makes up to six attempts, ten seconds apart. The Python,
TypeScript, and Go code retries only failures to connect, and not errors that
the server reports, such as a failed login; `psql` gives the same exit status
for every failure to connect, so the curl script repeats them all. The
following code runs the query:

=== "Python"

    ```python
    --8<-- "recipes/starfleet/branches/python/main.py:query"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/starfleet/branches/typescript/main.ts:query"
    ```

=== "Go"

    ```go
    --8<-- "recipes/starfleet/branches/go/main.go:query"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/starfleet/branches/curl/main.sh:query"
    ```

## Deleting the Resources

The program deletes the branch first and then the database. The API documents
that a delete is refused while the database has branches, unless the `force`
parameter is set, in which case it deletes every branch first, so the database
delete passes `force=true` as a safety net for a branch that the program could
not find. After a delete request the program polls until the API no longer
lists the branch, and until it answers 404 for the database. A delete of a
branch that is still being created is refused until it settles, and in testing
the API answered 409 to a database delete whilst the database was still being
created, so both deletes repeat the request after a 409, a 429 or 5xx status,
or a failure to get any reply, until the time limit passes. A 404 means that
the resource has gone already. The API assigns the name of a branch, so if the
outcome of the branch request is unknown (no reply arrived, the service
answered with a 5xx status, the reply could not be read, or you interrupted the
program during the request), the program lists the branches of the database and
picks the one with the display name that it chose before the request, trying up
to three times, ten seconds apart. It does not look after a 4xx reply, because
that is a definite refusal. The list request passes `limit=100` and
`descending=true`, but the API specification does not say which property it
sorts on. If a delete or a lookup fails, the program prints the name or ID and
tells you to delete the resource by hand. The following code deletes the branch
and the database:

=== "Python"

    ```python
    --8<-- "recipes/starfleet/branches/python/main.py:delete"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/starfleet/branches/typescript/main.ts:delete"
    ```

=== "Go"

    ```go
    --8<-- "recipes/starfleet/branches/go/main.go:delete"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/starfleet/branches/curl/main.sh:delete"
    ```

## Running the Program

The `main` function runs the steps in order, and deletes the branch and the
database in a `finally` block (a `defer` in Go, and a trap on `EXIT` in the
curl script), so that the deletion happens when a step fails or when you press
Ctrl-C. The program also turns the SIGTERM signal into a normal exit, so that
`kill` cleans up as well. The program chooses the database name and the branch
display name before it sends each create request, so the cleanup can find the
resource by name if the reply never arrives. The cleanup ignores further
interrupts, because a second Ctrl-C must not leave a billable resource behind.
The following code shows the function:

=== "Python"

    ```python
    --8<-- "recipes/starfleet/branches/python/main.py:main"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/starfleet/branches/typescript/main.ts:main"
    ```

=== "Go"

    ```go
    --8<-- "recipes/starfleet/branches/go/main.go:main"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/starfleet/branches/curl/main.sh:main"
    ```

## Running the Example

The complete project for each language is available in the [cookbook
repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/starfleet/branches).
Set the environment variables for your account, and then run the command for
your language from the corresponding project directory. The following tabs show
the commands that build and run each example:

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

The run takes several minutes, almost all of it spent waiting for the database
and then the branch to become available.

## Viewing the Complete Program

The following tabs show the complete program for each language:

=== "Python"

    ```python
    --8<-- "recipes/starfleet/branches/python/main.py"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/starfleet/branches/typescript/main.ts"
    ```

=== "Go"

    ```go
    --8<-- "recipes/starfleet/branches/go/main.go"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/starfleet/branches/curl/main.sh"
    ```

## Next Steps

The following resources provide more information about the topics in this
recipe:

- The "Creating a Database and Waiting for It" recipe explains the creation and
  deletion steps in more detail.
- The "Connecting to a Starfleet Database" recipe explains the connection step
  in more detail.
- The PostgreSQL documentation for [SSL
  support](https://www.postgresql.org/docs/current/libpq-ssl.html) explains the
  `sslmode` setting.
