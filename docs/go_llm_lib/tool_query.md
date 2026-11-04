# Letting a Model Query the Database

This recipe shows how a language model can answer a question about the data
in a PostgreSQL database without ever seeing or writing SQL. The program
describes one tool to the model with the
[pgEdge Go LLM Library](https://github.com/pgEdge/pgedge-go-llm-lib); the
model asks for the tool by name, the program runs a fixed, parameterised
query on its behalf, and the model turns the result into an answer.

The example asks how many data types named `int4` exist in the database,
and the program prints the tool call that the model made, followed by the
model's answer. The wording of the answer varies from run to run, so the
output looks similar to the following:

```text
Tool call: count_types(int4)
Answer: There is 1 data type named int4 in the database.
```

## Understanding Why the Model Never Sees SQL

A model that writes SQL can write any SQL, including a statement that reads
data it should not see or changes data it should not touch. A tool
inverts that arrangement. The program decides which queries exist and
describes each one to the model as a name, a description, and a JSON Schema
for its arguments. The model can then only choose a tool and supply values
for the arguments.

The values still need care, because they come from a model and not from a
trusted source. The program therefore checks each value before it uses it,
and passes the value to the database as a query parameter, so that the
server never interprets the value as SQL. A request for anything other than
the described tool is an error.

## Preparing the Ingredients

The example uses [pgx](https://github.com/jackc/pgx) to talk to PostgreSQL
and the pgEdge Go LLM Library to talk to the model. The library supports
several providers behind one `llm.Client` interface, so the same program
runs against a local Ollama server or a cloud service. The following
excerpt shows the dependency declarations from the `go.mod` file:

```text
--8<-- "recipes/go_llm_lib/tool_query/go/go.mod:deps"
```

The default settings use a local [Ollama](https://ollama.com/) server with
the `qwen2.5:1.5b` model, which you can install with the following
commands:

```bash
ollama serve
ollama pull qwen2.5:1.5b
```

!!! note

    A model with 1.5 billion parameters is small, and occasionally sends
    malformed or incomplete tool arguments. The program checks the
    arguments and stops with a clear error message when they are unusable;
    running the program again normally succeeds. Larger models are more
    reliable.

## Importing the Libraries

The program imports pgx, the library, and the `llm/all` package. The
`llm/all` package registers every built-in provider, and is imported only
for that side effect. The following code shows the imports:

```go
--8<-- "recipes/go_llm_lib/tool_query/go/main.go:imports"
```

## Configuring the Program

The program reads the PostgreSQL connection settings from the same `PG*`
environment variables as the other recipes, and reads the model settings
from the `LLM_*` variables. Like libpq, the program treats an empty
variable as unset. The following table describes the variables:

| Variable       | Default        | Description                                |
|----------------|----------------|--------------------------------------------|
| `PGHOST`       | `localhost`    | The host name or IP address of the server. |
| `PGPORT`       | `5432`         | The TCP port on which the server listens.  |
| `PGDATABASE`   | `postgres`     | The name of the database to connect to.    |
| `PGUSER`       | `postgres`     | The user name to connect as.               |
| `PGPASSWORD`   | None           | The password; omitted if unset or empty.   |
| `LLM_PROVIDER` | `ollama`       | The model provider.                        |
| `LLM_MODEL`    | `qwen2.5:1.5b` | The chat model.                            |
| `LLM_API_KEY`  | None           | The API key, if the provider needs one.    |
| `LLM_BASE_URL` | None           | Overrides the provider's own endpoint.     |

When `LLM_BASE_URL` is unset, the program passes no address to the library,
which then uses the default endpoint for the provider. The following code
reads the settings:

```go
--8<-- "recipes/go_llm_lib/tool_query/go/main.go:config"
```

## Creating the Clients

The `newClient` function builds the model client from the settings, and
the `connect` function opens the database connection. The library retries
failed requests five times by default, with a pause that doubles each
time; the example lowers the limit to two short retries so that an
unreachable server is reported within seconds. The following code creates
the two clients:

```go
--8<-- "recipes/go_llm_lib/tool_query/go/main.go:client"
```

```go
--8<-- "recipes/go_llm_lib/tool_query/go/main.go:connect"
```

## Describing the Tool

An `llm.Tool` holds the tool's name, a description that tells the model
when to use it, and a JSON Schema for its arguments. This description is
everything that the model knows about the database. The following code
defines the `count_types` tool, which takes the name of a data type:

```go
--8<-- "recipes/go_llm_lib/tool_query/go/main.go:tool"
```

## Running the Tool

When the model calls the tool, the program decodes the arguments, checks
that the type name is a plausible identifier, and runs the query with the
name as a parameter. The SQL text is fixed in the program, so the model
controls only the value of `$1`. The following code runs the tool:

```go
--8<-- "recipes/go_llm_lib/tool_query/go/main.go:execute"
```

## Asking the Question

The `answerWithTool` function makes two requests. The first request lists
the tool and uses `ToolChoiceSpecific` to require a call to `count_types`.
The program then runs the tool, and the second request sends back the
conversation so far, including the model's tool call and the result, which
`ToolResultMessage` links to the call by its ID. The second request lists
no tools, so the model has nothing to call and replies with a final answer
in plain text. Setting `ToolChoiceNone` would not do the same job:
Ollama ignores `ToolChoice`, and the library sends Anthropic `auto` in
its place. If your provider rejects a conversation that contains tool
calls but no tool definitions, list the tools again in the second request.

!!! note

    Ollama has no native setting that forces a tool call, so the library
    ignores `ToolChoice` for that provider and asks the model for a call in
    the system prompt instead. The program therefore also checks that the
    reply contains a tool call, and stops with an error if it does not. The
    OpenAI provider sends `ToolChoiceSpecific` as a `tool_choice` request
    field that names the function, and the library source maps the choice
    for the Anthropic and Gemini providers as well.

The following code asks the question:

```go
--8<-- "recipes/go_llm_lib/tool_query/go/main.go:ask"
```

## Handling Errors and Closing the Connection

The `run` function connects, asks the question, and prints the tool call
and the answer. It returns any error to `main`, which reports the error on
`stderr` and exits with a non-zero status. The deferred call closes the
database connection whether or not an error occurred. The following code
shows the main part of the program:

```go
--8<-- "recipes/go_llm_lib/tool_query/go/main.go:main"
```

## Running the Example

The complete project is available in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/go_llm_lib/tool_query).
Set the environment variables for your server and model, and then run the
following command from the `go` project directory:

```bash
go run .
```

## Viewing the Complete Program

The following code shows the complete program:

```go
--8<-- "recipes/go_llm_lib/tool_query/go/main.go"
```

## Next Steps

The following resources provide more information about the topics in this
recipe:

- The [pgEdge Go LLM Library](https://github.com/pgEdge/pgedge-go-llm-lib)
  documentation describes tool use, tool choice, and the supported
  providers.
- The [Contributing a Recipe](../contributing.md) page explains how to add
  a recipe to the cookbook.
- The [Connecting to PostgreSQL and Running a Query](../postgresql/connect_and_query.md)
  recipe explains the connection code in more detail.
