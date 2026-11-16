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
// pgx is a pure Go driver and toolkit for PostgreSQL; the pgEdge Go LLM
// Library provides one client interface for several model providers.
require (
	github.com/jackc/pgx/v5 v5.12.0
	github.com/pgEdge/pgedge-go-llm-lib v0.6.0
)

require (
	github.com/jackc/pgpassfile v1.0.0 // indirect
	github.com/jackc/pgservicefile v0.0.0-20240606120523-5a60cdf6a761 // indirect
	golang.org/x/text v0.41.0 // indirect
)

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
import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"net/url"
	"os"
	"regexp"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/pgEdge/pgedge-go-llm-lib/llm"
	_ "github.com/pgEdge/pgedge-go-llm-lib/llm/all"
)

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
// envOr returns the value of an environment variable, or a fallback if
// the variable is unset or empty.
func envOr(name, fallback string) string {
	if value := os.Getenv(name); value != "" {
		return value
	}
	return fallback
}

// connString builds a postgres:// URL from the standard libpq environment
// variables. net/url takes care of escaping any special characters in
// the user name, password, or database name.
func connString() string {
	u := url.URL{
		Scheme: "postgres",
		Host:   net.JoinHostPort(envOr("PGHOST", "localhost"), envOr("PGPORT", "5432")),
		Path:   "/" + envOr("PGDATABASE", "postgres"),
	}
	if password := os.Getenv("PGPASSWORD"); password != "" {
		u.User = url.UserPassword(envOr("PGUSER", "postgres"), password)
	} else {
		u.User = url.User(envOr("PGUSER", "postgres"))
	}
	return u.String()
}

// llmSettings reads the language model settings from the environment.
// An empty LLM_BASE_URL means that the library uses the provider's own
// default endpoint, and an empty LLM_API_KEY means that no key is sent.
func llmSettings() (provider string, opts llm.Options) {
	provider = envOr("LLM_PROVIDER", "ollama")
	opts = llm.Options{
		Model:   envOr("LLM_MODEL", "qwen2.5:1.5b"),
		APIKey:  os.Getenv("LLM_API_KEY"),
		BaseURL: os.Getenv("LLM_BASE_URL"),
	}
	return provider, opts
}

```

## Creating the Clients

The `newClient` function builds the model client from the settings, and
the `connect` function opens the database connection. The library retries
failed requests five times by default, with a pause that doubles each
time; the example lowers the limit to two short retries so that an
unreachable server is reported within seconds. The following code creates
the two clients:

```go
// newClient builds a chat client from the settings in the environment.
func newClient() (llm.Client, error) {
	provider, opts := llmSettings()

	// The default of five retries with a two second pause that doubles
	// each time suits a busy cloud service, but makes a mistyped address
	// take a minute to report. Two short retries still ride out a
	// momentary failure.
	opts.Retry = llm.RetryConfig{
		MaxRetries:     2,
		InitialBackoff: 500 * time.Millisecond,
	}

	client, err := llm.NewClient(provider, opts)
	if err != nil {
		return nil, fmt.Errorf("creating the %s client failed: %w", provider, err)
	}
	return client, nil
}

```

```go
// connect opens a connection with the settings from the environment.
func connect(ctx context.Context) (*pgx.Conn, error) {
	conn, err := pgx.Connect(ctx, connString())
	if err != nil {
		return nil, fmt.Errorf("connection failed: %w", err)
	}
	return conn, nil
}

```

## Describing the Tool

An `llm.Tool` holds the tool's name, a description that tells the model
when to use it, and a JSON Schema for its arguments. This description is
everything that the model knows about the database. The following code
defines the `count_types` tool, which takes the name of a data type:

```go
// countTypesTool describes the one thing the model may ask for. The
// model sees only this name, this description, and this JSON Schema; it
// never sees the SQL that the program runs, and it cannot write any.
var countTypesTool = llm.Tool{
	Name: "count_types",
	Description: "Counts the data types in the PostgreSQL database " +
		"that have the given name.",
	InputSchema: json.RawMessage(`{
		"type": "object",
		"properties": {
			"name": {
				"type": "string",
				"description": "The name of a data type, such as int4."
			}
		},
		"required": ["name"]
	}`),
}

