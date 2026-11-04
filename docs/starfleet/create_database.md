# Creating a Database and Waiting for It

This recipe shows the whole life of a pgEdge Starfleet database. The program
picks the smallest size, creates a database that only your machine can reach,
waits until the database is available, and then deletes it again. Starfleet
bills for the database whilst it exists, so the program removes it on every
path out, and waits until the API confirms that it has gone.

These examples are for the pgEdge Starfleet Managed API v1.

The name of the database and the number of status lines vary, so the output
looks similar to the following:

```text
Region: us-east-2
Size: small
Created database cookbook-3f9a1c
Database status: creating
Database status: available
Database is available
Deleted database
```

## Preparing the Ingredients

You need a pgEdge Starfleet account and an API client with its client ID and
secret. Never put the client secret in a file that you commit to version
control, and never paste it into a command line, because other users of the
machine can read the command lines of running processes. The programs in this
recipe read the secret from the environment and, for the curl script, pass it
to curl on standard input.

!!! warning "These examples create billable resources"

    Starfleet bills for a database until deletion is requested. The program
    deletes the database that it creates whether the example succeeds, fails,
    or is interrupted with Ctrl-C, and waits until the API no longer lists it.
    If the reply to the create request is lost, the program looks the database
    up by its name before it deletes it, and if that fails it tells you the
    name so that you can delete it by hand. A program that is killed outright,
    with `kill -9` for instance, cannot clean up, so check your account for
    databases whose display names start with `cookbook-` if you stop a run that
    way.

The dependencies are the same as for the "Getting an Access Token" recipe. The
following excerpts show them:

=== "Python"

    ```text
    --8<-- "recipes/starfleet/create_database/python/requirements.txt:deps"
    ```

=== "TypeScript"

    ```json
    --8<-- "recipes/starfleet/create_database/typescript/package.json"
    ```

=== "Go"

    ```text
    --8<-- "recipes/starfleet/create_database/go/go.mod:deps"
    ```

## Importing the Libraries

The following code shows the imports and, for the curl script, the check for
the tools that it needs:

=== "Python"

    ```python
    --8<-- "recipes/starfleet/create_database/python/main.py:imports"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/starfleet/create_database/typescript/main.ts:imports"
    ```

=== "Go"

    ```go
    --8<-- "recipes/starfleet/create_database/go/main.go:imports"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/starfleet/create_database/curl/main.sh:imports"
    ```

## Configuring the Program

The program reads the same environment variables as the other Starfleet
recipes, and treats an empty variable as unset:

| Variable                  | Default                  | Description         |
|---------------------------|--------------------------|---------------------|
| `STARFLEET_CLIENT_ID`     | None                     | Your client ID.     |
| `STARFLEET_CLIENT_SECRET` | None                     | Your client secret. |
| `STARFLEET_API_URL`       | `https://api.pgedge.com` | The API base URL.   |

The constants set how long to wait for the database, which can take several
minutes to provision, and how often to check. The following code reads the
settings:

=== "Python"

    ```python
    --8<-- "recipes/starfleet/create_database/python/main.py:config"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/starfleet/create_database/typescript/main.ts:config"
    ```

=== "Go"

    ```go
    --8<-- "recipes/starfleet/create_database/go/main.go:config"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/starfleet/create_database/curl/main.sh:config"
    ```

## Getting a Token

The program gets a token in the same way as the "Getting an Access Token"
recipe:

=== "Python"

    ```python
    --8<-- "recipes/starfleet/create_database/python/main.py:token"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/starfleet/create_database/typescript/main.ts:token"
    ```

=== "Go"

    ```go
    --8<-- "recipes/starfleet/create_database/go/main.go:token"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/starfleet/create_database/curl/main.sh:token"
    ```

## Calling the Managed API

The `api` function sends an authenticated request and returns the decoded
reply. The program also reacts to particular error statuses, so the error that
the function raises carries the HTTP status:

=== "Python"

    ```python
    --8<-- "recipes/starfleet/create_database/python/main.py:api"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/starfleet/create_database/typescript/main.ts:api"
    ```

=== "Go"

    ```go
    --8<-- "recipes/starfleet/create_database/go/main.go:api"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/starfleet/create_database/curl/main.sh:api"
    ```

## Choosing a Region and Size

The program asks the API for the regions and the sizes, and picks the first
size, which is the smallest and therefore the cheapest. The API does not price
regions, so the program takes the first region in the list. The following code
makes the choice:

=== "Python"

    ```python
    --8<-- "recipes/starfleet/create_database/python/main.py:placement"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/starfleet/create_database/typescript/main.ts:placement"
    ```

