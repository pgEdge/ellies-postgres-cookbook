# Sending a Chat Request

This recipe shows how a Go program sends a chat request to a large language
model with the
[pgEdge Go LLM Library](https://github.com/pgEdge/pgedge-go-llm-lib). The
library gives Anthropic, OpenAI, Gemini, Ollama, Voyage, and TypeSafe the
same interface, so the program chooses its provider from the environment
and the rest of the code stays the same. By default the example talks to a
local [Ollama](https://ollama.com) server, which needs no account and no
API key.

The example sends a system message and a user message, and then prints the
text of the reply with the number of tokens that the request used. A
language model produces different text on each run, so the output varies;
the output has the following shape:

```text
Provider: ollama
Model: qwen2.5:1.5b
Reply:
A primary key is a column, or set of columns, that uniquely identifies
each row in a table.
Tokens: 32 prompt, 26 completion
```

## Preparing the Ingredients

The example needs Go and the library, which the `go.mod` file pins at
version 0.6.0. The following snippet shows the dependency declaration from
the example project:

```text
--8<-- "recipes/go_llm_lib/chat_request/go/go.mod:deps"
```

To run the example against a local model, install Ollama, and then pull the
chat model that the example uses by default. The following commands pull
the model and confirm that the server is listening on its default port:

```bash
ollama pull qwen2.5:1.5b
curl http://localhost:11434/api/tags
```

## Importing the Library

The program imports the `llm` package, which defines the client interface
and the request types. The blank import of the `llm/all` package registers
all six providers, so that `llm.NewClient()` can find the provider by name;
a program that uses only one provider can import that provider's package
under `llm/provider` instead, to keep the binary small. The following
snippet shows the imports:

```go
--8<-- "recipes/go_llm_lib/chat_request/go/main.go:imports"
```

## Configuring the Provider

The program reads its settings from environment variables, so the same
code runs against a local model or a cloud service. Like the other recipes
in this cookbook, the program treats an empty variable as unset, and uses
the default instead. The following table describes the environment
variables that this example reads:

| Variable       | Default        | Description                         |
|----------------|----------------|-------------------------------------|
| `LLM_PROVIDER` | `ollama`       | The provider, such as `openai`.     |
| `LLM_MODEL`    | `qwen2.5:1.5b` | The name of the chat model.         |
| `LLM_API_KEY`  | None           | The API key, if the provider needs one. |
| `LLM_BASE_URL` | None           | Overrides the provider endpoint.    |

When `LLM_BASE_URL` is unset or empty, the program passes no base URL, and
the library uses the default endpoint of the chosen provider, which is
`http://localhost:11434` for Ollama. The following snippet shows how the
program reads the variables:

```go
--8<-- "recipes/go_llm_lib/chat_request/go/main.go:config"
```

## Switching Providers

Changing the provider needs no code change, only different values for the
variables. The following commands run the same program against OpenAI and
against Anthropic; replace the placeholders with a model that your account
can use and your API key:

```bash
LLM_PROVIDER=openai LLM_MODEL=<model> LLM_API_KEY=<key> go run .
LLM_PROVIDER=anthropic LLM_MODEL=<model> LLM_API_KEY=<key> go run .
```

Set `LLM_BASE_URL` to use a server that speaks the same protocol as a
provider but lives elsewhere, such as a gateway in front of OpenAI or a
remote Ollama server.

!!! note

    Production applications should not store API keys in source code or
    shell history. Use a secrets manager, or at least keep the key in an
    environment variable that the deployment sets.

## Creating the Client

The program passes the provider name and an `llm.Options` value to
`llm.NewClient()`, which returns a client that implements the `llm.Client`
interface. The options set the model, the API key, and the base URL. They
also cap the reply at 64 tokens, which keeps the example fast, and limit
the retry policy to two retries, so that the program gives up quickly if
the server is unreachable. The following snippet shows how the program
creates the client:

```go
--8<-- "recipes/go_llm_lib/chat_request/go/main.go:client"
```

## Sending the Request

The program calls `Chat()` with an `llm.ChatRequest`. The `SystemPrompt`
field sets the behaviour of the model, and the `Messages` field holds the
conversation, built here with the `llm.UserText()` helper. The call
returns once the model has produced the whole reply. The following snippet
shows the request:

```go
--8<-- "recipes/go_llm_lib/chat_request/go/main.go:chat"
```

## Reading the Reply

A response holds a list of content blocks rather than a single string,
because a model can return text, tool calls, and other kinds of content in
the same reply. The program prints each block whose type is
`llm.BlockText`, and then prints the prompt and completion token counts
from the `Usage` field. The following snippet shows how the program reads
the response:

```go
--8<-- "recipes/go_llm_lib/chat_request/go/main.go:print"
```

## Handling Errors

The main part of the program builds the client, sends the request, and
prints the result. It returns any error to `main()`, which reports the
error on `stderr` and exits with a non-zero status. The following snippet
shows the main part of the program:

```go
--8<-- "recipes/go_llm_lib/chat_request/go/main.go:main"
```

## Running the Example

The complete project is available in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/go_llm_lib/chat_request).
With Ollama running, run the following command from the `go` project
directory:

```bash
go run .
```

## Viewing the Complete Program

The following snippet shows the complete program:

```go
--8<-- "recipes/go_llm_lib/chat_request/go/main.go"
```

## Next Steps

The following resources provide more information about the topics in this
recipe:

- The [Streaming a Response](streaming_response.md) recipe prints the reply
  as the model produces it.
- The [Handling Provider Errors and Retries](error_handling.md) recipe
  shows how to tell the failures of a provider apart.
- The
  [pgEdge Go LLM Library documentation](https://github.com/pgEdge/pgedge-go-llm-lib/tree/main/docs)
  describes every provider, option, and request type.
- The [Ollama library](https://ollama.com/library) lists the models that
  you can run locally.
