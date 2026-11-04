# Querying Metrics with the AI DBA Workbench API

This recipe shows how a program reads time-series metrics and the most
expensive queries for a monitored server from the pgEdge AI DBA Workbench API.
These examples are for AI DBA Workbench 1.0.0. Each step shows the code in
every supported language; selecting a language tab switches every tab on the
site to that language.

The example program asks for two metrics from the `pg_stat_database` probe over
the last hour, and prints the number of points and the latest value of each. It
then asks for the five queries that have used the most execution time, and
prints each one with its number of calls and its mean execution time. The
values change from run to run, so the output has the following form:

```text
numbackends: 5 points, latest 3
xact_commit: 5 points, latest 1138
Top queries by total execution time:
1. 1 calls, 6.97 ms mean: CREATE EXTENSION IF NOT EXISTS pg_stat_statements
2. 26 calls, 0.01 ms mean: SELECT datname FROM pg_database WHERE datallowconn
3. 28 calls, 0.01 ms mean: SELECT EXISTS( SELECT $2 FROM pg_extension WHERE e
```

The second part of the output depends on the monitored server. The Workbench
builds the list of top queries from the `pg_stat_statements` extension, so a
server without the extension returns an empty list, and the program then prints
a line that starts with "No statements recorded" instead of the list. The
program stops with an error when the Workbench returns no series at all, which
happens before the collector has stored any data for the server.

## Preparing the Ingredients

The `scripts/start_workbench.sh` script in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook)
starts a test Workbench in Docker. The script creates a `cookbook` user and an
API token, registers a test PostgreSQL server as a monitored connection, and
prints the `WORKBENCH_URL`, `WORKBENCH_TOKEN`, `WORKBENCH_USERNAME`,
`WORKBENCH_PASSWORD`, and `WORKBENCH_CONNECTION_ID` values that the examples
read from the environment.

