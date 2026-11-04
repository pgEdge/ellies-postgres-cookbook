// Ellie's Postgres Cookbook
// Streaming a chat response with the pgEdge Go LLM Library.
//
// Copyright (c) 2026, pgEdge, Inc.
// This code is released under the PostgreSQL License.

package main

// --8<-- [start:imports]
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

// --8<-- [end:imports]

// --8<-- [start:config]
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

// --8<-- [end:config]

// --8<-- [start:client]
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

// --8<-- [end:client]

// --8<-- [start:stream]
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

// --8<-- [end:stream]

// --8<-- [start:read]
// printStream prints each text chunk as it arrives, and returns the
// token usage that the final chunk carries, with the number of text
// chunks that arrived.
func printStream(stream *llm.Stream) (llm.TokenUsage, int, error) {
	var usage llm.TokenUsage
	chunks := 0

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
			// The final chunk always carries the token usage.
			usage = *chunk.Usage
		}
	}
	fmt.Println()
	return usage, chunks, nil
}

// --8<-- [end:read]

// --8<-- [start:main]
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

// --8<-- [end:main]
