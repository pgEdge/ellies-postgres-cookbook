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
// The pgEdge Go LLM Library has no dependencies of its own.
require github.com/pgEdge/pgedge-go-llm-lib v0.6.0

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
import (
	"context"
	"fmt"
	"os"
	"strings"
	"time"

	"github.com/pgEdge/pgedge-go-llm-lib/llm"
	// Importing the llm/all package registers every provider; import
	// individual packages under llm/provider to keep the binary small.
	_ "github.com/pgEdge/pgedge-go-llm-lib/llm/all"
)

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
// envOr returns the value of an environment variable, or a fallback if
// the variable is unset or empty.
func envOr(name, fallback string) string {
	if value := os.Getenv(name); value != "" {
		return value
	}
	return fallback
}

// config holds the settings that choose the provider and the model.
type config struct {
	provider string
	model    string
	apiKey   string
	baseURL  string
}

// loadConfig reads the LLM_* environment variables. An empty
// LLM_BASE_URL leaves the field empty, so the library uses the default
// endpoint of the chosen provider.
func loadConfig() config {
	return config{
		provider: envOr("LLM_PROVIDER", "ollama"),
		model:    envOr("LLM_MODEL", "qwen2.5:1.5b"),
		apiKey:   os.Getenv("LLM_API_KEY"),
		baseURL:  os.Getenv("LLM_BASE_URL"),
	}
}

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
// newClient builds a client for the provider named in the configuration.
// Every provider implements the same llm.Client interface, so the rest
// of the program does not depend on which one is in use.
func newClient(cfg config) (llm.Client, error) {
	client, err := llm.NewClient(cfg.provider, llm.Options{
		APIKey:  cfg.apiKey,
		Model:   cfg.model,
		BaseURL: cfg.baseURL,
		// Cap the length of the reply; this also keeps the example fast.
		MaxTokens: llm.Int(64),
		// Retry transient failures twice, which gives up sooner than the
		// default of five retries with a two second initial backoff.
		Retry: llm.RetryConfig{
			MaxRetries:     2,
			InitialBackoff: 200 * time.Millisecond,
		},
	})
	if err != nil {
		return nil, fmt.Errorf("creating the client failed: %w", err)
	}
	return client, nil
}

```

## Sending the Request

The program calls `Chat()` with an `llm.ChatRequest`. The `SystemPrompt`
field sets the behaviour of the model, and the `Messages` field holds the
conversation, built here with the `llm.UserText()` helper. The call
returns once the model has produced the whole reply. The following snippet
shows the request:

```go
// ask sends a system message and a user message, and returns the
// response, which holds the content blocks and the token usage.
func ask(ctx context.Context, client llm.Client) (*llm.ChatResponse, error) {
	resp, err := client.Chat(ctx, llm.ChatRequest{
		// The system prompt sets the behaviour of the model, and the
		// messages hold the conversation so far.
		SystemPrompt: "You are a concise assistant for PostgreSQL users.",
		Messages: []llm.Message{
			llm.UserText("In one sentence, what is a primary key?"),
		},
	})
	if err != nil {
		return nil, fmt.Errorf("chat request failed: %w", err)
	}
	return resp, nil
}

```

## Reading the Reply

A response holds a list of content blocks rather than a single string,
because a model can return text, tool calls, and other kinds of content in
the same reply. The program prints each block whose type is
`llm.BlockText`, and then prints the prompt and completion token counts
from the `Usage` field. The following snippet shows how the program reads
the response:

```go
// printResponse prints the text blocks of the response, followed by the
// token usage that the provider reported.
func printResponse(resp *llm.ChatResponse) {
	fmt.Println("Reply:")
	for _, block := range resp.Content {
		// A response can hold other kinds of block (tool calls, for
		// example), so print only the text.
		if block.Type == llm.BlockText {
			fmt.Println(strings.TrimSpace(block.Text))
		}
	}
	fmt.Printf("Tokens: %d prompt, %d completion\n",
		resp.Usage.PromptTokens, resp.Usage.CompletionTokens)
}

```

## Handling Errors

The main part of the program builds the client, sends the request, and
prints the result. It returns any error to `main()`, which reports the
error on `stderr` and exits with a non-zero status. The following snippet
shows the main part of the program:

```go
// run builds the client, sends the request, and prints the response,
// returning any error to the caller.
func run(ctx context.Context) error {
	cfg := loadConfig()
	client, err := newClient(cfg)
	if err != nil {
		return err
	}

	fmt.Printf("Provider: %s\n", client.Provider())
	fmt.Printf("Model: %s\n", client.Model())

	resp, err := ask(ctx, client)
	if err != nil {
		return err
	}
	printResponse(resp)
	return nil
}