```

## Running the Tool

When the model calls the tool, the program decodes the arguments, checks
that the type name is a plausible identifier, and runs the query with the
name as a parameter. The SQL text is fixed in the program, so the model
controls only the value of `$1`. The following code runs the tool:

```go
// typeNamePattern limits the argument to the characters that appear in
// built-in type names, which rejects anything odd the model sends.
var typeNamePattern = regexp.MustCompile(`^[A-Za-z0-9_]{1,63}$`)

// countTypes runs the tool for the model, and returns the type name that
// the model asked about with the count as text. The model controls only
// the value of $1; the SQL text is fixed, and pgx sends the value
// separately.
func countTypes(ctx context.Context, conn *pgx.Conn, call *llm.ToolUse) (string, string, error) {
	if call.Name != countTypesTool.Name {
		return "", "", fmt.Errorf("the model called an unknown tool: %q", call.Name)
	}

	// A small model sometimes sends malformed or incomplete arguments,
	// so check them before they reach the database.
	var args struct {
		TypeName string `json:"name"`
	}
	if err := json.Unmarshal(call.Input, &args); err != nil {
		return "", "", fmt.Errorf("the model sent unusable arguments %s: %w", call.Input, err)
	}
	if !typeNamePattern.MatchString(args.TypeName) {
		return "", "", fmt.Errorf("the model sent an invalid type name %q in %s", args.TypeName, call.Input)
	}

	var count int64
	err := conn.QueryRow(ctx,
		"SELECT count(*) FROM pg_catalog.pg_type WHERE typname = $1",
		args.TypeName,
	).Scan(&count)
	if err != nil {
		return "", "", fmt.Errorf("query failed: %w", err)
	}
	return args.TypeName, fmt.Sprintf("%d", count), nil
}

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
// answerWithTool asks the question, runs the tool that the model calls,
// and returns the type name from the tool call with the model's final
// answer.
func answerWithTool(ctx context.Context, client llm.Client, conn *pgx.Conn, question string) (string, string, error) {
	messages := []llm.Message{llm.UserText(question)}
	tools := []llm.Tool{countTypesTool}

	// Force the first reply to be a call to count_types. Providers with a
	// native tool choice setting receive it; Ollama has none, so the check
	// below is what guarantees that a tool was called.
	first, err := client.Chat(ctx, llm.ChatRequest{
		Messages: messages,
		Tools:    tools,
		ToolChoice: &llm.ToolChoice{
			Mode: llm.ToolChoiceSpecific,
			Name: countTypesTool.Name,
		},
	})
	if err != nil {
		return "", "", fmt.Errorf("first request failed: %w", err)
	}

	var call *llm.ToolUse
	for _, block := range first.Content {
		if block.Type == llm.BlockToolUse {
			call = block.ToolUse
			break
		}
	}
	if call == nil {
		return "", "", errors.New("the model did not call the tool")
	}

	name, result, err := countTypes(ctx, conn, call)
	if err != nil {
		return "", "", err
	}

	// Send the whole conversation back: the question, the model's own
	// tool call, and the result, which refers to the call by its ID.
	messages = append(messages,
		llm.Message{Role: llm.RoleAssistant, Content: first.Content},
		llm.ToolResultMessage(call.ID, result, false),
	)

	// Leave the tools out of this request, so that the model has nothing
	// to call and can only answer. ToolChoiceNone would not do the same
	// job: Ollama ignores ToolChoice, and Anthropic treats "none" as
	// "auto".
	final, err := client.Chat(ctx, llm.ChatRequest{Messages: messages})
	if err != nil {
		return "", "", fmt.Errorf("second request failed: %w", err)
	}

	var text strings.Builder
	for _, block := range final.Content {
		if block.Type == llm.BlockText {
			text.WriteString(block.Text)
		}
	}
	answer := strings.TrimSpace(text.String())
	if answer == "" {
		return "", "", errors.New("the model gave no final answer")
	}
	return name, answer, nil
}