=== "Go"

    ```go
    --8<-- "recipes/starfleet/create_database/go/main.go:placement"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/starfleet/create_database/curl/main.sh:placement"
    ```

## Creating the Database

A new database refuses every connection until an allowlist rule admits the
source address. The program asks the API for the address that it sees the
request come from, and admits only that address; a bare address means a single
host. The `name` of a database becomes its Postgres database name, so in
testing it accepted only letters and digits; the readable `cookbook-` prefix
and a random suffix go in the `display_name`, which is how you recognise the
database in your account. The following code creates the database:

=== "Python"

    ```python
    --8<-- "recipes/starfleet/create_database/python/main.py:create"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/starfleet/create_database/typescript/main.ts:create"
    ```

=== "Go"

    ```go
    --8<-- "recipes/starfleet/create_database/go/main.go:create"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/starfleet/create_database/curl/main.sh:create"
    ```

## Waiting for the Database

Creating a database takes the API a few minutes. The program polls the database
every ten seconds, prints each new status, and stops when the status is
`available`, or the time limit passes, or the status is `degraded` or `failed`,
which the API does not document but which the program treats as failures. In
testing, `available` was the status of a database that is ready. The following
code waits:

=== "Python"

    ```python
    --8<-- "recipes/starfleet/create_database/python/main.py:wait"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/starfleet/create_database/typescript/main.ts:wait"
    ```

=== "Go"

    ```go
    --8<-- "recipes/starfleet/create_database/go/main.go:wait"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/starfleet/create_database/curl/main.sh:wait"
    ```

## Deleting the Database

The API documents a 409 reply to a delete as meaning that the database has
branches, and offers a `force` parameter for that case. In testing, the API
also answered 409 whilst a database was still being created, so the program
repeats the request after a 409, after a 429 or 5xx status, and after a failure
to get any reply, until the time limit passes. A 404 means that the database
has gone already. A delete only starts the teardown, so the program then polls
until the API answers 404, which in testing was the sign that the database had
gone. The following code deletes the database. If the outcome of the create
request is unknown (no reply arrived, the service answered with a 5xx status,
the reply could not be read, or you interrupted the program during the
request), the program has no database ID, so it first lists the databases and
picks the one with the name that it chose before the request. If the list has
no such database, the program tries up to three times, ten seconds apart, in
case the service has not yet recorded the request, and then reports the name so
that you can check your account by hand. It does not look after a 4xx reply,
because that is a definite refusal. The request passes `limit=100` and
`descending=true`, but the API specification does not say which property it
sorts on, so the program cannot be sure that a new database is on the first
page of an account with more than 100 databases. The program repeats the
listing in the same way as the delete, and if it still fails, prints the name
of the database and tells you to delete it by hand:

=== "Python"

    ```python
    --8<-- "recipes/starfleet/create_database/python/main.py:delete"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/starfleet/create_database/typescript/main.ts:delete"
    ```

=== "Go"

    ```go
    --8<-- "recipes/starfleet/create_database/go/main.go:delete"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/starfleet/create_database/curl/main.sh:delete"
    ```

## Running the Program

The `main` function runs the steps in order, and deletes the database in a
`finally` block (a `defer` in Go, and a trap on `EXIT` in the curl script), so
that the deletion happens when a step fails or when you press Ctrl-C. The
program also turns the SIGTERM signal into a normal exit, so that `kill` cleans
up as well. The program chooses the database name before it sends the create
request, so the cleanup can find the database by name if the reply never
arrives. The cleanup ignores further interrupts, because a second Ctrl-C must
not leave a billable database behind. The following code shows the function:

=== "Python"

    ```python
    --8<-- "recipes/starfleet/create_database/python/main.py:main"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/starfleet/create_database/typescript/main.ts:main"
    ```

=== "Go"

    ```go
    --8<-- "recipes/starfleet/create_database/go/main.go:main"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/starfleet/create_database/curl/main.sh:main"
    ```

## Running the Example

The complete project for each language is available in the [cookbook
repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/starfleet/create_database).
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
to become available.

## Viewing the Complete Program

The following tabs show the complete program for each language:

=== "Python"

    ```python
    --8<-- "recipes/starfleet/create_database/python/main.py"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/starfleet/create_database/typescript/main.ts"
    ```

=== "Go"

    ```go
    --8<-- "recipes/starfleet/create_database/go/main.go"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/starfleet/create_database/curl/main.sh"
    ```

## Next Steps

The following resources provide more information about the topics in this
recipe:

- The "Connecting to a Starfleet Database" recipe connects to the database
  and runs a query before it deletes the database.