// main reports any error returned by run() and exits with a non-zero
// status.
func main() {
	if err := run(context.Background()); err != nil {
		fmt.Fprintf(os.Stderr, "LLM error: %v\n", err)
		os.Exit(1)
	}
}

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
// Ellie's Postgres Cookbook
// Sending a chat request with the pgEdge Go LLM Library.
//
// Copyright (c) 2026, pgEdge, Inc.
// This code is released under the PostgreSQL License.

package main

import (
	"context"
	"fmt"
	"os"
	"strings"
	"time"

	"github.com/pgEdge/pgedge-go-llm-lib/llm"
	// Importing the llm/all package registers every provider; import
	// individual packages under llm/provider to keep the binary small.
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

// config holds the settings that choose the provider and the model.
type config struct {
	provider string
	model    string
	apiKey   string
	baseURL  string
}

// loadConfig reads the LLM_* environment variables. An empty
// LLM_BASE_URL leaves the field empty, so the library uses the default
// endpoint of the chosen provider.
func loadConfig() config {
	return config{
		provider: envOr("LLM_PROVIDER", "ollama"),
		model:    envOr("LLM_MODEL", "qwen2.5:1.5b"),
		apiKey:   os.Getenv("LLM_API_KEY"),
		baseURL:  os.Getenv("LLM_BASE_URL"),
	}
}


// newClient builds a client for the provider named in the configuration.
// Every provider implements the same llm.Client interface, so the rest
// of the program does not depend on which one is in use.
func newClient(cfg config) (llm.Client, error) {
	client, err := llm.NewClient(cfg.provider, llm.Options{
		APIKey:  cfg.apiKey,
		Model:   cfg.model,
		BaseURL: cfg.baseURL,
		// Cap the length of the reply; this also keeps the example fast.
		MaxTokens: llm.Int(64),
		// Retry transient failures twice, which gives up sooner than the
		// default of five retries with a two second initial backoff.
		Retry: llm.RetryConfig{
			MaxRetries:     2,
			InitialBackoff: 200 * time.Millisecond,
		},
	})
	if err != nil {
		return nil, fmt.Errorf("creating the client failed: %w", err)
	}
	return client, nil
}


// ask sends a system message and a user message, and returns the
// response, which holds the content blocks and the token usage.
func ask(ctx context.Context, client llm.Client) (*llm.ChatResponse, error) {
	resp, err := client.Chat(ctx, llm.ChatRequest{
		// The system prompt sets the behaviour of the model, and the
		// messages hold the conversation so far.
		SystemPrompt: "You are a concise assistant for PostgreSQL users.",
		Messages: []llm.Message{
			llm.UserText("In one sentence, what is a primary key?"),
		},
	})
	if err != nil {
		return nil, fmt.Errorf("chat request failed: %w", err)
	}
	return resp, nil
}


// printResponse prints the text blocks of the response, followed by the
// token usage that the provider reported.
func printResponse(resp *llm.ChatResponse) {
	fmt.Println("Reply:")
	for _, block := range resp.Content {
		// A response can hold other kinds of block (tool calls, for
		// example), so print only the text.
		if block.Type == llm.BlockText {
			fmt.Println(strings.TrimSpace(block.Text))
		}
	}
	fmt.Printf("Tokens: %d prompt, %d completion\n",
		resp.Usage.PromptTokens, resp.Usage.CompletionTokens)
}


// run builds the client, sends the request, and prints the response,
// returning any error to the caller.
func run(ctx context.Context) error {
	cfg := loadConfig()
	client, err := newClient(cfg)
	if err != nil {
		return err
	}

	fmt.Printf("Provider: %s\n", client.Provider())
	fmt.Printf("Model: %s\n", client.Model())

	resp, err := ask(ctx, client)
	if err != nil {
		return err
	}
	printResponse(resp)
	return nil
}

// main reports any error returned by run() and exits with a non-zero
// status.
func main() {
	if err := run(context.Background()); err != nil {
		fmt.Fprintf(os.Stderr, "LLM error: %v\n", err)
		os.Exit(1)
	}
}


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