```

## Handling Errors and Closing the Connection

The `run` function connects, asks the question, and prints the tool call
and the answer. It returns any error to `main`, which reports the error on
`stderr` and exits with a non-zero status. The deferred call closes the
database connection whether or not an error occurred. The following code
shows the main part of the program:

```go
// run connects, asks the question, and prints the result, returning any
// error to the caller.
func run(ctx context.Context) error {
	conn, err := connect(ctx)
	if err != nil {
		return err
	}
	// The deferred call closes the connection when run() returns, whether
	// or not an error occurred.
	defer conn.Close(ctx)

	client, err := newClient()
	if err != nil {
		return err
	}

	name, answer, err := answerWithTool(ctx, client, conn,
		"How many data types named int4 are there in the database?")
	if err != nil {
		return err
	}

	fmt.Printf("Tool call: count_types(%s)\n", name)
	fmt.Printf("Answer: %s\n", answer)
	return nil
}

// main reports any error returned by run() and exits with a non-zero
// status. Keeping the work in run() means that deferred cleanup always
// happens before the program exits.
func main() {
	if err := run(context.Background()); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
}

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
// Ellie's Postgres Cookbook
// Letting a model query the database through a tool, using the pgEdge Go
// LLM Library and pgx.
//
// Copyright (c) 2026, pgEdge, Inc.
// This code is released under the PostgreSQL License.

package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"net/url"
	"os"
	"regexp"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/pgEdge/pgedge-go-llm-lib/llm"
	_ "github.com/pgEdge/pgedge-go-llm-lib/llm/all"
)


// envOr returns the value of an environment variable, or a fallback if
// the variable is unset or empty.
func envOr(name, fallback string) string {
	if value := os.Getenv(name); value != "" {
		return value
	}
	return fallback
}

// connString builds a postgres:// URL from the standard libpq environment
// variables. net/url takes care of escaping any special characters in
// the user name, password, or database name.
func connString() string {
	u := url.URL{
		Scheme: "postgres",
		Host:   net.JoinHostPort(envOr("PGHOST", "localhost"), envOr("PGPORT", "5432")),
		Path:   "/" + envOr("PGDATABASE", "postgres"),
	}
	if password := os.Getenv("PGPASSWORD"); password != "" {
		u.User = url.UserPassword(envOr("PGUSER", "postgres"), password)
	} else {
		u.User = url.User(envOr("PGUSER", "postgres"))
	}
	return u.String()
}

// llmSettings reads the language model settings from the environment.
// An empty LLM_BASE_URL means that the library uses the provider's own
// default endpoint, and an empty LLM_API_KEY means that no key is sent.
func llmSettings() (provider string, opts llm.Options) {
	provider = envOr("LLM_PROVIDER", "ollama")
	opts = llm.Options{
		Model:   envOr("LLM_MODEL", "qwen2.5:1.5b"),
		APIKey:  os.Getenv("LLM_API_KEY"),
		BaseURL: os.Getenv("LLM_BASE_URL"),
	}
	return provider, opts
}


// newClient builds a chat client from the settings in the environment.
func newClient() (llm.Client, error) {
	provider, opts := llmSettings()

	// The default of five retries with a two second pause that doubles
	// each time suits a busy cloud service, but makes a mistyped address
	// take a minute to report. Two short retries still ride out a
	// momentary failure.
	opts.Retry = llm.RetryConfig{
		MaxRetries:     2,
		InitialBackoff: 500 * time.Millisecond,
	}

	client, err := llm.NewClient(provider, opts)
	if err != nil {
		return nil, fmt.Errorf("creating the %s client failed: %w", provider, err)
	}
	return client, nil
}


// connect opens a connection with the settings from the environment.
func connect(ctx context.Context) (*pgx.Conn, error) {
	conn, err := pgx.Connect(ctx, connString())
	if err != nil {
		return nil, fmt.Errorf("connection failed: %w", err)
	}
	return conn, nil
}


// countTypesTool describes the one thing the model may ask for. The
// model sees only this name, this description, and this JSON Schema; it
// never sees the SQL that the program runs, and it cannot write any.
var countTypesTool = llm.Tool{
	Name: "count_types",
	Description: "Counts the data types in the PostgreSQL database " +
		"that have the given name.",
	InputSchema: json.RawMessage(`{
		"type": "object",
		"properties": {
			"name": {
				"type": "string",
				"description": "The name of a data type, such as int4."
			}
		},
		"required": ["name"]
	}`),
}


// typeNamePattern limits the argument to the characters that appear in
// built-in type names, which rejects anything odd the model sends.
var typeNamePattern = regexp.MustCompile(`^[A-Za-z0-9_]{1,63}$`)

