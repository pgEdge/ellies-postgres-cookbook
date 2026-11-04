# Extracting Structured Data into a Table

This recipe shows how to turn free text into rows in a PostgreSQL table.
The program asks a language model to read a short order email and return
the customer and the ordered items as JSON that matches a schema; it then
decodes the JSON into Go structs, validates the values, and inserts them
into tables with [pgx](https://github.com/jackc/pgx). The model comes from
the [pgEdge Go LLM Library](https://github.com/pgEdge/pgedge-go-llm-lib).

The email in the example is made up. The program prints the rows that it
reads back from the database, so the output confirms that the data reached
the tables. The wording of some values, such as the capitalisation of an
item name, varies from run to run, so the output looks similar to the
following:

```text
Customer: Jane Doe <jane.doe@example.com>
Item: 1 x Gadget @ 12.00
Item: 2 x Widget @ 4.50
```

## Preparing the Ingredients

The example uses pgx to talk to PostgreSQL and the pgEdge Go LLM Library to
talk to the model. The library supports several providers behind one
`llm.Client` interface, so the same program runs against a local Ollama
server or a cloud service. The following excerpt shows the dependency
declarations from the `go.mod` file:

```text
--8<-- "recipes/go_llm_lib/structured_extraction/go/go.mod:deps"
```

The default settings use a local [Ollama](https://ollama.com/) server with
the `qwen2.5:1.5b` model, which you can install with the following
commands:

```bash
ollama serve
ollama pull qwen2.5:1.5b
```

## Importing the Libraries

The program imports pgx, the library, and the `llm/all` package. The
`llm/all` package registers every built-in provider, and is imported only
for that side effect. The following code shows the imports:

```go
--8<-- "recipes/go_llm_lib/structured_extraction/go/main.go:imports"
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
--8<-- "recipes/go_llm_lib/structured_extraction/go/main.go:config"
```

## Creating the Clients

The `newClient` function builds the model client from the settings, and
the `connect` function opens the database connection. The library retries
failed requests five times by default, with a pause that doubles each
time; the example lowers the limit to two short retries so that an
unreachable server is reported within seconds. The following code creates
the two clients:

```go
--8<-- "recipes/go_llm_lib/structured_extraction/go/main.go:client"
```

```go
--8<-- "recipes/go_llm_lib/structured_extraction/go/main.go:connect"
```

## Describing the Structure

The program describes the data it wants in two forms that must agree: Go
structs that the program decodes into, and a JSON Schema that tells the
model what to produce. The schema also lists `additionalProperties` as
`false`, so a provider that enforces the schema cannot add fields of its
own. The following code defines the email, the structs, and the schema:

```go
--8<-- "recipes/go_llm_lib/structured_extraction/go/main.go:schema"
```

## Extracting the Data

The `extractOrder` function sends the email with `ResponseFormatJSONSchema`
and the schema. Ollama passes the schema to the model runtime, which only
allows output that matches it, so even a small model returns well-formed
JSON of the right shape. The function decodes the reply and rejects any
field that the structs do not define. The following code extracts the
order:

```go
--8<-- "recipes/go_llm_lib/structured_extraction/go/main.go:extract"
```

!!! note

    Providers differ in how strictly they follow a schema. The library
    documents that a provider without strict schema support falls back to
    asking for JSON, so always decode and validate the reply, as the
    program does.

## Validating the Values

A reply that matches the schema can still be wrong; the model might return
an empty name, a quantity of zero, or an email address that is not an
address. The `validateOrder` function checks each value and returns a
clear message for the first problem that it finds, so that the program
stops before it writes anything to the database. The following code
validates the order:

```go
--8<-- "recipes/go_llm_lib/structured_extraction/go/main.go:validate"
```

## Storing the Data

The `storeOrder` function creates two `TEMPORARY` tables, which PostgreSQL
drops when the session ends, so the example leaves nothing behind and can
run repeatedly. The function inserts the customer, reads the generated key
with `RETURNING`, and inserts each item with that key, all in one
transaction. The program passes every value as a query parameter. The
following code stores the order:

```go
--8<-- "recipes/go_llm_lib/structured_extraction/go/main.go:store"
```

## Reading the Rows Back

The `showOrder` function joins the two tables and prints the rows. The
function casts the price to `text` so that the program prints the exact
`numeric` value from the database, such as `4.50`, instead of a
floating-point approximation. The following code reads the rows:

```go
--8<-- "recipes/go_llm_lib/structured_extraction/go/main.go:show"
```

## Handling Errors and Closing the Connection

The `run` function connects, extracts, validates, stores, and shows the
order. It returns any error to `main`, which reports the error on `stderr`
and exits with a non-zero status. The deferred call closes the database
connection whether or not an error occurred. The following code shows the
main part of the program:

```go
--8<-- "recipes/go_llm_lib/structured_extraction/go/main.go:main"
```

## Running the Example

The complete project is available in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/go_llm_lib/structured_extraction).
Set the environment variables for your server and model, and then run the
following command from the `go` project directory:

```bash
go run .
```

## Viewing the Complete Program

The following code shows the complete program:

```go
--8<-- "recipes/go_llm_lib/structured_extraction/go/main.go"
```

## Next Steps

The following resources provide more information about the topics in this
recipe:

- The [pgEdge Go LLM Library](https://github.com/pgEdge/pgedge-go-llm-lib)
  documentation describes structured output and the supported providers.
- The [Contributing a Recipe](../contributing.md) page explains how to add
  a recipe to the cookbook.
- The [Connecting to PostgreSQL and Running a Query](../postgresql/connect_and_query.md)
  recipe explains the connection code in more detail.
