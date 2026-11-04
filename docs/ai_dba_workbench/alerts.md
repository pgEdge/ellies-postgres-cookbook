# Listing and Acknowledging Alerts with the AI DBA Workbench API

This recipe shows how a program makes a Workbench alert fire on demand, finds
the alert in the list of active alerts, acknowledges it, and then undoes its
changes. These examples are for AI DBA Workbench 1.0.0. Each step shows the
code in every supported language; selecting a language tab switches every tab
on the site to that language.

!!! warning

    The example raises a real alert. A Workbench that has notification
    channels configured (email, Slack, or webhooks, for example) sends a
    notification when the alert fires and another when it clears, and those
    messages reach real people. Run the example against a test Workbench,
    or against a server that has no notification channels or that is in a
    blackout.

An alert normally fires only when something goes wrong with a monitored server,
so the example forces one. The `metric_staleness` rule raises an alert when a
probe's data is out of date, and a threshold override for one server lowers the
threshold of that rule to -1, which no value can satisfy. The alerter then
raises the alert the next time it evaluates its rules. The program waits for
the alert, acknowledges it, confirms that the alert is acknowledged, and then
undoes its changes. The output has the following form:

```text
Found the rule 'metric_staleness'
Set an override that makes the rule fire
Waiting for the alerter to raise an alert
An alert is active (severity: info)
Acknowledged the alert
The alert is now acknowledged
Returned the alert to the active state
Removed the override
```

The alerter evaluates its rules once a minute, so the example normally takes
between a few seconds and a minute and a half to run, and gives up after 150
seconds. When the program finishes, the alert stays active for up to 30 seconds
more, until the alerter's clean-up pass clears it, and the cleared alert
remains in the alert history afterwards. The program waits for a previous alert
from the same rule to clear before it starts, so running the example twice in
succession is safe, but it can add up to 30 seconds to the second run.

## Preparing the Ingredients

The `scripts/start_workbench.sh` script in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook)
starts a test Workbench in Docker. The script creates a `cookbook` user and an
API token, registers a test PostgreSQL server as a monitored connection, and
prints the `WORKBENCH_URL`, `WORKBENCH_TOKEN`, `WORKBENCH_USERNAME`,
`WORKBENCH_PASSWORD`, and `WORKBENCH_CONNECTION_ID` values that the examples
read from the environment.

