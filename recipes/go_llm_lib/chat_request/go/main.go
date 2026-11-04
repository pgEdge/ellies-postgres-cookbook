// Ellie's Postgres Cookbook
// Sending a chat request with the pgEdge Go LLM Library.
//
// Copyright (c) 2026, pgEdge, Inc.
// This code is released under the PostgreSQL License.

package main

// --8<-- [start:imports]
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

// --8<-- [start:chat]
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

// --8<-- [end:chat]

// --8<-- [start:print]
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

// --8<-- [end:print]

// --8<-- [start:main]
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

// --8<-- [end:main]