// countTypes runs the tool for the model, and returns the type name that
// the model asked about with the count as text. The model controls only
// the value of $1; the SQL text is fixed, and pgx sends the value
// separately.
func countTypes(ctx context.Context, conn *pgx.Conn, call *llm.ToolUse) (string, string, error) {
	if call.Name != countTypesTool.Name {
		return "", "", fmt.Errorf("the model called an unknown tool: %q", call.Name)
	}

	// A small model sometimes sends malformed or incomplete arguments,
	// so check them before they reach the database.
	var args struct {
		TypeName string `json:"name"`
	}
	if err := json.Unmarshal(call.Input, &args); err != nil {
		return "", "", fmt.Errorf("the model sent unusable arguments %s: %w", call.Input, err)
	}
	if !typeNamePattern.MatchString(args.TypeName) {
		return "", "", fmt.Errorf("the model sent an invalid type name %q in %s", args.TypeName, call.Input)
	}

	var count int64
	err := conn.QueryRow(ctx,
		"SELECT count(*) FROM pg_catalog.pg_type WHERE typname = $1",
		args.TypeName,
	).Scan(&count)
	if err != nil {
		return "", "", fmt.Errorf("query failed: %w", err)
	}
	return args.TypeName, fmt.Sprintf("%d", count), nil
}


// answerWithTool asks the question, runs the tool that the model calls,
// and returns the type name from the tool call with the model's final
// answer.
func answerWithTool(ctx context.Context, client llm.Client, conn *pgx.Conn, question string) (string, string, error) {
	messages := []llm.Message{llm.UserText(question)}
	tools := []llm.Tool{countTypesTool}

	// Force the first reply to be a call to count_types. Providers with a
	// native tool choice setting receive it; Ollama has none, so the check
	// below is what guarantees that a tool was called.
	first, err := client.Chat(ctx, llm.ChatRequest{
		Messages: messages,
		Tools:    tools,
		ToolChoice: &llm.ToolChoice{
			Mode: llm.ToolChoiceSpecific,
			Name: countTypesTool.Name,
		},
	})
	if err != nil {
		return "", "", fmt.Errorf("first request failed: %w", err)
	}

	var call *llm.ToolUse
	for _, block := range first.Content {
		if block.Type == llm.BlockToolUse {
			call = block.ToolUse
			break
		}
	}
	if call == nil {
		return "", "", errors.New("the model did not call the tool")
	}

	name, result, err := countTypes(ctx, conn, call)
	if err != nil {
		return "", "", err
	}

	// Send the whole conversation back: the question, the model's own
	// tool call, and the result, which refers to the call by its ID.
	messages = append(messages,
		llm.Message{Role: llm.RoleAssistant, Content: first.Content},
		llm.ToolResultMessage(call.ID, result, false),
	)

	// Leave the tools out of this request, so that the model has nothing
	// to call and can only answer. ToolChoiceNone would not do the same
	// job: Ollama ignores ToolChoice, and Anthropic treats "none" as
	// "auto".
	final, err := client.Chat(ctx, llm.ChatRequest{Messages: messages})
	if err != nil {
		return "", "", fmt.Errorf("second request failed: %w", err)
	}

	var text strings.Builder
	for _, block := range final.Content {
		if block.Type == llm.BlockText {
			text.WriteString(block.Text)
		}
	}
	answer := strings.TrimSpace(text.String())
	if answer == "" {
		return "", "", errors.New("the model gave no final answer")
	}
	return name, answer, nil
}


// run connects, asks the question, and prints the result, returning any
// error to the caller.
func run(ctx context.Context) error {
	conn, err := connect(ctx)
	if err != nil {
		return err
	}
	// The deferred call closes the connection when run() returns, whether
	// or not an error occurred.
	defer conn.Close(ctx)

	client, err := newClient()
	if err != nil {
		return err
	}

	name, answer, err := answerWithTool(ctx, client, conn,
		"How many data types named int4 are there in the database?")
	if err != nil {
		return err
	}

	fmt.Printf("Tool call: count_types(%s)\n", name)
	fmt.Printf("Answer: %s\n", answer)
	return nil
}

// main reports any error returned by run() and exits with a non-zero
// status. Keeping the work in run() means that deferred cleanup always
// happens before the program exits.
func main() {
	if err := run(context.Background()); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
}


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