The examples need a running Workbench server that monitors at least one
PostgreSQL server, and an API token for a user that can change alert overrides
and acknowledge alerts. The Python example uses
[httpx](https://www.python-httpx.org/), the TypeScript example uses the `fetch`
function that Node.js provides, and the Go example uses the `net/http` package
from the standard library. The curl example is a bash script that uses
[jq](https://jqlang.org/) to read the JSON replies. The following tabs show the
dependency declaration from each example project:

=== "Python"

    ```text
    --8<-- "recipes/ai_dba_workbench/alerts/python/requirements.txt:deps"
    ```

=== "TypeScript"

    ```json
    --8<-- "recipes/ai_dba_workbench/alerts/typescript/package.json"
    ```

=== "Go"

    ```text
    --8<-- "recipes/ai_dba_workbench/alerts/go/go.mod:deps"
    ```

## Importing the Libraries

Each program begins by importing the modules that it uses. The following tabs
show the imports for each language:

=== "Python"

    ```python
    --8<-- "recipes/ai_dba_workbench/alerts/python/main.py:imports"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/ai_dba_workbench/alerts/typescript/main.ts:imports"
    ```

=== "Go"

    ```go
    --8<-- "recipes/ai_dba_workbench/alerts/go/main.go:imports"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/ai_dba_workbench/alerts/curl/main.sh:imports"
    ```

## Configuring the Connection

The examples read their settings from environment variables, and treat an empty
variable as unset. The following table describes the variables that the
examples read:

| Variable                  | Description                                   |
|---------------------------|-----------------------------------------------|
| `WORKBENCH_URL`           | The base URL; default `http://localhost:8080` |
| `WORKBENCH_TOKEN`         | An API token for the Workbench.               |
| `WORKBENCH_CONNECTION_ID` | The ID of the server to raise the alert on.   |

The Authenticating recipe shows how to create an API token. The examples also
set the name of the rule and the longest time to wait for the alert. The
following tabs show how each program reads the settings and stops with an error
when the token or the connection ID is missing:

=== "Python"

    ```python
    --8<-- "recipes/ai_dba_workbench/alerts/python/main.py:config"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/ai_dba_workbench/alerts/typescript/main.ts:config"
    ```

=== "Go"

    ```go
    --8<-- "recipes/ai_dba_workbench/alerts/go/main.go:config"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/ai_dba_workbench/alerts/curl/main.sh:config"
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
    --8<-- "recipes/ai_dba_workbench/alerts/python/main.py:request"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/ai_dba_workbench/alerts/typescript/main.ts:request"
    ```

=== "Go"

    ```go
    --8<-- "recipes/ai_dba_workbench/alerts/go/main.go:request"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/ai_dba_workbench/alerts/curl/main.sh:request"
    ```

## Finding the Rule

Each alert rule has a numeric ID, which the override calls need. The program
lists the rules with `GET /api/v1/alert-rules`, and picks the one whose name is
`metric_staleness`. By default this rule fires when the staleness ratio of a
probe, which is the age of its newest data divided by its collection interval,
exceeds 3. The following tabs show how each program finds the rule:

=== "Python"

    ```python
    --8<-- "recipes/ai_dba_workbench/alerts/python/main.py:find_rule"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/ai_dba_workbench/alerts/typescript/main.ts:find_rule"
    ```

=== "Go"

    ```go
    --8<-- "recipes/ai_dba_workbench/alerts/go/main.go:find_rule"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/ai_dba_workbench/alerts/curl/main.sh:find_rule"
    ```

## Setting an Override

An override changes the threshold of a rule for one scope. The program sends
`PUT /api/v1/alert-overrides/server/{connection_id}/{rule_id}` with the
operator, the threshold, the severity, and whether the rule is enabled. A
threshold of -1 with the `>` operator is true for every ratio, because the
ratio is never negative, so the rule fires on the next evaluation. The
following tabs show how each program sets the override:

=== "Python"

    ```python
    --8<-- "recipes/ai_dba_workbench/alerts/python/main.py:set_override"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/ai_dba_workbench/alerts/typescript/main.ts:set_override"
    ```

=== "Go"

    ```go
    --8<-- "recipes/ai_dba_workbench/alerts/go/main.go:set_override"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/ai_dba_workbench/alerts/curl/main.sh:set_override"
    ```

## Waiting for the Alert

Before it sets the override, the program waits until the rule has no active
alert, because the alerter raises no new alert for a rule while one is active,
and an alert left by an earlier run would otherwise stand in for the new one.
The program then polls `GET /api/v1/alerts` with the connection ID, the status
`active`, the type `threshold`, and the largest `limit` that the API allows,
until the list contains an alert from the rule. The API cannot filter by rule,
so the program does that part itself. The alerter evaluates its rules every 60
seconds, so the alert appears within a minute of the override. This particular
alert clears itself between 0 and 30 seconds after it fires, because the
alerter's clean-up pass finds no current value for the staleness metric; the
program therefore polls twice a second. If the alert clears before the program
can acknowledge it, the program waits for the rule to fire again, which takes
up to another minute, within its overall limit of 150 seconds. The following
tabs show how each program waits:

=== "Python"

    ```python
    --8<-- "recipes/ai_dba_workbench/alerts/python/main.py:wait_for_alert"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/ai_dba_workbench/alerts/typescript/main.ts:wait_for_alert"
    ```

=== "Go"

    ```go
    --8<-- "recipes/ai_dba_workbench/alerts/go/main.go:wait_for_alert"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/ai_dba_workbench/alerts/curl/main.sh:wait_for_alert"
    ```

## Acknowledging the Alert

The program acknowledges the alert with `POST /api/v1/alerts/acknowledge`,
sending the alert ID and a message. The request can also set `false_positive`
to record that the alert was a mistake. The following tabs show how each
program acknowledges the alert:

=== "Python"

    ```python
    --8<-- "recipes/ai_dba_workbench/alerts/python/main.py:acknowledge"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/ai_dba_workbench/alerts/typescript/main.ts:acknowledge"
    ```

=== "Go"

    ```go
    --8<-- "recipes/ai_dba_workbench/alerts/go/main.go:acknowledge"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/ai_dba_workbench/alerts/curl/main.sh:acknowledge"
    ```

## Checking the Status

The program confirms the acknowledgement by listing the alerts with the status
`acknowledged`, and looking for the alert by its ID. The following tabs show
how each program checks the status:

=== "Python"

    ```python
    --8<-- "recipes/ai_dba_workbench/alerts/python/main.py:check"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/ai_dba_workbench/alerts/typescript/main.ts:check"
    ```

=== "Go"

    ```go
    --8<-- "recipes/ai_dba_workbench/alerts/go/main.go:check"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/ai_dba_workbench/alerts/curl/main.sh:check"
    ```

## Returning the Alert to the Active State

The alerter's clean-up pass looks only at active alerts, and its rule
evaluation treats an acknowledged alert as the current alert for the rule, so
it raises no new one. An acknowledged alert left behind by the example would
therefore stop the example from working the next time. The program calls
`DELETE /api/v1/alerts/acknowledge` with the alert ID, which returns the alert
to the active state, and the alerter then clears it within about half a minute.
The following tabs show how each program removes the acknowledgement:

=== "Python"

    ```python
    --8<-- "recipes/ai_dba_workbench/alerts/python/main.py:unacknowledge"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/ai_dba_workbench/alerts/typescript/main.ts:unacknowledge"
    ```

=== "Go"

    ```go
    --8<-- "recipes/ai_dba_workbench/alerts/go/main.go:unacknowledge"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/ai_dba_workbench/alerts/curl/main.sh:unacknowledge"
    ```

## Removing the Override

The program removes the override with `DELETE
/api/v1/alert-overrides/server/{connection_id}/{rule_id}`, and the rule reverts
to its default threshold. The following tabs show how each program removes the
override:

=== "Python"

    ```python
    --8<-- "recipes/ai_dba_workbench/alerts/python/main.py:remove_override"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/ai_dba_workbench/alerts/typescript/main.ts:remove_override"
    ```

=== "Go"

    ```go
    --8<-- "recipes/ai_dba_workbench/alerts/go/main.go:remove_override"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/ai_dba_workbench/alerts/curl/main.sh:remove_override"
    ```

## Cleaning Up After a Failure

Each program records an undo step as soon as it makes a change, and runs the
steps that remain when it finishes or fails, so that a failed run does not
leave the server raising alerts. The program records the step that returns the
alert to the active state before it sends the acknowledgement, so that a
request which times out after the server has acted on it is still reversed.
When the acknowledgement fails and the alert is still active, the server did
not acknowledge it, so the program drops that step and reports the error; when
the alert is no longer active, the program removes the acknowledgement only if
the list of acknowledged alerts contains the alert, and keeps the step for the
clean-up to retry if that fails. The Python program uses a `finally` block, the
TypeScript and Go programs keep a list of undo steps, and the curl script uses
an `EXIT` trap. Each program reports a failure on `stderr` and exits with a
non-zero status. The following tabs show the main part of each program:

=== "Python"

    ```python
    --8<-- "recipes/ai_dba_workbench/alerts/python/main.py:main"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/ai_dba_workbench/alerts/typescript/main.ts:main"
    ```

=== "Go"

    ```go
    --8<-- "recipes/ai_dba_workbench/alerts/go/main.go:main"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/ai_dba_workbench/alerts/curl/main.sh:main"
    ```

## Running the Example

The complete project for each language is available in the [cookbook
repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/ai_dba_workbench/alerts).
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
    --8<-- "recipes/ai_dba_workbench/alerts/python/main.py"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/ai_dba_workbench/alerts/typescript/main.ts"
    ```

=== "Go"

    ```go
    --8<-- "recipes/ai_dba_workbench/alerts/go/main.go"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/ai_dba_workbench/alerts/curl/main.sh"
    ```

## Next Steps

The following resources provide more information about the topics in this
recipe:

- The [Authenticating](authenticate.md) recipe shows how to create the API
  token that this recipe needs.
- The [Querying Metrics](metrics.md) recipe reads the data that the alerter
  evaluates.
- The AI DBA Workbench [API
  reference](https://github.com/pgEdge/ai-dba-workbench/blob/v1.0.0/docs/admin-guide/api/reference.md)
  describes every endpoint.