The examples need a running Workbench server that monitors at least one
PostgreSQL server, and an API token for a user that can read its metrics. The
Python example uses [httpx](https://www.python-httpx.org/), the TypeScript
example uses the `fetch` function that Node.js provides, and the Go example
uses the `net/http` package from the standard library. The curl example is a
bash script that uses [jq](https://jqlang.org/) to read the JSON replies. The
following tabs show the dependency declaration from each example project:

=== "Python"

    ```text
    --8<-- "recipes/ai_dba_workbench/metrics/python/requirements.txt:deps"
    ```

=== "TypeScript"

    ```json
    --8<-- "recipes/ai_dba_workbench/metrics/typescript/package.json"
    ```

=== "Go"

    ```text
    --8<-- "recipes/ai_dba_workbench/metrics/go/go.mod:deps"
    ```

To see the top queries, install the extension on the monitored server. Add
`pg_stat_statements` to `shared_preload_libraries` in `postgresql.conf`,
restart the server, and then run `CREATE EXTENSION pg_stat_statements` in the
monitored database. The collector collects the statements every five minutes,
so the first queries appear after the next collection.

## Importing the Libraries

Each program begins by importing the modules that it uses. The following tabs
show the imports for each language:

=== "Python"

    ```python
    --8<-- "recipes/ai_dba_workbench/metrics/python/main.py:imports"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/ai_dba_workbench/metrics/typescript/main.ts:imports"
    ```

=== "Go"

    ```go
    --8<-- "recipes/ai_dba_workbench/metrics/go/main.go:imports"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/ai_dba_workbench/metrics/curl/main.sh:imports"
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

The Authenticating recipe shows how to create an API token. The following tabs
show how each program reads the settings and stops with an error when the token
or the connection ID is missing:

=== "Python"

    ```python
    --8<-- "recipes/ai_dba_workbench/metrics/python/main.py:config"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/ai_dba_workbench/metrics/typescript/main.ts:config"
    ```

=== "Go"

    ```go
    --8<-- "recipes/ai_dba_workbench/metrics/go/main.go:config"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/ai_dba_workbench/metrics/curl/main.sh:config"
    ```

## Sending Requests

Every call to the API goes through one helper function. The function adds the
`/api/v1` prefix to the path, adds the query parameters, sends the token as a
`Bearer` credential in the `Authorization` header, and sets a timeout so that a
stalled server cannot hang the program. When the server rejects a request, the
function raises an error that includes the status code and the message from the
server, for example when a request names a metric that the probe does not
collect. The following tabs show the helper function from each program:

=== "Python"

    ```python
    --8<-- "recipes/ai_dba_workbench/metrics/python/main.py:request"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/ai_dba_workbench/metrics/typescript/main.ts:request"
    ```

=== "Go"

    ```go
    --8<-- "recipes/ai_dba_workbench/metrics/go/main.go:request"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/ai_dba_workbench/metrics/curl/main.sh:request"
    ```

## Querying Metrics

The program asks `GET /api/v1/metrics/query` for the `numbackends` and
`xact_commit` metrics of the `pg_stat_database` probe over the last hour. The
parameters `connection_id`, `probe_name`, and `time_range` choose the server,
the probe, and the period; the `time_range` parameter accepts `1h`, `6h`,
`24h`, `7d`, and `30d`. The `buckets` parameter divides the period into six
buckets, and the `metrics` parameter lists the metrics to return. The reply is
a list of series, each with a `name`, a `unit`, and a `data` list of points
with a `time` and a `value`. The number of points depends on how much data
exists for the period. The following tabs show how each program queries the
metrics:

=== "Python"

    ```python
    --8<-- "recipes/ai_dba_workbench/metrics/python/main.py:query_metrics"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/ai_dba_workbench/metrics/typescript/main.ts:query_metrics"
    ```

=== "Go"

    ```go
    --8<-- "recipes/ai_dba_workbench/metrics/go/main.go:query_metrics"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/ai_dba_workbench/metrics/curl/main.sh:query_metrics"
    ```

## Reading the Top Queries

The program asks `GET /api/v1/metrics/top-queries` for the five queries with
the largest total execution time. The `order_by` parameter accepts
`total_exec_time`, `calls`, `mean_exec_time`, `rows`, `shared_blks_hit`, and
`shared_blks_read`, and the `order` parameter chooses between `asc` and `desc`
(the default is `desc`). Setting `exclude_collector` to `true` hides the
queries that the Workbench's own probes run, so the list shows the queries of
the applications. The `limit` parameter accepts up to 100. The program cuts
each query to 50 characters on one line, because a statement can run to many
lines. The following tabs show how each program reads the top queries:

=== "Python"

    ```python
    --8<-- "recipes/ai_dba_workbench/metrics/python/main.py:top_queries"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/ai_dba_workbench/metrics/typescript/main.ts:top_queries"
    ```

=== "Go"

    ```go
    --8<-- "recipes/ai_dba_workbench/metrics/go/main.go:top_queries"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/ai_dba_workbench/metrics/curl/main.sh:top_queries"
    ```

## Putting It Together

The main part of each program reads the settings, queries the metrics, and then
reads the top queries. The program reports any failure on `stderr` and exits
with a non-zero status. The following tabs show the main part of each program:

=== "Python"

    ```python
    --8<-- "recipes/ai_dba_workbench/metrics/python/main.py:main"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/ai_dba_workbench/metrics/typescript/main.ts:main"
    ```

=== "Go"

    ```go
    --8<-- "recipes/ai_dba_workbench/metrics/go/main.go:main"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/ai_dba_workbench/metrics/curl/main.sh:main"
    ```

## Running the Example

The complete project for each language is available in the [cookbook
repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/ai_dba_workbench/metrics).
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
    --8<-- "recipes/ai_dba_workbench/metrics/python/main.py"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/ai_dba_workbench/metrics/typescript/main.ts"
    ```

=== "Go"

    ```go
    --8<-- "recipes/ai_dba_workbench/metrics/go/main.go"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/ai_dba_workbench/metrics/curl/main.sh"
    ```

## Next Steps

The following resources provide more information about the topics in this
recipe:

- The [Listing and Acknowledging Alerts](alerts.md) recipe shows how the
  Workbench raises alerts from these metrics.
- The AI DBA Workbench [probes
  guide](https://github.com/pgEdge/ai-dba-workbench/blob/v1.0.0/docs/admin-guide/probes.md)
  describes the probes and their collection intervals.
- The AI DBA Workbench [API
  reference](https://github.com/pgEdge/ai-dba-workbench/blob/v1.0.0/docs/admin-guide/api/reference.md)
  describes every endpoint.