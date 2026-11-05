# Streaming a Response

This recipe shows how a Go program prints a language model's reply as the
model produces it, using the
[pgEdge Go LLM Library](https://github.com/pgEdge/pgedge-go-llm-lib). A
model can take several seconds to finish a long reply, and a streamed
reply lets an application show the first words straight away instead of
waiting for the last. The example builds on the
[Sending a Chat Request](chat_request.md) recipe, which explains the
environment variables and how to run the examples against a local
[Ollama](https://ollama.com) server.

The example prints each piece of text as it arrives, and then prints the
token usage and the number of text chunks. A language model produces
different text on each run, so the output varies; the output has the
following shape:

```text
Provider: ollama
Model: qwen2.5:1.5b
Reply:
A primary key uniquely identifies each record in a database table.
Tokens: 32 prompt, 15 completion
Chunks: 14
```

## Preparing the Ingredients

The example needs Go and the library, which the `go.mod` file pins at
version 0.6.0. The example reads the same `LLM_PROVIDER`, `LLM_MODEL`,
`LLM_API_KEY`, and `LLM_BASE_URL` variables as the chat request recipe, and
treats an empty variable as unset. The following snippet shows the
dependency declaration from the example project:

```text
// The pgEdge Go LLM Library has no dependencies of its own.
require github.com/pgEdge/pgedge-go-llm-lib v0.6.0

```

## Importing the Library

The program imports the `llm` package for the client and the request
types, and the blank import of `llm/all` registers every provider. The
program also imports `errors` and `io`, because a stream signals its end
with `io.EOF`. The following snippet shows the imports:

```go
import (
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"time"

	"github.com/pgEdge/pgedge-go-llm-lib/llm"
	// Importing the llm/all package registers every provider; import
	// individual packages under llm/provider to keep the binary small.
	_ "github.com/pgEdge/pgedge-go-llm-lib/llm/all"
)

```

## Configuring the Provider

The program reads the provider, model, API key, and base URL from the
environment. When `LLM_BASE_URL` is unset or empty, the program passes no
base URL, and the library uses the default endpoint of the chosen
provider. The following snippet shows how the program reads the variables:

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

## Creating the Client

The program creates the client with `llm.NewClient()`, which returns the
same `llm.Client` interface for every provider. The options cap the reply
at 64 tokens and limit the retry policy to two retries, so that the
example runs quickly. The following snippet shows how the program creates
the client:

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

## Opening the Stream

The program calls `ChatStream()` instead of `Chat()`, with the same
`llm.ChatRequest`. The call returns as soon as the provider starts to
respond, with a `*llm.Stream` that delivers the reply in pieces. A failure
to reach the provider appears here, as the error from `ChatStream()`. The
following snippet shows how the program opens the stream:

```go
// openStream sends the request and returns a stream, which yields chunks
// while the model is still generating its reply.
func openStream(ctx context.Context, client llm.Client) (*llm.Stream, error) {
	stream, err := client.ChatStream(ctx, llm.ChatRequest{
		SystemPrompt: "You are a concise assistant for PostgreSQL users.",
		Messages: []llm.Message{
			llm.UserText("In one sentence, what is a primary key?"),
		},
	})
	if err != nil {
		return nil, fmt.Errorf("chat request failed: %w", err)
	}
	return stream, nil
}

```

## Reading the Chunks

The program calls `Recv()` in a loop. Each call blocks until the next
chunk arrives, and returns `io.EOF` when the stream has ended; any other
error means that the stream failed part-way through. The `Type` field of
a chunk says which of its other fields holds data. A chunk of type
`llm.ChunkText` carries a piece of the reply in `Text`, which the program
prints at once without a newline. The final chunk has the type
`llm.ChunkDone`, and its `Usage` field always holds the token counts for
the request. The following snippet shows the loop:

```go
// printStream prints each text chunk as it arrives, and returns the
// token usage that the final chunk carries, with the number of text
// chunks that arrived.
func printStream(stream *llm.Stream) (llm.TokenUsage, int, error) {
	var usage llm.TokenUsage
	chunks := 0
	done := false

	fmt.Println("Reply:")
	for {
		// Recv blocks until the next chunk arrives. It returns io.EOF
		// once the stream has ended, and any other error if the stream
		// fails part-way through.
		chunk, err := stream.Recv()
		if errors.Is(err, io.EOF) {
			break
		}
		if err != nil {
			return usage, chunks, fmt.Errorf("reading the stream failed: %w", err)
		}

		switch chunk.Type {
		case llm.ChunkText:
			fmt.Print(chunk.Text)
			chunks++
		case llm.ChunkDone:
			// The final chunk carries the token usage.
			done = true
			if chunk.Usage != nil {
				usage = *chunk.Usage
			}
		}
	}
	fmt.Println()

	// A stream that ends without a final chunk was cut short, even
	// though it reported no error.
	if !done {
		return usage, chunks, errors.New("the stream ended before the final chunk")
	}
	return usage, chunks, nil
}

```

A stream can fail in two ways after it opens. The first is an error from
`Recv()`, which the program returns with the text that it has already
printed. The second is a stream that reaches `io.EOF` without ever sending
the final chunk, which some providers do when the connection closes
cleanly part-way through a reply; the program tracks whether the final
chunk arrived, and returns an error if it did not, rather than reporting
a truncated reply as a success.

A stream can also carry chunks that describe tool calls and the reasoning
of a model. This program ignores them, because the request defines no
tools and does not ask for reasoning.

!!! tip

    If a program needs only the complete reply and has no use for the
    pieces, call the `Collect()` method of the stream, which reads the
    whole stream and returns an `llm.ChatResponse`.

## Handling Errors

The main part of the program builds the client, opens the stream, prints
the chunks, and then prints the usage. It returns any error to `main()`,
which reports the error on `stderr` and exits with a non-zero status. The
following snippet shows the main part of the program:

```go
// run builds the client, streams the reply, and prints the token usage,
// returning any error to the caller.
func run(ctx context.Context) error {
	cfg := loadConfig()
	client, err := newClient(cfg)
	if err != nil {
		return err
	}

	fmt.Printf("Provider: %s\n", client.Provider())
	fmt.Printf("Model: %s\n", client.Model())

	stream, err := openStream(ctx, client)
	if err != nil {
		return err
	}
	usage, chunks, err := printStream(stream)
	if err != nil {
		return err
	}

	fmt.Printf("Tokens: %d prompt, %d completion\n",
		usage.PromptTokens, usage.CompletionTokens)
	fmt.Printf("Chunks: %d\n", chunks)
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
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/go_llm_lib/streaming_response).
With Ollama running, run the following command from the `go` project
directory:

```bash
go run .
```

## Viewing the Complete Program

The following snippet shows the complete program:

```go
// Ellie's Postgres Cookbook
// Streaming a chat response with the pgEdge Go LLM Library.
//
// Copyright (c) 2026, pgEdge, Inc.
// This code is released under the PostgreSQL License.

package main

import (
	"context"
	"errors"
	"fmt"
	"io"
	"os"
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


// openStream sends the request and returns a stream, which yields chunks
// while the model is still generating its reply.
func openStream(ctx context.Context, client llm.Client) (*llm.Stream, error) {
	stream, err := client.ChatStream(ctx, llm.ChatRequest{
		SystemPrompt: "You are a concise assistant for PostgreSQL users.",
		Messages: []llm.Message{
			llm.UserText("In one sentence, what is a primary key?"),
		},
	})
	if err != nil {
		return nil, fmt.Errorf("chat request failed: %w", err)
	}
	return stream, nil
}


// printStream prints each text chunk as it arrives, and returns the
// token usage that the final chunk carries, with the number of text
// chunks that arrived.
func printStream(stream *llm.Stream) (llm.TokenUsage, int, error) {
	var usage llm.TokenUsage
	chunks := 0
	done := false

	fmt.Println("Reply:")
	for {
		// Recv blocks until the next chunk arrives. It returns io.EOF
		// once the stream has ended, and any other error if the stream
		// fails part-way through.
		chunk, err := stream.Recv()
		if errors.Is(err, io.EOF) {
			break
		}
		if err != nil {
			return usage, chunks, fmt.Errorf("reading the stream failed: %w", err)
		}

		switch chunk.Type {
		case llm.ChunkText:
			fmt.Print(chunk.Text)
			chunks++
		case llm.ChunkDone:
			// The final chunk carries the token usage.
			done = true
			if chunk.Usage != nil {
				usage = *chunk.Usage
			}
		}
	}
	fmt.Println()

	// A stream that ends without a final chunk was cut short, even
	// though it reported no error.
	if !done {
		return usage, chunks, errors.New("the stream ended before the final chunk")
	}
	return usage, chunks, nil
}


// run builds the client, streams the reply, and prints the token usage,
// returning any error to the caller.
func run(ctx context.Context) error {
	cfg := loadConfig()
	client, err := newClient(cfg)
	if err != nil {
		return err
	}

	fmt.Printf("Provider: %s\n", client.Provider())
	fmt.Printf("Model: %s\n", client.Model())

	stream, err := openStream(ctx, client)
	if err != nil {
		return err
	}
	usage, chunks, err := printStream(stream)
	if err != nil {
		return err
	}

	fmt.Printf("Tokens: %d prompt, %d completion\n",
		usage.PromptTokens, usage.CompletionTokens)
	fmt.Printf("Chunks: %d\n", chunks)
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

- The [Sending a Chat Request](chat_request.md) recipe explains the
  environment variables and how to switch providers.
- The [Handling Provider Errors and Retries](error_handling.md) recipe
  shows how to tell the failures of a provider apart.
- The
  [pgEdge Go LLM Library documentation](https://github.com/pgEdge/pgedge-go-llm-lib/tree/main/docs)
  describes streaming, tool calls, and reasoning chunks in detail.
