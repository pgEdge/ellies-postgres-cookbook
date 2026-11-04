// Ellie's Postgres Cookbook
// Handling provider errors and retries with the pgEdge Go LLM Library.
//
// Copyright (c) 2026, pgEdge, Inc.
// This code is released under the PostgreSQL License.

package main

// --8<-- [start:imports]
import (
	"context"
	"errors"
	"fmt"
	"net"
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
// The retry policy and the retry hook are parameters, so that the caller
// can choose how patient the client is and watch the retries happen.
func newClient(cfg config, retry llm.RetryConfig,
	onRetry func(llm.RetryEvent)) (llm.Client, error) {
	client, err := llm.NewClient(cfg.provider, llm.Options{
		APIKey:    cfg.apiKey,
		Model:     cfg.model,
		BaseURL:   cfg.baseURL,
		MaxTokens: llm.Int(16),
		Retry:     retry,
		OnRetry:   onRetry,
	})
	if err != nil {
		return nil, fmt.Errorf("creating the client failed: %w", err)
	}
	return client, nil
}

// --8<-- [end:client]

// --8<-- [start:classify]
// classify describes an error from the library in terms of the sentinel
// errors, which stay the same whichever provider returned the failure.
func classify(err error) string {
	// errors.Is looks through the *llm.ProviderError and any wrapping to
	// find the sentinel error that the library chose as its cause.
	switch {
	case errors.Is(err, llm.ErrAuthentication):
		return "authentication failed"
	case errors.Is(err, llm.ErrRateLimit):
		return "rate limit exceeded"
	case errors.Is(err, llm.ErrInvalidRequest):
		return "invalid request"
	case errors.Is(err, llm.ErrNotSupported):
		return "operation not supported"
	case errors.Is(err, llm.ErrProviderError):
		return "provider error"
	}

	// A failure to reach the server at all never gets as far as a
	// provider response, so it is a network error instead.
	var netErr net.Error
	if errors.As(err, &netErr) {
		return "network error"
	}
	return "unknown error"
}

// describe prints the category of an error, and the HTTP status code
// when the provider sent a response at all.
func describe(label string, err error) {
	fmt.Printf("%s: %s\n", label, classify(err))

	// errors.As extracts the *llm.ProviderError, which holds the details
	// that the sentinel errors leave out.
	var perr *llm.ProviderError
	if errors.As(err, &perr) {
		fmt.Printf("%s status: %d\n", label, perr.StatusCode)
	}
}

// --8<-- [end:classify]

// --8<-- [start:missing]
// missingModel asks for a model that does not exist. The server answers
// with an HTTP error, which the library returns as a *llm.ProviderError.
func missingModel(ctx context.Context, cfg config) error {
	cfg.model = "no-such-model"
	client, err := newClient(cfg, llm.RetryConfig{Disabled: true}, nil)
	if err != nil {
		return err
	}

	_, err = client.Chat(ctx, llm.ChatRequest{
		Messages: []llm.Message{llm.UserText("Hello")},
	})
	if err == nil {
		return errors.New("the request for a missing model succeeded")
	}
	// Anything other than a response from the provider means that the
	// server is unreachable, which this example cannot go on without.
	var perr *llm.ProviderError
	if !errors.As(err, &perr) {
		return fmt.Errorf("the server did not respond: %w", err)
	}

	describe("Missing model", err)
	return nil
}

// --8<-- [end:missing]

// --8<-- [start:retry]
// unreachableServer sends a request to an address with nothing listening
// on it. A network failure is transient, so the library retries it; the
// hook runs before each wait, and the final error arrives once the
// retries are used up.
func unreachableServer(ctx context.Context, cfg config) error {
	// Point the client at a closed port, whatever the environment says.
	cfg.baseURL = "http://127.0.0.1:1"
	retry := llm.RetryConfig{
		MaxRetries:     2,
		InitialBackoff: 50 * time.Millisecond,
		MaxBackoff:     100 * time.Millisecond,
	}

	retries := 0
	client, err := newClient(cfg, retry, func(e llm.RetryEvent) {
		retries++
		// The status code is zero because no response ever arrived; the
		// Err field holds the network error instead.
		fmt.Printf("Retry %d: status %d, network error: %t\n",
			e.Attempt, e.StatusCode, e.Err != nil)
	})
	if err != nil {
		return err
	}

	_, err = client.Chat(ctx, llm.ChatRequest{
		Messages: []llm.Message{llm.UserText("Hello")},
	})
	if err == nil {
		return errors.New("the request to a closed port succeeded")
	}

	describe("Unreachable server", err)
	fmt.Printf("Retries: %d\n", retries)
	return nil
}

// --8<-- [end:retry]

// --8<-- [start:main]
// run demonstrates each kind of failure in turn, returning any error
// that the demonstrations themselves cannot handle.
func run(ctx context.Context) error {
	cfg := loadConfig()
	if err := missingModel(ctx, cfg); err != nil {
		return err
	}
	return unreachableServer(ctx, cfg)
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
